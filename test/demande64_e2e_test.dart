// E2E — 4.15.2 : application entière contre le faux serveur Prestige (règles de la branche serveur
// correctif/demande64-1911, d6cf51fa5), données FICTIVES, Sunmi V2s et tablette :
//  - comptoir : prévente payée à la borne (Wave) reprise depuis « Préventes à encaisser » ; modifier la quantité ou
//    retirer la ligne → message du serveur affiché TEL QUEL, ligne inchangée à l'écran et sur le serveur ;
//  - comptoir : paiement Orange Money EN COURS sur la prévente → même verrou, message « en cours » ; une fois le
//    paiement annulé, la quantité se modifie ;
//  - borne (application en mode borne) : caisse de la borne fermée → aucun QR, ticket de prévente, « payez à la
//    caisse », une seule demande cloturer:true, aucun paiement créé ;
//  - serveur déployé (sans la demande 64) : panier modifiable, comme 4.15.1.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_kiosque.dart';
import 'package:prestige_vente_app/borne/borne_screen.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';
import 'outils/clients_vente_fictifs.dart';
import 'outils/demande62_fictive.dart';
import 'outils/demande64_fictive.dart';
import 'outils/faux_serveur_prestige.dart';
import 'outils/parcours_vente.dart';

Future<(AppE2E, Demande64Fictive)> _app(WidgetTester t, {TailleEcran taille = TailleEcran.sunmiV2s, bool d64 = true}) async {
  taille.appliquer(t);
  final app = AppE2E();
  CatalogueFictif(app.serveur, nombre: 10);
  ClientsVenteFictifs(app.serveur);
  final d = Demande64Fictive(app.serveur, d64: d64);
  await app.preparer(prefs: {...prefsVente, 'is_test_print_mode': true});
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
  return (app, d);
}

Future<void> _reprendre(WidgetTester t, AppE2E app, String ref) async {
  await t.tap(find.byTooltip('Préventes à encaisser').first);
  expect(await app.attendreQue(t, find.text(ref)), isTrue);
  await app.attendre(t, const Duration(milliseconds: 600));
  await t.tap(find.text(ref));
  await app.attendre(t, const Duration(seconds: 2));
}

String _snack(WidgetTester t) => (t.widget<SnackBar>(find.byType(SnackBar).last).content as Text).data!;

Future<void> _modifierQuantite(WidgetTester t, AppE2E app, String qte) async {
  await t.tap(find.byTooltip('Modifier').first);
  await app.attendre(t, const Duration(milliseconds: 600));
  await t.enterText(champQuantite.first, qte);
  await t.tap(find.text('Valider'));
  await app.attendre(t, const Duration(seconds: 1));
}

Future<void> _retirer(WidgetTester t, AppE2E app) async {
  await t.tap(find.byTooltip('Supprimer').first);
  await app.attendre(t, const Duration(milliseconds: 600));
  await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Supprimer')));
  await app.attendre(t, const Duration(seconds: 1));
}

