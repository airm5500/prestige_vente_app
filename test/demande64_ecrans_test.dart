// ÉCRANS — 4.15.2 : demande 64 (branche serveur correctif/demande64-1911, d6cf51fa5), faux services, données FICTIVES.
//  Borne :
//   - caisse de la borne fermée (refus « Paiement mobile money impossible ») : AUCUN QR, aucun suivi, ticket de
//     PRÉVENTE imprimé (vente gardée), avis « payez à la caisse », une seule demande (cloturer:true) ;
//   - serveur déployé (sans la demande 64) : paiement, ticket « PAYÉE » à terminer en caisse (inchangé) ;
//   - panne réseau à la création : écran d'erreur d'avant (« PAYER EN CAISSE » / « ABANDONNER »), aucun repli.
//  Comptoir, nouvelle interface (panier, remise) et ancienne interface : chaque modification refusée affiche le `msg`
//  du serveur TEL QUEL (payé et en cours), le panier affiché reste celui du serveur (rien d'ajouté ni de retiré).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_kiosque.dart';
import 'package:prestige_vente_app/borne/borne_screen.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/screens/pre_vente/widgets/sale_cart_widget.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/common/remise_vente.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_cart.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/demande64_fictive.dart';

// -----------------------------------------------------------------------------
// Borne
// -----------------------------------------------------------------------------

/// Faux module de paiement : règles des branches 62 et 64 (caisse de la borne ouverte ou non).
class PmBorne64 implements PaiementsMobileApi {
  PmBorne64({this.d64 = true, this.caisseOuverte = false, this.panne = false});
  bool d64;
  bool caisseOuverte;
  bool panne;
  final List<bool> cloturers = [];
  int statuts = 0;
  bool _cree = false;

  @override
  Future<VenteResult<CapacitesPM>> capacites() async => const VenteOk(CapacitesPM(operateurs: ['wave', 'orange'], fournisseur: 'simulateur'));

  @override
  Future<VenteResult<PaiementMobile>> creer({required String venteId, required String operateur, int? part, bool cloturer = false, required String cle}) async {
    cloturers.add(cloturer);
    if (panne) return const VenteFailed('Paiement : serveur injoignable (connectionError).');
    if (d64 && cloturer && part == null && !caisseOuverte) return const VenteRefused(messageCaisseFermee);
    _cree = true;
    return VenteOk(PaiementMobile(id: 'PM1', venteId: venteId, montant: 3000, operateur: operateur, statut: StatutPM.enAttente, clotureAuto: cloturer, lien: 'simulateur://PM1'));
  }

  @override
  Future<VenteResult<PaiementMobile>> statut(String id) async {
    statuts++;
    return VenteOk(PaiementMobile(
        id: 'PM1',
        venteId: 'V1',
        montant: 3000,
        operateur: 'wave',
        statut: _cree ? StatutPM.paye : StatutPM.enAttente,
        clotureAuto: true,
        cloture: _cree && caisseOuverte,
        message: _cree && !caisseOuverte ? 'Clôture refusée : Votre caisse est fermée' : ''));
  }

  @override
  Future<VenteResult<PaiementMobile>> annuler(String id) => statut(id);
  @override
  Future<VenteResult<List<PaiementMobile>>> historique(DateTime jour) async => const VenteOk([]);
}

