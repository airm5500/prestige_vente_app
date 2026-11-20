// Captures du MAGASIN (Sunmi App Store, Google Play) de Prestige Mobile V3 (5.0.0) : rendu Flutter RÉEL des écrans de
// l'application (application entière contre le faux serveur Prestige en mémoire, ou écran monté avec son faux serveur
// pour la vente assurance), données FICTIVES uniquement. Polices réelles (Roboto, icônes Material) chargées avant le
// rendu : aucun bloc à la place du texte.
//   1. connexion ; 2. vente au comptant (saisie) ; 3. vente assurance (organisme, bon) ; 4. encaissement : mobile money
//   (Wave) et remise ; 5. réception de BL.
// Terminal Sunmi V2s portrait 720 × 1440 (densité 2) et tablette paysage 1920 × 1200 (densité 1,5).
// Hors de la suite de la CI (ignoré sans APERCUS). Pour régénérer :
//   APERCUS=1 CAPTURES=/dossier flutter test test/outils/captures_store_v3_test.dart --update-goldens
// → /dossier/mobile/terminal/*.png et /dossier/mobile/tablette/*.png
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/connexion/connexion_reglages.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ventes_assurance_ui_test.dart'
    show FauxGatewayAssurance, ouvrirAssurancePourCaptures, tiersPayantPourCaptures, ayantDroitPourCaptures, produitPourCaptures;
import 'app_e2e.dart';
import 'parcours_vente.dart';
import 'remises_fictives.dart';
import 'version_installee.dart';

final _actif = Platform.environment.containsKey('APERCUS');
final _base = Platform.environment['CAPTURES'] ?? '/tmp/captures_store_v3';

/// Polices réelles : Roboto pour toutes les familles que le moteur de test peut demander, icônes Material.
Future<void> chargerPolicesReelles() async {
  final dossier = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<ByteData> lire(String f) async => ByteData.sublistView(await File('$dossier/$f').readAsBytes());
  for (final famille in ['Roboto', 'FlutterTest', '', 'Ahem', 'sans-serif', 'Roboto Flex', '.SF UI Text', '.SF UI Display']) {
    final l = FontLoader(famille);
    for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf', 'Roboto-Light.ttf', 'Roboto-Italic.ttf']) {
      l.addFont(lire(f));
    }
    await l.load();
  }
  await (FontLoader('MaterialIcons')..addFont(lire('MaterialIcons-Regular.otf'))).load();
}

/// Rendu fidèle au terminal avant la capture :
///  - images (logo, logos des modes de paiement) décodées pour de bon (sinon cadres vides) ;
///  - texte SANS famille de police (styles de boutons sans `fontFamily`) : sur Android il s'affiche en Roboto, mais le
///    moteur de test le dessine avec sa police de blocs (Ahem), que FontLoader ne remplace pas. Ces paragraphes
///    reçoivent donc Roboto (police réelle d'Android), seulement pour la capture ;
///  - ombres réelles (le moteur de test les remplace sinon par des traits noirs).
Future<void> capturerFidele(WidgetTester t, Finder cible, Uri fichier) async {
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate().toList()) {
      try {
        await precacheImage((e.widget as Image).image, e);
      } catch (_) {}
    }
  });
  await t.pump();
  void visiter(RenderObject r) {
    if (r is RenderParagraph) {
      final texte = r.text;
      if (!(texte is TextSpan && texte.style?.debugLabel == 'capture-roboto')) {
        r.text = TextSpan(style: const TextStyle(fontFamily: 'Roboto', debugLabel: 'capture-roboto'), children: [texte]);
      }
    }
    r.markNeedsPaint();
    r.visitChildren(visiter);
  }

  for (final v in t.binding.renderViews) {
    visiter(v);
  }
  debugDisableShadows = false;
  try {
    await t.pump();
    await expectLater(cible, matchesGoldenFile(fichier));
  } finally {
    debugDisableShadows = true;
    for (final v in t.binding.renderViews) {
      v.visitChildren((r) => r.markNeedsPaint());
    }
  }
}

