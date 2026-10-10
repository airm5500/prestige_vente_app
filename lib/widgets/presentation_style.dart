// lib/widgets/presentation_style.dart
// Présentations au choix des listes (Réception BL, Retour fournisseur) :
//   A · Tableau de bord (par défaut), B · Liste groupée, C · Parcours guidé.
// Le choix est mémorisé sur l'appareil et partagé par les deux écrans.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ListPresentation { dashboard, compact, guided }

extension ListPresentationLabel on ListPresentation {
  String get label => switch (this) {
        ListPresentation.dashboard => 'A · Tableau de bord',
        ListPresentation.compact => 'B · Liste groupée',
        ListPresentation.guided => 'C · Parcours guidé',
      };
}

class PresentationPrefs {
  PresentationPrefs._();
  static const _key = 'presentation_listes_v1';

  static Future<ListPresentation> load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_key);
      return ListPresentation.values.asNameMap()[v] ?? ListPresentation.dashboard;
    } catch (_) {
      return ListPresentation.dashboard;
    }
  }

  static Future<void> save(ListPresentation p) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, p.name);
    } catch (_) {}
  }
}

/// Couleurs des présentations (bleu Prestige + ambre pour l'action principale).
class Pal {
  Pal._();
  static const navy = Color(0xFF003366);
  static const amber = Color(0xFFF59E0B);
  static const onAmber = Color(0xFF1F1300);
  static const page = Color(0xFFF2F4F8);
  static const ink = Color(0xFF14213D);
  static const muted = Color(0xFF5B6B82);
  static const line = Color(0xFFE3E8EF);
  static const headerMuted = Color(0xFFC9D6E8);
  static const green = Color(0xFF16A34A);
  static const blue = Color(0xFF2563EB);
}

/// Boutons d'action des présentations (bleu Prestige / ambre), coins arrondis.
final ButtonStyle navyButton = ElevatedButton.styleFrom(
  backgroundColor: Pal.navy,
  foregroundColor: Colors.white,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
);
final ButtonStyle amberButton = ElevatedButton.styleFrom(
  backgroundColor: Pal.amber,
  foregroundColor: Pal.onAmber,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
);
final ButtonStyle outlineButton = OutlinedButton.styleFrom(
  foregroundColor: Pal.navy,
  side: const BorderSide(color: Color(0xFFC5D0DE)),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
);

/// Bouton « Présentation » de la barre du haut.
class PresentationMenuButton extends StatelessWidget {
  final ListPresentation value;
  final ValueChanged<ListPresentation> onChanged;
  final Color color;
  const PresentationMenuButton({super.key, required this.value, required this.onChanged, this.color = Colors.white});

  @override
  Widget build(BuildContext context) => PopupMenuButton<ListPresentation>(
        tooltip: 'Présentation',
        icon: Icon(Icons.dashboard_customize_outlined, color: color),
        initialValue: value,
        onSelected: onChanged,
        itemBuilder: (_) => [
          for (final p in ListPresentation.values)
            CheckedPopupMenuItem(value: p, checked: p == value, child: Text(p.label)),
        ],
      );
}

/// Initiales du grossiste sur une pastille de couleur stable.
class GrossisteAvatar extends StatelessWidget {
  final String name;
  final double size;
  const GrossisteAvatar(this.name, {super.key, this.size = 44});

  static const _colors = [
    (Color(0xFFE3ECF7), Color(0xFF003366)),
    (Color(0xFFE6F4EE), Color(0xFF0B6B45)),
    (Color(0xFFF3E8FA), Color(0xFF6B2A8F)),
    (Color(0xFFFFF1D6), Color(0xFF8A5300)),
    (Color(0xFFFDE7E7), Color(0xFF9B1C1C)),
    (Color(0xFFE0F2F1), Color(0xFF0F5F5A)),
  ];

  static String initials(String name) {
    final words = name.trim().split(RegExp(r'[\s\-_/]+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, words.first.length >= 2 ? 2 : 1).toUpperCase();
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  static (Color, Color) colorsFor(String name) => _colors[name.codeUnits.fold(0, (a, b) => a + b) % _colors.length];

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colorsFor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.27)),
      child: Text(initials(name), style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: size * 0.34)),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  const StatusBadge(this.text, {super.key, required this.fg, required this.bg});

