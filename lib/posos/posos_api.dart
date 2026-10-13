// lib/posos/posos_api.dart
// Routes (serveur Prestige, sans modification) :
//   GET  v1/posos/status   → {success, configuree, mode ("demonstration"|"posos"), …} (jamais de secret)
//   POST v1/posos/analyse  → forme A {produits:[{nom, quantite?, posologie?, cip?}], contexte?}
//                            forme B {venteId (id ou référence de vente, ou N° d'ordonnance), contexte?}
// Lecture seule et idempotente côté Prestige, mais chaque appel consomme l'API Posos : pas de relance automatique.
import 'package:prestige_vente_app/posos/posos_models.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';

class PososApi {
  final ClientPrestige client;
  PososApi(this.client);

  Future<PososStatut> statut() async => PososStatut.fromJson(await client.get('/posos/status'));

  Future<ResultatPosos> analyserProduits(List<ProduitAnalyse> produits, ContextePatient contexte) async {
    if (produits.isEmpty) throw const RefusMetier('Ajoutez au moins un produit à analyser.');
    return ResultatPosos.fromJson(await client.post('/posos/analyse', {
      'produits': [for (final p in produits) p.toJson()],
      if (contexte.toJson() case final c?) 'contexte': c,
    }, idempotent: true));
  }

  /// Analyse d'une vente : le serveur relit ses produits en base (préférable à la liste de l'écran).
  Future<ResultatPosos> analyserVente(String venteId, ContextePatient contexte) async {
    if (venteId.trim().isEmpty) throw const RefusMetier('Aucune vente à analyser.');
    return ResultatPosos.fromJson(await client.post('/posos/analyse', {
      'venteId': venteId.trim(),
      if (contexte.toJson() case final c?) 'contexte': c,
    }, idempotent: true));
  }
}
