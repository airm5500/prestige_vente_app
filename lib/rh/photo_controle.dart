// lib/rh/photo_controle.dart
// Photo de contrôle au pointage par badge (lutte contre le pointage pour un collègue, « buddy punching »).
//
// Après la lecture d'un badge (scanner, caméra, clavier, NFC), la caméra FRONTALE s'ouvre : l'employé voit
// l'aperçu et un compte à rebours (~2 s), puis la photo est prise sans action de sa part. L'empreinte (Sunmi V3H)
// reste la méthode la plus sûre : aucune photo pour un pointage par empreinte.
//
// Le serveur Prestige n'accepte AUCUNE photo avec le pointage (POST v1/rh/pointages : employeId, jour, heure, sens,
// motif ; aucune route d'envoi) : la photo est gardée sur CE terminal, dans le stockage privé de l'application
// (jamais dans la galerie ni sur la carte mémoire, exclue des sauvegardes Android), liée au pointage par son
// identifiant, consultable par l'administrateur et effacée automatiquement après la durée de conservation
// (30 jours par défaut). Demande au serveur : docs/serveur/DEMANDE_PHOTO_POINTAGE.md.
//
// Pannes : caméra absente, autorisation refusée, erreur, trop lente → le pointage n'est JAMAIS bloqué ; il est
// marqué « sans photo (motif) », noté dans le journal du terminal et signalé dans le rapport d'anomalies.
// Jamais de photo (ni d'octets, ni de chemin) dans les journaux.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Réglages administrateur (Paramètres › Équipe & pointage, protégés par le code administrateur)
// ---------------------------------------------------------------------------

class ReglagesPointageTerminal {
  /// Photo de contrôle à chaque pointage par badge (activée par défaut).
  final bool photoBadge;

  /// Pointage par simple bouton sur ce terminal : « Mon pointage » (Arrivée / Départ) et, dans le pointage local,
  /// le choix du nom sans PIN ni empreinte. Autorisé par défaut (comportement d'avant) ; à désactiver sur un
  /// terminal partagé.
  final bool simpleBouton;

  /// Durée de conservation des photos sur ce terminal (jours).
  final int retentionJours;

  const ReglagesPointageTerminal({this.photoBadge = true, this.simpleBouton = true, this.retentionJours = retentionParDefaut});

  static const int retentionParDefaut = 30;
  static const int retentionMin = 1;
  static const int retentionMax = 365;

  /// Durées proposées à l'administrateur.
  static const List<int> retentionsProposees = [7, 15, 30, 60, 90];

  static const prefPhoto = 'rh_photo_badge_v1';
  static const prefSimpleBouton = 'rh_simple_bouton_v1';
  static const prefRetention = 'rh_photo_retention_jours_v1';

  static int borner(int jours) => jours.clamp(retentionMin, retentionMax);

  ReglagesPointageTerminal copie({bool? photoBadge, bool? simpleBouton, int? retentionJours}) => ReglagesPointageTerminal(
        photoBadge: photoBadge ?? this.photoBadge,
        simpleBouton: simpleBouton ?? this.simpleBouton,
        retentionJours: borner(retentionJours ?? this.retentionJours),
      );

  /// Lecture (valeurs par défaut si les préférences sont illisibles).
  static Future<ReglagesPointageTerminal> charger() async {
    try {
      final p = await SharedPreferences.getInstance();
      return ReglagesPointageTerminal(
        photoBadge: p.getBool(prefPhoto) ?? true,
        simpleBouton: p.getBool(prefSimpleBouton) ?? true,
        retentionJours: borner(p.getInt(prefRetention) ?? retentionParDefaut),
      );
    } catch (_) {
      return const ReglagesPointageTerminal();
    }
  }

  Future<void> enregistrer() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(prefPhoto, photoBadge);
    await p.setBool(prefSimpleBouton, simpleBouton);
    await p.setInt(prefRetention, borner(retentionJours));
  }
}

