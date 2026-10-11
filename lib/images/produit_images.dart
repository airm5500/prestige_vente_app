// lib/images/produit_images.dart
// B2 — Images des produits, venant du serveur Prestige (API EXISTANTE, aucune évolution serveur) :
//   GET  /produit-images/{lgFAMILLEID}                         → {success, data:[{id, principale, vignette…}], modifiable}
//   GET  /produit-images/{f}/{imageId}/fichier?taille=vignette  → image (JPEG ≤ 240 px ; WEBP : pas de vignette)
//   POST /produit-images/{f} (multipart « image », « principale ») → {success, id | message} (droit P_PRODUIT_IMAGES_MAJ)
// Session cookie de l'appli (même connexion). Pas d'ETag ni de liste différentielle côté serveur :
// - la liste d'un produit est demandée À LA DEMANDE (cartes affichées), au plus 3 à la fois ;
// - cache disque (500 Mo par défaut, réglable, éviction des moins récemment vues) + cache NÉGATIF daté
//   (« pas d'image », revérifié après 24 h) ; une image déjà en cache n'est jamais retéléchargée
//   (fichier nommé par l'identifiant de l'image : une nouvelle image principale = nouvel identifiant) ;
// - hors ligne : images du cache seulement, aucune requête ;
// - serveur sans l'API (404 sur la route) : pictogrammes seulement, plus aucune requête (revérifié après 30 min).
// L'API « v1/mobile » (jeton Bearer, KEY_MOBILE_ACTIF) n'est PAS utilisée : l'appli fonctionne en session cookie.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/images/images_reglages.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

/// Image d'un produit dans la liste du serveur.
class ImageProduitInfo {
  final String id;
  final bool principale;

  /// Une vignette (JPEG ≤ 240 px) existe ; sinon (WEBP) seule l'image normale est disponible.
  final bool vignette;
  const ImageProduitInfo({required this.id, this.principale = false, this.vignette = true});
}

class ImagesListe {
  final List<ImageProduitInfo> images;

  /// L'utilisateur connecté peut ajouter / modifier les images (droit P_PRODUIT_IMAGES_MAJ).
  final bool modifiable;
  const ImagesListe(this.images, {this.modifiable = false});

  ImageProduitInfo? get principale => images.where((i) => i.principale).firstOrNull ?? images.firstOrNull;
}

/// Accès serveur (remplaçable dans les tests).
abstract class ProduitImagesApi {
  /// Liste des images ; VenteOk(null) : route absente (serveur sans l'API images).
  Future<VenteResult<ImagesListe?>> lister(String familleId);
  Future<VenteResult<Uint8List>> fichier(String familleId, String imageId, {bool vignette = true});

  /// Ajout (principale = remplace et supprime l'ancienne principale) ; identifiant de la nouvelle image.
  Future<VenteResult<String>> ajouter(String familleId, Uint8List octets, {String nom = 'photo.jpg', bool principale = true});
}

/// Lecture de la liste du serveur.
VenteResult<ImagesListe?> imagesListeDepuis(int status, Object? body) {
  if (status == 404) return const VenteOk(null);
  if (status == 401 || status == 403) return const VenteFailed('Session expirée : reconnectez-vous.');
  if (status != 200) return VenteFailed('Images : erreur du serveur (code $status).');
  Object? b = body;
  if (b is String) {
    final t = b.trim();
    if (t.startsWith('<')) return const VenteOk(null); // page HTML (ancien serveur / route inconnue)
    try {
      b = jsonDecode(t);
    } catch (_) {
      return const VenteFailed('Images : réponse illisible.');
    }
  }
  if (b is! Map) return const VenteFailed('Images : réponse illisible.');
  if (b['success'] != true) {
    final m = '${b['message'] ?? b['msg'] ?? ''}';
    return VenteRefused(m.isEmpty ? 'Images refusées par le serveur.' : m);
  }
  final data = b['data'];
  final out = <ImageProduitInfo>[];
  if (data is List) {
    for (final e in data) {
      if (e is! Map || '${e['id'] ?? ''}'.isEmpty) continue;
      final v = '${e['vignette'] ?? ''}';
      out.add(ImageProduitInfo(id: '${e['id']}', principale: e['principale'] == true, vignette: v.contains('taille=vignette')));
    }
  }
  return VenteOk(ImagesListe(out, modifiable: b['modifiable'] == true));
}

