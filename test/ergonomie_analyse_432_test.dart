// 4.3.2 — Ergonomie de l'Analyse article (demande du pharmacien) :
// - liste des résultats : libellé et valeur du STOCK et du PRIX sur UNE même ligne (cartes plus compactes) ;
// - fenêtre « Détails de l'Article » : STOCK RAYON et STOCK RÉSERVE sur la même ligne, bouton « Fermer » visible
//   SANS DÉFILER (en-tête et pied fixes).
// Vérifié sur Sunmi V2s (720×1440) et téléphone 360×640, texte ×1 et ×1,3, produit géré en réserve avec seuils
// (contenu le plus long), application entière contre le faux serveur.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/screens/analysis/article_analysis_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/analyse_fictive.dart';
import 'outils/app_e2e.dart';
import 'outils/performance.dart';

void main() {
  for (final ecran in [TailleEcran.sunmiV2s, TailleEcran.telephone]) {
    for (final echelle in [1.0, 1.3]) {
      testWidgets('$ecran, texte ×$echelle : stock et prix sur une ligne ; détail : rayon et réserve sur une ligne, Fermer visible',
          (t) async {
        final app = await lancerAnalyse(t, info: Duration.zero, ecran: ecran);
        t.platformDispatcher.textScaleFactorTestValue = echelle;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await app.ouvrirMenu(t, ListPresentation.dashboard, 'analyse_article');
        expect(find.byType(ArticleAnalysisScreen), findsOneWidget);
        await frappeAnalyse(t, 'doli');
        await app.attendre(t, const Duration(seconds: 1));

        // Carte de la liste : « Stock » et « Prix de vente » (libellés ET valeurs) sur la même ligne.
        final ligne = find.byKey(const ValueKey('analyse-stock-prix-F1'));
        expect(ligne, findsOneWidget);
        double milieu(Finder f) => t.getCenter(f).dy;
        final stock = find.descendant(of: ligne, matching: find.text('Stock'));
        final prix = find.descendant(of: ligne, matching: find.text('Prix de vente'));
        final valeurStock = find.descendant(of: ligne, matching: find.text('18'));
        final valeurPrix = find.descendant(of: ligne, matching: find.textContaining('475 F'));
        for (final f in [prix, valeurStock, valeurPrix]) {
          expect((milieu(f) - milieu(stock)).abs(), lessThan(2), reason: 'même ligne que « Stock »');
        }
        mesurer('Analyse article ($ecran, ×$echelle) : hauteur de la ligne stock / prix', t.getSize(ligne).height,
            seuil: 48, unite: 'px', detail: 'avant 4.3.2 : deux pavés valeur + libellé (≈ 56 px)');
        expect(t.getSize(ligne).height, lessThanOrEqualTo(48));

        // Détail (produit géré en réserve, seuils renseignés : contenu le plus long).
        await t.tap(find.text(analyseDoli).hitTestable().first);
        await app.attendre(t, const Duration(seconds: 1));
        expect(find.byKey(const ValueKey('analyse-detail')), findsOneWidget);
        final rayon = find.text('Stock rayon');
        final reserve = find.text('Stock réserve');
        expect((milieu(rayon) - milieu(reserve)).abs(), lessThan(2), reason: 'stock rayon et stock réserve sur la même ligne');
        expect(t.getTopLeft(reserve).dx, greaterThan(t.getTopRight(rayon).dx), reason: 'côte à côte');

        // « Fermer » visible sans défiler : dans l'écran, au-dessus de tout, et utilisable.
        final fermer = find.byKey(const ValueKey('analyse-detail-fermer'));
        final taille = t.view.physicalSize / t.view.devicePixelRatio;
        final r = t.getRect(fermer);
        expect(r.top, greaterThanOrEqualTo(0));
        expect(r.bottom, lessThanOrEqualTo(taille.height), reason: 'Fermer dans l\'écran sans défiler');
        expect(fermer.hitTestable(), findsOneWidget);
        // Défilement nécessaire pour voir le graphe en entier (information, sans seuil bloquant).
        final defil = find.descendant(of: find.byKey(const ValueKey('analyse-detail-fenetre')), matching: find.byType(Scrollable));
        final reste = t.state<ScrollableState>(defil.first).position.maxScrollExtent;
        mesurer('Détails de l\'Article ($ecran, ×$echelle) : contenu à faire défiler', reste.round(), seuil: 450, unite: 'px',
            detail: 'en-tête et « Fermer » fixes : toujours visibles');
        expect(t.takeException(), isNull, reason: 'aucun débordement');

        await t.tap(fermer);
        await app.attendre(t, const Duration(milliseconds: 500));
        expect(find.byKey(const ValueKey('analyse-detail')), findsNothing);
        await app.fermer(t);
      });
    }
  }
}