/// Explication affichée quand le pointage par simple bouton est désactivé sur ce terminal.
const String messageSimpleBoutonDesactive =
    'Désactivé sur ce terminal par l\'administrateur (terminal partagé) : pointez avec votre badge (photo de contrôle) '
    'ou votre empreinte.';

// ---------------------------------------------------------------------------
// Résultat d'une prise de photo
// ---------------------------------------------------------------------------

/// Pourquoi un pointage par badge n'a pas de photo.
enum MotifSansPhoto { cameraAbsente, permissionRefusee, erreurCamera, delaiDepasse, photoIllisible }

extension MotifSansPhotoInfo on MotifSansPhoto {
  String get label => switch (this) {
        MotifSansPhoto.cameraAbsente => 'caméra frontale absente',
        MotifSansPhoto.permissionRefusee => 'autorisation de la caméra refusée',
        MotifSansPhoto.erreurCamera => 'erreur de la caméra',
        MotifSansPhoto.delaiDepasse => 'caméra trop lente',
        MotifSansPhoto.photoIllisible => 'photo illisible',
      };
}

/// « sans photo (autorisation de la caméra refusée) ».
String libelleSansPhoto(MotifSansPhoto m) => 'sans photo (${m.label})';

sealed class ResultatPhoto {
  const ResultatPhoto();
}

/// Photo prise et compressée (JPEG).
class PhotoPrise extends ResultatPhoto {
  final Uint8List jpeg;
  const PhotoPrise(this.jpeg);
}

/// Pas de photo : le pointage continue, marqué « sans photo (motif) ».
class PhotoAbsente extends ResultatPhoto {
  final MotifSansPhoto motif;
  const PhotoAbsente(this.motif);
}

/// La caméra ne peut pas servir (motif pour le marquage « sans photo »).
class CameraIndisponible implements Exception {
  final MotifSansPhoto motif;
  final String detail;
  const CameraIndisponible(this.motif, [this.detail = '']);
  @override
  String toString() => detail.isEmpty ? motif.label : '${motif.label} ($detail)';
}

// ---------------------------------------------------------------------------
// Caméra (abstraction injectable : caméra simulée dans les tests)
// ---------------------------------------------------------------------------

abstract class CameraControle {
  /// Ouvre la caméra FRONTALE ; [CameraIndisponible] si elle ne peut pas servir.
  Future<SessionCamera> ouvrir();
}

abstract class SessionCamera {
  /// Aperçu affiché à l'employé (il voit qu'il est photographié).
  Widget apercu();

  /// Photo brute (JPEG du capteur).
  Future<Uint8List> capturer();

  Future<void> fermer();
}

/// Caméra frontale Android (camera_android, Camera2, déjà utilisée par la capture guidée ; aucun nouveau paquet).
/// L'autorisation CAMERA (déjà déclarée) est demandée par Android à la première ouverture.
class CameraFrontalePlateforme implements CameraControle {
  const CameraFrontalePlateforme();

  CameraPlatform get _cam => CameraPlatform.instance;

  static MotifSansPhoto motifDe(Object e) {
    if (e is CameraException) {
      switch (e.code) {
        case 'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' || 'CameraAccessRestricted' || 'cameraPermission':
          return MotifSansPhoto.permissionRefusee;
        case 'NoCamera':
          return MotifSansPhoto.cameraAbsente;
      }
    }
    return MotifSansPhoto.erreurCamera;
  }