Future<void> _capture(WidgetTester t, String dossier, String nom) =>
    capturerFidele(t, find.byType(MaterialApp).first, Uri.file('$_base/mobile/$dossier/$nom.png'));

/// Produits fictifs (dénominations communes, aucun nom de marque), prix en F CFA.
const _noms = [
  ('PARACETAMOL FICTIF 1000MG CPR B/8', 1250),
  ('AMOXICILLINE FICTIVE 500MG GEL B/12', 2850),
  ('VITAMINE C FICTIVE 500MG CPR B/20', 1900),
  ('SIROP TOUX FICTIF 125ML', 3200),
  ('SERUM PHYSIO FICTIF 5ML B/40', 2400),
];

CatalogueFictif _catalogue(AppE2E app) {
  final c = CatalogueFictif(app.serveur, nombre: 12);
  for (var i = 0; i < _noms.length; i++) {
    c.produits[i]['strNAME'] = _noms[i].$1;
    c.produits[i]['intPRICE'] = _noms[i].$2;
  }
  // Lignes du panier : nom et CIP du produit fictif choisi (le faux serveur ne garde que son identifiant).
  app.serveur.routes['GET /vente/deatails'] = (r) {
    final l = app.serveur.ventes[r.query['venteId']] ?? const <Map<String, dynamic>>[];
    for (final ligne in l) {
      final p = c.produits.where((p) => p['lgFAMILLEID'] == ligne['lgFAMILLEID']).firstOrNull;
      if (p != null) {
        ligne['strNAME'] = p['strNAME'];
        ligne['intCIP'] = p['intCIP'];
      }
    }
    return ReponseLocale({'data': l, 'total': l.length});
  };
  return c;
}

Future<AppE2E> _app(WidgetTester t, TailleEcran taille, {void Function(AppE2E)? routes}) async {
  taille.appliquer(t);
  final app = AppE2E(serveur: FauxServeurPrestige(comptes: {DonneesFictives.login: DonneesFictives.motDePasse, DonneesFictives.admin: DonneesFictives.motDePasseAdmin}));
  _catalogue(app);
  RemisesFictives(app.serveur);
  routes?.call(app);
  simulerVersionInstallee(); // « Version 5.0.0+49 » (pubspec.yaml) au bas de la connexion
  await app.preparer(prefs: {
    ...prefsVente,
    'enabled_payment_method_ids': ['1', '10', '7'],
    ConnexionReglages.cleOfficine: 'PHARMACIE DÉMO',
    'reception_bl_settings_v1': jsonEncode({'shortExpiryMonths': 6, 'terminalValidation': true}),
  });
  return app;
}

Future<void> _ajouter(WidgetTester t, AppE2E app, String nom, String qte) async {
  expect(await ajouterAuPanier(t, app, nom, qte: qte), isTrue, reason: nom);
  await app.attendre(t, const Duration(seconds: 2));
}

Map<String, dynamic> _ligneBl(String id, String nom, String cip, int cmde, {int saisie = 0, String lots = ''}) => {
      'lg_BON_LIVRAISON_DETAIL': id,
      'lg_FAMILLE_ID': 'F$id',
      'lg_FAMILLE_NAME': nom,
      'lg_FAMILLE_CIP': cip,
      'int_QTE_CMDE': cmde,
      'quantiteSaisie': saisie,
      'freeQty': 0,
      'lots': lots,
      'datePeremption': '',
      'str_REF_LIVRAISON': 'BL-DEMO-0425',
      'int_QTE_RECUE_BIS': -1,
    };

