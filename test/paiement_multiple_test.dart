// Paiement en plusieurs modes (2 maximum) : règles de répartition (reste, dépassement, doublon, raccourcis),
// requête de clôture (2 règlements, somme = net ; 1 mode = requête identique à avant), espèces + monnaie,
// mobile non confirmé bloquant, double tap = 1 clôture, réponse perdue, part client assurance, 360 px A/B/C.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_controller.dart';
import 'package:prestige_vente_app/ventes/core/paiement_multiple.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/encaissement_page.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _esp = PaymentMethod(id: '1', name: 'Espèces');
final _wave = PaymentMethod(id: '10', name: 'WAVE');
final _orange = PaymentMethod(id: '7', name: 'ORANGE');

/// PNG 1×1 (QR factice).
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

SaleItemDetail _item(String id, int qty, int pu) => SaleItemDetail(
      lgPREENREGISTREMENTDETAILID: 'V1-$id',
      lgFAMILLEID: id,
      strNAME: 'PRODUIT $id',
      intCIP: '340000000$id',
      intQUANTITY: qty,
      intPRICEUNITAIR: pu,
      intPRICE: qty * pu,
      strREF: 'REF-V1',
    );

enum _Close { ok, lostNotApplied, lostApplied }

/// Fausse passerelle : vente V1 de 12 500 F ; clôtures enregistrées (un mode / plusieurs modes).
class _Gw implements VenteGateway {
  Duration delay = const Duration(milliseconds: 20);
  _Close mode = _Close.ok;
  String statut = 'pending';
  final items = [_item('P1', 2, 1500), _item('P2', 1, 6500), _item('P3', 1, 3000)];
  final List<({String type, int? recu, int? remis})> simples = [];
  final List<({List<VenteReglement> reglements, int recu, int remis, String clientId})> multiples = [];
  final List<({List<VenteReglement> reglements, int recu, int remis, int net})> assurances = [];
  int assuranceNet = 3000;

  Future<void> _wait() => Future.delayed(delay);

