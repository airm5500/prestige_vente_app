// Parcours de vente et catalogue FICTIF pour les tests de performance et réseau (application entière, faux
// serveur Prestige en mémoire) : catalogue de N produits fictifs servi par GET /vente/search (pages, « commence
// par » sur le nom ou le CIP, comme le serveur), modes de règlement, clôture d'une vente comptant, préventes à
// encaisser ; gestes : ajouter un produit au panier, encaisser en espèces.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_e2e.dart';

/// Produit fictif n° [i] : « PRODUIT 0007 CPR B/20 », CIP 34009 + 8 chiffres.
Map<String, dynamic> produitFictif(int i, {int stock = 50}) => {
      'lgFAMILLEID': 'F$i',
      'strNAME': 'PRODUIT ${i.toString().padLeft(4, '0')} CPR B/20',
      'intCIP': '34009${i.toString().padLeft(8, '0')}',
      'intPRICE': 1000 + i,
      'intNUMBERAVAILABLE': stock,
      'strLIBELLEE': 'FAMILLE TEST',
      'intPAF': 500,
    };

/// Nom tapé pour trouver UN seul produit (« PRODUIT 0007 »).
String nomCourt(int i) => 'PRODUIT ${i.toString().padLeft(4, '0')}';

/// Prévente fictive à encaisser n° [i].
Map<String, dynamic> preventeFictive(int i) => {
      'lgPREENREGISTREMENTID': 'PV$i',
      'heure': '${(8 + i % 10).toString().padLeft(2, '0')}:${(i % 60).toString().padLeft(2, '0')}:00',
      'dtUPDATED': '15/10/2026',
      'intPRICE': 1000 + 25 * i,
      'strREF': 'PV-${i.toString().padLeft(4, '0')}',
      'userFullName': 'Vendeur ${i % 7}',
      'lgTYPEVENTEID': '1',
    };

/// Installe sur [s] : catalogue de [nombre] produits (GET /vente/search par pages), modes de règlement
/// (Espèces, WAVE), clôture d'une vente comptant (POST /vente/cloturer/vno, comptée dans [clotures]) et
/// [preventes] préventes à encaisser. Les autres routes de vente (création, lignes, net) sont celles du faux
/// serveur Prestige.
class CatalogueFictif {
  final FauxServeurPrestige s;
  final List<Map<String, dynamic>> produits;
  int clotures = 0;
  Duration delaiRecherche = Duration.zero;
  Duration delaiCloture = Duration.zero;

  CatalogueFictif(this.s, {int nombre = 60, int preventes = 0}) : produits = [for (var i = 1; i <= nombre; i++) produitFictif(i)] {
    s.routes['GET /vente/search'] = (r) {
      final q = (r.query['query'] ?? '').toUpperCase().replaceAll('%', '');
      final l = [for (final p in produits) if ((p['strNAME'] as String).startsWith(q) || (p['intCIP'] as String).startsWith(q)) p];
      final start = int.tryParse(r.query['start'] ?? '0') ?? 0;
      final limit = int.tryParse(r.query['limit'] ?? '50') ?? 50;
      return FauxServeurPrestige.ok({'data': l.skip(start).take(limit).toList(), 'total': l.length}, delai: delaiRecherche);
    };
    s.routes['GET /common/reglement'] = (_) => FauxServeurPrestige.ok({
          'data': [
            {'lgTYPEREGLEMENTID': '1', 'strNAME': 'Espèces'},
            {'lgTYPEREGLEMENTID': '10', 'strNAME': 'WAVE'},
          ]
        });
    s.routes['POST /vente/cloturer/vno'] = (r) {
      clotures++;
      final id = '${r.json['venteId'] ?? ''}';
      if (s.statutVentes.containsKey(id)) s.statutVentes[id] = 'is_Closed';
      return FauxServeurPrestige.ok({'success': true}, delai: delaiCloture);
    };
    s.routes['POST /vente/update/client'] = (_) => FauxServeurPrestige.ok({'success': true});
    if (preventes > 0) {
      final liste = [for (var i = 1; i <= preventes; i++) preventeFictive(i)];
      s.routes['GET /ventestats/preventes'] = (_) => FauxServeurPrestige.ok({'data': liste, 'total': liste.length});
    }
  }
}

/// Préférences de l'appareil pour la vente : tous les menus visibles, espèces activées.
const prefsVente = <String, Object>{
  'hiddenMenuIds': <String>[],
  'enabled_payment_method_ids': ['1', '10'],
};

Finder get champRechercheVente => find.byKey(const ValueKey('vente-recherche'));
Finder get champQuantite => find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));

/// Ajoute au panier le produit trouvé par [texte] (un seul résultat → fenêtre de quantité) ; renvoie false si
/// la fenêtre de quantité n'est pas apparue dans [max].
Future<bool> ajouterAuPanier(WidgetTester t, AppE2E app, String texte, {String qte = '1', Duration max = const Duration(seconds: 5)}) async {
  await t.enterText(champRechercheVente, texte);
  if (!await app.attendreQue(t, champQuantite, max: max)) return false;
  await t.enterText(champQuantite, qte);
  await t.tap(find.text('Ajouter'));
  await t.pump();
  return true;
}

/// Page d'encaissement ouverte, espèces « Exact », sans impression, puis VALIDER (sans attendre la réponse).
Future<void> validerEncaissementEspeces(WidgetTester t, AppE2E app) async {
  await t.tap(find.byKey(const ValueKey('vente-encaisser')));
  expect(await app.attendreQue(t, find.text('Exact')), isTrue, reason: 'page d\'encaissement ouverte');
  await t.tap(find.text('Exact'));
  await t.pump();
  await t.tap(find.byKey(const ValueKey('encaissement-imprimer')));
  await t.pump();
  await t.tap(find.byKey(const ValueKey('encaissement-valider')));
  await t.pump();
}
