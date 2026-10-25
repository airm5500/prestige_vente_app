// 4.8.0 — e2e, application entière (faux serveur Prestige en mémoire, données fictives) : demande 56, nom de
// l'appareil gardé par le serveur (GET / PUT v1/appareil/nom, rattaché à l'empreinte de l'appareil).
//  - « Caisse mobile 1 » saisi à l'étape → PUT après la connexion (nom et empreinte), une seule fois par serveur ;
//  - réinstallation simulée (préférences effacées, même appareil) : GET rend le nom → pas d'étape, vente suivante
//    avec X-Poste « Caisse mobile 1 », aucun PUT de plus ;
//  - empreinte inconnue, 429, 404, délai dépassé : étape comme avant ;
//  - le serveur renvoie un nom nettoyé autrement : l'application garde le sien ;
//  - serveur ancien (PUT 404) : plus d'essai pour ce serveur ;
//  - X-Poste sur la connexion ET la déconnexion ;
//  - l'empreinte ne part QUE dans le champ « empreinte » des deux routes, jamais ailleurs ni dans le journal.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/serveur/nom_appareil_serveur.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/app_e2e.dart';
import 'outils/parcours_vente.dart';

/// Empreinte FICTIVE (64 hexadécimaux) : celle qu'aurait cet appareil.
final _emp = 'c0ffee12' * 8;
const _caisse = 'Caisse%20mobile%201';
final _etape = find.byKey(const Key('nom_appareil_etape'));

Future<(AppE2E, CatalogueFictif)> _preparer({String? nom, Map<String, String> serveurNoms = const {}}) async {
  final app = AppE2E();
  app.serveur.droitsComptes = {
    DonneesFictives.login: ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE'],
  };
  app.serveur.activerNomAppareil();
  app.serveur.nomsAppareils.addAll(serveurNoms);
  final c = CatalogueFictif(app.serveur, nombre: 10);
  await app.preparer(prefs: prefsVente, nomAppareil: nom);
  JournalTerminal.instance.terminalNom = 'SUNMI V2s';
  NomAppareilServeur.instance.empreinte = () async => _emp;
  return (app, c);
}

Iterable<RequeteRecue> _puts(AppE2E app) => app.serveur.recues.where((r) => r.methode == 'PUT' && r.chemin.endsWith('/appareil/nom'));
Iterable<RequeteRecue> _gets(AppE2E app) => app.serveur.recues.where((r) => r.methode == 'GET' && r.chemin.endsWith('/appareil/nom'));

Future<void> _enregistrer(WidgetTester t, AppE2E app) async {
  final b = find.byKey(const Key('nom_appareil_enregistrer'));
  await app.defilerJusqua(t, b, zone: find.descendant(of: _etape, matching: find.byType(Scrollable)).first);
  await t.tap(b);
  await t.pump();
}

Future<void> _vente(WidgetTester t, AppE2E app, CatalogueFictif c) async {
  await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
  expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
  await app.attendre(t, const Duration(seconds: 2));
  await validerEncaissementEspeces(t, app);
  await app.attendre(t, const Duration(seconds: 3));
  expect(c.clotures, 1);
}

Future<void> _deconnecter(WidgetTester t, AppE2E app) async {
  expect(await app.attendreQue(t, find.byType(AccueilScreen)), isTrue);
  await app.defilerJusqua(t, find.byKey(const Key('accueil_deconnexion')));
  await t.tap(find.byKey(const Key('accueil_deconnexion')));
  await app.attendre(t, const Duration(milliseconds: 500));
  await t.tap(find.widgetWithText(ElevatedButton, 'Se déconnecter'));
  await app.attendre(t, const Duration(seconds: 2));
}

/// L'empreinte ne part que dans le champ prévu des deux routes.
void _empreinteSeulementOuPrevu(AppE2E app) {
  for (final r in app.serveur.recues) {
    final ailleurs = '${r.chemin} ${r.cookie} ${r.clientRef} ${r.poste} ${r.utilisateur} ${r.autorisation}';
    expect(ailleurs, isNot(contains(_emp)), reason: '$r');
    final prevu = r.chemin.endsWith('/appareil/nom');
    if (!prevu) {
      expect('${r.query} ${r.corps}', isNot(contains(_emp)), reason: '$r');
    } else if (r.methode == 'GET') {
      expect(r.query.keys, ['empreinte']);
    } else {
      expect(r.json.keys.toSet(), {'empreinte', 'nom'});
    }
  }
}

