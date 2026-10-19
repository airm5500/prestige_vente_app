// lib/fiche_client/fiche_client_api.dart
// Routes v1/ordonnance-client (serveur Prestige, sans modification). Le serveur vérifie P_ORDONNANCE_CLIENT
// (lecture) et P_ORDONNANCE_CLIENT_MAJ (écriture) sur CHAQUE route ; un refus arrive en HTTP 200
// {success:false, message} et remonte en RefusMetier.
//   GET  droits                                  {success, consulter, modifier}
//   GET  clients?query=&start=&limit=            {data:[{lgCLIENTID, strFIRSTNAME, strLASTNAME, strTELEPHONE, …}]}
//   GET  client/{id}/dossier                     identité, terrains, allergies, derniers paramètres, IMC
//   POST client/{id}/dossier {allergies, terrains}   (terrains REMPLACÉS entièrement ; idempotent)
//   GET  terrains / parametres                   référentiels (actifs)
//   GET  client/{id}/mesures?parametreId=        historique d'un paramètre
//   POST client/{id}/mesures {parametreId, date, valeur | gauche/droite, commentaire}   (NON idempotent ; 4.6.1 :
//        en-tête X-Client-Ref = une seule mesure par clé sur un serveur à jour, ignoré par un serveur ancien)
//   GET  client/{id}/consommation?dtStart=&dtEnd=   consommation (12 mois par défaut)
// Aucune réponse n'est journalisée ni conservée sur le disque.
import 'package:prestige_vente_app/droits/droits_modules.dart';
import 'package:prestige_vente_app/fiche_client/fiche_client_models.dart';
import 'package:prestige_vente_app/fiche_client/fiche_client_validation.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/serveur/json_tolerant.dart';
import 'package:uuid/uuid.dart';

class FicheClientApi {
  final ClientPrestige client;
  FicheClientApi(this.client);

  static const _base = '/ordonnance-client';
  static String _id(String id) => Uri.encodeComponent(id);

  Future<DroitsOrdonnances> droits() async => DroitsOrdonnances.fromJson(await client.get('$_base/droits'));

  Future<List<ClientResume>> clients(String recherche, {int limit = 30}) async {
    final q = recherche.trim();
    if (q.length < 2) return const [];
    final j = await client.get('$_base/clients', {'query': q, 'start': 0, 'limit': limit});
    return [for (final o in objets(j['data'])) ClientResume.fromJson(o)]..removeWhere((c) => c.id.isEmpty);
  }

  Future<DossierClient> dossier(String clientId) async => DossierClient.fromJson(await client.get('$_base/client/${_id(clientId)}/dossier'));

  /// Enregistre allergies et terrains (les terrains du client sont remplacés par [terrains]).
  Future<String> enregistrerDossier(String clientId, {required String allergies, required List<String> terrains}) async {
    final e = validerAllergies(allergies);
    if (e != null) throw RefusMetier(e);
    final j = await client.post('$_base/client/${_id(clientId)}/dossier', {'allergies': allergies.trim(), 'terrains': terrains}, idempotent: true);
    return txtOuNull(j['message']) ?? 'Dossier du client enregistré.';
  }

  Future<List<TerrainClinique>> terrains() async {
    final j = await client.get('$_base/terrains');
    return [for (final o in objets(j['data'])) TerrainClinique.fromJson(o)]..removeWhere((t) => t.id.isEmpty || !t.actif);
  }

  Future<List<ParametreClinique>> parametres() async {
    final j = await client.get('$_base/parametres');
    return [for (final o in objets(j['data'])) ParametreClinique.fromJson(o)]..removeWhere((p) => p.id.isEmpty || !p.actif);
  }

  Future<List<Mesure>> mesures(String clientId, String parametreId) async {
    final j = await client.get('$_base/client/${_id(clientId)}/mesures', {'parametreId': parametreId});
    return [for (final o in objets(j['data'])) Mesure.fromJson(o)];
  }

  /// Ajoute une mesure (NON idempotent sur un serveur ancien : un seul envoi par saisie).
  /// [cle] (4.6.1, demande 19) : `X-Client-Ref` de la saisie ; un serveur à jour n'enregistre qu'une mesure pour une
  /// même clé et renvoie la même réponse (un renvoi après une réponse perdue ne crée pas de doublon).
  Future<String> ajouterMesure(String clientId, SaisieMesure saisie, {String? cle}) async {
    final erreurs = saisie.erreurs();
    if (erreurs.isNotEmpty) throw RefusMetier(erreurs.first);
    final j = await client.post('$_base/client/${_id(clientId)}/mesures', saisie.toJson(), idempotent: false, clientRef: cle);
    return txtOuNull(j['message']) ?? 'Mesure enregistrée.';
  }

  /// Clé d'une saisie de mesure (X-Client-Ref, 64 caractères au plus côté serveur).
  static String nouvelleCle() => 'FM-${const Uuid().v4()}';

  Future<List<LigneConsommation>> consommation(String clientId) async {
    final j = await client.get('$_base/client/${_id(clientId)}/consommation');
    return [for (final o in objets(j['data'])) LigneConsommation.fromJson(o)]..removeWhere((l) => l.nom.isEmpty);
  }
}