  static StatusBadge enCours() => const StatusBadge('En cours', fg: Color(0xFF8A5300), bg: Color(0xFFFFF1D6));
  static StatusBadge passee() => const StatusBadge('Passée', fg: Color(0xFF1F4F8F), bg: Color(0xFFE3ECF7));
  static StatusBadge nouveau() => const StatusBadge('Nouveau', fg: Color(0xFF0B6B45), bg: Color(0xFFDCF5E7));
  static StatusBadge enSaisie() => const StatusBadge('En saisie', fg: Color(0xFF1F4F8F), bg: Color(0xFFE3ECF7));
  static StatusBadge aCommencer() => const StatusBadge('À commencer', fg: Color(0xFF3D4B60), bg: Color(0xFFE6EBF2));
  static StatusBadge pret() => const StatusBadge('Prêt', fg: Color(0xFF0B6B45), bg: Color(0xFFDCF5E7));

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

/// Tuile de chiffre clé dans l'en-tête bleu.
class KpiTile extends StatelessWidget {
  final String value;
  final String label;
  final bool highlight;
  const KpiTile(this.value, this.label, {super.key, this.highlight = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: highlight ? Pal.amber : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: highlight ? Pal.onAmber : Colors.white)),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: highlight ? Pal.onAmber : const Color(0xFFDCE6F2), fontWeight: highlight ? FontWeight.w500 : null)),
        ]),
      );
}

/// Sélecteur à pastilles blanc sur fond bleu (remplace les onglets).
class SegmentedPills extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  const SegmentedPills({super.key, required this.labels, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Material(
                color: i == selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => onSelected(i),
                  child: SizedBox(
                    height: 40,
                    child: Center(
                      child: Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: i == selected ? Pal.navy : Colors.white,
                          fontWeight: i == selected ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
}

/// En-tête bleu arrondi (présentations A et C), sous la barre d'état.
/// Tablette : fond bleu sur toute la largeur, contenu aligné sur la largeur du corps ([wide] : panneaux).
class NavyHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final bool rounded;
  final bool wide;
  const NavyHeader(
      {super.key, required this.title, this.subtitle, this.actions = const [], this.children = const [], this.rounded = true, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop() && !EmbeddedPane.of(context);
    final inset = Responsive.sideInset(context, wide: wide);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: BoxDecoration(
          color: Pal.navy,
          borderRadius: rounded ? const BorderRadius.vertical(bottom: Radius.circular(24)) : null,
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(4 + inset, 4, 4 + inset, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                if (canPop)
                  IconButton(
                    tooltip: 'Retour',
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  )
                else
                  const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    if (subtitle != null) Text(subtitle!, style: const TextStyle(color: Pal.headerMuted, fontSize: 13)),
                  ]),
                ),
                ...actions,
              ]),
              for (final c in children) Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: c),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Étapes du parcours (présentation C) : l'étape active est blanche ; les autres se touchent si [onTap].
class StepsBar extends StatelessWidget {
  final List<({String title, String detail, VoidCallback? onTap})> steps;
  final int active;
  const StepsBar({super.key, required this.steps, required this.active});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final on = i == active;
      children.add(Expanded(
        child: Material(
          color: on ? Colors.white : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: on ? BorderSide.none : BorderSide(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: s.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ÉTAPE ${i + 1}',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6, color: on ? Pal.navy : Pal.headerMuted)),
                Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? Pal.navy : Colors.white)),
                Text(s.detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: on ? Pal.muted : Pal.headerMuted)),
              ]),
            ),
          ),
        ),
      ));
      if (i < steps.length - 1) {
        children.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Icon(Icons.chevron_right, color: Color(0xFF8FA8C8), size: 18),
        ));
      }
    }
    return Row(children: children);
  }
}

/// Carte blanche arrondie, avec bande de couleur en haut (présentation C).
class SoftCard extends StatelessWidget {
  final Widget child;
  final Color? band;
  final bool highlighted;
  final EdgeInsets padding;
  const SoftCard({super.key, required this.child, this.band, this.highlighted = false, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: highlighted ? Border.all(color: Pal.green, width: 2) : null,
          boxShadow: const [BoxShadow(color: Color(0x1214213D), blurRadius: 8, offset: Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (band != null) Container(height: 6, color: band),
          Padding(padding: padding, child: child),
        ]),
      );
}

/// Barre de progression fine avec légende (lignes, boîtes).
class ThinProgress extends StatelessWidget {
  final double value;
  final String left;
  final String right;
  final Color color;
  const ThinProgress({super.key, required this.value, required this.left, required this.right, this.color = Pal.blue});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(left, style: const TextStyle(fontSize: 13, color: Pal.muted))),
          Text(right, style: const TextStyle(fontSize: 13, color: Pal.muted)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: value.clamp(0, 1), minHeight: 8, backgroundColor: const Color(0xFFE6EBF2), color: color),
        ),
      ]);
}

