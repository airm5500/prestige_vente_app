// lib/ventes/assurance/assurance_frame.dart
// Cadre commun des étapes de la Pré-vente Assurance (présentations A / B / C) : barre d'étapes
// Client → Couverture → Produits → Encaisser (retour possible aux étapes précédentes), carte client
// permanente, bandeau d'état du panier.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_controller.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';

/// Ce que l'écran transmet à chaque étape : présentation, actions de l'en-tête, retour par la barre.
class AssuranceFrame {
  final ListPresentation style;
  final List<Widget> Function(Color iconColor) actions;

  /// Action d'une étape touchée dans la barre (null = non disponible).
  final VoidCallback? Function(int index) stepTap;

  /// Opération en cours hors panier (fine barre de progression).
  final bool progress;

  const AssuranceFrame({required this.style, required this.actions, required this.stepTap, this.progress = false});

  bool get compact => style == ListPresentation.compact;
  bool get guided => style == ListPresentation.guided;

  /// Action principale : bleu (A, B), ambre (C).
  ButtonStyle get mainButton => guided ? amberButton : navyButton;

  Widget scaffold({
    required int step,
    required String title,
    String? subtitle,
    List<Widget> header = const [],
    List<Widget>? compactHeader,
    required Widget body,
    Widget? bottom,
  }) =>
      PresentationScaffold(
        style: style,
        title: title,
        subtitle: guided ? 'Étape ${step + 1} sur 4${subtitle == null ? '' : ' · $subtitle'}' : subtitle,
        actions: actions,
        header: [AssuranceStepsBar(active: step, onDark: true, onTap: stepTap), ...header],
        compactHeader: [AssuranceStepsBar(active: step, onDark: false, onTap: stepTap), ...(compactHeader ?? header)],
        body: progress ? Column(children: [const LinearProgressIndicator(minHeight: 2), Expanded(child: body)]) : body,
        bottomNavigationBar: bottom,
      );
}

/// Barre fixée en bas (bouton principal toujours visible).
class AssuranceBottomBar extends StatelessWidget {
  final List<Widget> children;
  const AssuranceBottomBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Material(
        elevation: 8,
        color: Colors.white,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      );
}

/// Étapes en pastilles (maquette) : active en ambre (bleu sur fond clair), faites en vert.
class AssuranceStepsBar extends StatelessWidget {
  static const labels = ['Client', 'Couverture', 'Produits', 'Encaisser'];
  final int active;
  final bool onDark;
  final VoidCallback? Function(int index)? onTap;
  const AssuranceStepsBar({super.key, required this.active, required this.onDark, this.onTap});

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
              child: _pill(i),
            ),
          ),
      ]);

  Widget _pill(int i) {
    final on = i == active, done = i < active;
    final Color bg, fg;
    if (onDark) {
      bg = on ? Pal.amber : (done ? const Color(0x5916A34A) : Colors.white.withValues(alpha: 0.12));
      fg = on ? Pal.onAmber : (done ? Colors.white : Pal.headerMuted);
    } else {
      bg = on ? Pal.navy : (done ? const Color(0xFFE6F4EA) : const Color(0xFFF1F4F8));
      fg = on ? Colors.white : (done ? const Color(0xFF166534) : Pal.muted);
    }
    final tap = done ? onTap?.call(i) : null;
    return Material(
      key: ValueKey('assurance-etape-$i'),
      color: bg,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: tap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (done) ...[Icon(Icons.check, size: 13, color: fg), const SizedBox(width: 2)] else Text('${i + 1} ', style: TextStyle(fontSize: 11.5, color: fg)),
              Text(labels[i], style: TextStyle(fontSize: 11.5, color: fg, fontWeight: on ? FontWeight.bold : FontWeight.w500)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Client → ayant droit, nom affiché sur la carte client.
String assurancePatientLabel(AssuranceController c) {
  final client = c.client, ad = c.ayantDroit;
  if (client == null) return '—';
  if (ad == null) return '${client.fullName} → ayant droit ?';
  if (ad.lgAYANTSDROITSID == client.lgCLIENTID || ad.fullName == client.fullName) return client.fullName;
  return '${client.fullName} → ${ad.fullName}';
}

/// Carte client permanente (étape Produits) : client → ayant droit, chaque TP avec taux et bon, « ✎ Couverture ».
class AssuranceClientCard extends StatelessWidget {
  final AssuranceController controller;
  final bool onDark;
  final VoidCallback? onCouverture;
  const AssuranceClientCard({super.key, required this.controller, required this.onDark, this.onCouverture});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final ink = onDark ? Colors.white : Pal.ink;
    final muted = onDark ? Pal.headerMuted : Pal.muted;
    return Container(
      key: const ValueKey('assurance-carte-client'),
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 8),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.10) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: onDark ? null : Border.all(color: Pal.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.person, size: 18, color: muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(assurancePatientLabel(c),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: ink)),
          ),
          TextButton.icon(
            key: const ValueKey('assurance-couverture'),
            style: TextButton.styleFrom(
              foregroundColor: onDark ? Colors.white : Pal.navy,
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            onPressed: onCouverture,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Couverture'),
          ),
        ]),
        // Chaque TP : taux et n° de bon (une ligne, deux au plus).
        Text.rich(
          TextSpan(children: [
            for (final (i, tp) in c.activeTiersPayants.indexed) ...[
              if (i > 0) const TextSpan(text: '     '),
              TextSpan(text: '${tp.tpFullName} ${tp.taux} %', style: TextStyle(fontWeight: FontWeight.w600, color: ink)),
              TextSpan(text: ' · bon ${(c.bonNumbers[tp.compteTp] ?? '').isEmpty ? '—' : c.bonNumbers[tp.compteTp]}'),
            ],
          ]),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, color: muted),
        ),
      ]),
    );
  }
}