  @override
  Future<SessionCamera> ouvrir() async {
    try {
      return await _ouvrir();
    } on CameraIndisponible {
      rethrow;
    } catch (e) {
      final m = motifDe(e);
      if (m == MotifSansPhoto.permissionRefusee) throw CameraIndisponible(m);
      // Le scanner du badge (caméra arrière) peut tenir encore la caméra un court instant : un nouvel essai.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      try {
        return await _ouvrir();
      } on CameraIndisponible {
        rethrow;
      } catch (e2) {
        throw CameraIndisponible(motifDe(e2), e2 is CameraException ? e2.code : e2.runtimeType.toString());
      }
    }
  }

  Future<SessionCamera> _ouvrir() async {
    final cameras = await _cam.availableCameras();
    final avant = cameras.where((c) => c.lensDirection == CameraLensDirection.front).toList();
    // Pas de repli sur la caméra arrière : elle photographierait le mur, pas l'employé.
    if (avant.isEmpty) throw const CameraIndisponible(MotifSansPhoto.cameraAbsente);
    final d = avant.first;
    final id = await _cam.createCameraWithSettings(d, const MediaSettings(resolutionPreset: ResolutionPreset.medium, enableAudio: false));
    try {
      final init = _cam.onCameraInitialized(id).first;
      await _cam.initializeCamera(id, imageFormatGroup: ImageFormatGroup.jpeg);
      final e = await init;
      try {
        await _cam.setFlashMode(id, FlashMode.off);
      } catch (_) {}
      return _SessionPlateforme(_cam, id, Size(e.previewWidth, e.previewHeight));
    } catch (e) {
      try {
        await _cam.dispose(id);
      } catch (_) {}
      rethrow;
    }
  }
}

class _SessionPlateforme implements SessionCamera {
  final CameraPlatform cam;
  final int id;
  final Size taille;
  bool _fermee = false;
  _SessionPlateforme(this.cam, this.id, this.taille);

