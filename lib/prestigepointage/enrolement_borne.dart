// lib/prestigepointage/enrolement_borne.dart
// Prestige Pointage (demande 57) : enrôlement de la borne, UNE fois, par un administrateur :
//   1. connexion TEMPORAIRE du compte de l'administrateur (POST v1/user/auth) ;
//   2. POST v1/rh/bornes {empreinte (demande 56), nom} → {borneId, secret (rendu une seule fois), creeLe} ;
//   3. déconnexion immédiate (POST v1/user/logout) et cookies effacés, que l'enrôlement réussisse ou non.
// Ensuite plus aucune connexion : la borne signe ses appels (client_borne.dart). Le mot de passe de l'administrateur
// n'est jamais gardé ; le secret va directement au stockage sécurisé (identite_borne.dart).
// Refus : 403 {interdit} → droit P_SM_RH ou profil administrateur requis ; 400 {code:INVALIDE} ; 404 / 405 → serveur
// sans la demande 57.
import 'package:dio/dio.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/prestigepointage/identite_borne.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';

/// Issue d'un enrôlement : identité (succès) ou message.
class ResultatEnrolement {
  final IdentiteBorne? identite;
  final String message;
  const ResultatEnrolement.ok(IdentiteBorne this.identite) : message = '';
  const ResultatEnrolement.refus(this.message) : identite = null;
  bool get reussi => identite != null;
}

class EnrolementBorne {
  final ApiService Function(String baseUrl) _api;
  EnrolementBorne({ApiService Function(String baseUrl)? api}) : _api = api ?? ((u) => ApiService(baseUrl: u));

  static const messageDroit = 'Ce compte ne peut pas enrôler une borne : il faut le droit Ressources humaines (P_SM_RH) '
      'ou le profil administrateur.';
  static const messageServeurAncien = 'Serveur à mettre à jour : ce serveur Prestige ne connaît pas encore les bornes de '
      'pointage (demande 57).';

  Future<ResultatEnrolement> enroler({
    required String baseUrl,
    required String login,
    required String motDePasse,
    required String nom,
    required String empreinte,
  }) async {
    final api = _api(baseUrl);
    final u = await api.login(login.trim(), motDePasse);
    if (u == null) {
      final e = api.dernierEchecConnexion;
      return ResultatEnrolement.refus(e?.message.isNotEmpty == true ? e!.message : 'Connexion refusée.');
    }
    try {
      final Response<dynamic> r;
      try {
        r = await api.dio.post('/rh/bornes',
            data: {'empreinte': empreinte, 'nom': nom}, options: Options(validateStatus: (_) => true, headers: {'Cache-Control': 'no-store'}));
      } on DioException {
        return const ResultatEnrolement.refus('Serveur injoignable pendant l\'enrôlement : réessayez.');
      }
      final b = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : null;
      if (r.statusCode == 403 || b?['interdit'] == true) return const ResultatEnrolement.refus(messageDroit);
      if (r.statusCode == 404 || r.statusCode == 405) return const ResultatEnrolement.refus(messageServeurAncien);
      if (r.statusCode == 200) {
        final id = IdentiteBorne.depuisEnrolement(b, empreinte: empreinte, nom: nom, serveur: baseUrl);
        if (id != null) return ResultatEnrolement.ok(id);
      }
      return ResultatEnrolement.refus(messageRh(b, 'Enrôlement refusé par le serveur (${r.statusCode}).'));
    } finally {
      // Session de l'administrateur fermée tout de suite : la borne ne garde aucune session.
      await api.logout();
      try {
        await DioClient.cookieJar.deleteAll();
      } catch (_) {}
    }
  }
}
