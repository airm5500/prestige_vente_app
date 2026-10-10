// Envoi des quantités contrôlées (attente du serveur, « non enregistrée », Réessayer, sortie protégée)
// et échecs de chargement distingués d'une liste vide.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/api/models/commande.dart';
import 'package:prestige_vente_app/api/models/reception_model.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/delivery_control_provider.dart';
import 'package:prestige_vente_app/providers/reception_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/bl_control/bl_list_screen.dart';
import 'package:prestige_vente_app/screens/delivery_control/delivery_list_screen.dart';
import 'package:prestige_vente_app/screens/reception_control/reception_detail_screen.dart';
import 'package:prestige_vente_app/screens/reception_control/reception_list_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ReceptionItem _item(String id, String name, int expected) => ReceptionItem(
      id: id,
      produitId: 'p$id',
      nomProduit: name,
      cip: '34000$id',
      ean: '',
      qteCommandee: expected,
      qteRecue: expected,
      quantiteControle: 0,
      prixAchat: 1000,
      prixVente: 1500,
      emplacement: 'RAYON A1',
    );

class _Api extends ApiService {
  _Api() : super(baseUrl: 'http://localhost');

  /// Message d'échec du chargement (null = succès).
  String? loadFailure;

  /// Résultat des envois de quantité.
  bool postOk = true;
  final posted = <(String, int)>[];

  @override
  Future<List<ReceptionBon>> getReceptionBons({String query = '', String? dtStart, String? dtEnd}) async {
    if (loadFailure != null) throw ApiLoadException(loadFailure!);
    return [
      ReceptionBon(
        id: 'b1',
        ref: 'BL-0001',
        grossiste: 'LABOREX',
        dateLivraison: '10/10/2026',
        dateCreation: '10/10/2026',
        statutTraitement: 'EN_COURS',
        nbreLignes: 2,
        montantHt: 1000,
        details: [_item('d1', 'DOLIPRANE 1000MG', 5), _item('d2', 'EFFERALGAN 500MG', 3)],
      ),
    ];
  }

  @override
  Future<List<BonLivraison>> getBonsLivraison({String query = '', String? dtStart, String? dtEnd}) async {
    if (loadFailure != null) throw ApiLoadException(loadFailure!);
    return [];
  }

  @override
  Future<List<Commande>> getCommandes() async {
    if (loadFailure != null) throw ApiLoadException(loadFailure!);
    return [];
  }

  @override
  Future<bool> postBonItemCheckedQuantity({required String detailId, required int quantity}) async {
    posted.add((detailId, quantity));
    return postOk;
  }
}

/// Vrai client HTTP (le banc de test Flutter remplace les requêtes par des réponses 400).
class _RealHttp extends HttpOverrides {}

