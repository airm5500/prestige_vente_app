// Captures PNG RÉELLES (rendu Flutter, faux serveur, données FICTIVES) — 4.15.2, demande 64 :
//  - borne : caisse de la borne fermée → refus du serveur avant tout paiement : aucun QR de paiement, ticket de
//    prévente, « Paiement mobile indisponible, rendez-vous à la caisse avec votre ticket. » ;
//  - comptoir (panier de la nouvelle interface) : prévente payée par Wave puis quantité modifiée → message du serveur
//    tel quel ; paiement Orange Money en cours → message « en cours ».
// Sunmi V2s (720 × 1440) et tablette (1920 × 1200). Hors de la suite de la CI. Pour régénérer :
//   APERCUS=1 CAPTURES=/chemin flutter test test/outils/captures_demande64_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_kiosque.dart';
import 'package:prestige_vente_app/borne/borne_screen.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_cart.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../demande64_ecrans_test.dart' show PmBorne64, BorneGw64, ImpBorne64, GwVerrou64, regler64, modifierLigne64;
import 'app_e2e.dart' show TailleEcran;
import 'demande64_fictive.dart';

final _actif = Platform.environment.containsKey('APERCUS');
final _dossier = Platform.environment['CAPTURES'] ?? '/tmp/captures_d64';

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
  await (FontLoader('MaterialIcons')..addFont(lire('MaterialIcons-Regular.otf'))).load();
}

Future<void> _capture(WidgetTester t, String nom) async {
  await t.pump();
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile(Uri.file('$_dossier/$nom.png')));
}

void main() {
  setUpAll(() async {
    if (_actif) {
      await _polices();
      Directory(_dossier).createSync(recursive: true);
    }
  });

  for (final (taille, code) in [(TailleEcran.sunmiV2s, 'sunmi_v2s'), (TailleEcran.tablette, 'tablette')]) {
    testWidgets('capture borne : caisse fermée, refus avant paiement → ticket de prévente — $code', (t) async {
      taille.appliquer(t);
      SharedPreferences.setMockInitialValues({});
      PaiementsMobileReglages.actif.value = true;
      addTearDown(() => PaiementsMobileReglages.actif.value = false);
      DroitsVente.instance.fixer({'P_SM_VENTE', DroitsVente.bornePaiementMobileDroit}, utilisateur: 'U-borne.fictive');
      addTearDown(DroitsVente.instance.oublier);
      BorneKiosque.instance = KiosqueSimule();
      final pm = PmBorne64();
      await t.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: BorneScreen(
          service: BorneService(BorneGw64()),
          config: const BorneConfig(actif: true, login: 'borne.fictive'),
          monitor: ServerMonitor(),
          imprimante: ImpBorne64(),
          kiosque: KiosqueSimule(),
          adminCheck: (_) async => true,
          onSortie: (_) {},
          officine: 'PHARMACIE FICTIVE',
          paiementsMobile: PaiementsMobile(api: pm),
          delaiTicket: const Duration(minutes: 5),
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
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 250));
      }
      expect(pm.cloturers, [true]);
      expect(find.byKey(const ValueKey('pm-qr')), findsNothing);
      expect(find.text(BorneScreen.avisMobileIndisponible), findsOneWidget);
      await _capture(t, '${code}_1_borne_caisse_fermee_payer_en_caisse');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    }, skip: !_actif);

    for (final paye in [true, false]) {
      // Panier du comptoir (nouvelle interface, charte de l'application). Seule différence avec l'appareil : la police
      // du bandeau est nommée (Roboto), le moteur de test n'ayant pas de police par défaut lisible.
      testWidgets('capture comptoir : panier verrouillé (${paye ? 'payée Wave' : 'Orange Money en cours'}) — $code', (t) async {
        taille.appliquer(t);
        SharedPreferences.setMockInitialValues({});
        final message = paye ? messagePayeWave4125 : messageEnCoursOrange4125;
        final c = VenteController(gateway: GwVerrou64(message));
        await regler64(t, c.loadVente('V-FICT-64'));
        final base = themeNouvelleInterface(AppTheme.lightTheme);
        final theme = base.copyWith(
            snackBarTheme: base.snackBarTheme.copyWith(contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Roboto')));
        await t.pumpWidget(ChangeNotifierProvider<VenteController>.value(
          value: c,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: Scaffold(
              appBar: AppBar(
                  backgroundColor: Pal.navy,
                  foregroundColor: Colors.white,
                  title: const Text('Vente · REF-FICT-64', style: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w700))),
              body: const VenteCart(),
            ),
          ),
        ));
        await t.pump();
        await modifierLigne64(t, '1');
        await t.pump(const Duration(milliseconds: 600));
        expect(find.text(message), findsOneWidget);
        await _capture(t, '${code}_${paye ? 2 : 3}_comptoir_verrou_${paye ? 'payee' : 'en_cours'}');
        await t.pumpWidget(const SizedBox());
      }, skip: !_actif);
    }
  }
}
