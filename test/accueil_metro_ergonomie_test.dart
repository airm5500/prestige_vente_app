// ERGONOMIE — 5.2.0 : présentations Metro de l'accueil (mosaïque, bandes), données fictives. Pour 320 dp, 360 dp,
// Sunmi V2s (400 dp vus par l'interface), tablette portrait (800 dp), tablette paysage (960 et 1 280 dp), texte ×1,0
// et ×1,3, compteurs à 1 et 3 chiffres :
//  - aucun débordement (exception de mise en page), tuiles dans l'écran, aucun chevauchement ;
//  - libellés jamais tronqués, jamais coupés au milieu d'un mot, 2 lignes au plus (1 ligne en 1×1) ;
//  - libellé complet des favoris principaux (sous-titre) entier ;
//  - cadenas et pastille sans chevaucher l'icône ; contraste du texte blanc ≥ 4,5:1 ;
//  - cibles tactiles ≥ 48 dp.
// Puis l'application entière (Sunmi V2s, tablette) : en-tête, recherche et barre du bas conservés.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/accueil/accueil_metro.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/accueil_metro_fictif.dart';
import 'outils/app_e2e.dart';

const _largeurs = [320.0, 360.0, 400.0, 800.0, 960.0, 1280.0];
const _textes = [1.0, 1.3];

