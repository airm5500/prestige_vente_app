// UNITAIRES + ÉCRANS — 5.4.0 : réédition des ventes (comptant, assurance, carnet) faites sur ce terminal.
//  - VentesDuTerminal : identifiants seulement (ni client, ni montant), 45 jours, noté à la clôture acceptée ;
//  - ReeditionVentesService : GET v1/ventestats (jour, type, n° de ticket), pages, refus et réseau ;
//  - écran : ce terminal par défaut (vente notée OU poste du serveur), « Tous les postes », jour, type, recherche ;
//    « Réimprimer » = ticket du serveur (route image vno / vo), nombre d'exemplaires et pause « Ticket suivant ».
// Données FICTIVES.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/services/impression_ticket.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/ventes/reedition/reedition_ventes.dart';
import 'package:prestige_vente_app/ventes/reedition/reedition_ventes_screen.dart';
import 'package:prestige_vente_app/ventes/reedition/ventes_du_terminal.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/remises_fictives.dart';

/// Faux serveur : liste des ventes terminées et route image.
class _Serveur implements HttpClientAdapter {
  List<Map<String, dynamic>> ventes = [];
  final List<RequestOptions> listes = [];
  final List<String> images = [];
  int? statutListe;
  bool coupe = false;
  bool routeImage = true;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    if (coupe) throw DioException.connectionError(requestOptions: o, reason: 'coupé');
    ResponseBody json(Object b, [int st = 200]) =>
        ResponseBody.fromString(jsonEncode(b), st, headers: {Headers.contentTypeHeader: ['application/json']});
    if (o.path == '/ventestats') {
      listes.add(o);
      if (statutListe != null) return json({'success': false}, statutListe!);
      final q = '${o.queryParameters['query'] ?? ''}';
      final t = o.queryParameters['lgTypeVenteId'];
      final l = [
        for (final v in ventes)
          if ((t == null || v['lgTYPEVENTEID'] == t) && (q.isEmpty || '${v['strREFTICKET']}'.startsWith(q) || '${v['strREF']}'.startsWith(q))) v
      ];
      final start = o.queryParameters['start'] as int, limit = o.queryParameters['limit'] as int;
      return json({'total': l.length, 'data': l.skip(start).take(limit).toList()});
    }
    final m = RegExp(r'/vente/ticket/(vno|vo)/([^/]+)/image$').firstMatch(o.path);
    if (m != null) {
      images.add('${m.group(1)} ${m.group(2)}');
      if (!routeImage) return json({'success': false}, 404);
      return json({
        'success': true,
        'largeur': 58,
        'dpi': 203,
        'tickets': [
          {'modele': 'VENTE', 'png': base64Encode(RemisesFictives.pngFictif(384, 30)), 'largeurPoints': 384, 'hauteurPoints': 30}
        ],
      });
    }
    return json({'success': false}, 404);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _vente(String id, String ticket, String type, String heure, {String poste = '', int prix = 2500, String client = 'CLIENT FICTIF'}) => {
      'lgPREENREGISTREMENTID': id,
      'strREF': 'REF-$id',
      'strREFTICKET': ticket,
      'intPRICE': prix,
      'intCUSTPART': prix,
      'dtUPDATED': DateFormat('dd/MM/yyyy').format(DateTime.now()),
      'heure': heure,
      'strTYPEVENTE': type == '1' ? 'VNO' : 'VO',
      'lgTYPEVENTEID': type,
      'cancel': false,
      'posteSaisie': poste,
      'posteEncaissement': poste,
      'clientFullName': client,
    };

late _Serveur _srv;
late Dio _dio;

Future<void> _ecran(WidgetTester t) async {
  t.view.physicalSize = const Size(720, 1440);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
  final settings = SettingsProvider();
  await settings.loadSettings();
  await t.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
    value: settings,
    child: MaterialApp(home: ReeditionVentesScreen(dio: _dio)),
  ));
  await t.pumpAndSettle();
}

