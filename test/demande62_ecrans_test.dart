// ÉCRANS — 4.15.0 : demande 62 (branche serveur correctif/demande62-1911, fb0a3cc2), faux services, données FICTIVES.
//  Borne (point 3a) :
//   - cas du pharmacien : compte borne avec le seul droit P_BORNE_PAIEMENT_MOBILE, caisse ouverte → cloturer:true,
//     vente terminée par le serveur (ticket « payée », sans « présentez ce ticket à la caisse ») ;
//   - même droit, AUCUNE caisse ouverte pour le compte de la borne → payé mais pas clôturé (`cloture:false`) : ticket
//     « PAYÉE, présentez ce ticket à la caisse » ;
//   - 403 interdit à cloturer:true avec le droit (droit retiré entre-temps) → une nouvelle demande cloturer:false ;
//   - serveur d'aujourd'hui (droit inconnu, compte prévente) : cloturer:false, comme 4.13.1.
//  Comptoir (point 3b) :
//   - prévente payée reprise : bandeau, mode de l'opérateur imposé (même non activé sur l'appareil), montant reçu =
//     montant payé non modifiable, « TERMINER LA VENTE » sans saisie d'argent, clôture avec ce règlement ;
//   - net augmenté : complément dans un autre mode ; net diminué : bloqué avec le motif ;
//   - refus du serveur `{success:false, paiementMobile:true, msg}` : message affiché tel quel, vente gardée ;
//   - liste des préventes : « Payée Wave … » à la place de « À encaisser » ;
//   - page d'origine sans le champ (serveur d'aujourd'hui).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
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
import 'package:prestige_vente_app/paiements/prevente_payee.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/ventes/common/remise_vente.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/encaissement_page.dart';
import 'package:prestige_vente_app/ventes/prevente/prevente_list.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'demande62_test.dart' show venteFictivePayee;

// -----------------------------------------------------------------------------
// Borne
// -----------------------------------------------------------------------------

/// Faux module de paiement avec les règles de la branche de la demande 62 (PaiementsMobileRessource / Service).
class _Pm implements PaiementsMobileApi {
  _Pm({required this.droits, this.caisseOuverte = true, this.d62 = true});
  Set<String> droits;
  bool caisseOuverte;
  bool d62;
  bool payer = true;
  final List<bool> cloturers = [];
  final Set<String> cles = {};
  bool _auto = false;

  @override
  Future<VenteResult<CapacitesPM>> capacites() async => const VenteOk(CapacitesPM(operateurs: ['wave'], fournisseur: 'simulateur'));

  @override
  Future<VenteResult<PaiementMobile>> creer({required String venteId, required String operateur, int? part, bool cloturer = false, required String cle}) async {
    cloturers.add(cloturer);
    cles.add(cle);
    if (cloturer && !droits.any(DroitsVente.terminerVenteDroits.contains) && !(d62 && droits.contains(DroitsVente.bornePaiementMobileDroit))) {
      return const VenteRefused('Droit manquant (fictif).', code: VenteRefused.codeInterdit);
    }
    _auto = cloturer;
    return VenteOk(PaiementMobile(id: 'PM1', venteId: venteId, montant: 3000, operateur: operateur, statut: StatutPM.enAttente, clotureAuto: cloturer));
  }

  @override
  Future<VenteResult<PaiementMobile>> statut(String id) async {
    final paye = payer;
    final cloture = paye && _auto && caisseOuverte;
    return VenteOk(PaiementMobile(
        id: 'PM1',
        venteId: 'V1',
        montant: 3000,
        operateur: 'wave',
        statut: paye ? StatutPM.paye : StatutPM.enAttente,
        clotureAuto: _auto,
        cloture: cloture,
        message: paye && _auto && !caisseOuverte ? 'Clôture refusée : Votre caisse est fermée' : ''));
  }

