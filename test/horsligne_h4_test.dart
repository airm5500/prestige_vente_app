// H4 — clé client anti-doublon (X-Client-Ref) : ventes hors ligne et retours fournisseurs.
// - Faux serveur AVEC H4 : création dont la réponse est perdue (ou appli fermée pendant l'appel) → relue par sa
//   clé, reprise sans doublon et sans anomalie ; clé inconnue → renvoi (même clé) ; relecture impossible → arrêt.
// - Faux serveur SANS H4 : anomalie « vérifiez sur Prestige » exactement comme avant, aucun en-tête envoyé.
// - HTTP réel (serveur local) : en-tête envoyé sur la création seulement, capacité lue (200 / 401 « expire » /
//   404), relecture 200 / 404.
// - Intégration contre le serveur de test (http://localhost:8080/prestige/api/v1, ou PRESTIGE_TEST_URL), sautée
//   s'il n'est pas joignable ou n'a pas le patch H4.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/horsligne/client_ref.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_sender.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/horsligne/ventes_sync.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

// -----------------------------------------------------------------------------
// Faux serveur des ventes (mémoire), avec ou sans H4
// -----------------------------------------------------------------------------

/// Création : normale, réponse perdue APRÈS création, réponse perdue SANS création, panne (rien ne part).
enum _Mode { ok, perdue, perdueSansCreation, panne }

class _VenteSrv implements VenteGateway, ClientRefGateway {
  final bool h4;
  _VenteSrv({required this.h4});

  final Map<String, List<SaleItemDetail>> sales = {};
  final Map<String, String> statut = {};
  final Map<String, String> parCle = {};

  /// Clé reçue (en-tête) à chaque requête de création (null = sans en-tête).
  final List<String?> clesRecues = [];
  final List<_Mode> modes = [];
  int creations = 0;
  int lectures = 0;
  bool lecturePanne = false;
  String? _cleEnCours;

  VenteResult<String> _add(String produitId, int qte, int pu, String? venteId) {
    final cle = venteId == null ? _cleEnCours : null;
    _cleEnCours = null;
    if (venteId == null) clesRecues.add(cle);
    final m = venteId == null && modes.isNotEmpty ? modes.removeAt(0) : _Mode.ok;
    if (m == _Mode.panne) return const VenteFailed('Serveur injoignable (ajouter le produit).');
    if (m == _Mode.perdueSansCreation) return const VenteFailed('Le serveur met trop de temps à répondre.', maybeApplied: true);
    var id = venteId;
    if (id == null) {
      // Serveur H4 : même clé = même vente, rien n'est recréé.
      final deja = h4 && cle != null ? parCle[cle] : null;
      if (deja != null) {
        id = deja;
      } else {
        creations++;
        id = 'V$creations';
        sales[id] = [];
        statut[id] = 'pending';
        if (h4 && cle != null) parCle[cle] = id;
        _ligne(id, produitId, qte, pu);
      }
    } else {
      _ligne(id, produitId, qte, pu);
    }
    if (m == _Mode.perdue) return const VenteFailed('Le serveur met trop de temps à répondre.', maybeApplied: true);
    return VenteOk(id);
  }

  void _ligne(String id, String produitId, int qte, int pu) {
    final l = sales[id]!;
    l.add(SaleItemDetail(
      lgPREENREGISTREMENTDETAILID: '$id-L${l.length + 1}',
      lgFAMILLEID: produitId,
      strNAME: 'PRODUIT $produitId',
      intCIP: 'CIP$produitId',
      intQUANTITY: qte,
      intPRICEUNITAIR: pu,
      intPRICE: qte * pu,
      strREF: 'PV-$id',
    ));
  }

  // --- H4 ---
  @override
  Future<bool> clientRefSupporte() async => h4;