class BorneGw64 implements VenteGateway {
  int terminees = 0;
  final produits = [
    ProductSearchResult(lgFAMILLEID: 'P1', strNAME: 'PRODUIT FICTIF 500MG CPR', intCIP: '1P1', intPRICE: 3000, intNUMBERAVAILABLE: 10, strLIBELLEE: '', intPAF: 0)
  ];
  @override
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async => VenteOk(ProductPage(produits, produits.length));
  @override
  Future<VenteResult<String>> addItemVno({required String produitId, required int qte, required int itemPu, String? venteId, required bool prevente}) async =>
      const VenteOk('V1');
  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) async => VenteOk(SaleSummary(montant: 3000, montantNet: 3000, reference: '261119_00064', venteId: 'V1'));
  @override
  Future<VenteResult<void>> terminerPrevente(String venteId) async {
    terminees++;
    return const VenteOk(null);
  }

  @override
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async => VenteOk([
        SaleItemDetail(
            lgPREENREGISTREMENTDETAILID: 'D1', lgFAMILLEID: 'P1', strNAME: 'PRODUIT FICTIF 500MG CPR', intCIP: '1P1', intQUANTITY: 1, intPRICEUNITAIR: 3000, intPRICE: 3000, strREF: '261119_00064')
      ]);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class ImpBorne64 implements BorneImprimante {
  final tickets = <BorneTicket>[];
  @override
  Future<bool> imprimer(BorneTicket t) async {
    tickets.add(t);
    return true;
  }
}

Future<void> avancer64(WidgetTester t, Duration d) async {
  const pas = Duration(milliseconds: 250);
  for (var x = Duration.zero; x < d; x += pas) {
    await t.pump(pas);
  }
}

/// Borne au panier (1 produit) ; [payer] : « PAYER PAR MOBILE MONEY » puis Wave. Taille de l'écran : [taille] (dp).
Future<(BorneGw64, ImpBorne64)> borne64(WidgetTester t, PmBorne64 pm, {Size taille = const Size(360, 760), bool payer = true}) async {
  t.view.physicalSize = taille * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  PaiementsMobileReglages.actif.value = true;
  addTearDown(() => PaiementsMobileReglages.actif.value = false);
  BorneKiosque.instance = KiosqueSimule();
  final gw = BorneGw64();
  final imp = ImpBorne64();
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: BorneScreen(
      service: BorneService(gw),
      config: const BorneConfig(actif: true, login: 'borne.fictive'),
      monitor: ServerMonitor(),
      imprimante: imp,
      kiosque: KiosqueSimule(),
      adminCheck: (_) async => true,
      onSortie: (_) {},
      paiementsMobile: PaiementsMobile(api: pm),
    ),
  ));
  await t.pump();
  await t.pump();
  await t.enterText(find.byKey(const ValueKey('borne-recherche')), 'prod');
  await t.pump(const Duration(milliseconds: 450));
  await t.pump();
  await t.pump();
  await t.tap(find.byKey(const ValueKey('borne-ajouter-P1')));
  await t.pump();
  // Panier : bouton « voir le panier » (téléphone, tablette portrait) ou « PAYER » du panier latéral (≥ 900 dp).
  final voir = find.byKey(const ValueKey('borne-voir-panier'));
  final lateral = find.byKey(const ValueKey('borne-panier-lateral-payer'));
  if (voir.evaluate().isNotEmpty) {
    await t.tap(voir);
    await t.pump();
  } else if (lateral.evaluate().isNotEmpty) {
    await t.tap(lateral);
    await t.pump();
  }
  if (!payer) return (gw, imp);
  final mobile = find.byKey(const ValueKey('borne-payer-mobile'));
  expect(mobile, findsOneWidget);
  await t.ensureVisible(mobile);
  await t.pump();
  await t.tap(mobile);
  await t.pump();
  await t.tap(find.byKey(const ValueKey('borne-operateur-wave')));
  await t.pump();
  return (gw, imp);
}

