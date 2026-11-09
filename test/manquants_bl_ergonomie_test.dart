// ERGONOMIE — Prestige Mobile 4.12.0 (demande 59) : Sunmi V2s / V3, téléphone 360 × 800 dp et tablette 10″, texte
// ×1,0 et ×1,3. Fenêtre du résultat « au reçu » avec le bilan relu, le total manquant et « Créer un retour en attente
// des manquants », puis la référence du retour ; fenêtre du refus AUCUN_RECU. Aucune erreur de rendu, boutons
// entièrement visibles, cibles tactiles ≥ 48 dp (de l'interface). Données FICTIVES.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/reception/manquants_bl.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_summary_screen.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart' show RacineTailleEcran;
import 'package:prestige_vente_app/widgets/responsive.dart';

import 'manquants_bl_test.dart' show FakeManquants;
import 'outils/app_e2e.dart';
import 'outils/ergonomie.dart' show ciblesTactiles, facteurEcran;

const _tailles = [TailleEcran.sunmiV2s, TailleEcran.sunmiV3, TailleEcran.telephone360x800, TailleEcran.tablette];

const _lignes = [
  ReceptionLine(detailId: 'd1', produitId: 'p1', name: 'PARACETAMOL FICTIF 1000MG COMPRIMES PELLICULES B/8', code: '3595583', ordered: 24, entered: 20, lots: ['L1'], blRef: 'BL-778'),
  ReceptionLine(detailId: 'd2', produitId: 'p2', name: 'AUTRE PRODUIT FICTIF AU NOM TRÈS LONG POUR LE TEST', code: '3000000', ordered: 10, blRef: 'BL-778'),
];

const _ecarts = [
  LigneEcart(nom: 'PARACETAMOL FICTIF 1000MG COMPRIMES PELLICULES B/8', commande: 24, recu: 20, manquant: 4),
  LigneEcart(nom: 'AUTRE PRODUIT FICTIF AU NOM TRÈS LONG POUR LE TEST', commande: 10, recu: 0, manquant: 10),
];

Future<void> _bilan(WidgetTester t, FakeManquants g) async {
  await t.pumpWidget(RacineTailleEcran(
      child: MaterialApp(
          builder: (c, child) => ResponsiveTheme(child: child!),
          home: ReceptionSummaryScreen(
              bl: const ReceptionBl(id: 'bl1', ref: 'BL-778', grossiste: 'GROSSISTE FICTIF'),
              gateway: g,
              settings: const ReceptionSettings(terminalValidation: true),
              lines: _lignes,
              clock: () => DateTime(2026, 11, 9)))));
  await t.pumpAndSettle();
  final b = find.byKey(const Key('bl_entrer_recu'));
  await t.ensureVisible(b);
  await t.tap(b);
  await t.pumpAndSettle();
  await t.tap(find.text('Entrer le reçu'));
  await t.pumpAndSettle();
}

void _visible(WidgetTester t, Finder f, String raison) {
  final ecran = Offset.zero & (t.view.physicalSize / t.view.devicePixelRatio);
  final r = t.getRect(f);
  expect(ecran.contains(r.topLeft) && ecran.contains(r.bottomRight - const Offset(0.1, 0.1)), isTrue, reason: raison);
}

void main() {
  for (final taille in _tailles) {
    for (final texte in [1.0, 1.3]) {
      final nom = '${taille.nom}, texte ×$texte';

      testWidgets('résultat « au reçu » et retour des manquants — $nom', (t) async {
        taille.appliquer(t);
        t.platformDispatcher.textScaleFactorTestValue = texte;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final g = FakeManquants()
          ..reponseRecu = const ReceptionResult(true, 'BL entré en stock avec écart : 2 ligne(s), 14 boîte(s) manquante(s)', {'success': true, 'totalManquant': 14})
          ..apres = const EcartsBl(success: true, mode: 'RECU', ecarts: _ecarts, totalManquant: 14)
          ..reponsesRetour.add(const RetourManquants(success: true, retourId: 'R1', ref: 'RF-0001', statut: 'is_Waiting', lignes: 2, totalManquant: 14));
        await _bilan(t, g);
        final creer = find.byKey(const Key('bl_retour_manquants'));
        expect(creer, findsOneWidget);
        _visible(t, creer, '$nom : « Créer un retour » visible');
        _visible(t, find.text('OK'), '$nom : OK visible');
        expect(t.takeException(), isNull, reason: '$nom : résultat');
        final h = t.ensureSemantics();
        await expectLater(t, meetsGuideline(ciblesTactiles(facteurEcran(t))), reason: '$nom : cibles ≥ 48 dp');
        h.dispose();
        await t.tap(creer);
        await t.pumpAndSettle();
        expect(find.byKey(const Key('bl_retour_manquants_message')), findsOneWidget);
        expect(t.takeException(), isNull, reason: '$nom : retour créé');
      });

      testWidgets('refus AUCUN_RECU — $nom', (t) async {
        taille.appliquer(t);
        t.platformDispatcher.textScaleFactorTestValue = texte;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final g = FakeManquants()..reponseRecu = const ReceptionResult(false, 'x', {'success': false, 'code': 'AUCUN_RECU'});
        await _bilan(t, g);
        expect(find.byKey(const Key('bl_aucun_recu')), findsOneWidget);
        _visible(t, find.text('OK'), '$nom : OK visible');
        expect(t.takeException(), isNull, reason: nom);
      });
    }
  }
}
