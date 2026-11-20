// lib/accueil/accueil_metro.dart
// 5.2.0 — Présentations « Metro » de l'accueil (Réglages › Apparence › Accueil) :
//   · Metro mosaïque : fond bleu nuit, tuiles de couleur pleine (icône en haut à gauche, libellé en bas à gauche) ;
//     grille de 4 colonnes (terminal), 6 (tablette portrait), deux groupes de 4 côte à côte (paysage) ; les 2 premiers
//     favoris en 2×2 avec le libellé complet en sous-titre ; tuile élargie si le libellé ne tient pas sur une ligne ;
//     trous comblés.
//   · Metro bandes : bandes de 58 dp de haut, largeur selon le libellé, rangées justifiées, fond blanc, ordre strict.
// Communs : familles, cadenas des menus protégés, pastilles des compteurs, couleurs assombries pour un contraste
// ≥ 4,5:1 avec le texte blanc ; calcul sur la largeur réelle (LayoutBuilder) et le facteur de texte ; libellés jamais
// tronqués ni sur 3 lignes. Clés `tuile_<id>` (comme la présentation actuelle), appui long = favoris / organiser.
// L'en-tête, la barre du bas et le choix des menus (droits, menus masqués) restent ceux de l'accueil.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Couleurs et mesures communes aux présentations Metro.
class MetroCharte {
  MetroCharte._();

  /// Fond de la mosaïque (bleu nuit).
  static const fondMosaique = Color(0xFF0B1B2E);

  static Color fond(AccueilPresentation p) => p == AccueilPresentation.metroMosaique ? fondMosaique : Colors.white;

  /// Rapport de contraste minimal du texte blanc sur une tuile (WCAG AA, texte normal).
  static const contrasteMin = 4.5;

  static final Map<int, Color> _pleines = {};

  /// Contraste du blanc sur [c] (WCAG 2.x).
  static double contrasteBlanc(Color c) => 1.05 / (c.computeLuminance() + 0.05);

  /// Couleur pleine lisible sous un texte blanc : [c] assombrie si besoin (lime, orange clair…), teinte conservée.
  static Color pleine(Color c) => _pleines.putIfAbsent(c.toARGB32(), () {
        var h = HSLColor.fromColor(c.withValues(alpha: 1));
        while (contrasteBlanc(h.toColor()) < contrasteMin && h.lightness > 0.02) {
          h = h.withLightness(math.max(0, h.lightness - 0.02));
        }
        return h.toColor();
      });
}

/// Mesure du texte comme le widget Text l'affiche (style par défaut fusionné, facteur de texte de l'écran).
class _Mesure {
  final TextStyle base;
  final TextScaler scaler;
  _Mesure(BuildContext context)
      : base = DefaultTextStyle.of(context).style,
        scaler = MediaQuery.textScalerOf(context);

  final _cache = <String, TextPainter>{};

  TextPainter _tp(String s, TextStyle st, double maxWidth) =>
      _cache.putIfAbsent('${st.hashCode}|$maxWidth|$s', () => TextPainter(
            text: TextSpan(text: s, style: base.merge(st)),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout(maxWidth: maxWidth));

  double largeur(String s, TextStyle st) => _tp(s, st, double.infinity).width;

  /// Hauteur d'une ligne.
  double ligne(TextStyle st) => _tp('Ég', st, double.infinity).height;

  /// Nombre de lignes de [s] sur [largeurMax] ; [AccueilMetro._motTropLong] si un mot ne tient pas entier.
  int lignes(String s, TextStyle st, double largeurMax) {
    if (largeurMax <= 0) return AccueilMetro._motTropLong;
    for (final mot in s.split(' ')) {
      if (largeur(mot, st) > largeurMax) return AccueilMetro._motTropLong;
    }
    return _tp(s, st, largeurMax).computeLineMetrics().length;
  }

  double hauteur(String s, TextStyle st, double largeurMax) => _tp(s, st, largeurMax).height;

  void dispose() {
    for (final tp in _cache.values) {
      tp.dispose();
    }
  }
}

/// Corps de l'accueil en présentation Metro (sous l'en-tête de l'accueil).
class AccueilMetro extends StatelessWidget {
  final AccueilPresentation presentation;

