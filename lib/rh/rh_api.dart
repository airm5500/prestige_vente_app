// lib/rh/rh_api.dart
// Voie B — API `v1/rh` de Prestige avec la SESSION de l'appli (cookies de /user/auth) : le compte
// connecté doit avoir le droit P_SM_RH. Routes utilisées telles quelles (aucune modification du serveur) :
//   GET  rh/droits                              → {success, valider} ou refus {success:false, message}
//   GET  rh/employes?query=&inactifs=false      → {data:[{id, matricule, badge, nom, prenoms, poste, statut…}]}
//   GET  rh/presence?jour=YYYY-MM-DD            → {data:[RhPresenceDTO], pointages:[{id, employeId, horodatage, sens, source, motif}]}
//   POST rh/pointages {employeId, jour, heure, sens, motif} → {success, message} (doublon de minute : refus « existe déjà »)
// Pas de journal des réponses (LogInterceptor) : seules les erreurs utiles remontent.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:prestige_vente_app/api/dio_client.dart';

typedef ReponseRh = ({int status, Map<String, dynamic>? body});

/// Le serveur ne répond pas (réseau) : la voie B passe en file hors ligne.
class RhHorsLigne implements Exception {
  const RhHorsLigne();
  @override
  String toString() => 'Serveur injoignable.';
}

abstract class RhServeur {
  Future<ReponseRh> get(String chemin, [Map<String, dynamic> query = const {}]);
  Future<ReponseRh> post(String chemin, Map<String, dynamic> corps);
}

/// Même session (cookies) et même adresse que l'appli.
class DioRhServeur implements RhServeur {
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
      ..interceptors.add(CookieManager(DioClient.cookieJar)));
    d.options.baseUrl = baseUrl();
    return d;
  }

  Future<ReponseRh> _envoyer(Future<Response<String>> Function(Dio d) f) async {
    try {
      final r = await f(_client);
      Map<String, dynamic>? body;
      try {
        final o = jsonDecode(r.data ?? '');
        if (o is Map) body = Map<String, dynamic>.from(o);
      } catch (_) {}
      return (status: r.statusCode ?? 0, body: body);
    } on DioException catch (e) {
      if (e.response == null) throw const RhHorsLigne();
      return (status: e.response?.statusCode ?? 0, body: null);
    }
  }

  @override
  Future<ReponseRh> get(String chemin, [Map<String, dynamic> query = const {}]) =>
      _envoyer((d) => d.get<String>(chemin, queryParameters: query));

  @override
  Future<ReponseRh> post(String chemin, Map<String, dynamic> corps) => _envoyer(
      (d) => d.post<String>(chemin, data: jsonEncode(corps), options: Options(headers: {'Content-Type': 'application/json'})));
}

/// Message d'une réponse Prestige (`message`, sinon `msg`).
String messageRh(Map<String, dynamic>? b, String defaut) {
  final m = '${b?['message'] ?? b?['msg'] ?? ''}'.trim();
  return m.isEmpty ? defaut : m;
}
