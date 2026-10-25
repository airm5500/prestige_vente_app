// 4.9.0 — e2e, application entière (faux serveur Prestige en mémoire, données FICTIVES) : étiquettes GS1 à la vente
// alignées sur le web. Réglage KEY_VENTE_LECTURE_GS1 (GET v1/app-params/value), verdict GET v1/vente/gs1 :
//  - mode A lot différent : ajouté, avertissement ; mode B lot en stock : `lotScanne` dans l'ajout de la ligne ;
//    mode C lot différent : refusé « Prenez une boîte du lot… » ; périmée, étiquette étendue, sans produit : refusés ;
//  - lecture inactive (0), serveur ancien (404), panne de vente/gs1 : comportement d'avant (produit trouvé par le
//    décodage de l'appareil, aucun refus) ;
//  - hors ligne (lecture active) : boîte périmée refusée par sa date ;
//  - ancienne interface des ventes : l'étiquette GS1 est trouvée, refus affichés ;
//  - le contenu scanné n'apparaît jamais dans le journal de la console.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart' show CatalogueCategorie;
import 'package:prestige_vente_app/ventes/core/gs1_vente.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';
import 'outils/parcours_vente.dart';

/// Produit FICTIF au CIP13 valide (clé EAN juste) : DataMatrix « 01 0 3400935955838 … ».
final _doli = {...produitFictif(83), 'lgFAMILLEID': 'F83', 'strNAME': 'DOLI FICTIF 1000 CPR B/8', 'intCIP': '3400935955838'};
const _dm = '0103400935955838\u001d17281031\u001d10LOTA1';
const _dmPerime = '010340093595583817200131\u001d10LOTX';

Map<String, dynamic> _gs1({String controle = 'CONFORME', String mode = 'A', bool lotEnStock = false, bool perime = false}) => {
      'success': true,
      'actif': true,
      'gs1': true,
      'lot': 'LOTA1',
      'peremption': perime ? '31/01/2020' : '31/10/2028',
      'perime': perime,
      'cip': '3400935955838',
      'gtin': '03400935955838',
      'lotPrevu': 'LOTB2',
      'peremptionPrevue': '30/06/2028',
      'controle': controle,
      'modeControle': mode,
      'lotEnStock': lotEnStock,
      'data': {'lgFAMILLEID': 'F83', 'intCIP': '3400935955838'},
    };

Future<(AppE2E, CatalogueFictif)> _app({String? lecture = '1', Map<String, dynamic>? verdict, int statutGs1 = 200, bool ancienne = false}) async {
  final app = AppE2E();
  app.serveur.droitsComptes = {
    DonneesFictives.login: ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE'],
  };
  final c = CatalogueFictif(app.serveur, nombre: 10);
  c.produits.add(_doli);
  app.serveur.routes['GET /app-params/value/KEY_VENTE_LECTURE_GS1'] =
      (_) => lecture == null ? FauxServeurPrestige.payara404 : FauxServeurPrestige.ok({'success': true, 'data': lecture, 'total': 1});
  app.serveur.routes['GET /vente/gs1'] = (_) => statutGs1 != 200
      ? (statutGs1 == 404 ? FauxServeurPrestige.payara404 : ReponseLocale('<html>$statutGs1</html>', statut: statutGs1))
      : FauxServeurPrestige.ok(verdict ?? _gs1());
  await app.preparer(prefs: {...prefsVente, if (ancienne) 'ventes_nouvelle_version_v1': false});
  return (app, c);
}

Iterable<RequeteRecue> _gs1Appels(AppE2E app) => app.serveur.recues.where((r) => r.chemin.endsWith('/vente/gs1'));

int _ajouts(AppE2E app) => app.serveur.recues.where((r) => r.methode == 'POST' && RegExp(r'/vente/add/(vno|item)$').hasMatch(r.chemin)).length;

/// Scan (code saisi d'un bloc) : un code exact est ajouté directement (quantité 1), comme avant. Vrai si une ligne
/// est partie au serveur.
/// [message] : attendu à l'écran (attente arrêtée dès qu'il paraît, avant que le bandeau ne s'efface).
Future<bool> _scanner(WidgetTester t, AppE2E app, String code, {String? message}) async {
  final avant = _ajouts(app);
  await t.enterText(champRechercheVente, code);
  var vu = message == null;
  for (var i = 0; i < 25 && (_ajouts(app) == avant || !vu); i++) {
    await app.attendre(t, const Duration(milliseconds: 200));
    if (!vu && find.textContaining(message!).evaluate().isNotEmpty) {
      vu = true;
      if (_ajouts(app) == avant) break;
    }
  }
  if (message != null) expect(vu, isTrue, reason: 'message affiché : $message');
  await app.attendre(t, const Duration(milliseconds: 300));
  return _ajouts(app) > avant;
}

