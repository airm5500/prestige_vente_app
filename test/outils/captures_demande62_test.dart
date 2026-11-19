// Captures PNG RÉELLES (rendu Flutter, faux serveur, données FICTIVES) — 4.15.0, demande 62 :
//  - comptoir : prévente payée à la borne, « Payée Wave … » dans la liste, bandeau « Déjà payée par Wave », page
//    d'encaissement au mode imposé (« TERMINER LA VENTE ») ;
//  - remise proposée à un compte de prévente (décision du pharmacien du 19/11) ;
//  - borne : ticket « PAYÉE, présentez ce ticket à la caisse » (droit P_BORNE_PAIEMENT_MOBILE, caisse fermée).
// Sunmi V2s (720 × 1440) et tablette (1920 × 1200). Hors de la suite de la CI. Pour régénérer :
//   APERCUS=1 CAPTURES=/chemin flutter test test/outils/captures_demande62_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_e2e.dart';
import 'clients_vente_fictifs.dart';
import 'demande62_fictive.dart';
import 'parcours_vente.dart';
import 'remises_fictives.dart';

final _actif = Platform.environment.containsKey('APERCUS');
final _dossier = Platform.environment['CAPTURES'] ?? '/tmp/captures_d62';

Future<void> _polices() async {
  final dossier = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<ByteData> lire(String f) async => ByteData.sublistView(await File(f.startsWith('/') ? f : '$dossier/$f').readAsBytes());
  for (final famille in ['Roboto', 'FlutterTest', '', 'Ahem', 'sans-serif', 'Roboto Flex']) {
    final l = FontLoader(famille);
    for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
      l.addFont(lire(f));
    }
    await l.load();
  }
  final mono = FontLoader('monospace');
  for (final f in ['/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf']) {
    if (File(f).existsSync()) mono.addFont(lire(f));
  }
  await mono.load();
  await (FontLoader('MaterialIcons')..addFont(lire('MaterialIcons-Regular.otf'))).load();
}

Future<void> _capture(WidgetTester t, String nom) async {
  await t.pump();
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile(Uri.file('$_dossier/$nom.png')));
}

class _Pm implements PaiementsMobileApi {
  bool _auto = false;
  @override
  Future<VenteResult<CapacitesPM>> capacites() async => const VenteOk(CapacitesPM(operateurs: ['wave', 'orange'], fournisseur: 'simulateur'));
  @override
  Future<VenteResult<PaiementMobile>> creer({required String venteId, required String operateur, int? part, bool cloturer = false, required String cle}) async {
    _auto = cloturer;
    return VenteOk(PaiementMobile(id: 'PM1', venteId: venteId, montant: 4125, operateur: operateur, statut: StatutPM.enAttente, clotureAuto: cloturer));
  }

  // Payé ; clôture automatique refusée (aucune caisse ouverte pour le compte de la borne).
  @override
  Future<VenteResult<PaiementMobile>> statut(String id) async => VenteOk(PaiementMobile(
      id: 'PM1', venteId: 'V1', montant: 4125, operateur: 'wave', statut: StatutPM.paye, clotureAuto: _auto, message: 'Clôture refusée : Votre caisse est fermée'));
  @override
  Future<VenteResult<PaiementMobile>> annuler(String id) => statut(id);
  @override
  Future<VenteResult<List<PaiementMobile>>> historique(DateTime jour) async => const VenteOk([]);
}

class _BorneGw implements VenteGateway {
  final produits = [
    ProductSearchResult(lgFAMILLEID: 'P1', strNAME: 'PRODUIT FICTIF 500MG CPR B/20', intCIP: '1P1', intPRICE: 4125, intNUMBERAVAILABLE: 10, strLIBELLEE: '', intPAF: 0)
  ];
  @override
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async => VenteOk(ProductPage(produits, produits.length));
  @override
  Future<VenteResult<String>> addItemVno({required String produitId, required int qte, required int itemPu, String? venteId, required bool prevente}) async =>
      const VenteOk('V1');
  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) async => VenteOk(SaleSummary(montant: 4125, montantNet: 4125, reference: '261119_00042', venteId: 'V1'));
  @override
  Future<VenteResult<void>> terminerPrevente(String venteId) async => const VenteOk(null);
  @override
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async => VenteOk([
        SaleItemDetail(
            lgPREENREGISTREMENTDETAILID: 'D1', lgFAMILLEID: 'P1', strNAME: 'PRODUIT FICTIF 500MG CPR B/20', intCIP: '1P1', intQUANTITY: 1, intPRICEUNITAIR: 4125, intPRICE: 4125, strREF: '261119_00042')
      ]);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _SansImprimante implements BorneImprimante {
  @override
  Future<bool> imprimer(BorneTicket t) async => false;
}

