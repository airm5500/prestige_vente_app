// E2E — 4.15.1 : application entière contre le faux serveur Prestige (règles de la branche serveur
// correctif/demande63-1911, bb6b4604), données FICTIVES, Sunmi V2s et tablette :
//  - compte avec P_REMISE_VENTE : remise appliquée, net rendu par vente/remise (aucun net/vno de plus) ; « Retirer »
//    envoie "0" ; ticket (mode test d'impression) = image du serveur (route image, largeur 58 / 80, dpi 203) ;
//  - compte sans le droit (rôle modifié par le pharmacien) : refus 403 affiché tel quel, zone Remise masquée ;
//  - serveur d'aujourd'hui : remise comme 4.15.0 (« Retirer » envoie null, net/vno relu), ticket local.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';
import 'outils/clients_vente_fictifs.dart';
import 'outils/demande63_fictive.dart';
import 'outils/parcours_vente.dart';
import 'outils/remises_fictives.dart';

final _zone = find.byKey(const ValueKey('remise-vente-zone'));
final _choisir = find.byKey(const ValueKey('remise-vente-choisir'));
final _retirer = find.byKey(const ValueKey('remise-vente-retirer'));

Future<(AppE2E, RemisesFictives, Demande63Fictive)> _vente(WidgetTester t,
    {TailleEcran taille = TailleEcran.sunmiV2s, bool d63 = true, List<String>? droits}) async {
  taille.appliquer(t);
  TicketServeur.oublier();
  final app = AppE2E();
  CatalogueFictif(app.serveur, nombre: 10);
  ClientsVenteFictifs(app.serveur);
  final rf = RemisesFictives(app.serveur);
  final d = Demande63Fictive(app.serveur, rf, d63: d63);
  if (droits != null) app.serveur.droitsComptes = {DonneesFictives.login: droits};
  await app.preparer(prefs: {...prefsVente, 'is_test_print_mode': true});
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
  expect(await ajouterAuPanier(t, app, nomCourt(3), qte: '4'), isTrue);
  await app.attendre(t, const Duration(seconds: 2));
  return (app, rf, d);
}

Future<void> _appliquer(WidgetTester t, AppE2E app, String id) async {
  await t.tap(_choisir);
  expect(await app.attendreQue(t, find.byKey(ValueKey('remise-option-$id'))), isTrue);
  await app.attendre(t, const Duration(milliseconds: 800));
  await t.tap(find.byKey(ValueKey('remise-option-$id')));
  await app.attendre(t, const Duration(seconds: 2));
}

String _net(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('vente-net'))).data!;

const _avecDroit = ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE', droitRemise];

void main() {
  for (final taille in [TailleEcran.sunmiV2s, TailleEcran.tablette]) {
    testWidgets('${taille.nom} : P_REMISE_VENTE → remise avec le net de vente/remise ; « Retirer » = "0" ; ticket du serveur', (t) async {
      final (app, rf, d) = await _vente(t, taille: taille, droits: _avecDroit);
      final brut = _net(t);
      final nets = rf.netsVno.length;
      await _appliquer(t, app, 'REM-FICT-10');
      expect(d.lgRemise['V-1'], 'REM-FICT-10');
      expect(rf.netsVno.length, nets, reason: 'net rendu par vente/remise (data)');
      expect(_net(t), isNot(brut));
      await t.tap(_retirer);
      await app.attendre(t, const Duration(seconds: 2));
      expect(d.lgRemise['V-1'], '0');
      expect(_net(t), brut);
      await _appliquer(t, app, 'REM-FICT-5');
      await t.tap(find.byKey(const ValueKey('vente-encaisser')));
      expect(await app.attendreQue(t, find.text('Exact')), isTrue);
      await t.tap(find.text('Exact'));
      await t.pump();
      final v = find.byKey(const ValueKey('encaissement-valider'));
      await t.ensureVisible(v);
      await t.tap(v);
      await app.attendre(t, const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('ticket-serveur-apercu')), findsOneWidget);
      expect(d.images.single, startsWith('vno V-1 '));
      expect(d.images.single, endsWith(' 203'));
      await t.tap(find.text('Fermer'));
      await app.attendre(t);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }

  testWidgets('compte sans P_REMISE_VENTE : 403 « Droit manquant : Remise sur une vente » tel quel, zone masquée', (t) async {
    final (app, _, d) = await _vente(t, droits: ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE']);
    expect(_zone, findsOneWidget, reason: 'serveur pas encore prouvé : le serveur reste juge');
    await _appliquer(t, app, 'REM-FICT-10');
    expect(find.text(messageDroitRemise), findsOneWidget);
    expect(d.refus403, 1);
    await app.attendre(t, const Duration(seconds: 1));
    expect(_zone, findsNothing);
    await app.fermer(t);
  });

  testWidgets('serveur d\'aujourd\'hui : remise comme 4.15.0 (net/vno relu, « Retirer » = null), ticket local', (t) async {
    final (app, rf, d) = await _vente(t, d63: false, droits: ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE']);
    await _appliquer(t, app, 'REM-FICT-10');
    expect(rf.netsVno.last['remiseId'], 'REM-FICT-10');
    await t.tap(_retirer);
    await app.attendre(t, const Duration(seconds: 2));
    expect(d.lgRemise['V-1'], isNull);
    expect(d.lgRemise.containsKey('V-1'), isTrue);
    await t.tap(find.byKey(const ValueKey('vente-encaisser')));
    expect(await app.attendreQue(t, find.text('Exact')), isTrue);
    await t.tap(find.text('Exact'));
    await t.pump();
    final v = find.byKey(const ValueKey('encaissement-valider'));
    await t.ensureVisible(v);
    await t.tap(v);
    await app.attendre(t, const Duration(seconds: 3));
    expect(find.text('Aperçu du Ticket'), findsOneWidget, reason: 'route absente : gabarit local');
    expect(d.images, isEmpty);
    await t.tap(find.text('Fermer'));
    await app.attendre(t);
    await app.fermer(t);
  });
}