  @override
  Future<VenteResult<ClientRefInfo?>> lireClientRef(String ref) async {
    lectures++;
    if (lecturePanne) return const VenteFailed('Serveur injoignable (relire la création).');
    final id = parCle[ref];
    return VenteOk(id == null ? null : ClientRefInfo(type: ClientRefInfo.typeVente, id: id, reference: 'PV-$id', statut: statut[id]));
  }

  @override
  VenteGateway avecClientRef(String ref) {
    _cleEnCours = ref;
    return this;
  }

  // --- Ventes ---
  @override
  Future<VenteResult<String>> addItemVno({required String produitId, required int qte, required int itemPu, String? venteId, required bool prevente}) async =>
      _add(produitId, qte, itemPu, venteId);

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
  }) async =>
      _add(produitId, qte, itemPu, venteId);

  @override
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async => VenteOk(List.of(sales[venteId] ?? const []));

  int _total(String id) => (sales[id] ?? const []).fold(0, (s, i) => s + i.intPRICE);

  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) async =>
      VenteOk(SaleSummary(montant: _total(venteId), montantNet: _total(venteId), venteId: venteId, reference: 'PV-$venteId'));

  @override
  Future<VenteResult<AssuranceSaleSummary>> netAssurance({required String venteId, required List<VenteTp> tierspayants}) async =>
      VenteOk(AssuranceSaleSummary(montant: _total(venteId), montantTp: 0, montantNet: _total(venteId)));

  @override
  Future<VenteResult<void>> terminerPrevente(String venteId) async {
    statut[venteId] = 'is_Process';
    return const VenteOk(null);
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId) async => VenteOk({'strSTATUT': statut[venteId] ?? ''});

  @override
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async => VenteOk(ProductPage([
        ProductSearchResult(lgFAMILLEID: 'P1', strNAME: 'PRODUIT P1', intCIP: 'CIPP1', intPRICE: 1500, intNUMBERAVAILABLE: 50, strLIBELLEE: '', intPAF: 0),
      ], 1));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

final _t0 = DateTime(2026, 10, 10, 9);

VenteHorsLigne _vente({String id = 'loc1', TypeVenteHL type = TypeVenteHL.comptant, StatutVenteHL statut = StatutVenteHL.enAttente, String? etape}) =>
    VenteHorsLigne(
      id: id,
      numero: 7,
      type: type,
      lignes: const [LigneHL(cle: 'l1', produitId: 'P1', nom: 'PRODUIT P1', cip: 'CIPP1', qte: 2, prix: 1500)],
      client: type == TypeVenteHL.comptant ? null : const {'lgCLIENTID': 'C1', 'fullName': 'AWA KOUASSI'},
      tps: type == TypeVenteHL.comptant ? const [] : const [TpHL(compteTp: 'T1', numBon: 'B1', taux: 80)],
      fin: FinVenteHL.prevente,
      totalEstime: 3000,
      netEstime: 3000,
      statut: statut,
      etape: etape,
      createdAt: _t0,
      updatedAt: _t0,
    );

Future<FileVentesHL> _file(_VenteSrv srv, {MemoryVentesHLStore? store, VenteHorsLigne? v}) async {
  final f = FileVentesHL(store: store ?? MemoryVentesHLStore(), gateway: srv, clock: () => _t0);
  await f.load();
  if (v != null) await f.ajouter(v);
  return f;
}

// -----------------------------------------------------------------------------
// Faux serveur des retours fournisseurs (StockServer), avec ou sans H4
// -----------------------------------------------------------------------------

class _RetourSrv implements StockServer {
  final bool h4;
  _RetourSrv({required this.h4});

  final List<Map<String, dynamic>> retours = [];
  final List<Map<String, dynamic>> items = [];
  final Map<String, String> parCle = {};
  final List<String?> clesRecues = [];
  final List<String> calls = [];

  /// La prochaine création est faite puis sa réponse perdue.
  bool perdreReponse = false;