/// Réponse de l'ajout (text/html contenant du JSON).
VenteResult<String> ajoutDepuis(int status, Object? body) {
  if (status == 401 || status == 403) return const VenteFailed('Session expirée : reconnectez-vous.');
  if (status == 404) return const VenteRefused('Ce serveur ne gère pas les images des produits.');
  if (status != 200) return VenteFailed('Envoi de la photo : erreur du serveur (code $status).');
  Object? b = body;
  if (b is String) {
    final m = RegExp(r'\{.*\}', dotAll: true).firstMatch(b);
    try {
      b = m == null ? null : jsonDecode(m.group(0)!);
    } catch (_) {
      b = null;
    }
  }
  if (b is! Map) return const VenteFailed('Envoi de la photo : réponse illisible.');
  if (b['success'] == true && '${b['id'] ?? ''}'.isNotEmpty) return VenteOk('${b['id']}');
  final msg = '${b['message'] ?? b['msg'] ?? ''}';
  return VenteRefused(msg.isEmpty ? 'Photo refusée par le serveur.' : msg);
}

class DioProduitImagesApi implements ProduitImagesApi {
  /// Adresse du serveur (…/api/v1).
  final String Function() serveur;
  Dio? _dio;
  DioProduitImagesApi(this.serveur);

  /// Client dédié (pas de journal des réponses binaires), même session que l'appli.
  Dio get dio {
    final d = _dio ??= (Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 20)))
      ..interceptors.add(CookieManager(DioClient.cookieJar)));
    d.options.baseUrl = serveur();
    return d;
  }

  String _e(String s) => Uri.encodeComponent(s);

  @override
  Future<VenteResult<ImagesListe?>> lister(String familleId) async {
    try {
      final r = await dio.get('/produit-images/${_e(familleId)}', options: Options(validateStatus: (_) => true));
      return imagesListeDepuis(r.statusCode ?? 0, r.data);
    } on DioException catch (e) {
      return VenteFailed('Images : serveur injoignable (${e.type.name}).');
    } catch (e) {
      return VenteFailed('Images : $e');
    }
  }

  @override
  Future<VenteResult<Uint8List>> fichier(String familleId, String imageId, {bool vignette = true}) async {
    try {
      final r = await dio.get<List<int>>('/produit-images/${_e(familleId)}/${_e(imageId)}/fichier',
          queryParameters: {'taille': vignette ? 'vignette' : 'normale'},
          options: Options(responseType: ResponseType.bytes, validateStatus: (_) => true));
      final code = r.statusCode ?? 0;
      if (code == 200 && r.data != null && r.data!.isNotEmpty) return VenteOk(Uint8List.fromList(r.data!));
      if (code == 404) return const VenteRefused('Image introuvable.');
      if (code == 401) return const VenteFailed('Session expirée : reconnectez-vous.');
      return VenteFailed('Image : erreur du serveur (code $code).');
    } on DioException catch (e) {
      return VenteFailed('Image : serveur injoignable (${e.type.name}).');
    }
  }

  @override
  Future<VenteResult<String>> ajouter(String familleId, Uint8List octets, {String nom = 'photo.jpg', bool principale = true}) async {
    try {
      final form = FormData.fromMap({
        'principale': principale ? 'true' : 'false',
        'image': MultipartFile.fromBytes(octets, filename: nom, contentType: DioMediaType('image', nom.endsWith('.png') ? 'png' : 'jpeg')),
      });
      final r = await dio.post('/produit-images/${_e(familleId)}',
          data: form, options: Options(responseType: ResponseType.plain, validateStatus: (_) => true, sendTimeout: const Duration(seconds: 60)));
      return ajoutDepuis(r.statusCode ?? 0, r.data);
    } on DioException catch (e) {
      return VenteFailed('Envoi de la photo impossible (${e.type.name}).');
    }
  }
}

/// Entrée du cache (index persistant).
class _Entree {
  /// null : le produit n'a pas d'image (cache négatif).
  final String? imageId;
  final String? fichier;
  final int taille;
  final DateTime verifie;
  DateTime vue;
  _Entree({this.imageId, this.fichier, this.taille = 0, required this.verifie, required this.vue});

