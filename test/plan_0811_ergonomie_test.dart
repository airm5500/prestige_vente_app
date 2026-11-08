// ERGONOMIE — Prestige Mobile 4.11.0, plan du pharmacien du 08/11 : Sunmi V2s / V3, téléphone 360 × 800 dp et
// tablette 10″, texte ×1,0 et ×1,3 :
//  - icônes agrandies (« trop petites sur tablette et terminal ») : accueil, barre du haut, saisie rapide de la
//    réserve ; aucune erreur de rendu ; cibles tactiles ≥ 48 dp ; téléphone courant inchangé ;
//  - nouveaux éléments lisibles et sans débordement : aide « 0128 = 01/01/2028 » et message d'erreur de la
//    péremption, rapport des écarts et bouton « Entrer le reçu », champ « Saisir un produit », confirmation du sens.
// Données FICTIVES.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/reserve/reserve_api.dart';
import 'package:prestige_vente_app/reserve/reserve_models.dart';
import 'package:prestige_vente_app/reserve/reserve_panier_screen.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_bl_screen.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/ui/icones.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart' show RacineTailleEcran;
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

import 'outils/app_e2e.dart';
import 'outils/ergonomie.dart' show ciblesTactiles, facteurEcran;
import 'reception_bl_test.dart' show FakePrestigeRecu;

const _tailles = [TailleEcran.sunmiV2s, TailleEcran.sunmiV3, TailleEcran.telephone360x800, TailleEcran.tablette];

class _Api extends ReserveApi {
  _Api() : super(ClientPrestige(() => 'http://127.0.0.1:1/prestige/api/v1'));
  @override
  Future<List<EnteteSuggestion>> enAttente({int limit = 200}) async => const [];
  @override
  Future<List<MotifReserve>> motifs(SensReserve sens) async => const [MotifReserve(id: 1, libelle: 'Reappro rayon journalier', categorie: 'RAYON')];
  @override
  Future<PageArticles> articles(String recherche, {String type = '', int start = 0, int limit = 30}) async =>
      const PageArticles([ArticleReserve(familleId: 'F1', cip: '3595583', nom: 'PARACETAMOL FICTIF 1000MG COMPRIMES B/8', stockRayon: 2, stockReserve: 9)], 1);
}

/// Hauteur rendue (dp de l'interface) des icônes trouvées par [f].
List<double> _icones(WidgetTester t, Finder f) => [
      for (final e in f.evaluate())
        if (e.renderObject is RenderBox && (e.renderObject! as RenderBox).hasSize) (e.renderObject! as RenderBox).size.height,
    ];

Future<void> _app(WidgetTester t, Widget w) async {
  // Même enveloppe que l'application (MaterialApp.builder) : ResponsiveTheme applique l'échelle des icônes.
  // « Taille de l'écran » au-dessus (Automatique : Compact sur les terminaux), comme dans l'application.
  await t.pumpWidget(RacineTailleEcran(child: MaterialApp(builder: (c, child) => ResponsiveTheme(child: child!), home: w)));
  await t.pumpAndSettle();
}

