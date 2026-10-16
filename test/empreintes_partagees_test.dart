// 4.4.0 — Empreintes partagées entre terminaux de pointage (demande 43, serveur du 16/10/2026).
// Deux terminaux V3H simulés (coffres et états séparés) et le faux serveur des empreintes (règles du vrai) :
// enrôlement sur A → envoi ; synchronisation de B → reconnaissance sur B ; incrémental ; suppression ; partage
// désactivé ou serveur sans les routes → comportement d'avant (local), sans erreur ; consentement adapté ;
// jamais de gabarit dans les journaux. Gabarits FACTICES uniquement.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/rh/empreintes_partagees.dart';
import 'package:prestige_vente_app/rh/empreintes_screen.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/rh/rh_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/faux_serveur_empreintes.dart';

final _consentement = DateTime(2026, 10, 16, 9);

/// Lecteur simulé : reconnaît le doigt dont le gabarit est [doigt] (comparaison exacte des octets factices).
class LecteurSimule implements FournisseurEmpreinte {
  Uint8List? doigt;
  int captures = 0;
  LecteurSimule([this.doigt]);
  @override
  Future<bool> disponible() async => true;
  @override
  Future<Uint8List> enroler() async {
    captures++;
    return doigt!;
  }

  @override
  Future<int?> identifier(List<Uint8List> modeles) async {
    for (var i = 0; i < modeles.length; i++) {
      if (listEquals(modeles[i], doigt)) return i;
    }
    return null;
  }

  @override
  Future<void> annuler() async {}
}

class Terminal {
  final CoffreEmpreintesMemoire coffre = CoffreEmpreintesMemoire();
  final JournalTerminal journal = JournalTerminal(store: MemoryJournalStore());
  final LecteurSimule lecteur = LecteurSimule();
  late final IdentificationEmploye id = IdentificationEmploye(empreinte: lecteur, coffre: coffre);
  late final EmpreintesPartagees partage;
  Terminal(FauxServeurEmpreintes s, String nom) {
    partage = EmpreintesPartagees(serveur: s, coffre: coffre, journal: () => journal, cle: 'rh_empreintes_partage_$nom', clock: () => DateTime(2026, 10, 16, 10));
  }

  Future<EmpreintesEmploye> enroler(String employeId, Uint8List g, {bool partageConsenti = true}) async {
    final e = EmpreintesEmploye(employeId: employeId, employeNom: 'TEST $employeId', modeles: [g, g], consentementLe: _consentement, recueilliPar: 'admin', consentementPartage: partageConsenti);
    await id.enregistrer(e);
    await partage.envoyer(e);
    return (await coffre.lire())[employeId]!;
  }
}

EmployeRh _emp(String id) => EmployeRh.fromJson({'id': id, 'matricule': 'M-$id', 'badge': 'B-$id', 'nom': 'TEST', 'prenoms': id, 'statut': 'ACTIF'});