  Map<String, dynamic> toJson() => {'i': imageId, 'f': fichier, 't': taille, 'v': verifie.millisecondsSinceEpoch, 'a': vue.millisecondsSinceEpoch};
  static _Entree fromJson(Map<String, dynamic> j) => _Entree(
        imageId: j['i'] as String?,
        fichier: j['f'] as String?,
        taille: (j['t'] as num?)?.toInt() ?? 0,
        verifie: DateTime.fromMillisecondsSinceEpoch((j['v'] as num?)?.toInt() ?? 0),
        vue: DateTime.fromMillisecondsSinceEpoch((j['a'] as num?)?.toInt() ?? 0),
      );
}

enum CapaciteImages { inconnue, oui, non }

/// Images des produits : cache disque + demandes limitées.
class ProduitImages extends ChangeNotifier {
  ProduitImagesApi? api;

  /// Dossier du cache (null : pas encore connu ; l'appli le fixe au démarrage).
  Future<Directory> Function()? dossier;

  /// Serveur hors ligne (aucune requête).
  bool Function() horsLigne = () => false;
  DateTime Function() clock;

  /// Demandes simultanées au plus.
  final int concurrence;

  /// Revérification d'un produit déjà connu (avec ou sans image).
  final Duration fraicheur;

  /// Taille maximale du cache en octets (tests) ; sinon le réglage (Mo).
  final int? tailleMaxOctets;

  ProduitImages({this.api, this.dossier, DateTime Function()? clock, this.concurrence = 3, this.fraicheur = const Duration(hours: 24), this.tailleMaxOctets})
      : clock = clock ?? DateTime.now;

  /// Instance de l'appli (remplaçable dans les tests).
  static ProduitImages instance = ProduitImages();

  final Map<String, _Entree> _index = {};
  final Map<String, Future<File?>> _enCours = {};
  final Map<String, bool> _modifiable = {};
  bool _charge = false;
  Directory? _dir;
  int _actifs = 0;
  final List<Completer<void>> _attente = [];
  CapaciteImages _capacite = CapaciteImages.inconnue;
  DateTime? _capaciteAt;

  /// Nombre de requêtes envoyées (diagnostic, tests).
  int requetes = 0;

  CapaciteImages get capacite => _capacite;
  int get tailleCache => _index.values.fold(0, (s, e) => s + e.taille);
  int get nbImages => _index.values.where((e) => e.imageId != null).length;

  /// Le serveur peut être interrogé (réglage actif, capacité non refusée, en ligne).
  bool get _interrogeable {
    if (!ImagesReglages.courant.value.actif || api == null || horsLigne()) return false;
    if (_capacite == CapaciteImages.non) {
      final at = _capaciteAt;
      if (at != null && clock().difference(at) < const Duration(minutes: 30)) return false;
      _capacite = CapaciteImages.inconnue;
    }
    return true;
  }

  /// Oublie la capacité (changement de serveur).
  void reinitialiserCapacite() {
    _capacite = CapaciteImages.inconnue;
    _capaciteAt = null;
  }

  // ---------------------------------------------------------------------------
  // Cache
  // ---------------------------------------------------------------------------

  Future<void> _charger() async {
    if (_charge) return;
    _charge = true;
    final d = dossier;
    if (d == null) return;
    try {
      _dir = await d();
      if (!_dir!.existsSync()) _dir!.createSync(recursive: true);
      final f = File('${_dir!.path}/index.json');
      if (f.existsSync()) {
        final j = jsonDecode(f.readAsStringSync());
        if (j is Map) {
          j.forEach((k, v) {
            if (v is Map) _index['$k'] = _Entree.fromJson(Map<String, dynamic>.from(v));
          });
        }
      }
      // Entrées dont le fichier a disparu : oubliées.
      _index.removeWhere((_, e) => e.fichier != null && !File('${_dir!.path}/${e.fichier}').existsSync());
    } catch (_) {
      _index.clear();
    }
  }

  /// Charge l'index du cache (au démarrage, pour l'affichage hors ligne et le tri de la borne).
  Future<void> init() => _charger();