void main() {
  setUpAll(() async {
    if (_actif) {
      await _polices();
      Directory(_dossier).createSync(recursive: true);
    }
  });

  for (final (taille, code) in [(TailleEcran.sunmiV2s, 'sunmi_v2s'), (TailleEcran.tablette, 'tablette')]) {
    testWidgets('captures comptoir : prévente payée à la borne — $code', (t) async {
      taille.appliquer(t);
      final app = AppE2E();
      CatalogueFictif(app.serveur, nombre: 10);
      ClientsVenteFictifs(app.serveur);
      RemisesFictives(app.serveur);
      final d = Demande62Fictive(app.serveur);
      await app.preparer(prefs: {...prefsVente, 'is_test_print_mode': true});
      await app.lancer(t);
      expect(await app.seConnecter(t), isTrue);
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
      final id = d.preventeDeLaBorne();
      d.preventeDeLaBorne(payee: false, prix: 2350);
      await t.tap(find.byTooltip('Préventes à encaisser').first);
      expect(await app.attendreQue(t, find.text('REF-$id')), isTrue);
      await app.attendre(t, const Duration(milliseconds: 800));
      await _capture(t, '${code}_1_liste_prevente_payee');
      await t.tap(find.text('REF-$id'));
      await app.attendre(t, const Duration(seconds: 2));
      FocusManager.instance.primaryFocus?.unfocus();
      await app.attendre(t, const Duration(milliseconds: 500));
      await _capture(t, '${code}_2_bandeau_deja_payee');
      await t.tap(find.byKey(const ValueKey('vente-encaisser')));
      await app.attendre(t, const Duration(seconds: 2));
      await _capture(t, '${code}_3_encaissement_mode_impose');
      await app.fermer(t);
    }, skip: !_actif);

    testWidgets('captures remise d\'un compte de prévente — $code', (t) async {
      taille.appliquer(t);
      final app = AppE2E();
      CatalogueFictif(app.serveur, nombre: 10);
      ClientsVenteFictifs(app.serveur);
      RemisesFictives(app.serveur);
      Demande62Fictive(app.serveur);
      app.serveur.droitsComptes = {DonneesFictives.login: ['P_SM_VENTE']};
      await app.preparer(prefs: prefsVente);
      await app.lancer(t);
      expect(await app.seConnecter(t), isTrue);
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
      expect(await ajouterAuPanier(t, app, nomCourt(3), qte: '4'), isTrue);
      await app.attendre(t, const Duration(seconds: 2));
      FocusManager.instance.primaryFocus?.unfocus();
      await app.attendre(t, const Duration(milliseconds: 500));
      await t.tap(find.byKey(const ValueKey('remise-vente-choisir')));
      await app.attendre(t, const Duration(seconds: 1));
      await t.tap(find.byKey(const ValueKey('remise-option-REM-FICT-10')));
      await app.attendre(t, const Duration(seconds: 2));
      await _capture(t, '${code}_4_remise_compte_prevente');
      await app.fermer(t);
    }, skip: !_actif);

    testWidgets('captures borne : ticket PAYÉE (caisse de la borne fermée) — $code', (t) async {
      taille.appliquer(t);
      SharedPreferences.setMockInitialValues({});
      PaiementsMobileReglages.actif.value = true;
      addTearDown(() => PaiementsMobileReglages.actif.value = false);
      DroitsVente.instance.fixer({'P_SM_VENTE', DroitsVente.bornePaiementMobileDroit}, utilisateur: 'U-borne.fictive');
      addTearDown(DroitsVente.instance.oublier);
      BorneKiosque.instance = KiosqueSimule();
      await t.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: BorneScreen(
          service: BorneService(_BorneGw()),
          config: const BorneConfig(actif: true, login: 'borne.fictive'),
          monitor: ServerMonitor(),
          imprimante: _SansImprimante(),
          kiosque: KiosqueSimule(),
          adminCheck: (_) async => true,
          onSortie: (_) {},
          officine: 'PHARMACIE FICTIVE',
          paiementsMobile: PaiementsMobile(api: _Pm()),
          delaiTicketEcran: const Duration(minutes: 5),
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
      for (final k in ['borne-voir-panier', 'borne-panier-lateral-payer']) {
        final panier = find.byKey(ValueKey(k));
        if (panier.evaluate().isNotEmpty) {
          await t.tap(panier);
          await t.pump();
          break;
        }
      }
      final mobile = find.byKey(const ValueKey('borne-payer-mobile'));
      await t.ensureVisible(mobile);
      await t.pump();
      await t.tap(mobile);
      await t.pump();
      await t.tap(find.byKey(const ValueKey('borne-operateur-wave')));
      for (var i = 0; i < 24; i++) {
        await t.pump(const Duration(milliseconds: 250));
      }
      expect(find.textContaining('PAYÉE, présentez ce ticket à la caisse'), findsWidgets);
      await _capture(t, '${code}_5_borne_ticket_payee');
      final voir = find.text('Voir le ticket');
      await t.ensureVisible(voir);
      await t.tap(voir);
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 250));
      }
      await t.ensureVisible(find.byKey(const ValueKey('borne-ticket-titre')));
      await t.pump();
      await _capture(t, '${code}_6_borne_ticket_payee_detail');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    }, skip: !_actif);
  }
}
