// ÉCRANS — 4.14.0 : remise des ventes assurance / carnet (contrat commun RemiseVenteVoMixin) et impression du ticket
// dessiné par le serveur (ImpressionTicket) : route absente → gabarit local ; présente → images imprimées telles quelles,
// un exemplaire par copie (5.4.0 : le nombre de tickets de l'appareil est respecté) ; échec d'impression (papier, Bluetooth) → motif + « Réimprimer » ; réseau coupé
// alors que le serveur dessine → « Ticket non imprimé : réseau indisponible ». Données FICTIVES.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/services/impression_ticket.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/ventes/common/copies_ticket.dart';
import 'package:prestige_vente_app/ventes/common/remise_vente.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

import 'outils/remises_fictives.dart';
import 'outils/tickets_vente_fictifs.dart';

/// Contrôleur minimal (comme Assurance / Carnet) : net relu sur le serveur simulé, remise de la vente ou du client.
class _VoFictif extends ChangeNotifier with RemiseVenteVoMixin {
  final _GwVo gw;
  _VoFictif(this.gw);
  String? venteId = 'V-VO-1';
  bool horsLigne = false;
  bool fini = false;
  int epoch = 0;
  int remiseNet = 0;
  int nets = 0;

  @override
  bool get busy => false;
  @override
  Object get passerelleRemise => gw;
  @override
  String? get venteIdRemise => venteId;
  @override
  bool get remiseHorsLigne => horsLigne;
  @override
  bool get remiseTerminee => fini;
  @override
  int get remiseEpoch => epoch;
  @override
  int get remiseDuNet => remiseNet;
  @override
  Future<T> remiseDansLaFile<T>(Future<T> Function() op) => op();
  @override
  Future<void> apresRemise() async {
    nets++;
    // Serveur : remise de la vente, à défaut celle de la fiche du client.
    final r = gw.remiseVente ?? gw.remiseClient;
    remiseNet = r == null ? 0 : 500;
    notifyListeners();
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> relireVentePourRemise(String id) async => VenteOk({'lgREMISEID': gw.remiseVente});
}

class _GwVo implements RemiseVenteGateway {
  String? remiseVente;
  String? remiseClient;
  VenteResult<void>? reponse;
  final List<String?> poses = [];

  @override
  Future<VenteResult<List<RemiseOption>>> remisesVente() async => const VenteOk([RemiseOption(id: 'REM-FICT-10', nom: 'REMISE FICTIVE 10 %')]);

  @override
  Future<VenteResult<void>> appliquerRemise(String venteId, String? remiseId) async {
    poses.add(remiseId);
    final r = reponse;
    if (r != null) return r;
    remiseVente = remiseId;
    return const VenteOk(null);
  }

  @override
  Future<VenteResult<Never>> netVnoRemise(String venteId, String? remiseId) => throw UnimplementedError('jamais pour assurance / carnet');
}

class _Adaptateur implements HttpClientAdapter {
  ResponseBody Function(RequestOptions o) repondre;
  int appels = 0;
  _Adaptateur(this.repondre);
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    appels++;
    return repondre(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object corps, [int statut = 200]) =>
    ResponseBody.fromString(jsonEncode(corps), statut, headers: {Headers.contentTypeHeader: ['application/json']});

ResponseBody _images(RequestOptions o, {int n = 1}) {
  final p = o.queryParameters['largeur'] == 58 ? 384 : 576;
  return _json({
    'success': true,
    'largeur': p == 384 ? 58 : 80,
    'tickets': [for (var i = 0; i < n; i++) {'modele': 'VENTE_ASSURANCE', 'png': base64Encode(RemisesFictives.pngFictif(p, 30)), 'largeurPoints': p, 'hauteurPoints': 30}],
  });
}

late _Adaptateur _adaptateur;
final List<int> _imprimees = [];
String? _echecImprimante;

Future<void> _monter(WidgetTester t, Future<void> Function(BuildContext c) action) async {
  t.view.physicalSize = const Size(720, 1440);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Builder(builder: (c) => Scaffold(body: Center(child: ElevatedButton(onPressed: () => action(c), child: const Text('IMPRIMER'))))),
  ));
  await t.tap(find.text('IMPRIMER'));
  await t.pumpAndSettle();
}

