// ÉCRANS — 5.4.0 : retour du pharmacien (SUNMI V3) « vente à crédit, nombre de tickets = 2 : le 1er ticket sort, la
// question pour le 2e n'apparaît plus, le 2e ne sort jamais ».
//
// Cause (régression de la 4.14.0, visible depuis le déploiement du serveur 76aa5fc1 en officine, le 19/11) : quand le
// serveur dessine le ticket (route image), ImpressionTicket.copiesParServeur arrêtait la série après la 1ʳᵉ copie
// (« le serveur décide du nombre d'exemplaires »), alors que la route image est la RÉIMPRESSION du poste et ne rend
// qu'UN exemplaire. Les tests de la 4.10.3 (pause « Ticket suivant (i/N) ») passaient : leur faux serveur n'avait
// pas la route image (gabarit local).
//
// Ces tests passent par le VRAI chemin d'impression : route image du serveur (lente : « Préparation du ticket… »
// affiché), conversion 1 bit, imprimante intégrée Sunmi simulée dont le service se connecte en retard (5.1.0), et la
// pause entre les copies. Données FICTIVES.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/services/contraste_impression.dart';
import 'package:prestige_vente_app/services/impression_ticket.dart';
import 'package:prestige_vente_app/services/imprimante_sunmi.dart';
import 'package:prestige_vente_app/services/largeur_ticket.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/ventes/common/copies_ticket.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/remises_fictives.dart';
import 'outils/tickets_vente_fictifs.dart';

/// Imprimante intégrée Sunmi simulée : le service ne se connecte qu'après [attente] lectures de la version (comme
/// onServiceConnected, plusieurs secondes après le lancement sur un SUNMI V3).
class _SunmiLent {
  int attente;
  final List<String> appels = [];
  _SunmiLent({this.attente = 6});

  int get images => appels.where((a) => a == 'RAW_DATA').length;