  @override
  Future<StockHttp> call(String method, String path, {Map<String, dynamic>? query, Object? data, Map<String, String>? headers}) async {
    calls.add('$method $path');
    final d = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    if (path == '/mobile/capacites') {
      // Serveur sans H4 : chemin v1/mobile/ protégé par jeton → 401 « expire ».
      return h4 ? const StockHttp(200, {'success': true, 'clientRef': true}) : const StockHttp(401, {'success': false, 'expire': true});
    }
    if (path.startsWith('/mobile/client-ref/')) {
      final id = parCle[Uri.decodeComponent(path.substring('/mobile/client-ref/'.length))];
      if (id == null) return const StockHttp(404, {'success': false, 'msg': 'Clé client inconnue.'});
      return StockHttp(200, {'success': true, 'type': 'RETOUR_FRS', 'id': id, 'reference': 'REF-$id', 'statut': 'is_Process'});
    }
    if (path == '/retourfournisseur/new') {
      final cle = headers?[enteteClientRef];
      clesRecues.add(cle);
      var id = h4 && cle != null ? parCle[cle] : null;
      if (id == null) {
        id = 'R${retours.length + 1}';
        retours.add({'lg_RETOUR_FRS_ID': id, 'str_COMMENTAIRE': d['strCOMMENTAIRE'], 'str_STATUT': 'is_Process'});
        final it = (d['items'] as List).first as Map;
        items.add({'retourId': id, 'produitId': it['produitId'], 'intNUMBERRETURN': it['intNUMBERRETURN']});
        if (h4 && cle != null) parCle[cle] = id;
      }
      if (perdreReponse) {
        perdreReponse = false;
        throw const StockStopException('Serveur injoignable : envoi interrompu.');
      }
      return StockHttp(200, {'success': true, 'data': {'lgRETOURFRSID': id, 'strREFRETOURFRS': 'REF-$id'}});
    }
    // Prestige ne liste que les retours VALIDÉS : un retour « en préparation » n'y est jamais.
    if (path == '/produit/retours-data') return const StockHttp(200, {'total': 0, 'results': []});
    if (path == '/retourfournisseur/add-item') {
      items.add({'retourId': d['lgRETOURFRSID'], 'produitId': d['produitId'], 'intNUMBERRETURN': d['intNUMBERRETURN']});
      return const StockHttp(200, {'success': true});
    }
    if (path == '/retourfournisseur/retours-items') {
      return StockHttp(200, {'data': [for (final i in items) if (i['retourId'] == query?['retourId']) i]});
    }
    return const StockHttp(404, {'success': false});
  }

  int count(String p) => calls.where((c) => c.endsWith(p)).length;
}

StockOp _retour({String id = 'HL3-20261010090000-ab12', int lignes = 2}) => StockOp(
      id: id,
      type: StockOpType.retour,
      createdAt: _t0,
      refId: 'BL1',
      reference: 'BL 0308',
      meta: {'blRef': '0308', 'marker': '[HL:ab12100900]', 'comment': 'casse [HL:ab12100900]'},
      lines: [
        for (var i = 1; i <= lignes; i++)
          StockOpLine(key: 'k$i', label: 'Produit $i', data: {'produitId': 'P$i', 'motifId': '01', 'qty': i}),
      ],
    );

StockSender _sender(StockServer s) => StockSender(s, persist: (_) async {}, clock: () => _t0);

// -----------------------------------------------------------------------------
// HTTP réel (serveur local) / serveur de test
// -----------------------------------------------------------------------------

class _RealHttp extends HttpOverrides {}

Future<void> _real(Future<void> Function() body) => HttpOverrides.runWithHttpOverrides(body, _RealHttp());

