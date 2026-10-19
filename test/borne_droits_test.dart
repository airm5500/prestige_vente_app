// 4.5.1 — Borne et droits de vente (correction du pharmacien : la borne termine une vente par paiement mobile money,
// clôture `cloturer:true` sous la session de l'utilisateur borne ; l'espèce donne un ticket de prévente pour la caisse) :
//  - droits de l'utilisateur borne lus (GET v1/user/droits) à la connexion de la borne, avec l'en-tête
//    X-Prestige-Utilisateur ;
//  - sans droit de clôture : « PAYER PAR MOBILE MONEY » n'est pas proposé, seul le ticket pour la caisse reste ;
//  - 403 interdit pendant un paiement mobile money : « Paiement mobile indisponible, rendez-vous à la caisse avec votre
//    ticket », ticket de prévente imprimé, vente gardée, aucune nouvelle tentative, borne toujours connectée ;
//  - « Tester la borne » : « Utilisateur borne sans droit de clôture : paiement mobile désactivé ».
// Données fictives uniquement.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_diagnostic.dart';
import 'package:prestige_vente_app/borne/borne_kiosque.dart';
import 'package:prestige_vente_app/borne/borne_screen.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/app_e2e.dart';

/// Faux module de paiement : capacités (Wave), création refusée faute de droit si [refuser].
class _Pm implements PaiementsMobileApi {
  bool refuser = false;
  int creations = 0;
  int statuts = 0;

  @override
  Future<VenteResult<CapacitesPM>> capacites() async => const VenteOk(CapacitesPM(operateurs: ['wave'], fournisseur: 'simulateur'));

  @override
  Future<VenteResult<PaiementMobile>> creer({required String venteId, required String operateur, int? part, bool cloturer = false, required String cle}) async {
    creations++;
    if (refuser) return const VenteRefused('Droit manquant : terminer une vente.', code: VenteRefused.codeInterdit);
    return VenteOk(PaiementMobile(
        id: 'PM1', venteId: venteId, reference: 'R', montant: 3000, operateur: operateur, statut: StatutPM.enAttente, lien: 'simulateur://PM1', clotureAuto: cloturer));
  }

  @override
  Future<VenteResult<PaiementMobile>> statut(String id) async {
    statuts++;
    return const VenteOk(PaiementMobile(id: 'PM1', venteId: 'V1', reference: 'R', montant: 3000, operateur: 'wave', statut: StatutPM.enAttente, lien: ''));
  }

  @override
  Future<VenteResult<PaiementMobile>> annuler(String id) async => statut(id);
  @override
  Future<VenteResult<List<PaiementMobile>>> historique(DateTime jour) async => const VenteOk([]);
}

