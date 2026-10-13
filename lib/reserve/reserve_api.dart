// lib/reserve/reserve_api.dart
// Routes du menu « Réserve » (serveur Prestige, aucune modification côté serveur) :
//   GET  reserve/articles?search_value=&str_TYPE_TRANSACTION=&start=&limit=   produits suivis en réserve + stocks
//   GET  suggestion-reserve/motifs?categorie=RESERVE|RAYON                   motifs (tableau nu)
//   GET  suggestion-reserve/en-attente?limit=                                 suggestions A_TRAITER / EN_COURS
//        (filtrées sur l'emplacement de l'utilisateur, contrairement à « liste »)
//   POST suggestion-reserve/creer {categorie, motifId, commentaire, items}   NON idempotente (2 envois = 2 suggestions)
//   PUT  suggestion-reserve/{id}/ouvrir                                       détail + verrou (20 min)
//   PUT  suggestion-reserve/{id}/liberer                                      rend la suggestion aux autres
//   PUT  suggestion-reserve/ligne/{detailId}/quantite {int_QTE}               quantité retenue (aucun stock ne bouge)
//   DELETE suggestion-reserve/ligne/{detailId}?motif=                         retire la ligne
//   PUT  suggestion-reserve/{id}/traiter | reessayer                          DÉPLACE LE STOCK, renvoie le compte rendu
//   GET  roles/est-admin                                                      {authorize} : profil administrateur
// Aucun mouvement direct (assort / reassort) : décision du pharmacien, tout passe par une suggestion.
import 'package:prestige_vente_app/reserve/reserve_models.dart';
import 'package:prestige_vente_app/reserve/reserve_regles.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/serveur/json_tolerant.dart';

class ReserveApi {
  final ClientPrestige client;
  ReserveApi(this.client);

  /// Produits suivis en réserve. [type] : '' (tous), 'REAPPRO' (rayon au-dessus du seuil réserve),
  /// 'REASSORT_RAYON' (rayon sous le seuil mini et réserve > 0).
  Future<PageArticles> articles(String recherche, {String type = '', int start = 0, int limit = 30}) async =>
      PageArticles.fromJson(await client.get('/reserve/articles', {
        'search_value': recherche.trim(),
        'str_TYPE_TRANSACTION': type,
        'start': start,
        'limit': limit,
      }));

  /// Produits que le serveur propose pour ce sens (onglets REAPPRO / REASSORT RAYON du web).
  Future<PageArticles> articlesProposes(SensReserve sens, {int limit = 100}) =>
      articles('', type: sens == SensReserve.versReserve ? 'REAPPRO' : 'REASSORT_RAYON', limit: limit);

  /// Article suivi en réserve correspondant exactement à un produit choisi dans la recherche de l'application.
  /// Null : le produit n'est pas suivi en réserve sur cet emplacement.
  Future<ArticleReserve?> articleDuProduit({required String familleId, required String cip}) async {
    final p = await articles(cip.isNotEmpty ? cip : familleId, limit: 50);
    for (final a in p.articles) {
      if (a.familleId == familleId) return a;
    }
    return null;
  }

  Future<List<MotifReserve>> motifs(SensReserve sens) async {
    final l = await client.getListe('/suggestion-reserve/motifs', {'categorie': sens.categorieApi});
    return [
      for (final o in objets(l))
        if (MotifReserve.fromJson(o) case final m?) m,
    ];
  }

  /// Suggestions encore à traiter sur l'emplacement de l'utilisateur.
  Future<List<EnteteSuggestion>> enAttente({int limit = 200}) async {
    final j = await client.get('/suggestion-reserve/en-attente', {'limit': limit});
    return [for (final o in objets(j['results'])) EnteteSuggestion.fromJson(o)]..removeWhere((s) => s.id.isEmpty);
  }

  /// Création (NON idempotente) : à n'appeler qu'une fois par panier ; un délai dépassé après l'envoi lève
  /// [ServeurInjoignable] avec `resultatIncertain` (ne pas renvoyer : relire [enAttente]).
  Future<ResultatCreation> creer(SensReserve sens, int motifId, String commentaire, List<LignePanier> panier) async {
    final r = ResultatCreation.fromJson(
        await client.post('/suggestion-reserve/creer', corpsCreation(sens, motifId, commentaire, panier), idempotent: false));
    if (r.id.isEmpty) throw const ReponseIllisible();
    return r;
  }

  Future<SuggestionOuverte> ouvrir(String id) async => SuggestionOuverte.fromJson(await client.put('/suggestion-reserve/${Uri.encodeComponent(id)}/ouvrir'));

  /// Libère le verrou (sans erreur : appelé en quittant l'écran).
  Future<void> liberer(String id) async {
    try {
      await client.put('/suggestion-reserve/${Uri.encodeComponent(id)}/liberer');
    } catch (_) {
      // Le verrou expire seul au bout de 20 minutes.
    }
  }

  /// Enregistre la quantité retenue d'une ligne (> 0 ; pour retirer une ligne : [retirerLigne]).
  Future<int> majQuantite(String detailId, int quantite) async {
    if (quantite <= 0) throw const RefusMetier('La quantité doit être supérieure à 0.');
    final j = await client.put('/suggestion-reserve/ligne/${Uri.encodeComponent(detailId)}/quantite', {'int_QTE': quantite});
    return entier(j['int_QTE_RETENUE']) ?? quantite;
  }

  Future<void> retirerLigne(String detailId, {String motif = 'Retirée depuis le mobile'}) async {
    await client.delete('/suggestion-reserve/ligne/${Uri.encodeComponent(detailId)}', {'motif': motif});
  }

  /// Traitement : déplace réellement le stock (sûr en cas de double envoi côté serveur : les lignes déjà
  /// traitées sont exclues).
  Future<CompteRendu> traiter(String id) async => CompteRendu.fromJson(await client.put('/suggestion-reserve/${Uri.encodeComponent(id)}/traiter'));

  /// Rejoue seulement les lignes en échec.
  Future<CompteRendu> reessayer(String id) async =>
      CompteRendu.fromJson(await client.put('/suggestion-reserve/${Uri.encodeComponent(id)}/reessayer'));
}