  @override
  Future<VenteResult<PaiementMobile>> annuler(String id) => statut(id);
  @override
  Future<VenteResult<List<PaiementMobile>>> historique(DateTime jour) async => const VenteOk([]);
}

class _BorneGw implements VenteGateway {
  final produits = [
    ProductSearchResult(lgFAMILLEID: 'P1', strNAME: 'PRODUIT FICTIF 500MG CPR', intCIP: '1P1', intPRICE: 3000, intNUMBERAVAILABLE: 10, strLIBELLEE: '', intPAF: 0)
  ];
  @override
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async => VenteOk(ProductPage(produits, produits.length));
  @override
  Future<VenteResult<String>> addItemVno({required String produitId, required int qte, required int itemPu, String? venteId, required bool prevente}) async =>
      const VenteOk('V1');
  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) async => VenteOk(SaleSummary(montant: 3000, montantNet: 3000, reference: '261119_00042', venteId: 'V1'));
  @override
  Future<VenteResult<void>> terminerPrevente(String venteId) async => const VenteOk(null);
  @override
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async => VenteOk([
        SaleItemDetail(
            lgPREENREGISTREMENTDETAILID: 'D1', lgFAMILLEID: 'P1', strNAME: 'PRODUIT FICTIF 500MG CPR', intCIP: '1P1', intQUANTITY: 1, intPRICEUNITAIR: 3000, intPRICE: 3000, strREF: '261119_00042')
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

Future<void> _avancer(WidgetTester t, Duration d) async {
  const pas = Duration(milliseconds: 250);
  for (var x = Duration.zero; x < d; x += pas) {
    await t.pump(pas);
  }
}

/// Borne au panier (1 produit), puis paiement Wave ; renvoie les tickets imprimés.
Future<_Imp> _payerALaBorne(WidgetTester t, _Pm pm) async {
  t.view.physicalSize = const Size(720, 1520);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  PaiementsMobileReglages.actif.value = true;
  addTearDown(() => PaiementsMobileReglages.actif.value = false);
  BorneKiosque.instance = KiosqueSimule();
  final imp = _Imp();
  await t.pumpWidget(MaterialApp(
    home: BorneScreen(
      service: BorneService(_BorneGw()),
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
  await t.tap(find.byKey(const ValueKey('borne-voir-panier')));
  await t.pump();
  expect(find.byKey(const ValueKey('remise-vente-zone')), findsNothing, reason: 'la borne ne propose jamais de remise');
  final mobile = find.byKey(const ValueKey('borne-payer-mobile'));
  expect(mobile, findsOneWidget);
  await t.ensureVisible(mobile);
  await t.pump();
  await t.tap(mobile);
  await t.pump();
  await t.tap(find.byKey(const ValueKey('borne-operateur-wave')));
  await _avancer(t, const Duration(seconds: 6));
  return imp;
}

Future<void> _fin(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

String _invitationEcran(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('borne-ticket-invitation'))).data!;

// -----------------------------------------------------------------------------
// Comptoir
// -----------------------------------------------------------------------------

/// Passerelle fictive d'une prévente comptant (relue avec ventestats/{id}) ; clôture selon la règle du serveur.
class _Gw implements VenteGateway, RemiseVenteGateway {
  _Gw({this.vente, this.net = 4125});
  Map<String, dynamic>? vente;
  int net;
  final List<Map<String, Object?>> clotures = [];
  int lectures = 0;
  VenteResult<Map<String, dynamic>> Function()? reponseCloture;

  @override
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId) async {
    lectures++;
    return VenteOk({'strSTATUT': 'is_Process', 'lgTYPEVENTEID': '1', ...?vente});
  }

  @override
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async => VenteOk([
        SaleItemDetail(
            lgPREENREGISTREMENTDETAILID: 'D1', lgFAMILLEID: 'P1', strNAME: 'PRODUIT FICTIF', intCIP: '1', intQUANTITY: 1, intPRICEUNITAIR: net, intPRICE: net, strREF: 'REF-FICT')
      ]);
  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) async => VenteOk(SaleSummary(montant: net, montantNet: net, reference: 'REF-FICT', venteId: venteId));
  @override
  Future<VenteResult<SaleSummary>> netVnoRemise(String venteId, String? remiseId) => netVno(venteId);
  @override
  Future<VenteResult<List<RemiseOption>>> remisesVente() async => const VenteOk([]);
  @override
  Future<VenteResult<void>> appliquerRemise(String venteId, String? remiseId) async => const VenteOk(null);
  @override
  Future<VenteResult<List<PaymentMethod>>> paymentMethods() async =>
      VenteOk([PaymentMethod(id: '1', name: 'Espèces'), PaymentMethod(id: '7', name: 'ORANGE MONEY'), PaymentMethod(id: '10', name: 'WAVE')]);
  @override
  Future<VenteResult<List<PaymentMethodQr>>> paymentMethodsWithQr() async => const VenteOk([]);

  VenteResult<Map<String, dynamic>> _clore(Map<String, Object?> corps) {
    clotures.add(corps);
    final f = reponseCloture;
    if (f != null) return f();
    return const VenteOk({'success': true});
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
  }) async =>
      _clore({'typeRegleId': typeReglementId, 'reglements': [(typeReglementId, summary.montantNet)], 'montantRecu': montantRecu});

  @override
  Future<VenteResult<Map<String, dynamic>>> cloturerVnoReglements({
    required String venteId,
    required SaleSummary summary,
    required List<VenteReglement> reglements,
    required String clientId,
    required String userVendeurId,
    required int montantRecu,
    required int montantRemis,
  }) async =>
      _clore({
        'typeRegleId': reglementPrincipal(reglements).typeReglementId,
        'reglements': [for (final r in reglements) (r.typeReglementId, r.montant)],
        'montantRecu': montantRecu,
        'montantRemis': montantRemis,
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Future<T> _settle<T>(WidgetTester t, Future<T> f) async {
  var done = false;
  late T v;
  unawaited(f.then((x) {
    v = x;
    done = true;
  }));
  for (var i = 0; i < 200 && !done; i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(done, isTrue);
  return v;
}

/// Ouvre l'encaissement de la prévente V-FICT-1 ; [done] reçoit le résultat.
Future<VenteController> _encaissement(WidgetTester t, _Gw gw, void Function(EncaissementDone?) done,
    {List<String> modes = const ['1'], Size taille = const Size(720, 1440), double dpr = 2}) async {
  t.view.physicalSize = taille;
  t.view.devicePixelRatio = dpr;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({'enabled_payment_method_ids': modes});
  final c = VenteController(gateway: gw);
  await _settle(t, c.loadVente('V-FICT-1'));
  final settings = SettingsProvider();
  await settings.loadSettings();
  await t.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
    value: settings,
    child: MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => done(await Navigator.of(ctx).push<EncaissementDone>(MaterialPageRoute(
                  builder: (_) => EncaissementPage(
                        controller: c,
                        userId: 'U-FICT',
                        expectedChanges: c.changes,
                        summary: c.summary,
                        itemCount: c.items.length,
                        presentation: ListPresentation.dashboard,
                        initialCopies: 1,
                        dejaPayee: c.preventePayee,
                      )))),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('Ouvrir'));
  await t.pumpAndSettle();
  return c;
}

final _valider = find.byKey(const ValueKey('encaissement-valider'));
bool _actif(WidgetTester t) => t.widget<ElevatedButton>(_valider).onPressed != null;
String _libelle(WidgetTester t) =>
    find.descendant(of: _valider, matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data ?? '').join(' ');

void main() {
  setUp(() => DroitsVente.instance.oublier());
  tearDown(() => DroitsVente.instance.oublier());

  group('Borne (point 3a)', () {
    testWidgets('cas du pharmacien : droit P_BORNE_PAIEMENT_MOBILE + caisse ouverte → cloturer:true, vente terminée par le serveur', (t) async {
      DroitsVente.instance.fixer({'P_SM_VENTE', DroitsVente.bornePaiementMobileDroit}, utilisateur: 'U-borne.fictive');
      final pm = _Pm(droits: {'P_SM_VENTE', DroitsVente.bornePaiementMobileDroit});
      final imp = await _payerALaBorne(t, pm);
      expect(pm.cloturers, [true]);
      expect(DroitsVente.instance.terminerVente, isFalse, reason: 'aucun bouton « Terminer une vente » ordinaire');
      final ticket = imp.tickets.single;
      expect((ticket.paye, ticket.aTerminer), (true, false));
      expect(ticket.invitationTexte, BorneTicket.invitationPayee);
      expect(_invitationEcran(t), isNot(contains('PAYÉE')));
      expect(t.takeException(), isNull);
      await _fin(t);
    });

    testWidgets('droit de la borne SANS caisse ouverte : payé, pas clôturé → ticket « PAYÉE, présentez ce ticket à la caisse »', (t) async {
      DroitsVente.instance.fixer({'P_SM_VENTE', DroitsVente.bornePaiementMobileDroit}, utilisateur: 'U-borne.fictive');
      final pm = _Pm(droits: {'P_SM_VENTE', DroitsVente.bornePaiementMobileDroit}, caisseOuverte: false);
      final imp = await _payerALaBorne(t, pm);
      expect(pm.cloturers, [true]);
      final ticket = imp.tickets.single;
      expect((ticket.paye, ticket.aTerminer), (true, true));
      expect(ticket.invitationTexte, 'PAYÉE, présentez ce ticket à la caisse');
      expect(_invitationEcran(t), contains('PAYÉE, présentez ce ticket à la caisse'));
      await _fin(t);
    });

    testWidgets('droit de la borne retiré entre-temps (403 interdit à cloturer:true) : redemandé une fois avec cloturer:false', (t) async {
      DroitsVente.instance.fixer({'P_SM_VENTE', DroitsVente.bornePaiementMobileDroit}, utilisateur: 'U-borne.fictive');
      final pm = _Pm(droits: {'P_SM_VENTE'}); // droit retiré sur le serveur
      final imp = await _payerALaBorne(t, pm);
      expect(pm.cloturers, [true, false]);
      expect(pm.cles, hasLength(1), reason: 'même clé X-Client-Ref : jamais deux paiements');
      expect(imp.tickets.single.aTerminer, isTrue);
      expect(find.byKey(const ValueKey('borne-avis-ticket')), findsNothing);
      await _fin(t);
    });

    testWidgets('serveur d\'aujourd\'hui (droit inconnu), compte prévente : cloturer:false, ticket PAYÉE (comme 4.13.1)', (t) async {
      DroitsVente.instance.fixer({'P_SM_VENTE'}, utilisateur: 'U-borne.fictive');
      final pm = _Pm(droits: {'P_SM_VENTE'}, d62: false);
      final imp = await _payerALaBorne(t, pm);
      expect(pm.cloturers, [false]);
      expect(imp.tickets.single.aTerminer, isTrue);
      await _fin(t);
    });

    testWidgets('serveur d\'aujourd\'hui, compte avec « Terminer une vente », 403 inattendu : pas de repli (comme 4.14.0)', (t) async {
      DroitsVente.instance.fixer({'P_SM_CLOTURER_CAISSE'}, utilisateur: 'U-borne.fictive');
      final pm = _Pm(droits: {'P_SM_VENTE'}, d62: false);
      final imp = await _payerALaBorne(t, pm);
      expect(pm.cloturers, [true]);
      expect(imp.tickets.single.paye, isFalse, reason: 'ticket de prévente pour la caisse');
      expect(find.byKey(const ValueKey('borne-avis-ticket')), findsOneWidget);
      await _fin(t);
    });
  });

  group('Comptoir (point 3b)', () {
    testWidgets('prévente payée reprise : bandeau, mode imposé (non activé sur l\'appareil), rien à encaisser, TERMINER LA VENTE', (t) async {
      final gw = _Gw(vente: venteFictivePayee());
      EncaissementDone? fini;
      final c = await _encaissement(t, gw, (d) => fini = d, modes: const ['1']);
      expect(c.preventePayee?.montant, 4125);
      expect(find.byKey(const ValueKey('prevente-payee-bandeau')), findsOneWidget);
      expect(find.textContaining('Déjà payée par Wave'), findsOneWidget);
      expect(find.byKey(const ValueKey('mode-impose-10')), findsOneWidget);
      expect(find.byKey(const ValueKey('mode-1')), findsNothing, reason: 'liste verrouillée');
      expect(find.byKey(const ValueKey('encaissement-recu')), findsNothing, reason: 'aucun montant à saisir');
      expect(find.text('Exact'), findsNothing);
      final recu = t.widget<TextFormField>(find.byKey(const ValueKey('encaissement-payee-recu')));
      expect(recu.enabled, isFalse);
      expect(find.byKey(const ValueKey('pm-qr-unique')), findsNothing, reason: 'jamais de nouveau QR');
      expect(_libelle(t), 'TERMINER LA VENTE');
      expect(_actif(t), isTrue);
      await t.tap(_valider);
      await t.pumpAndSettle();
      expect(gw.clotures.single['typeRegleId'], '10');
      expect(gw.clotures.single['reglements'], [('10', 4125)]);
      expect(fini?.method.id, '10');
      expect(fini?.dejaCloturee, isFalse);
    });

    testWidgets('net augmenté : Wave porte le montant payé, complément en espèces ; clôture en deux modes', (t) async {
      final gw = _Gw(vente: venteFictivePayee(montant: 4125), net: 5000);
      EncaissementDone? fini;
      await _encaissement(t, gw, (d) => fini = d, modes: const ['1', '10']);
      expect(find.textContaining('a augmenté'), findsWidgets);
      expect(_actif(t), isFalse, reason: 'complément à choisir');
      final especes = find.byKey(const ValueKey('complement-1'));
      await t.scrollUntilVisible(especes, 100, scrollable: find.byType(Scrollable).last);
      await t.tap(especes);
      await t.pump();
      final recu = find.byKey(const ValueKey('complement-recu'));
      await t.scrollUntilVisible(recu, 100, scrollable: find.byType(Scrollable).last);
      await t.enterText(recu, '1000');
      await t.pump();
      expect(_actif(t), isTrue);
      await t.tap(_valider);
      await t.pumpAndSettle();
      expect(gw.clotures.single['reglements'], [('10', 4125), ('1', 875)]);
      expect(gw.clotures.single['montantRemis'], 125);
      expect(fini?.reglements, hasLength(2));
    });

    testWidgets('net diminué sous le montant payé : TERMINER bloqué avec le motif (aucune requête)', (t) async {
      final gw = _Gw(vente: venteFictivePayee(montant: 4125), net: 3000);
      await _encaissement(t, gw, (_) {});
      expect(find.textContaining('ne peut pas être terminée'), findsWidgets);
      expect(_actif(t), isFalse);
      expect(gw.clotures, isEmpty);
    });

    testWidgets('refus du serveur {success:false, paiementMobile:true} : message tel quel, vente gardée, paiement relu', (t) async {
      const msg = 'Cette prévente est déjà payée par Wave : 4125 F (n° TX-FICT-0042). Terminez-la avec le mode Wave pour ce montant, '
          'sans encaisser à nouveau.';
      final gw = _Gw(vente: venteFictivePayee())..reponseCloture = () => const VenteRefused(msg, code: VenteRefused.codePaiementMobile);
      EncaissementDone? fini;
      var ferme = false;
      final c = await _encaissement(t, gw, (d) {
        fini = d;
        ferme = true;
      });
      final avant = gw.lectures;
      await t.tap(_valider);
      await t.pumpAndSettle();
      expect(find.text(msg), findsOneWidget);
      expect((ferme, fini), (false, null), reason: 'la page reste ouverte');
      expect(c.finished, isFalse, reason: 'vente gardée');
      expect(gw.lectures, avant + 1, reason: 'paiement relu');
      expect(find.byKey(const ValueKey('encaissement-caisse-fermee')), findsNothing);
    });

    testWidgets('serveur d\'aujourd\'hui (aucun champ) : page d\'origine (Espèces, montant reçu), aucun bandeau', (t) async {
      final gw = _Gw();
      await _encaissement(t, gw, (_) {}, modes: const ['1', '10']);
      expect(find.byKey(const ValueKey('prevente-payee-bandeau')), findsNothing);
      expect(find.byKey(const ValueKey('encaissement-payee')), findsNothing);
      expect(find.byKey(const ValueKey('mode-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('encaissement-recu')), findsOneWidget);
      expect(_libelle(t), 'VALIDER L\'ENCAISSEMENT');
    });

    testWidgets('liste des préventes : « Payée Wave … » à la place de « À encaisser » ; sans le champ : badge d\'origine', (t) async {
      t.view.physicalSize = const Size(720, 1440);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      SharedPreferences.setMockInitialValues({});
      Map<String, dynamic> ligne(String id, {bool payee = false}) => {
            if (payee) ...venteFictivePayee(),
            'lgPREENREGISTREMENTID': id,
            'heure': '10:42:00',
            'dtUPDATED': '19/11/2026',
            'intPRICE': 4125,
            'strREF': 'REF-$id',
            'userFullName': 'Vendeur Fictif',
            'lgTYPEVENTEID': '1',
          };
      await t.pumpWidget(MaterialApp(
        home: PreventeListScreen(
          load: () async => VenteOk([PreventeListItem.fromJson(ligne('V-A', payee: true)), PreventeListItem.fromJson(ligne('V-B'))]),
          onSelect: (_) async => true,
          presentation: ListPresentation.dashboard,
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('prevente-payee-V-A')), findsOneWidget);
      expect(find.textContaining('Payée Wave'), findsOneWidget);
      expect(find.text('À encaisser'), findsOneWidget, reason: 'seule la prévente non payée garde le badge');
    });

    testWidgets('assurance : bandeau seulement, page d\'origine (le serveur ne contrôle pas la clôture assurance)', (t) async {
      t.view.physicalSize = const Size(720, 1440);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      SharedPreferences.setMockInitialValues({'enabled_payment_method_ids': ['1', '10']});
      final settings = SettingsProvider();
      await settings.loadSettings();
      await t.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: EncaissementPage(
            actions: EncaissementActions(
              paymentMethods: () async => VenteOk([PaymentMethod(id: '1', name: 'Espèces'), PaymentMethod(id: '10', name: 'WAVE')]),
              loadQrMethods: () async {},
              qrFor: (_) => null,
              encaisser: (m, r, x) async => const VenteOk((dejaCloturee: false)),
            ),
            expectedChanges: 1,
            summary: SaleSummary(montant: 4125, montantNet: 4125, reference: 'REF-FICT', venteId: 'V-FICT-1'),
            itemCount: 1,
            presentation: ListPresentation.dashboard,
            totalLabel: 'Part client à payer',
            dejaPayee: PreventePayee.depuisVente(venteFictivePayee()),
            dejaPayeeImpose: false,
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('prevente-payee-bandeau')), findsOneWidget);
      expect(find.byKey(const ValueKey('encaissement-payee')), findsNothing);
      expect(find.byKey(const ValueKey('mode-1')), findsOneWidget);
    });
  });
}

