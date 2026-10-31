// E2E — Prestige Mobile 4.10.1 : fiche client, date de naissance ABSENTE ajoutée depuis le téléphone (retour du
// pharmacien du 31/10), application ENTIÈRE contre le faux serveur Prestige en mémoire, qui applique les règles du
// serveur (POST v1/ordonnance-client/client/{id}/identite : date absente seulement, ni à venir ni avant 1900) :
//  - « Ajouter » → JJ/MM/AAAA → enregistrée (AAAA-MM-JJ envoyé), fiche relue : « 02/03/1985 · … ans », bouton retiré ;
//  - date à venir : refusée sur l'appareil, aucune requête ;
//  - date déjà renseignée : affichée JJ/MM/AAAA, aucun bouton ;
//  - serveur sans la route (ancien) : « il doit être mis à jour » ;
//  - la date saisie n'est jamais journalisée.
// Patient FICTIF.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';

Future<AppE2E> _ouvrirFiche(WidgetTester t, {String naissance = ''}) async {
  TailleEcran.sunmiV2s.appliquer(t);
  final app = AppE2E()..serveur.activerModules();
  app.serveur.naissanceC1 = naissance;
  await app.preparer(prefs: {'hiddenMenuIds': <String>[]});
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await app.ouvrirMenu(t, ListPresentation.dashboard, 'ordonnances_clients');
  final onglet = find.text('Fiche client');
  if (onglet.evaluate().isNotEmpty) {
    await t.tap(onglet.first);
    await app.attendre(t, const Duration(milliseconds: 600));
  }
  await t.enterText(find.byKey(const ValueKey('fiche-recherche')), 'DEMO');
  await app.attendre(t, const Duration(seconds: 1));
  await t.tap(find.byKey(const ValueKey('fiche-client-C1')));
  await app.attendre(t);
  return app;
}

void main() {
  testWidgets('date absente : « Ajouter » → 02/03/1985 enregistrée, fiche relue, bouton retiré ; date à venir refusée sans requête', (t) async {
    final app = await _ouvrirFiche(t);
    expect(await app.attendreQue(t, find.byKey(const ValueKey('fiche-ajouter-naissance'))), isTrue);
    await t.tap(find.byKey(const ValueKey('fiche-ajouter-naissance')));
    await app.attendre(t, const Duration(milliseconds: 600));
    final demain = DateTime.now().add(const Duration(days: 1));
    String deux(int v) => v.toString().padLeft(2, '0');
    await t.enterText(find.byKey(const ValueKey('fiche-naissance-champ')), '${deux(demain.day)}${deux(demain.month)}${demain.year}');
    await t.tap(find.byKey(const ValueKey('fiche-naissance-enregistrer')));
    await app.attendre(t, const Duration(milliseconds: 600));
    expect(find.textContaining('futur'), findsOneWidget);
    expect(app.serveur.recuesSur('/identite'), isEmpty);
    await t.enterText(find.byKey(const ValueKey('fiche-naissance-champ')), '02031985');
    await t.tap(find.byKey(const ValueKey('fiche-naissance-enregistrer')));
    await app.attendre(t);
    expect(app.serveur.recuesSur('/client/C1/identite').single.json, {'naissance': '1985-03-02'});
    expect(app.serveur.naissanceC1, '1985-03-02');
    expect(find.text('Fiche complétée : date de naissance.'), findsOneWidget);
    expect(find.byKey(const ValueKey('fiche-ajouter-naissance')), findsNothing);
    expect(find.textContaining('02/03/1985'), findsOneWidget);
    final journal = [for (final e in await JournalTerminal.instance.lire()) '${e.action}|${e.motif}|${e.refLocale}'].join('\n');
    expect(journal, isNot(contains('1985')), reason: 'date de naissance jamais journalisée');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('date déjà renseignée : affichée JJ/MM/AAAA, aucun bouton', (t) async {
    final app = await _ouvrirFiche(t, naissance: '1980-01-01');
    expect(await app.attendreQue(t, find.textContaining('01/01/1980')), isTrue);
    expect(find.byKey(const ValueKey('fiche-ajouter-naissance')), findsNothing);
    await app.fermer(t);
  });

  testWidgets('serveur ancien (route absente) : message « doit être mis à jour », fiche inchangée', (t) async {
    final app = await _ouvrirFiche(t);
    app.serveur.routesParDefaut.remove('POST /client/C1/identite');
    await t.tap(find.byKey(const ValueKey('fiche-ajouter-naissance')));
    await app.attendre(t, const Duration(milliseconds: 600));
    await t.enterText(find.byKey(const ValueKey('fiche-naissance-champ')), '02031985');
    await t.tap(find.byKey(const ValueKey('fiche-naissance-enregistrer')));
    await app.attendre(t);
    expect(find.textContaining('mis à jour'), findsOneWidget);
    expect(app.serveur.naissanceC1, '');
    await app.fermer(t);
  });
}