  @override
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async {
    await _wait();
    return VenteOk(List.of(items));
  }

  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) async {
    await _wait();
    final total = items.fold<int>(0, (s, i) => s + i.intPRICE);
    return VenteOk(SaleSummary(montant: total, montantNet: total, venteId: venteId, reference: 'PV-000123'));
  }

  @override
  Future<VenteResult<void>> updateClient(String venteId, String clientId) async => const VenteOk(null);

  VenteResult<Map<String, dynamic>> _close() {
    if (statut == 'is_Closed') return const VenteRefused('Cette vente a déjà été clôturée');
    switch (mode) {
      case _Close.lostNotApplied:
        return const VenteFailed('Le serveur met trop de temps à répondre.', maybeApplied: true);
      case _Close.lostApplied:
        statut = 'is_Closed';
        return const VenteFailed('Le serveur met trop de temps à répondre.', maybeApplied: true);
      case _Close.ok:
        statut = 'is_Closed';
        return const VenteOk({'success': true});
    }
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> cloturerVno({
    required String venteId,
    required SaleSummary summary,
    required String typeReglementId,
    required String clientId,
    required String userVendeurId,
    int? montantRecu,
    int? montantRemis,
  }) async {
    simples.add((type: typeReglementId, recu: montantRecu, remis: montantRemis));
    await _wait();
    return _close();
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> cloturerVnoReglements({
    required String venteId,
    required SaleSummary summary,
    required List<VenteReglement> reglements,
    required String clientId,
    required String userVendeurId,
    required int montantRecu,
    required int montantRemis,
  }) async {
    multiples.add((reglements: reglements, recu: montantRecu, remis: montantRemis, clientId: clientId));
    await _wait();
    final invalid = reglementsInvalides(reglements, summary.montantNet);
    if (invalid != null) return VenteRefused(invalid);
    return _close();
  }

  @override
  Future<VenteResult<List<PaymentMethod>>> paymentMethods() async {
    await _wait();
    return VenteOk([_esp, _wave, _orange]);
  }

  @override
  Future<VenteResult<List<PaymentMethodQr>>> paymentMethodsWithQr() async => VenteOk([PaymentMethodQr(id: '10', name: 'WAVE', qrCode: _png)]);

  @override
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId) async {
    await _wait();
    return VenteOk({'strSTATUT': statut});
  }

  // --- Assurance (part client) ---
  @override
  Future<VenteResult<String>> addItemAssurance({
    required String produitId,
    required int qte,
    required int itemPu,
    required String clientId,
    required String ayantDroitId,
    required String natureVenteId,
    required String typeVenteId,
    required String? userVendeurId,
    required List<VenteTp> tierspayants,
    String? venteId,
  }) async {
    await _wait();
    return const VenteOk('V1');
  }

  @override
  Future<VenteResult<AssuranceSaleSummary>> netAssurance({required String venteId, required List<VenteTp> tierspayants}) async {
    await _wait();
    return VenteOk(AssuranceSaleSummary(montant: 12500, montantNet: assuranceNet, montantTp: 12500 - assuranceNet, venteId: venteId, reference: 'PV-000124'));
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> cloturerAssuranceReglements({
    required String venteId,
    required String clientId,
    required String ayantDroitId,
    required String natureVenteId,
    required String typeVenteId,
    required String? userVendeurId,
    required AssuranceSaleSummary summary,
    required List<VenteReglement> reglements,
    required List<VenteTp> tierspayants,
    required int montantRecu,
    required int montantRemis,
  }) async {
    assurances.add((reglements: reglements, recu: montantRecu, remis: montantRemis, net: summary.montantNet));
    await _wait();
    return _close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

ClientAssurance _client() => ClientAssurance(
      lgCLIENTID: 'C1',
      fullName: 'KOUASSI Awa',
      strFIRSTNAME: 'KOUASSI',
      strLASTNAME: 'Awa',
      strNUMEROSECURITESOCIAL: 'MAT1',
      tiersPayants: [
        ClientTiersPayant(lgTIERSPAYANTID: 'TP1', tpFullName: 'MCI', taux: 70, numSecurity: 'M1', compteTp: 'CT1', order: 1, principal: true),
      ],
      ayantDroits: [
        AyantDroit(lgAYANTSDROITSID: 'C1', lgCLIENTID: 'C1', fullName: 'KOUASSI Awa', strFIRSTNAME: 'KOUASSI', strLASTNAME: 'Awa', strNUMEROSECURITESOCIAL: 'M', strSEXE: ''),
      ],
    );

final _doli = ProductSearchResult(
  lgFAMILLEID: 'P1',
  strNAME: 'DOLIPRANE 1000MG',
  intCIP: '3400930000001',
  intPRICE: 12500,
  intNUMBERAVAILABLE: 10,
  strLIBELLEE: '',
  intPAF: 0,
);

Future<AssuranceController> _assurance(_Gw gw) async {
  final c = AssuranceController(gateway: gw, userId: 'U1');
  await c.selectClient(_client());
  expectSync(c.validateCouverture({'CT1': 'B-1'}), isNull);
  expectSync((await c.addProduct(_doli, 1)).isOk, isTrue);
  await c.idle();
  return c;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

String _n(int v) => Constants.formatNumber(v);
String _f(int v) => '${_n(v)} F';

/// Ouvre la page d'encaissement ; [done] reçoit le résultat à la fermeture.
Future<void> _open(WidgetTester tester, Widget Function() page, void Function(EncaissementDone?) done) async {
  final settings = SettingsProvider();
  await settings.loadSettings();
  await tester.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
    value: settings,
    child: MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => done(await Navigator.of(ctx).push<EncaissementDone>(MaterialPageRoute(builder: (_) => page()))),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Ouvrir'));
  await tester.pumpAndSettle();
}

/// Attend [f] en faisant avancer l'horloge du test (délais simulés de la passerelle).
Future<T> _settle<T>(WidgetTester tester, Future<T> f) async {
  var done = false;
  late T value;
  unawaited(f.then((v) {
    value = v;
    done = true;
  }));
  for (var i = 0; i < 200 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done, isTrue);
  return value;
}

Future<VenteController> _vente(WidgetTester tester, _Gw gw) async {
  final c = VenteController(gateway: gw);
  await _settle(tester, c.loadVente('V1'));
  expect(c.netUpToDate, isTrue);
  return c;
}

Future<void> _openVente(WidgetTester tester, _Gw gw, void Function(EncaissementDone?) done, {ListPresentation style = ListPresentation.dashboard}) async {
  final c = await _vente(tester, gw);
  await _open(
    tester,
    () => EncaissementPage(
      controller: c,
      userId: 'U1',
      expectedChanges: c.changes,
      summary: c.summary,
      itemCount: c.items.length,
      presentation: style,
      initialCopies: 1,
    ),
    done,
  );
}

Finder get _valider => find.byKey(const ValueKey('encaissement-valider'));
Finder get _ajouter => find.byKey(const ValueKey('paiement-ajouter-mode'));
Finder _montant(String id) => find.byKey(ValueKey('reglement-montant-$id'));

bool _enabled(WidgetTester tester, Finder f) => (tester.widget(f) as ButtonStyleButton).onPressed != null;

String _label(WidgetTester tester) {
  final texts = find.descendant(of: _valider, matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data ?? '');
  return texts.join(' ');
}

/// Liste de la page (construite au fil du défilement).
Finder get _list => find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;

/// Fait défiler la page jusqu'à [f] (les éléments hors écran ne sont pas construits).
Future<void> _see(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    tester.state<ScrollableState>(_list).position.jumpTo(0);
    await tester.pump();
    if (f.evaluate().isEmpty) await tester.scrollUntilVisible(f, 120, scrollable: _list);
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

Future<String> _text(WidgetTester tester, Finder f) async {
  await _see(tester, f);
  return tester.widget<TextField>(f).controller?.text ?? '';
}

Future<String?> _data(WidgetTester tester, Finder f) async {
  await _see(tester, f);
  return tester.widget<Text>(f).data;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await _see(tester, f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, Finder f, String text) async {
  await _see(tester, f);
  await tester.enterText(f, text);
  await tester.pumpAndSettle();
}

/// « + Ajouter un mode » puis choix de [id] dans la liste.
Future<void> _addMode(WidgetTester tester, String id) async {
  await _tap(tester, _ajouter);
  await tester.tap(find.byKey(ValueKey('ajout-mode-$id')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({
        'enabled_payment_method_ids': ['1', '10', '7'],
      }));

  // ---------------------------------------------------------------------------
  // Règles de répartition
  // ---------------------------------------------------------------------------
  group('Règles', () {
    test('1ᵉʳ ajout : le nouveau mode reçoit le reste, la part du 1ᵉʳ est à saisir ; 2 modes maximum', () {
      final p = PaiementMultiple(12500, _esp);
      expect(p.lignes.single.montant, 12500);
      expect(p.peutAjouter, isTrue);
      expect(p.ajouter(_wave), isNull);
      expect([for (final l in p.lignes) l.montant], [0, 12500]);
      expect(p.reste, 0);
      expect(p.peutAjouter, isFalse);
      expect(p.ajouter(_orange), contains('2 modes au maximum'));
      expect(p.lignes.length, 2);
      expect(p.valide, isFalse); // part espèces à 0
    });

    test('un même mode une seule fois', () {
      final p = PaiementMultiple(12500, _esp);
      expect(p.ajouter(_esp), contains('déjà'));
      expect(p.lignes.length, 1);
      expect(reglementsInvalides([(typeReglementId: '10', montant: 6000, montantVerse: null), (typeReglementId: '10', montant: 6500, montantVerse: null)], 12500),
          contains('une fois'));
    });

    test('modifier un montant recalcule le reste ; dépassement corrigé avec message', () {
      final p = PaiementMultiple(12500, _esp)..ajouter(_wave);
      expect(p.modifier(0, 5000), isNull);
      expect([for (final l in p.lignes) l.montant], [5000, 7500]);
      expect(p.reste, 0);
      // 1ᵉʳ mode : jamais au-delà du net.
      expect(p.modifier(0, 20000), '${_f(20000)} dépasse le net à répartir (${_f(12500)}) : montant corrigé.');
      expect([for (final l in p.lignes) l.montant], [12500, 0]);
      expect(p.valide, isFalse);
      // Dernier mode : jamais au-delà du reste.
      p.modifier(0, 5000);
      expect(p.modifier(1, 9000), '${_f(9000)} dépasse le reste (${_f(7500)}) : montant corrigé.');
      expect(p.lignes[1].montant, 7500);
      expect(p.modifier(1, 3000), isNull);
      expect(p.reste, 4500);
      expect(p.peutAjouter, isFalse); // 2 modes maximum
      expect(p.blocage, contains('égale au net'));
    });

    test('raccourcis : 50 / 50, Tout en <mode> ; ✕ retirer', () {
      final p = PaiementMultiple(12500, _esp)..ajouter(_wave);
      p.moitie();
      expect([for (final l in p.lignes) l.montant], [6250, 6250]);
      final odd = PaiementMultiple(2951, _esp)..ajouter(_wave);
      odd.moitie();
      expect([for (final l in odd.lignes) l.montant], [1475, 1476]);
      p.toutEn(_wave);
      expect(p.lignes.single.method.id, '10');
      expect(p.lignes.single.montant, 12500);
      final q = PaiementMultiple(12500, _esp)
        ..ajouter(_wave)
        ..modifier(0, 5000);
      q.retirer(1);
      expect(q.lignes.single.method.id, '1');
      expect(q.lignes.single.montant, 12500);
    });

    test('espèces : reçu ≥ part, monnaie sur la part espèces seulement, rendu > 500 000 refusé', () {
      final p = PaiementMultiple(12500, _esp)
        ..ajouter(_wave)
        ..modifier(0, 5000);
      p.setRecu(0, 4000);
      expect(p.lignes[0].erreur, 'Montant insuffisant : il manque ${_f(1000)}');
      p.setRecu(0, 600000);
      expect(p.lignes[0].erreur, contains('aberrant'));
      p.setRecu(0, 10000);
      expect(p.lignes[0].erreur, isNull);
      expect(p.monnaie, 5000);
      expect(p.montantRecu, 17500); // somme des parts + surplus espèces
      expect(p.nbRecus, 1);
    });

    test('mobile non confirmé : bloque ; montant changé après confirmation → à reconfirmer', () {
      final p = PaiementMultiple(12500, _esp)
        ..ajouter(_wave)
        ..modifier(0, 5000)
        ..setRecu(0, 5000);
      expect(p.valide, isFalse);
      expect(p.blocage, 'Paiement non reçu.');
      p.setConfirme(1, true);
      expect(p.valide, isTrue);
      expect(p.principal.method.id, '10');
      p.modifier(0, 6000);
      expect(p.lignes[1].confirme, isFalse);
      expect(p.valide, isFalse);
    });

    test('contrôle avant envoi : 1 ou 2 règlements, chacun > 0, somme = net exactement', () {
      VenteReglement r(String id, int m) => (typeReglementId: id, montant: m, montantVerse: null);
      expect(reglementsInvalides([r('1', 5000), r('10', 7500)], 12500), isNull);
      expect(reglementsInvalides([r('1', 5000), r('10', 8000)], 12500), contains('égale au net'));
      expect(reglementsInvalides([r('1', 0), r('10', 12500)], 12500), contains('supérieur à 0'));
      expect(reglementsInvalides([r('1', 5000), r('10', 5000), r('7', 2500)], 12500), contains('maximum'));
      expect(reglementPrincipal([r('1', 6250), r('10', 6250)]).typeReglementId, '1');
    });

    test('ticket : détail par mode (reçu / rendu pour les espèces)', () {
      final p = PaiementMultiple(12500, _esp)
        ..ajouter(_wave)
        ..modifier(0, 5000)
        ..setRecu(0, 10000)
        ..setConfirme(1, true);
      final EncaissementDone done = (method: _wave, recu: 17500, remis: 5000, dejaCloturee: false, copies: 1, reglements: p.lignes);
      expect(ticketReglementLines(ticketReglementsOf(done)!), ['ESPÈCES: ${_n(5000)}', 'reçu ${_n(10000)} / rendu ${_n(5000)}', 'WAVE: ${_n(7500)}']);
      final EncaissementDone simple = (method: _esp, recu: 15000, remis: 2500, dejaCloturee: false, copies: 1, reglements: const []);
      expect(ticketReglementsOf(simple), isNull); // ticket d'origine
    });
  });

  // ---------------------------------------------------------------------------
  // Requête envoyée (vraie passerelle Dio vers un serveur local)
  // ---------------------------------------------------------------------------
  group('Requête de clôture', () {
    late HttpServer server;
    final received = <Map<String, dynamic>>[];

    setUp(() async {
      received.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final payload = await utf8.decoder.bind(req).join();
        received.add({'path': req.uri.path, 'body': jsonDecode(payload)});
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'success': true, 'msg': 'Opération effectuée avec success'}));
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    Future<void> real(Future<void> Function() body) => HttpOverrides.runWithHttpOverrides(body, _RealHttp());
    DioVenteGateway gw() => DioVenteGateway(ApiService(baseUrl: 'http://127.0.0.1:${server.port}/api'));
    final summary = SaleSummary(montant: 12500, montantNet: 12500, venteId: 'V1', reference: 'PV-000123', marge: 3000);

    test('1 mode : requête identique à avant', () => real(() async {
          final r = await gw().cloturerVno(
            venteId: 'V1',
            summary: summary,
            typeReglementId: '1',
            clientId: 'especes',
            userVendeurId: 'U1',
            montantRecu: 15000,
            montantRemis: 2500,
          );
          expect(r.isOk, isTrue);
          expect(received.single['path'], '/api/vente/cloturer/vno');
          // Corps attendu : exactement celui envoyé avant le paiement multiple.
          expect(received.single['body'], jsonDecode(jsonEncode({
            "banque": "",
            "clientId": "especes",
            "commentaire": "",
            "data": summary.toJson(),
            "devis": false,
            "lieux": "",
            "marge": summary.marge,
            "medecinId": null,
            "montantPaye": 12500,
            "montantRecu": 15000,
            "montantRemis": 2500,
            "natureVenteId": "1",
            "nom": "",
            "partTP": 0,
            "reglements": [
              {"montant": 12500, "montantAttentu": 12500, "typeReglement": "1"}
            ],
            "remiseId": null,
            "totalRecap": 12500,
            "typeRegleId": "1",
            "typeVenteId": "1",
            "userVendeurId": "U1",
            "venteId": "V1",
          })));
        }));

    test('2 modes : une requête, 2 règlements, somme = net, mode principal, reçu / rendu cohérents', () => real(() async {
          final r = await gw().cloturerVnoReglements(
            venteId: 'V1',
            summary: summary,
            reglements: [(typeReglementId: '1', montant: 5000, montantVerse: 10000), (typeReglementId: '10', montant: 7500, montantVerse: null)],
            clientId: 'wave',
            userVendeurId: 'U1',
            montantRecu: 17500,
            montantRemis: 5000,
          );
          expect(r.isOk, isTrue);
          final body = received.single['body'] as Map;
          expect(body['reglements'], [
            {"montant": 5000, "montantAttentu": 5000, "typeReglement": "1", "montantVerse": 10000},
            {"montant": 7500, "montantAttentu": 7500, "typeReglement": "10"},
          ]);
          expect((body['reglements'] as List).fold<int>(0, (s, e) => s + (e['montant'] as int)), body['montantPaye']);
          expect(body['typeRegleId'], '10');
          expect(body['montantRecu'], 17500);
          expect(body['montantRemis'], 5000);
          expect(body['montantPaye'], 12500);
          expect(body['clientId'], 'wave');
        }));

    test('somme ≠ net, 3 modes ou doublon : refus SANS requête', () => real(() async {
          for (final regl in [
            [(typeReglementId: '1', montant: 5000, montantVerse: null), (typeReglementId: '10', montant: 8000, montantVerse: null)],
            [(typeReglementId: '1', montant: 5000, montantVerse: null), (typeReglementId: '10', montant: 5000, montantVerse: null), (typeReglementId: '7', montant: 2500, montantVerse: null)],
            [(typeReglementId: '10', montant: 5000, montantVerse: null), (typeReglementId: '10', montant: 7500, montantVerse: null)],
          ]) {
            final r = await gw().cloturerVnoReglements(
                venteId: 'V1', summary: summary, reglements: regl, clientId: 'x', userVendeurId: 'U1', montantRecu: 12500, montantRemis: 0);
            expect(r, isA<VenteRefused<Map<String, dynamic>>>());
          }
          expect(received, isEmpty);
        }));

    test('assurance : part client en 2 modes, reste du corps identique au paiement simple', () => real(() async {
          final s = AssuranceSaleSummary(montant: 12500, montantNet: 3000, montantTp: 9500, marge: 100, tierspayants: [TiersPayantSummary(numBon: 'B-1', taux: 70, compteTp: 'CT1', tpnet: 9500)]);
          const tps = [(compteTp: 'CT1', numBon: 'B-1', taux: 70)];
          await gw().cloturerAssurance(
              venteId: 'V1', clientId: 'C1', ayantDroitId: 'C1', natureVenteId: '1', typeVenteId: '2', userVendeurId: 'U1', summary: s, typeReglementId: '1', tierspayants: tps);
          await gw().cloturerAssuranceReglements(
            venteId: 'V1',
            clientId: 'C1',
            ayantDroitId: 'C1',
            natureVenteId: '1',
            typeVenteId: '2',
            userVendeurId: 'U1',
            summary: s,
            reglements: [(typeReglementId: '1', montant: 1000, montantVerse: 1000), (typeReglementId: '10', montant: 2000, montantVerse: null)],
            tierspayants: tps,
            montantRecu: 3000,
            montantRemis: 0,
          );
          final simple = Map<String, dynamic>.from(received[0]['body'] as Map), multi = Map<String, dynamic>.from(received[1]['body'] as Map);
          expect(received[1]['path'], '/api/vente/cloturer/assurance');
          expect(simple['reglements'], [
            {"montant": 3000, "montantAttentu": 3000, "typeReglement": "1"}
          ]);
          expect((multi['reglements'] as List).length, 2);
          expect(multi['typeRegleId'], '10');
          for (final k in ['reglements', 'typeRegleId']) {
            simple.remove(k);
            multi.remove(k);
          }
          expect(multi, simple);
        }));
  });

  // ---------------------------------------------------------------------------
  // Page d'encaissement (Pré-vente), 360 px
  // ---------------------------------------------------------------------------
  testWidgets('un seul mode (sans « Ajouter un mode ») : même page et même clôture qu\'avant', (tester) async {
    _phone(tester);
    final gw = _Gw();
    EncaissementDone? done;
    await _openVente(tester, gw, (d) => done = d);
    expect(find.byKey(const ValueKey('encaissement-recu')), findsOneWidget);
    expect(find.byKey(const ValueKey('paiement-reste')), findsNothing);
    expect(_ajouter, findsOneWidget);
    await tester.tap(find.text('Exact'));
    await tester.pump();
    await tester.tap(_valider);
    await tester.pumpAndSettle();
    expect(gw.simples.single, (type: '1', recu: 12500, remis: 0));
    expect(gw.multiples, isEmpty);
    expect(done?.reglements, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final style in ListPresentation.values) {
    testWidgets('espèces + Wave : reste auto, monnaie, QR, « Reçu » obligatoire, 1 clôture à 2 règlements — ${style.label}', (tester) async {
      _phone(tester);
      final gw = _Gw();
      EncaissementDone? done;
      await _openVente(tester, gw, (d) => done = d, style: style);
      await _addMode(tester, '10');
      expect(find.byKey(const ValueKey('reglement-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('reglement-10')), findsOneWidget);
      expect(await _text(tester, _montant('10')), '12500');
      // 2 modes maximum : le bouton est désactivé.
      await _see(tester, _ajouter);
      expect(_enabled(tester, _ajouter), isFalse);

      await _enter(tester, _montant('1'), '5000');
      expect(await _text(tester, _montant('10')), '7500');
      expect(await _data(tester, find.byKey(const ValueKey('paiement-reste'))), '${_f(0)} ✓');
      expect(_label(tester), 'EN ATTENTE DES PAIEMENTS (0/2)');
      expect(_enabled(tester, _valider), isFalse);

      await _enter(tester, find.byKey(const ValueKey('reglement-recu-montant-1')), '10000');
      expect(await _data(tester, find.byKey(const ValueKey('reglement-monnaie'))), _f(5000));
      expect(_label(tester), 'EN ATTENTE DES PAIEMENTS (1/2)');
      expect(find.byKey(const ValueKey('reglement-qr-10')), findsOneWidget);
      expect(find.text('Faites scanner · ${_f(7500)}'), findsOneWidget);
      expect(_enabled(tester, _valider), isFalse); // Wave non confirmé

      await _tap(tester, find.byKey(const ValueKey('reglement-recu-10')));
      expect(_label(tester), 'VALIDER L\'ENCAISSEMENT');
      expect(_enabled(tester, _valider), isTrue);
      await tester.tap(_valider);
      await tester.pumpAndSettle();

      expect(gw.simples, isEmpty);
      final m = gw.multiples.single;
      expect(m.reglements, [(typeReglementId: '1', montant: 5000, montantVerse: 10000), (typeReglementId: '10', montant: 7500, montantVerse: null)]);
      expect(m.recu, 17500);
      expect(m.remis, 5000);
      expect(m.clientId, 'wave'); // mode principal
      expect(done?.reglements.length, 2);
      expect(done?.method.id, '10');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dépassement : montant corrigé avec message ; validation bloquée tant que reste ≠ 0', (tester) async {
    _phone(tester);
    final gw = _Gw();
    await _openVente(tester, gw, (_) {});
    await _addMode(tester, '10');
    await _enter(tester, _montant('1'), '20000');
    expect(await _text(tester, _montant('1')), '12500');
    expect(find.textContaining('${_f(20000)} dépasse le net à répartir'), findsOneWidget);
    expect(await _text(tester, _montant('10')), '');
    await _enter(tester, _montant('1'), '5000');
    await _enter(tester, _montant('10'), '9000');
    expect(await _text(tester, _montant('10')), '7500');
    expect(find.textContaining('${_f(9000)} dépasse le reste (${_f(7500)}) : montant corrigé.'), findsOneWidget);
    await _enter(tester, _montant('10'), '3000');
    expect(await _data(tester, find.byKey(const ValueKey('paiement-reste'))), _f(4500));
    await _enter(tester, find.byKey(const ValueKey('reglement-recu-montant-1')), '5000');
    await _tap(tester, find.byKey(const ValueKey('reglement-recu-10')));
    expect(_enabled(tester, _valider), isFalse); // somme ≠ net
    expect(gw.multiples, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('doublon impossible, raccourcis « 50 / 50 », « Tout en WAVE », « Tout en espèces », ✕ retirer', (tester) async {
    _phone(tester);
    final gw = _Gw();
    await _openVente(tester, gw, (_) {});
    await _tap(tester, _ajouter);
    expect(find.byKey(const ValueKey('ajout-mode-1')), findsNothing); // espèces déjà utilisé
    expect(find.byKey(const ValueKey('ajout-mode-10')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ajout-mode-10')));
    await tester.pumpAndSettle();

    await _tap(tester, find.byKey(const ValueKey('raccourci-moitie')));
    expect(await _text(tester, _montant('1')), '6250');
    expect(await _text(tester, _montant('10')), '6250');

    await _tap(tester, find.byKey(const ValueKey('raccourci-tout-10')));
    expect(find.byKey(const ValueKey('paiement-reste')), findsNothing);
    expect(find.byKey(const ValueKey('encaissement-qr')), findsOneWidget); // paiement simple Wave

    await _addMode(tester, '1');
    expect(find.byKey(const ValueKey('reglement-10')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('raccourci-tout-1')));
    expect(find.byKey(const ValueKey('encaissement-recu')), findsOneWidget); // paiement simple espèces

    await _addMode(tester, '7');
    await _tap(tester, find.byKey(const ValueKey('reglement-retirer-7')));
    expect(find.byKey(const ValueKey('paiement-reste')), findsNothing);
    expect(find.byKey(const ValueKey('encaissement-recu')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Future<void> fillValid(WidgetTester tester) async {
    await _addMode(tester, '10');
    await _enter(tester, _montant('1'), '5000');
    await _enter(tester, find.byKey(const ValueKey('reglement-recu-montant-1')), '5000');
    await _tap(tester, find.byKey(const ValueKey('reglement-recu-10')));
  }

  testWidgets('double tap VALIDER : une seule clôture', (tester) async {
    _phone(tester);
    final gw = _Gw()..delay = const Duration(milliseconds: 120);
    EncaissementDone? done;
    await _openVente(tester, gw, (d) => done = d);
    await fillValid(tester);
    await tester.tap(_valider);
    await tester.tap(_valider, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(_valider, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(gw.multiples.length, 1);
    expect(done?.dejaCloturee, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('réponse perdue : vente relue avant « Réessayer », jamais de seconde clôture', (tester) async {
    _phone(tester);
    final gw = _Gw()..mode = _Close.lostNotApplied;
    EncaissementDone? done;
    await _openVente(tester, gw, (d) => done = d);
    await fillValid(tester);
    await tester.tap(_valider);
    await tester.pumpAndSettle();
    expect(done, isNull);
    expect(_label(tester), 'RÉESSAYER');
    expect(gw.multiples.length, 1);
    // La réponse se perd encore mais la vente est clôturée : la relecture le confirme.
    gw.mode = _Close.lostApplied;
    await tester.tap(_valider);
    await tester.pumpAndSettle();
    expect(gw.multiples.length, 2);
    expect(done?.reglements.length, 2);
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------------------
  // Assurance : part client
  // ---------------------------------------------------------------------------
  test('assurance (contrôleur) : 2 modes = 1 clôture avec la liste ; somme ≠ part client refusée sans appel', () async {
    SharedPreferences.setMockInitialValues({});
    final gw = _Gw()..delay = const Duration(milliseconds: 5);
    final c = await _assurance(gw);
    final bad = PaiementMultiple(3000, _esp)
      ..ajouter(_wave)
      ..modifier(0, 1000);
    final badLignes = [bad.lignes[0], bad.lignes[1].copyWith(montant: 2500)];
    expect((await c.cloturerReglements(lignes: badLignes, expectedChanges: c.changes, montantRecu: 3500, montantRemis: 0)).isOk, isFalse);
    expect(gw.assurances, isEmpty);
    final ok = PaiementMultiple(3000, _esp)
      ..ajouter(_wave)
      ..modifier(0, 1000)
      ..setRecu(0, 2000)
      ..setConfirme(1, true);
    final r = await Future.wait([
      c.cloturerReglements(lignes: ok.lignes, expectedChanges: c.changes, montantRecu: ok.montantRecu, montantRemis: ok.monnaie),
      c.cloturerReglements(lignes: ok.lignes, expectedChanges: c.changes, montantRecu: ok.montantRecu, montantRemis: ok.monnaie),
    ]);
    expect(r.every((x) => x.isOk), isTrue);
    final a = gw.assurances.single;
    expect(a.net, 3000);
    expect(a.reglements.fold<int>(0, (s, x) => s + x.montant), 3000);
    expect(a.recu, 4000);
    expect(a.remis, 1000);
  });

  testWidgets('assurance (page) : part client en espèces + Wave', (tester) async {
    _phone(tester);
    final gw = _Gw();
    late AssuranceController c;
    c = await _settle(tester, _assurance(gw));
    final s = c.summary!;
    EncaissementDone? done;
    await _open(
      tester,
      () => EncaissementPage(
        actions: EncaissementActions(
          paymentMethods: c.paymentMethods,
          loadQrMethods: c.loadQrMethods,
          qrFor: c.qrFor,
          encaisser: (method, recu, remis) => c.cloturer(method: method, expectedChanges: c.changes, montantRecu: recu, montantRemis: remis),
          encaisserReglements: (lignes, recu, remis) => c.cloturerReglements(lignes: lignes, expectedChanges: c.changes, montantRecu: recu, montantRemis: remis),
        ),
        expectedChanges: c.changes,
        summary: SaleSummary(montant: s.montant, montantNet: s.montantNet, reference: 'PV-000124', venteId: 'V1'),
        itemCount: 1,
        presentation: ListPresentation.guided,
        totalLabel: 'Part client à payer',
      ),
      (d) => done = d,
    );
    await _addMode(tester, '10');
    await _enter(tester, _montant('1'), '1000');
    expect(await _text(tester, _montant('10')), '2000');
    await _enter(tester, find.byKey(const ValueKey('reglement-recu-montant-1')), '1000');
    await _tap(tester, find.byKey(const ValueKey('reglement-recu-10')));
    await tester.tap(_valider);
    await tester.pumpAndSettle();
    expect(gw.assurances.single.reglements, [(typeReglementId: '1', montant: 1000, montantVerse: 1000), (typeReglementId: '10', montant: 2000, montantVerse: null)]);
    expect(done?.reglements.length, 2);
    expect(tester.takeException(), isNull);
  });
}

class _RealHttp extends HttpOverrides {}
