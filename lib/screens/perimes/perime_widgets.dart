// lib/screens/perimes/perime_widgets.dart
// Petits éléments communs au menu « Gestion Périmés » (présentations A, B, C) :
// onglets lisibles, chiffres clés, état vide, confirmation et contrôles de saisie.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Quantité maximale acceptée pour une ligne de périmés.
const int kPerimeMaxQte = 99999;

/// Longueur maximale d'un n° de lot.
const int kPerimeMaxLot = 30;

/// Caractères de contrôle refusés dans les champs texte.
final RegExp perimeControlChars = RegExp(r'[\x00-\x1F\x7F]');

/// Refuse les caractères de contrôle à la frappe.
final TextInputFormatter perimeNoControlChars = FilteringTextInputFormatter.deny(perimeControlChars);

/// Valeur affichable : '—' si vide.
String perimeOrDash(String? v) {
  final t = (v ?? '').trim();
  return t.isEmpty ? '—' : t;
}

/// Lit une date de péremption saisie : MMAA (1er du mois), JJMMAA ou JJMMAAAA,
/// avec ou sans séparateurs (/ - . espace). Renvoie null si la date n'existe pas
/// (31/02, mois 13…) ou sort des bornes plausibles (avant 2000, plus de 10 ans).
DateTime? parseDatePeremption(String input, {DateTime? now}) {
  final t = input.trim();
  if (t.isEmpty || t.length > 10) return null;
  if (!RegExp(r'^[0-9/\-\s\.]+$').hasMatch(t)) return null;
  final d = t.replaceAll(RegExp(r'[\/\-\s\.]'), '');
  int? day, month, year;
  switch (d.length) {
    case 4: // MMAA -> 01/MM/20AA
      day = 1;
      month = int.tryParse(d.substring(0, 2));
      final y = int.tryParse(d.substring(2, 4));
      year = y == null ? null : 2000 + y;
    case 6: // JJMMAA -> JJ/MM/20AA
      day = int.tryParse(d.substring(0, 2));
      month = int.tryParse(d.substring(2, 4));
      final y = int.tryParse(d.substring(4, 6));
      year = y == null ? null : 2000 + y;
    case 8: // JJMMAAAA
      day = int.tryParse(d.substring(0, 2));
      month = int.tryParse(d.substring(2, 4));
      year = int.tryParse(d.substring(4, 8));
    default:
      return null;
  }
  if (day == null || month == null || year == null) return null;
  if (month < 1 || month > 12) return null;
  final lastDay = DateTime(year, month + 1, 0).day;
  if (day < 1 || day > lastDay) return null;
  final ref = now ?? DateTime.now();
  if (year < 2000 || year > ref.year + 10) return null;
  return DateTime(year, month, day);
}

/// Onglets du menu : texte blanc et indicateur ambre sur fond bleu (A, C),
/// texte bleu et indicateur ambre sur fond blanc (B).
class PerimeTabBar extends StatelessWidget {
  final TabController controller;
  final List<(IconData, String)> tabs;
  final bool dark;
  const PerimeTabBar({super.key, required this.controller, required this.tabs, this.dark = true});

  @override
  Widget build(BuildContext context) => TabBar(
        controller: controller,
        labelColor: dark ? Colors.white : Pal.navy,
        unselectedLabelColor: dark ? Pal.headerMuted : const Color(0xFF4A5A70),
        indicatorColor: Pal.amber,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: dark ? Colors.transparent : Pal.line,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        tabs: [
          for (final (icon, text) in tabs)
            Tab(
              height: 46,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 6),
                  Text(text, maxLines: 1),
                ]),
              ),
            ),
        ],
      );
}

/// Chiffre clé de l'en-tête bleu ; le chiffre se réduit au lieu de déborder.
class PerimeKpi extends StatelessWidget {
  final String value;
  final String label;
  final bool highlight;
  const PerimeKpi(this.value, this.label, {super.key, this.highlight = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: highlight ? Pal.amber : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                maxLines: 1,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: highlight ? Pal.onAmber : Colors.white)),
          ),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: highlight ? Pal.onAmber : const Color(0xFFDCE6F2))),
        ]),
      );
}

/// État vide explicite (icône + phrase + action), défilable pour le « tirer pour actualiser ».
class PerimeEmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  const PerimeEmptyState({super.key, required this.icon, required this.text, this.detail, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
        children: [
          Icon(icon, size: 56, color: const Color(0xFFB8C4D4)),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(detail!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Pal.muted)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            Center(child: OutlinedButton(style: outlineButton, onPressed: onAction, child: Text(actionLabel!))),
          ],
        ],
      );
}

/// Ligne d'information « libellé : valeur » (détails).
class PerimeInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const PerimeInfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Pal.muted, fontSize: 13))),
          Expanded(child: Text(perimeOrDash(value), style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink))),
        ]),
      );
}

/// Dialogue de confirmation (action irréversible). Renvoie true si confirmé.
Future<bool> confirmPerime(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.ink)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
        ElevatedButton(
          style: danger
              ? ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB91C1C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                )
              : navyButton,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Bouton principal fixé en bas (hauteur 52), avec indicateur pendant l'envoi.
class PerimeBottomAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
  final ButtonStyle style;
  const PerimeBottomAction({super.key, required this.label, required this.icon, required this.onPressed, required this.style, this.busy = false});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Pal.line))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SizedBox(
              height: 52,
              width: double.infinity,
              child: ElevatedButton.icon(
                style: style,
                onPressed: busy ? null : onPressed,
                icon: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(icon),
                label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        ),
      );
}
