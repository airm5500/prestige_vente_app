// NON-RÉGRESSION — 4.13.0 (demande du 13/11/2026) :
//  - plus JAMAIS le nom du mode de règlement dans `clientId` (vente en ligne, ancienne interface, synchronisation hors
//    ligne) ; plus d'appel « associer le client » avant l'encaissement ;
//  - le client d'une vente ne passe que par un lgCLIENTID reçu du serveur (ClientVente.depuisJson) ;
//  - confidentialité : ni nom, ni téléphone, ni texte cherché dans les journaux (console de débogage, journal du
//    terminal, fil d'Ariane du support), parcours complet en application entière ;
//  - les routes du client ne sont pas des écritures journalisées ; la borne (lib/borne, lib/prestigepos) n'affiche
//    jamais la zone Client ; l'assurance, le carnet, le dépôt, la proforma gardent leur client.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/support/support_centre.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';
import 'outils/clients_vente_fictifs.dart';
import 'outils/parcours_vente.dart';

String _lire(String p) => File(p).readAsStringSync();

void main() {
  test('nom du mode de règlement : plus jamais transformé en clientId (vente, ancienne interface, hors ligne)', () {
    final motif = RegExp(r"""\.toLowerCase\(\)\.replaceAll\(' ', ''\)\.replaceAll\('é', 'e'\)""");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      expect(motif.hasMatch(f.readAsStringSync()), isFalse, reason: '${f.path} : nom du mode transformé en identifiant');
    }
    expect(_lire('lib/horsligne/ventes_sync.dart'), isNot(contains('updateClient(')));
    expect(_lire('lib/ventes/prevente/vente_controller.dart'), isNot(contains('gateway.updateClient(')));
    expect(_lire('lib/providers/sale_provider.dart'), isNot(contains('updateClientForSale')));
    expect(_lire('lib/api/api_service.dart'), isNot(contains('updateClientForSale')));
    expect(_lire('lib/ventes/prevente/vente_controller.dart'), contains("close(id, _client?.id ?? '')"));
  });

  test('clôture comptant : clientId vide → null (comme le poste), sinon tel quel ; assurance inchangée', () {
    final g = _lire('lib/ventes/core/vente_gateway.dart');
    expect(RegExp(r'"clientId": clientId\.isEmpty \? null : clientId').allMatches(g), hasLength(1), reason: 'corps comptant seulement');
    expect(g, contains('"ayantDroitId": ayantDroitId,\n        "banque": "",\n        "clientId": clientId,'));
    expect(_lire('lib/api/api_service.dart'), contains('"clientId": clientId.isEmpty ? null : clientId'));
  });

  test('routes du client : pas des écritures journalisées ; aucun journal dans la zone Client', () {
    final j = _lire('lib/horsligne/journal/journal_interceptor.dart');
    for (final r in ['update/client', 'client/lambda', 'add/lambda']) {
      expect(j, isNot(contains(r)), reason: 'journal du terminal : $r');
    }
    final zone = _lire('lib/ventes/prevente/client_vente.dart');
    for (final x in ['debugPrint', 'print(', 'journalErreur', 'JournalTerminal', 'noterAction', 'log(']) {
      expect(zone, isNot(contains(x)), reason: 'client_vente.dart : $x');
    }
    final g = _lire('lib/ventes/core/vente_gateway.dart');
    final debut = g.indexOf('Future<VenteResult<List<ClientVente>>> rechercherClientsVente(String texte) async');
    expect(debut, greaterThan(0));
    final client = g.substring(debut, g.indexOf('cloturerVno({', debut));
    for (final x in ['debugPrint', 'journalErreur', 'print(']) {
      expect(client, isNot(contains(x)));
    }
  });

  test('borne libre-service : jamais de zone Client', () {
    for (final d in ['lib/borne', 'lib/prestigepos']) {
      if (!Directory(d).existsSync()) continue;
      for (final f in Directory(d).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final c = f.readAsStringSync();
        expect(c, isNot(contains('client_vente.dart')), reason: f.path);
        expect(c, isNot(contains('ClientVenteZone')), reason: f.path);
        expect(c, isNot(contains('rattacherClientVente')), reason: f.path);
      }
    }
  });

  test('autres ventes : client inchangé (assurance, carnet, dépôt, proforma)', () {
    for (final f in [
      'lib/ventes/assurance/assurance_controller.dart',
      'lib/ventes/carnet/carnet_controller.dart',
      'lib/providers/depot_sale_provider.dart',
      'lib/providers/proforma_provider.dart',
    ]) {
      final c = _lire(f);
      expect(c, contains('clientId: '), reason: f);
      expect(c, isNot(contains('ClientVente')), reason: f);
    }
  });

  testWidgets('confidentialité : parcours complet, aucun nom / téléphone / texte cherché dans les journaux', (t) async {
    final console = <String>[];
    final avant = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => console.add(m ?? '');
    addTearDown(() => debugPrint = avant);
    final support = SupportCentre(actif: false);
    final supportAvant = SupportCentre.instance;
    SupportCentre.instance = support;
    addTearDown(() => SupportCentre.instance = supportAvant);

    TailleEcran.sunmiV2s.appliquer(t);
    final app = AppE2E();
    CatalogueFictif(app.serveur, nombre: 10);
    final cl = ClientsVenteFictifs(app.serveur);
    await app.preparer(prefs: prefsVente);
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
    await app.attendre(t, const Duration(seconds: 2));
    await t.tap(find.byKey(const ValueKey('client-vente-ouvrir')));
    await app.attendre(t, const Duration(milliseconds: 600));
    await t.enterText(find.byKey(const ValueKey('client-vente-recherche')), 'SECRETNOM');
    await app.attendre(t, const Duration(seconds: 1));
    await t.enterText(find.byKey(const ValueKey('client-vente-recherche')), '0711');
    await app.attendre(t, const Duration(seconds: 1));
    await t.tap(find.byKey(const ValueKey('client-vente-nouveau')));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('client-vente-nom-saisi')), 'SECRETNOM');
    await t.enterText(find.byKey(const ValueKey('client-vente-prenom-saisi')), 'SECRETPRENOM');
    await t.enterText(find.byKey(const ValueKey('client-vente-telephone-saisi')), '0711223344');
    // Premier essai refusé (message du serveur), puis création.
    cl.forcerCreation = (_) => FauxServeurPrestige.refus('Refus fictif.');
    await t.ensureVisible(find.byKey(const ValueKey('client-vente-creer')));
    await t.tap(find.byKey(const ValueKey('client-vente-creer')));
    await app.attendre(t, const Duration(seconds: 1));
    cl.forcerCreation = null;
    await t.tap(find.byKey(const ValueKey('client-vente-creer')));
    await app.attendre(t, const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('client-vente-nom')), findsOneWidget);
    // Retrait refusé (403), puis encaissement.
    cl.forcerRattachement = (_) => ClientsVenteFictifs.interdit403;
    await t.tap(find.byKey(const ValueKey('client-vente-retirer')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('client-vente-retirer')));
    await app.attendre(t, const Duration(seconds: 1));
    cl.forcerRattachement = null;
    await validerEncaissementEspeces(t, app);
    await app.attendre(t, const Duration(seconds: 2));
    expect(cl.clotures.single['clientId'], 'CL-CREE-1');
    debugPrint = avant;

    final journal = [for (final e in await JournalTerminal.instance.store.lire(const JournalFiltre())) jsonEncode(e.toJson())].join('\n');
    expect(journal, isNotEmpty, reason: 'journal du terminal actif (vente, encaissement)');
    final tout = '${console.join('\n')}\n$journal\n${support.filAriane.join('\n')}';
    for (final interdit in ['SECRETNOM', 'SECRETPRENOM', 'Secretnom', '0711223344', '0711', 'query=', 'CL-CREE-1']) {
      expect(tout.contains(interdit), isFalse, reason: 'journaux : « $interdit »');
    }
    await app.fermer(t);
  });
}
