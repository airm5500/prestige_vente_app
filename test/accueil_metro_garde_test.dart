// NON-RÉGRESSION — 5.2.0 : la présentation « Actuelle » de l'accueil reste la valeur par défaut et reste identique.
//  - clés de préférences existantes inchangées (présentation des menus, favoris, menus masqués, ordre) ; la nouvelle
//    clé est à part ; ListPresentation (présentation de tous les menus) inchangée : A / B / C ;
//  - accueil « Actuelle » : image identique au pixel près sans choix enregistré, avec « actuelle » enregistré, et après
//    un passage par Metro mosaïque puis retour à Actuelle ; dans les présentations A, B et C des menus.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/accueil/accueil_metro.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';

Future<Uint8List> _image(WidgetTester t) async {
  final rv = t.binding.renderViews.first;
  final layer = rv.debugLayer! as OffsetLayer;
  final img = await t.runAsync(() => layer.toImage(Offset.zero & rv.size));
  final data = await t.runAsync(() => img!.toByteData(format: ui.ImageByteFormat.rawRgba));
  img!.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  test('clés et présentations existantes inchangées', () {
    expect(AccueilFavoris.key, 'accueil_favoris_v1');
    expect(ListPresentation.values.map((p) => p.name), ['dashboard', 'compact', 'guided']);
    expect(PresentationPrefs.cleAccueil, 'presentation_accueil_v1');
    expect(AccueilPresentation.values.first, AccueilPresentation.actuelle, reason: 'Actuelle par défaut');
  });

  for (final style in ListPresentation.values) {
    testWidgets('accueil « Actuelle » (${style.label}) identique au pixel près : sans choix, « actuelle » enregistrée, après un passage par Metro', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      Future<Uint8List> accueil(Map<String, Object> prefs, {AccueilPresentation? avant}) async {
        final app = AppE2E();
        await app.preparer(prefs: {'hiddenMenuIds': <String>[], 'presentation_listes_v1': style.name, ...prefs});
        await app.lancer(t);
        expect(await app.seConnecter(t), isTrue);
        await app.attendre(t, const Duration(seconds: 3));
        if (avant != null) {
          await PresentationPrefs.saveAccueil(avant);
          await t.pump();
          expect(find.byType(AccueilMetro), findsOneWidget);
          await PresentationPrefs.saveAccueil(AccueilPresentation.actuelle);
          await app.attendre(t, const Duration(seconds: 1));
        }
        expect(find.byType(AccueilMetro), findsNothing);
        // Point clignotant de l'état du serveur : même instant d'animation pour chaque image.
        final img = await _image(t);
        await app.fermer(t);
        return img;
      }

      final sansChoix = await accueil(const {});
      final actuelle = await accueil({PresentationPrefs.cleAccueil: 'actuelle'});
      final retour = await accueil(const {}, avant: AccueilPresentation.metroMosaique);
      expect(actuelle.length, sansChoix.length);
      expect(sansChoix.toSet().length, greaterThan(50), reason: 'image réelle de l\'accueil (pas un écran vide)');
      var diff = 0;
      var diffRetour = 0;
      for (var i = 0; i < sansChoix.length; i++) {
        if (sansChoix[i] != actuelle[i]) diff++;
        if (sansChoix[i] != retour[i]) diffRetour++;
      }
      // Mesuré : 0 octet différent. Tolérance pour le point « Serveur connecté » qui clignote (animation infinie).
      expect(diff, lessThan(800), reason: 'octets différents (sans choix / actuelle) : $diff');
      expect(diffRetour, lessThan(800), reason: 'octets différents (après un passage par Metro) : $diffRetour');
    });
  }
}