  /// Menus affichés par famille (droits, menus masqués et ordre déjà appliqués par l'accueil).
  final Map<MenuFamille, List<AccueilMenu>> familles;

  /// Favoris visibles, dans l'ordre : les 2 premiers en grand dans la mosaïque.
  final List<String> favoris;
  final Map<String, int> pastilles;

  /// Marge latérale (tablette : contenu centré).
  final double inset;
  final void Function(AccueilMenu) onOpen;
  final void Function(AccueilMenu) onLongPress;

  const AccueilMetro({
    super.key,
    required this.presentation,
    required this.familles,
    required this.favoris,
    required this.pastilles,
    required this.inset,
    required this.onOpen,
    required this.onLongPress,
  }) : assert(presentation != AccueilPresentation.actuelle);

  bool get _mosaique => presentation == AccueilPresentation.metroMosaique;

  // Mosaïque
  static const gap = 6.0;
  static const pad = 9.0;
  static const icone = 28.0;

  /// Marges verticales d'une tuile (haut [pad], bas [pad] - 1).
  static const _marges = 2 * pad - 1;
  static const iconeGrande = 46.0;
  static const styleCourt = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.15);
  static const styleGrand = TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.15);
  static const styleSousTitre = TextStyle(fontSize: 12.5);
  // Bandes
  static const hauteurBande = 58.0;
  static const styleBande = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
  static const iconeBande = 26.0;
  // Pastille / cadenas
  static const stylePastille = TextStyle(fontSize: 12, fontWeight: FontWeight.bold);
  static const cadenas = 15.0;

  /// Largeur à partir de laquelle les familles se répartissent sur deux colonnes (tablette paysage).
  static const largeurDeuxGroupes = 880.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('accueil_metro_${presentation.name}'),
      padding: EdgeInsets.fromLTRB(16 + inset, 4, 16 + inset, 0),
      child: LayoutBuilder(builder: (context, c) {
        final mesure = _Mesure(context);
        try {
          return _groupes(context, c.maxWidth, mesure);
        } finally {
          mesure.dispose();
        }
      }),
    );
  }

  Widget _groupes(BuildContext context, double w, _Mesure mesure) {
    final nbCol = w >= largeurDeuxGroupes ? 2 : 1;
    const gapG = 24.0;
    final wg = (w - gapG * (nbCol - 1)) / nbCol;
    final principaux = favoris.take(2).toSet();
    final groupes = <(MenuFamille, Widget, double)>[];
    for (final f in MenuFamille.values) {
      final menus = familles[f] ?? const <AccueilMenu>[];
      if (menus.isEmpty) continue;
      final (widget, h) = _mosaique ? _grille(menus, wg, principaux, mesure) : _bandes(menus, wg, mesure);
      groupes.add((f, widget, h + mesure.hauteur(f.label, _styleTitre, wg) + 26));
    }
    // Familles réparties dans la colonne la plus courte (tablette paysage), dans l'ordre.
    final cols = List.generate(nbCol, (_) => <Widget>[]);
    final hauteurs = List.filled(nbCol, 0.0);
    for (final (f, widget, h) in groupes) {
      var i = 0;
      for (var k = 1; k < nbCol; k++) {
        if (hauteurs[k] < hauteurs[i] - 1) i = k;
      }
      cols[i]
        ..add(_titre(f))
        ..add(widget);
      hauteurs[i] += h;
    }
    if (nbCol == 1) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: cols[0]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < nbCol; i++) ...[
        if (i > 0) const SizedBox(width: gapG),
        SizedBox(width: wg, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: cols[i])),
      ],
    ]);
  }

  TextStyle get _styleTitre => _mosaique
      ? const TextStyle(fontSize: 18, fontWeight: FontWeight.w300, color: Colors.white, letterSpacing: 0.3)
      : const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Pal.muted);

  Widget _titre(MenuFamille f) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Text(_mosaique ? f.label : f.label.toUpperCase(), key: ValueKey('metro_famille_${f.name}'), style: _styleTitre),
      );

  /// Largeur occupée en haut à droite par le cadenas et la pastille d'un menu (0 : rien).
  double _decor(AccueilMenu m, _Mesure mesure) {
    final n = pastilles[m.id];
    var l = 0.0;
    if (m.protege) l += cadenas + 4;
    if (n != null) l += math.max(22, mesure.largeur('$n', stylePastille) + 12) + 4;
    return l;
  }

  // ---------------------------------------------------------------------------
  // Mosaïque : tuiles 1×1, n×1 et 2×2 (ou plus large si le libellé l'exige)
  // ---------------------------------------------------------------------------
  (Widget, double) _grille(List<AccueilMenu> menus, double w, Set<String> principaux, _Mesure mesure) {
    final g = MetroGrille.calculer(
      ids: [for (final m in menus) m.id],
      colonnes: w >= 600 ? 6 : 4,
      largeur: w,
      taille: (id, cell, unite, colonnes) {
        final m = menus.firstWhere((x) => x.id == id);
        return _taille(m, cell, unite, colonnes, principaux.contains(id), mesure);
      },
      // Hauteur d'une rangée : carrée, sauf si l'icône et une ligne de libellé n'y tiennent pas (petit écran, grand texte).
      hauteurUnite: (cell) => math.max(cell, (_marges + icone + 4 + mesure.ligne(styleCourt)).ceilToDouble()),
    );
    final enfants = <Widget>[
      for (final m in menus)
        Positioned(
          left: g.gauche(m.id),
          top: g.haut(m.id),
          width: g.largeur(m.id),
          height: g.hauteur(m.id),
          child: _tuile(m, principaux.contains(m.id),
              reduit: mesure.lignes(m.short, principaux.contains(m.id) ? styleGrand : styleCourt, g.largeur(m.id) - 2 * pad) >= _motTropLong),
        ),
    ];
    return (SizedBox(height: g.hauteurTotale, child: Stack(children: enfants)), g.hauteurTotale);
  }

  /// Taille (colonnes, rangées) d'une tuile : la plus petite où le libellé tient sans coupure.
  (int, int) _taille(AccueilMenu m, double cell, double unite, int colonnes, bool principal, _Mesure mesure) {
    double largeurSpan(int s) => s * cell + (s - 1) * gap;
    final decor = _decor(m, mesure);
    final ligne = mesure.ligne(styleCourt);
    if (principal) {
      // Favori principal : 2×2, plus large (ou plus haut, texte très agrandi) si le titre ou le libellé complet
      // ne tiennent pas.
      final sous = m.label != m.short;
      for (var rangs = 2; rangs <= 3; rangs++) {
        final hDispo = rangs * unite + (rangs - 1) * gap - _marges - iconeGrande - 2;
        for (var s = 2; s <= colonnes; s++) {
          final lt = largeurSpan(s) - 2 * pad;
          if (largeurSpan(s) < pad + iconeGrande + 6 + decor + 6) continue;
          final l1 = mesure.lignes(m.short, styleGrand, lt);
          final l2 = sous ? mesure.lignes(m.label, styleSousTitre, lt) : 0;
          if (l1 > 2 || l2 > 2) continue;
          final h = mesure.hauteur(m.short, styleGrand, lt) + (sous ? 2 + mesure.hauteur(m.label, styleSousTitre, lt) : 0);
          if (h <= hDispo) return (s, rangs);
        }
      }
      return (colonnes, 3);
    }
    // Une rangée d'abord (1×1 si une seule ligne, sinon plus large, 2 lignes au plus), puis 2 rangées (petit écran,
    // grand texte), puis 3 en dernier recours (texte très agrandi) : jamais de libellé coupé ni de débordement.
    for (var rangs = 1; rangs <= 3; rangs++) {
      final hTexte = rangs * unite + (rangs - 1) * gap - _marges - icone - 2;
      final lignesMax = rangs <= 2 ? (hTexte / ligne).floor().clamp(1, 2) : (hTexte / ligne).floor();
      for (var s = 1; s <= colonnes; s++) {
        if (largeurSpan(s) < pad + icone + 6 + decor + (decor > 0 ? 6 : 0)) continue;
        final l = mesure.lignes(m.short, styleCourt, largeurSpan(s) - 2 * pad);
        if (l <= (s == 1 && rangs == 1 ? 1 : lignesMax)) return (s, rangs);
      }
    }
    return (colonnes, 3);
  }

  /// [_Mesure.lignes] : un mot ne tient pas entier sur toute la largeur.
  static const _motTropLong = 99;

  /// Libellé ; [reduit] (texte très agrandi, au-delà de ×1,3 : un mot plus large que la tuile entière) : sur une ligne,
  /// réduit pour tenir plutôt que coupé au milieu d'un mot.
  static Widget _libelle(AccueilMenu m, TextStyle style, {required bool reduit, int? maxLines}) {
    final texte = Text(m.short, key: ValueKey('libelle_${m.id}'), maxLines: reduit ? 1 : maxLines, softWrap: !reduit, style: style);
    return reduit ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: texte) : texte;
  }

  Widget _tuile(AccueilMenu m, bool grand, {bool reduit = false}) {
    final nb = pastilles[m.id];
    return Tooltip(
      message: m.label,
      child: Material(
        color: MetroCharte.pleine(m.color),
        borderRadius: BorderRadius.circular(3),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('tuile_${m.id}'),
          onTap: () => onOpen(m),
          onLongPress: () => onLongPress(m),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(pad, pad, pad, pad - 1),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(alignment: Alignment.topLeft, child: Icon(m.icon, color: Colors.white, size: grand ? iconeGrande : icone)),
                const Spacer(),
                _libelle(m, (grand ? styleGrand : styleCourt).copyWith(color: Colors.white), reduit: reduit),
                if (grand && m.label != m.short)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(m.label,
                        key: ValueKey('sous_titre_${m.id}'), style: styleSousTitre.copyWith(color: Colors.white.withValues(alpha: 0.88))),
                  ),
              ]),
            ),
            Positioned(top: 6, right: 6, child: _decorWidget(m, nb)),
          ]),
        ),
      ),
    );
  }

  Widget _decorWidget(AccueilMenu m, int? nb) => Row(mainAxisSize: MainAxisSize.min, children: [
        if (m.protege) Icon(Icons.lock, key: ValueKey('cadenas_${m.id}'), size: cadenas, color: Colors.white),
        if (m.protege && nb != null) const SizedBox(width: 4),
        if (nb != null) _pastille(m.id, nb),
      ]);

  static Widget _pastille(String id, int n) => Container(
        key: ValueKey('pastille_$id'),
        constraints: const BoxConstraints(minWidth: 22),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
        child: Text('$n', textAlign: TextAlign.center, style: stylePastille.copyWith(color: const Color(0xFFDC2626))),
      );

  // ---------------------------------------------------------------------------
  // Bandes : largeur selon le libellé, rangées justifiées, ordre strict
  // ---------------------------------------------------------------------------
  (Widget, double) _bandes(List<AccueilMenu> menus, double w, _Mesure mesure) {
    const gapB = 6.0;
    const fixe = 14.0 + iconeBande + 10 + 12 + 2; // marges, icône, espace, marge droite, arrondi
    final rangs = <List<(AccueilMenu, double, int)>>[];
    var courant = <(AccueilMenu, double, int)>[];
    var occ = 0.0;
    for (final m in menus) {
      final naturelle = fixe + mesure.largeur(m.short, styleBande) + _decor(m, mesure);
      final l = math.min(naturelle, w);
      // Libellé plus large que la rangée entière (très grand texte) : 2 lignes, jamais coupé.
      final lignes = naturelle > w ? math.max(1, mesure.lignes(m.short, styleBande, w - fixe - _decor(m, mesure))) : 1;
      // lignes = _motTropLong : un mot plus large que la rangée entière (texte très agrandi) → libellé réduit.
      if (courant.isNotEmpty && occ + gapB + l > w) {
        rangs.add(courant);
        courant = [];
        occ = 0;
      }
      occ = courant.isEmpty ? l : occ + gapB + l;
      courant.add((m, l, lignes));
    }
    if (courant.isNotEmpty) rangs.add(courant);
    final hauteurs = [
      for (final r in rangs)
        math.max(
            hauteurBande,
            [for (final e in r) (e.$3 >= _motTropLong ? mesure.ligne(styleBande) : mesure.hauteur(e.$1.short, styleBande, w - fixe - _decor(e.$1, mesure))) + 14]
                .reduce(math.max)
                .ceilToDouble()),
    ];
    final h = hauteurs.fold<double>(0, (a, b) => a + b) + (rangs.length - 1) * gapB;
    final widget = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < rangs.length; i++) ...[
        if (i > 0) const SizedBox(height: gapB),
        SizedBox(
          height: hauteurs[i],
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var j = 0; j < rangs[i].length; j++) ...[
              if (j > 0) const SizedBox(width: gapB),
              Expanded(flex: math.max(1, (rangs[i][j].$2 * 10).round()), child: _bande(rangs[i][j].$1, rangs[i][j].$3)),
            ],
          ]),
        ),
      ],
    ]);
    return (widget, h);
  }

  Widget _bande(AccueilMenu m, int lignes) {
    final nb = pastilles[m.id];
    return Tooltip(
      message: m.label,
      child: Material(
        color: MetroCharte.pleine(m.color),
        borderRadius: BorderRadius.circular(4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('tuile_${m.id}'),
          onTap: () => onOpen(m),
          onLongPress: () => onLongPress(m),
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 12),
            child: Row(children: [
              Icon(m.icon, color: Colors.white, size: iconeBande),
              const SizedBox(width: 10),
              Expanded(
                child: _libelle(m, styleBande.copyWith(color: Colors.white), reduit: lignes >= _motTropLong, maxLines: lignes),
              ),
              if (m.protege) ...[
                const SizedBox(width: 4),
                Icon(Icons.lock, key: ValueKey('cadenas_${m.id}'), size: cadenas, color: Colors.white),
              ],
              if (nb != null) ...[const SizedBox(width: 4), _pastille(m.id, nb)],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Placement de la mosaïque (sans widget, testable) : tailles, placement « dense » dans l'ordre, rangées d'une
/// ligne justifiées (les tuiles les plus étroites s'élargissent d'abord), trous restants comblés par la tuile voisine.
class MetroGrille {
  final int colonnes;
  final double cellule;
  final double unite;

  /// (colonnes, rangées) de chaque tuile.
  final Map<String, (int, int)> taille;

  /// (rangée, colonne) de chaque tuile.
  final Map<String, (int, int)> position;
  final int rangees;

  MetroGrille._(this.colonnes, this.cellule, this.unite, this.taille, this.position, this.rangees);

  static const gap = AccueilMetro.gap;

  static double _largeurTotale(double cell, int s) => s * cell + (s - 1) * gap;

  double gauche(String id) => position[id]!.$2 * (cellule + gap);
  double haut(String id) => position[id]!.$1 * (unite + gap);
  double largeur(String id) => _largeurTotale(cellule, taille[id]!.$1);
  double hauteur(String id) => taille[id]!.$2 * unite + (taille[id]!.$2 - 1) * gap;
  double get hauteurTotale => rangees == 0 ? 0 : rangees * unite + (rangees - 1) * gap;

  /// Cases occupées : [rangée][colonne] → id (null : trou).
  late final List<List<String?>> cases = [
    for (var r = 0; r < rangees; r++)
      [
        for (var c = 0; c < colonnes; c++)
          () {
            for (final e in position.entries) {
              final (pr, pc) = e.value;
              final (tw, th) = taille[e.key]!;
              if (r >= pr && r < pr + th && c >= pc && c < pc + tw) return e.key;
            }
            return null;
          }(),
      ],
  ];

  static MetroGrille calculer({
    required List<String> ids,
    required int colonnes,
    required double largeur,
    required (int, int) Function(String id, double cellule, double unite, int colonnes) taille,
    required double Function(double cellule) hauteurUnite,
  }) {
    final n = colonnes;
    final cell = (largeur - gap * (n - 1)) / n;
    final unite = hauteurUnite(cell);
    final tailles = <String, (int, int)>{for (final id in ids) id: _borner(taille(id, cell, unite, n), n)};
    final occ = <List<String?>>[];
    final pos = <String, (int, int)>{};

    void agrandir(int r) {
      while (occ.length <= r) {
        occ.add(List<String?>.filled(n, null));
      }
    }

    bool libre(int r, int c, int cw, int rh) {
      if (c + cw > n) return false;
      agrandir(r + rh - 1);
      for (var i = r; i < r + rh; i++) {
        for (var j = c; j < c + cw; j++) {
          if (occ[i][j] != null) return false;
        }
      }
      return true;
    }

    void poser(String id, int r, int c) {
      final (cw, rh) = tailles[id]!;
      for (var i = r; i < r + rh; i++) {
        for (var j = c; j < c + cw; j++) {
          occ[i][j] = id;
        }
      }
      pos[id] = (r, c);
    }

    // 1. Placement dense : premier emplacement libre, dans l'ordre de l'accueil.
    for (final id in ids) {
      final (cw, rh) = tailles[id]!;
      var place = false;
      for (var r = 0; !place; r++) {
        for (var c = 0; c < n && !place; c++) {
          if (libre(r, c, cw, rh)) {
            poser(id, r, c);
            place = true;
          }
        }
      }
    }
    while (occ.isNotEmpty && occ.last.every((e) => e == null)) {
      occ.removeLast();
    }

    // 2. Rangées faites seulement de tuiles d'une ligne : place libre répartie (les plus étroites d'abord).
    for (var r = 0; r < occ.length; r++) {
      final ligne = <String>[];
      for (final e in occ[r]) {
        if (e != null && !ligne.contains(e)) ligne.add(e);
      }
      if (ligne.isEmpty || ligne.any((id) => tailles[id]!.$2 != 1 || pos[id]!.$1 != r)) continue;
      var libres = n - ligne.fold<int>(0, (a, id) => a + tailles[id]!.$1);
      if (libres <= 0) continue;
      while (libres > 0) {
        var k = ligne.length - 1;
        for (var i = ligne.length - 1; i >= 0; i--) {
          if (tailles[ligne[i]]!.$1 < tailles[ligne[k]]!.$1) k = i;
        }
        tailles[ligne[k]] = (tailles[ligne[k]]!.$1 + 1, 1);
        libres--;
      }
      occ[r] = List<String?>.filled(n, null);
      var c = 0;
      for (final id in ligne) {
        poser(id, r, c);
        c += tailles[id]!.$1;
      }
    }

    // 3. Trous restants : la tuile de gauche s'élargit si la colonne est libre sur toute sa hauteur, sinon celle de
    //    droite s'étend vers la gauche, sinon celle du dessus (une rangée) descend si le trou couvre sa largeur.
    bool colonneLibre(String id, int c) {
      final (r0, _) = pos[id]!;
      for (var i = r0; i < r0 + tailles[id]!.$2; i++) {
        if (occ[i][c] != null) return false;
      }
      return true;
    }

    var change = true;
    while (change) {
      change = false;
      for (var r = 0; r < occ.length; r++) {
        for (var c = 0; c < n; c++) {
          if (occ[r][c] != null) continue;
          final g = c > 0 ? occ[r][c - 1] : null;
          final d = c < n - 1 ? occ[r][c + 1] : null;
          if (g != null && pos[g]!.$2 + tailles[g]!.$1 == c && colonneLibre(g, c)) {
            tailles[g] = (tailles[g]!.$1 + 1, tailles[g]!.$2);
            poser(g, pos[g]!.$1, pos[g]!.$2);
            change = true;
          } else if (d != null && pos[d]!.$2 == c + 1 && colonneLibre(d, c)) {
            tailles[d] = (tailles[d]!.$1 + 1, tailles[d]!.$2);
            poser(d, pos[d]!.$1, c);
            change = true;
          } else if (r > 0 && occ[r - 1][c] != null) {
            final h = occ[r - 1][c]!;
            final (hr, hc) = pos[h]!;
            final (hw, hh) = tailles[h]!;
            if (hh == 1 && hr == r - 1 && [for (var j = hc; j < hc + hw; j++) occ[r][j]].every((e) => e == null)) {
              tailles[h] = (hw, 2);
              poser(h, hr, hc);
              change = true;
            }
          }
        }
      }
    }
    return MetroGrille._(n, cell, unite, tailles, pos, occ.length);
  }

  static (int, int) _borner((int, int) t, int n) => (t.$1.clamp(1, n), t.$2.clamp(1, 3));
}
