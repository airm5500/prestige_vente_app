// 4.9.1 — e2e, application entière (faux serveur Prestige en mémoire, données FICTIVES) : lecture GS1 dans les
// ventes Dépôt et Proforma, mêmes règles que la vente au comptant, SANS `lotScanne` (leurs routes d'ajout ne s'en
// servent pas : la clôture d'un dépôt ne sort pas de lot, une proforma ne sort pas de stock) :
//  - mode A et mode B lot différent : produit ajouté, avertissement neutre, aucun `lotScanne` ;
//  - mode C lot différent, périmée, étiquette étendue, sans produit : refusées, rien n'est ajouté ;
//  - lecture inactive, réglage absent (404), vente/gs1 absente (404) ou en panne (500) : comme avant ;
//  - code-barres classique : jamais vente/gs1 ; contenu scanné jamais journalisé.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/depot_model.dart';
import 'package:prestige_vente_app/api/models/proforma_models.dart';
import 'package:prestige_vente_app/providers/depot_sale_provider.dart';
import 'package:prestige_vente_app/providers/proforma_provider.dart';
import 'package:prestige_vente_app/screens/depot_sale/depot_sale_screen.dart';
import 'package:prestige_vente_app/screens/proforma/proforma_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

import 'outils/app_e2e.dart';
import 'outils/parcours_vente.dart';

final _doli = {...produitFictif(83), 'lgFAMILLEID': 'F83', 'strNAME': 'DOLI FICTIF 1000 CPR B/8', 'intCIP': '3400935955838'};
const _dm = '01034009359558381728103110LOTA1';

Map<String, dynamic> _gs1({String controle = 'DIFFERENT', String mode = 'A', bool lotEnStock = false, bool perime = false}) => {
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

/// Une vente : menu, écran de saisie prêt (dépôt choisi / type de devis et client choisis).
class _Vente {
  final String nom;
  final String menu;
  final String nouvelle;
  final String ajout;
  final Type ecran;
  final void Function(BuildContext) preparer;
  const _Vente(this.nom, this.menu, this.nouvelle, this.ajout, this.ecran, this.preparer);
}

final _ventes = [
  _Vente('Dépôt', 'depot', 'Nouvelle Vente', '/vente/add/depot', DepotSaleScreen, (c) {
    Provider.of<DepotSaleProvider>(c, listen: false).selectDepot(DepotModel.fromJson(const {
      'lgCLIENTID': 'D1',
      'strFIRSTNAME': 'DEPOT',
      'strLASTNAME': 'FICTIF',
      'strNAME': 'DEPOT FICTIF',
      'lgEMPLACEMENTID': 'E2',
      'lgTYPEDEPOTID': 'T1',
      'descriptionTypeDepot': 'Agréé',
    }));
  }),
  _Vente('Proforma', 'proforma', 'Nouveau Devis', '/vente/devis', ProformaScreen, (c) {
    // Type de devis choisi dans la liste (voir _ouvrir), client fixé ici.
    Provider.of<ProformaProvider>(c, listen: false).setClient(ClientModel(lgCLIENTID: 'C1', strFIRSTNAME: 'CLIENT', strLASTNAME: 'FICTIF'));
  }),
];

Future<AppE2E> _app({String? lecture = '1', Map<String, dynamic>? verdict, int statutGs1 = 200}) async {
  final app = AppE2E();
  final c = CatalogueFictif(app.serveur, nombre: 10);
  c.produits.add(_doli);
  final s = app.serveur;
  s.routes['GET /app-params/value/KEY_VENTE_LECTURE_GS1'] =
      (_) => lecture == null ? FauxServeurPrestige.payara404 : FauxServeurPrestige.ok({'success': true, 'data': lecture, 'total': 1});
  s.routes['GET /vente/gs1'] = (_) => statutGs1 != 200
      ? (statutGs1 == 404 ? FauxServeurPrestige.payara404 : ReponseLocale('<html>$statutGs1</html>', statut: statutGs1))
      : FauxServeurPrestige.ok(verdict ?? _gs1());
  s.routes['GET /magasin/find-depots'] = (_) => FauxServeurPrestige.ok({'data': [], 'total': 0});
  s.routes['GET /ventestats/preventes-depot'] = (_) => FauxServeurPrestige.ok({'data': [], 'total': 0});
  s.routes['POST /vente/add/depot'] =
      (_) => FauxServeurPrestige.ok({'success': true, 'data': {'lgPREENREGISTREMENTID': 'D-1', 'strREF': 'DEP-1'}});
  s.routes['GET /ventestats/devis'] = (_) => FauxServeurPrestige.ok({'data': [], 'total': 0});
  s.routes['GET /common/typedevis'] = (_) => FauxServeurPrestige.ok({'data': [{'lgTYPEVENTEID': '1', 'strNAME': 'VENTE AU COMPTANT', 'strDESCRIPTION': ''}]});
  s.routes['GET /common/typeremises'] = (_) => FauxServeurPrestige.ok({'data': [], 'total': 0});
  s.routes['POST /vente/devis'] =
      (_) => FauxServeurPrestige.ok({'success': true, 'data': {'lgPREENREGISTREMENTID': 'P-1', 'strREF': 'DEV-1'}});
  await app.preparer(prefs: prefsVente);
  return app;
}

Iterable<RequeteRecue> _gs1Appels(AppE2E app) => app.serveur.recues.where((r) => r.chemin.endsWith('/vente/gs1'));
List<RequeteRecue> _ajouts(AppE2E app, _Vente v) =>
    app.serveur.recues.where((r) => r.methode == 'POST' && r.chemin.endsWith(v.ajout)).toList();

final _champQte = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));
final _message = find.byKey(const Key('vente_message_gs1'));

