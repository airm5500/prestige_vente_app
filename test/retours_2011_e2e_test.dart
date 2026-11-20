// E2E — 5.1.0 (retours du pharmacien du 20/11/2026) : application ENTIÈRE contre le faux serveur Prestige en mémoire,
// téléphone Sunmi V2s, données FICTIVES uniquement.
//  1. Vente : « PRODUIT 0 » tapé (120 produits, liste par pages « 50 sur 120 ») → la liste s'ouvre avec le texte tapé
//     dans le filtre, le curseur à la fin, le clavier ouvert ; on continue à taper « PRODUIT 01 » → nouvelle recherche
//     sur le serveur (produits au-delà des 50 chargés) ; choix du produit → fenêtre de quantité « NOM · CIP » → panier.
//     Ce test échoue sur 5.0.1 (filtre vide et sans focus depuis 963fcb6 / ca2c7dd).
//  3. Terminal Sunmi, service d'impression qui se connecte en retard (canal simulé) : le PREMIER ticket après le
//     lancement est imprimé, aucune commande envoyée avant la connexion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/services/imprimante_sunmi.dart';
import 'package:prestige_vente_app/services/largeur_ticket.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';
import 'outils/parcours_vente.dart';

Finder get _filtre => find.byKey(const ValueKey('liste-produits-filtre'));
EditableText _champ(WidgetTester t) => t.widget<EditableText>(find.descendant(of: _filtre, matching: find.byType(EditableText)));

Future<(AppE2E, CatalogueFictif)> _vente(WidgetTester t, {int nombre = 120, Map<String, Object> prefs = const {}}) async {
  TailleEcran.sunmiV2s.appliquer(t);
  TicketServeur.oublier();
  final app = AppE2E();
  final c = CatalogueFictif(app.serveur, nombre: nombre);
  await app.preparer(prefs: {...prefsVente, ...prefs});
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
  return (app, c);
}

void main() {
  testWidgets('vente : texte tapé repris dans la liste (focus, curseur à la fin), on continue à taper → recherche serveur, ajout', (t) async {
    final (app, _) = await _vente(t);
    final recherchesAvant = app.serveur.recuesSur('/vente/search').length;
    await t.enterText(champRechercheVente, 'PRODUIT 0');
    expect(await app.attendreQue(t, find.text('Résultats (50 sur 120)')), isTrue, reason: 'liste par pages');
    await app.attendre(t, const Duration(milliseconds: 500));
    expect(_champ(t).controller.text, 'PRODUIT 0', reason: 'texte tapé repris');
    expect(_champ(t).focusNode.hasFocus, isTrue, reason: 'focus dans le filtre');
    expect(_champ(t).controller.selection, const TextSelection.collapsed(offset: 9), reason: 'curseur à la fin');
    expect(t.testTextInput.isVisible, isTrue, reason: 'clavier ouvert');

    // On continue à taper : « PRODUIT 01 » (produits 100 à 120, au-delà des 50 chargés) → recherche sur le serveur.
    await t.enterText(_filtre, 'PRODUIT 01');
    expect(await app.attendreQue(t, find.text('Résultats (21 sur 21)')), isTrue);
    final requetes = [for (final r in app.serveur.recuesSur('/vente/search').skip(recherchesAvant)) r.query['query']];
    expect(requetes.last, contains('PRODUIT 01'));
    expect(_champ(t).focusNode.hasFocus, isTrue, reason: 'le clavier reste ouvert');
    expect(t.testTextInput.isVisible, isTrue);

    await t.tap(find.text('PRODUIT 0105 CPR B/20'));
    expect(await app.attendreQue(t, champQuantite), isTrue);
    expect(find.text('PRODUIT 0105 CPR B/20 · CIP 3400900000105', findRichText: true), findsOneWidget);
    await t.tap(find.text('Ajouter'));
    await app.attendre(t, const Duration(seconds: 2));
    final ajout = app.serveur.recues.where((r) => r.methode == 'POST' && RegExp(r'/vente/add/(vno|item)$').hasMatch(r.chemin)).toList();
    expect(ajout.single.json['produitId'], 'F105', reason: 'produit choisi ajouté au panier');
    expect(find.text('PRODUIT F105'), findsWidgets, reason: 'ligne du panier (nom renvoyé par le faux serveur)');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('terminal Sunmi, service connecté en retard : premier ticket après le lancement imprimé, aucune commande perdue', (t) async {
    ImprimanteSunmi.reinitialiser(avec: () async => true, pas: const Duration(milliseconds: 100));
    LargeurTicket.reinitialiser();
    addTearDown(() {
      ImprimanteSunmi.reinitialiser();
      LargeurTicket.reinitialiser();
    });
    // Imprimante simulée : connectée après 5 lectures de version qui suivent la demande de liaison (≈ 0,5 s).
    var lie = false;
    var lectures = 0;
    bool connecte() => lie && lectures > 5;
    final appels = <String>[];
    final perdues = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(ImprimanteSunmi.canal, (call) async {
      appels.add(call.method);
      switch (call.method) {
        case 'BIND_PRINTER_SERVICE':
          lie = true;
          return true;
        case 'PRINTER_VERSION':
          if (lie) lectures++;
          return connecte() ? '2.4.1' : 'NOT FOUND';
        case 'PAPER_SIZE':
          return 1;
        case 'GET_UPDATE_PRINTER':
          return connecte() ? 'NORMAL' : 'ERROR';
        default:
          if (!connecte()) perdues.add(call.method);
          return null;
      }
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(ImprimanteSunmi.canal, null));

    final (app, c) = await _vente(t, nombre: 10, prefs: {'is_test_print_mode': false, 'number_of_tickets': 1});
    ImprimanteSunmi.lierAuDemarrage(); // comme main()
    expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
    await app.attendre(t, const Duration(seconds: 2));
    await t.tap(find.byKey(const ValueKey('vente-encaisser')));
    expect(await app.attendreQue(t, find.text('Exact')), isTrue);
    await t.tap(find.text('Exact'));
    await t.pump();
    final valider = find.byKey(const ValueKey('encaissement-valider'));
    await t.ensureVisible(valider);
    await t.pump();
    await t.tap(valider);
    await app.attendre(t, const Duration(seconds: 6));
    expect(c.clotures, 1);
    expect(appels, contains('PRINT_TEXT'), reason: 'ticket imprimé');
    expect(perdues, isEmpty, reason: 'avant 5.1.0 : commandes envoyées avant la connexion du service (ticket perdu)');
    expect(LargeurTicket.integreeConnue, 58);
    expect(find.textContaining('Imprimante non connectée'), findsNothing);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