/// Anneau de progression avec fraction au centre (présentation B).
class RingProgress extends StatelessWidget {
  final int done;
  final int total;
  const RingProgress({super.key, required this.done, required this.total});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 48,
        height: 48,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              value: total == 0 ? 0 : done / total,
              strokeWidth: 5,
              backgroundColor: const Color(0xFFDDE3EA),
              color: done >= total && total > 0 ? Pal.green : Pal.blue,
            ),
          ),
          Text('$done/$total', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Pal.ink)),
        ]),
      );
}

/// Chiffre + libellé (cartes).
class Figure extends StatelessWidget {
  final String value;
  final String label;
  const Figure(this.value, this.label, {super.key});

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(children: [
        TextSpan(text: value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Pal.ink)),
        TextSpan(text: ' $label', style: const TextStyle(fontSize: 13, color: Pal.muted)),
      ]));
}

/// Charge la présentation choisie sur l'appareil (si elle n'est pas imposée) pour un écran intérieur.
mixin PresentationAware<T extends StatefulWidget> on State<T> {
  ListPresentation? get forcedPresentation;
  late ListPresentation style = forcedPresentation ?? ListPresentation.dashboard;

  void loadPresentation() {
    if (forcedPresentation != null) return;
    PresentationPrefs.load().then((p) {
      if (mounted && p != style) setState(() => style = p);
    });
  }
}

/// Cadre d'écran commun aux trois présentations.
/// - A : en-tête bleu arrondi ; [header] (chiffres clés, champ de scan…) dans l'en-tête.
/// - B : barre blanche sobre ; [header] affiché sous la barre, sur fond clair.
/// - C : en-tête bleu droit avec les étapes [steps] ; [header] en dessous des étapes.
/// Tablette (≥ 600 dp) : corps, contenu de l'en-tête et barre du bas centrés à la largeur maximale
/// ([wide] : plus large, pour les grilles de cartes et les panneaux côte à côte) ; téléphone inchangé.
class PresentationScaffold extends StatelessWidget {
  final ListPresentation style;
  final String title;
  final String? subtitle;
  final List<Widget> Function(Color iconColor) actions;
  final List<Widget> header;
  final List<Widget> compactHeader;
  final StepsBar? steps;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool wide;

  const PresentationScaffold({
    super.key,
    required this.style,
    required this.title,
    this.subtitle,
    required this.actions,
    this.header = const [],
    this.compactHeader = const [],
    this.steps,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = bottomNavigationBar == null ? null : BottomBarWidth(wide: wide, child: bottomNavigationBar!);
    if (style == ListPresentation.compact) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _InsetAppBar(
            wide: wide,
            appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Pal.navy,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.navy, fontSize: 18)),
            if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: Pal.muted)),
          ]),
          actions: actions(Pal.navy),
          bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Pal.line)),
        )),
        bottomNavigationBar: bottom,
        floatingActionButton: floatingActionButton,
        body: ContentWidth(
          wide: wide,
          child: Column(children: [
            for (final h in compactHeader) Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: h),
            Expanded(child: body),
          ]),
        ),
      );
    }
    final dashboard = style == ListPresentation.dashboard;
    return Scaffold(
      backgroundColor: dashboard ? Pal.page : const Color(0xFFEEF2F7),
      bottomNavigationBar: bottom,
      floatingActionButton: floatingActionButton,
      body: Column(children: [
        NavyHeader(
          title: title,
          subtitle: subtitle,
          rounded: dashboard,
          wide: wide,
          actions: actions(Colors.white),
          children: [
            if (!dashboard && steps != null) steps!,
            ...header,
          ],
        ),
        Expanded(child: ContentWidth(wide: wide, child: body)),
      ]),
    );
  }
}

/// Barre blanche (B) : fond et filet sur toute la largeur, titre et actions alignés sur le corps.
class _InsetAppBar extends StatelessWidget implements PreferredSizeWidget {
  final PreferredSizeWidget appBar;
  final bool wide;
  const _InsetAppBar({required this.appBar, required this.wide});

  @override
  Size get preferredSize => appBar.preferredSize;

  @override
  Widget build(BuildContext context) {
    final inset = Responsive.sideInset(context, wide: wide);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: inset > 0 ? Colors.white : null,
        border: inset > 0 ? const Border(bottom: BorderSide(color: Pal.line)) : null,
      ),
      child: Padding(padding: EdgeInsets.symmetric(horizontal: inset), child: appBar),
    );
  }
}

/// Bandeau de chiffres clairs (présentation B) : chiffres en couleur sur fond très clair.
class LightFigures extends StatelessWidget {
  final List<(String value, String label, Color color)> items;
  const LightFigures(this.items, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: Pal.line)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          for (final (v, l, c) in items)
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(children: [
                  Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c)),
                  Text(l, style: const TextStyle(fontSize: 11, color: Color(0xFF4A5A70))),
                ]),
              ),
            ),
        ]),
      );
}