  Timer? _ecriture;
  void _sauver() {
    _ecriture?.cancel();
    _ecriture = Timer(const Duration(milliseconds: 500), _ecrireIndex);
  }

  void _ecrireIndex() {
    final d = _dir;
    if (d == null) return;
    try {
      File('${d.path}/index.json').writeAsStringSync(jsonEncode({for (final e in _index.entries) e.key: e.value.toJson()}));
    } catch (_) {}
  }

  /// Écrit l'index tout de suite (tests, fermeture).
  Future<void> flush() async {
    _ecriture?.cancel();
    _ecrireIndex();
  }

  /// Fichier en cache (null : aucun connu) — synchrone, pour l'affichage.
  File? fichierConnu(String familleId) {
    final e = _index[familleId];
    final d = _dir;
    if (e == null || e.fichier == null || d == null) return null;
    e.vue = clock();
    return File('${d.path}/${e.fichier}');
  }

  /// true : image connue en cache ; false : « pas d'image » connu ; null : inconnu.
  bool? aImage(String familleId) {
    final e = _index[familleId];
    if (e == null) return null;
    return e.fichier != null;
  }

  /// Droit d'ajouter une photo (connu après la liste du produit).
  bool? modifiable(String familleId) => _modifiable[familleId];

  Future<void> _evincer() async {
    final max = tailleMaxOctets ?? ImagesReglages.courant.value.cacheMo * 1024 * 1024;
    var total = tailleCache;
    if (total <= max) return;
    final parVue = _index.entries.where((e) => e.value.fichier != null).toList()..sort((a, b) => a.value.vue.compareTo(b.value.vue));
    for (final e in parVue) {
      if (total <= max * 0.9) break;
      try {
        File('${_dir!.path}/${e.value.fichier}').deleteSync();
      } catch (_) {}
      total -= e.value.taille;
      _index.remove(e.key);
    }
  }

