// Aides des tests de la présentation de l'accueil 5.2.0 (Actuelle / Metro mosaïque / Metro bandes), données fictives.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/accueil/accueil_metro.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Tous les menus de l'accueil par famille (ordre par défaut), « Borne » de l'administrateur comprise.
Map<MenuFamille, List<AccueilMenu>> famillesCompletes({List<String> masques = const []}) =>
    avecMenusAdmin(menusByFamille(const [], masques), admin: true);

/// Compteurs fictifs : un nombre à 3 chiffres (pastille la plus large) et un à 1 chiffre.
const pastillesFictives = {'prevente': 128, 'bl_control': 7};

/// Monte le corps Metro seul, sur [largeur] dp et avec le facteur de texte [texte] (défilant, comme l'accueil).
Future<List<AccueilMenu>> monterMetro(
  WidgetTester t,
  AccueilPresentation p, {
  double largeur = 360,
  double hauteur = 800,
  double texte = 1.0,
  Map<MenuFamille, List<AccueilMenu>>? familles,
  List<String> favoris = AccueilFavoris.parDefaut,
  Map<String, int> pastilles = pastillesFictives,
  void Function(AccueilMenu)? onOpen,
  void Function(AccueilMenu)? onLongPress,
}) async {
  t.view.physicalSize = Size(largeur, hauteur) * 2;
  t.view.devicePixelRatio = 2;
  t.platformDispatcher.textScaleFactorTestValue = texte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  final f = familles ?? famillesCompletes();
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      backgroundColor: MetroCharte.fond(p),
      body: ListView(children: [
        AccueilMetro(
          presentation: p,
          familles: f,
          favoris: favoris,
          pastilles: pastilles,
          inset: 0,
          onOpen: onOpen ?? (_) {},
          onLongPress: onLongPress ?? (_) {},
        ),
      ]),
    ),
  ));
  await t.pump();
  return [for (final l in f.values) ...l];
}

/// Identifiants des tuiles `tuile_<id>` construites.
Set<String> tuilesConstruites() => {
      for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('tuile_')).evaluate())
        (e.widget.key! as ValueKey<String>).value.substring(6),
    };

/// Libellé [k] (Text) : nombre de lignes affichées, mot coupé ou texte tronqué (RenderParagraph réel).
({int lignes, bool tronque, bool motCoupe}) mesureLibelle(WidgetTester t, Finder k) {
  final rp = t.renderObject<RenderParagraph>(find.descendant(of: k, matching: find.byType(RichText)).first);
  final largeur = rp.size.width;
  final tp = TextPainter(text: rp.text, textDirection: TextDirection.ltr, textScaler: rp.textScaler)..layout(maxWidth: largeur);
  final lignes = tp.computeLineMetrics().length;
  final plein = TextPainter(text: rp.text, textDirection: TextDirection.ltr, textScaler: rp.textScaler)..layout(maxWidth: largeur);
  var motCoupe = false;
  final texte = rp.text.toPlainText();
  for (final mot in texte.split(' ')) {
    final m = TextPainter(text: TextSpan(text: mot, style: (rp.text as TextSpan).style), textDirection: TextDirection.ltr, textScaler: rp.textScaler)
      ..layout();
    if (m.width > largeur + 0.01) motCoupe = true;
    m.dispose();
  }
  final tronque = rp.didExceedMaxLines || plein.height > rp.size.height + 0.5;
  tp.dispose();
  plein.dispose();
  return (lignes: lignes, tronque: tronque, motCoupe: motCoupe);
}