void main() {
  late FauxServeurEmpreintes srv;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    srv = FauxServeurEmpreintes()..employesActifs.addAll(['E1', 'E2', 'E3']);
  });

  group('unitaire / intégration', () {
    test('enrôlé sur A → envoyé (ids gardés) ; B synchronise → reconnu sur B ; incrémental : rien de nouveau', () async {
      final a = Terminal(srv, 'A'), b = Terminal(srv, 'B');
      final g = gabaritFactice(1);
      final e = await a.enroler('E1', g);
      expect(e.idsServeur, hasLength(2));
      expect(e.envoiEnAttente, isFalse);
      expect(srv.modelesDe('E1'), [base64Encode(g), base64Encode(g)]);
      expect((await a.partage.statut()).etat, EtatPartageEmpreintes.actif);

      final bilan = await b.partage.synchroniser();
      expect(bilan.etat, EtatPartageEmpreintes.actif);
      expect(bilan.ajoutes, 2);
      final surB = (await b.coffre.lire())['E1']!;
      expect(surB.modeles.map(base64Encode), [base64Encode(g), base64Encode(g)], reason: 'gabarits identiques à l\'envoi');
      b.lecteur.doigt = g;
      expect((await b.id.parEmpreinte([_emp('E1'), _emp('E2')]))?.id, 'E1', reason: 'reconnu sur le second terminal');

      final st = await b.partage.statut();
      expect(st.depuis, isNotNull);
      final avant = srv.appels.length;
      final b2 = await b.partage.synchroniser();
      expect([b2.ajoutes, b2.retires], [0, 0]);
      expect(srv.appels.length, avant + 1);
      // A synchronise : ses propres modèles reviennent avec les mêmes ids → pas de doublon.
      final ba = await a.partage.synchroniser();
      expect(ba.ajoutes, 0);
      expect((await a.coffre.lire())['E1']!.modeles, hasLength(2));
    });

    test('suppression dans l\'application → DELETE ; les autres terminaux la reçoivent ; ré-enrôlement : anciens retirés', () async {
      final a = Terminal(srv, 'A'), b = Terminal(srv, 'B');
      await a.enroler('E1', gabaritFactice(1));
      await a.enroler('E2', gabaritFactice(2));
      await b.partage.synchroniser();
      expect((await b.coffre.lire()).keys, containsAll(['E1', 'E2']));
      await a.id.supprimer('E1');
      await a.partage.supprimer('E1');
      expect(srv.appels.last, 'DELETE /rh/employes/E1/empreintes');
      final bilan = await b.partage.synchroniser();
      expect(bilan.retires, 2);
      expect((await b.coffre.lire()).keys, ['E2']);
      // Employé devenu inactif sur le serveur : purgé et signalé.
      srv.employesActifs.remove('E2');
      final b2 = await b.partage.synchroniser();
      expect(b2.retires, 2);
      expect(await b.coffre.lire(), isEmpty);
    });

    test('partage désactivé sur le serveur : enrôlement local gardé, aucune erreur, état « désactivé »', () async {
      srv.actif = false;
      final a = Terminal(srv, 'A');
      final e = await a.enroler('E1', gabaritFactice(3));
      expect(e.modeles, hasLength(2));
      expect(e.envoiEnAttente, isFalse);
      expect(e.partage, isFalse);
      final st = await a.partage.statut();
      expect(st.etat, EtatPartageEmpreintes.desactive);
      expect(texteStatutEmpreintes(st, 1), 'Empreintes : 1 employé sur ce terminal — partage désactivé sur le serveur');
      expect((await a.partage.synchroniser()).etat, EtatPartageEmpreintes.desactive);
      expect((await a.coffre.lire())['E1']!.modeles, hasLength(2), reason: 'rien n\'est effacé');
    });

    test('serveur sans les routes (404) : comportement d\'avant (local seulement), aucune suppression envoyée', () async {
      srv.sansRoutes = true;
      final a = Terminal(srv, 'A');
      await a.enroler('E1', gabaritFactice(4));
      expect((await a.partage.statut()).etat, EtatPartageEmpreintes.absent);
      expect((await a.partage.synchroniser()).etat, EtatPartageEmpreintes.absent);
      final n = srv.appels.length;
      await a.partage.supprimer('E1');
      expect(srv.appels.length, n, reason: 'serveur sans partage : aucune requête');
      expect(texteStatutEmpreintes(await a.partage.statut(), 1), contains('serveur sans partage'));
    });

    test('consentement sans partage : jamais envoyé ; droit refusé : état « refusé », local gardé', () async {
      final a = Terminal(srv, 'A');
      await a.enroler('E1', gabaritFactice(5), partageConsenti: false);
      expect(srv.nombreModeles, 0, reason: 'consentement donné pour ce terminal seulement');
      srv.refus = true;
      await a.enroler('E2', gabaritFactice(6));
      expect(srv.nombreModeles, 0);
      expect((await a.partage.statut()).etat, EtatPartageEmpreintes.refuse);
      expect((await a.coffre.lire()).keys, containsAll(['E1', 'E2']));
    });

    test('statut lisible : N employés, dernière synchronisation', () {
      final s = StatutPartageEmpreintes(etat: EtatPartageEmpreintes.actif, derniere: DateTime(2026, 10, 16, 10, 5));
      expect(texteStatutEmpreintes(s, 12), 'Empreintes : 12 employés, dernière synchronisation le 16/10/2026 à 10:05');
      expect(texteStatutEmpreintes(const StatutPartageEmpreintes(), 0), contains('pas encore vérifié'));
      expect(StatutPartageEmpreintes.fromJson(s.copie(suppressionsEnAttente: ['E9']).toJson()).suppressionsEnAttente, ['E9']);
    });

    test('jamais de gabarit dans le journal du terminal, ni dans l\'état enregistré', () async {
      final a = Terminal(srv, 'A'), b = Terminal(srv, 'B');
      final g = gabaritFactice(7);
      await a.enroler('E1', g);
      await b.partage.synchroniser();
      await a.partage.supprimer('E1');
      await b.partage.synchroniser();
      final b64 = base64Encode(g);
      for (final t in [a, b]) {
        await t.journal.idle;
        final lignes = await t.journal.lire();
        expect(lignes, isNotEmpty);
        for (final l in lignes) {
          expect(l.action.contains(b64.substring(0, 24)), isFalse);
        }
      }
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        expect('${prefs.get(k)}'.contains(b64.substring(0, 24)), isFalse, reason: 'préférence $k');
      }
    });
  });

  group('écran des empreintes (enrôlement, consentement, suppression)', () {
    late Terminal t;
    late PointageRh rh;
    setUp(() {
      t = Terminal(srv, 'ecran');
      rh = PointageRh(store: MemoryRhStore(), serveur: srv, identification: t.id, clock: () => DateTime(2026, 10, 16, 9), journal: () => t.journal);
    });

    Future<void> ouvrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(720, 1440);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      srv.employesActifs
        ..clear()
        ..addAll(['E1', 'E2']);
      await rh.verifierAcces();
      await rh.rafraichirEmployes();
      expect(rh.acces, AccesRh.autorise);
      await tester.pumpWidget(MaterialApp(home: EmpreintesScreen(rh: rh, identification: t.id, codeAdmin: (_) async => true)));
      await tester.pumpAndSettle();
    }

    testWidgets('partage actif : texte « conservé chiffré sur le serveur… reconnu sur tous ses terminaux », envoi, statut', (tester) async {
      await ouvrir(tester);
      expect(find.byKey(const Key('rh_empreintes_statut')), findsOneWidget);
      expect(find.textContaining('Empreintes : 0 employé, dernière synchronisation'), findsOneWidget);
      t.lecteur.doigt = gabaritFactice(8);
      await tester.tap(find.byKey(const Key('rh_enroler_E1')));
      await tester.pumpAndSettle();
      final texte = tester.widget<Text>(find.byKey(const Key('rh_consentement_texte'))).data!;
      expect(texte, texteConsentementEmpreintePartagee);
      expect(texte, contains('conservé chiffré sur le serveur de la pharmacie'));
      expect(texte, contains('reconnu sur tous ses terminaux'));
      expect(texte, isNot(contains('jamais envoyé au serveur')));
      await tester.ensureVisible(find.byKey(const Key('rh_consentement_coche')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rh_consentement_coche')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('rh_consentement_ok')));
      await tester.pumpAndSettle();
      expect(find.textContaining('partagées avec les autres terminaux'), findsOneWidget);
      expect(srv.modelesDe('E1'), hasLength(3), reason: '3 captures envoyées');
      expect(find.textContaining('Empreintes : 1 employé, dernière synchronisation'), findsOneWidget);
      // Suppression : du serveur aussi.
      await tester.tap(find.byKey(const Key('rh_supprimer_E1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('effacées du serveur et de tous les terminaux'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rh_supprimer_ok')));
      await tester.pumpAndSettle();
      expect(srv.modelesDe('E1'), isEmpty);
      expect(await t.coffre.lire(), isEmpty);
    });

    testWidgets('serveur sans partage : texte d\'avant (sur ce terminal), rien envoyé, aucune erreur', (tester) async {
      srv.sansRoutes = true;
      await ouvrir(tester);
      expect(find.textContaining('serveur sans partage des empreintes'), findsOneWidget);
      t.lecteur.doigt = gabaritFactice(9);
      await tester.tap(find.byKey(const Key('rh_enroler_E2')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('rh_consentement_texte'))).data, texteConsentementEmpreinte);
      await tester.ensureVisible(find.byKey(const Key('rh_consentement_coche')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rh_consentement_coche')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('rh_consentement_ok')));
      await tester.pumpAndSettle();
      expect(find.text('Empreintes de TEST E2 enregistrées et reconnues.'), findsOneWidget);
      expect(srv.nombreModeles, 0);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('réglages du terminal (Équipe & pointage) : « Empreintes : N employés, dernière synchronisation … »', (tester) async {
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final a = Terminal(srv, 'reglages');
    await a.enroler('E1', gabaritFactice(10));
    // L'écran des réglages lit l'état enregistré par défaut de ce terminal.
    SharedPreferences.setMockInitialValues({
      EmpreintesPartagees.pref: jsonEncode(StatutPartageEmpreintes(etat: EtatPartageEmpreintes.actif, derniere: DateTime(2026, 10, 16, 10, 5)).toJson()),
    });
    await tester.pumpWidget(MaterialApp(home: EquipePage(repository: MemoryPointageRepository(), coffreEmpreintes: a.coffre)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('rh_reglage_empreintes')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Empreintes : 1 employé, dernière synchronisation le 16/10/2026 à 10:05'), findsOneWidget);
    SharedPreferences.setMockInitialValues({
      EmpreintesPartagees.pref: jsonEncode(const StatutPartageEmpreintes(etat: EtatPartageEmpreintes.desactive).toJson()),
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(home: EquipePage(repository: MemoryPointageRepository(), coffreEmpreintes: a.coffre)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('rh_reglage_empreintes')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Empreintes : 1 employé sur ce terminal — partage désactivé sur le serveur'), findsOneWidget);
  });
}
