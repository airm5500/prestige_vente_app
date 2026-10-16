// RÉSEAU — Empreintes partagées (4.4.0, demande 43) : coupures pendant l'envoi, la lecture et la suppression,
// puis reprise ; requêtes HTTP réelles (chemins, X-Client-Ref, « depuis ») contre un serveur local ; terminal à
// empreinte : synchronisation à l'ouverture puis toutes les 15 min. Gabarits FACTICES uniquement.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/rh/empreintes_partagees.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/rh/rh_store.dart';
import 'package:prestige_vente_app/rh/terminal_pointage_screen.dart';
import 'package:prestige_vente_app/services/nfc_service.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../empreintes_partagees_test.dart' show LecteurSimule, Terminal;
import '../outils/faux_serveur_empreintes.dart';
import '../outils/serveur_json_local.dart';

class _SansNfc implements NfcReader {
  @override
  Future<NfcAvailability> availability() async => NfcAvailability.absent;
  @override
  Stream<String> get tags => const Stream.empty();
  @override
  Future<bool> start() async => false;
  @override
  Future<void> stop() async {}
  @override
  Future<void> openSettings() async {}
}

void main() {
  late FauxServeurEmpreintes srv;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    srv = FauxServeurEmpreintes()..employesActifs.addAll(['E1', 'E2', 'E3']);
  });

  test('coupure AVANT l\'envoi : gardé « en attente », envoyé à la synchronisation suivante (une seule fois)', () async {
    final a = Terminal(srv, 'A');
    srv.coupe = true;
    final e = await a.enroler('E1', gabaritFactice(1));
    expect(e.envoiEnAttente, isTrue);
    expect(e.refEnvoi, startsWith('EMP-'));
    expect(srv.nombreModeles, 0);
    expect((await a.partage.synchroniser()).horsLigne, isTrue);
    srv.coupe = false;
    final b = await a.partage.synchroniser();
    expect(b.envoyes, 1);
    expect(srv.nombreModeles, 2);
    final apres = (await a.coffre.lire())['E1']!;
    expect(apres.envoiEnAttente, isFalse);
    expect(apres.idsServeur, hasLength(2));
    expect((await a.partage.synchroniser()).envoyes, 0);
    expect(srv.nombreModeles, 2, reason: 'aucun doublon');
  });

  test('coupure PENDANT l\'envoi (enregistré, réponse perdue) : même X-Client-Ref au nouvel essai → pas de doublon', () async {
    final a = Terminal(srv, 'A');
    srv.perdreReponseEnvoi = true;
    final e = await a.enroler('E1', gabaritFactice(2));
    expect(e.envoiEnAttente, isTrue);
    expect(srv.nombreModeles, 2, reason: 'le serveur a enregistré avant la coupure');
    final b = await a.partage.synchroniser();
    expect(b.envoyes, 1);
    expect(srv.nombreModeles, 2, reason: 'même référence = même réponse, rien de plus');
    expect((await a.coffre.lire())['E1']!.idsServeur, hasLength(2));
    expect(b.ajoutes, 0, reason: 'ses propres modèles reconnus par leur id');
  });

  test('coupure PENDANT la lecture : « depuis » n\'avance pas ; reprise : tout reçu une fois', () async {
    final a = Terminal(srv, 'A'), b = Terminal(srv, 'B');
    await a.enroler('E1', gabaritFactice(3));
    await a.enroler('E2', gabaritFactice(4));
    srv.coupe = true;
    final c = await b.partage.synchroniser();
    expect(c.horsLigne, isTrue);
    expect((await b.partage.statut()).depuis, isNull);
    expect(await b.coffre.lire(), isEmpty);
    srv.coupe = false;
    final r = await b.partage.synchroniser();
    expect(r.ajoutes, 4);
    final r2 = await b.partage.synchroniser();
    expect(r2.ajoutes, 0);
    expect((await b.coffre.lire()).values.expand((e) => e.modeles), hasLength(4));
  });

  test('coupure PENDANT la suppression : gardée, envoyée avant la lecture suivante ; les autres terminaux suivent', () async {
    final a = Terminal(srv, 'A'), b = Terminal(srv, 'B');
    await a.enroler('E1', gabaritFactice(5));
    await b.partage.synchroniser();
    srv.coupe = true;
    await a.id.supprimer('E1');
    await a.partage.supprimer('E1');
    expect((await a.partage.statut()).suppressionsEnAttente, ['E1']);
    srv.coupe = false;
    await a.partage.synchroniser();
    expect((await a.partage.statut()).suppressionsEnAttente, isEmpty);
    expect(srv.nombreModeles, 0);
    expect(srv.appels.indexWhere((x) => x.startsWith('DELETE')), lessThan(srv.appels.lastIndexOf('GET /rh/empreintes')));
    await b.partage.synchroniser();
    expect(await b.coffre.lire(), isEmpty);
  });

  test('HTTP réel : chemins, en-tête X-Client-Ref, « depuis » et « format », DELETE', () => avecVraiHttp(() async {
        final s = ServeurJsonLocal();
        await s.demarrer();
        addTearDown(s.arreter);
        s.routes['POST /rh/employes/E1/empreintes'] = (r) => const ReponseLocale({'success': true, 'nombre': 1, 'ids': ['ID-1']});
        s.routes['GET /rh/empreintes'] = (r) => const ReponseLocale({'success': true, 'horodatage': '2026-10-16T10:00:00', 'modeles': [], 'suppressions': []});
        s.routes['DELETE /rh/employes/E1/empreintes'] = (r) => const ReponseLocale({'success': true, 'nombre': 1});
        final rh = DioRhServeur(() => s.base);
        final coffre = CoffreEmpreintesMemoire();
        final p = EmpreintesPartagees(serveur: rh, coffre: coffre, journal: () => JournalTerminal(store: MemoryJournalStore()));
        final e = EmpreintesEmploye(employeId: 'E1', modeles: [gabaritFactice(6, 64)], consentementLe: DateTime(2026, 10, 16, 9), recueilliPar: 'admin', consentementPartage: true);
        await coffre.ecrire({'E1': e});
        expect(await p.envoyer(e), EtatPartageEmpreintes.actif);
        final post = s.recues.singleWhere((r) => r.methode == 'POST');
        expect(post.chemin, endsWith('/rh/employes/E1/empreintes'));
        expect(post.clientRef, startsWith('EMP-'));
        final corps = jsonDecode(post.corps) as Map;
        expect(corps['format'], formatEmpreinteSunmi);
        expect(corps['consentement'], {'le': '2026-10-16T09:00:00', 'par': 'admin'});
        expect((corps['modeles'] as List).single, base64Encode(gabaritFactice(6, 64)));
        await p.synchroniser();
        await p.synchroniser();
        final gets = s.recues.where((r) => r.methode == 'GET').toList();
        expect(gets.first.query, {'format': formatEmpreinteSunmi});
        expect(gets.last.query, {'format': formatEmpreinteSunmi, 'depuis': '2026-10-16T10:00:00'});
        await p.supprimer('E1');
        expect(s.recues.last.methode, 'DELETE');
        // Serveur sans la route : 404 → local seulement.
        s.routes.clear();
        await EmpreintesPartagees.oublier();
        expect((await p.synchroniser()).etat, EtatPartageEmpreintes.absent);
      }));

  testWidgets('terminal à empreinte : synchronisation à l\'ouverture puis toutes les 15 min ; sans lecteur : aucune', (t) async {
    t.view.physicalSize = const Size(720, 1440);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final a = Terminal(srv, 'source');
    await a.enroler('E1', gabaritFactice(7));
    final coffre = CoffreEmpreintesMemoire();
    final id = IdentificationEmploye(empreinte: LecteurSimule(gabaritFactice(7)), nfc: _SansNfc(), coffre: coffre);
    final rh = PointageRh(store: MemoryRhStore(), serveur: srv, identification: id, journal: () => JournalTerminal(store: MemoryJournalStore()));
    await rh.verifierAcces();
    await rh.rafraichirEmployes();
    int lectures() => srv.appels.where((x) => x == 'GET /rh/empreintes').length;
    final avant = lectures();
    await t.pumpWidget(MaterialApp(home: TerminalPointageScreen(rh: rh, identification: id, presentation: ListPresentation.dashboard, rafraichirAuDemarrage: false)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(lectures(), avant + 1, reason: 'à l\'ouverture');
    expect((await coffre.lire())['E1']?.modeles, hasLength(2), reason: 'modèles du serveur recopiés');
    expect(find.byKey(const Key('rh_empreinte')), findsOneWidget, reason: 'empreinte proposée dès la synchronisation');
    await t.pump(EmpreintesPartagees.intervalle);
    await t.pump();
    expect(lectures(), avant + 2, reason: 'toutes les 15 min');
    await t.pumpWidget(const SizedBox());
    await t.pump(EmpreintesPartagees.intervalle);
    expect(lectures(), avant + 2, reason: 'plus rien après la sortie du terminal');

    // Terminal sans lecteur d'empreinte : aucune lecture des gabarits.
    final sans = IdentificationEmploye(empreinte: const AucuneEmpreinte(), nfc: _SansNfc(), coffre: CoffreEmpreintesMemoire());
    final rh2 = PointageRh(store: MemoryRhStore(), serveur: srv, identification: sans, journal: () => JournalTerminal(store: MemoryJournalStore()));
    final n = lectures();
    await t.pumpWidget(MaterialApp(home: TerminalPointageScreen(rh: rh2, identification: sans, presentation: ListPresentation.dashboard, rafraichirAuDemarrage: false)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(lectures(), n);
    await t.pumpWidget(const SizedBox());
  });
}