void main() {
  for (final p in [AccueilPresentation.metroMosaique, AccueilPresentation.metroBandes]) {
    for (final largeur in _largeurs) {
      for (final texte in _textes) {
        testWidgets('${p.label} — $largeur dp, texte ×$texte : rien de tronqué, ni débordement ni chevauchement', (t) async {
          final menus = await monterMetro(t, p, largeur: largeur, hauteur: 4000, texte: texte);
          expect(t.takeException(), isNull, reason: 'aucun débordement');
          expect(tuilesConstruites(), {for (final m in menus) m.id});
          final rects = <String, Rect>{};
          for (final m in menus) {
            final tuile = find.byKey(ValueKey('tuile_${m.id}'));
            final r = t.getRect(tuile);
            rects[m.id] = r;
            expect(r.left, greaterThanOrEqualTo(16 - 0.01), reason: '${m.id} dans l\'écran');
            expect(r.right, lessThanOrEqualTo(largeur - 16 + 0.01), reason: '${m.id} dans l\'écran');
            expect(r.height, greaterThanOrEqualTo(48), reason: '${m.id} : cible tactile');
            expect(r.width, greaterThanOrEqualTo(48), reason: '${m.id} : cible tactile');
            final libelle = find.byKey(ValueKey('libelle_${m.id}'));
            final l = mesureLibelle(t, libelle);
            expect(l.tronque, isFalse, reason: '${m.id} : « ${m.short} » tronqué');
            expect(l.motCoupe, isFalse, reason: '${m.id} : mot coupé');
            expect(l.lignes, lessThanOrEqualTo(2), reason: '${m.id} : ${l.lignes} lignes');
            final rl = t.getRect(libelle);
            expect(r.inflate(0.01).contains(rl.topLeft) && r.inflate(0.01).contains(rl.bottomRight), isTrue, reason: '${m.id} : libellé dans la tuile');
            final sous = find.byKey(ValueKey('sous_titre_${m.id}'));
            if (sous.evaluate().isNotEmpty) {
              final s = mesureLibelle(t, sous);
              expect(s.tronque || s.motCoupe, isFalse, reason: '${m.id} : sous-titre « ${m.label} » entier');
              final rs = t.getRect(sous);
              expect(rs.bottom, lessThanOrEqualTo(r.bottom + 0.01));
            }
            // Cadenas / pastille : à l'écart de l'icône et du libellé.
            for (final k in ['cadenas_${m.id}', 'pastille_${m.id}']) {
              final d = find.byKey(ValueKey(k));
              if (d.evaluate().isEmpty) continue;
              final rd = t.getRect(d);
              final icone = t.getRect(find.descendant(of: tuile, matching: find.byIcon(m.icon)).first);
              expect(rd.overlaps(icone.deflate(0.5)), isFalse, reason: '$k sur l\'icône');
              expect(rd.overlaps(rl.deflate(0.5)), isFalse, reason: '$k sur le libellé');
              expect(r.contains(rd.topLeft) && r.inflate(0.01).contains(rd.bottomRight), isTrue, reason: '$k dans la tuile');
            }
            final couleur = (t.widget<Material>(find.ancestor(of: tuile, matching: find.byType(Material)).first)).color!;
            expect(MetroCharte.contrasteBlanc(couleur), greaterThanOrEqualTo(4.5), reason: '${m.id} : contraste');
          }
          final ids = rects.keys.toList();
          for (var i = 0; i < ids.length; i++) {
            for (var j = i + 1; j < ids.length; j++) {
              expect(rects[ids[i]]!.deflate(0.5).overlaps(rects[ids[j]]!.deflate(0.5)), isFalse, reason: '${ids[i]} / ${ids[j]}');
            }
          }
          if (p == AccueilPresentation.metroBandes) {
            for (final r in rects.values) {
              expect(r.height, greaterThanOrEqualTo(AccueilMetro.hauteurBande - 0.01));
            }
          }
        });
      }
    }
  }

  testWidgets('libellé plus long que d\'habitude (menu fictif), texte ×1 et ×2 : jamais coupé, aucun débordement', (t) async {
    final long = AccueilMenu(
      id: 'fictif_long',
      label: 'Menu fictif au libellé très long pour le test',
      short: 'Inventaire tournant fictif',
      icon: Icons.inventory,
      color: Colors.amber,
      famille: MenuFamille.stock,
      protege: true,
      screen: () => const SizedBox(),
    );
    final f = famillesCompletes();
    f[MenuFamille.stock] = [...f[MenuFamille.stock]!, long];
    for (final p in [AccueilPresentation.metroMosaique, AccueilPresentation.metroBandes]) {
      for (final texte in [1.0, 2.0]) {
        await monterMetro(t, p, largeur: 320, hauteur: 5000, texte: texte, familles: f, pastilles: const {'fictif_long': 999});
        expect(t.takeException(), isNull, reason: '${p.name} ×$texte');
        final l = mesureLibelle(t, find.byKey(const ValueKey('libelle_fictif_long')));
        expect(l.tronque || l.motCoupe, isFalse, reason: '${p.name} ×$texte');
        // Au-delà de ×1,3 (hors de la plage demandée), une 3e ligne est permise plutôt qu'un libellé coupé.
        if (texte <= 1.3) expect(l.lignes, lessThanOrEqualTo(2), reason: '${p.name} ×$texte');
      }
    }
  });

  for (final (taille, nom) in [(TailleEcran.sunmiV2s, 'Sunmi V2s'), (TailleEcran.tablette, 'tablette paysage'), (const TailleEcran('Tablette portrait', Size(1200, 1920), 1.5), 'tablette portrait')]) {
    for (final p in [AccueilPresentation.metroMosaique, AccueilPresentation.metroBandes]) {
      testWidgets('application entière, $nom, ${p.label} : en-tête, recherche, barre du bas ; contenu centré, sans débordement', (t) async {
        taille.appliquer(t);
        final app = AppE2E();
        await app.preparer(prefs: {'hiddenMenuIds': <String>[], PresentationPrefs.cleAccueil: p.name});
        await app.lancer(t);
        expect(await app.seConnecter(t), isTrue);
        await app.attendre(t, const Duration(seconds: 2));
        expect(find.byKey(ValueKey('accueil_metro_${p.name}')), findsOneWidget);
        expect(find.byKey(const Key('accueil_barre_bas')), findsOneWidget);
        expect(find.byKey(const Key('accueil_cloche')), findsOneWidget);
        expect(find.text('Rechercher un menu ou un produit'), findsOneWidget);
        expect(find.byKey(const ValueKey('accueil-ligne-etat')), findsOneWidget);
        final ecran = t.getRect(find.byType(Scaffold).first);
        final corps = t.getRect(find.byKey(ValueKey('accueil_metro_${p.name}')));
        expect(corps.left, greaterThanOrEqualTo(ecran.left));
        expect(corps.right, lessThanOrEqualTo(ecran.right + 0.01));
        expect((corps.left - ecran.left - (ecran.right - corps.right)).abs(), lessThan(1), reason: 'centré');
        final fond = t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor;
        expect(fond, MetroCharte.fond(p));
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });
    }
  }
}