/// Bandeau d'état du panier : enregistré ✓ / envoi… / non relu / net non calculé.
class AssuranceStatusBanner extends StatelessWidget {
  final AssuranceController controller;
  const AssuranceStatusBanner({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.cartError != null && c.items.isNotEmpty) {
      return LoadErrorBanner(message: 'Panier non relu : ${venteMessage(c.cartError)} (dernier état affiché).', onRetry: c.busy ? null : c.reload);
    }
    if (c.netError != null && c.cartError == null && c.hasCart) {
      return LoadErrorBanner(message: 'Net à payer non calculé : ${venteMessage(c.netError)}', onRetry: c.busy ? null : c.reload);
    }
    if (c.busy && c.venteId != null) {
      return const AssuranceStrip(
        key: ValueKey('assurance-etat-envoi'),
        bg: Color(0xFFE3ECF7),
        fg: Pal.navy,
        leading: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        text: 'Envoi au serveur…',
      );
    }
    if (c.hasCart && c.netUpToDate && !c.finished) {
      final n = c.items.length;
      return AssuranceStrip(
        key: const ValueKey('assurance-etat-ok'),
        bg: const Color(0xFFE6F4EA),
        fg: const Color(0xFF14532D),
        leading: const Icon(Icons.check_circle, size: 16, color: Color(0xFF16A34A)),
        text: '$n article${n > 1 ? 's' : ''} enregistré${n > 1 ? 's' : ''} sur le serveur · net à jour',
      );
    }
    return const SizedBox.shrink();
  }
}

/// Bandeau coloré d'une ligne.
class AssuranceStrip extends StatelessWidget {
  final Color bg;
  final Color fg;
  final Widget leading;
  final String text;
  const AssuranceStrip({super.key, required this.bg, required this.fg, required this.leading, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          leading,
          const SizedBox(width: 8),
          Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w500))),
        ]),
      );
}

/// Titre de section (« AYANT DROIT », « TIERS PAYANTS »).
class AssuranceSectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const AssuranceSectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Pal.muted, letterSpacing: 0.5)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Carte blanche arrondie ; bande de couleur à gauche en présentation C.
class AssuranceCard extends StatelessWidget {
  final Widget child;
  final Color? band;
  final Color color;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  const AssuranceCard({super.key, required this.child, this.band, this.color = Colors.white, this.onTap, this.padding = const EdgeInsets.fromLTRB(12, 10, 10, 10)});

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x1014213D), blurRadius: 4, offset: Offset(0, 1))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: band == null
              ? content
              : IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(width: 5, color: band),
                    Expanded(child: content),
                  ]),
                ),
        ),
      ),
    );
  }
}
