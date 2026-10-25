// 4.9.2 — e2e, application entière (faux serveur Prestige en mémoire, données FICTIVES) : étiquette étendue
// (DataMatrix+, QR+) refusée comme le web MÊME lecture GS1 inactive ou absente, sans requête :
//  - vente au comptant (nouvelle interface) : lecture 0, réglage absent, lecture 1, hors ligne ;
//  - ancienne interface des ventes ; Proforma ;
//  - Dépôt (le web ne la refuse pas dans DepotCtr) : comme avant ;
//  - étiquette GS1 normale, code-barres, nom, lecture inactive : comme avant ; contenu scanné jamais journalisé.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/depot_model.dart';
import 'package:prestige_vente_app/api/models/proforma_models.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart' show CatalogueCategorie;
import 'package:prestige_vente_app/providers/depot_sale_provider.dart';
import 'package:prestige_vente_app/providers/proforma_provider.dart';
import 'package:prestige_vente_app/screens/depot_sale/depot_sale_screen.dart';
import 'package:prestige_vente_app/screens/proforma/proforma_screen.dart';
import 'package:prestige_vente_app/ventes/core/gs1_vente.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

import 'outils/app_e2e.dart';
import 'outils/parcours_vente.dart';

final _doli = {...produitFictif(83), 'lgFAMILLEID': 'F83', 'strNAME': 'DOLI FICTIF 1000 CPR B/8', 'intCIP': '3400935955838'};

/// Étiquettes saisies au champ de recherche (le champ retire les caractères de contrôle : séparateurs « | » de la
/// douchette, comme les formes reconnues par le web).
const _dmPlus = '0103400935955838|17281031|10LOTA1|91EPLUS1|92DOLI_FICTIF|931250';
const _qrPlus = 'EP1|CIP:3400935955838|NOM:DOLI FICTIF|PRIX:1250|LOT:LOTA1|PER:31/10/2028';
const _dm = '01034009359558381728103110LOTA1';

Future<AppE2E> _app({String? lecture = '0', bool ancienne = false}) async {
  final app = AppE2E();
  final c = CatalogueFictif(app.serveur, nombre: 10);
  c.produits.add(_doli);
  final s = app.serveur;
  s.routes['GET /app-params/value/KEY_VENTE_LECTURE_GS1'] =
      (_) => lecture == null ? FauxServeurPrestige.payara404 : FauxServeurPrestige.ok({'success': true, 'data': lecture, 'total': 1});
  s.routes['GET /vente/gs1'] = (_) => FauxServeurPrestige.ok({
        'success': true, 'actif': true, 'lot': 'LOTA1', 'peremption': '31/10/2028', 'perime': false, 'cip': '3400935955838',
        'controle': 'CONFORME', 'modeControle': 'A', 'lotEnStock': false, 'data': {'lgFAMILLEID': 'F83'},
      });
  s.routes['GET /magasin/find-depots'] = (_) => FauxServeurPrestige.ok({'data': [], 'total': 0});
  s.routes['GET /ventestats/preventes-depot'] = (_) => FauxServeurPrestige.ok({'data': [], 'total': 0});
  s.routes['POST /vente/add/depot'] =
      (_) => FauxServeurPrestige.ok({'success': true, 'data': {'lgPREENREGISTREMENTID': 'D-1', 'strREF': 'DEP-1'}});
  s.routes['GET /ventestats/devis'] = (_) => FauxServeurPrestige.ok({'data': [], 'total': 0});
  s.routes['GET /common/typedevis'] = (_) => FauxServeurPrestige.ok({'data': [{'lgTYPEVENTEID': '1', 'strNAME': 'VENTE AU COMPTANT', 'strDESCRIPTION': ''}]});
  s.routes['GET /common/typeremises'] = (_) => FauxServeurPrestige.ok({'data': [], 'total': 0});
  s.routes['POST /vente/devis'] =
      (_) => FauxServeurPrestige.ok({'success': true, 'data': {'lgPREENREGISTREMENTID': 'P-1', 'strREF': 'DEV-1'}});
  await app.preparer(prefs: {...prefsVente, if (ancienne) 'ventes_nouvelle_version_v1': false});
  return app;
}

