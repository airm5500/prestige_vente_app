// ÉCRANS — 5.2.0 : présentation de l'accueil au choix (Réglages › Apparence › Accueil) : « Actuelle » (par défaut),
// « Metro mosaïque », « Metro bandes ». Données fictives.
//  - réglage : Actuelle sans valeur enregistrée (installations existantes), valeur inconnue → Actuelle, enregistré et
//    relu, autres préférences (présentation des menus, favoris, menus masqués) intactes ;
//  - Réglages › Apparence : 3 choix avec aperçu et description pour l'administrateur, choix appliqué tout de suite ;
//    présentation seulement indiquée pour un autre compte ;
//  - placement de la mosaïque : aucune case vide, aucun chevauchement, 2 premiers favoris en 2×2 ;
//  - couleurs : contraste du texte blanc ≥ 4,5:1, teinte gardée ;
//  - corps Metro : toutes les tuiles `tuile_<id>`, cadenas, pastilles, toucher / appui long ; bandes dans l'ordre
//    strict, 58 dp, rangées justifiées.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/accueil/accueil_metro.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/accueil_metro_fictif.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PresentationPrefs.accueil.value = AccueilPresentation.actuelle;
  });

  group('réglage enregistré', () {
    test('sans valeur enregistrée (installation existante) : Actuelle ; les autres préférences sont intactes', () async {
      final avant = <String, Object>{
        'presentation_listes_v1': 'compact',
        'accueil_favoris_v1': ['search', 'caisse'],
        'hiddenMenuIds': ['carnet'],
        'menuOrder': ['stock', 'prevente'],
      };
      SharedPreferences.setMockInitialValues(avant);
      expect(await PresentationPrefs.loadAccueil(), AccueilPresentation.actuelle);
      expect(await PresentationPrefs.load(), ListPresentation.compact, reason: 'présentation des menus inchangée');
      await PresentationPrefs.saveAccueil(AccueilPresentation.metroBandes);
      final p = await SharedPreferences.getInstance();
      for (final e in avant.entries) {
        expect(p.get(e.key), e.value, reason: '${e.key} intacte');
      }
      expect(p.getString(PresentationPrefs.cleAccueil), 'metroBandes');
    });

    test('valeur inconnue (version future, fichier abîmé) : Actuelle', () async {
      SharedPreferences.setMockInitialValues({PresentationPrefs.cleAccueil: 'metroInconnue'});
      expect(await PresentationPrefs.loadAccueil(), AccueilPresentation.actuelle);
    });

    test('chaque choix enregistré est relu (redémarrage : valeur en mémoire perdue)', () async {
      for (final v in AccueilPresentation.values) {
        await PresentationPrefs.saveAccueil(v);
        PresentationPrefs.accueil.value = AccueilPresentation.actuelle; // nouveau lancement
        expect(await PresentationPrefs.loadAccueil(), v);
        expect(PresentationPrefs.accueil.value, v);
      }
    });

    test('libellés et descriptions des 3 présentations', () {
      expect(AccueilPresentation.values.map((p) => p.label), ['Actuelle', 'Metro mosaïque', 'Metro bandes']);
      for (final p in AccueilPresentation.values) {
        expect(p.description, isNotEmpty);
      }
      expect(AccueilPresentation.actuelle.metro, isFalse);
      expect(AccueilPresentation.metroMosaique.metro, isTrue);
    });
  });

  group('Réglages › Apparence', () {
    Future<void> page(WidgetTester t, {required bool admin}) async {
      t.view.physicalSize = const Size(720, 1440);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: ApparencePage(initial: ListPresentation.dashboard, openOrganiser: (_) async {}, choixPresentation: admin)));
      await t.pumpAndSettle();
    }

    testWidgets('administrateur : 3 choix avec aperçu et description, Actuelle cochée, choix enregistré tout de suite', (t) async {
      await page(t, admin: true);
      final carte = find.byKey(const Key('presentation_accueil'));
      await t.scrollUntilVisible(find.byKey(const Key('presentation_accueil_metroBandes')), 120, scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      expect(carte, findsOneWidget);
      for (final p in AccueilPresentation.values) {
        expect(find.byKey(Key('presentation_accueil_${p.name}')), findsOneWidget);
        expect(find.byKey(ValueKey('apercu_accueil_${p.name}')), findsOneWidget);
        expect(find.text(p.description), findsOneWidget);
      }
      RadioListTile<AccueilPresentation> tuile(AccueilPresentation p) => t.widget(find.byKey(Key('presentation_accueil_${p.name}')));
      expect(tuile(AccueilPresentation.actuelle).groupValue, AccueilPresentation.actuelle, reason: 'Actuelle par défaut');
      await t.ensureVisible(find.byKey(const Key('presentation_accueil_metroMosaique')));
      await t.pumpAndSettle();
      await t.tap(find.text('Metro mosaïque'));
      await t.pumpAndSettle();
      expect(PresentationPrefs.accueil.value, AccueilPresentation.metroMosaique);
      expect((await SharedPreferences.getInstance()).getString(PresentationPrefs.cleAccueil), 'metroMosaique');
      expect(tuile(AccueilPresentation.actuelle).groupValue, AccueilPresentation.metroMosaique);
      expect(await PresentationPrefs.load(), ListPresentation.dashboard, reason: 'présentation des menus non touchée');
      await t.scrollUntilVisible(find.text('Organiser l\'accueil'), -120, scrollable: find.byType(Scrollable).first);
      expect(find.text('Organiser l\'accueil'), findsOneWidget, reason: 'Organiser l\'accueil toujours là');
      expect(t.takeException(), isNull);
    });

    testWidgets('autre compte : présentation indiquée, pas de choix', (t) async {
      PresentationPrefs.accueil.value = AccueilPresentation.metroBandes;
      await page(t, admin: false);
      await t.scrollUntilVisible(find.byKey(const Key('presentation_accueil_reservee')), 120, scrollable: find.byType(Scrollable).first);
      expect(find.text('Présentation de l\'accueil : Metro bandes'), findsOneWidget);
      expect(find.byKey(const Key('presentation_accueil_actuelle')), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('placement de la mosaïque', () {
    for (final largeur in [320.0, 360.0, 400.0, 800.0, 452.0]) {
      testWidgets('$largeur dp : chaque famille sans case vide ni chevauchement, favoris principaux en 2×2', (t) async {
        await monterMetro(t, AccueilPresentation.metroMosaique, largeur: largeur);
        final familles = famillesCompletes();
        for (final f in MenuFamille.values) {
          final ids = [for (final m in familles[f]!) m.id];
          if (ids.isEmpty) continue;
          final rects = {for (final id in ids) id: t.getRect(find.byKey(ValueKey('tuile_$id')))};
          for (final a in ids) {
            for (final b in ids) {
              if (a.compareTo(b) < 0) {
                expect(rects[a]!.deflate(0.5).overlaps(rects[b]!.deflate(0.5)), isFalse, reason: '$a / $b se chevauchent');
              }
            }
          }
          // Pavage complet : chaque tuile + la moitié de l'espace qui l'entoure couvre exactement le rectangle englobant.
          const gap = AccueilMetro.gap;
          final englobant = rects.values.reduce((a, b) => a.expandToInclude(b));
          final surface = rects.values.fold<double>(0, (s, r) => s + (r.width + gap) * (r.height + gap));
          expect(englobant.width, closeTo(largeur - 32, 0.6), reason: '$f : pleine largeur');
          expect(surface, closeTo((englobant.width + gap) * (englobant.height + gap), 2), reason: '$f : aucune case vide');
        }
        final simple = t.getRect(find.byKey(const ValueKey('tuile_carnet'))).height;
        for (final id in ['prevente', 'assurance']) {
          final r = t.getRect(find.byKey(ValueKey('tuile_$id')));
          expect(r.height, greaterThan(simple * 1.9), reason: '$id en grand (2 rangées)');
          expect(find.byKey(ValueKey('sous_titre_$id')), findsOneWidget, reason: 'libellé complet en sous-titre');
        }
        expect(t.takeException(), isNull);
      });
    }

    test('MetroGrille : tailles imposées, trous comblés par la voisine', () {
      // 4 colonnes : a (2×2), b (1×1), c (3×1) → c ne tient pas à côté de a : b s'élargit, c passe dessous.
      final g = MetroGrille.calculer(
        ids: ['a', 'b', 'c', 'd'],
        colonnes: 4,
        largeur: 4 * 50 + 3 * MetroGrille.gap,
        taille: (id, _, __, ___) => switch (id) { 'a' => (2, 2), 'c' => (3, 1), _ => (1, 1) },
        hauteurUnite: (cell) => cell,
      );
      for (final ligne in g.cases) {
        expect(ligne.contains(null), isFalse, reason: 'aucune case vide : ${g.cases}');
      }
      expect(g.position['a'], (0, 0));
      expect(g.taille['a'], (2, 2));
      expect(g.cases.expand((l) => l).toSet(), {'a', 'b', 'c', 'd'});
    });
  });

  group('couleurs', () {
    test('texte blanc lisible (≥ 4,5:1) sur chaque menu ; teinte gardée ; couleur déjà sombre inchangée', () {
      for (final m in [...accueilMenus, ...menusSousDroits, menuBorneAdmin, menuPrestigePointage]) {
        final c = MetroCharte.pleine(m.color);
        expect(MetroCharte.contrasteBlanc(c), greaterThanOrEqualTo(4.5), reason: m.id);
        final h0 = HSLColor.fromColor(m.color).hue;
        expect((HSLColor.fromColor(c).hue - h0).abs(), lessThan(2.5), reason: '${m.id} : teinte');
      }
      const sombre = Color(0xFF283593);
      expect(MetroCharte.pleine(sombre), sombre);
      expect(MetroCharte.contrasteBlanc(MetroCharte.pleine(Colors.lime.shade700)), greaterThanOrEqualTo(4.5));
    });
  });

  group('corps Metro', () {
    for (final p in [AccueilPresentation.metroMosaique, AccueilPresentation.metroBandes]) {
      testWidgets('${p.label} : toutes les tuiles, cadenas, pastilles, toucher et appui long', (t) async {
        final ouverts = <String>[];
        final longs = <String>[];
        final menus = await monterMetro(t, p, hauteur: 3000, onOpen: (m) => ouverts.add(m.id), onLongPress: (m) => longs.add(m.id));
        expect(tuilesConstruites(), {for (final m in menus) m.id});
        for (final m in menus) {
          expect(find.byKey(ValueKey('libelle_${m.id}')), findsOneWidget);
          expect(find.byKey(ValueKey('cadenas_${m.id}')), m.protege ? findsOneWidget : findsNothing, reason: m.id);
        }
        expect(find.descendant(of: find.byKey(const ValueKey('pastille_prevente')), matching: find.text('128')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('pastille_bl_control')), matching: find.text('7')), findsOneWidget);
        for (final f in MenuFamille.values) {
          expect(find.byKey(ValueKey('metro_famille_${f.name}')), famillesCompletes()[f]!.isEmpty ? findsNothing : findsOneWidget);
        }
        await t.tap(find.byKey(const ValueKey('tuile_stock')));
        await t.longPress(find.byKey(const ValueKey('tuile_carnet')));
        await t.pumpAndSettle();
        expect(ouverts, ['stock']);
        expect(longs, ['carnet']);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('bandes : ordre strict, 58 dp, rangées justifiées', (t) async {
      await monterMetro(t, AccueilPresentation.metroBandes, hauteur: 3000);
      for (final f in MenuFamille.values) {
        final menus = famillesCompletes()[f]!;
        Rect? prec;
        final droites = <double, double>{};
        for (final m in menus) {
          final r = t.getRect(find.byKey(ValueKey('tuile_${m.id}')));
          expect(r.height, closeTo(AccueilMetro.hauteurBande, 0.01), reason: m.id);
          if (prec != null) {
            final suite = (r.top - prec.top).abs() < 0.5 ? r.left > prec.right : r.top > prec.bottom;
            expect(suite, isTrue, reason: '${m.id} après le précédent (ordre strict)');
          }
          droites[r.top] = r.right;
          prec = r;
        }
        for (final d in droites.values) {
          expect(d, closeTo(360 - 16, 0.6), reason: '$f : rangée justifiée');
        }
      }
    });

    testWidgets('mosaïque sans favori visible : aucune tuile 2×2', (t) async {
      await monterMetro(t, AccueilPresentation.metroMosaique, hauteur: 3000, favoris: const []);
      expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('sous_titre_')), findsNothing);
      expect(t.takeException(), isNull);
    });
  });
}
