// Images des modes de paiement : résolution par id Prestige et par libellé (casse, accents), repli
// (mode inconnu, logo absent), présence et chargement des logos déclarés, accessibilité, écran
// d'encaissement (présentations A/B/C, 360 px, thème sombre) et liste des paiements mobile money.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/paiements/mode_paiement_logo.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile_screen.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/encaissement_page.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _modes = {
  '1': 'Espèces',
  '2': 'CHEQUE',
  '3': 'CARTE BANCAIRE',
  '4': 'DIFFERE',
  '6': 'VIREMENT',
  '7': 'ORANGE',
  '8': 'MOOV',
  '9': 'MTN',
  '10': 'WAVE',
  '19': 'DJAMO',
};

final _methods = [for (final e in _modes.entries) PaymentMethod(id: e.key, name: e.value)];

void _ecran(WidgetTester tester, {double largeur = 360, double hauteur = 780}) {
  tester.view.physicalSize = Size(largeur * 2, hauteur * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

/// Page d'encaissement avec tous les modes activés.
Future<List<PaymentMethod>> _encaissement(WidgetTester tester, {ListPresentation style = ListPresentation.dashboard, ThemeData? theme}) async {
  SharedPreferences.setMockInitialValues({'enabled_payment_method_ids': _modes.keys.toList()});
  final settings = SettingsProvider();
  await settings.loadSettings();
  final payes = <PaymentMethod>[];
  await tester.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
    value: settings,
    child: MaterialApp(
      theme: theme,
      home: EncaissementPage(
        actions: EncaissementActions(
          paymentMethods: () async => VenteOk(_methods),
          loadQrMethods: () async {},
          qrFor: (_) => null,
          encaisser: (m, recu, remis) async {
            payes.add(m);
            return const VenteFailed('test');
          },
        ),
        expectedChanges: 0,
        summary: SaleSummary(montant: 4000, montantNet: 4000, reference: 'REF-1', venteId: 'V1'),
        itemCount: 2,
        presentation: style,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return payes;
}

class _Pm implements PaiementsMobileApi {
  @override
  Future<VenteResult<CapacitesPM>> capacites() async => const VenteOk(CapacitesPM(operateurs: ['orange', 'moov', 'mtn', 'wave']));
  @override
  Future<VenteResult<PaiementMobile>> creer({required String venteId, required String operateur, int? part, bool cloturer = false, required String cle}) async =>
      const VenteFailed('non');
  @override
  Future<VenteResult<PaiementMobile>> statut(String id) async => const VenteFailed('non');
  @override
  Future<VenteResult<PaiementMobile>> annuler(String id) async => const VenteFailed('non');
  @override
  Future<VenteResult<List<PaiementMobile>>> historique(DateTime jour) async => VenteOk([
        for (final (i, op) in ['orange', 'moov', 'mtn', 'wave', 'inconnu'].indexed)
          PaiementMobile(
              id: 'P$i', venteId: 'V$i', reference: 'R-$i', montant: 1000 * (i + 1), operateur: op, statut: StatutPM.paye, creeLe: '2026-10-11 09:1$i:00'),
      ]);
}

void main() {
  group('Résolution du mode', () {
    test('par id Prestige', () {
      const attendu = {
        '1': ModePaiementType.especes,
        '2': ModePaiementType.cheque,
        '3': ModePaiementType.carte,
        '4': ModePaiementType.differe,
        '6': ModePaiementType.virement,
        '7': ModePaiementType.orange,
        '8': ModePaiementType.moov,
        '9': ModePaiementType.mtn,
        '10': ModePaiementType.wave,
        '19': ModePaiementType.djamo,
      };
      for (final e in attendu.entries) {
        expect(resoudreModePaiement(modeId: e.key), e.value, reason: 'id ${e.key}');
        expect(resoudreModePaiement(modeId: ' ${e.key} ', libelle: 'autre'), e.value, reason: 'id prioritaire');
      }
      // Codes opérateur B3 → mode Prestige (même table que le serveur).
      for (final e in typeReglementOperateur.entries) {
        expect(resoudreModePaiement(modeId: e.value).name, e.key);
      }
    });

    test('par libellé quand l\'id est inconnu (casse, accents, mots courts)', () {
      const cas = {
        'WAVE': ModePaiementType.wave,
        'Wave CI': ModePaiementType.wave,
        'wave': ModePaiementType.wave,
        'Orange Money': ModePaiementType.orange,
        'ORANGE': ModePaiementType.orange,
        'OM': ModePaiementType.orange,
        'Paiement om': ModePaiementType.orange,
        'Moov Money': ModePaiementType.moov,
        'MOOV': ModePaiementType.moov,
        'MTN MoMo': ModePaiementType.mtn,
        'MOMO': ModePaiementType.mtn,
        'mtn mobile money': ModePaiementType.mtn,
        'DJAMO': ModePaiementType.djamo,
        'Djamo carte': ModePaiementType.djamo,
        'Espèces': ModePaiementType.especes,
        'ESPECES': ModePaiementType.especes,
        'ÉSPÈCES (hors ligne)': ModePaiementType.especes,
        'Chèque': ModePaiementType.cheque,
        'CHEQUE': ModePaiementType.cheque,
        'Carte bancaire': ModePaiementType.carte,
        'CB': ModePaiementType.carte,
        'Virement bancaire': ModePaiementType.virement,
        'Différé': ModePaiementType.differe,
        'CREDIT': ModePaiementType.differe,
        'Commerçant': ModePaiementType.inconnu,
        'Bon d\'achat': ModePaiementType.inconnu,
        '': ModePaiementType.inconnu,
      };
      for (final e in cas.entries) {
        expect(resoudreModePaiement(modeId: '55', libelle: e.key), e.value, reason: e.key);
        expect(modePaiementParLibelle(e.key), e.value, reason: e.key);
      }
      expect(resoudreModePaiement(), ModePaiementType.inconnu);
      expect(resoudreModePaiement(modeId: null, libelle: null), ModePaiementType.inconnu);
    });

    test('logos fournis pour le mobile money, pictogrammes pour les autres', () {
      for (final t in [ModePaiementType.orange, ModePaiementType.moov, ModePaiementType.mtn, ModePaiementType.wave, ModePaiementType.djamo]) {
        expect(visuelsModesPaiement[t]!.asset, startsWith(dossierLogosPaiement), reason: t.name);
      }
      for (final t in [ModePaiementType.especes, ModePaiementType.cheque, ModePaiementType.carte, ModePaiementType.differe, ModePaiementType.virement, ModePaiementType.inconnu]) {
        expect(visuelsModesPaiement[t]!.asset, isNull, reason: t.name);
      }
      expect(visuelsModesPaiement.keys.toSet(), ModePaiementType.values.toSet());
      expect(visuelModePaiement(modeId: '1').icone, Icons.payments);
      expect(visuelModePaiement(libelle: '???').icone, Icons.account_balance_wallet);
    });
  });

  group('Logos déclarés', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('chaque logo existe, fait 256 px au plus et se charge via rootBundle', () async {
      expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/paiements/'));
      expect(assetsModesPaiement, hasLength(5));
      for (final a in assetsModesPaiement) {
        final f = File(a);
        expect(f.existsSync(), isTrue, reason: a);
        final b = f.readAsBytesSync();
        expect(b.sublist(1, 4), 'PNG'.codeUnits, reason: '$a : PNG');
        final d = ByteData.sublistView(b);
        expect(d.getUint32(16), lessThanOrEqualTo(256), reason: '$a : largeur');
        expect(d.getUint32(20), lessThanOrEqualTo(256), reason: '$a : hauteur');
        final data = await rootBundle.load(a);
        expect(data.lengthInBytes, b.length, reason: '$a chargé');
      }
    });
  });

  group('Widget', () {
    testWidgets('logo fourni, pictogramme, repli inconnu et logo absent : jamais d\'exception', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            ModePaiementLogo(modeId: '10', libelle: 'WAVE', size: 40),
            ModePaiementLogo(modeId: '1', libelle: 'Espèces'),
            ModePaiementLogo(libelle: 'Bon d\'achat', size: 24),
            ModePaiementLogo.depuisVisuel(
                ModePaiementVisuel(ModePaiementType.wave, 'Wave', Icons.phone_android, Colors.blue, asset: 'assets/paiements/absent.png'),
                libelle: 'Wave'),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('logo-mode-wave')), findsNWidgets(2));
      expect(find.byKey(const ValueKey('picto-mode-especes')), findsOneWidget);
      // Inconnu + logo absent → pictogramme générique (portefeuille).
      expect(find.byKey(const ValueKey('picto-mode-inconnu')), findsNWidgets(2));
      expect(tester.getSize(find.byKey(const ValueKey('logo-mode-inconnu'))), const Size(24, 24));
      expect(tester.getSize(find.byKey(const ValueKey('logo-mode-wave')).first), const Size(40, 40));
      final img = tester.widget<Image>(find.byType(Image).first);
      expect((img.image as AssetImage).assetName, 'assets/paiements/wave.png');
    });

    testWidgets('accessibilité : nom du mode lu', (tester) async {
      final h = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Row(children: [
            ModePaiementLogo(modeId: '7', libelle: 'ORANGE'),
            ModePaiementLogo(modeId: '3'),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Mode de paiement : ORANGE'), findsOneWidget);
      expect(find.bySemanticsLabel('Mode de paiement : Carte bancaire'), findsOneWidget);
      h.dispose();
    });
  });

  group('Écrans', () {
    for (final style in ListPresentation.values) {
      testWidgets('encaissement ${style.label} : logo + libellé pour chaque mode, 360 px sans débordement', (tester) async {
        _ecran(tester);
        final payes = await _encaissement(tester, style: style);
        expect(tester.takeException(), isNull);
        final types = <String, ModePaiementType>{};
        for (final e in _modes.entries) {
          final tuile = find.byKey(ValueKey('mode-${e.key}'));
          await tester.ensureVisible(tuile);
          await tester.pumpAndSettle();
          expect(find.descendant(of: tuile, matching: find.text(e.value)), findsOneWidget, reason: 'libellé ${e.value} conservé');
          final logo = tester.widget<ModePaiementLogo>(find.descendant(of: tuile, matching: find.byType(ModePaiementLogo)));
          expect(tester.getSize(find.descendant(of: tuile, matching: find.byType(ModePaiementLogo))), const Size(28, 28));
          types[e.key] = resoudreModePaiement(modeId: logo.modeId, libelle: logo.libelle);
        }
        expect(types['10'], ModePaiementType.wave);
        expect(types['19'], ModePaiementType.djamo);
        expect(types['1'], ModePaiementType.especes);
        // La sélection ne change pas : un tap choisit le mode, rien n'est envoyé.
        await tester.tap(find.byKey(const ValueKey('mode-10')));
        await tester.pumpAndSettle();
        expect(payes, isEmpty);
        expect(find.textContaining('WAVE · '), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('encaissement en thème sombre : rendu sans erreur', (tester) async {
      _ecran(tester);
      await _encaissement(tester, theme: ThemeData.dark());
      expect(find.byType(ModePaiementLogo), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('liste des paiements mobile money : logo de l\'opérateur à côté du libellé, 360 px', (tester) async {
      _ecran(tester);
      await tester.pumpWidget(MaterialApp(home: PaiementsMobileScreen(api: _Pm(), jour: DateTime(2026, 10, 11))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      const attendu = {'P0': 'orange', 'P1': 'moov', 'P2': 'mtn', 'P3': 'wave', 'P4': 'inconnu'};
      for (final e in attendu.entries) {
        final ligne = find.byKey(ValueKey('pm-ligne-${e.key}'));
        await tester.ensureVisible(ligne);
        await tester.pumpAndSettle();
        expect(find.descendant(of: ligne, matching: find.byKey(ValueKey('logo-mode-${e.value}'))), findsOneWidget, reason: e.key);
      }
      expect(find.textContaining('Orange Money'), findsOneWidget);
      expect(find.textContaining('Wave'), findsOneWidget);
    });
  });
}