Iterable<RequeteRecue> _gs1Appels(AppE2E app) => app.serveur.recues.where((r) => r.chemin.endsWith('/vente/gs1'));
int _ajouts(AppE2E app) =>
    app.serveur.recues.where((r) => r.methode == 'POST' && RegExp(r'/vente/(add/(vno|item|depot|assurance)|devis)$').hasMatch(r.chemin)).length;
final _refus = find.textContaining('Cette étiquette (DataMatrix+ ou QR+) est réservée à la commande');
final _champQte = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));

Future<void> _vente(WidgetTester t, AppE2E app) async {
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
  await app.attendre(t);
}

/// Saisie dans [champ] ; attend le refus, un ajout ou la fenêtre de quantité. Vrai si le refus est affiché.
Future<bool> _saisir(WidgetTester t, AppE2E app, Finder champ, String code) async {
  final avant = _ajouts(app);
  await t.enterText(champ, code);
  for (var i = 0; i < 25 && _refus.evaluate().isEmpty && _ajouts(app) == avant && _champQte.evaluate().isEmpty; i++) {
    await app.attendre(t, const Duration(milliseconds: 200));
  }
  return _refus.evaluate().isNotEmpty;
}

void main() {
  for (final (cas, lecture) in <(String, String?)>[
    ('lecture inactive (0)', '0'),
    ('réglage absent (serveur ancien)', null),
    ('lecture active (1)', '1'),
  ]) {
    testWidgets('vente au comptant, $cas : DataMatrix+ et QR+ refusés, rien ajouté, aucune requête', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = await _app(lecture: lecture);
      await _vente(t, app);
      for (final e in [_dmPlus, _qrPlus]) {
        expect(await _saisir(t, app, champRechercheVente, e), isTrue, reason: e.substring(0, 4));
        await app.attendre(t, const Duration(seconds: 7)); // bandeau de 6 s
      }
      expect(_ajouts(app), 0);
      expect(_gs1Appels(app), isEmpty, reason: 'reconnue sur l\'appareil');
      expect(app.serveur.recuesSur('/vente/search').map((r) => r.query['query']).where((q) => q != '%').toList(), isEmpty,
          reason: 'aucune recherche de produit (« % » : copie hors ligne du catalogue)');
      await app.fermer(t);
    });
  }

  testWidgets('lecture inactive : étiquette GS1 normale, code-barres et nom comme avant', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = await _app();
    await _vente(t, app);
    expect(await _saisir(t, app, champRechercheVente, _dm), isFalse);
    expect(_ajouts(app), 1, reason: 'étiquette normale : ajoutée comme avant');
    await app.attendre(t, const Duration(seconds: 3));
    expect(await _saisir(t, app, champRechercheVente, '3400935955838'), isFalse);
    expect(_ajouts(app), 2);
    expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
    expect(_gs1Appels(app), isEmpty);
    expect(_refus, findsNothing);
    await app.fermer(t);
  });

  testWidgets('hors ligne, lecture inactive : DataMatrix+ refusé sur l\'appareil', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = await _app();
    await _vente(t, app);
    await app.horsLigne.store.replace(CatalogueCategorie.produits, [for (var i = 1; i <= 10; i++) produitFictif(i), _doli], DateTime.now());
    await app.horsLigne.sync.refreshStats();
    await app.serveur.couper();
    expect(await app.attendreQue(t, find.text('Continuer hors ligne'), max: const Duration(minutes: 3)), isTrue);
    await t.tap(find.text('Continuer hors ligne'));
    await app.attendre(t);
    expect(Gs1Vente.instance.actif, isFalse);
    expect(await _saisir(t, app, champRechercheVente, _dmPlus), isTrue);
    expect(_champQte, findsNothing);
    await app.fermer(t);
  });

  testWidgets('ancienne interface des ventes, lecture inactive : QR+ refusé', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = await _app(ancienne: true);
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    await t.tap(find.text('VENTE'));
    await app.attendre(t);
    await t.enterText(find.widgetWithText(TextField, 'Rechercher (Nom/CIP)'), _qrPlus);
    await app.attendre(t, const Duration(seconds: 2));
    expect(find.byKey(const Key('vente_message_gs1')), findsOneWidget);
    expect(_refus, findsWidgets);
    expect(_gs1Appels(app), isEmpty);
    await app.fermer(t);
  });

  Future<void> ouvrirProforma(WidgetTester t, AppE2E app) async {
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'proforma');
    await app.attendre(t);
    await t.tap(find.text('Nouveau Devis').first);
    await app.attendre(t);
    await t.tap(find.byType(DropdownButtonFormField<TypeDevis>));
    await app.attendre(t, const Duration(milliseconds: 500));
    await t.tap(find.text('VENTE AU COMPTANT').last);
    await app.attendre(t, const Duration(milliseconds: 500));
    if (find.text('Annuler').evaluate().isNotEmpty) {
      await t.tap(find.text('Annuler').last);
      await app.attendre(t, const Duration(milliseconds: 500));
    }
    Provider.of<ProformaProvider>(t.element(find.byType(ProformaScreen)), listen: false)
        .setClient(ClientModel(lgCLIENTID: 'C1', strFIRSTNAME: 'CLIENT', strLASTNAME: 'FICTIF'));
    await app.attendre(t, const Duration(milliseconds: 500));
  }

  testWidgets('Proforma, lecture inactive : DataMatrix+ et QR+ refusés, rien ajouté', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = await _app();
    await ouvrirProforma(t, app);
    final champ = find.widgetWithText(TextField, 'Saisir nom ou scanner');
    for (final e in [_dmPlus, _qrPlus]) {
      expect(await _saisir(t, app, champ, e), isTrue);
      expect(find.byKey(const Key('vente_message_gs1')), findsOneWidget);
      expect(_champQte, findsNothing);
      await app.attendre(t, const Duration(seconds: 7));
    }
    expect(_ajouts(app), 0);
    expect(_gs1Appels(app), isEmpty);
    await app.fermer(t);
  });

  testWidgets('Dépôt, lecture inactive : comme avant (le web ne refuse pas l\'étiquette étendue dans DepotCtr)', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = await _app();
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'depot');
    await app.attendre(t);
    await t.tap(find.text('Nouvelle Vente').first);
    await app.attendre(t);
    Provider.of<DepotSaleProvider>(t.element(find.byType(DepotSaleScreen)), listen: false).selectDepot(DepotModel.fromJson(const {
      'lgCLIENTID': 'D1', 'strNAME': 'DEPOT FICTIF', 'lgEMPLACEMENTID': 'E2', 'lgTYPEDEPOTID': 'T1',
    }));
    await app.attendre(t, const Duration(milliseconds: 500));
    expect(await _saisir(t, app, find.widgetWithText(TextField, 'Saisir nom ou scanner'), _dmPlus), isFalse);
    await app.attendre(t, const Duration(seconds: 2));
    expect(_refus, findsNothing);
    expect(find.byKey(const Key('vente_message_gs1')), findsNothing);
    expect(app.serveur.recuesSur('/vente/search').where((r) => r.query['query'] != '%'), isNotEmpty, reason: 'recherche d\'avant');
    expect(_gs1Appels(app), isEmpty);
    await app.fermer(t);
  });

  testWidgets('le contenu de l\'étiquette étendue n\'apparaît jamais dans le journal', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final journal = <String>[];
    final avant = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => journal.add(m ?? '');
    final app = await _app(lecture: '1');
    await _vente(t, app);
    expect(await _saisir(t, app, champRechercheVente, _qrPlus), isTrue);
    expect(await _saisir(t, app, champRechercheVente, _dmPlus), isTrue);
    await app.fermer(t);
    debugPrint = avant;
    final tout = journal.join('\n');
    expect(tout, isNotEmpty);
    for (final x in ['EPLUS1', 'EP1|', 'LOTA1', 'DOLI_FICTIF', '3400935955838']) {
      expect(tout, isNot(contains(x)), reason: x);
    }
  });
}
