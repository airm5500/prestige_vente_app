// lib/rh/rh_api.dart
// Voie B — API `v1/rh` de Prestige avec la SESSION de l'appli (cookies de /user/auth) : le compte
// connecté doit avoir le droit P_SM_RH. Routes utilisées telles quelles (aucune modification du serveur) :
//   GET  rh/droits                              → {success, valider} ou refus {success:false, message}
//   GET  rh/employes?query=&inactifs=false      → {data:[{id, matricule, badge, nom, prenoms, poste, statut…}]}
//   GET  rh/presence?jour=YYYY-MM-DD            → {data:[RhPresenceDTO], pointages:[{id, employeId, horodatage, sens, source, motif}]}
//   POST rh/pointages {employeId, jour, heure, sens, motif} → {success, message} (doublon de minute : refus « existe déjà »)
// 4.3.0 (réponse du serveur du 15/10/2026, demande 31) — serveur à jour, rien d'obligatoire :
//   POST rh/pointages {id, …, controle?} → {success, id, message} ; même id renvoyé → {success, id, deja:true}
//   POST rh/pointages/{id}/photo (multipart : photo = JPEG, prise = date et heure ISO de la prise) → {success}
//     ancien serveur : 404 / 405 → la photo reste sur le terminal (comme avant).
// 4.4.0 (demande 43, serveur du 16/10) — empreintes partagées, voir empreintes_partagees.dart :
//   POST rh/employes/{id}/empreintes, GET rh/empreintes?depuis&format, DELETE rh/employes/{id}/empreintes.
// Pas de journal des réponses (LogInterceptor) : seules les erreurs utiles remontent. Jamais la photo dans un journal.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';

typedef ReponseRh = ({int status, Map<String, dynamic>? body});

/// Le serveur ne répond pas (réseau) ou Prestige n'est pas déployé (4.3.3 : démarrage / redéploiement) : la voie B
/// passe en file hors ligne ; rien n'est conclu sur les routes du serveur.
class RhHorsLigne implements Exception {
  final PanneServeur panne;
  const RhHorsLigne([this.panne = PanneServeur.injoignable]);

  /// « Serveur injoignable » / « Serveur indisponible ».
  String get titre => MessagesServeur.titre(panne);
  @override
  String toString() => MessagesServeur.message(panne);
}

abstract class RhServeur {
  Future<ReponseRh> get(String chemin, [Map<String, dynamic> query = const {}]);
  Future<ReponseRh> post(String chemin, Map<String, dynamic> corps);
}

/// Envoi de la photo de contrôle d'un pointage (demande 31) ; facultatif pour un [RhServeur].
abstract class RhPhotos {
  Future<ReponseRh> envoyerPhoto(String pointageId, Uint8List jpeg, DateTime prise);
}

/// 4.4.0 — Empreintes partagées (demande 43) ; facultatif pour un [RhServeur] (sans : empreintes locales seulement).
abstract class RhEmpreintes {
  /// POST v1/rh/employes/{id}/empreintes avec l'en-tête X-Client-Ref (même référence = même réponse).
  Future<ReponseRh> envoyerEmpreintes(String employeId, Map<String, dynamic> corps, String clientRef);

  /// DELETE v1/rh/employes/{id}/empreintes.
  Future<ReponseRh> supprimerEmpreintes(String employeId);
}

/// Même session (cookies) et même adresse que l'appli.
class DioRhServeur implements RhServeur, RhPhotos, RhEmpreintes {
  final String Function() baseUrl;
  Dio? _dio;
  DioRhServeur(this.baseUrl);

  Dio get _client {
    final d = _dio ??= (Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (_) => true,
      responseType: ResponseType.plain,
    ))
      ..transformer = BackgroundTransformer()
      ..interceptors.add(CookieManager(DioClient.cookieJar))
      ..interceptors.add(IntercepteurUtilisateur()));
    avecDeploiement(d);
    d.options.baseUrl = baseUrl();
    return d;
  }

  Future<ReponseRh> _envoyer(Future<Response<String>> Function(Dio d) f) async {
    try {
      final r = await f(_client);
      if (reponseIndisponible(r)) throw const RhHorsLigne(PanneServeur.indisponible);
      Map<String, dynamic>? body;
      try {
        final o = jsonDecode(r.data ?? '');
        if (o is Map) body = Map<String, dynamic>.from(o);
      } catch (_) {}
      return (status: r.statusCode ?? 0, body: body);
    } on DioException catch (e) {
      if (e.response == null) throw const RhHorsLigne();
      if (reponseIndisponible(e.response)) throw const RhHorsLigne(PanneServeur.indisponible);
      return (status: e.response?.statusCode ?? 0, body: null);
    }
  }

  @override
  Future<ReponseRh> get(String chemin, [Map<String, dynamic> query = const {}]) =>
      _envoyer((d) => d.get<String>(chemin, queryParameters: query));

  @override
  Future<ReponseRh> post(String chemin, Map<String, dynamic> corps) => _envoyer(
      (d) => d.post<String>(chemin, data: jsonEncode(corps), options: Options(headers: {'Content-Type': 'application/json'})));

  // Jamais de journal de ces requêtes : le corps contient des gabarits d'empreinte.
  @override
  Future<ReponseRh> envoyerEmpreintes(String employeId, Map<String, dynamic> corps, String clientRef) => _envoyer((d) => d.post<String>(
      '/rh/employes/${Uri.encodeComponent(employeId)}/empreintes',
      data: jsonEncode(corps),
      options: Options(headers: {'Content-Type': 'application/json', 'X-Client-Ref': clientRef})));

  @override
  Future<ReponseRh> supprimerEmpreintes(String employeId) =>
      _envoyer((d) => d.delete<String>('/rh/employes/${Uri.encodeComponent(employeId)}/empreintes'));

  @override
  Future<ReponseRh> envoyerPhoto(String pointageId, Uint8List jpeg, DateTime prise) => _envoyer((d) => d.post<String>(
        '/rh/pointages/${Uri.encodeComponent(pointageId)}/photo',
        data: FormData.fromMap({
          'photo': MultipartFile.fromBytes(jpeg, filename: 'controle.jpg', contentType: DioMediaType('image', 'jpeg')),
          'prise': isoLocal(prise),
        }),
      ));
}

/// « 2026-10-15T08:02:00 » (heure du terminal, sans fuseau) : format lu par le serveur.
String isoLocal(DateTime t) {
  String d2(int v) => v.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${d2(t.month)}-${d2(t.day)}T${d2(t.hour)}:${d2(t.minute)}:${d2(t.second)}';
}

/// Message d'une réponse Prestige (`message`, sinon `msg`).
String messageRh(Map<String, dynamic>? b, String defaut) {
  final m = '${b?['message'] ?? b?['msg'] ?? ''}'.trim();
  return m.isEmpty ? defaut : m;
}
