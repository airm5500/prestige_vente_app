// ERGONOMIE — 5.1.0 (retour du pharmacien du 20/11/2026) : fenêtre de quantité sur un téléphone 720×1440 (360 dp,
// Sunmi V2s), clavier ouvert (encart simulé de 288 dp) : le nom et le CIP, l'étiquette « Quantité » (jamais coupée),
// le champ, « Total ligne » et les boutons Annuler / Ajouter restent visibles et touchables, sans défiler ; sans
// clavier : raccourcis et aide « 1 à 9999 » présents. Données FICTIVES.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/ventes/common/quantity_dialog.dart';

final _produit = ProductSearchResult(
  lgFAMILLEID: 'F1',
  strNAME: 'PRODUIT FICTIF AU NOM TRES LONG 1000MG COMPRIMES PELLICULES SECABLES BOITE DE 30',
  intCIP: '3400930012345',
  intPRICE: 2450,
  intNUMBERAVAILABLE: 12,
  strLIBELLEE: '',
  intPAF: 0,
);

const _largeur = 720.0, _hauteur = 1440.0, _densite = 2.0;
const _clavierDp = 288.0;

Future<void> _ouvrir(WidgetTester t, {required bool clavier, bool smart = false, double texte = 1.0}) async {
  t.view.physicalSize = const Size(_largeur, _hauteur);
  t.view.devicePixelRatio = _densite;
  t.view.viewInsets = FakeViewPadding(bottom: clavier ? _clavierDp * _densite : 0);
  t.platformDispatcher.textScaleFactorTestValue = texte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showDialog<int>(context: ctx, barrierDismissible: false, builder: (_) => QuantityDialog(product: _produit, isSmartMode: smart)),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('go'));
  await t.pumpAndSettle();
}

/// Zone visible au-dessus du clavier (dp).
Rect _visible(bool clavier) => Rect.fromLTRB(0, 0, _largeur / _densite, _hauteur / _densite - (clavier ? _clavierDp : 0));

void _visibleEtTouchable(WidgetTester t, Finder f, Rect zone, String nom) {
  expect(f, findsOneWidget, reason: nom);
  final r = t.getRect(f);
  expect(zone.contains(r.topLeft) && zone.contains(r.bottomRight - const Offset(0.01, 0.01)), isTrue, reason: '$nom hors de la zone visible : $r');
  expect(f.hitTestable(), findsOneWidget, reason: '$nom non touchable (caché ou recouvert)');
}

void main() {
  for (final smart in [false, true]) {
    testWidgets('Sunmi V2s 720×1440, clavier ouvert${smart ? ' (scan répété)' : ''} : nom · CIP, « Quantité », champ, Total ligne, boutons visibles', (t) async {
      await _ouvrir(t, clavier: true, smart: smart);
      final zone = _visible(true);
      _visibleEtTouchable(t, find.byKey(const ValueKey('quantite-nom-cip')), zone, 'nom · CIP');
      _visibleEtTouchable(t, find.byKey(const ValueKey('quantite-champ')), zone, 'champ Quantité');
      _visibleEtTouchable(t, find.byKey(const ValueKey('quantite-total-ligne')), zone, 'Total ligne');
      _visibleEtTouchable(t, find.text('Annuler'), zone, 'Annuler');
      _visibleEtTouchable(t, find.text('Ajouter'), zone, 'Ajouter');
      expect(find.text('Total ligne'), findsOneWidget);
      // Étiquette flottante « Quantité » : entièrement dans la zone défilante (jamais coupée par son bord haut).
      final etiquette = find.text('Quantité');
      expect(etiquette, findsOneWidget);
      final defilante = find.ancestor(of: find.byKey(const ValueKey('quantite-champ')), matching: find.byType(Scrollable)).first;
      final cadre = t.getRect(defilante);
      final e = t.getRect(etiquette);
      expect(e.top, greaterThanOrEqualTo(cadre.top), reason: '« Quantité » coupée en haut : $e dans $cadre');
      expect(e.bottom, lessThanOrEqualTo(cadre.bottom));
      expect(zone.contains(e.center), isTrue);
      // Clavier ouvert : présentation compacte (ni raccourcis ni aide), rien à faire défiler.
      expect(find.byKey(const ValueKey('quantite-raccourci-1')), findsNothing);
      expect(find.text('1 à 9999'), findsNothing);
      final pos = t.state<ScrollableState>(defilante).position;
      expect(pos.maxScrollExtent, 0, reason: 'tout tient sans défiler');
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('Sunmi V2s 720×1440, sans clavier : raccourcis, aide « 1 à 9999 », tout visible', (t) async {
    await _ouvrir(t, clavier: false);
    final zone = _visible(false);
    for (final k in ['quantite-nom-cip', 'quantite-champ', 'quantite-total-ligne', 'quantite-raccourci-1', 'quantite-raccourci-10']) {
      _visibleEtTouchable(t, find.byKey(ValueKey(k)), zone, k);
    }
    expect(find.text('1 à 9999'), findsOneWidget);
    _visibleEtTouchable(t, find.text('Ajouter'), zone, 'Ajouter');
    expect(t.takeException(), isNull);
  });

  testWidgets('clavier ouvert, texte × 1,3 : aucun débordement, total et boutons visibles', (t) async {
    await _ouvrir(t, clavier: true, texte: 1.3);
    final zone = _visible(true);
    _visibleEtTouchable(t, find.text('Ajouter'), zone, 'Ajouter');
    final total = find.byKey(const ValueKey('quantite-total-ligne'));
    await t.ensureVisible(total);
    await t.pumpAndSettle();
    _visibleEtTouchable(t, total, zone, 'Total ligne');
    expect(t.takeException(), isNull);
  });
}
