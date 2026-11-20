// BOUT EN BOUT — 5.2.0 : présentation de l'accueil au choix, application entière contre le faux serveur Prestige,
// données fictives :
//  - par défaut (préférences d'une installation existante) : accueil « Actuelle », inchangé ;
//  - Réglages › Apparence › Accueil : « Metro mosaïque » choisi → accueil en mosaïque dès le retour ; conservé au
//    redémarrage ; « Metro bandes » puis retour à « Actuelle » ;
//  - les 3 présentations affichent exactement les mêmes menus (droits du compte, menus masqués, « Borne » de
//    l'administrateur), avec les clés `tuile_<id>` ;
//  - ouverture d'un menu par app_e2e.ouvrirMenu dans A et B (menu protégé : code administrateur demandé) ;
//  - appui long : favoris / « Organiser l'accueil » toujours proposés.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_metro.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/screens/ajustement/ajustement_screen.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_screen.dart';
import 'package:prestige_vente_app/screens/stock_report/stock_report_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/accueil_metro_fictif.dart';
import 'outils/app_e2e.dart';

Future<AppE2E> _connecte(WidgetTester t, {bool admin = false, Map<String, Object> prefs = const {}}) async {
  TailleEcran.sunmiV2s.appliquer(t);
  final app = AppE2E(
      serveur: FauxServeurPrestige(comptes: {DonneesFictives.login: DonneesFictives.motDePasse, DonneesFictives.admin: DonneesFictives.motDePasseAdmin}));
  await app.preparer(prefs: {'hiddenMenuIds': <String>[], ...prefs});
  await app.lancer(t);
  final ok = admin
      ? await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin)
      : await app.seConnecter(t);
  expect(ok, isTrue);
  await app.attendre(t, const Duration(seconds: 2));
  return app;
}

