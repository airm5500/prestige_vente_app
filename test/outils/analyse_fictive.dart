// Données et application fictives de l'Analyse article / fiche produit (tests 4.3.2 : lenteur, ergonomie) :
// catalogue de 3 produits, GET /vente/search, GET /info « commence par » (comme le serveur), lent à volonté.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'app_e2e.dart';

const analyseDoli = 'DOLIPRANE 1000MG CP B/8';
const analyseDoliD = 'DOLIPRANE 1000MG CP B/8 DETAIL';
const analyseIbex = 'IBEX 200/325/30MG GEL B/24';

Map<String, dynamic> produitAnalyse(String id, String nom, String cip, int prix, int stock, {int paf = 976}) => {
      'lgFAMILLEID': id,
      'strNAME': nom,
      'intCIP': cip,
      'intPRICE': prix,
      'intNUMBERAVAILABLE': stock,
      'strLIBELLEE': 'ANTALGIQUES',
      'intPAF': paf,
    };

Map<String, dynamic> infoAnalyse(String id, String nom, String cip, String emplacement, {int stock = 18, int? reserve}) => {
      'produitId': id,
      'codeCip': cip,
      'libelle': nom,
      'emplacement': emplacement,
      'grossiste': 'LABOREX-CI YOP',
      'moyenne': 11.33,
      'prixAchat': 976,
      'prixVente': 1475,
      'quantiteVendue': 34,
      'stock': stock,
      'quantiteMois': '10:10,12:9,8:8',
      if (reserve != null) ...{'stockReserve': reserve, 'seuilReserve': 10, 'seuilMiniRayon': 5},
    };

final catalogueAnalyse = [
  produitAnalyse('F1', analyseDoli, '3595583', 1475, 18),
  produitAnalyse('F2', analyseDoliD, '3595583D', 200, 4),
  produitAnalyse('F3', analyseIbex, '8049052', 1435, 37, paf: 930),
];

/// GET /info?search= « commence par » sur le CIP ou le nom, comme le serveur.
List<Map<String, dynamic>> infoAnalyseSearch(String q) {
  final u = q.toUpperCase();
  bool m(String nom, String cip) => u.isNotEmpty && (cip.startsWith(u) || nom.startsWith(u));
  return [
    if (m(analyseDoliD, '3595583D')) infoAnalyse('F2', analyseDoliD, '3595583D', 'RAYON DETAIL', stock: 4),
    if (m(analyseDoli, '3595583')) infoAnalyse('F1', analyseDoli, '3595583', 'RAYON F-DOLI', reserve: 20),
    if (m(analyseIbex, '8049052')) infoAnalyse('F3', analyseIbex, '8049052', 'RAYON IBEX', stock: 37),
  ];
}

const lentAnalyse = Duration(seconds: 4);

AppE2E appAnalyse({Duration info = lentAnalyse, Duration images = Duration.zero}) {
  final app = AppE2E()..serveur.activerModules();
  app.serveur.routes['GET /vente/search'] = (r) {
    final q = (r.query['query'] ?? '').toUpperCase().replaceAll('%', '');
    final l = [for (final p in catalogueAnalyse) if ((p['strNAME'] as String).startsWith(q) || (p['intCIP'] as String).startsWith(q)) p];
    return FauxServeurPrestige.ok({'data': l, 'total': l.length});
  };
  app.serveur.routes['GET /info'] = (r) => FauxServeurPrestige.lent(infoAnalyseSearch(r.query['search'] ?? ''), info);
  if (images > Duration.zero) {
    for (final id in ['F1', 'F2', 'F3']) {
      app.serveur.routes['GET /produit-images/$id'] = (r) => FauxServeurPrestige.lent({'success': true, 'data': []}, images);
    }
  }
  return app;
}

Future<AppE2E> lancerAnalyse(WidgetTester t,
    {Duration info = lentAnalyse,
    Duration images = Duration.zero,
    ListPresentation style = ListPresentation.dashboard,
    TailleEcran ecran = TailleEcran.sunmiV2s}) async {
  ecran.appliquer(t);
  FicheInfoCache.instance.vider();
  addTearDown(FicheInfoCache.instance.vider);
  final app = appAnalyse(info: info, images: images);
  await app.preparer(prefs: {'hiddenMenuIds': <String>[], 'presentation_listes_v1': style.name});
  await app.lancer(t);
  expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
  await app.attendre(t);
  return app;
}

Future<void> frappeAnalyse(WidgetTester t, String texte) async {
  for (var i = 1; i <= texte.length; i++) {
    await t.enterText(find.byType(TextField).first, texte.substring(0, i));
    await t.pump(const Duration(milliseconds: 100));
  }
}

