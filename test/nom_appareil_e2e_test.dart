// 4.7.0 — e2e, application entière (faux serveur Prestige en mémoire, données fictives) : nom de cet appareil dans
// l'en-tête X-Poste (demande du serveur du 25/10/2026).
//  - sans nom saisi : marque et modèle (« SUNMI V2s ») sur TOUTES les requêtes, connexion, création de la vente et
//    clôture comprises ;
//  - première connexion : nom proposé, « Caisse mobile 1 » saisi, vente faite et terminée → X-Poste « Caisse mobile 1 »
//    sur la création et la clôture ;
//  - « Plus tard » : nom par défaut envoyé, plus de proposition ensuite ;
//  - routes et corps inchangés ; aucun jeton ni identifiant dans le nom.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/app_e2e.dart';
import 'outils/parcours_vente.dart';

const _defaut = 'SUNMI%20V2s';
const _caisse = 'Caisse%20mobile%201';

/// Marque et modèle lus au démarrage (main : JournalTerminal.chargerIdentite) ; ici fixés pour le test.
Future<(AppE2E, CatalogueFictif)> _preparer({bool proposer = false}) async {
  final app = AppE2E();
  app.serveur.droitsComptes = {
    DonneesFictives.login: ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE'],
  };
  final c = CatalogueFictif(app.serveur, nombre: 10);
  await app.preparer(prefs: {...prefsVente, if (proposer) NomAppareil.prefPropose: false});
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

RequeteRecue _une(AppE2E app, String fin) => app.serveur.recues.lastWhere((r) => r.chemin.endsWith(fin));

void main() {
  testWidgets('sans nom saisi : « SUNMI V2s » sur toutes les requêtes (connexion, création, clôture)', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, c) = await _preparer();
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await _venteTerminee(t, app, c);
    expect(app.serveur.recues, isNotEmpty);
    for (final r in app.serveur.recues) {
      expect(r.poste, _defaut, reason: '$r');
    }
    expect(_une(app, '/user/auth').poste, _defaut);
    expect(_une(app, '/vente/add/vno').poste, _defaut);
    expect(_une(app, '/vente/cloturer/vno').poste, _defaut);
    expect(find.byKey(const Key('nom_appareil_proposition')), findsNothing, reason: 'déjà proposé (préférence)');
    await app.fermer(t);
  });

  testWidgets('première connexion : nom proposé, « Caisse mobile 1 » saisi, vente terminée avec ce nom', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, c) = await _preparer(proposer: true);
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    expect(await app.attendreQue(t, find.byKey(const Key('nom_appareil_proposition'))), isTrue, reason: 'proposé après la connexion');
    expect(_une(app, '/user/auth').poste, _defaut, reason: 'connexion : nom par défaut');
    await t.enterText(find.byKey(const Key('nom_appareil_champ')), 'Caisse mobile 1');
    await t.pump();
    expect(find.text('Enregistré dans Prestige : « Caisse mobile 1 »'), findsOneWidget);
    await t.tap(find.byKey(const Key('nom_appareil_valider')));
    await app.attendre(t);
    expect(find.byKey(const Key('nom_appareil_proposition')), findsNothing);
    final avant = app.serveur.recues.length;
    await _venteTerminee(t, app, c);
    final apres = app.serveur.recues.sublist(avant);
    expect(apres, isNotEmpty);
    for (final r in apres) {
      expect(r.poste, _caisse, reason: '$r');
    }
    expect(_une(app, '/vente/add/vno').poste, _caisse, reason: 'poste de saisie');
    expect(_une(app, '/vente/cloturer/vno').poste, _caisse, reason: 'poste d\'encaissement');
    // Corps et routes inchangés : rien du nom ailleurs que dans l'en-tête.
    for (final r in app.serveur.recues) {
      expect('${r.chemin} ${r.query} ${r.corps}', isNot(contains('Caisse mobile 1')), reason: '$r');
    }
    final p = await SharedPreferences.getInstance();
    expect(p.getString(NomAppareil.prefNom), 'Caisse mobile 1', reason: 'gardé sur l\'appareil');
    await app.fermer(t);
  });

  testWidgets('« Plus tard » : nom par défaut envoyé, plus de proposition', (t) async {
    TailleEcran.telephone.appliquer(t);
    final (app, c) = await _preparer(proposer: true);
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    expect(await app.attendreQue(t, find.byKey(const Key('nom_appareil_proposition'))), isTrue);
    expect(t.takeException(), isNull, reason: 'fenêtre lisible sur un téléphone 360 dp');
    await t.tap(find.byKey(const Key('nom_appareil_plus_tard')));
    await app.attendre(t);
    expect(NomAppareil.instance.dejaPropose, isTrue);
    expect((await SharedPreferences.getInstance()).getBool(NomAppareil.prefPropose), isTrue);
    await _venteTerminee(t, app, c);
    expect(_une(app, '/vente/cloturer/vno').poste, _defaut);
    await app.fermer(t);
  });
}