Future<void> _ouvrir(WidgetTester t, AppE2E app, _Vente v) async {
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await app.ouvrirMenu(t, ListPresentation.dashboard, v.menu);
  await app.attendre(t);
  await t.tap(find.text(v.nouvelle).first);
  await app.attendre(t);
  expect(find.byType(v.ecran), findsOneWidget);
  if (v.ecran == ProformaScreen) {
    await t.tap(find.byType(DropdownButtonFormField<TypeDevis>));
    await app.attendre(t, const Duration(milliseconds: 500));
    await t.tap(find.text('VENTE AU COMPTANT').last);
    await app.attendre(t, const Duration(milliseconds: 500));
    // Le choix du type ouvre la recherche du client : client fixé par le test.
    if (find.text('Annuler').evaluate().isNotEmpty) {
      await t.tap(find.text('Annuler').last);
      await app.attendre(t, const Duration(milliseconds: 500));
    }
  }
  v.preparer(t.element(find.byType(v.ecran)));
  await app.attendre(t, const Duration(milliseconds: 500));
}

/// Saisie d'un code (recherche après 500 ms) : vrai si la fenêtre de quantité s'ouvre (produit trouvé exactement).
Future<bool> _scanner(WidgetTester t, AppE2E app, _Vente v, String code) async {
  await t.enterText(find.widgetWithText(TextField, 'Saisir nom ou scanner'), code);
  for (var i = 0; i < 30 && _champQte.evaluate().isEmpty && _message.evaluate().isEmpty; i++) {
    await app.attendre(t, const Duration(milliseconds: 200));
  }
  await t.pump();
  return _champQte.evaluate().isNotEmpty;
}

Future<void> _ajouter(WidgetTester t, AppE2E app) async {
  await t.enterText(_champQte, '1');
  await t.tap(find.text('Ajouter'));
  await app.attendre(t, const Duration(seconds: 2));
}