void main() {
  setUp(CapaciteClientRef.vider);

  group('Ventes hors ligne — serveur avec H4', () {
    test('réponse perdue à la création : vente relue par sa clé, reprise sans doublon ni anomalie', () async {
      final srv = _VenteSrv(h4: true)..modes.add(_Mode.perdue);
      final f = await _file(srv, v: _vente());
      await f.envoyer();
      final v = f.byId('loc1')!;
      expect(v.statut, StatutVenteHL.envoyee);
      expect(v.venteId, 'V1');
      expect(srv.creations, 1, reason: 'jamais de 2ᵉ vente');
      expect(srv.sales['V1']!.single.intQUANTITY, 2, reason: 'aucun article en double');
      expect(srv.clesRecues, ['HL2-loc1'], reason: 'en-tête X-Client-Ref envoyé à la création');
      expect(srv.lectures, 1);
      expect(f.anomalies, isEmpty);
      expect(srv.statut['V1'], 'is_Process');
    });

    test('appli fermée pendant la création (étape « envoyée avec clé ») : relue au redémarrage', () async {
      final srv = _VenteSrv(h4: true);
      // La création est arrivée au serveur, la réponse jamais reçue (téléphone redémarré).
      srv.avecClientRef('HL2-loc1');
      await srv.addItemVno(produitId: 'P1', qte: 2, itemPu: 1500, prevente: true);
      final store = MemoryVentesHLStore();
      await store.put(_vente(statut: StatutVenteHL.envoiEnCours, etape: EtapeHL.creationEnvoyeeRef));
      final f = await _file(srv, store: store);
      expect(f.byId('loc1')!.supprimable, isFalse, reason: 'peut exister sur le serveur');
      await f.envoyer();
      expect(f.byId('loc1')!.statut, StatutVenteHL.envoyee);
      expect(f.byId('loc1')!.venteId, 'V1');
      expect(srv.creations, 1);
      expect(srv.sales['V1']!.length, 1);
      expect(f.anomalies, isEmpty);
    });

    test('clé inconnue du serveur (création jamais faite) : arrêt puis renvoi avec la MÊME clé, une seule vente', () async {
      final srv = _VenteSrv(h4: true)..modes.add(_Mode.perdueSansCreation);
      final f = await _file(srv, v: _vente());
      await f.envoyer();
      expect(srv.creations, 0);
      expect(f.panne, isNotNull);
      expect(f.byId('loc1')!.statut, StatutVenteHL.enAttente);
      expect(f.anomalies, isEmpty);
      await f.envoyer();
      expect(f.byId('loc1')!.statut, StatutVenteHL.envoyee);
      expect(srv.creations, 1);
      expect(srv.clesRecues, ['HL2-loc1', 'HL2-loc1']);
    });

    test('relecture impossible (panne) : envoi arrêté, rien de perdu, reprise au retour du serveur', () async {
      final srv = _VenteSrv(h4: true)
        ..modes.add(_Mode.perdue)
        ..lecturePanne = true;
      final f = await _file(srv, v: _vente());
      await f.envoyer();
      expect(f.panne, isNotNull);
      expect(f.byId('loc1')!.etape, EtapeHL.creationEnvoyeeRef);
      expect(f.byId('loc1')!.statut, StatutVenteHL.envoiEnCours);
      expect(f.anomalies, isEmpty);
      srv.lecturePanne = false;
      await f.envoyer();
      expect(f.byId('loc1')!.statut, StatutVenteHL.envoyee);
      expect(srv.creations, 1);
      expect(srv.clesRecues, ['HL2-loc1'], reason: 'pas de 2ᵉ création : la vente a été relue');
    });

    test('assurance : en-tête sur la création, réponse perdue → reprise sans doublon', () async {
      final srv = _VenteSrv(h4: true)..modes.add(_Mode.perdue);
      final f = await _file(srv, v: _vente(type: TypeVenteHL.assurance));
      await f.envoyer();
      expect(f.byId('loc1')!.statut, StatutVenteHL.envoyee);
      expect(srv.creations, 1);
      expect(srv.clesRecues, ['HL2-loc1']);
    });

    test('envoi normal : une seule requête de création, avec la clé', () async {
      final srv = _VenteSrv(h4: true);
      final f = await _file(srv, v: _vente());
      await f.envoyer();
      expect(f.byId('loc1')!.statut, StatutVenteHL.envoyee);
      expect(srv.clesRecues, ['HL2-loc1']);
      expect(srv.lectures, 0);
    });
  });

  group('Ventes hors ligne — serveur sans H4 (comportement d\'origine)', () {
    test('réponse perdue : anomalie « vérifiez dans les préventes », aucun en-tête, aucune relecture', () async {
      final srv = _VenteSrv(h4: false)..modes.add(_Mode.perdue);
      final f = await _file(srv, v: _vente());
      await f.envoyer();
      final v = f.byId('loc1')!;
      expect(v.statut, StatutVenteHL.aVerifier);
      expect(v.motif, contains('Réponse perdue pendant la création'));
      expect(v.motif, contains('vérifiez dans les préventes'));
      expect(f.anomalies.single.motif, v.motif);
      expect(srv.clesRecues, [null]);
      expect(srv.lectures, 0);
    });

    test('appli fermée pendant la création : anomalie « Envoi interrompu » comme avant', () async {
      final srv = _VenteSrv(h4: false);
      final store = MemoryVentesHLStore();
      await store.put(_vente(statut: StatutVenteHL.envoiEnCours, etape: EtapeHL.creationEnvoyee));
      final f = await _file(srv, store: store);
      await f.envoyer();
      expect(f.byId('loc1')!.statut, StatutVenteHL.aVerifier);
      expect(f.byId('loc1')!.motif, startsWith('Envoi interrompu pendant la création'));
      expect(srv.clesRecues, isEmpty);
    });

    test('étape « envoyée avec clé » mais serveur sans H4 (remplacé) : prudence d\'origine, anomalie', () async {
      final srv = _VenteSrv(h4: false);
      final store = MemoryVentesHLStore();
      await store.put(_vente(statut: StatutVenteHL.envoiEnCours, etape: EtapeHL.creationEnvoyeeRef));
      final f = await _file(srv, store: store);
      await f.envoyer();
      expect(f.byId('loc1')!.statut, StatutVenteHL.aVerifier);
      expect(f.byId('loc1')!.motif, startsWith('Envoi interrompu pendant la création'));
      expect(srv.lectures, 0);
    });

    test('passerelle sans H4 (VenteGateway seule) : envoi inchangé', () async {
      final srv = _VenteSrv(h4: false);
      final f = await _file(srv, v: _vente());
      await f.envoyer();
      expect(f.byId('loc1')!.statut, StatutVenteHL.envoyee);
      expect(srv.clesRecues, [null]);
    });
  });

  group('Retours fournisseurs', () {
    test('H4 : réponse perdue à la création → relue immédiatement, produits suivants envoyés, un seul retour', () async {
      final srv = _RetourSrv(h4: true)..perdreReponse = true;
      final op = _retour();
      await _sender(srv).apply(op);
      expect(srv.retours, hasLength(1));
      expect(srv.clesRecues, ['HL3-20261010090000-ab12']);
      expect(op.meta['retourId'], 'R1');
      expect(op.meta['retourRef'], 'REF-R1');
      expect(op.lines[0].etat, StockLineEtat.dejaApplique);
      expect(op.lines[1].etat, StockLineEtat.applied);
      expect(srv.items.where((i) => i['retourId'] == 'R1'), hasLength(2));
      expect(op.lines.where((l) => l.etat == StockLineEtat.rejected), isEmpty);
    });

    test('H4 : coupure pendant la création (ligne « en cours ») → relue au prochain envoi, jamais recréée', () async {
      final srv = _RetourSrv(h4: true);
      final op = _retour(lignes: 1);
      // 1er envoi : création faite, réponse perdue ET relecture impossible (serveur tombé).
      srv.perdreReponse = true;
      final coupe = _Coupure(srv);
      await expectLater(_sender(coupe).apply(op), throwsA(isA<StockStopException>()));
      expect(op.lines.single.etat, StockLineEtat.sending);
      expect(op.meta['clientRef'], isTrue);
      // 2ᵉ envoi (nouvel envoi, serveur revenu).
      await _sender(srv).apply(op);
      expect(srv.retours, hasLength(1));
      expect(srv.count('/retourfournisseur/new'), 1);
      expect(op.lines.single.etat, StockLineEtat.dejaApplique);
      expect(op.meta['retourId'], 'R1');
    });

    test('H4 : ligne « en cours » mais clé inconnue (rien créé) → renvoi avec la même clé', () async {
      final srv = _RetourSrv(h4: true);
      final op = _retour(lignes: 1);
      op.meta['clientRef'] = true;
      op.lines.single.etat = StockLineEtat.sending;
      await _sender(srv).apply(op);
      expect(srv.retours, hasLength(1));
      expect(op.lines.single.etat, StockLineEtat.applied);
      expect(srv.clesRecues, ['HL3-20261010090000-ab12']);
    });

    test('sans H4 : réponse perdue → anomalie « vérifiez sur Prestige » comme avant, jamais de 2ᵉ retour', () async {
      final srv = _RetourSrv(h4: false)..perdreReponse = true;
      final op = _retour();
      await expectLater(_sender(srv).apply(op), throwsA(isA<StockStopException>()));
      expect(srv.clesRecues, [null], reason: 'aucun en-tête vers un serveur sans H4');
      await _sender(srv).apply(op);
      expect(srv.retours, hasLength(1));
      expect(op.lines.every((l) => l.etat == StockLineEtat.rejected), isTrue);
      expect(op.lines.first.motif, contains('vérifiez sur Prestige'));
      expect(srv.calls.where((c) => c.contains('/mobile/client-ref/')), isEmpty);
    });
  });

  group('HTTP (serveur local)', () {
    late HttpServer server;
    final recus = <({String method, String path, String? cle})>[];
    var capacites = <String, dynamic>{'status': 200, 'body': {'success': true, 'clientRef': true}};

    setUp(() async {
      recus.clear();
      capacites = {'status': 200, 'body': {'success': true, 'clientRef': true}};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await utf8.decoder.bind(req).join();
        recus.add((method: req.method, path: req.uri.path, cle: req.headers.value(enteteClientRef)));
        final r = req.response..headers.contentType = ContentType.json;
        final p = req.uri.path.replaceFirst('/api', '');
        if (p == '/mobile/capacites') {
          r.statusCode = capacites['status'] as int;
          r.write(jsonEncode(capacites['body']));
        } else if (p == '/mobile/client-ref/HL2-connue') {
          r.write(jsonEncode({'success': true, 'type': 'VENTE', 'id': 'V9', 'reference': '261010_00009', 'statut': 'pending', 'existe': true}));
        } else if (p.startsWith('/mobile/client-ref/')) {
          r.statusCode = 404;
          r.write(jsonEncode({'success': false, 'msg': 'Clé client inconnue.'}));
        } else if (p == '/vente/add/vno' || p == '/vente/add/assurance' || p == '/vente/add/item') {
          r.write(jsonEncode({'success': true, 'data': {'lgPREENREGISTREMENTID': 'V9'}}));
        } else if (p == '/retourfournisseur/new') {
          r.write(jsonEncode({'success': true, 'data': {'lgRETOURFRSID': 'R9', 'strREFRETOURFRS': '9'}}));
        } else {
          r.statusCode = 404;
          r.write('{}');
        }
        await r.close();
      });
    });
    tearDown(() => server.close(force: true));

    String base() => 'http://127.0.0.1:${server.port}/api';

    test('en-tête X-Client-Ref sur la création seulement ; passerelle en ligne : aucun en-tête', () => _real(() async {
          final gw = DioVenteGateway(ApiService(baseUrl: base()));
          await gw.addItemVno(produitId: 'P1', qte: 1, itemPu: 100, prevente: true);
          final avec = gw.avecClientRef('HL2-abc');
          await avec.addItemVno(produitId: 'P1', qte: 1, itemPu: 100, prevente: true);
          await avec.addItemVno(produitId: 'P2', qte: 1, itemPu: 100, venteId: 'V9', prevente: true);
          await avec.addItemAssurance(
            produitId: 'P1',
            qte: 1,
            itemPu: 100,
            clientId: 'C',
            ayantDroitId: 'A',
            natureVenteId: '1',
            typeVenteId: '2',
            userVendeurId: null,
            tierspayants: const [],
          );
          expect([for (final r in recus) '${r.path.replaceFirst('/api', '')} ${r.cle}'], [
            '/vente/add/vno null',
            '/vente/add/vno HL2-abc',
            '/vente/add/item null',
            '/vente/add/assurance HL2-abc',
          ]);
        }));

    test('capacité : 200 clientRef → oui (en cache), 401 « expire » / 404 → non, autre réponse → non sans cache', () => _real(() async {
          final gw = DioVenteGateway(ApiService(baseUrl: base()));
          expect(await gw.clientRefSupporte(), isTrue);
          expect(await gw.clientRefSupporte(), isTrue);
          expect(recus.where((r) => r.path.endsWith('/mobile/capacites')), hasLength(1), reason: 'mise en cache');
          CapaciteClientRef.vider();
          capacites = {'status': 401, 'body': {'success': false, 'expire': true}};
          expect(await gw.clientRefSupporte(), isFalse);
          CapaciteClientRef.vider();
          capacites = {'status': 404, 'body': {}};
          expect(await gw.clientRefSupporte(), isFalse);
          CapaciteClientRef.vider();
          capacites = {'status': 500, 'body': {}};
          expect(await gw.clientRefSupporte(), isFalse);
          capacites = {'status': 200, 'body': {'success': true, 'clientRef': true}};
          expect(await gw.clientRefSupporte(), isTrue, reason: 'réponse indéterminée jamais gardée');
        }));

    test('capacité revérifiée après changement de serveur', () => _real(() async {
          final api = ApiService(baseUrl: base());
          final gw = DioVenteGateway(api);
          expect(await gw.clientRefSupporte(), isTrue);
          final autre = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          autre.listen((req) async {
            req.response
              ..statusCode = 404
              ..write('<html>Not Found</html>');
            await req.response.close();
          });
          try {
            // Nouvelle adresse (Réglages) : nouvelle vérification, l'ancien « oui » ne s'applique pas.
            final gw2 = DioVenteGateway(ApiService(baseUrl: 'http://127.0.0.1:${autre.port}/api'));
            expect(await gw2.clientRefSupporte(), isFalse);
          } finally {
            await autre.close(force: true);
          }
        }));

    test('relecture : 200 → création, 404 → clé inconnue', () => _real(() async {
          final gw = DioVenteGateway(ApiService(baseUrl: base()));
          final ok = await gw.lireClientRef('HL2-connue');
          expect(ok.valueOrNull?.id, 'V9');
          expect(ok.valueOrNull?.reference, '261010_00009');
          final inconnue = await gw.lireClientRef('HL2-autre');
          expect(inconnue, isA<VenteOk<ClientRefInfo?>>());
          expect(inconnue.valueOrNull, isNull);
        }));

    test('retour fournisseur : en-tête envoyé par DioStockServer vers un serveur H4', () => _real(() async {
          final dio = Dio(BaseOptions(baseUrl: base()));
          final op = _retour(lignes: 1);
          await _sender(DioStockServer(dio)).apply(op);
          final creation = recus.where((r) => r.path.endsWith('/retourfournisseur/new')).single;
          expect(creation.cle, op.id);
          expect(op.meta['retourId'], 'R9');
        }));
  });

  group('Intégration serveur de test', () {
    final url = Platform.environment['PRESTIGE_TEST_URL'] ?? 'http://localhost:8080/prestige/api/v1';

    Future<DioVenteGateway?> connecter() async {
      try {
        final r = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 2), receiveTimeout: const Duration(seconds: 5)))
            .get('$url/officine');
        if (r.statusCode != 200) return null;
      } catch (_) {
        return null;
      }
      final api = ApiService(baseUrl: url);
      final user = await api.login('admin', 'Test1234');
      if (user == null) return null;
      final gw = DioVenteGateway(api);
      return await gw.clientRefSupporte() ? gw : null;
    }

    test('vente : création arrivée au serveur, réponse perdue → relue par sa clé, une seule vente', () => _real(() async {
          final gw = await connecter();
          if (gw == null) {
            markTestSkipped('Serveur de test injoignable ou sans le patch H4 : $url');
            return;
          }
          // Produit en stock (recherche réelle).
          final page = await gw.searchProductsPage('DOLIMEX', 0, 50);
          final p = page.valueOrNull?.items.where((x) => x.intNUMBERAVAILABLE > 0).firstOrNull;
          if (p == null) {
            markTestSkipped('Aucun produit DOLIMEX en stock sur le serveur de test.');
            return;
          }
          final local = 'it-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
          final cle = cleClientVente(local);
          // La création part avec la clé (comme l'envoi H4) ; la réponse est « perdue » (ignorée ici).
          final c1 = await gw.avecClientRef(cle).addItemVno(produitId: p.lgFAMILLEID, qte: 1, itemPu: p.intPRICE, prevente: true);
          expect(c1.isOk, isTrue, reason: c1.message);
          // Second envoi de la même clé : même vente, rien de recréé.
          final c2 = await gw.avecClientRef(cle).addItemVno(produitId: p.lgFAMILLEID, qte: 1, itemPu: p.intPRICE, prevente: true);
          expect(c2.valueOrNull, c1.valueOrNull);
          final det = await gw.saleDetails(c1.valueOrNull!);
          expect(det.valueOrNull!.single.intQUANTITY, 1, reason: 'aucune ligne en double');
          // Le téléphone redémarre : vente « envoyée avec clé », réponse jamais reçue → l'envoi la relit.
          final store = MemoryVentesHLStore();
          await store.put(VenteHorsLigne(
            id: local,
            numero: 1,
            type: TypeVenteHL.comptant,
            lignes: [LigneHL(cle: 'l1', produitId: p.lgFAMILLEID, nom: p.strNAME, cip: p.intCIP, qte: 1, prix: p.intPRICE)],
            fin: FinVenteHL.prevente,
            totalEstime: p.intPRICE,
            netEstime: p.intPRICE,
            statut: StatutVenteHL.envoiEnCours,
            etape: EtapeHL.creationEnvoyeeRef,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ));
          final f = FileVentesHL(store: store, gateway: gw);
          await f.load();
          await f.envoyer();
          final v = f.byId(local)!;
          expect(v.statut, StatutVenteHL.envoyee, reason: v.motif ?? f.panne);
          expect(v.venteId, c1.valueOrNull);
          expect(f.anomalies, isEmpty);
          final lu = await gw.lireClientRef(cle);
          expect(lu.valueOrNull?.id, c1.valueOrNull);
          expect(lu.valueOrNull?.statut, 'is_Process');
          // ignore: avoid_print
          print('H4 intégration : prévente de test ${lu.valueOrNull?.reference} (clé $cle) — à supprimer du serveur de test.');
        }), timeout: const Timeout(Duration(minutes: 2)));
  });
}

/// Serveur qui « tombe » juste après la création : la création est faite, puis plus rien ne répond.
class _Coupure implements StockServer {
  final _RetourSrv srv;
  bool tombe = false;
  _Coupure(this.srv);

  @override
  Future<StockHttp> call(String method, String path, {Map<String, dynamic>? query, Object? data, Map<String, String>? headers}) async {
    if (tombe) throw const StockStopException('Serveur injoignable : envoi interrompu.');
    if (path == '/retourfournisseur/new') tombe = true;
    return srv.call(method, path, query: query, data: data, headers: headers);
  }
}