void main() {
  testWidgets('« Caisse mobile 1 » saisi : PUT après la connexion, une fois ; X-Poste sur connexion et déconnexion', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    // Journal de la console capté pendant le test (remis avant la fin : invariant de flutter_test).
    final journal = <String>[];
    final avant = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => journal.add(m ?? '');
    final (app, _) = await _preparer();
    await app.lancer(t);
    expect(await app.attendreQue(t, _etape), isTrue, reason: 'empreinte inconnue du serveur : étape');
    expect(_gets(app), hasLength(1));
    await t.enterText(find.byKey(const Key('nom_appareil_champ')), 'Caisse mobile 1');
    await _enregistrer(t, app);
    expect(_puts(app), isEmpty, reason: 'pas encore connecté');
    expect(await app.seConnecter(t), isTrue);
    await app.attendre(t);
    final put = _puts(app).single;
    expect(put.json, {'empreinte': _emp, 'nom': 'Caisse mobile 1'});
    expect(app.serveur.nomsAppareils[_emp], 'Caisse mobile 1');
    expect(app.serveur.recues.lastWhere((r) => r.chemin.endsWith('/user/auth')).poste, _caisse, reason: 'X-Poste à la connexion');
    await _deconnecter(t, app);
    expect(app.serveur.recuesSur('/user/logout').single.poste, _caisse, reason: 'X-Poste à la déconnexion');
    expect(await app.seConnecter(t), isTrue);
    await app.attendre(t);
    expect(_puts(app), hasLength(1), reason: 'déjà confirmé par ce serveur : pas de nouvel envoi');
    _empreinteSeulementOuPrevu(app);
    await app.fermer(t);
    debugPrint = avant;
    expect(journal, isNotEmpty, reason: 'journal HTTP du mode débogage actif');
    expect(journal.join('\n'), isNot(contains(_emp.substring(0, 16))), reason: 'empreinte jamais dans le journal');
  });

  testWidgets('réinstallation simulée (préférences effacées, même appareil) : nom rendu par le serveur, aucune étape', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, c) = await _preparer(serveurNoms: {_emp: 'Caisse mobile 1'});
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue, reason: 'pas d\'étape : nom retrouvé');
    expect(_etape, findsNothing);
    expect(NomAppareil.instance.saisi, 'Caisse mobile 1');
    expect((await SharedPreferences.getInstance()).getString(NomAppareil.prefNom), 'Caisse mobile 1');
    await _vente(t, app, c);
    expect(app.serveur.recues.lastWhere((r) => r.chemin.endsWith('/vente/cloturer/vno')).poste, _caisse);
    expect(app.serveur.recues.lastWhere((r) => r.chemin.endsWith('/vente/add/vno')).poste, _caisse);
    expect(_puts(app), isEmpty, reason: 'nom venu de ce serveur : déjà confirmé');
    _empreinteSeulementOuPrevu(app);
    await app.fermer(t);
  });

  for (final (cas, preparer) in <(String, void Function(AppE2E))>[
    ('429 trop de demandes', (a) => a.serveur.statutLectureNom = 429),
    ('404 serveur ancien', (a) => a.serveur.statutLectureNom = 404),
    ('délai dépassé (5 s)', (a) => a.serveur.delaiLectureNom = const Duration(seconds: 5)),
  ]) {
    testWidgets('lecture impossible ($cas) : étape comme avant, au plus 3 s d\'attente', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final (app, _) = await _preparer(serveurNoms: {_emp: 'Caisse mobile 1'});
      preparer(app);
      await app.lancer(t);
      expect(await app.attendreQue(t, _etape, max: const Duration(seconds: 8)), isTrue);
      expect(NomAppareil.instance.nomEnregistre, isFalse);
      expect(t.widget<TextField>(find.byKey(const Key('nom_appareil_champ'))).controller!.text, 'SUNMI V2s');
      await app.fermer(t);
    });
  }

  testWidgets('le serveur enregistre un nom nettoyé autrement : l\'application garde celui du serveur', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, c) = await _preparer(nom: 'Caisse mobile 1');
    app.serveur.nomEnregistreServeur = (n) => n.toUpperCase();
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.attendre(t);
    expect(_puts(app).single.json['nom'], 'Caisse mobile 1');
    expect(NomAppareil.instance.saisi, 'CAISSE MOBILE 1');
    await _vente(t, app, c);
    expect(app.serveur.recues.lastWhere((r) => r.chemin.endsWith('/vente/cloturer/vno')).poste, 'CAISSE%20MOBILE%201');
    await app.fermer(t);
  });

  testWidgets('serveur ancien (PUT 404) : plus d\'essai pour ce serveur', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, _) = await _preparer(nom: 'Caisse mobile 1');
    app.serveur.statutEnvoiNom = 404;
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.attendre(t);
    expect(_puts(app), hasLength(1));
    await _deconnecter(t, app);
    expect(await app.seConnecter(t), isTrue);
    await app.attendre(t);
    expect(_puts(app), hasLength(1), reason: 'serveur ancien noté : aucun nouvel essai');
    await app.fermer(t);
  });

  testWidgets('envoi refusé (500) : nouvel essai à la connexion suivante', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, _) = await _preparer(nom: 'Caisse mobile 1');
    app.serveur.statutEnvoiNom = 500;
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.attendre(t);
    expect(_puts(app), hasLength(1));
    app.serveur.statutEnvoiNom = null;
    await _deconnecter(t, app);
    expect(await app.seConnecter(t), isTrue);
    await app.attendre(t);
    expect(_puts(app), hasLength(2));
    expect(app.serveur.nomsAppareils[_emp], 'Caisse mobile 1');
    await app.fermer(t);
  });
}