Future<void> fin64(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

// -----------------------------------------------------------------------------
// Comptoir
// -----------------------------------------------------------------------------

/// Passerelle fictive d'une prévente verrouillée (payée ou paiement en cours) : toute modification est refusée avec le
/// `msg` du serveur, rien n'est écrit ; le panier relu reste le même.
class GwVerrou64 implements VenteGateway, RemiseVenteGateway {
  GwVerrou64(this.message);
  String? message;
  int relectures = 0;
  final List<String> appels = [];
  List<SaleItemDetail> lignes = [
    SaleItemDetail(
        lgPREENREGISTREMENTDETAILID: 'D1', lgFAMILLEID: 'P1', strNAME: 'PRODUIT FICTIF 1000MG CPR B/8', intCIP: '1', intQUANTITY: 3, intPRICEUNITAIR: 1375, intPRICE: 4125, strREF: 'REF-FICT-64')
  ];

  VenteResult<T> _refus<T>(String route, T ok) {
    appels.add(route);
    final m = message;
    return m == null ? VenteOk(ok) : VenteRefused(m);
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId) async => const VenteOk({'strSTATUT': 'is_Process', 'lgTYPEVENTEID': '1'});
  @override
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async {
    relectures++;
    return VenteOk(List.of(lignes));
  }

  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) async =>
      VenteOk(SaleSummary(montant: lignes.fold(0, (a, l) => a + l.intPRICE), montantNet: lignes.fold(0, (a, l) => a + l.intPRICE), reference: 'REF-FICT-64', venteId: venteId));
  @override
  Future<VenteResult<SaleSummary>> netVnoRemise(String venteId, String? remiseId) => netVno(venteId);
  @override
  Future<VenteResult<String>> addItemVno({required String produitId, required int qte, required int itemPu, String? venteId, required bool prevente}) async =>
      _refus('add/item', venteId ?? 'V-FICT-64');
  @override
  Future<VenteResult<void>> updateItem({required String itemId, required String produitId, required int qte, required int itemPu}) async => _refus('update/item/vno', null);
  @override
  Future<VenteResult<void>> removeItem(String itemId) async => _refus('remove/vno/item', null);
  @override
  Future<VenteResult<List<RemiseOption>>> remisesVente() async => const VenteOk([RemiseOption(id: 'R10', nom: 'Remise fictive 10 %')]);
  @override
  Future<VenteResult<void>> appliquerRemise(String venteId, String? remiseId) async => _refus('remise', null);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Future<T> regler64<T>(WidgetTester t, Future<T> f) async {
  var fini = false;
  late T v;
  f.then((x) {
    v = x;
    fini = true;
  });
  for (var i = 0; i < 200 && !fini; i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(fini, isTrue);
  return v;
}

/// Panier du comptoir (nouvelle interface) d'une prévente reprise.
Future<VenteController> panier64(WidgetTester t, GwVerrou64 gw, {Size taille = const Size(360, 760), double texte = 1}) async {
  t.view.physicalSize = taille * 2;
  t.view.devicePixelRatio = 2;
  t.platformDispatcher.textScaleFactorTestValue = texte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({});
  final c = VenteController(gateway: gw);
  await regler64(t, c.loadVente('V-FICT-64'));
  await t.pumpWidget(ChangeNotifierProvider<VenteController>.value(
    value: c,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Prévente fictive')),
        body: Builder(builder: (ctx) {
          return Column(children: [
            const Expanded(child: VenteCart()),
            Padding(
              padding: const EdgeInsets.all(8),
              child: ElevatedButton(
                key: const ValueKey('test-ajouter'),
                onPressed: () async {
                  final r = await c.addProduct(
                      ProductSearchResult(lgFAMILLEID: 'P2', strNAME: 'PRODUIT FICTIF 2', intCIP: '2', intPRICE: 500, intNUMBERAVAILABLE: 9, strLIBELLEE: '', intPAF: 0), 1);
                  if (!r.isOk && ctx.mounted) showVenteFailure(ctx, r);
                },
                child: const Text('Ajouter'),
              ),
            ),
          ]);
        }),
      ),
    ),
  ));
  await t.pump();
  return c;
}

List<(String, int)> etat64(VenteController c) => [for (final i in c.items) (i.lgPREENREGISTREMENTDETAILID, i.intQUANTITY)];

String snack64(WidgetTester t) {
  final s = t.widget<SnackBar>(find.byType(SnackBar));
  return (s.content as Text).data!;
}

