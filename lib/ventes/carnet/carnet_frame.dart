// lib/ventes/carnet/carnet_frame.dart
// Cadre commun des étapes de la Vente Carnet (A / B / C) : barre d'étapes
// Client → Bon & ayant droit → Produits → Valider (retour possible), pied fixe, carte client.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_controller.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

typedef CarnetStepInfo = ({String title, String short, String detail, VoidCallback? onTap});

/// Données communes transmises par l'écran à chaque étape.
class CarnetFrame {
  final ListPresentation style;

  /// Étape active (0 client, 1 bon, 2 produits, 3 valider).
  final int active;
  final List<CarnetStepInfo> steps;
  final List<Widget> Function(Color iconColor) actions;

  const CarnetFrame({required this.style, required this.active, required this.steps, required this.actions});

  bool get compact => style == ListPresentation.compact;
  bool get guided => style == ListPresentation.guided;

  /// Bouton principal : ambre en C, bleu sinon.
  ButtonStyle get mainButton => guided ? amberButton : navyButton;

  Widget scaffold({
    required String title,
    String? subtitle,
    List<Widget> header = const [],
    List<Widget>? compactHeader,
    required Widget body,
    Widget? bottom,
    bool pills = true,
    bool wide = false,
  }) =>
      PresentationScaffold(
        style: style,
        wide: wide,
        title: title,
        subtitle: subtitle,
        actions: actions,
        steps: StepsBar(active: active, steps: [for (final s in steps) (title: s.title, detail: s.detail, onTap: s.onTap)]),
        header: [
          if (style == ListPresentation.dashboard && pills) CarnetStepPills(steps: steps, active: active, dark: true),
          ...header,
        ],
        compactHeader: [CarnetStepPills(steps: steps, active: active, dark: false), ...(compactHeader ?? header)],
        body: body,
        bottomNavigationBar: bottom,
      );
}

/// Barre d'étapes courte (A et B) : étape faite en vert, étape active en évidence.
class CarnetStepPills extends StatelessWidget {
  final List<CarnetStepInfo> steps;
  final int active;
  final bool dark;
  const CarnetStepPills({super.key, required this.steps, required this.active, required this.dark});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final on = i == active, done = i < active;
      final Color bg, fg;
      if (on) {
        bg = dark ? Pal.amber : Pal.navy;
        fg = dark ? Pal.onAmber : Colors.white;
      } else if (done) {
        bg = dark ? const Color(0x5916A34A) : const Color(0xFFE6F4EA);
        fg = dark ? Colors.white : const Color(0xFF166534);
      } else {
        bg = dark ? Colors.white.withValues(alpha: 0.12) : Pal.page;
        fg = dark ? Pal.headerMuted : Pal.muted;
      }
      if (i > 0) children.add(const SizedBox(width: 4));
      children.add(Expanded(
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: on ? null : s.onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 34),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
              child: Text(
                '${done ? '✓' : '${i + 1}'} ${s.short}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: fg, fontWeight: on ? FontWeight.bold : FontWeight.w500),
              ),
            ),
          ),
        ),
      ));
    }
    return Row(children: children);
  }
}

/// Pied fixe en bas de l'écran (actions principales, ≥ 48 px).
class CarnetBottomBar extends StatelessWidget {
  final Widget child;
  const CarnetBottomBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Material(
        elevation: 8,
        color: Colors.white,
        child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), child: child)),
      );
}

/// Nom affiché d'un client / ayant droit (nom complet ou « NOM Prénom »).
String carnetName(String full, String first, String last) => full.trim().isNotEmpty ? full.trim() : '$first $last'.trim();

/// Carte client permanente de l'étape Produits : client → ayant droit, carnet(s), bon, lien « ✎ Bon ».
class CarnetClientBanner extends StatelessWidget {
  final CarnetController controller;
  final bool dark;
  final VoidCallback? onBon;
  const CarnetClientBanner({super.key, required this.controller, required this.dark, this.onBon});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final cl = c.client, ad = c.ayantDroit;
    final client = cl == null ? '—' : carnetName(cl.fullName, cl.strFIRSTNAME, cl.strLASTNAME);
    final self = ad == null || ad.lgAYANTSDROITSID == cl?.lgCLIENTID;
    final who = self ? client : '$client → ${carnetName(ad.fullName, ad.strFIRSTNAME, ad.strLASTNAME)}';
    final tps = [
      for (final tp in c.activeTps) '${tp.tpFullName} ${tp.taux} % · bon ${(c.bons[tp.compteTp] ?? '').isEmpty ? '—' : c.bons[tp.compteTp]}',
    ].join('  ·  ');
    final fg = dark ? Colors.white : Pal.ink;
    final muted = dark ? Pal.headerMuted : Pal.muted;
    return Container(
      key: const ValueKey('carnet-carte-client'),
      padding: const EdgeInsets.fromLTRB(12, 6, 2, 6),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.10) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: dark ? null : Border.all(color: Pal.line),
      ),
      child: Row(children: [
        Icon(Icons.badge_outlined, size: 20, color: muted),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 14.5)),
            Text(tps.isEmpty ? 'Aucun carnet' : tps, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 12)),
          ]),
        ),
        TextButton.icon(
          key: const ValueKey('carnet-retour-bons'),
          style: TextButton.styleFrom(
            foregroundColor: dark ? Colors.white : Pal.navy,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          onPressed: onBon,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Bon'),
        ),
      ]),
    );
  }
}
