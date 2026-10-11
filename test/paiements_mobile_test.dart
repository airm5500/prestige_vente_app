// B3 — Paiement mobile money par agrégateur : désactivé par défaut, sans capacité, hors ligne, montant fixé
// par le serveur, attente → payé, expiré, échoué, annulation puis paiement tardif (à régulariser),
// idempotence (une seule création), comptoir (Wave seul et espèces + Wave), borne (QR → ticket PAYÉ),
// historique (groupes, PDF).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_kiosque.dart';
import 'package:prestige_vente_app/borne/borne_screen.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile_screen.dart';
import 'package:prestige_vente_app/parametres/parametres_logic.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/ventes/core/paiement_multiple.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/encaissement_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Faux module serveur : montant = net de la vente (jamais celui du téléphone), clé client idempotente.
class _Srv implements PaiementsMobileApi {
  List<String> ops = const ['orange', 'mtn', 'wave'];
  final Map<String, int> nets = {'V1': 12500};
  final Map<String, PaiementMobile> paiements = {};
  final Map<String, String> parCle = {};
  int creations = 0;
  int capacitesAppels = 0;
  int statuts = 0;
  bool autoClotureFaite = false;

  @override
  Future<VenteResult<CapacitesPM>> capacites() async {
    capacitesAppels++;
    return VenteOk(CapacitesPM(operateurs: ops, fournisseur: 'simulateur', expirationMin: 10));
  }

  @override
  Future<VenteResult<PaiementMobile>> creer({required String venteId, required String operateur, int? part, bool cloturer = false, required String cle}) async {
    final deja = parCle[cle];
    if (deja != null) return VenteOk(paiements[deja]!);
    final net = nets[venteId];
    if (net == null) return const VenteRefused('Vente introuvable.');
    if (part != null && (part <= 0 || part > net)) return VenteRefused('Montant du paiement invalide (1 à $net).');
    creations++;
    final id = 'PM$creations';
    final p = PaiementMobile(
        id: id, venteId: venteId, reference: 'R-$venteId', montant: part ?? net, operateur: operateur, statut: StatutPM.enAttente,
        lien: 'simulateur://payer/$id', clotureAuto: cloturer && part == null);
    paiements[id] = p;
    parCle[cle] = id;
    return VenteOk(p);
  }

  void _maj(String id, StatutPM s, {bool? cloture}) {
    final p = paiements[id]!;
    paiements[id] = PaiementMobile(
        id: p.id, venteId: p.venteId, reference: p.reference, montant: p.montant, operateur: p.operateur, statut: s, lien: p.lien,
        clotureAuto: p.clotureAuto, cloture: cloture ?? p.cloture, creeLe: '2026-10-11 10:15:00.0');
  }

  /// Le client paie chez l'opérateur (notification + revérification côté serveur).
  void payer(String id) {
    final s = paiements[id]!.statut;
    final n = switch (s) {
      StatutPM.enAttente || StatutPM.echoue => StatutPM.paye,
      StatutPM.annule || StatutPM.expire => StatutPM.payeApresAnnulation,
      _ => s,
    };
    _maj(id, n, cloture: n == StatutPM.paye && paiements[id]!.clotureAuto);
    if (n == StatutPM.paye && paiements[id]!.clotureAuto) autoClotureFaite = true;
  }

  void etat(String id, StatutPM s) => _maj(id, s);

  @override
  Future<VenteResult<PaiementMobile>> statut(String id) async {
    statuts++;
    return VenteOk(paiements[id]!);
  }

  @override
  Future<VenteResult<PaiementMobile>> annuler(String id) async {
    if (paiements[id]!.statut == StatutPM.enAttente) _maj(id, StatutPM.annule);
    return VenteOk(paiements[id]!);
  }

  @override
  Future<VenteResult<List<PaiementMobile>>> historique(DateTime jour) async => VenteOk(paiements.values.toList());
}

PaiementsMobile _pm(_Srv s, {bool horsLigne = false}) => PaiementsMobile(api: s, horsLigne: () => horsLigne);

JournalTerminal _journal() {
  final prev = JournalTerminal.instance;
  final j = JournalTerminal(clock: DateTime.now)..utilisateur = 'Awa';
  JournalTerminal.instance = j;
  addTearDown(() => JournalTerminal.instance = prev);
  return j;
}

