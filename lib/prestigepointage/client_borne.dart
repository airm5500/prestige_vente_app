// lib/prestigepointage/client_borne.dart
// Prestige Pointage (demande 57, serveur 31622a33) : client SIGNÉ des routes v1/borne-pointage/*, sans session ni
// cookie. Il remplace, pour le terminal de pointage (lib/rh), le client de session DioRhServeur :
//   /rh/droits    → GET  borne-pointage/moi        (→ {success, gerer:false} : jamais de gestion avec la clé)
//   /rh/employes  → GET  borne-pointage/employes   (champs réduits : id, matricule, nom, prenoms, badge, statut)
//   /rh/pointages → POST borne-pointage/pointages  (id obligatoire, idempotent {deja:true}, 72 h au plus)
//   photo         → POST borne-pointage/pointages/{id}/photo (multipart construit ici, octet pour octet)
//   /rh/empreintes→ GET  borne-pointage/empreintes (partage des empreintes ; {code:DESACTIVE} sinon)
//   tout le reste → 404 sans requête (la borne n'a accès à rien d'autre).
// Chaque appel est signé (signature_borne.dart) sur les OCTETS EXACTS envoyés : le corps est construit ici (JSON en
// UTF-8, multipart) puis envoyé tel quel ; le chemin et les paramètres signés sont ceux de l'adresse envoyée.
// États du serveur (EtatBorne), affichés par l'application :
//   401 {code:BORNE}     → « Borne non reconnue » ; si l'heure du serveur (en-tête Date) diffère de plus de 4 min :
//                          « Heure du terminal incorrecte » ;
//   401 {code:REVOQUEE}  → « Appareil retiré : faites-le enrôler à nouveau » ;
//   403 {code:RESEAU}    → « Borne utilisable seulement sur le réseau de l'officine » ;
//   404 / 405, ou 401 sans code (serveur sans la demande 57) → « Serveur à mettre à jour » ;
//   429 + Retry-After    → aucun appel avant la fin de l'attente ;
//   réseau / Prestige indisponible → hors ligne (file des pointages).
// Dans tous ces cas, les pointages ne sont jamais perdus : le terminal les garde en file (RhHorsLigne).
// Jamais de journal des requêtes : ni le secret (qui ne circule pas), ni la signature, ni le contenu d'un badge.
import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/prestigepointage/identite_borne.dart';
import 'package:prestige_vente_app/prestigepointage/signature_borne.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';

enum EtatBorne {
  /// Aucun appel encore.
  inconnu,
  ok,

  /// Serveur injoignable (réseau).
  horsLigne,

  /// Prestige en démarrage ou en redéploiement.
  indisponible,

  /// 401 BORNE (signature, empreinte, borne inconnue).
  nonReconnue,

  /// 401 BORNE avec une horloge du terminal décalée de plus de 4 min.
  horloge,

  /// 401 REVOQUEE.
  revoquee,

  /// 403 RESEAU.
  reseau,

  /// Serveur sans la demande 57.
  serveurAncien,

  /// 429 TROP_DE_DEMANDES.
  tropDeDemandes,
}

/// Message de chaque état (écran de la borne).
String messageEtatBorne(EtatBorne e, {Duration? ecart, DateTime? heureServeur}) => switch (e) {
      EtatBorne.inconnu || EtatBorne.ok => '',
      EtatBorne.horsLigne => '${MessagesServeur.injoignable} Les pointages sont gardés sur la borne et envoyés au retour.',
      EtatBorne.indisponible => '${MessagesServeur.indisponible} Les pointages sont gardés sur la borne.',
      EtatBorne.nonReconnue => 'Borne non reconnue par Prestige : faites-la enrôler à nouveau (Administration). '
          'Les pointages sont gardés sur la borne.',
      EtatBorne.horloge => 'Heure du terminal incorrecte${ecart == null ? '' : ' (écart de ${_ecart(ecart)} avec le serveur'
          '${heureServeur == null ? '' : ', heure du serveur ${_hm(heureServeur.toLocal())}'})'} : réglez la date et l\'heure '
          'd\'Android (Paramètres › Date et heure, « automatique »). Les pointages sont gardés sur la borne.',
      EtatBorne.revoquee => 'Appareil retiré : faites-le enrôler à nouveau (Administration). Les pointages sont gardés sur la borne.',
      EtatBorne.reseau => 'Borne utilisable seulement sur le réseau de l\'officine : connectez-la au Wi-Fi de l\'officine.',
      EtatBorne.serveurAncien => 'Serveur à mettre à jour : ce serveur Prestige ne connaît pas encore les bornes de pointage '
          '(demande 57). Les pointages sont gardés sur la borne.',
      EtatBorne.tropDeDemandes => 'Trop de demandes : la borne réessaie dans un instant.',
    };

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
String _ecart(Duration d) {
  final m = d.inMinutes.abs();
  return m >= 120 ? '${(m / 60).round()} h' : '$m min';
}

