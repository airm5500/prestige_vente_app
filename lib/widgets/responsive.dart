// lib/widgets/responsive.dart
// Points de rupture communs (téléphone / terminal Sunmi, tablette portrait, tablette paysage) :
//   compact < 600 dp : rendu d'origine, strictement inchangé (marges 0, une colonne) ;
//   moyen 600-899 dp : contenu centré à 720 dp, cartes sur 2 colonnes ;
//   large ≥ 900 dp  : contenu centré à 960 dp (1200 pour les grilles / panneaux), 3 colonnes, liste + détail.
// Les aides gardent la même structure de widgets à toutes les tailles : tourner l'appareil ne perd rien.
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum WindowClass { compact, medium, expanded }

class Responsive {
  Responsive._();

  static const double mediumMin = 600;
  static const double expandedMin = 900;

  /// Largeur maximale des fenêtres de dialogue (tablette).
  static const double dialogMaxWidth = 640;

  static WindowClass classOf(double width) => width >= expandedMin
      ? WindowClass.expanded
      : width >= mediumMin
          ? WindowClass.medium
          : WindowClass.compact;

  static WindowClass of(BuildContext context) => classOf(MediaQuery.sizeOf(context).width);
  static bool isCompact(BuildContext context) => of(context) == WindowClass.compact;
  static bool isExpanded(BuildContext context) => of(context) == WindowClass.expanded;

  /// Largeur maximale du contenu (formulaires, listes de lecture) ; [wide] : grilles de cartes et panneaux.
  /// null en compact (toute la largeur, comme avant).
  static double? maxWidth(WindowClass c, {bool wide = false}) => switch (c) {
        WindowClass.compact => null,
        WindowClass.medium => wide ? 840 : 720,
        WindowClass.expanded => wide ? 1200 : 960,
      };

  /// Marge de chaque côté pour centrer le contenu à sa largeur maximale (0 en compact).
  static double sideInset(BuildContext context, {bool wide = false}) {
    final w = MediaQuery.sizeOf(context).width;
    final m = maxWidth(classOf(w), wide: wide);
    return m == null ? 0 : math.max(0, (w - m) / 2);
  }

  /// Nombre de colonnes d'une liste de cartes : 1 / 2 / 3.
  static int columns(BuildContext context, {int compact = 1, int medium = 2, int expanded = 3}) => switch (of(context)) {
        WindowClass.compact => compact,
        WindowClass.medium => medium,
        WindowClass.expanded => expanded,
      };
}

/// Contenu centré à largeur maximale (marges latérales nulles en compact).
class ContentWidth extends StatelessWidget {
  final Widget child;
  final bool wide;
  const ContentWidth({super.key, required this.child, this.wide = false});

  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.symmetric(horizontal: Responsive.sideInset(context, wide: wide)), child: child);
}

/// Barre d'actions fixée en bas : fond sur toute la largeur, boutons centrés à la largeur du contenu.
class BottomBarWidth extends StatelessWidget {
  final Widget child;
  final bool wide;
  final Color color;
  const BottomBarWidth({super.key, required this.child, this.wide = false, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    final inset = Responsive.sideInset(context, wide: wide);
    return DecoratedBox(
      decoration: BoxDecoration(color: inset > 0 ? color : null),
      child: Padding(padding: EdgeInsets.symmetric(horizontal: inset), child: child),
    );
  }
}

/// Cartes rangées par [columns] (alignées en haut, [gap] entre colonnes) ; en une colonne, [cards] tels quels.
List<Widget> cardRows(List<Widget> cards, int columns, {double gap = 10}) {
  if (columns <= 1) return cards;
  return [
    for (var r = 0; r < cards.length; r += columns)
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var c = 0; c < columns; c++) ...[
          if (c > 0) SizedBox(width: gap),
          Expanded(child: r + c < cards.length ? cards[r + c] : const SizedBox.shrink()),
        ],
      ]),
  ];
}

/// Liste de cartes : ListView.separated d'origine en une colonne, rangées de [columns] cartes sinon.
class AdaptiveCardList extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder separatorBuilder;
  final int columns;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final ScrollController? controller;
  final double gap;

  const AdaptiveCardList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.separatorBuilder,
    required this.columns,
    this.padding,
    this.physics,
    this.controller,
    this.gap = 10,
  });

  @override
  Widget build(BuildContext context) {
    if (columns <= 1) {
      return ListView.separated(
        controller: controller,
        physics: physics,
        padding: padding,
        itemCount: itemCount,
        separatorBuilder: separatorBuilder,
        itemBuilder: itemBuilder,
      );
    }
    final rows = (itemCount + columns - 1) ~/ columns;
    return ListView.separated(
      controller: controller,
      physics: physics,
      padding: padding,
      itemCount: rows,
      separatorBuilder: separatorBuilder,
      itemBuilder: (context, r) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var c = 0; c < columns; c++) ...[
          if (c > 0) SizedBox(width: gap),
          Expanded(child: r * columns + c < itemCount ? itemBuilder(context, r * columns + c) : const SizedBox.shrink()),
        ],
      ]),
    );
  }
}

/// Panneau qui se met en page selon sa propre largeur (MediaQuery ramenée à la taille du panneau).
class PaneSize extends StatelessWidget {
  final Widget child;
  const PaneSize({super.key, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final mq = MediaQuery.of(context);
        return MediaQuery(data: mq.copyWith(size: Size(box.maxWidth, box.maxHeight)), child: child);
      });
}

/// Liste + détail côte à côte (large) : liste de largeur fixe à gauche, détail à droite.
class ListDetail extends StatelessWidget {
  final Widget list;
  final Widget detail;
  final double listWidth;
  const ListDetail({super.key, required this.list, required this.detail, this.listWidth = 360});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: listWidth, child: PaneSize(child: list)),
        const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE3E8EF)),
        Expanded(child: PaneSize(child: detail)),
      ]);
}

/// Thème adapté à la taille de l'écran (à placer dans MaterialApp.builder) :
/// en moyen / large, les fenêtres de dialogue restent à [Responsive.dialogMaxWidth] au plus.
class ResponsiveTheme extends StatelessWidget {
  final Widget child;
  const ResponsiveTheme({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = MediaQuery.sizeOf(context).width;
    if (Responsive.classOf(w) == WindowClass.compact) return Theme(data: theme, child: child);
    final side = math.max(40.0, (w - Responsive.dialogMaxWidth) / 2);
    return Theme(
      data: theme.copyWith(dialogTheme: theme.dialogTheme.copyWith(insetPadding: EdgeInsets.symmetric(horizontal: side, vertical: 24))),
      child: child,
    );
  }
}

/// Contenu affiché dans le panneau de détail d'une page « liste + détail » : pas de bouton Retour.
class EmbeddedPane extends InheritedWidget {
  const EmbeddedPane({super.key, required super.child});

  static bool of(BuildContext context) => context.getInheritedWidgetOfExactType<EmbeddedPane>() != null;

  @override
  bool updateShouldNotify(EmbeddedPane oldWidget) => false;
}

/// Cartes suivies chacune d'un espace [spacing] (forme d'origine en une colonne), rangées sinon.
List<Widget> cardColumn(List<Widget> cards, int columns, {double spacing = 12, double gap = 10}) {
  if (columns <= 1) return [for (final c in cards) ...[c, SizedBox(height: spacing)]];
  return cardRows([for (final c in cards) Padding(padding: EdgeInsets.only(bottom: spacing), child: c)], columns, gap: gap);
}