Future<void> modifierLigne64(WidgetTester t, String qte) async {
  await t.tap(find.byTooltip('Modifier').first);
  await t.pumpAndSettle();
  await t.enterText(find.descendant(of: find.byKey(const ValueKey('ligne-dialogue')), matching: find.byType(TextFormField)).first, qte);
  await t.tap(find.text('Valider'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> supprimerLigne64(WidgetTester t) async {
  await t.tap(find.byTooltip('Supprimer').first);
  await t.pumpAndSettle();
  await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Supprimer')));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

// -----------------------------------------------------------------------------
// Ancienne interface : ApiService fictif (lignes en mémoire, refus du serveur rendu par prendreRefusPanier)
// -----------------------------------------------------------------------------

class ApiAncienne64 extends ApiService {
  ApiAncienne64(this.message) : super(baseUrl: 'http://localhost');
  String? message;
  String? _dernier;
  final List<SaleItemDetail> lignes = [
    SaleItemDetail(
        lgPREENREGISTREMENTDETAILID: 'D1', lgFAMILLEID: 'P1', strNAME: 'PRODUIT FICTIF 1000MG CPR B/8', intCIP: '1', intQUANTITY: 3, intPRICEUNITAIR: 1375, intPRICE: 4125, strREF: 'REF-FICT-64')
  ];

  @override
  String? prendreRefusPanier() {
    final m = _dernier;
    _dernier = null;
    return m;
  }

  bool _refuser() {
    _dernier = message;
    return message != null;
  }

  @override
  Future<String?> addItemToSale({required String produitId, required int qte, required int itemPu, String? venteId, bool isPrevente = false}) async =>
      _refuser() ? null : venteId;
  @override
  Future<bool> updateSaleItem({required String itemId, required String produitId, required int qte, required int itemPu}) async => !_refuser();
  @override
  Future<bool> removeItemFromSale(String itemId) async => !_refuser();
  @override
  Future<List<SaleItemDetail>> getSaleDetails(String venteId) async => List.of(lignes);
  @override
  Future<SaleSummary?> calculateNet(String venteId) async => SaleSummary(montant: 4125, montantNet: 4125, reference: 'REF-FICT-64', venteId: venteId);
}

void main() {
  setUp(() => DroitsVente.instance.oublier());
  tearDown(() => DroitsVente.instance.oublier());

  group('Borne : refus du serveur avant paiement (point 1)', () {
    testWidgets('caisse de la borne fermée : aucun QR, ticket de prévente, « payez à la caisse », une seule demande', (t) async {
      DroitsVente.instance.fixer({'P_SM_VENTE', DroitsVente.bornePaiementMobileDroit}, utilisateur: 'U-borne.fictive');
      final pm = PmBorne64();
      final (gw, imp) = await borne64(t, pm);
      await avancer64(t, const Duration(seconds: 1));
      expect(pm.cloturers, [true], reason: 'jamais de demande cloturer:false');
      expect(find.byKey(const ValueKey('pm-qr')), findsNothing);
      expect(find.byKey(const ValueKey('borne-avis-ticket')), findsOneWidget);
      expect(find.text(BorneScreen.avisMobileIndisponible), findsOneWidget);
      expect(find.textContaining('Paiement mobile money impossible'), findsNothing, reason: 'motif destiné à l\'équipe, pas au client');
      expect(gw.terminees, 1, reason: 'prévente validée, panier gardé sur le serveur');
      expect(imp.tickets.single.paye, isFalse, reason: 'ticket de PRÉVENTE pour la caisse');
      expect(find.byKey(const ValueKey('borne-numero')), findsOneWidget);
      await avancer64(t, const Duration(seconds: 6));
      expect((pm.cloturers.length, pm.statuts), (1, 0), reason: 'aucune nouvelle tentative, aucun paiement à suivre');
      expect(t.takeException(), isNull);
      await fin64(t);
    });

    testWidgets('caisse ouverte : paiement, vente terminée par le serveur (inchangé)', (t) async {
      DroitsVente.instance.fixer({'P_SM_VENTE', DroitsVente.bornePaiementMobileDroit}, utilisateur: 'U-borne.fictive');
      final pm = PmBorne64(caisseOuverte: true);
      final (_, imp) = await borne64(t, pm);
      await avancer64(t, const Duration(seconds: 6));
      expect(pm.cloturers, [true]);
      expect((imp.tickets.single.paye, imp.tickets.single.aTerminer), (true, false));
      await fin64(t);
    });

    testWidgets('serveur déployé (sans la demande 64), caisse fermée : payé, ticket « PAYÉE » à terminer en caisse (comme 4.15.1)', (t) async {
      DroitsVente.instance.fixer({'P_SM_VENTE', DroitsVente.bornePaiementMobileDroit}, utilisateur: 'U-borne.fictive');
      final pm = PmBorne64(d64: false);
      final (_, imp) = await borne64(t, pm);
      await avancer64(t, const Duration(seconds: 6));
      expect(pm.cloturers, [true]);
      expect((imp.tickets.single.paye, imp.tickets.single.aTerminer), (true, true));
      expect(find.byKey(const ValueKey('borne-avis-ticket')), findsNothing);
      await fin64(t);
    });

    testWidgets('panne réseau à la création : écran d\'erreur d\'avant (payer en caisse / abandonner), aucun repli', (t) async {
      DroitsVente.instance.fixer({'P_SM_CLOTURER_CAISSE'}, utilisateur: 'U-borne.fictive');
      final pm = PmBorne64(panne: true);
      final (_, imp) = await borne64(t, pm);
      await avancer64(t, const Duration(seconds: 1));
      expect(pm.cloturers, [true]);
      expect(find.byKey(const ValueKey('borne-mobile-caisse')), findsOneWidget);
      expect(find.byKey(const ValueKey('pm-erreur')), findsOneWidget);
      expect(find.byKey(const ValueKey('pm-qr')), findsNothing);
      expect(imp.tickets, isEmpty);
      await t.tap(find.byKey(const ValueKey('borne-mobile-caisse')));
      await t.pump();
      await t.pump();
      expect(imp.tickets.single.paye, isFalse);
      expect(pm.cloturers, [true]);
      await fin64(t);
    });
  });

  group('Comptoir, nouvelle interface : panier verrouillé (point 2)', () {
    for (final (cas, message) in [('payée', messagePayeWave4125), ('paiement en cours', messageEnCoursOrange4125)]) {
      testWidgets('prévente $cas : quantité, retrait, ajout refusés, message tel quel (8 s), panier inchangé', (t) async {
        final gw = GwVerrou64(message);
        final c = await panier64(t, gw);
        final avant = etat64(c);
        final net = c.summary.montantNet;
        final ch = c.changes;
        await modifierLigne64(t, '1');
        expect(snack64(t), message);
        expect(t.widget<SnackBar>(find.byType(SnackBar)).duration, dureeMessageVerrou);
        expect(etat64(c), avant);
        expect(c.summary.montantNet, net);
        expect(find.text('3 × ${Constants.formatNumber(1375)} F'), findsOneWidget, reason: 'quantité affichée : celle du serveur');
        ScaffoldMessenger.of(t.element(find.byType(VenteCart))).removeCurrentSnackBar();
        await t.pump();
        await supprimerLigne64(t);
        expect(snack64(t), message);
        expect(etat64(c), avant, reason: 'la ligne n\'est pas retirée');
        ScaffoldMessenger.of(t.element(find.byType(VenteCart))).removeCurrentSnackBar();
        await t.pump();
        await t.tap(find.byKey(const ValueKey('test-ajouter')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(snack64(t), message);
        expect(etat64(c), avant, reason: 'rien d\'ajouté');
        expect(find.text('PRODUIT FICTIF 2'), findsNothing);
        expect(gw.appels, ['update/item/vno', 'remove/vno/item', 'add/item']);
        expect(c.changes, ch, reason: 'aucune modification notée : l\'encaissement reste possible tel quel');
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('remise refusée (payée puis en cours) : message tel quel, remise inchangée', (t) async {
      DroitsVente.instance.fixer({'P_SM_VENTE', 'P_SM_CLOTURER_CAISSE', droitRemiseVente}, utilisateur: 'U-FICT');
      for (final message in [messagePayeWave4125, messageEnCoursOrange4125]) {
        final gw = GwVerrou64(message);
        final c = await panier64(t, gw);
        final ch = c.changes;
        final r = await regler64(t, c.choisirRemise(const RemiseOption(id: 'R10', nom: 'Remise fictive 10 %')));
        expect(r.message, message);
        expect((r as VenteRefused).panierVerrouille, isTrue);
        expect((c.remiseId, c.changes), (null, ch));
        expect(etat64(c), [('D1', 3)]);
        final r2 = await regler64(t, c.retirerRemise());
        expect(r2.message, message);
      }
    });

    testWidgets('vente non verrouillée (serveur déployé) : quantité modifiée et relue comme en 4.15.1', (t) async {
      final gw = GwVerrou64(null);
      final c = await panier64(t, gw);
      final ch = c.changes;
      gw.lignes = [
        SaleItemDetail(
            lgPREENREGISTREMENTDETAILID: 'D1', lgFAMILLEID: 'P1', strNAME: 'PRODUIT FICTIF 1000MG CPR B/8', intCIP: '1', intQUANTITY: 1, intPRICEUNITAIR: 1375, intPRICE: 1375, strREF: 'REF-FICT-64')
      ];
      await modifierLigne64(t, '1');
      await t.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(etat64(c), [('D1', 1)]);
      expect(c.changes, ch + 1);
    });
  });

  group('Comptoir, ancienne interface (réglage « Ventes : ancienne version »)', () {
    for (final (cas, message) in [('payée', messagePayeWave4125), ('paiement en cours', messageEnCoursOrange4125)]) {
      testWidgets('prévente $cas : quantité et retrait refusés, message tel quel, panier inchangé', (t) async {
        t.view.physicalSize = const Size(720, 1520);
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        SharedPreferences.setMockInitialValues({});
        final api = ApiAncienne64(message);
        final sp = SaleProvider(api);
        await regler64(t, sp.loadPrevente('V-FICT-64'));
        await t.pumpWidget(ChangeNotifierProvider<SaleProvider>.value(
          value: sp,
          child: const MaterialApp(home: Scaffold(body: SaleCartWidget())),
        ));
        await t.pump();
        expect(find.text('3 x ${Constants.formatNumber(1375)}'), findsOneWidget);
        await t.tap(find.byTooltip('Modifier'));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField).first, '1');
        await t.tap(find.text('Valider'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const Key('vente_refus_panier')), findsOneWidget);
        expect(snack64(t), message);
        expect(find.text('3 x ${Constants.formatNumber(1375)}'), findsOneWidget, reason: 'quantité du serveur');
        ScaffoldMessenger.of(t.element(find.byType(SaleCartWidget))).removeCurrentSnackBar();
        await t.pump();
        await t.tap(find.byTooltip('Supprimer'));
        await t.pumpAndSettle();
        await t.tap(find.text('Oui'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(snack64(t), message);
        expect(sp.cartItems, hasLength(1), reason: 'ligne gardée');
        expect(await regler64(t, sp.addProductToCart(
            ProductSearchResult(lgFAMILLEID: 'P2', strNAME: 'PRODUIT FICTIF 2', intCIP: '2', intPRICE: 500, intNUMBERAVAILABLE: 9, strLIBELLEE: '', intPAF: 0), 1)), message);
        expect(sp.cartItems, hasLength(1));
        expect(t.takeException(), isNull);
        sp.dispose();
      });
    }
  });
}