RequeteRecue _derniereLigne(AppE2E app) =>
    app.serveur.recues.lastWhere((r) => r.methode == 'POST' && RegExp(r'/vente/add/(vno|item)$').hasMatch(r.chemin));

Future<void> _vente(WidgetTester t, AppE2E app) async {
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
  await app.attendre(t);
}

void main() {
  testWidgets('mode A, lot différent : produit ajouté avec un avertissement, aucun lot envoyé', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, _) = await _app(verdict: _gs1(controle: 'DIFFERENT'));
    await _vente(t, app);
    expect(Gs1Vente.instance.actif, isTrue, reason: 'réglage lu à la connexion');
    expect(await _scanner(t, app, _dm, message: 'Lot différent'), isTrue, reason: 'ajouté, avertissement au vendeur');
    final ajout = _derniereLigne(app);
    expect(ajout.json['produitId'], 'F83');
    expect(ajout.json.containsKey('lotScanne'), isFalse);
    // Le champ de recherche retire les caractères de contrôle (GS) depuis toujours : le serveur reçoit la forme du
    // web (AI 10 en dernier, sans ambiguïté).
    expect(_gs1Appels(app).single.query['code'], _dm.replaceAll('\u001d', ''));
    await app.fermer(t);
  });

  testWidgets('mode B, lot en stock : « lotScanne » envoyé avec la ligne, une seule fois', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, _) = await _app(verdict: _gs1(controle: 'DIFFERENT', mode: 'B', lotEnStock: true));
    await _vente(t, app);
    expect(await _scanner(t, app, _dm), isTrue);
    expect(_derniereLigne(app).json['lotScanne'], 'LOTA1');
    // Même produit ajouté ensuite par son nom : plus de lot.
    expect(await _scanner(t, app, '3400935955838'), isTrue);
    expect(_derniereLigne(app).json.containsKey('lotScanne'), isFalse, reason: 'lot pris une seule fois');
    await app.fermer(t);
  });

  for (final (cas, verdict, message) in <(String, Map<String, dynamic>, String)>[
    ('mode C, lot différent', _gs1(controle: 'DIFFERENT', mode: 'C'), 'Prenez une boîte du lot LOTB2, péremption 30/06/2028'),
    ('boîte périmée', _gs1(perime: true), 'Boîte périmée (31/01/2020) : non ajoutée'),
    ('étiquette étendue', {'success': false, 'actif': true, 'etendu': true, 'msg': 'Étiquette étendue (DataMatrix+ ou QR+) : réservée à la commande.'}, 'Étiquette étendue'),
    ('étiquette sans produit', {'success': false, 'actif': true, 'gs1': false, 'sansProduit': true, 'msg': 'Étiquette sans produit : lot LOTA1.'}, 'Étiquette sans produit'),
  ]) {
    testWidgets('$cas : refusée, rien ajouté, message clair', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final (app, _) = await _app(verdict: verdict);
      await _vente(t, app);
      expect(await _scanner(t, app, _dm, message: message), isFalse, reason: 'rien n\'est ajouté');
      await app.attendre(t, const Duration(seconds: 2));
      expect(_ajouts(app), 0);
      await app.fermer(t);
    });
  }

  for (final (cas, lecture, statut) in <(String, String?, int)>[
    ('lecture inactive (0)', '0', 200),
    ('réglage absent (serveur ancien, 404)', null, 200),
    ('vente/gs1 absente (404)', '1', 404),
    ('vente/gs1 en panne (500)', '1', 500),
  ]) {
    testWidgets('$cas : comportement d\'avant, produit trouvé par l\'appareil, aucun refus', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      // Le verdict « périmé » n'est JAMAIS appliqué quand la lecture n'aboutit pas.
      final (app, _) = await _app(lecture: lecture, statutGs1: statut, verdict: _gs1(perime: true));
      await _vente(t, app);
      expect(await _scanner(t, app, _dm), isTrue, reason: 'produit trouvé comme avant');
      expect(_derniereLigne(app).json['produitId'], 'F83');
      if (lecture != '1') expect(_gs1Appels(app), isEmpty, reason: 'lecture inactive : jamais vente/gs1');
      final recherches = app.serveur.recuesSur('/vente/search').map((r) => r.query['query']).toList();
      expect(recherches, contains('3400935955838'), reason: 'GTIN → EAN-13, comme avant');
      await app.fermer(t);
    });
  }

  testWidgets('code-barres classique et nom : jamais vente/gs1', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, _) = await _app();
    await _vente(t, app);
    expect(await _scanner(t, app, '3400935955838'), isTrue);
    expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
    expect(_gs1Appels(app), isEmpty);
    await app.fermer(t);
  });

  testWidgets('hors ligne, lecture active : boîte périmée refusée par sa date, boîte valide ajoutée', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, _) = await _app();
    await _vente(t, app);
    await app.horsLigne.store.replace(CatalogueCategorie.produits, [for (var i = 1; i <= 10; i++) produitFictif(i), _doli], DateTime.now());
    await app.horsLigne.sync.refreshStats();
    await app.serveur.couper();
    expect(await app.attendreQue(t, find.text('Continuer hors ligne'), max: const Duration(minutes: 3)), isTrue);
    await t.tap(find.text('Continuer hors ligne'));
    await app.attendre(t);
    expect(await _scanner(t, app, _dmPerime, message: 'Boîte périmée (31/01/2020) : non ajoutée'), isFalse);
    // Boîte valide : produit trouvé dans la copie locale et ajouté (lot non contrôlé hors ligne), sans requête.
    await t.enterText(champRechercheVente, _dm);
    final champQte = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));
    final ajoute = find.textContaining('DOLI FICTIF 1000 CPR B/8 ajouté');
    for (var i = 0; i < 25 && champQte.evaluate().isEmpty && ajoute.evaluate().isEmpty; i++) {
      await app.attendre(t, const Duration(milliseconds: 200));
    }
    if (champQte.evaluate().isNotEmpty) {
      await t.enterText(champQte, '1');
      await t.tap(find.text('Ajouter'));
      await app.attendre(t);
    } else {
      expect(ajoute, findsWidgets, reason: 'boîte valide : ajoutée');
    }
    expect(find.textContaining('Boîte périmée'), findsNothing);
    await app.fermer(t);
  });

  testWidgets('ancienne interface des ventes : étiquette GS1 trouvée ; boîte périmée refusée', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, _) = await _app(verdict: _gs1(perime: true), ancienne: true);
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    await t.tap(find.text('VENTE'));
    await app.attendre(t);
    final champ = find.widgetWithText(TextField, 'Rechercher (Nom/CIP)');
    await t.enterText(champ, _dm);
    await app.attendre(t, const Duration(seconds: 2));
    expect(find.byKey(const Key('vente_message_gs1')), findsOneWidget);
    expect(find.textContaining('Boîte périmée (31/01/2020) : non ajoutée'), findsWidgets);
    await app.fermer(t);
  });

  testWidgets('ancienne interface, lecture inactive : l\'étiquette GS1 est maintenant trouvée (décodage de l\'appareil)', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, _) = await _app(lecture: '0', ancienne: true);
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    await t.tap(find.text('VENTE'));
    await app.attendre(t);
    await t.enterText(find.widgetWithText(TextField, 'Rechercher (Nom/CIP)'), _dm);
    await app.attendre(t, const Duration(seconds: 2));
    expect(find.textContaining('DOLI FICTIF'), findsWidgets, reason: 'produit proposé');
    expect(_gs1Appels(app), isEmpty);
    await app.fermer(t);
  });

  testWidgets('le contenu scanné n\'apparaît jamais dans le journal de la console', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final journal = <String>[];
    final avant = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => journal.add(m ?? '');
    final (app, _) = await _app(verdict: _gs1(controle: 'DIFFERENT', mode: 'B', lotEnStock: true));
    await _vente(t, app);
    expect(await _scanner(t, app, _dm), isTrue);
    await app.fermer(t);
    debugPrint = avant;
    final tout = journal.join('\n');
    // « gs1 » contient un chiffre : masqué comme une valeur (jamais de paramètre ni de contenu).
    expect(tout, contains('GET /prestige/api/v1/vente/* → 200'), reason: 'la requête est journalisée (chemin seul)');
    for (final x in ['LOTA1', '0103400935955838', '281031']) {
      expect(tout, isNot(contains(x)), reason: x);
    }
  });
}