  void installer(WidgetTester t) {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(ImprimanteSunmi.canal, (call) async {
      appels.add(call.method);
      switch (call.method) {
        case 'BIND_PRINTER_SERVICE':
          return true;
        case 'PRINTER_VERSION':
          if (attente > 0) {
            attente--;
            return 'NOT FOUND';
          }
          return '2.4.1';
        case 'PAPER_SIZE':
          return 1;
        case 'GET_UPDATE_PRINTER':
          return 'NORMAL';
        default:
          return null;
      }
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(ImprimanteSunmi.canal, null));
  }
}

/// Route image du serveur, lente (dessin du ticket) : [n] tickets par appel.
class _RouteImage implements HttpClientAdapter {
  Duration lenteur = const Duration(seconds: 2);
  int n = 1;
  final List<String> chemins = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    chemins.add(o.path);
    await Future<void>.delayed(lenteur);
    final p = o.queryParameters['largeur'] == 58 ? 384 : 576;
    return ResponseBody.fromString(
      jsonEncode({
        'success': true,
        'largeur': p == 384 ? 58 : 80,
        'dpi': 203,
        'tickets': [
          for (var i = 0; i < n; i++) {'modele': 'VENTE_ASSURANCE', 'png': base64Encode(RemisesFictives.pngFictif(p, 30)), 'largeurPoints': p, 'hauteurPoints': 30}
        ],
      }),
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

enum _Vente { comptant, assurance, carnet }

late _RouteImage _route;
late _SunmiLent _sunmi;

final _pause = find.byKey(const ValueKey('ticket-suivant'));
final _imprimer = find.byKey(const ValueKey('ticket-suivant-imprimer'));
final _arreter = find.byKey(const ValueKey('ticket-suivant-arreter'));
final _preparation = find.byKey(const ValueKey('ticket-preparation'));

Future<void> _uneCopie(BuildContext c, _Vente v, {bool apercu = false, int copiesAncienne = 1, bool confirmer = false}) => switch (v) {
      _Vente.comptant => ReceiptService().printSaleTicket(
          context: c,
          officine: officineTicket,
          saleSummary: SaleSummary(montant: 1530, montantNet: 1530, reference: '20261120000101', venteId: 'V-FICT-C'),
          items: lignesTicket,
          paymentMethod: PaymentMethod(id: '1', name: 'ESPECES'),
          currentUser: vendeurTicket,
          isTestMode: apercu,
          paperWidth: 58,
          showQrCode: false,
          ticketCodeType: 'QR_CODE',
        ),
      _ => ReceiptService().printAssuranceSaleTicket(
          context: c,
          officine: officineTicket,
          saleSummary: ticketAssuranceResume,
          items: lignesTicket,
          client: clientTicket,
          ayantDroit: ayantDroitTicket,
          paymentMethod: PaymentMethod(id: '1', name: v == _Vente.carnet ? 'CARNET' : 'ESPECES'),
          currentUser: vendeurTicket,
          isTestMode: apercu,
          paperWidth: 58,
          ticketCodeType: 'QR_CODE',
          numberOfCopies: copiesAncienne,
          carnet: v == _Vente.carnet,
          confirmEachCopy: confirmer,
        ),
    };

/// Écran fictif : « IMPRIMER » lance [action] ; « QUITTER » ferme l'écran (contexte démonté).
Future<void> _monter(WidgetTester t, Future<void> Function(BuildContext c) action, {bool lancer = true}) async {
  t.view.physicalSize = const Size(720, 1440);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (accueil) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(accueil).push(MaterialPageRoute(
              builder: (_) => Builder(
                builder: (c) => Scaffold(
                  body: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    ElevatedButton(onPressed: () => action(c), child: const Text('IMPRIMER')),
                    ElevatedButton(onPressed: () => Navigator.of(c).pop(), child: const Text('QUITTER')),
                  ]),
                ),
              ),
            )),
            child: const Text('VENTE'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('VENTE'));
  await t.pumpAndSettle();
  if (lancer) await t.tap(find.text('IMPRIMER'));
}

/// Avance le temps (pas de 100 ms, 8 s au plus) jusqu'à ce que [f] soit affiché.
Future<void> _attendre(WidgetTester t, Finder f) async {
  for (var i = 0; i < 80 && f.evaluate().isEmpty; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.pumpAndSettle();
}

/// Attend la fin de la copie en cours : bandeau « Préparation du ticket… » pendant la lecture, puis impression.
Future<void> _copieImprimee(WidgetTester t) async {
  // Attente de la connexion Sunmi (1ʳᵉ copie), puis lecture lente de l'image : le bandeau finit par s'afficher.
  for (var i = 0; i < 40 && _preparation.evaluate().isEmpty; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  expect(_preparation, findsOneWidget, reason: 'serveur lent : « Préparation du ticket… » affiché');
  expect(_pause, findsNothing, reason: 'jamais de question pendant une copie');
  await t.pumpAndSettle();
  expect(_preparation, findsNothing, reason: 'bandeau retiré après la lecture');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DroitsVente.instance.fixer(null);
    TicketServeur.oublier();
    ImpressionTicket.reinitialiser();
    ImprimanteSunmi.reinitialiser(avec: () async => true, pas: const Duration(milliseconds: 100));
    LargeurTicket.reinitialiser();
    ReglageContraste.reinitialiser();
    _route = _RouteImage();
    ImpressionTicket.dioDe = (_) => Dio(BaseOptions(baseUrl: 'http://serveur-fictif/prestige/api/v1'))..httpClientAdapter = _route;
  });
  tearDown(() {
    ImpressionTicket.reinitialiser();
    ImprimanteSunmi.reinitialiser();
    LargeurTicket.reinitialiser();
  });

  group('ticket du serveur + Sunmi lent : le nombre de tickets choisi est respecté', () {
    for (final v in _Vente.values) {
      for (final n in [1, 2, 3]) {
        testWidgets('${v.name}, $n ticket(s) : copie 1, puis « Ticket suivant (i/$n) » et la copie i', (t) async {
          _sunmi = _SunmiLent()..installer(t);
          await _monter(t, (c) => imprimerCopiesAvecPause(c, n, () => _uneCopie(c, v)));
          await _copieImprimee(t);
          expect(_sunmi.images, 1, reason: 'copie 1 imprimée (service Sunmi connecté en retard)');
          for (var i = 2; i <= n; i++) {
            expect(_pause, findsOneWidget, reason: 'question avant la copie $i (absente en 5.3.0)');
            expect(find.text('Ticket suivant ($i/$n)'), findsOneWidget);
            expect(find.text('Coupez le ticket, puis imprimez le suivant.'), findsOneWidget);
            await t.tap(_imprimer);
            await _copieImprimee(t);
            expect(_sunmi.images, i);
          }
          expect(_pause, findsNothing, reason: 'aucune question après la dernière copie');
          expect(_route.chemins, List.filled(n, '/vente/ticket/${v == _Vente.comptant ? 'vno' : 'vo'}/${v == _Vente.comptant ? 'V-FICT-C' : 'V-FICT-A'}/image'));
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('assurance à deux tickets serveur par vente (vente + ticket combiné), 2 exemplaires : 4 images', (t) async {
      _sunmi = _SunmiLent()..installer(t);
      _route.n = 2;
      await _monter(t, (c) => imprimerCopiesAvecPause(c, 2, () => _uneCopie(c, _Vente.assurance)));
      await _copieImprimee(t);
      expect(_sunmi.images, 2);
      expect(find.text('Ticket suivant (2/2)'), findsOneWidget);
      await t.tap(_imprimer);
      await _copieImprimee(t);
      expect(_sunmi.images, 4);
      expect(ImpressionTicket.imagesImprimees, 4);
    });

    testWidgets('« Arrêter » à la question 2/2 : le 2e ticket n\'est pas demandé au serveur', (t) async {
      _sunmi = _SunmiLent()..installer(t);
      await _monter(t, (c) => imprimerCopiesAvecPause(c, 2, () => _uneCopie(c, _Vente.assurance)));
      await _copieImprimee(t);
      await t.tap(_arreter);
      await t.pumpAndSettle();
      expect(_sunmi.images, 1);
      expect(_route.chemins, hasLength(1));
      expect(_pause, findsNothing);
    });

    testWidgets('Sunmi pas encore connecté au 1er ticket (V3 juste lancé) : motif, « Réimprimer », puis la question 2/2', (t) async {
      _sunmi = _SunmiLent(attente: 1000)..installer(t);
      ImprimanteSunmi.reinitialiser(avec: () async => true, pas: const Duration(milliseconds: 100), delai: const Duration(seconds: 1));
      await _monter(t, (c) => imprimerCopiesAvecPause(c, 2, () => _uneCopie(c, _Vente.assurance)));
      await _attendre(t, find.byKey(const ValueKey('ticket-non-imprime')));
      expect(find.byKey(const ValueKey('ticket-non-imprime')), findsOneWidget);
      expect(_pause, findsNothing, reason: 'la question vient après le 1er ticket, pas à sa place');
      _sunmi.attente = 0;
      await t.tap(find.byKey(const ValueKey('ticket-reimprimer')));
      await _copieImprimee(t);
      expect(_sunmi.images, 1);
      expect(find.text('Ticket suivant (2/2)'), findsOneWidget);
      await t.tap(_imprimer);
      await _copieImprimee(t);
      expect(_sunmi.images, 2);
    });

    testWidgets('écran fermé pendant la préparation du 1er ticket : ni question ni 2e ticket, aucune erreur', (t) async {
      _sunmi = _SunmiLent()..installer(t);
      await _monter(t, (c) => imprimerCopiesAvecPause(c, 2, () => _uneCopie(c, _Vente.assurance)));
      for (var i = 0; i < 40 && _preparation.evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(_preparation, findsOneWidget);
      await t.tap(find.text('QUITTER'));
      await t.pumpAndSettle();
      expect(_preparation, findsNothing, reason: 'bandeau retiré même écran fermé');
      expect(_pause, findsNothing);
      expect(_route.chemins, hasLength(1));
      expect(_sunmi.images, 0, reason: 'écran fermé avant la réponse : rien n\'est imprimé à l\'aveugle');
      expect(t.takeException(), isNull);
    });

    testWidgets('mode test d\'impression : aperçu du ticket serveur, question 2/2, second aperçu', (t) async {
      _sunmi = _SunmiLent()..installer(t);
      await _monter(t, (c) => imprimerCopiesAvecPause(c, 2, () => _uneCopie(c, _Vente.carnet, apercu: true)));
      await _attendre(t, find.byKey(const ValueKey('ticket-serveur-apercu')));
      expect(find.byKey(const ValueKey('ticket-serveur-apercu')), findsOneWidget);
      await t.tap(find.text('Fermer'));
      await t.pumpAndSettle();
      expect(find.text('Ticket suivant (2/2)'), findsOneWidget);
      await t.tap(_imprimer);
      await _attendre(t, find.byKey(const ValueKey('ticket-serveur-apercu')));
      expect(find.byKey(const ValueKey('ticket-serveur-apercu')), findsOneWidget);
      await t.tap(find.text('Fermer'));
      await t.pumpAndSettle();
      expect(_pause, findsNothing);
      expect(_sunmi.images, 0);
    });

    testWidgets('ancienne interface (ReceiptService, 2 copies, « Réimpression (2/2) ») : 2e ticket après le ticket du serveur', (t) async {
      _sunmi = _SunmiLent()..installer(t);
      await _monter(t, (c) => _uneCopie(c, _Vente.assurance, copiesAncienne: 2, confirmer: true));
      await _copieImprimee(t);
      expect(_sunmi.images, 1);
      expect(find.text('Voulez-vous réimprimer le ticket ? (2/2)'), findsOneWidget);
      await t.tap(find.text('Oui'));
      await _copieImprimee(t);
      expect(_sunmi.images, 2);
    });

    testWidgets('route absente (serveur ancien, gabarit local) : pause et 2e ticket, comme avant', (t) async {
      _sunmi = _SunmiLent(attente: 0)..installer(t);
      ImpressionTicket.dioDe = (_) => null;
      await _monter(t, (c) => imprimerCopiesAvecPause(c, 2, () => _uneCopie(c, _Vente.comptant)));
      await _attendre(t, _pause);
      final textes1 = _sunmi.appels.where((a) => a == 'PRINT_TEXT').length;
      expect(textes1, greaterThan(0));
      expect(find.text('Ticket suivant (2/2)'), findsOneWidget);
      await t.tap(_imprimer);
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(_sunmi.appels.where((a) => a == 'PRINT_TEXT').length, 2 * textes1);
    });
  });

  test('aucun délai inutile : la question 2/2 n\'attend que la fin du 1er ticket (canal du paquet inchangé)', () {
    expect(ImprimanteSunmi.canal, const MethodChannel('sunmi_printer_plus'));
    expect(ImpressionTicket.delaiPreparation, const Duration(milliseconds: 300));
  });
}