void _routesReception(AppE2E app) {
  final s = app.serveur;
  final lignes = [
    _ligneBl('D1', _noms[0].$1, '3595583', 24),
    _ligneBl('D2', _noms[1].$1, '3000001', 10, saisie: 10, lots: 'A21'),
    _ligneBl('D3', _noms[2].$1, '3000002', 12, saisie: 6, lots: 'C07'),
  ];
  s.routes['GET /commande/list'] = (_) => const ReponseLocale({
        'data': [
          {'lg_ORDER_ID': 'O1', 'str_REF_ORDER': 'CMD-DEMO-0425', 'str_GROSSISTE_LIBELLE': 'GROSSISTE DÉMO', 'int_NBRE_PRODUIT': 46, 'int_LINE': 3, 'PRIX_ACHAT_TOTAL': 61500, 'str_STATUT': 'passed'}
        ],
        'total': 1
      });
  s.routes['GET /commande/list/passees'] = (_) => const ReponseLocale({'data': [], 'total': 0});
  s.routes['GET /commande/list-bons'] = (_) => const ReponseLocale({
        'data': [
          {'lg_BON_LIVRAISON_ID': 'BL1', 'str_REF_LIVRAISON': 'BL-DEMO-0425', 'str_GROSSISTE_LIBELLE': 'GROSSISTE DÉMO', 'int_NBRE_LIGNE_BL_DETAIL': 3, 'int_NBRE_PRODUIT': 46}
        ],
        'total': 1
      });
  s.routes['GET /commande/bon/items/BL1'] = (r) {
    final q = r.query['query'] ?? '';
    return ReponseLocale({
      'data': [for (final l in lignes) if (q.isEmpty || l['lg_FAMILLE_CIP'] == q) l],
      'total': lignes.length
    });
  };
  s.routes['GET /commande/entree-stock/autorisation'] = (_) => const ReponseLocale({'authorize': true});
  s.routes['GET /reception/parametres'] = (_) => const ReponseLocale({'success': true, 'peremptionObligatoire': false, 'clotureRecu': true});
}