void main() {
  for (final v in _ventes) {
    group(v.nom, () {
      for (final (cas, verdict) in <(String, Map<String, dynamic>)>[
        ('mode A, lot différent', _gs1()),
        ('mode B, lot en stock', _gs1(mode: 'B', lotEnStock: true)),
      ]) {
        testWidgets('$cas : ajouté, avertissement, AUCUN « lotScanne »', (t) async {
          TailleEcran.sunmiV2s.appliquer(t);
          final app = await _app(verdict: verdict);
          await _ouvrir(t, app, v);
          expect(await _scanner(t, app, v, _dm), isTrue, reason: 'produit trouvé');
          expect(find.textContaining('Lot différent : boîte scannée lot LOTA1'), findsWidgets);
          expect(find.textContaining('sortira'), findsNothing, reason: 'aucun lot ne sera sorti par cette vente');
          await _ajouter(t, app);
          final a = _ajouts(app, v).single;
          expect(a.json['produitId'], 'F83');
          expect(a.json.containsKey('lotScanne'), isFalse);
          expect(_gs1Appels(app).single.query['code'], _dm);
          await app.fermer(t);
        });
      }

      for (final (cas, verdict, message) in <(String, Map<String, dynamic>, String)>[
        ('mode C, lot différent', _gs1(mode: 'C'), 'Prenez une boîte du lot LOTB2, péremption 30/06/2028'),
        ('boîte périmée', _gs1(controle: 'CONFORME', perime: true), 'Boîte périmée (31/01/2020) : non ajoutée'),
        ('étiquette étendue', {'success': false, 'actif': true, 'etendu': true, 'msg': 'Étiquette étendue (DataMatrix+ ou QR+) : réservée à la commande.'}, 'Étiquette étendue'),
        ('étiquette sans produit', {'success': false, 'actif': true, 'gs1': false, 'sansProduit': true, 'msg': 'Étiquette sans produit : lot LOTA1.'}, 'Étiquette sans produit'),
      ]) {
        testWidgets('$cas : refusée, rien ajouté, message clair', (t) async {
          TailleEcran.sunmiV2s.appliquer(t);
          final app = await _app(verdict: verdict);
          await _ouvrir(t, app, v);
          expect(await _scanner(t, app, v, _dm), isFalse, reason: 'pas de fenêtre de quantité');
          expect(_message, findsOneWidget);
          expect(find.textContaining(message), findsWidgets);
          await app.attendre(t, const Duration(seconds: 2));
          expect(_ajouts(app, v), isEmpty);
          await app.fermer(t);
        });
      }

      for (final (cas, lecture, statut) in <(String, String?, int)>[
        ('lecture inactive (0)', '0', 200),
        ('réglage absent (404)', null, 200),
        ('vente/gs1 absente (404)', '1', 404),
        ('vente/gs1 en panne (500)', '1', 500),
      ]) {
        testWidgets('$cas : comme avant, produit trouvé par l\'appareil, aucun refus', (t) async {
          TailleEcran.sunmiV2s.appliquer(t);
          final app = await _app(lecture: lecture, statutGs1: statut, verdict: _gs1(perime: true));
          await _ouvrir(t, app, v);
          expect(await _scanner(t, app, v, _dm), isTrue);
          expect(_message, findsNothing);
          await _ajouter(t, app);
          expect(_ajouts(app, v).single.json['produitId'], 'F83');
          if (lecture != '1') expect(_gs1Appels(app), isEmpty);
          await app.fermer(t);
        });
      }

      testWidgets('code-barres classique : jamais vente/gs1 ; contenu scanné jamais journalisé', (t) async {
        TailleEcran.sunmiV2s.appliquer(t);
        final journal = <String>[];
        final avant = debugPrint;
        debugPrint = (String? m, {int? wrapWidth}) => journal.add(m ?? '');
        final app = await _app(verdict: _gs1(mode: 'B', lotEnStock: true));
        await _ouvrir(t, app, v);
        expect(await _scanner(t, app, v, '3400935955838'), isTrue);
        await _ajouter(t, app);
        expect(_gs1Appels(app), isEmpty);
        expect(await _scanner(t, app, v, _dm), isTrue);
        await _ajouter(t, app);
        await app.fermer(t);
        debugPrint = avant;
        final tout = journal.join('\n');
        expect(tout, contains('GET /prestige/api/v1/vente/* → 200'));
        for (final x in ['LOTA1', '0103400935955838', '281031']) {
          expect(tout, isNot(contains(x)), reason: x);
        }
      });
    });
  }
}