void _phone(WidgetTester tester, [Size s = const Size(360, 760)]) {
  tester.view.physicalSize = s * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

/// Avance l'horloge du test par pas (minuteries de l'attente).
Future<void> _avancer(WidgetTester tester, Duration d) async {
  const pas = Duration(milliseconds: 250);
  for (var t = Duration.zero; t < d; t += pas) {
    await tester.pump(pas);
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'enabled_payment_method_ids': ['1', '10', '7'],
    });
    PaiementsMobileReglages.actif.value = false;
  });

  group('Disponibilité', () {
    test('désactivé par défaut : aucun opérateur, aucune requête', () async {
      await PaiementsMobileReglages.charger();
      expect(PaiementsMobileReglages.actif.value, isFalse);
      final s = _Srv();
      expect(await _pm(s).operateurs(), isEmpty);
      expect(s.capacitesAppels, 0);
      expect(Rubrique.paiementsMobile.locked, isTrue);
      expect(operateurDuMode('10'), 'wave');
      expect(operateurDuMode('7'), 'orange');
      expect(operateurDuMode('1'), isNull);
    });

    test('activé : opérateurs du serveur ; sans capacité (module absent / non configuré) : rien', () async {
      PaiementsMobileReglages.actif.value = true;
      final s = _Srv();
      expect(await _pm(s).operateurs(), ['orange', 'mtn', 'wave']);
      s.ops = const [];
      expect(await _pm(s).operateurs(), isEmpty);
    });

    test('hors ligne : mobile money indisponible (espèces seulement)', () async {
      PaiementsMobileReglages.actif.value = true;
      final s = _Srv();
      expect(await _pm(s, horsLigne: true).operateurs(), isEmpty);
      expect(s.capacitesAppels, 0);
    });
  });

  group('Attente', () {
    test('montant fixé par le serveur ; part d\'un paiement en deux modes contrôlée', () async {
      final s = _Srv();
      final a = AttentePaiement(s, intervalle: const Duration(hours: 1));
      await a.demarrer(venteId: 'V1', operateur: 'wave');
      expect(a.paiement!.montant, 12500);
      final b = AttentePaiement(s, intervalle: const Duration(hours: 1));
      await b.demarrer(venteId: 'V1', operateur: 'wave', part: 20000);
      expect(b.paiement, isNull);
      expect(b.erreur, contains('invalide'));
      a.dispose();
      b.dispose();
    });

    test('attente → payé (journal), échoué, expiré', () async {
      final j = _journal();
      final s = _Srv();
      final a = AttentePaiement(s, intervalle: const Duration(hours: 1));
      await a.demarrer(venteId: 'V1', operateur: 'wave');
      await a.interroger();
      expect(a.statut, StatutPM.enAttente);
      s.payer('PM1');
      await a.interroger();
      expect(a.statut, StatutPM.paye);
      expect(a.termine, isTrue);
      final e = await j.lire();
      expect(e.map((x) => x.action), containsAll(['Paiement mobile money demandé', 'Paiement mobile money reçu']));
      expect(e.firstWhere((x) => x.action == 'Paiement mobile money reçu').montant, 12500);

      final b = AttentePaiement(s, intervalle: const Duration(hours: 1));
      await b.demarrer(venteId: 'V1', operateur: 'orange');
      s.etat(b.paiement!.id, StatutPM.echoue);
      await b.interroger();
      expect(b.statut, StatutPM.echoue);

      final c = AttentePaiement(s, intervalle: const Duration(hours: 1), delai: Duration.zero);
      await c.demarrer(venteId: 'V1', operateur: 'mtn');
      expect(c.reste, 0);
      s.etat(c.paiement!.id, StatutPM.expire);
      await c.interroger();
      expect(c.statut, StatutPM.expire);
      for (final x in [a, b, c]) {
        x.dispose();
      }
    });

    test('annulation puis paiement tardif : « à régulariser », jamais encaissé deux fois', () async {
      final j = _journal();
      final s = _Srv();
      final a = AttentePaiement(s, intervalle: const Duration(hours: 1));
      await a.demarrer(venteId: 'V1', operateur: 'wave');
      await a.annuler();
      expect(a.statut, StatutPM.annule);
      s.payer('PM1');
      expect(await a.verifierApresAnnulation(), StatutPM.payeApresAnnulation);
      expect(a.paiement!.aRegulariser, isTrue);
      expect((await j.lire()).any((e) => e.action.contains('à régulariser')), isTrue);
      a.dispose();
    });

    test('idempotence : double appui = une seule création ; réessai = même paiement (clé client)', () async {
      final s = _Srv();
      final a = AttentePaiement(s, intervalle: const Duration(hours: 1));
      await Future.wait([a.demarrer(venteId: 'V1', operateur: 'wave'), a.demarrer(venteId: 'V1', operateur: 'wave')]);
      expect(s.creations, 1);
      // Même clé renvoyée (réponse perdue) : le serveur rend le paiement existant.
      final cle = s.parCle.keys.single;
      final r = await s.creer(venteId: 'V1', operateur: 'wave', cle: cle);
      expect(r.valueOrNull!.id, 'PM1');
      expect(s.creations, 1);
      a.dispose();
    });
  });

  group('Comptoir', () {
    final methodes = [PaymentMethod(id: '1', name: 'Especes'), PaymentMethod(id: '10', name: 'WAVE'), PaymentMethod(id: '7', name: 'ORANGE')];

    Future<({List<String> simples, List<List<ReglementLigne>> multiples})> ouvrir(WidgetTester tester, _Srv srv, {bool actif = true}) async {
      final simples = <String>[];
      final multiples = <List<ReglementLigne>>[];
      final settings = SettingsProvider();
      await settings.loadSettings();
      PaiementsMobileReglages.actif.value = actif;
      final page = EncaissementPage(
        actions: EncaissementActions(
          paymentMethods: () async => VenteOk(methodes),
          loadQrMethods: () async {},
          qrFor: (_) => null,
          encaisser: (m, r, remis) async {
            simples.add(m.id);
            return const VenteOk((dejaCloturee: false));
          },
          encaisserReglements: (l, r, remis) async {
            multiples.add(l);
            return const VenteOk((dejaCloturee: false));
          },
        ),
        expectedChanges: 1,
        summary: SaleSummary(montant: 12500, montantNet: 12500, reference: 'PV-1', venteId: 'V1'),
        itemCount: 2,
        initialCopies: 1,
        paiementsMobile: _pm(srv),
      );
      await tester.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => page)),
                  child: const Text('Ouvrir'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      return (simples: simples, multiples: multiples);
    }

    Future<void> voir(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pump();
    }

    testWidgets('Wave seul : QR du montant exact, « Paiement reçu ✓ » automatique, puis encaissement', (tester) async {
      _phone(tester, const Size(400, 900));
      _journal();
      final srv = _Srv();
      final r = await ouvrir(tester, srv);
      await tester.tap(find.byKey(const ValueKey('mode-10')));
      await tester.pumpAndSettle();
      final qr = find.byKey(const ValueKey('pm-qr-unique'));
      await voir(tester, qr);
      await tester.tap(qr);
      await _avancer(tester, const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('pm-qr')), findsOneWidget);
      expect(find.byKey(const ValueKey('pm-attente')), findsOneWidget);
      expect(find.textContaining('12'), findsWidgets);
      expect(srv.paiements['PM1']!.montant, 12500);
      srv.payer('PM1');
      await _avancer(tester, const Duration(seconds: 4));
      expect(r.simples, ['10'], reason: 'encaissement après le paiement reçu');
      expect(tester.takeException(), isNull);
    });

    testWidgets('espèces + Wave : part Wave payée par QR, « Reçu » coché, une clôture à 2 règlements', (tester) async {
      _phone(tester, const Size(400, 900));
      _journal();
      final srv = _Srv();
      final r = await ouvrir(tester, srv);
      final ajouter = find.byKey(const ValueKey('paiement-ajouter-mode'));
      await voir(tester, ajouter);
      await tester.tap(ajouter);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ajout-mode-10')));
      await tester.pumpAndSettle();
      final m1 = find.byKey(const ValueKey('reglement-montant-1'));
      await voir(tester, m1);
      await tester.enterText(m1, '5000');
      await tester.pumpAndSettle();
      final recu = find.byKey(const ValueKey('reglement-recu-montant-1'));
      await voir(tester, recu);
      await tester.enterText(recu, '5000');
      await tester.pumpAndSettle();
      final qr = find.byKey(const ValueKey('pm-qr-10'));
      await voir(tester, qr);
      await tester.tap(qr);
      await _avancer(tester, const Duration(milliseconds: 500));
      expect(srv.paiements['PM1']!.montant, 7500, reason: 'part Wave contrôlée par le serveur');
      srv.payer('PM1');
      await _avancer(tester, const Duration(seconds: 4));
      await tester.pumpAndSettle();
      final valider = find.byKey(const ValueKey('encaissement-valider'));
      await voir(tester, valider);
      await tester.tap(valider);
      await tester.pumpAndSettle();
      final l = r.multiples.single;
      expect(l.map((x) => (x.method.id, x.montant)), [('1', 5000), ('10', 7500)]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('désactivé : aucun bouton QR, écran d\'origine', (tester) async {
      _phone(tester, const Size(400, 900));
      final srv = _Srv();
      await ouvrir(tester, srv, actif: false);
      await tester.tap(find.byKey(const ValueKey('mode-10')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pm-qr-unique')), findsNothing);
      expect(srv.capacitesAppels, 0);
    });
  });

  group('Borne', () {
    testWidgets('mobile money : opérateur, QR du montant exact, payé → ticket « PAYÉ » avec les produits', (tester) async {
      _phone(tester);
      _journal();
      PaiementsMobileReglages.actif.value = true;
      final srv = _Srv()..nets['V1'] = 3000;
      final gw = _Gw();
      final imp = _Imp();
      BorneKiosque.instance = KiosqueSimule();
      await tester.pumpWidget(MaterialApp(
        home: BorneScreen(
          service: BorneService(gw),
          config: const BorneConfig(actif: true, login: 'b'),
          monitor: ServerMonitor(),
          imprimante: imp,
          kiosque: KiosqueSimule(),
          adminCheck: (_) async => true,
          onSortie: (_) {},
          paiementsMobile: _pm(srv),
        ),
      ));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('borne-recherche')), 'doli');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('borne-ajouter-P1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('borne-voir-panier')));
      await tester.pump();
      final mobile = find.byKey(const ValueKey('borne-payer-mobile'));
      await tester.ensureVisible(mobile);
      await tester.pump();
      await tester.tap(mobile);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('borne-operateur-wave')));
      await _avancer(tester, const Duration(milliseconds: 500));
      expect(gw.terminees, 1, reason: 'prévente créée avant le paiement');
      expect(find.byKey(const ValueKey('pm-qr')), findsOneWidget);
      expect(srv.paiements['PM1']!.clotureAuto, isTrue, reason: 'la borne demande la clôture par le serveur');
      srv.payer('PM1');
      await _avancer(tester, const Duration(seconds: 4));
      expect(srv.autoClotureFaite, isTrue);
      final t = imp.tickets.single;
      expect(t.paye, isTrue);
      expect(t.titre, contains('PAYEE'));
      expect(t.lignes.join(' '), contains('DOLIPRANE'));
      expect(t.lignes.join(' '), contains('PAYE PAR WAVE'));
      expect(find.byKey(const ValueKey('borne-numero')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('mobile money annulé : « Payer en caisse » imprime le ticket de prévente', (tester) async {
      _phone(tester);
      _journal();
      PaiementsMobileReglages.actif.value = true;
      final srv = _Srv()..nets['V1'] = 3000;
      final imp = _Imp();
      await tester.pumpWidget(MaterialApp(
        home: BorneScreen(
          service: BorneService(_Gw()),
          config: const BorneConfig(actif: true, login: 'b'),
          monitor: ServerMonitor(),
          imprimante: imp,
          kiosque: KiosqueSimule(),
          adminCheck: (_) async => true,
          onSortie: (_) {},
          paiementsMobile: _pm(srv),
          intervallePaiement: const Duration(seconds: 1),
        ),
      ));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('borne-recherche')), 'doli');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('borne-ajouter-P1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('borne-voir-panier')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('borne-payer-mobile')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('borne-payer-mobile')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('borne-operateur-orange')));
      await _avancer(tester, const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('pm-annuler')));
      await _avancer(tester, const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('pm-fin')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('borne-mobile-caisse')));
      await tester.pump();
      await tester.pump();
      expect(imp.tickets.single.paye, isFalse);
      expect(imp.tickets.single.titre, 'PRE-VENTE BORNE');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('sans module (désactivé) : seulement « Payer en caisse »', (tester) async {
      _phone(tester);
      final srv = _Srv();
      await tester.pumpWidget(MaterialApp(
        home: BorneScreen(
          service: BorneService(_Gw()),
          config: const BorneConfig(actif: true, login: 'b'),
          monitor: ServerMonitor(),
          imprimante: _Imp(),
          kiosque: KiosqueSimule(),
          adminCheck: (_) async => true,
          onSortie: (_) {},
          paiementsMobile: _pm(srv),
        ),
      ));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('borne-recherche')), 'doli');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('borne-ajouter-P1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('borne-voir-panier')));
      await tester.pump();
      expect(find.byKey(const ValueKey('borne-payer')), findsOneWidget);
      expect(find.byKey(const ValueKey('borne-payer-mobile')), findsNothing);
      expect(srv.capacitesAppels, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  testWidgets('historique : groupes (à régulariser en tête, alerte), total des reçus, PDF', (tester) async {
    _phone(tester, const Size(400, 900));
    final srv = _Srv();
    for (final op in ['wave', 'orange', 'mtn', 'wave']) {
      await srv.creer(venteId: 'V1', operateur: op, cle: 'c-$op-${srv.creations}');
    }
    srv.payer('PM1');
    srv.etat('PM2', StatutPM.echoue);
    srv.etat('PM4', StatutPM.annule);
    srv.payer('PM4');
    Uint8List? pdf;
    await tester.pumpWidget(MaterialApp(home: PaiementsMobileScreen(api: srv, jour: DateTime(2026, 10, 11), partagerPdf: (b) async => pdf = b)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pm-alerte-regulariser')), findsOneWidget);
    expect(find.textContaining('À régulariser (1)'), findsOneWidget);
    expect(find.textContaining('Reçus (1)'), findsOneWidget);
    expect(find.textContaining('En attente (1)'), findsOneWidget);
    expect(find.textContaining('Échoués'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pm-pdf')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    expect(pdf, isNotNull);
    expect(String.fromCharCodes(pdf!.take(4)), '%PDF');
  });
}

ProductSearchResult _p(String id, String nom, int prix, int stock) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: nom, intCIP: '1$id', intPRICE: prix, intNUMBERAVAILABLE: stock, strLIBELLEE: '', intPAF: 0);

class _Gw implements VenteGateway {
  final produits = [_p('P1', 'DOLIPRANE 1000MG CP', 3000, 10)];
  int terminees = 0;
  final ajouts = <int>[];

  @override
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async => VenteOk(ProductPage(produits, produits.length));
  @override
  Future<VenteResult<String>> addItemVno({required String produitId, required int qte, required int itemPu, String? venteId, required bool prevente}) async {
    ajouts.add(qte);
    return const VenteOk('V1');
  }

  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) async => VenteOk(SaleSummary(montant: 3000, montantNet: 3000, reference: '261011_00042', venteId: 'V1'));
  @override
  Future<VenteResult<void>> terminerPrevente(String venteId) async {
    terminees++;
    return const VenteOk(null);
  }

  @override
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async => VenteOk([
        SaleItemDetail(
            lgPREENREGISTREMENTDETAILID: 'D1', lgFAMILLEID: 'P1', strNAME: 'DOLIPRANE 1000MG CP', intCIP: '1P1', intQUANTITY: 1, intPRICEUNITAIR: 3000, intPRICE: 3000, strREF: '261011_00042')
      ]);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _Imp implements BorneImprimante {
  final tickets = <BorneTicket>[];
  @override
  Future<bool> imprimer(BorneTicket t) async {
    tickets.add(t);
    return true;
  }
}