  @override
  Widget apercu() => FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        // Le capteur est en paysage : l'aperçu est affiché en portrait.
        child: SizedBox(width: taille.height, height: taille.width, child: cam.buildPreview(id)),
      );

  @override
  Future<Uint8List> capturer() async {
    final f = await cam.takePicture(id);
    try {
      return await f.readAsBytes();
    } finally {
      // Fichier temporaire du plugin : supprimé aussitôt (seule la version compressée est gardée).
      try {
        await File(f.path).delete();
      } catch (_) {}
    }
  }

  @override
  Future<void> fermer() async {
    if (_fermee) return;
    _fermee = true;
    try {
      await cam.dispose(id);
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Compression (JPEG ~640 px max, < 100 Ko)
// ---------------------------------------------------------------------------

const int photoCoteMax = 640;
const int photoOctetsMax = 100 * 1024;

/// Redresse (EXIF), réduit à [cote] px sur le plus grand côté et compresse en JPEG sous [maxOctets].
/// Lève [FormatException] si l'image est illisible.
Uint8List compresserPhoto(Uint8List brut, {int cote = photoCoteMax, int maxOctets = photoOctetsMax}) {
  img.Image? source;
  try {
    source = img.decodeImage(brut);
  } catch (_) {
    source = null;
  }
  if (source == null) throw const FormatException('Photo illisible');
  var image = img.bakeOrientation(source);
  var c = cote;
  while (true) {
    final grand = image.width >= image.height ? image.width : image.height;
    final r = grand > c
        ? (image.width >= image.height ? img.copyResize(image, width: c, interpolation: img.Interpolation.average) : img.copyResize(image, height: c, interpolation: img.Interpolation.average))
        : image;
    for (final q in const [75, 65, 55, 45, 35]) {
      final jpeg = img.encodeJpg(r, quality: q);
      if (jpeg.length < maxOctets) return jpeg;
    }
    // Image très détaillée : on réduit encore.
    if (c <= 160) return img.encodeJpg(r, quality: 30);
    c = (c * 0.75).round();
    image = r;
  }
}

/// Compression hors du fil de l'interface.
Future<Uint8List> compresserPhotoIsolat(Uint8List brut) => compute(compresserPhoto, brut);

// ---------------------------------------------------------------------------
// Prise de photo : aperçu ~2 s avec compte à rebours, puis capture automatique
// ---------------------------------------------------------------------------

enum EtatCapture { ouverture, apercu, capture, prise, absente }

class CapturePhotoControle extends ChangeNotifier {
  final CameraControle camera;
  final Future<Uint8List> Function(Uint8List) compresser;

  /// Durée de l'aperçu avant la capture (compte à rebours affiché).
  final Duration delaiApercu;
  final Duration delaiOuverture;
  final Duration delaiCapture;

  CapturePhotoControle({
    required this.camera,
    this.compresser = compresserPhotoIsolat,
    this.delaiApercu = const Duration(seconds: 2),
    this.delaiOuverture = const Duration(seconds: 6),
    this.delaiCapture = const Duration(seconds: 6),
  });

  EtatCapture _etat = EtatCapture.ouverture;
  EtatCapture get etat => _etat;
  SessionCamera? _session;
  SessionCamera? get session => _session;
  int _restant = 0;

  /// Secondes restantes avant la photo (compte à rebours affiché).
  int get restant => _restant;
  MotifSansPhoto? _motif;
  MotifSansPhoto? get motif => _motif;

  final _fini = Completer<ResultatPhoto>();
  Future<ResultatPhoto> get resultat => _fini.future;
  bool get terminee => _fini.isCompleted;

  Timer? _tic;
  Timer? _declencheur;
  Timer? _garde;
  bool _lance = false;
  bool _presse = false;
  bool _annulee = false;
  bool _disposee = false;

  void _notifier() {
    if (!_disposee) notifyListeners();
  }

  /// Ouvre la caméra frontale, montre l'aperçu [delaiApercu], puis prend la photo.
  void lancer() {
    if (_lance) return;
    _lance = true;
    _garde = Timer(delaiOuverture, () {
      if (_etat == EtatCapture.ouverture) _terminer(const PhotoAbsente(MotifSansPhoto.delaiDepasse));
    });
    camera.ouvrir().then((s) {
      if (terminee || _annulee) {
        s.fermer();
        return;
      }
      _garde?.cancel();
      _session = s;
      _etat = EtatCapture.apercu;
      // « Valider » déjà appuyé : aperçu bref (l'employé se voit quand même), puis la photo.
      final delai = _presse ? const Duration(milliseconds: 700) : delaiApercu;
      _restant = (delai.inMilliseconds / 1000).ceil();
      _notifier();
      _tic = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_restant > 1) {
          _restant--;
          _notifier();
        }
      });
      _declencheur = Timer(delai, capturerMaintenant);
    }, onError: (Object e) {
      _terminer(PhotoAbsente(e is CameraIndisponible ? e.motif : CameraFrontalePlateforme.motifDe(e)));
    });
  }

  /// Photo tout de suite (l'employé a appuyé sur « Valider ») si l'aperçu est affiché.
  Future<void> capturerMaintenant() async {
    final s = _session;
    if (_etat == EtatCapture.ouverture) _presse = true;
    if (s == null || _etat != EtatCapture.apercu || terminee) return;
    _tic?.cancel();
    _declencheur?.cancel();
    _etat = EtatCapture.capture;
    _restant = 0;
    _notifier();
    try {
      final brut = await s.capturer().timeout(delaiCapture);
      if (terminee) return;
      Uint8List jpeg;
      try {
        jpeg = await compresser(brut);
      } catch (_) {
        _terminer(const PhotoAbsente(MotifSansPhoto.photoIllisible));
        return;
      }
      _terminer(PhotoPrise(jpeg));
    } on TimeoutException {
      _terminer(const PhotoAbsente(MotifSansPhoto.delaiDepasse));
    } catch (e) {
      _terminer(PhotoAbsente(e is CameraIndisponible ? e.motif : CameraFrontalePlateforme.motifDe(e)));
    }
  }

  void _terminer(ResultatPhoto r) {
    _tic?.cancel();
    _declencheur?.cancel();
    _garde?.cancel();
    if (!_fini.isCompleted) _fini.complete(r);
    _etat = r is PhotoPrise ? EtatCapture.prise : EtatCapture.absente;
    _motif = r is PhotoAbsente ? r.motif : null;
    final s = _session;
    _session = null;
    s?.fermer();
    _notifier();
  }

  /// Lecture annulée : caméra fermée, aucune photo gardée.
  void annuler() {
    _annulee = true;
    _tic?.cancel();
    _declencheur?.cancel();
    _garde?.cancel();
    final s = _session;
    _session = null;
    s?.fermer();
    if (!_fini.isCompleted) _fini.complete(const PhotoAbsente(MotifSansPhoto.erreurCamera));
  }

  @override
  void dispose() {
    if (!terminee) annuler();
    _disposee = true;
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Registre des photos (stockage privé du terminal) et rétention
// ---------------------------------------------------------------------------

/// Photo (ou absence de photo) liée à un pointage.
class PhotoPointage {
  /// Identifiant du pointage (PointageBadge.id, PointageRecord.id) : nom du fichier.
  final String id;

  /// `rh` (Pointage présence, envoyé à Prestige) ou `local` (pointage local).
  final String source;
  final String employeId;
  final String employeNom;
  final DateTime lu;

  /// « Entrée », « Sortie », « Arrivée »…
  final String sens;

  /// « Scan du badge », « Badge NFC »…
  final String moyen;
  final bool avecPhoto;
  final MotifSansPhoto? motif;
  final int taille;

  /// État de l'envoi à Prestige (StatutPointageBadge.name) ; vide pour le pointage local.
  final String envoi;

  /// « Sans photo » vu par l'administrateur.
  final bool traitee;

  const PhotoPointage({
    required this.id,
    this.source = 'rh',
    required this.employeId,
    this.employeNom = '',
    required this.lu,
    this.sens = '',
    this.moyen = '',
    required this.avecPhoto,
    this.motif,
    this.taille = 0,
    this.envoi = '',
    this.traitee = false,
  });

  String get etat => avecPhoto ? 'Photo de contrôle' : libelleSansPhoto(motif ?? MotifSansPhoto.erreurCamera);

  PhotoPointage copie({String? envoi, bool? traitee}) => PhotoPointage(
        id: id,
        source: source,
        employeId: employeId,
        employeNom: employeNom,
        lu: lu,
        sens: sens,
        moyen: moyen,
        avecPhoto: avecPhoto,
        motif: motif,
        taille: taille,
        envoi: envoi ?? this.envoi,
        traitee: traitee ?? this.traitee,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source,
        'employeId': employeId,
        'employeNom': employeNom,
        'lu': lu.toIso8601String(),
        'sens': sens,
        'moyen': moyen,
        'avecPhoto': avecPhoto,
        'motif': motif?.name,
        'taille': taille,
        'envoi': envoi,
        'traitee': traitee,
      };

  factory PhotoPointage.fromJson(Map<String, dynamic> j) => PhotoPointage(
        id: '${j['id'] ?? ''}',
        source: '${j['source'] ?? 'rh'}',
        employeId: '${j['employeId'] ?? ''}',
        employeNom: '${j['employeNom'] ?? ''}',
        lu: DateTime.tryParse('${j['lu']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        sens: '${j['sens'] ?? ''}',
        moyen: '${j['moyen'] ?? ''}',
        avecPhoto: j['avecPhoto'] == true,
        motif: MotifSansPhoto.values.asNameMap()['${j['motif']}'],
        taille: j['taille'] is num ? (j['taille'] as num).toInt() : 0,
        envoi: '${j['envoi'] ?? ''}',
        traitee: j['traitee'] == true,
      );
}

/// Identifiant utilisable comme nom de fichier (UUID) : rien d'autre n'est accepté.
bool idPhotoValide(String id) => RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id);

abstract class StockagePhotos {
  Future<List<PhotoPointage>> lire();
  Future<void> ecrire(PhotoPointage p, {Uint8List? jpeg});
  Future<Uint8List?> image(String id);
  Future<void> supprimer(Iterable<String> ids);
}

class StockagePhotosMemoire implements StockagePhotos {
  final Map<String, PhotoPointage> fiches = {};
  final Map<String, Uint8List> images = {};

  @override
  Future<List<PhotoPointage>> lire() async => fiches.values.toList();
  @override
  Future<void> ecrire(PhotoPointage p, {Uint8List? jpeg}) async {
    fiches[p.id] = p;
    if (jpeg != null) images[p.id] = jpeg;
  }

  @override
  Future<Uint8List?> image(String id) async => images[id];
  @override
  Future<void> supprimer(Iterable<String> ids) async {
    for (final id in ids.toList()) {
      fiches.remove(id);
      images.remove(id);
    }
  }
}

/// Stockage privé de l'application (Android : /data/data/<appli>/files/photos_pointage, inaccessible aux autres
/// applications, exclu des sauvegardes) : un index JSON et un fichier JPEG par pointage.
class StockagePhotosFichiers implements StockagePhotos {
  final Future<Directory> Function() dossier;
  StockagePhotosFichiers([Future<Directory> Function()? dossier]) : dossier = dossier ?? _dossierPrive;

  static Future<Directory> _dossierPrive() async => Directory('${(await getApplicationSupportDirectory()).path}/photos_pointage');

  Future<Directory> _dir() async {
    final d = await dossier();
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _index() async => File('${(await _dir()).path}/index.json');
  Future<File> _fichier(String id) async => File('${(await _dir()).path}/$id.jpg');

  Future<Map<String, PhotoPointage>> _lireIndex() async {
    try {
      final f = await _index();
      if (!await f.exists()) return {};
      final l = jsonDecode(await f.readAsString());
      if (l is! List) return {};
      return {
        for (final x in l)
          if (x is Map) PhotoPointage.fromJson(Map<String, dynamic>.from(x)).id: PhotoPointage.fromJson(Map<String, dynamic>.from(x)),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _ecrireIndex(Map<String, PhotoPointage> m) async {
    final f = await _index();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final p in m.values) p.toJson()]), flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<List<PhotoPointage>> lire() async => (await _lireIndex()).values.toList();

  @override
  Future<void> ecrire(PhotoPointage p, {Uint8List? jpeg}) async {
    if (!idPhotoValide(p.id)) throw ArgumentError('Identifiant de pointage invalide');
    if (jpeg != null) await (await _fichier(p.id)).writeAsBytes(jpeg, flush: true);
    final m = await _lireIndex();
    m[p.id] = p;
    await _ecrireIndex(m);
  }

  @override
  Future<Uint8List?> image(String id) async {
    if (!idPhotoValide(id)) return null;
    final f = await _fichier(id);
    return await f.exists() ? await f.readAsBytes() : null;
  }

  @override
  Future<void> supprimer(Iterable<String> ids) async {
    final s = ids.toSet();
    if (s.isEmpty) return;
    for (final id in s) {
      if (!idPhotoValide(id)) continue;
      try {
        final f = await _fichier(id);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    final m = await _lireIndex();
    m.removeWhere((k, _) => s.contains(k));
    await _ecrireIndex(m);
  }
}

/// Photos de contrôle de CE terminal ; les pointages « sans photo » sont signalés dans le rapport d'anomalies commun.
class RegistrePhotosPointage extends ChangeNotifier implements AnomalieSourceListe {
  final StockagePhotos stockage;
  final DateTime Function() _clock;
  final JournalTerminal Function() journal;

  /// Durée de conservation (jours) ; par défaut celle des réglages administrateur.
  final Future<int> Function() retentionJours;

  RegistrePhotosPointage({
    StockagePhotos? stockage,
    DateTime Function()? clock,
    JournalTerminal Function()? journal,
    Future<int> Function()? retentionJours,
  })  : stockage = stockage ?? StockagePhotosFichiers(),
        _clock = clock ?? DateTime.now,
        journal = journal ?? (() => JournalTerminal.instance),
        retentionJours = retentionJours ?? (() async => (await ReglagesPointageTerminal.charger()).retentionJours);

  static RegistrePhotosPointage? _instance;
  static RegistrePhotosPointage get instance => _instance ??= RegistrePhotosPointage();
  static set instance(RegistrePhotosPointage? v) => _instance = v;

  List<PhotoPointage> _photos = [];
  bool _charge = false;

  /// Les plus récentes d'abord.
  List<PhotoPointage> get photos => List.unmodifiable(_photos);
  List<PhotoPointage> get sansPhoto => _photos.where((p) => !p.avecPhoto).toList();

  void _trier() => _photos.sort((a, b) => b.lu.compareTo(a.lu));

  /// Charge l'index et efface ce qui dépasse la durée de conservation.
  Future<void> charger({bool forcer = false}) async {
    if (!_charge || forcer) {
      try {
        _photos = await stockage.lire();
        _charge = true;
      } catch (_) {
        _photos = [];
      }
      _trier();
    }
    await purger();
    notifyListeners();
  }

  /// Purge automatique : photos et fiches plus anciennes que la durée de conservation. Renvoie le nombre effacé.
  Future<int> purger() async {
    int jours;
    try {
      jours = ReglagesPointageTerminal.borner(await retentionJours());
    } catch (_) {
      jours = ReglagesPointageTerminal.retentionParDefaut;
    }
    final limite = _clock().subtract(Duration(days: jours));
    final vieux = [for (final p in _photos) if (p.lu.isBefore(limite)) p.id];
    if (vieux.isEmpty) return 0;
    try {
      await stockage.supprimer(vieux);
    } catch (_) {
      return 0;
    }
    _photos.removeWhere((p) => vieux.contains(p.id));
    notifyListeners();
    _noter('Photos de contrôle effacées (conservation $jours jours) : ${vieux.length}', ResultatJournal.info);
    return vieux.length;
  }

  /// Photo (ou absence de photo) du pointage [id]. Jamais bloquant : une erreur d'écriture est seulement notée.
  Future<PhotoPointage> ajouter({
    required String id,
    String source = 'rh',
    required String employeId,
    String employeNom = '',
    required DateTime lu,
    String sens = '',
    String moyen = '',
    required ResultatPhoto resultat,
    String envoi = '',
  }) async {
    if (!_charge) {
      try {
        _photos = await stockage.lire();
        _charge = true;
      } catch (_) {}
    }
    final jpeg = resultat is PhotoPrise ? resultat.jpeg : null;
    var p = PhotoPointage(
      id: id,
      source: source,
      employeId: employeId,
      employeNom: employeNom,
      lu: lu,
      sens: sens,
      moyen: moyen,
      avecPhoto: jpeg != null,
      motif: resultat is PhotoAbsente ? resultat.motif : null,
      taille: jpeg?.length ?? 0,
      envoi: envoi,
    );
    try {
      await stockage.ecrire(p, jpeg: jpeg);
    } catch (_) {
      if (jpeg != null) {
        // Photo non écrite (stockage plein…) : le pointage est gardé, marqué sans photo.
        p = PhotoPointage(
            id: id, source: source, employeId: employeId, employeNom: employeNom, lu: lu, sens: sens, moyen: moyen, avecPhoto: false,
            motif: MotifSansPhoto.photoIllisible, envoi: envoi);
        try {
          await stockage.ecrire(p);
        } catch (_) {}
      }
    }
    _photos.removeWhere((x) => x.id == id);
    _photos.add(p);
    _trier();
    // Journal : jamais la photo ni son chemin, seulement le fait.
    _noter(
        p.avecPhoto ? 'Photo de contrôle prise — $employeNom $sens' : 'Pointage ${libelleSansPhoto(p.motif!)} — $employeNom $sens',
        p.avecPhoto ? ResultatJournal.ok : ResultatJournal.info,
        ref: id);
    notifyListeners();
    return p;
  }

  /// État de l'envoi du pointage à Prestige (après l'envoi de la file hors ligne).
  Future<void> majEnvoi(String id, String envoi) async {
    final i = _photos.indexWhere((p) => p.id == id);
    if (i < 0 || _photos[i].envoi == envoi) return;
    _photos[i] = _photos[i].copie(envoi: envoi);
    try {
      await stockage.ecrire(_photos[i]);
    } catch (_) {}
    notifyListeners();
  }

  Future<Uint8List?> image(String id) async {
    try {
      return await stockage.image(id);
    } catch (_) {
      return null;
    }
  }

  void _noter(String action, ResultatJournal r, {String ref = ''}) {
    try {
      journal().noter(
        type: TypeJournal.pointageRh,
        action: action,
        refLocale: ref.length > 8 ? ref.substring(0, 8) : ref,
        resultat: r,
      );
    } catch (_) {}
  }

  // Rapport d'anomalies commun : pointages par badge SANS photo de contrôle.

  @override
  String get titreAnomalies => 'POINTAGES BADGE SANS PHOTO';

  @override
  List<Anomalie> get anomaliesList => [
        for (final p in _photos)
          if (!p.avecPhoto)
            Anomalie(
              id: 'photo-${p.id}',
              source: 'photo',
              date: p.lu,
              type: 'Pointage ${p.sens.toLowerCase()} ${libelleSansPhoto(p.motif ?? MotifSansPhoto.erreurCamera)}',
              reference: '${p.employeNom} · ${p.moyen}',
              motif: 'Photo de contrôle non prise : ${(p.motif ?? MotifSansPhoto.erreurCamera).label}.',
              traitee: p.traitee,
              operationId: p.id,
            ),
      ];

  @override
  int get anomaliesNonTraitees => _photos.where((p) => !p.avecPhoto && !p.traitee).length;

  @override
  Future<List<Anomalie>> anomalies() async {
    if (!_charge) await charger();
    return anomaliesList;
  }

  @override
  Future<void> setTraitee(String id, bool traitee) async {
    final pid = id.startsWith('photo-') ? id.substring(6) : id;
    final i = _photos.indexWhere((p) => p.id == pid);
    if (i < 0) return;
    _photos[i] = _photos[i].copie(traitee: traitee);
    try {
      await stockage.ecrire(_photos[i]);
    } catch (_) {}
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// Service : réglages + caméra + registre
// ---------------------------------------------------------------------------

class PhotoControle {
  final CameraControle camera;
  final RegistrePhotosPointage registre;
  final Future<ReglagesPointageTerminal> Function() reglages;
  final Future<Uint8List> Function(Uint8List) compresser;
  final Duration delaiApercu;
  final Duration delaiOuverture;
  final Duration delaiCapture;

  PhotoControle({
    CameraControle? camera,
    RegistrePhotosPointage? registre,
    Future<ReglagesPointageTerminal> Function()? reglages,
    this.compresser = compresserPhotoIsolat,
    this.delaiApercu = const Duration(seconds: 2),
    this.delaiOuverture = const Duration(seconds: 6),
    this.delaiCapture = const Duration(seconds: 6),
  })  : camera = camera ?? const CameraFrontalePlateforme(),
        registre = registre ?? RegistrePhotosPointage.instance,
        reglages = reglages ?? ReglagesPointageTerminal.charger;

  /// Service de l'application (branché par PointageRh.bind) ; null dans les tests qui ne l'installent pas.
  static PhotoControle? instance;

  CapturePhotoControle demarrer() => CapturePhotoControle(
        camera: camera,
        compresser: compresser,
        delaiApercu: delaiApercu,
        delaiOuverture: delaiOuverture,
        delaiCapture: delaiCapture,
      )..lancer();

  static const prefPermissionExpliquee = 'rh_photo_permission_expliquee_v1';

  static Future<bool> permissionExpliquee() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(prefPermissionExpliquee) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Ouvre puis ferme la caméra frontale : Android demande l'autorisation la première fois. Null si tout va bien.
  Future<MotifSansPhoto?> preparerCamera() async {
    try {
      final s = await camera.ouvrir().timeout(const Duration(seconds: 30));
      await s.fermer();
      try {
        await (await SharedPreferences.getInstance()).setBool(prefPermissionExpliquee, true);
      } catch (_) {}
      return null;
    } on CameraIndisponible catch (e) {
      try {
        await (await SharedPreferences.getInstance()).setBool(prefPermissionExpliquee, true);
      } catch (_) {}
      return e.motif;
    } on TimeoutException {
      return MotifSansPhoto.delaiDepasse;
    } catch (e) {
      return CameraFrontalePlateforme.motifDe(e);
    }
  }
}