void main() {
  for (final taille in [TailleEcran.sunmiV2s, TailleEcran.tablette]) {
    testWidgets('${taille.nom} : prévente payée par Wave, quantité puis retrait refusés : message tel quel, ligne gardée', (t) async {
      final (app, d) = await _app(t, taille: taille);
      final id = d.d62.preventeDeLaBorne();
      final avant = jsonEncode(app.serveur.ventes[id]);
      await _reprendre(t, app, 'REF-$id');
      expect(find.byKey(const ValueKey('prevente-payee-bandeau')), findsOneWidget);
      await _modifierQuantite(t, app, '2');
      expect(_snack(t), messagePayeWave4125);
      expect(find.text('PRODUIT 0001 CPR B/20'), findsWidgets, reason: 'ligne toujours affichée');
      await app.attendre(t, const Duration(seconds: 9));
      await _retirer(t, app);
      expect(_snack(t), messagePayeWave4125);
      expect(find.text('PRODUIT 0001 CPR B/20'), findsWidgets);
      expect(jsonEncode(app.serveur.ventes[id]), avant, reason: 'rien n\'est écrit sur le serveur');
      expect(d.refus, ['update/item/vno $id', 'remove/vno/item $id']);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }

  testWidgets('paiement Orange Money en cours : verrou « en cours » ; paiement annulé → quantité modifiée', (t) async {
    final (app, d) = await _app(t);
    final id = d.d62.preventeDeLaBorne(payee: false);
    final p = d.paiementEnCours(id);
    await _reprendre(t, app, 'REF-$id');
    await _modifierQuantite(t, app, '2');
    expect(_snack(t), messageEnCoursOrange4125);
    expect(app.serveur.ventes[id]!.single['intQUANTITY'], 1);
    await app.attendre(t, const Duration(seconds: 9));
    d.annuler(p);
    await _modifierQuantite(t, app, '2');
    expect(app.serveur.ventes[id]!.single['intQUANTITY'], 2);
    expect(find.text(messageEnCoursOrange4125), findsNothing);
    await app.fermer(t);
  });

  testWidgets('serveur déployé (sans la demande 64) : prévente payée modifiable comme en 4.15.1', (t) async {
    final (app, d) = await _app(t, d64: false);
    final id = d.d62.preventeDeLaBorne();
    await _reprendre(t, app, 'REF-$id');
    await _modifierQuantite(t, app, '2');
    expect(app.serveur.ventes[id]!.single['intQUANTITY'], 2);
    expect(d.refus, isEmpty);
    await app.fermer(t);
  });

  testWidgets('borne (application en mode borne), caisse fermée : aucun QR, ticket de prévente, une seule demande', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final avantSecrets = BorneReglages.secrets;
    BorneReglages.secrets = MemoireBorneSecrets('Borne#2026');
    final avantKiosque = BorneKiosque.instance;
    BorneKiosque.instance = KiosqueSimule();
    final avantPm = PaiementsMobile.instance;
    PaiementsMobile.instance = PaiementsMobile();
    addTearDown(() {
      BorneReglages.secrets = avantSecrets;
      BorneReglages.courant.value = const BorneConfig();
      BorneKiosque.instance = avantKiosque;
      PaiementsMobile.instance = avantPm;
      PaiementsMobileReglages.actif.value = false;
    });
    final app = AppE2E(serveur: FauxServeurPrestige(comptes: {
      DonneesFictives.login: DonneesFictives.motDePasse,
      'borne.accueil': 'Borne#2026',
    }));
    final d = Demande64Fictive(app.serveur);
    app.serveur.droitsComptes = {'borne.accueil': ['P_SM_VENTE', droitBorne]};
    app.serveur.routes['GET /vente/search'] = (_) => FauxServeurPrestige.ok({
          'data': [
            {'lgFAMILLEID': 'F1', 'strNAME': 'PRODUIT FICTIF 1000MG CP B/8', 'intCIP': '3400000000064', 'intPRICE': 1500, 'intNUMBERAVAILABLE': 40, 'strLIBELLEE': '', 'intPAF': 0}
          ],
          'total': 1
        });
    await app.preparer(prefs: {
      'borne_config_v1': jsonEncode(const BorneConfig(actif: true, login: 'borne.accueil').toJson()),
      'hiddenMenuIds': <String>[],
      'paiements_mobile_actif_v1': true,
    });
    await app.lancer(t);
    expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-recherche'))), isTrue);
    await app.attendre(t, const Duration(seconds: 2));
    await t.enterText(find.byKey(const ValueKey('borne-recherche')), 'prod');
    await app.attendre(t, const Duration(seconds: 2));
    await t.tap(find.byKey(const ValueKey('borne-ajouter-F1')));
    await app.attendre(t, const Duration(milliseconds: 500));
    await t.tap(find.byKey(const ValueKey('borne-voir-panier')));
    await app.attendre(t, const Duration(milliseconds: 500));
    final mobile = find.byKey(const ValueKey('borne-payer-mobile'));
    expect(mobile, findsOneWidget, reason: 'droit P_BORNE_PAIEMENT_MOBILE : proposé');
    await t.ensureVisible(mobile);
    await app.attendre(t, const Duration(milliseconds: 300));
    await t.tap(mobile);
    await app.attendre(t, const Duration(milliseconds: 500));
    await t.tap(find.byKey(const ValueKey('borne-operateur-wave')));
    await app.attendre(t, const Duration(seconds: 3));
    expect(d.d62.creations.map((c) => c['cloturer']), [true], reason: 'une seule demande, jamais cloturer:false');
    expect(d.d62.paiements, isEmpty, reason: 'aucun paiement créé, client non débité');
    expect(find.byKey(const ValueKey('pm-qr')), findsNothing);
    expect(find.text(BorneScreen.avisMobileIndisponible), findsOneWidget);
    expect(find.byKey(const ValueKey('borne-numero')), findsOneWidget, reason: 'ticket de prévente pour la caisse');
    expect(app.serveur.statutVentes.values, everyElement('is_Process'), reason: 'prévente gardée');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