/// Toutes les tuiles `tuile_<id>` de l'accueil, page parcourue de haut en bas.
Future<Set<String>> _tuilesDeLaPage(WidgetTester t) async {
  final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
  pos.jumpTo(pos.minScrollExtent);
  await t.pump();
  final ids = <String>{...tuilesConstruites()};
  while (pos.pixels < pos.maxScrollExtent) {
    pos.jumpTo((pos.pixels + 200).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    await t.pump();
    ids.addAll(tuilesConstruites());
  }
  pos.jumpTo(pos.minScrollExtent);
  await t.pump();
  return ids;
}

Future<void> _choisir(WidgetTester t, AppE2E app, AccueilPresentation p) async {
  await t.tap(find.text('Réglages'));
  await app.attendre(t, const Duration(seconds: 1));
  await t.tap(find.byKey(const Key('rubrique_apparence')));
  await app.attendre(t, const Duration(seconds: 1));
  final choix = find.byKey(Key('presentation_accueil_${p.name}'));
  await t.scrollUntilVisible(choix, 200, scrollable: find.byType(Scrollable).last);
  await t.pump();
  await t.tap(find.descendant(of: choix, matching: find.text(p.label)));
  await app.attendre(t, const Duration(milliseconds: 500));
  // Retour à l'accueil : Apparence puis Réglages.
  while (find.byType(AccueilScreen).hitTestable().evaluate().isEmpty) {
    await t.tap(find.byTooltip('Retour').last);
    await app.attendre(t, const Duration(seconds: 1));
  }
}

void main() {
  testWidgets('installation existante (aucun choix enregistré) : accueil « Actuelle », inchangé', (t) async {
    final app = await _connecte(t, prefs: {'presentation_listes_v1': 'dashboard', 'accueil_favoris_v1': ['search', 'caisse']});
    expect(PresentationPrefs.accueil.value, AccueilPresentation.actuelle);
    expect(find.byType(AccueilMetro), findsNothing);
    expect(find.byKey(const ValueKey('favori_search')), findsOneWidget, reason: 'favoris de la présentation actuelle');
    expect(find.byKey(const ValueKey('tuile_stock'), skipOffstage: false), findsOneWidget);
    expect(t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor, Pal.page);
    expect((await SharedPreferences.getInstance()).getStringList('accueil_favoris_v1'), ['search', 'caisse']);
    await app.fermer(t);
  });

  testWidgets('Réglages › Apparence : Metro mosaïque appliquée tout de suite, conservée au redémarrage ; bandes ; retour à Actuelle', (t) async {
    final app = await _connecte(t, admin: true);
    await _choisir(t, app, AccueilPresentation.metroMosaique);
    expect(find.byKey(const ValueKey('accueil_metro_metroMosaique')), findsOneWidget, reason: 'appliquée au retour, sans relancer');
    expect(t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor, MetroCharte.fondMosaique);
    expect((await SharedPreferences.getInstance()).getString(PresentationPrefs.cleAccueil), 'metroMosaique');

    // Redémarrage : la valeur en mémoire est perdue, relue au lancement comme main().
    await app.fermer(t);
    PresentationPrefs.accueil.value = AccueilPresentation.actuelle;
    await PresentationPrefs.loadAccueil();
    await app.lancer(t);
    expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
    await app.attendre(t, const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('accueil_metro_metroMosaique')), findsOneWidget, reason: 'conservée au redémarrage');

    await _choisir(t, app, AccueilPresentation.metroBandes);
    expect(find.byKey(const ValueKey('accueil_metro_metroBandes')), findsOneWidget);
    expect(t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor, Colors.white);
    await _choisir(t, app, AccueilPresentation.actuelle);
    expect(find.byType(AccueilMetro), findsNothing);
    expect(find.byKey(const ValueKey('favori_prevente')), findsOneWidget);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  for (final admin in [false, true]) {
    testWidgets('${admin ? 'administrateur' : 'vendeur'} : les 3 présentations affichent les mêmes menus, clés tuile_<id>', (t) async {
      final app = await _connecte(t, admin: admin);
      final actuelle = await _tuilesDeLaPage(t);
      expect(actuelle, isNotEmpty);
      expect(actuelle.contains('borne_admin'), admin, reason: '« Borne » réservée à l\'administrateur');
      expect(actuelle.contains('empreinte'), isFalse, reason: 'pointage local masqué par défaut');
      for (final p in [AccueilPresentation.metroMosaique, AccueilPresentation.metroBandes]) {
        await PresentationPrefs.saveAccueil(p);
        await t.pump();
        expect(find.byKey(ValueKey('accueil_metro_${p.name}')), findsOneWidget);
        expect(await _tuilesDeLaPage(t), actuelle, reason: '${p.label} : mêmes menus que l\'accueil actuel');
      }
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }

  testWidgets('menus masqués (Organiser l\'accueil) : absents des présentations Metro', (t) async {
    final app = await _connecte(t, prefs: {'hiddenMenuIds': ['carnet', 'stock'], PresentationPrefs.cleAccueil: 'metroMosaique'});
    for (final p in [AccueilPresentation.metroMosaique, AccueilPresentation.metroBandes]) {
      await PresentationPrefs.saveAccueil(p);
      await t.pump();
      final ids = await _tuilesDeLaPage(t);
      expect(ids.contains('carnet') || ids.contains('stock'), isFalse, reason: p.label);
      expect(ids, containsAll(['prevente', 'search', 'reception_bl']));
    }
    await app.fermer(t);
  });

  for (final p in [AccueilPresentation.metroMosaique, AccueilPresentation.metroBandes]) {
    testWidgets('${p.label} : ouvrir un menu (app_e2e.ouvrirMenu), menu protégé, appui long', (t) async {
      final app = await _connecte(t, prefs: {PresentationPrefs.cleAccueil: p.name});
      expect(find.byKey(ValueKey('accueil_metro_${p.name}')), findsOneWidget);
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'search');
      expect(find.byType(ProductSearchScreen), findsOneWidget);
      await t.tap(find.byTooltip('Retour').last);
      await app.attendre(t, const Duration(seconds: 1));
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'stock');
      expect(find.byType(StockReportScreen), findsOneWidget);
      await t.tap(find.byTooltip('Retour').last);
      await app.attendre(t, const Duration(seconds: 1));
      // Menu protégé : code administrateur demandé avant d'ouvrir.
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'ajustement');
      expect(find.byKey(const Key('pin_admin_saisie')), findsOneWidget, reason: 'code administrateur demandé');
      expect(find.byType(AjustementScreen), findsNothing);
      await t.tap(find.text('Annuler').last);
      await app.attendre(t, const Duration(seconds: 1));
      // Appui long : favoris et « Organiser l'accueil… ».
      await app.defilerJusqua(t, find.byKey(const ValueKey('tuile_caisse')));
      await t.longPress(find.byKey(const ValueKey('tuile_caisse')));
      await app.attendre(t, const Duration(seconds: 1));
      expect(find.byKey(const Key('favori_basculer')), findsOneWidget);
      expect(find.text('Organiser l\'accueil…'), findsOneWidget);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }
}
