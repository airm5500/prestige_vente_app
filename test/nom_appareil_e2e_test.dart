// 4.7.0 / 4.7.1 — e2e, application entière (faux serveur Prestige en mémoire, données fictives) : nom de cet appareil
// (en-tête X-Poste, demande du serveur du 25/10/2026), OBLIGATOIRE depuis la 4.7.1 (décision du pharmacien) :
//  - nouvelle installation : étape « Nom de cet appareil » au lancement, pré-remplie (marque et modèle) ; retour
//    bloqué avec un message ; un appui sur « Enregistrer » suffit ; vente faite et terminée avec ce nom ;
//  - « Caisse mobile 1 » saisi → X-Poste sur la création et la clôture de la vente ; nom vide refusé ;
//  - nom déjà enregistré : aucune étape ; mise à jour d'une 4.7.0 sans nom : demandé une fois, plus ensuite ;
//  - première configuration : réglages non quittables sans nom enregistré ;
//  - ergonomie de l'étape : téléphone 360 dp et Sunmi V2s, texte ×1,3 et ×2.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/parametres/parametres_screen.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/app_e2e.dart';
import 'outils/parcours_vente.dart';

const _defaut = 'SUNMI%20V2s';
const _caisse = 'Caisse%20mobile%201';
final _etape = find.byKey(const Key('nom_appareil_etape'));

/// Marque et modèle lus au démarrage (main : JournalTerminal.chargerIdentite) ; ici fixés pour le test.
Future<(AppE2E, CatalogueFictif)> _preparer({String? nom, Map<String, Object> prefs = const {}}) async {
  final app = AppE2E();
  app.serveur.droitsComptes = {
    DonneesFictives.login: ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE'],
  };
  final c = CatalogueFictif(app.serveur, nombre: 10);
  await app.preparer(prefs: {...prefsVente, ...prefs}, nomAppareil: nom);
  JournalTerminal.instance.terminalNom = 'SUNMI V2s';
  return (app, c);
}

Future<void> _venteTerminee(WidgetTester t, AppE2E app, CatalogueFictif c) async {
  await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
  expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
  await app.attendre(t, const Duration(seconds: 2));
  await validerEncaissementEspeces(t, app);
  await app.attendre(t, const Duration(seconds: 3));
  expect(c.clotures, 1, reason: 'vente terminée');
}

String _poste(AppE2E app, String fin) => app.serveur.recues.lastWhere((r) => r.chemin.endsWith(fin)).poste;

/// « Enregistrer » rendu visible dans sa zone défilante puis touché.
Future<void> _enregistrer(WidgetTester t, AppE2E app, Finder ecran) async {
  final b = find.byKey(const Key('nom_appareil_enregistrer'));
  await app.defilerJusqua(t, b, zone: find.descendant(of: ecran, matching: find.byType(Scrollable)).first);
  await t.tap(b);
  await t.pump();
}

Future<void> _retourAndroid(WidgetTester t, AppE2E app) async {
  await t.binding.handlePopRoute();
  await app.attendre(t, const Duration(milliseconds: 500));
}