class ClientBorne extends ChangeNotifier implements RhServeur, RhPhotos {
  final IdentiteBorne identite;
  final DateTime Function() maintenant;

  /// Écart au-delà duquel un refus BORNE est attribué à l'horloge (le serveur tolère 300 s).
  static const ecartHorlogeSignale = Duration(minutes: 4);

  /// Client HTTP (remplaçable pour les tests) ; par défaut : délais courts, statut toujours rendu.
  final Dio _dio;

  ClientBorne(this.identite, {Dio? dio, DateTime Function()? maintenant})
      : maintenant = maintenant ?? DateTime.now,
        _dio = avecDeploiement(dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              sendTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              validateStatus: (_) => true,
              responseType: ResponseType.plain,
            )));

  int _derniereDate = 0;
  EtatBorne _etat = EtatBorne.inconnu;
  EtatBorne get etat => _etat;
  Duration? _ecart;
  DateTime? _heureServeur;
  DateTime? _bloqueJusqua;

  /// Écart mesuré avec l'heure du serveur (en-tête Date) lors du dernier refus BORNE.
  Duration? get ecartHorloge => _ecart;
  DateTime? get bloqueJusqua => _bloqueJusqua;
  String get message => messageEtatBorne(_etat, ecart: _ecart, heureServeur: _heureServeur);

  /// La borne doit garder ses pointages en file (tout état autre que « en ligne », sauf avant le premier appel).
  bool get horsLigne => _etat != EtatBorne.ok && _etat != EtatBorne.inconnu;

  void _poser(EtatBorne e) {
    if (e == _etat) return;
    _etat = e;
    if (e != EtatBorne.horloge && e != EtatBorne.nonReconnue) {
      _ecart = null;
      _heureServeur = null;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------------------------- appel signé

  Uri _adresse(String route, Map<String, String>? query) {
    final base = Uri.parse(identite.serveur.trim().replaceAll(RegExp(r'/+$'), ''));
    final u = base.replace(path: '${base.path}/borne-pointage/$route');
    return query == null || query.isEmpty ? u : u.replace(queryParameters: query);
  }

  /// En-têtes signés d'un appel (exposé pour les tests : même calcul que l'envoi).
  @visibleForTesting
  Map<String, String> entetes(String methode, Uri adresse, List<int> corps) {
    // Date strictement croissante (milliseconde) : deux appels identiques dans la même milliseconde auraient la même
    // signature, refusée comme un rejeu par le serveur.
    var ms = maintenant().millisecondsSinceEpoch;
    if (ms <= _derniereDate) ms = _derniereDate + 1;
    _derniereDate = ms;
    final date = SignatureBorne.date(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));
    final chaine = SignatureBorne.chaine(methode, SignatureBorne.cheminEtParametres(adresse), date, identite.empreinte, corps);
    return {
      'X-Borne': identite.borneId,
      'X-Borne-Date': date,
      'X-Borne-Empreinte': identite.empreinte,
      'X-Borne-Signature': SignatureBorne.signer(identite.secret, chaine),
    };
  }

  Future<ReponseRh> appeler(String methode, String route, {Map<String, String>? query, List<int>? corps, String? type}) async {
    final fin = _bloqueJusqua;
    if (fin != null && maintenant().isBefore(fin)) throw const RhHorsLigne();
    _bloqueJusqua = null;
    final adresse = _adresse(route, query);
    final octets = corps ?? const <int>[];
    final h = <String, dynamic>{
      ...entetes(methode, adresse, octets),
      if (corps != null) Headers.contentTypeHeader: type ?? 'application/json; charset=utf-8',
      if (corps != null) Headers.contentLengthHeader: octets.length,
    };
    final Response<String> r;
    try {
      r = await _dio.requestUri<String>(adresse,
          data: corps == null ? null : Stream<List<int>>.value(octets),
          options: Options(method: methode, headers: h, responseType: ResponseType.plain, validateStatus: (_) => true));
    } on DioException catch (e) {
      final p = panneDe(e);
      _poser(p == PanneServeur.indisponible ? EtatBorne.indisponible : EtatBorne.horsLigne);
      throw RhHorsLigne(p ?? PanneServeur.injoignable);
    }
    if (reponseIndisponible(r)) {
      _poser(EtatBorne.indisponible);
      throw const RhHorsLigne(PanneServeur.indisponible);
    }
    Map<String, dynamic>? body;
    try {
      final o = jsonDecode(r.data ?? '');
      if (o is Map) body = Map<String, dynamic>.from(o);
    } catch (_) {}
    final s = r.statusCode ?? 0;
    final code = '${body?['code'] ?? ''}';
    if (s == 401) {
      if (code == 'REVOQUEE') {
        _poser(EtatBorne.revoquee);
      } else if (code == 'BORNE') {
        _refusBorne(r);
      } else {
        _poser(EtatBorne.serveurAncien); // serveur sans la demande 57 : « Veuillez vous connecter »
      }
      throw const RhHorsLigne();
    }
    if (s == 403 && code == 'RESEAU') {
      _poser(EtatBorne.reseau);
      throw const RhHorsLigne();
    }
    if (s == 404 || s == 405) {
      _poser(EtatBorne.serveurAncien);
      throw const RhHorsLigne();
    }
    if (s == 429) {
      final ra = int.tryParse((r.headers.value('retry-after') ?? '').trim());
      _bloqueJusqua = maintenant().add(Duration(seconds: max(1, min(ra ?? 60, 900))));
      _poser(EtatBorne.tropDeDemandes);
      throw const RhHorsLigne();
    }
    _poser(EtatBorne.ok);
    return (status: s, body: body);
  }

  void _refusBorne(Response<String> r) {
    DateTime? serveur;
    try {
      final d = r.headers.value('date');
      if (d != null) serveur = HttpDate.parse(d);
    } catch (_) {}
    if (serveur != null) {
      final ecart = maintenant().toUtc().difference(serveur.toUtc());
      if (ecart.abs() > ecartHorlogeSignale) {
        _ecart = ecart;
        _heureServeur = serveur;
        _etat = EtatBorne.nonReconnue; // forcé : notifie même si l'état était déjà « horloge »
        _poser(EtatBorne.horloge);
        return;
      }
    }
    _poser(EtatBorne.nonReconnue);
  }

  /// GET moi : état de la borne (test, retour en ligne) ; null si l'appel n'aboutit pas.
  Future<Map<String, dynamic>?> moi() async {
    try {
      final r = await appeler('GET', 'moi');
      return r.status == 200 && r.body?['success'] == true ? r.body : null;
    } on RhHorsLigne {
      return null;
    }
  }

  // ---------------------------------------------------------------------------------------------- RhServeur

  @override
  Future<ReponseRh> get(String chemin, [Map<String, dynamic> query = const {}]) async {
    switch (chemin) {
      case '/rh/droits':
        final r = await appeler('GET', 'moi');
        if (r.status == 200 && r.body?['success'] == true) return (status: 200, body: {'success': true, 'gerer': false});
        return r;
      case '/rh/employes':
        return appeler('GET', 'employes');
      case '/rh/empreintes':
        return appeler('GET', 'empreintes', query: {for (final e in query.entries) e.key: '${e.value}'});
      default:
        return (status: 404, body: null); // présence, gestion : jamais avec la clé de la borne
    }
  }

  @override
  Future<ReponseRh> post(String chemin, Map<String, dynamic> corps) async {
    if (chemin != '/rh/pointages') return (status: 404, body: null);
    return appeler('POST', 'pointages', corps: utf8.encode(jsonEncode(corps)));
  }

  @override
  Future<ReponseRh> envoyerPhoto(String pointageId, Uint8List jpeg, DateTime prise) {
    final (type, octets) = multipartPhoto(jpeg, isoLocal(prise));
    return appeler('POST', 'pointages/${Uri.encodeComponent(pointageId)}/photo', corps: octets, type: type);
  }

  /// Corps multipart de la photo (champ « photo » JPEG, champ « prise ») et son Content-Type.
  @visibleForTesting
  static (String, Uint8List) multipartPhoto(Uint8List jpeg, String prise, {String? frontiere}) {
    final f = frontiere ?? 'PrestigePointage${List.generate(16, (_) => Random.secure().nextInt(16).toRadixString(16)).join()}';
    final b = BytesBuilder(copy: false)
      ..add(utf8.encode('--$f\r\nContent-Disposition: form-data; name="photo"; filename="controle.jpg"\r\nContent-Type: image/jpeg\r\n\r\n'))
      ..add(jpeg)
      ..add(utf8.encode('\r\n--$f\r\nContent-Disposition: form-data; name="prise"\r\n\r\n$prise\r\n--$f--\r\n'));
    return ('multipart/form-data; boundary=$f', b.toBytes());
  }
}
