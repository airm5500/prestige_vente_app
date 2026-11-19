// E2E — 4.15.0 : application entière contre le faux serveur Prestige (règles de la branche serveur
// correctif/demande62-1911, fb0a3cc2), données FICTIVES, Sunmi V2s et tablette :
//  - la caissière reprend une prévente payée à la borne depuis « Préventes à encaisser » : « Payée Wave … » dans la
//    liste, bandeau « Déjà payée par Wave : … », mode Wave imposé, aucun montant demandé, « TERMINER LA VENTE » ;
//    clôture avec ce règlement (typeRegleId 10, montant payé) ; vente terminée ;
//  - refus du serveur {success:false, paiementMobile:true} (paiement déjà réglé en partie ailleurs) : message tel
//    quel, vente gardée ;
//  - compte de prévente seulement : zone Remise proposée (décision du pharmacien du 19/11), pas d'encaissement ;
//  - serveur d'aujourd'hui (sans la demande 62) : badge « À encaisser », aucun bandeau, page d'encaissement d'origine.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';
import 'outils/clients_vente_fictifs.dart';
import 'outils/demande62_fictive.dart';
import 'outils/parcours_vente.dart';
import 'outils/remises_fictives.dart';

final _bandeau = find.byKey(const ValueKey('prevente-payee-bandeau'));
final _valider = find.byKey(const ValueKey('encaissement-valider'));

Future<(AppE2E, Demande62Fictive)> _app(WidgetTester t, {TailleEcran taille = TailleEcran.sunmiV2s, bool d62 = true, List<String>? droits}) async {
  taille.appliquer(t);
  final app = AppE2E();
  CatalogueFictif(app.serveur, nombre: 10);
  ClientsVenteFictifs(app.serveur);
  RemisesFictives(app.serveur);
  final d = Demande62Fictive(app.serveur, d62: d62);
  if (droits != null) app.serveur.droitsComptes = {DonneesFictives.login: droits};
  await app.preparer(prefs: {...prefsVente, 'is_test_print_mode': true});
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
  return (app, d);
}

/// « Préventes à encaisser » → prévente [ref].
Future<void> _reprendre(WidgetTester t, AppE2E app, String ref) async {
  await t.tap(find.byTooltip('Préventes à encaisser').first);
  expect(await app.attendreQue(t, find.text(ref)), isTrue);
  await app.attendre(t, const Duration(milliseconds: 600));
}

Future<void> _ouvrir(WidgetTester t, AppE2E app, String ref) async {
  await t.tap(find.text(ref));
  await app.attendre(t, const Duration(seconds: 2));
}

Future<void> _encaisser(WidgetTester t, AppE2E app) async {
  await t.tap(find.byKey(const ValueKey('vente-encaisser')));
  expect(await app.attendreQue(t, _valider), isTrue);
  await app.attendre(t, const Duration(milliseconds: 600));
  final imprimer = find.byKey(const ValueKey('encaissement-imprimer'));
  await app.defilerJusqua(t, imprimer, zone: find.byType(Scrollable).last);
  await t.tap(imprimer);
  await t.pump();
}

void main() {
  for (final taille in [TailleEcran.sunmiV2s, TailleEcran.tablette]) {
    testWidgets('${taille.nom} : prévente payée à la borne reprise au comptoir → mode imposé, aucun argent demandé, terminée', (t) async {
      final (app, d) = await _app(t, taille: taille);
      final id = d.preventeDeLaBorne();
      await _reprendre(t, app, 'REF-$id');
      expect(find.byKey(ValueKey('prevente-payee-$id')), findsOneWidget);
      expect(find.textContaining('Payée Wave'), findsOneWidget);
      await _ouvrir(t, app, 'REF-$id');
      expect(_bandeau, findsOneWidget);
      expect(find.textContaining('Déjà payée par Wave'), findsOneWidget);
      await _encaisser(t, app);
      expect(find.byKey(const ValueKey('mode-impose-10')), findsOneWidget);
      expect(find.text('Exact'), findsNothing, reason: 'aucun montant à saisir');
      expect(find.byKey(const ValueKey('encaissement-recu')), findsNothing);
      expect(find.text('TERMINER LA VENTE'), findsOneWidget);
      await t.tap(_valider);
      await app.attendre(t, const Duration(seconds: 3));
      final c = d.clotures.single;
      expect(c['typeRegleId'], '10');
      expect(c['reglements'], [
        {'montant': 4125, 'montantAttentu': 4125, 'typeReglement': '10'}
      ]);
      expect(d.refusClotures, isEmpty);
      expect(app.serveur.statutVentes[id], 'is_Closed');
      expect(d.paiements.values.single.message, 'Vente terminée au comptoir');
      expect(_bandeau, findsNothing, reason: 'vente terminée : nouveau panier');
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }

  testWidgets('refus du serveur {success:false, paiementMobile:true} : message tel quel, vente gardée', (t) async {
    final (app, d) = await _app(t);
    final id = d.preventeDeLaBorne();
    await _reprendre(t, app, 'REF-$id');
    await _ouvrir(t, app, 'REF-$id');
    // Le paiement relu à la borne a changé entre-temps (montant fictif différent) : le serveur refuse la clôture.
    d.paiements.values.single.statut = 'annule';
    d.payeeALaBorne(id, montant: 2000);
    await _encaisser(t, app);
    await t.tap(_valider);
    await app.attendre(t, const Duration(seconds: 3));
    expect(d.refusClotures, [id]);
    expect(find.textContaining('Cette prévente est déjà payée par Wave : 2000 F (n° TX-FICT-0042).'), findsOneWidget);
    expect(app.serveur.statutVentes[id], 'is_Process', reason: 'rien écrit, vente gardée');
    expect(_valider, findsOneWidget, reason: 'la page reste ouverte');
    await app.fermer(t);
  });

  testWidgets('compte de prévente seulement : remise proposée (comme le web), aucun encaissement', (t) async {
    final (app, _) = await _app(t, droits: ['P_SM_VENTE']);
    expect(await ajouterAuPanier(t, app, nomCourt(3), qte: '2'), isTrue);
    await app.attendre(t, const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('remise-vente-zone')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('remise-vente-choisir')));
    expect(await app.attendreQue(t, find.byKey(const ValueKey('remise-option-REM-FICT-10'))), isTrue);
    await app.attendre(t, const Duration(milliseconds: 800));
    await t.tap(find.byKey(const ValueKey('remise-option-REM-FICT-10')));
    await app.attendre(t, const Duration(seconds: 2));
    expect(find.text('REMISE FICTIVE 10 %'), findsWidgets);
    expect(find.byKey(const ValueKey('vente-encaisser')), findsNothing, reason: 'toujours pas de « Terminer une vente »');
    await app.fermer(t);
  });

  testWidgets('serveur d\'aujourd\'hui (sans la demande 62) : « À encaisser », aucun bandeau, encaissement d\'origine', (t) async {
    final (app, d) = await _app(t, d62: false);
    final id = d.preventeDeLaBorne();
    await _reprendre(t, app, 'REF-$id');
    expect(find.text('À encaisser'), findsOneWidget);
    expect(find.textContaining('Payée'), findsNothing);
    await _ouvrir(t, app, 'REF-$id');
    expect(_bandeau, findsNothing);
    await t.tap(find.byKey(const ValueKey('vente-encaisser')));
    expect(await app.attendreQue(t, find.text('Exact')), isTrue, reason: 'page d\'origine (espèces)');
    expect(find.byKey(const ValueKey('encaissement-payee')), findsNothing);
    await app.fermer(t);
  });
}