Future<void> _assurance(BuildContext c, {int copies = 1, bool apercu = false}) => imprimerCopiesAvecPause(
    c,
    copies,
    () => ReceiptService().printAssuranceSaleTicket(
          context: c,
          officine: officineTicket,
          saleSummary: ticketAssuranceResume,
          items: lignesTicket,
          client: clientTicket,
          ayantDroit: ayantDroitTicket,
          paymentMethod: PaymentMethod(id: '1', name: 'ESPECES'),
          currentUser: vendeurTicket,
          isTestMode: apercu,
          paperWidth: 58,
          ticketCodeType: 'QR_CODE',
          confirmEachCopy: false,
        ));

void main() {
  setUp(() {
    DroitsVente.instance.fixer(null);
    DroitsVente.instance.oublierControles();
    TicketServeur.oublier();
    ImpressionTicket.reinitialiser();
    _imprimees.clear();
    _echecImprimante = null;
    _adaptateur = _Adaptateur((o) => _json({'success': false}, 404));
    ImpressionTicket.dioDe = (_) => Dio(BaseOptions(baseUrl: 'http://serveur-fictif/prestige/api/v1'))..httpClientAdapter = _adaptateur;
    ImpressionTicket.imprimeur = (tickets) async {
      if (_echecImprimante != null) return _echecImprimante;
      _imprimees.add(tickets.length);
      return null;
    };
  });

  group('Remise assurance / carnet (net/assurance lit la remise de la vente, sinon celle du client)', () {
    test('choisir : POST remise puis net relu ; retirer avec une remise sur la fiche du client : celle-ci revient', () async {
      final gw = _GwVo()..remiseClient = 'REM-CLIENT';
      final c = _VoFictif(gw);
      expect(c.remiseDisponible, isTrue);
      expect((await c.choisirRemise(const RemiseOption(id: 'REM-FICT-10', nom: 'REMISE FICTIVE 10 %'))).isOk, isTrue);
      expect(gw.poses, ['REM-FICT-10']);
      expect(c.remiseId, 'REM-FICT-10');
      expect(c.remiseNom, 'REMISE FICTIVE 10 %');
      expect(c.nets, 1);
      expect((await c.retirerRemise()).isOk, isTrue);
      expect(gw.poses.last, isNull);
      expect(c.remiseId, isNull);
      expect(c.montantRemise, 500, reason: 'remise de la fiche du client, appliquée par le serveur');
    });

    test('hors ligne, vente terminée, sans vente : pas proposée, refus clair, rien envoyé', () async {
      final gw = _GwVo();
      final c = _VoFictif(gw)..horsLigne = true;
      expect(c.remiseDisponible, isFalse);
      expect((await c.remisesProposees()).message, contains('hors ligne'));
      expect((await c.choisirRemise(const RemiseOption(id: 'R', nom: 'R'))).isOk, isFalse);
      c
        ..horsLigne = false
        ..fini = true;
      expect(c.remiseDisponible, isFalse);
      c
        ..fini = false
        ..venteId = null;
      expect(c.remiseDisponible, isFalse);
      expect(gw.poses, isEmpty);
    });

    test('refus et 403 : état gardé ; 403 masque la remise pour la session', () async {
      final gw = _GwVo()..reponse = const VenteRefused('Erreur::: L\'Opération n\'a pas aboutie');
      final c = _VoFictif(gw);
      expect((await c.choisirRemise(const RemiseOption(id: 'R', nom: 'R'))).message, 'Erreur::: L\'Opération n\'a pas aboutie');
      expect(c.remiseId, isNull);
      gw.reponse = const VenteRefused('Accès refusé.', code: VenteRefused.codeInterdit);
      await c.choisirRemise(const RemiseOption(id: 'R', nom: 'R'));
      expect(c.remiseDisponible, isFalse);
    });

    test('remise relue avec la vente (lgREMISEID) ; nom retrouvé dans la liste', () async {
      final c = _VoFictif(_GwVo());
      c.lireRemiseDe({'lgREMISEID': 'REM-FICT-10'});
      expect(c.remiseId, 'REM-FICT-10');
      expect(c.remiseNom, isNull);
      await c.remisesProposees();
      expect(c.remiseNom, 'REMISE FICTIVE 10 %');
      c.lireRemiseDe({'lgREMISEID': null});
      expect(c.remiseId, isNull);
    });
  });

  group('Ticket du serveur (route image) avant le gabarit local', () {
    testWidgets('route absente (404) : gabarit local (aperçu « VENTE ASSURANCE »), plus de nouvel appel ensuite', (t) async {
      await _monter(t, (c) => _assurance(c, apercu: true));
      expect(find.text('Aperçu du Ticket'), findsOneWidget);
      expect(find.text('VENTE ASSURANCE'), findsOneWidget);
      await t.tap(find.text('Fermer'));
      await t.pumpAndSettle();
      expect(_adaptateur.appels, 1);
      await t.tap(find.text('IMPRIMER'));
      await t.pumpAndSettle();
      expect(_adaptateur.appels, 1, reason: 'route absente gardée en mémoire');
    });

    // 5.4.0 (régression 4.14.0, retour du pharmacien) : la route image rend UN exemplaire (réimpression du poste) ;
    // le nombre de copies choisi sur l'appareil est respecté, avec la pause « Ticket suivant (i/N) ».
    testWidgets('route présente : images imprimées telles quelles, UN exemplaire par copie, pause avant chaque copie suivante', (t) async {
      _adaptateur.repondre = (o) => _images(o, n: 2);
      await _monter(t, (c) => _assurance(c, copies: 3));
      expect(_imprimees, [2], reason: 'copie 1 : les deux tickets de la vente rendus par le serveur');
      expect(find.text('Ticket suivant (2/3)'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('ticket-suivant-imprimer')));
      await t.pumpAndSettle();
      expect(_imprimees, [2, 2]);
      expect(find.text('Ticket suivant (3/3)'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('ticket-suivant-imprimer')));
      await t.pumpAndSettle();
      expect(_imprimees, [2, 2, 2]);
      expect(find.byKey(const ValueKey('ticket-suivant')), findsNothing);
      expect(ImpressionTicket.imagesImprimees, 6);
      expect(_adaptateur.appels, 3, reason: 'chaque copie redemande le ticket au serveur');
    });

    testWidgets('mode test d\'impression : aperçu des images du serveur', (t) async {
      _adaptateur.repondre = (o) => _images(o);
      await _monter(t, (c) => _assurance(c, apercu: true));
      expect(find.byKey(const ValueKey('ticket-serveur-apercu')), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('échec de l\'imprimante (Bluetooth coupé) : motif, vente intacte, « Réimprimer » rappelle la route', (t) async {
      _adaptateur.repondre = (o) => _images(o);
      _echecImprimante = 'imprimante Bluetooth déconnectée.';
      await _monter(t, (c) => _assurance(c));
      expect(find.byKey(const ValueKey('ticket-non-imprime')), findsOneWidget);
      expect(find.textContaining('imprimante Bluetooth déconnectée.'), findsOneWidget);
      expect(find.textContaining('La vente est enregistrée'), findsOneWidget);
      _echecImprimante = null;
      await t.tap(find.byKey(const ValueKey('ticket-reimprimer')));
      await t.pumpAndSettle();
      expect(_adaptateur.appels, 2);
      expect(_imprimees, [1]);
      expect(find.byKey(const ValueKey('ticket-non-imprime')), findsNothing);
    });

    testWidgets('réseau coupé après une première image : « Ticket non imprimé : réseau indisponible », pas de ticket recomposé', (t) async {
      _adaptateur.repondre = (o) => _images(o);
      await _monter(t, (c) => _assurance(c));
      expect(_imprimees, [1]);
      _adaptateur.repondre = (o) => throw DioException.connectionError(requestOptions: o, reason: 'coupé');
      await t.tap(find.text('IMPRIMER'));
      await t.pumpAndSettle();
      expect(find.textContaining(TicketServeur.messageReseau), findsOneWidget);
      expect(find.text('Aperçu du Ticket'), findsNothing);
      // Retour du réseau : « Réimprimer ».
      _adaptateur.repondre = (o) => _images(o);
      await t.tap(find.byKey(const ValueKey('ticket-reimprimer')));
      await t.pumpAndSettle();
      expect(_imprimees, [1, 1]);
    });

    testWidgets('réseau coupé, route jamais vue : gabarit local comme avant', (t) async {
      _adaptateur.repondre = (o) => throw DioException.connectionError(requestOptions: o, reason: 'coupé');
      await _monter(t, (c) => _assurance(c, apercu: true));
      expect(find.text('Aperçu du Ticket'), findsOneWidget);
    });

    testWidgets('refus du serveur (vente introuvable) : gabarit local', (t) async {
      _adaptateur.repondre = (o) => _json({'success': false, 'msg': 'Vente introuvable'});
      await _monter(t, (c) => _assurance(c, apercu: true));
      expect(find.text('Aperçu du Ticket'), findsOneWidget);
    });
  });
}