Future<void> _real(Future<void> Function() body) => HttpOverrides.runWithHttpOverrides(body, _RealHttp());

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ApiService : échec de chargement ≠ liste vide', () {
    late HttpServer server;
    late ApiService api;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        final r = req.response;
        switch (req.uri.path) {
          case '/ok/commande/list':
            r.headers.contentType = ContentType.json;
            r.write(jsonEncode({'data': []}));
          case '/html/commande/list':
            r.headers.contentType = ContentType.html;
            r.write('<html>Connexion</html>');
          default:
            r.statusCode = 500;
        }
        r.close();
      });
    });
    tearDown(() => server.close(force: true));

    test('liste vide renvoyée seulement si le serveur a répondu', () => _real(() async {
          api = ApiService(baseUrl: 'http://127.0.0.1:${server.port}/ok');
          expect(await api.getCommandes(), isEmpty);
        }));

    test('erreur serveur, page HTML (session expirée), serveur injoignable : exception claire', () => _real(() async {
      api = ApiService(baseUrl: 'http://127.0.0.1:${server.port}/err');
      await expectLater(api.getCommandes(), throwsA(isA<ApiLoadException>().having((e) => e.message, 'message', contains('500'))));
      api = ApiService(baseUrl: 'http://127.0.0.1:${server.port}/html');
      await expectLater(api.getCommandes(), throwsA(isA<ApiLoadException>().having((e) => e.message, 'message', contains('session'))));
      final port = server.port;
      await server.close(force: true);
      api = ApiService(baseUrl: 'http://127.0.0.1:$port/ok');
      await expectLater(api.getCommandes(), throwsA(isA<ApiLoadException>().having((e) => e.message, 'message', contains('injoignable'))));
    }));
  });

  group('Providers', () {
    test('échec de chargement : message, la liste précédente reste', () async {
      final api = _Api();
      final p = ReceptionProvider(api);
      await p.fetchReceptionBons();
      expect(p.receptionBons, hasLength(1));
      api.loadFailure = 'Serveur injoignable.';
      await p.fetchReceptionBons();
      expect(p.loadError, 'Serveur injoignable.');
      expect(p.receptionBons, hasLength(1));
      api.loadFailure = null;
      await p.fetchReceptionBons();
      expect(p.loadError, isNull);

      final bl = BlControlProvider(api..loadFailure = 'x');
      await bl.fetchBonsLivraison();
      expect(bl.loadError, 'x');
      final cmd = DeliveryControlProvider(api);
      await cmd.fetchCommandes();
      expect(cmd.loadError, 'x');
    });

    test('quantité refusée : marquée non enregistrée puis Réessayer', () async {
      final api = _Api()..postOk = false;
      final p = ReceptionProvider(api);
      await p.fetchReceptionBons();
      p.selectBon(p.receptionBons.first);
      expect(await p.updateQuantity('d1', 4), isFalse);
      expect(p.unsyncedCount, 1);
      expect(p.isUnsynced('d1'), isTrue);
      expect(p.currentCheckedQuantities['d1'], 4); // la saisie n'est pas perdue

      expect(await p.retryUnsyncedQuantities(), 1); // toujours en échec
      api.postOk = true;
      expect(await p.retryUnsyncedQuantities(), 0);
      expect(p.unsyncedCount, 0);
      expect(api.posted.last, ('d1', 4));
    });

    test('une saisie plus récente l\'emporte sur la réponse d\'un envoi dépassé', () async {
      final api = _Api()..postOk = false;
      final p = ReceptionProvider(api);
      await p.fetchReceptionBons();
      p.selectBon(p.receptionBons.first);
      final first = p.updateQuantity('d1', 4); // échouera
      p.currentCheckedQuantities; // la ligne est déjà à 4 localement
      api.postOk = true;
      final second = p.updateQuantity('d1', 5); // réussira
      await Future.wait([first, second]);
      expect(p.unsyncedCount, 0);
      expect(p.currentCheckedQuantities['d1'], 5);
    });
  });

  group('Écrans', () {
    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(720, 1400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('Contrôle Réception : échec de chargement affiché, pas « aucun bon »', (tester) async {
      phone(tester);
      final api = _Api()..loadFailure = 'Serveur injoignable (bons de réception non chargés).';
      await tester.pumpWidget(ChangeNotifierProvider<ReceptionProvider>.value(
        value: ReceptionProvider(api),
        child: MaterialApp(home: ReceptionListScreen(presentation: ListPresentation.dashboard, clock: () => DateTime(2026, 10, 10))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Chargement impossible'), findsOneWidget);
      expect(find.textContaining('Serveur injoignable'), findsOneWidget);
      api.loadFailure = null;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Chargement impossible'), findsNothing);
      expect(find.textContaining('BL-0001'), findsWidgets);
    });

    testWidgets('Pointage BL Stock et Contrôle Livraison : bandeau d\'erreur', (tester) async {
      phone(tester);
      final api = _Api()..loadFailure = 'Session expirée ou accès refusé (bons de livraison). Reconnectez-vous.';
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => BlControlProvider(api)),
          ChangeNotifierProvider(create: (_) => DeliveryControlProvider(api)),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const MaterialApp(home: BlListScreen(presentation: ListPresentation.compact)),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Session expirée'), findsOneWidget);
      expect(find.text('Liste non chargée.'), findsOneWidget);
      expect(find.textContaining('Aucun bon'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => DeliveryControlProvider(api)),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const MaterialApp(home: DeliveryListScreen(presentation: ListPresentation.guided)),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Session expirée'), findsOneWidget);
      expect(find.text('Liste non chargée.'), findsOneWidget);
    });

    testWidgets('Comptage : quantité non enregistrée signalée, Réessayer, sortie protégée', (tester) async {
      phone(tester);
      final api = _Api()..postOk = false;
      final p = ReceptionProvider(api);
      await p.fetchReceptionBons();
      p.selectBon(p.receptionBons.first);
      await tester.pumpWidget(ChangeNotifierProvider<ReceptionProvider>.value(
        value: p,
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).push(
                    MaterialPageRoute(builder: (_) => const ReceptionDetailScreen(presentation: ListPresentation.dashboard)),
                  ),
                  child: const Text('ouvrir'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('qte_d1')), '4');
      await tester.showKeyboard(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(find.text('1 quantité non enregistrée sur le serveur.'), findsOneWidget);
      expect(find.byTooltip('Non enregistrée sur le serveur'), findsOneWidget);

      // Retour : avertissement, on reste.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Quantités non enregistrées'), findsOneWidget);
      await tester.tap(find.text('Rester'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceptionDetailScreen), findsOneWidget);

      // Le réseau revient : Réessayer enregistre et le bandeau disparaît.
      api.postOk = true;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('1 quantité non enregistrée sur le serveur.'), findsNothing);
      expect(api.posted.last, ('d1', 4));

      // Plus rien en attente : on quitte sans question.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReceptionDetailScreen), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
