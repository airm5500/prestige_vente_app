// lib/reserve/reserve_widgets.dart
// Éléments communs des écrans « Réserve » : sens du mouvement, stocks rayon / réserve, saisie de quantité.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/reserve/reserve_models.dart';
import 'package:prestige_vente_app/reserve/reserve_regles.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Couleur associée à un sens (même couleur partout pour ne pas confondre).
Color couleurSens(SensReserve s) => s == SensReserve.versRayon ? const Color(0xFF0F766E) : const Color(0xFF7C3AED);

IconData iconeSens(SensReserve s) => s == SensReserve.versRayon ? Icons.move_up : Icons.move_down;

/// Pastille « Réserve → Rayon ».
class SensBadge extends StatelessWidget {
  final SensReserve sens;
  final bool clair;
  const SensBadge(this.sens, {super.key, this.clair = false});

  @override
  Widget build(BuildContext context) {
    final c = couleurSens(sens);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: clair ? Colors.white : c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(iconeSens(sens), size: 15, color: c),
        const SizedBox(width: 4),
        Text(sens.fleche, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }
}

/// « Rayon 12 · Réserve 40 » : le stock source est mis en avant.
class StocksLigne extends StatelessWidget {
  final int rayon;
  final int reserve;
  final SensReserve sens;
  const StocksLigne({super.key, required this.rayon, required this.reserve, required this.sens});

  @override
  Widget build(BuildContext context) {
    Widget bloc(String label, int v, bool source) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: source ? const Color(0xFFFFF7E6) : const Color(0xFFF2F4F8),
            borderRadius: BorderRadius.circular(8),
            border: source ? Border.all(color: const Color(0xFFF5C26B)) : null,
          ),
          child: Text('$label $v', style: TextStyle(fontSize: 12.5, fontWeight: source ? FontWeight.w700 : FontWeight.w500, color: v < 0 ? Colors.red : Pal.ink)),
        );
    return Wrap(spacing: 6, runSpacing: 4, children: [
      bloc('Rayon', rayon, sens == SensReserve.versReserve),
      bloc('Réserve', reserve, sens == SensReserve.versRayon),
    ]);
  }
}

/// Saisie d'une quantité à déplacer : entier > 0, borné par le stock source. Renvoie null si annulé.
Future<int?> demanderQuantite(
  BuildContext context, {
  required String produit,
  required SensReserve sens,
  required int disponible,
  int? initiale,
  String? aide,
}) =>
    showDialog<int>(
      context: context,
      builder: (_) => _QuantiteDialog(produit: produit, sens: sens, disponible: disponible, initiale: initiale, aide: aide),
    );

class _QuantiteDialog extends StatefulWidget {
  final String produit;
  final SensReserve sens;
  final int disponible;
  final int? initiale;
  final String? aide;
  const _QuantiteDialog({required this.produit, required this.sens, required this.disponible, this.initiale, this.aide});

  @override
  State<_QuantiteDialog> createState() => _QuantiteDialogState();
}

class _QuantiteDialogState extends State<_QuantiteDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initiale == null ? '' : '${widget.initiale}');
  String? _erreur;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _valider() {
    final e = validerQuantite(_c.text, disponible: widget.disponible, sens: widget.sens);
    if (e != null) {
      setState(() => _erreur = e);
      return;
    }
    Navigator.of(context).pop(lireQuantite(_c.text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.produit, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SensBadge(widget.sens),
          const SizedBox(height: 8),
          Text('Stock ${widget.sens.source} disponible : ${widget.disponible}', style: const TextStyle(color: Pal.muted)),
          if (widget.aide != null && widget.aide!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(widget.aide!, style: const TextStyle(fontSize: 12, color: Pal.muted)),
          ],
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('reserve-quantite'),
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            decoration: InputDecoration(labelText: 'Quantité (boîtes)', errorText: _erreur, errorMaxLines: 3),
            onSubmitted: (_) => _valider(),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          ElevatedButton(style: navyButton, onPressed: _valider, child: const Text('Valider')),
        ],
      );
}

/// Bandeau d'aide rappelant le sens du mouvement.
class BandeauSens extends StatelessWidget {
  final SensReserve sens;
  const BandeauSens(this.sens, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = couleurSens(sens);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.35))),
      child: Row(children: [
        Icon(iconeSens(sens), color: c),
        const SizedBox(width: 10),
        Expanded(
          child: Text('${sens.fleche} : ${sens.action.toLowerCase()}. Les boîtes sortent du stock ${sens.source}.',
              style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ]),
    );
  }
}

/// Carte cliquable d'une suggestion à traiter (liste, reprise depuis le panier).
class CarteSuggestion extends StatelessWidget {
  final EnteteSuggestion entete;
  final VoidCallback onTap;
  const CarteSuggestion({super.key, required this.entete, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SoftCard(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(entete.ref.isEmpty ? 'Suggestion' : entete.ref, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Pal.ink)),
                const SizedBox(height: 2),
                Text(
                  [
                    '${entete.nbProduits} produit(s)',
                    if (entete.dateCreation.isNotEmpty) 'créée le ${entete.dateCreation}',
                    if (entete.createur.isNotEmpty) 'par ${entete.createur}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12.5, color: Pal.muted),
                ),
                if (entete.motifLibelle.isNotEmpty) Text(entete.motifLibelle, style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
              ]),
            ),
            const SizedBox(width: 8),
            entete.statut == StatutSuggestion.enCours ? StatusBadge.enCours() : StatusBadge.aCommencer(),
            const Icon(Icons.chevron_right, color: Pal.muted),
          ]),
        ),
      );
}