void main() {
  setUpAll(() async {
    if (_actif) await chargerPolicesReelles();
  });

  for (final (taille, dossier) in [(TailleEcran.sunmiV2s, 'terminal'), (TailleEcran.tablette, 'tablette')]) {
    testWidgets('1. connexion — $dossier', (t) async {
      final app = await _app(t, taille);
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
      await t.enterText(find.byKey(const Key('connexion_login')), 'caisse.demo');
      FocusManager.instance.primaryFocus?.unfocus();
      await app.attendre(t, const Duration(seconds: 1));
      await _capture(t, dossier, '1_connexion');
      await app.fermer(t);
    }, skip: !_actif);

    testWidgets('2. vente au comptant — $dossier', (t) async {
      final app = await _app(t, taille);
      await app.lancer(t);
      expect(await app.seConnecter(t), isTrue);
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
      await _ajouter(t, app, _noms[0].$1, '2');
      await _ajouter(t, app, _noms[2].$1, '1');
      await _ajouter(t, app, _noms[4].$1, '3');
      FocusManager.instance.primaryFocus?.unfocus();
      await app.attendre(t, const Duration(seconds: 1));
      await _capture(t, dossier, '2_vente_comptant');
      await app.fermer(t);
    }, skip: !_actif);

    testWidgets('3. vente assurance — $dossier', (t) async {
      taille.appliquer(t);
      SharedPreferences.setMockInitialValues({'enabled_payment_method_ids': ['1', '10'], 'number_of_tickets_assurance': 1});
      WidgetsApp.debugAllowBannerOverride = false; // écran monté sans l'application : pas de bandeau « DEBUG »
      addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
      final gw = FauxGatewayAssurance();
      gw.catalog
        ..clear()
        ..addAll([for (var i = 0; i < 3; i++) produitPourCaptures('P$i', _noms[i].$1, '340093000000$i', _noms[i].$2)]);
      gw.clients = [
        ClientAssurance(
          lgCLIENTID: 'C1',
          fullName: 'CLIENT DÉMO Aya',
          strFIRSTNAME: 'CLIENT DÉMO',
          strLASTNAME: 'Aya',
          strNUMEROSECURITESOCIAL: 'MAT-DEMO-01',
          tiersPayants: [
            tiersPayantPourCaptures('TP1', 'ASSURANCE DÉMO SANTÉ', 'CT1', 80, 1),
            tiersPayantPourCaptures('TP2', 'MUTUELLE DÉMO', 'CT2', 10, 2),
          ],
          ayantDroits: [ayantDroitPourCaptures('C1', 'CLIENT DÉMO', 'Aya'), ayantDroitPourCaptures('AD2', 'CLIENT DÉMO', 'Junior')],
        ),
      ];
      await ouvrirAssurancePourCaptures(t, gw);
      await t.enterText(find.byKey(const ValueKey('assurance-client-recherche')), 'cli');
      await t.pump(const Duration(milliseconds: 600));
      await t.pumpAndSettle();
      await t.tap(find.text('CLIENT DÉMO Aya').first);
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('assurance-bon-CT1')), 'BON-2025-0187');
      await t.enterText(find.byKey(const ValueKey('assurance-bon-CT2')), 'MD-44120');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await _capture(t, dossier, '3_vente_assurance');
    }, skip: !_actif);

    testWidgets('4. encaissement mobile money et remise — $dossier', (t) async {
      final app = await _app(t, taille);
      await app.lancer(t);
      expect(await app.seConnecter(t), isTrue);
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
      await _ajouter(t, app, _noms[1].$1, '2');
      await _ajouter(t, app, _noms[3].$1, '1');
      await t.tap(find.byKey(const ValueKey('remise-vente-choisir')));
      expect(await app.attendreQue(t, find.byKey(const ValueKey('remise-option-REM-FICT-10'))), isTrue);
      await app.attendre(t, const Duration(milliseconds: 800));
      await t.tap(find.byKey(const ValueKey('remise-option-REM-FICT-10')));
      await app.attendre(t, const Duration(seconds: 2));
      // Complément : la remise appliquée (la page d'encaissement montre le net, remise déduite, sans la détailler).
      final remise = find.byKey(const ValueKey('remise-vente-zone'));
      await t.ensureVisible(remise);
      await app.attendre(t, const Duration(milliseconds: 500));
      await capturerFidele(t, find.byType(MaterialApp).first, Uri.file('$_base/mobile/complements/${dossier}_4b_remise_appliquee.png'));
      await t.tap(find.byKey(const ValueKey('vente-encaisser')));
      expect(await app.attendreQue(t, find.byKey(const ValueKey('mode-10'))), isTrue);
      await t.tap(find.byKey(const ValueKey('mode-10')));
      await app.attendre(t, const Duration(seconds: 1));
      await _capture(t, dossier, '4_encaissement_mobile_money_remise');
      await app.fermer(t);
    }, skip: !_actif);

    testWidgets('5. réception de BL — $dossier', (t) async {
      final app = await _app(t, taille, routes: _routesReception);
      await app.lancer(t);
      expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'reception_bl');
      await app.attendre(t, const Duration(seconds: 2));
      await t.tap(find.text('BL à entrer · 1'));
      await app.attendre(t);
      await t.tap(find.text('Continuer'));
      await app.attendre(t, const Duration(seconds: 2));
      await t.enterText(find.byType(TextField).first, '3595583');
      await app.attendre(t, const Duration(seconds: 2));
      final lot = find.widgetWithText(TextField, 'N° de lot');
      final date = find.widgetWithText(TextField, 'Péremption (JJ/MM/AAAA ou MM/AAAA)');
      await t.tap(lot);
      await t.enterText(lot, 'LOT-B2207');
      await t.testTextInput.receiveAction(TextInputAction.next);
      await app.attendre(t, const Duration(milliseconds: 500));
      await t.enterText(date, '0328');
      await t.testTextInput.receiveAction(TextInputAction.next);
      await app.attendre(t, const Duration(milliseconds: 500));
      FocusManager.instance.primaryFocus?.unfocus();
      await app.attendre(t, const Duration(seconds: 1));
      await _capture(t, dossier, '5_reception_bl');
      await app.fermer(t);
    }, skip: !_actif);
  }
}