void main() {
  testWidgets('nouvelle installation : étape obligatoire pré-remplie, retour bloqué, « Enregistrer » suffit, vente avec ce nom',
      (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, c) = await _preparer();
    await app.lancer(t);
    expect(await app.attendreQue(t, _etape), isTrue, reason: 'étape imposée au lancement');
    expect(find.byType(ConnexionScreen), findsNothing);
    final champ = t.widget<TextField>(find.byKey(const Key('nom_appareil_champ')));
    expect(champ.controller!.text, 'SUNMI V2s', reason: 'pré-rempli avec la marque et le modèle');
    await _retourAndroid(t, app);
    expect(_etape, findsOneWidget, reason: 'retour bloqué');
    expect(find.text('Saisissez le nom de cet appareil pour continuer.'), findsOneWidget);
    await _enregistrer(t, app, _etape);
    expect(await app.seConnecter(t), isTrue, reason: 'puis la connexion, comme avant');
    expect(NomAppareil.instance.nomEnregistre, isTrue);
    await _venteTerminee(t, app, c);
    for (final r in app.serveur.recues) {
      expect(r.poste, _defaut, reason: '$r');
    }
    expect(_poste(app, '/user/auth'), _defaut);
    await app.fermer(t);
  });

  testWidgets('« Caisse mobile 1 » saisi : X-Poste sur la création et la clôture ; nom vide refusé', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, c) = await _preparer();
    await app.lancer(t);
    expect(await app.attendreQue(t, _etape), isTrue);
    await t.enterText(find.byKey(const Key('nom_appareil_champ')), '  #/!  ');
    await _enregistrer(t, app, _etape);
    await app.attendre(t);
    expect(_etape, findsOneWidget, reason: 'nom vide : refusé');
    expect(find.textContaining('Saisissez le nom de cet appareil'), findsWidgets);
    await t.enterText(find.byKey(const Key('nom_appareil_champ')), 'Caisse mobile 1');
    await t.pump();
    expect(find.text('Enregistré dans Prestige : « Caisse mobile 1 »'), findsOneWidget);
    await _enregistrer(t, app, _etape);
    final avant = app.serveur.recues.length;
    expect(await app.seConnecter(t), isTrue);
    await _venteTerminee(t, app, c);
    expect(_poste(app, '/vente/add/vno'), _caisse, reason: 'poste de saisie');
    expect(_poste(app, '/vente/cloturer/vno'), _caisse, reason: 'poste d\'encaissement');
    for (final r in app.serveur.recues.sublist(avant)) {
      expect(r.poste, _caisse, reason: '$r');
    }
    for (final r in app.serveur.recues) {
      expect('${r.chemin} ${r.query} ${r.corps}', isNot(contains('Caisse mobile 1')), reason: 'routes et corps inchangés');
    }
    expect((await SharedPreferences.getInstance()).getString(NomAppareil.prefNom), 'Caisse mobile 1');
    await app.fermer(t);
  });

  testWidgets('nom déjà enregistré : aucune étape, connexion directe', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, _) = await _preparer(nom: 'Caisse mobile 1');
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    expect(_etape, findsNothing);
    expect(_poste(app, '/user/auth'), _caisse);
    await app.fermer(t);
  });

  testWidgets('mise à jour d\'une 4.7.0 sans nom (« Plus tard ») : demandé une fois, plus au lancement suivant', (t) async {
    TailleEcran.telephone.appliquer(t);
    final (app, _) = await _preparer(prefs: {'nom_appareil_propose_v1': true});
    await app.lancer(t);
    expect(await app.attendreQue(t, _etape), isTrue, reason: 'pas encore de nom : demandé');
    await _enregistrer(t, app, _etape);
    expect(await app.seConnecter(t), isTrue);
    // Relance de l'application (mêmes préférences sur l'appareil).
    await app.fermer(t);
    NomAppareil.reinitialiser();
    await NomAppareil.instance.charger();
    expect(NomAppareil.instance.nomEnregistre, isTrue);
    await app.lancer(t);
    await app.attendre(t, const Duration(seconds: 3));
    expect(_etape, findsNothing, reason: 'enregistré : plus jamais demandé');
    await app.fermer(t);
  });

  testWidgets('première configuration : réglages non quittables sans nom enregistré', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, _) = await _preparer(prefs: {'local_ip': ''});
    await app.lancer(t);
    expect(await app.attendreQue(t, find.byKey(const Key('configurer_serveur'))), isTrue, reason: 'appareil non configuré');
    await t.tap(find.byKey(const Key('configurer_serveur')));
    expect(await app.attendreQue(t, find.byType(ParametresScreen)), isTrue);
    expect(find.byKey(const Key('nom_appareil_obligatoire')), findsOneWidget, reason: 'en tête des réglages');
    await _retourAndroid(t, app);
    expect(find.byType(ParametresScreen), findsOneWidget, reason: 'retour bloqué');
    expect(find.text('Saisissez le nom de cet appareil avant de quitter les réglages.'), findsOneWidget);
    await _enregistrer(t, app, find.byType(ParametresScreen));
    await app.attendre(t);
    expect(find.byKey(const Key('nom_appareil_obligatoire')), findsNothing);
    await _retourAndroid(t, app);
    expect(find.byType(ParametresScreen), findsNothing, reason: 'nom enregistré : les réglages se quittent');
    await app.fermer(t);
  });

  for (final (taille, echelle) in [(TailleEcran.telephone, 1.3), (TailleEcran.sunmiV2s, 2.0)]) {
    testWidgets('étape obligatoire (${taille.nom}, texte ×$echelle) : lisible, sans débordement', (t) async {
      taille.appliquer(t);
      t.platformDispatcher.textScaleFactorTestValue = echelle;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final (app, _) = await _preparer();
      await app.lancer(t);
      expect(await app.attendreQue(t, _etape), isTrue);
      expect(t.takeException(), isNull);
      await _enregistrer(t, app, _etape);
      await app.attendre(t);
      expect(_etape, findsNothing);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }
}
