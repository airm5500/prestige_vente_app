// E2E — 4.14.0 : application entière contre le faux serveur Prestige (données FICTIVES), téléphone Sunmi V2s et
// tablette :
//  - vente comptant : remise choisie dans la liste du serveur, appliquée après sa réponse, net relu (remise du
//    serveur), encaissée ; ticket (mode test d'impression) mis en page comme le serveur avec la ligne de remise ;
//  - retrait de la remise ; le net revient au brut ;
//  - route image présente : le ticket est l'image du serveur (aucun gabarit local) ;
//  - aucune requête vers POST v1/vente/ticket/vno|vo (imprimante du serveur).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';
import 'outils/clients_vente_fictifs.dart';
import 'outils/parcours_vente.dart';
import 'outils/remises_fictives.dart';

final _zone = find.byKey(const ValueKey('remise-vente-zone'));
final _choisir = find.byKey(const ValueKey('remise-vente-choisir'));
final _retirer = find.byKey(const ValueKey('remise-vente-retirer'));

Future<(AppE2E, RemisesFictives)> _vente(WidgetTester t, {TailleEcran taille = TailleEcran.sunmiV2s}) async {
  taille.appliquer(t);
  TicketServeur.oublier();
  final app = AppE2E();
  CatalogueFictif(app.serveur, nombre: 10);
  ClientsVenteFictifs(app.serveur);
  final rf = RemisesFictives(app.serveur);
  await app.preparer(prefs: {...prefsVente, 'is_test_print_mode': true});
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
  expect(_zone, findsNothing, reason: 'pas de remise avant la création de la vente');
  expect(await ajouterAuPanier(t, app, nomCourt(3), qte: '4'), isTrue);
  await app.attendre(t, const Duration(seconds: 2));
  expect(_zone, findsOneWidget);
  return (app, rf);
}

Future<void> _appliquer(WidgetTester t, AppE2E app, String id) async {
  await t.tap(_choisir);
  expect(await app.attendreQue(t, find.byKey(ValueKey('remise-option-$id'))), isTrue);
  await app.attendre(t, const Duration(milliseconds: 800)); // fin de l'ouverture de la liste
  await t.tap(find.byKey(ValueKey('remise-option-$id')));
  await app.attendre(t, const Duration(seconds: 2));
}

Future<void> _encaisserAvecTicket(WidgetTester t, AppE2E app) async {
  await t.tap(find.byKey(const ValueKey('vente-encaisser')));
  expect(await app.attendreQue(t, find.text('Exact')), isTrue);
  await t.tap(find.text('Exact'));
  await t.pump();
  final v = find.byKey(const ValueKey('encaissement-valider'));
  await t.ensureVisible(v);
  await t.tap(v);
  await app.attendre(t, const Duration(seconds: 3));
}

String _net(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('vente-net'))).data!;

void main() {
  for (final taille in [TailleEcran.sunmiV2s, TailleEcran.tablette]) {
    testWidgets('${taille.nom} : remise appliquée par le serveur, encaissée, ticket « comme le serveur » avec la remise', (t) async {
      final (app, rf) = await _vente(t, taille: taille);
      final brut = _net(t);
      await _appliquer(t, app, 'REM-FICT-10');
      expect(rf.poses.single.remiseId, 'REM-FICT-10');
      expect(rf.netsVno.last['remiseId'], 'REM-FICT-10');
      expect(find.text('REMISE FICTIVE 10 %'), findsWidgets);
      expect(_net(t), isNot(brut));
      await _encaisserAvecTicket(t, app);
      expect(find.text('Aperçu du Ticket'), findsOneWidget, reason: 'route image absente : gabarit local');
      expect(find.text('VENTE COMPTANT'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\*\s+- ')), findsOneWidget, reason: 'ligne de remise du serveur');
      expect(app.serveur.recues.where((r) => r.methode == 'POST' && RegExp(r'/vente/ticket/(vno|vo)$').hasMatch(r.chemin)), isEmpty);
      await t.tap(find.text('Fermer'));
      await app.attendre(t);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }

  testWidgets('retirer la remise : net du serveur sans remise', (t) async {
    final (app, rf) = await _vente(t);
    final brut = _net(t);
    await _appliquer(t, app, 'REM-FICT-5');
    expect(_net(t), isNot(brut));
    await t.tap(_retirer);
    await app.attendre(t, const Duration(seconds: 2));
    expect(rf.poses.last.remiseId, isNull);
    expect(_net(t), brut);
    expect(_retirer, findsNothing);
    await app.fermer(t);
  });

  testWidgets('route image présente : ticket = image du serveur (aucun gabarit local)', (t) async {
    final (app, rf) = await _vente(t);
    rf.routeImage = true;
    await _encaisserAvecTicket(t, app);
    expect(find.byKey(const ValueKey('ticket-serveur-apercu')), findsOneWidget);
    expect(find.text('Aperçu du Ticket'), findsNothing);
    expect(rf.images.single, startsWith('vno V-1 58'));
    await t.tap(find.text('Fermer'));
    await app.attendre(t);
    await app.fermer(t);
  });
}