Finder _carte(String id) => find.byKey(ValueKey('reedition-vente-$id'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'paper_width': 58});
    VentesDuTerminal.reinitialiser();
    TicketServeur.oublier();
    ImpressionTicket.reinitialiser();
    _srv = _Serveur();
    _dio = Dio(BaseOptions(baseUrl: 'http://serveur-fictif/prestige/api/v1'))..httpClientAdapter = _srv;
    ImpressionTicket.dioDe = (_) => _dio;
    ImpressionTicket.imprimeur = (tickets) async => null;
  });
  tearDown(ImpressionTicket.reinitialiser);

  group('ventes de ce terminal (stockage local)', () {
    test('identifiants seulement, gardés sur l\'appareil, relus ; 45 jours au plus', () async {
      final r = VentesDuTerminal();
      await r.noter('V-1', type: 'vno');
      await r.noter('V-2', type: 'vo');
      final brut = (await SharedPreferences.getInstance()).getString(VentesDuTerminal.cle)!;
      final l = jsonDecode(brut) as List;
      expect(l, hasLength(2));
      for (final e in l) {
        expect((e as Map).keys.toSet(), {'id', 't', 'd'}, reason: 'aucune donnée client, aucun montant');
      }
      final relu = VentesDuTerminal();
      await relu.charger();
      expect(relu.contient('V-1') && relu.contient('V-2'), isTrue);
      expect(relu.ventes.first.id, 'V-2');
      final vieux = VentesDuTerminal()..maintenant = () => DateTime.now().add(const Duration(days: 46));
      await vieux.charger();
      expect(vieux.nombre, 0, reason: 'plus de 45 jours : oubliées');
    });

    test('intercepteur : clôture acceptée notée (vno / assurance / dépôt) ; refus, panier et prévente ignorés', () async {
      final reg = VentesDuTerminal();
      final dio = Dio(BaseOptions(baseUrl: 'http://serveur-fictif/prestige/api/v1'))
        ..interceptors.add(VentesDuTerminalInterceptor(registre: () => reg))
        ..httpClientAdapter = _Reponses({
          '/vente/cloturer/vno': {'success': true},
          '/vente/cloturer/assurance': {'success': false, 'msg': 'Bon déjà utilisé'},
          '/vente/clotureVenteDepot': {'success': true},
          '/vente/add/item': {'success': true},
        });
      await dio.post('/vente/cloturer/vno', data: {'venteId': 'V-C'});
      await dio.post('/vente/cloturer/assurance', data: {'venteId': 'V-A'});
      await dio.post('/vente/clotureVenteDepot', data: {'venteId': 'V-D'});
      await dio.post('/vente/add/item', data: {'venteId': 'V-X'});
      await Future<void>.delayed(Duration.zero);
      expect(reg.ventes.map((v) => '${v.id}:${v.type}').toSet(), {'V-C:vno', 'V-D:vo'});
      expect(VentesDuTerminalInterceptor.typeCloture('POST', '/prestige/api/v1/vente/cloturer/assurance'), 'vo');
      expect(VentesDuTerminalInterceptor.typeCloture('GET', '/vente/cloturer/vno'), isNull);
      expect(VentesDuTerminalInterceptor.typeCloture('PUT', '/vente/terminerprevente/V-1'), isNull);
    });
  });

  group('liste du serveur (GET v1/ventestats)', () {
    test('jour, type (lgTypeVenteId), n° de ticket ; plus récentes d\'abord', () async {
      _srv.ventes = [_vente('V-1', '1000000001', '1', '08:05'), _vente('V-2', '1000000002', '2', '09:30'), _vente('V-3', '1000000003', '3', '10:15')];
      final r = await ReeditionVentesService(_dio).lister(jour: DateTime(2026, 11, 20), type: TypeReedition.assurance, recherche: '1000');
      final q = _srv.listes.single.queryParameters;
      expect(q['dtStart'], '2026-11-20');
      expect(q['dtEnd'], '2026-11-20');
      expect((q['hStart'], q['hEnd']), ('00:00', '23:59'));
      expect(q['lgTypeVenteId'], '2');
      expect(q['query'], '1000');
      expect((r as ListeVentes).ventes.single.id, 'V-2');
      final tous = await ReeditionVentesService(_dio).lister(jour: DateTime(2026, 11, 20)) as ListeVentes;
      expect(tous.ventes.map((v) => v.id), ['V-3', 'V-2', 'V-1']);
      expect(tous.ventes.map((v) => v.categorie), [TypeReedition.carnet, TypeReedition.assurance, TypeReedition.comptant]);
      expect(tous.ventes.map((v) => v.typeImage), ['vo', 'vo', 'vno']);
    });

    test('journée chargée : pages lues, les 1 000 plus récentes au plus', () async {
      _srv.ventes = [for (var i = 0; i < 1100; i++) _vente('V-$i', '${2000000000 + i}', '1', '${(i ~/ 60 % 24).toString().padLeft(2, '0')}:${(i % 60).toString().padLeft(2, '0')}')];
      final r = await ReeditionVentesService(_dio).lister(jour: DateTime.now()) as ListeVentes;
      expect(r.ventes, hasLength(1000));
      expect(r.tronquee, isTrue);
      expect(r.ventes.any((v) => v.id == 'V-1099'), isTrue, reason: 'la plus récente');
      expect(r.ventes.any((v) => v.id == 'V-0'), isFalse);
    });

    test('session expirée, refus, réseau coupé : messages clairs (jamais « aucune vente »)', () async {
      _srv.statutListe = 401;
      expect((await ReeditionVentesService(_dio).lister(jour: DateTime.now()) as EchecListeVentes).message, ReeditionVentesService.messageSession);
      _srv.statutListe = 500;
      expect((await ReeditionVentesService(_dio).lister(jour: DateTime.now()) as EchecListeVentes).message, contains('code 500'));
      _srv
        ..statutListe = null
        ..coupe = true;
      expect((await ReeditionVentesService(_dio).lister(jour: DateTime.now()) as EchecListeVentes).message, ReeditionVentesService.messageReseau);
    });

    test('vente de ce terminal : notée à la clôture OU poste du serveur égal au nom de l\'appareil', () {
      final a = VenteTerminee.fromJson(_vente('V-1', '1', '1', '08:00', poste: 'Poste test'))!;
      final b = VenteTerminee.fromJson(_vente('V-2', '2', '1', '08:00', poste: 'CAISSE 2'))!;
      expect(a.deCeTerminal(notee: (_) => false, nomPoste: 'Poste test'), isTrue);
      expect(b.deCeTerminal(notee: (_) => false, nomPoste: 'Poste test'), isFalse);
      expect(b.deCeTerminal(notee: (id) => id == 'V-2', nomPoste: 'Poste test'), isTrue);
      expect(b.deCeTerminal(notee: (_) => false, nomPoste: null), isFalse);
    });
  });

  group('écran « Réédition des ventes »', () {
    setUp(() {
      _srv.ventes = [
        _vente('V-10', '3100000010', '1', '08:10'), // notée sur ce terminal (poste du serveur différent)
        _vente('V-11', '3100000011', '2', '09:20', poste: 'Poste test'), // poste du serveur = ce terminal
        _vente('V-12', '3100000012', '3', '10:30', poste: 'Poste test'),
        _vente('V-20', '3200000020', '1', '11:40', poste: 'CAISSE 2'), // autre terminal
      ];
    });

    testWidgets('ce terminal par défaut ; « Tous les postes » ; type ; recherche par n° de ticket', (t) async {
      await VentesDuTerminal.instance.noter('V-10', type: 'vno');
      expect(NomAppareil.instance.effectif, 'Poste test');
      await _ecran(t);
      expect(find.text('Réédition des ventes'), findsOneWidget);
      for (final id in ['V-10', 'V-11', 'V-12']) {
        expect(_carte(id), findsOneWidget);
      }
      expect(_carte('V-20'), findsNothing, reason: 'vente d\'un autre terminal');
      await t.tap(find.text('Tous les postes'));
      await t.pumpAndSettle();
      expect(_carte('V-20'), findsOneWidget);
      await t.tap(find.text('Ce terminal'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('reedition-type-carnet')));
      await t.pumpAndSettle();
      expect(_srv.listes.last.queryParameters['lgTypeVenteId'], '3');
      expect(_carte('V-12'), findsOneWidget);
      expect(_carte('V-10'), findsNothing);
      await t.tap(find.byKey(const ValueKey('reedition-type-tous')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('reedition-recherche')), '3100000011');
      await t.pump(const Duration(milliseconds: 600));
      await t.pumpAndSettle();
      expect(_srv.listes.last.queryParameters['query'], '3100000011');
      expect(_carte('V-11'), findsOneWidget);
      expect(_carte('V-10'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('« Hier » : liste du jour précédent ; aucune vente du terminal → message, pas d\'erreur', (t) async {
      await _ecran(t);
      await t.tap(find.byKey(const ValueKey('reedition-jour-hier')));
      await t.pumpAndSettle();
      final hier = DateTime.now().subtract(const Duration(days: 1));
      expect(_srv.listes.last.queryParameters['dtStart'], DateFormat('yyyy-MM-dd').format(hier));
      _srv.ventes = [_vente('V-20', '3200000020', '1', '11:40', poste: 'CAISSE 2')];
      await t.tap(find.byKey(const ValueKey('reedition-actualiser')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('reedition-vide')), findsOneWidget);
      expect(find.textContaining('Tous les postes'), findsWidgets);
    });

    testWidgets('réseau coupé : message et « Réessayer »', (t) async {
      _srv.coupe = true;
      await _ecran(t);
      expect(find.text(ReeditionVentesService.messageReseau), findsOneWidget);
      _srv.coupe = false;
      await t.tap(find.text('Réessayer'));
      await t.pumpAndSettle();
      expect(_carte('V-11'), findsOneWidget);
    });

    for (final (id, type) in [('V-10', 'vno'), ('V-11', 'vo'), ('V-12', 'vo')]) {
      testWidgets('« Réimprimer » $id, 2 exemplaires : ticket du serveur ($type), « Ticket suivant (2/2) », 2e exemplaire', (t) async {
        await VentesDuTerminal.instance.noter('V-10', type: 'vno');
        final imprimes = <int>[];
        ImpressionTicket.imprimeur = (tickets) async {
          imprimes.add(tickets.length);
          return null;
        };
        await _ecran(t);
        await t.ensureVisible(find.byKey(ValueKey('reedition-reimprimer-$id')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(ValueKey('reedition-reimprimer-$id')));
        await t.pumpAndSettle();
        expect(find.textContaining('Réimprimer le ticket N°'), findsOneWidget);
        await t.tap(find.byTooltip('Plus de copies'));
        await t.pump();
        expect(find.text('2 copies'), findsOneWidget);
        await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Imprimer')));
        await t.pumpAndSettle();
        expect(imprimes, [1]);
        expect(find.text('Ticket suivant (2/2)'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('ticket-suivant-imprimer')));
        await t.pumpAndSettle();
        expect(imprimes, [1, 1]);
        expect(_srv.images, ['$type $id', '$type $id']);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('« Ne pas imprimer » : rien n\'est demandé au serveur', (t) async {
      await _ecran(t);
      await t.tap(find.byKey(const ValueKey('reedition-reimprimer-V-11')));
      await t.pumpAndSettle();
      await t.tap(find.text('Ne pas imprimer'));
      await t.pumpAndSettle();
      expect(_srv.images, isEmpty);
    });
  });
}

class _Reponses implements HttpClientAdapter {
  final Map<String, Object> corps;
  _Reponses(this.corps);
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async =>
      ResponseBody.fromString(jsonEncode(corps[o.path] ?? {'success': false}), 200, headers: {Headers.contentTypeHeader: ['application/json']});
  @override
  void close({bool force = false}) {}
}