void main() {
  for (final taille in _tailles) {
    for (final texte in [1.0, 1.3]) {
      final nom = '${taille.nom}, texte ×$texte';
      final facteur = EchelleIcones.pour(taille.pixels / taille.densite);

      testWidgets('accueil : icônes ×$facteur, sans débordement — $nom', (t) async {
        taille.appliquer(t);
        t.platformDispatcher.textScaleFactorTestValue = texte;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final app = AppE2E();
        await app.preparer(prefs: {'hiddenMenuIds': <String>[]});
        await app.lancer(t);
        expect(await app.seConnecter(t), isTrue);
        await app.attendre(t, const Duration(seconds: 2));
        final tuiles = _icones(t, find.descendant(of: find.byKey(const ValueKey('tuile_prevente')), matching: find.byType(Icon)));
        expect(tuiles, isNotEmpty);
        expect(tuiles.first, closeTo(30 * facteur, 0.6), reason: '$nom : icône de tuile (30 dp × $facteur)');
        final barre = _icones(t, find.descendant(of: find.byType(IconButton), matching: find.byType(Icon)));
        expect(barre.reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(24 * facteur - 0.5), reason: '$nom : boutons-icônes');
        expect(t.takeException(), isNull, reason: nom);
        final h = t.ensureSemantics();
        await expectLater(t, meetsGuideline(ciblesTactiles(facteurEcran(t))), reason: '$nom : cibles ≥ 48 dp');
        h.dispose();
        await app.fermer(t);
      });

      testWidgets('réception : aide et erreur de la péremption, écarts et « Entrer le reçu » — $nom', (t) async {
        taille.appliquer(t);
        t.platformDispatcher.textScaleFactorTestValue = texte;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final srv = FakePrestigeRecu()
          ..add('d1', 'PARACETAMOL FICTIF 1000MG COMPRIMES PELLICULES B/8', '3595583', '3400935955838', 24)
          ..add('d2', 'AUTRE PRODUIT FICTIF AU NOM TRÈS LONG POUR LE TEST', '3000000', '3400930000007', 10, entered: 4, lots: ['Z9']);
        await _app(
            t,
            ReceptionBlScreen(
              bl: const ReceptionBl(id: 'bl1', ref: 'BL-778', grossiste: 'GROSSISTE FICTIF'),
              gateway: srv,
              settings: const ReceptionSettings(terminalValidation: true),
              clock: () => DateTime(2026, 11, 8),
              presentation: ListPresentation.dashboard,
            ));
        await t.enterText(find.byType(TextField).first, '3595583');
        await t.pump(const Duration(milliseconds: 400));
        await t.pumpAndSettle();
        final date = find.widgetWithText(TextField, 'Péremption (JJ/MM/AAAA ou MM/AAAA)');
        await t.ensureVisible(date);
        await t.tap(date);
        await t.enterText(date, '9999');
        await t.testTextInput.receiveAction(TextInputAction.next);
        await t.pumpAndSettle();
        expect(find.textContaining('Date illisible'), findsOneWidget);
        expect(t.takeException(), isNull, reason: '$nom : champ de péremption');
        FocusManager.instance.primaryFocus?.unfocus();
        await t.pumpAndSettle();
        final liste = find.ancestor(of: date, matching: find.byType(Scrollable)).first;
        t.state<ScrollableState>(liste).position.jumpTo(0);
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('Fermer').first);
        await t.pumpAndSettle();
        final terminer = find.text('Terminer et vérifier');
        await t.ensureVisible(terminer);
        await t.tap(terminer);
        await t.pumpAndSettle();
        final recu = find.byKey(const Key('bl_entrer_recu'));
        expect(recu, findsOneWidget);
        expect(t.getSize(recu).height, greaterThanOrEqualTo(48));
        final ecran = t.view.physicalSize / t.view.devicePixelRatio;
        expect(t.getRect(recu).right, lessThanOrEqualTo(ecran.width + 0.5));
        expect(t.takeException(), isNull, reason: '$nom : bilan');
      });

      testWidgets('réserve : « Saisir un produit » et confirmation du sens — $nom', (t) async {
        taille.appliquer(t);
        t.platformDispatcher.textScaleFactorTestValue = texte;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await _app(t, ReservePanierScreen(sens: SensReserve.versRayon, api: _Api()));
        final champ = find.byKey(const ValueKey('reserve-saisie'));
        expect(t.getSize(champ).height, greaterThanOrEqualTo(48));
        final scanner = find.byKey(const ValueKey('reserve-saisie-scanner'));
        expect(t.getSize(scanner).width, greaterThanOrEqualTo(48));
        expect(_icones(t, find.descendant(of: scanner, matching: find.byType(Icon))).single, greaterThanOrEqualTo(28));
        await t.tap(champ);
        await t.enterText(champ, '3595583');
        await t.testTextInput.receiveAction(TextInputAction.search);
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const ValueKey('reserve-quantite')), '2');
        await t.testTextInput.receiveAction(TextInputAction.done);
        await t.pumpAndSettle();
        final creer = find.byKey(const ValueKey('reserve-creer'));
        await t.ensureVisible(creer);
        await t.tap(creer);
        await t.pumpAndSettle();
        final dialogue = find.byKey(const ValueKey('reserve-confirmer-sens'));
        expect(dialogue, findsOneWidget);
        final ecran = Offset.zero & (t.view.physicalSize / t.view.devicePixelRatio);
        for (final k in ['reserve-confirmer-sens-oui', 'reserve-confirmer-sens-non', 'reserve-confirmer-sens-fleche']) {
          final r = t.getRect(find.byKey(ValueKey(k)));
          expect(ecran.contains(r.topLeft) && ecran.contains(r.bottomRight - const Offset(0.1, 0.1)), isTrue, reason: '$nom : $k visible');
        }
        expect(t.getSize(find.byKey(const ValueKey('reserve-confirmer-sens-oui'))).height, greaterThanOrEqualTo(40));
        expect(t.takeException(), isNull, reason: nom);
      });
    }
  }
}