class _Gw implements VenteGateway {
  final produits = [
    ProductSearchResult(lgFAMILLEID: 'P1', strNAME: 'DOLIPRANE 1000MG CP', intCIP: '1P1', intPRICE: 3000, intNUMBERAVAILABLE: 10, strLIBELLEE: '', intPAF: 0)
  ];
  int terminees = 0;
  @override
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async => VenteOk(ProductPage(produits, produits.length));
  @override
  Future<VenteResult<String>> addItemVno({required String produitId, required int qte, required int itemPu, String? venteId, required bool prevente}) async =>
      const VenteOk('V1');
  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) async => VenteOk(SaleSummary(montant: 3000, montantNet: 3000, reference: '261019_00007', venteId: 'V1'));
  @override
  Future<VenteResult<void>> terminerPrevente(String venteId) async {
    terminees++;
    return const VenteOk(null);
  }

  @override
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async => VenteOk([
        SaleItemDetail(
            lgPREENREGISTREMENTDETAILID: 'D1', lgFAMILLEID: 'P1', strNAME: 'DOLIPRANE 1000MG CP', intCIP: '1P1', intQUANTITY: 1, intPRICEUNITAIR: 3000, intPRICE: 3000, strREF: '261019_00007')
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

Future<(_Gw, _Imp)> _borne(WidgetTester t, _Pm pm) async {
  t.view.physicalSize = const Size(720, 1520);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  PaiementsMobileReglages.actif.value = true;
  addTearDown(() => PaiementsMobileReglages.actif.value = false);
  BorneKiosque.instance = KiosqueSimule();
  final gw = _Gw(), imp = _Imp();
  await t.pumpWidget(MaterialApp(
    home: BorneScreen(
      service: BorneService(gw),
      config: const BorneConfig(actif: true, login: 'borne.accueil'),
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
  await t.enterText(find.byKey(const ValueKey('borne-recherche')), 'doli');
  await t.pump(const Duration(milliseconds: 450));
  await t.pump();
  await t.pump();
  await t.tap(find.byKey(const ValueKey('borne-ajouter-P1')));
  await t.pump();
  await t.tap(find.byKey(const ValueKey('borne-voir-panier')));
  await t.pump();
  return (gw, imp);
}

void main() {
  setUp(() => DroitsVente.instance.oublier());
  tearDown(() => DroitsVente.instance.oublier());

  group('Écran de la borne', () {
    testWidgets('utilisateur borne sans droit de clôture : mobile money non proposé, ticket pour la caisse seul', (t) async {
      DroitsVente.instance.fixer({'P_SM_VENTE'}, utilisateur: 'U-borne.accueil');
      final pm = _Pm();
      await _borne(t, pm);
      expect(find.byKey(const ValueKey('borne-payer')), findsOneWidget);
      expect(find.byKey(const ValueKey('borne-payer-mobile')), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('droits relus en cours de route (retour au premier plan) : le choix disparaît sans écran cassé', (t) async {
      DroitsVente.instance.fixer({'P_SM_CLOTURER_CAISSE'}, utilisateur: 'U-borne.accueil');
      await _borne(t, _Pm());
      await t.pump();
      expect(find.byKey(const ValueKey('borne-payer-mobile')), findsOneWidget, reason: 'avec le droit : proposé comme avant');
      DroitsVente.instance.fixer({'P_SM_VENTE'}, utilisateur: 'U-borne.accueil');
      await t.pump();
      expect(find.byKey(const ValueKey('borne-payer-mobile')), findsNothing);
      expect(find.byKey(const ValueKey('borne-payer')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('403 interdit pendant le paiement mobile : message, ticket de prévente imprimé, aucune nouvelle tentative', (t) async {
      DroitsVente.instance.fixer(null, utilisateur: 'U-borne.accueil'); // serveur sans lecture des droits : proposé
      final pm = _Pm()..refuser = true;
      final (gw, imp) = await _borne(t, pm);
      final mobile = find.byKey(const ValueKey('borne-payer-mobile'));
      await t.ensureVisible(mobile);
      await t.pump();
      await t.tap(mobile);
      await t.pump();
      await t.tap(find.byKey(const ValueKey('borne-operateur-wave')));
      await _avancer(t, const Duration(seconds: 2));
      expect(gw.terminees, 1, reason: 'prévente créée (vente gardée)');
      expect(find.byKey(const ValueKey('borne-avis-ticket')), findsOneWidget);
      expect(find.text(BorneScreen.avisMobileIndisponible), findsOneWidget);
      expect(imp.tickets, hasLength(1));
      expect(imp.tickets.single.paye, isFalse, reason: 'ticket de PRÉVENTE pour la caisse');
      expect(find.byKey(const ValueKey('borne-numero')), findsOneWidget);
      await _avancer(t, const Duration(seconds: 6));
      expect(pm.creations, 1, reason: 'aucune nouvelle tentative');
      expect(pm.statuts, 0, reason: 'aucun paiement à suivre');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  });

  group('« Tester la borne »', () {
    Future<DiagnosticBorne> tester(List<String>? droits) async => avecVraiHttp(() async {
          final s = FauxServeurPrestige(exigerSession: true, comptes: {'borne.accueil': 'Borne#2026'})..droitsComptes = droits == null ? null : {'borne.accueil': droits};
          await s.demarrer();
          addTearDown(s.arreter);
          final d = await TesteurBorne(
                  baseUrl: s.base,
                  secrets: MemoireBorneSecrets('Borne#2026'),
                  delai: const Duration(seconds: 5))
              .tester(const BorneConfig(actif: true, login: 'borne.accueil'));
          final droitsLus = s.recuesSur('/user/droits');
          expect(droitsLus, hasLength(1));
          expect(droitsLus.single.utilisateur, 'U-borne.accueil', reason: 'en-tête X-Prestige-Utilisateur de l\'utilisateur borne');
          return d;
        });

    test('sans droit de clôture : « Utilisateur borne sans droit de clôture : paiement mobile désactivé »', () async {
      final d = await tester(['P_SM_VENTE']);
      final e = d.etapes.firstWhere((e) => e.titre == titreDroitCloture);
      expect(e.etat, EtatEtapeBorne.attention);
      expect(e.detail, startsWith('Utilisateur borne sans droit de clôture : paiement mobile désactivé'));
      expect(d.ok, isTrue, reason: 'la borne fonctionne (ticket pour la caisse)');
    });

    test('avec le droit : paiement mobile possible ; serveur ancien : comme avant', () async {
      expect((await tester(['P_SM_CLOTURER_CAISSE'])).etapes.firstWhere((e) => e.titre == titreDroitCloture).etat, EtatEtapeBorne.ok);
      expect((await tester(null)).etapes.firstWhere((e) => e.titre == titreDroitCloture).detail, contains('comme avant'));
    });
  });

  group('Borne dans l\'application (e2e)', () {
    testWidgets('connexion de la borne : droits de l\'utilisateur borne lus avec son en-tête ; mobile money masqué sans le droit', (t) async {
      TailleEcran.telephone360x800.appliquer(t);
      final avantSecrets = BorneReglages.secrets;
      BorneReglages.secrets = MemoireBorneSecrets('Borne#2026');
      final avantKiosque = BorneKiosque.instance;
      BorneKiosque.instance = KiosqueSimule();
      final avantPm = PaiementsMobile.instance;
      PaiementsMobile.instance = PaiementsMobile();
      addTearDown(() {
        BorneReglages.secrets = avantSecrets;
        BorneReglages.courant.value = const BorneConfig();
        BorneKiosque.instance = avantKiosque;
        PaiementsMobile.instance = avantPm;
        PaiementsMobileReglages.actif.value = false;
      });
      final app = AppE2E(serveur: FauxServeurPrestige(comptes: {
        DonneesFictives.login: DonneesFictives.motDePasse,
        'borne.accueil': 'Borne#2026',
      }));
      app.serveur.droitsComptes = {'borne.accueil': ['P_SM_VENTE']};
      app.serveur.routes['GET /paiements-mobile/capacites'] =
          (_) => FauxServeurPrestige.ok({'success': true, 'paiementsMobile': ['wave'], 'fournisseur': 'simulateur'});
      app.serveur.routes['GET /vente/search'] = (_) => FauxServeurPrestige.ok({
            'data': [
              {'lgFAMILLEID': 'F1', 'strNAME': 'DOLIPRANE 1000MG CP B/8', 'intCIP': '3595583', 'intPRICE': 1500, 'intNUMBERAVAILABLE': 40, 'strLIBELLEE': '', 'intPAF': 0}
            ],
            'total': 1
          });
      await app.preparer(prefs: {
        'borne_config_v1': jsonEncode(const BorneConfig(actif: true, login: 'borne.accueil').toJson()),
        'hiddenMenuIds': <String>[],
        'paiements_mobile_actif_v1': true,
      });
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-recherche'))), isTrue);
      await app.attendre(t, const Duration(seconds: 2));
      final lus = app.serveur.recuesSur('/user/droits');
      expect(lus, isNotEmpty, reason: 'droits lus à la connexion de la borne');
      expect(lus.last.utilisateur, 'U-borne.accueil');
      expect(DroitsVente.instance.cloturerPaiementMobile, isFalse);
      await t.enterText(find.byKey(const ValueKey('borne-recherche')), 'doli');
      await app.attendre(t, const Duration(seconds: 2));
      await t.tap(find.byKey(const ValueKey('borne-ajouter-F1')));
      await app.attendre(t, const Duration(milliseconds: 500));
      await t.tap(find.byKey(const ValueKey('borne-voir-panier')));
      await app.attendre(t, const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('borne-payer')), findsOneWidget);
      expect(find.byKey(const ValueKey('borne-payer-mobile')), findsNothing);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });
}
