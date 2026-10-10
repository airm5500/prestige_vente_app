// lib/parametres/parametres_widgets.dart
// Petits éléments communs aux pages des réglages (en-tête bleu, cartes, choix segmentés, compteurs).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

/// Page d'une rubrique : en-tête bleu arrondi, contenu qui défile, barre fixe éventuelle en bas
/// (tablette : contenu et barre centrés à la largeur maximale).
class RubriquePage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? bottom;
  final List<Widget> actions;
  const RubriquePage({super.key, required this.title, this.subtitle, required this.children, this.bottom, this.actions = const []});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Pal.page,
        bottomNavigationBar: bottom == null ? null : BottomBarWidth(child: bottom!),
        body: Column(children: [
          NavyHeader(title: title, subtitle: subtitle, actions: actions),
          Expanded(
            child: ContentWidth(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: children,
              ),
            ),
          ),
        ]),
      );
}

/// Barre fixe du bas (boutons d'action).
class BottomBar extends StatelessWidget {
  final List<Widget> children;
  const BottomBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Pal.line))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      );
}

/// Libellé de section (majuscules discrètes).
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Pal.muted, letterSpacing: 0.6)),
      );
}

/// Carte blanche simple, espacée.
class SettingCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const SettingCard({super.key, required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SoftCard(padding: padding, child: child),
      );
}

/// Titre + description d'un réglage (prend toute la place disponible).
class SettingText extends StatelessWidget {
  final String title;
  final String? subtitle;
  const SettingText(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
        ],
      ]);
}

/// Interrupteur appliqué immédiatement.
class SwitchCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const SwitchCard({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SettingCard(
        child: InkWell(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(children: [
              Expanded(child: SettingText(title, subtitle: subtitle)),
              const SizedBox(width: 8),
              Switch(value: value, activeColor: Pal.navy, onChanged: onChanged),
            ]),
          ),
        ),
      );
}

/// Choix segmenté (fond gris, option choisie en blanc).
class Segmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: const Color(0xFFE6EBF2), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          for (final (v, label) in options)
            Expanded(
              child: Semantics(
                selected: v == value,
                button: true,
                child: Material(
                  color: v == value ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  elevation: v == value ? 1 : 0,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => onChanged(v),
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: v == value ? FontWeight.w700 : FontWeight.w500,
                              color: v == value ? Pal.navy : Pal.muted,
                            )),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
}

/// Compteur − valeur + (bornes incluses).
class CounterCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final Key? minusKey;
  final Key? plusKey;
  const CounterCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.minusKey,
    this.plusKey,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String tip, VoidCallback? onTap, Key? key) => SizedBox(
          width: 44,
          height: 44,
          child: OutlinedButton(
            key: key,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: Pal.navy,
              side: const BorderSide(color: Pal.line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: onTap,
            child: Icon(icon, size: 20, semanticLabel: tip),
          ),
        );
    return SettingCard(
      child: Row(children: [
        Expanded(child: SettingText(title, subtitle: subtitle)),
        const SizedBox(width: 6),
        btn(Icons.remove, 'Moins', value > min ? () => onChanged((value - 1).clamp(min, max)) : null, minusKey),
        SizedBox(
          width: 32,
          child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.ink)),
        ),
        btn(Icons.add, 'Plus', value < max ? () => onChanged((value + 1).clamp(min, max)) : null, plusKey),
      ]),
    );
  }
}

/// Ligne cliquable (ouvre un écran ou un dialogue).
class LinkCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool locked;
  const LinkCard({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.locked = false});

  @override
  Widget build(BuildContext context) => SettingCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(icon, color: Pal.navy),
              const SizedBox(width: 12),
              Expanded(child: SettingText(title, subtitle: subtitle)),
              if (locked) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.lock_outline, size: 16, color: Pal.muted)),
              const Icon(Icons.chevron_right, color: Pal.muted),
            ]),
          ),
        ),
      );
}

/// Bandeau d'information (bleu), d'avertissement (ambre) ou d'erreur (rouge).
class InfoBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color fg;
  final Color bg;
  const InfoBanner(this.text, {super.key, this.icon = Icons.info_outline, this.fg = Pal.navy, this.bg = const Color(0xFFE3ECF7)});

  const InfoBanner.warning(this.text, {super.key})
      : icon = Icons.warning_amber_rounded,
        fg = const Color(0xFF7C2D12),
        bg = const Color(0xFFFFF4E0);

  const InfoBanner.error(this.text, {super.key})
      : icon = Icons.error_outline,
        fg = const Color(0xFF7F1D1D),
        bg = const Color(0xFFFDECEC);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: fg, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(color: fg, fontSize: 13))),
          ]),
        ),
      );
}

/// Confirmation simple (Annuler / action).
Future<bool> confirmer(BuildContext context, {required String title, required String message, required String action, bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
        ElevatedButton(
          style: danger ? ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white) : navyButton,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Bouton « Rétablir les valeurs par défaut » (avec confirmation).
class ResetDefaultsButton extends StatelessWidget {
  final String rubrique;
  final String detail;
  final Future<void> Function() onReset;
  const ResetDefaultsButton({super.key, required this.rubrique, required this.detail, required this.onReset});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Center(
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(44, 44), foregroundColor: Pal.muted),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Rétablir les valeurs par défaut'),
            onPressed: () async {
              final ok = await confirmer(context,
                  title: 'Rétablir les valeurs par défaut ?', message: '$rubrique : $detail', action: 'Rétablir');
              if (!ok) return;
              await onReset();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$rubrique : valeurs par défaut rétablies.')));
            },
          ),
        ),
      );
}