  /// Vide le cache (Réglages).
  Future<void> vider() async {
    await _charger();
    final d = _dir;
    for (final e in _index.values) {
      if (e.fichier == null || d == null) continue;
      try {
        File('${d.path}/${e.fichier}').deleteSync();
      } catch (_) {}
    }
    _index.clear();
    await flush();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Demandes
  // ---------------------------------------------------------------------------

  Future<void> _jeton() async {
    if (_actifs < concurrence) {
      _actifs++;
      return;
    }
    final c = Completer<void>();
    _attente.add(c);
    await c.future;
    _actifs++;
  }

  void _rendre() {
    _actifs--;
    if (_attente.isNotEmpty) _attente.removeAt(0).complete();
  }

  /// Image du produit (cache, sinon serveur) ; null : pas d'image, pas de capacité, ou hors ligne sans cache.
  Future<File?> demander(String familleId, {bool forcer = false}) async {
    if (familleId.isEmpty) return null;
    await _charger();
    final e = _index[familleId];
    final frais = e != null && clock().difference(e.verifie) < fraicheur;
    if ((frais && !forcer) || !_interrogeable) return fichierConnu(familleId);
    // (le rappel ne doit rien renvoyer : renvoyer la demande elle-même la ferait s'attendre.)
    return _enCours[familleId] ??= _rafraichir(familleId).whenComplete(() {
      _enCours.remove(familleId);
    });
  }

  Future<File?> _rafraichir(String familleId) async {
    await _jeton();
    try {
      if (!_interrogeable) return fichierConnu(familleId);
      requetes++;
      final r = await api!.lister(familleId);
      if (r is! VenteOk<ImagesListe?>) return fichierConnu(familleId); // panne : on garde le cache
      final liste = r.value;
      if (liste == null) {
        _capacite = CapaciteImages.non;
        _capaciteAt = clock();
        return null;
      }
      _capacite = CapaciteImages.oui;
      _modifiable[familleId] = liste.modifiable;
      final p = liste.principale;
      final ancien = _index[familleId];
      final now = clock();
      if (p == null) {
        _supprimerFichier(ancien);
        _index[familleId] = _Entree(verifie: now, vue: now);
        _sauver();
        if (ancien?.fichier != null) notifyListeners();
        return null;
      }
      if (ancien?.imageId == p.id && ancien?.fichier != null && File('${_dir?.path}/${ancien!.fichier}').existsSync()) {
        _index[familleId] = _Entree(imageId: p.id, fichier: ancien.fichier, taille: ancien.taille, verifie: now, vue: ancien.vue);
        _sauver();
        return fichierConnu(familleId);
      }
      requetes++;
      final f = await api!.fichier(familleId, p.id, vignette: p.vignette);
      if (f is! VenteOk<Uint8List>) return fichierConnu(familleId);
      final d = _dir;
      if (d == null) return null;
      final nom = '${_sur(familleId)}_${_sur(p.id)}.img';
      File('${d.path}/$nom').writeAsBytesSync(f.value, flush: true);
      if (ancien?.fichier != null && ancien!.fichier != nom) _supprimerFichier(ancien);
      _index[familleId] = _Entree(imageId: p.id, fichier: nom, taille: f.value.length, verifie: now, vue: now);
      await _evincer();
      _sauver();
      notifyListeners();
      return fichierConnu(familleId);
    } catch (_) {
      return fichierConnu(familleId);
    } finally {
      _rendre();
    }
  }

  static String _sur(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  void _supprimerFichier(_Entree? e) {
    if (e?.fichier == null || _dir == null) return;
    try {
      File('${_dir!.path}/${e!.fichier}').deleteSync();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Préchargement (copie locale du catalogue) : par lots, en tâche de fond, interrompu à la demande
  // ---------------------------------------------------------------------------

  bool _prechargeEnCours = false;
  bool _pause = false;
  bool _arret = false;
  int precharges = 0;

  bool get prechargeEnCours => _prechargeEnCours;
  void pause() => _pause = true;
  void reprendre() => _pause = false;
  void arreter() => _arret = true;

  /// Préchargement depuis la copie locale du catalogue (H5) : produits par lots de 200 ; seuls les produits
  /// jamais vus ou à revérifier (24 h) interrogent le serveur. Pause automatique quand l'appli est utilisée.
  Future<int> prechargerCatalogue(LocalStore store, {bool Function()? occupe}) {
    Stream<List<String>> lots() async* {
      var start = 0;
      while (true) {
        final page = await store.searchProducts('', start, 200);
        if (page.items.isEmpty) return;
        yield [for (final p in page.items) p.lgFAMILLEID];
        start += page.items.length;
        if (start >= page.total) return;
      }
    }

    return precharger(lots(), occupe: occupe);
  }

  /// Parcourt les identifiants par lots ; [occupe] : l'appli est utilisée (pause automatique).
  Future<int> precharger(Stream<List<String>> lots, {bool Function()? occupe, Duration attente = const Duration(seconds: 2)}) async {
    if (_prechargeEnCours) return 0;
    _prechargeEnCours = true;
    _arret = false;
    var n = 0;
    try {
      await for (final lot in lots) {
        for (final id in lot) {
          while (!_arret && (_pause || (occupe?.call() ?? false))) {
            await Future<void>.delayed(attente);
          }
          if (_arret || !_interrogeable) return n;
          await demander(id);
          n++;
          precharges++;
        }
      }
      return n;
    } finally {
      _prechargeEnCours = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Ajout depuis le terminal (bouton caché derrière un réglage admin)
  // ---------------------------------------------------------------------------

  /// Envoie la photo (image principale) ; refusée sans le droit « modifiable ».
  Future<VenteResult<String>> ajouterPhoto(String familleId, Uint8List jpeg) async {
    if (!ImagesReglages.courant.value.photoTerminal) return const VenteRefused('Ajout de photo désactivé (Réglages).');
    if (api == null || horsLigne()) return const VenteFailed('Serveur injoignable : photo non envoyée.');
    if (_modifiable[familleId] != true) {
      final l = await api!.lister(familleId);
      if (l case VenteOk(value: final v?)) _modifiable[familleId] = v.modifiable;
    }
    if (_modifiable[familleId] != true) return const VenteRefused('Vous n\'avez pas le droit de modifier les images des produits.');
    final r = await api!.ajouter(familleId, jpeg);
    if (r.isOk) await demander(familleId, forcer: true);
    return r;
  }
}
