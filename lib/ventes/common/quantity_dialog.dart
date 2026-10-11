// lib/ventes/common/quantity_dialog.dart
// Fenêtre de quantité commune (1 à 9 999, confirmation au-delà de 50) ; mode « scan répété ».
// Style des présentations A/B/C : nom du produit, prix unitaire, stock, gros boutons − / +, champ
// numérique centré, total de la ligne en direct, raccourcis 1/2/3/5/10, Valider/Annuler larges.
// Même API et même valeur renvoyée qu'avant (quantité saisie, null si annulé).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Demande une quantité pour [product] ; renvoie null si annulé. [isSmartMode] : produit scanné plusieurs fois.
class QuantityDialog extends StatefulWidget {
  final ProductSearchResult product;
  final bool isSmartMode;
  final String confirmLabel;
  const QuantityDialog({super.key, required this.product, this.isSmartMode = false, this.confirmLabel = 'Ajouter'});

  @override
  State<QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<QuantityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qteController = TextEditingController(text: '1');
  final _qtyFocusNode = FocusNode();
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _qteController.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _selectAll();
    });
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _selectAll() {
    _qtyFocusNode.requestFocus();
    _qteController.selection = TextSelection(baseOffset: 0, extentOffset: _qteController.text.length);
  }

  @override
  void dispose() {
    _qteController.removeListener(_onChanged);
    _qtyFocusNode.dispose();
    _qteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_confirming) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      _selectAll();
      return;
    }
    final qty = VenteInput.parseQuantity(_qteController.text);
    if (qty == null) return;
    if (qty > VenteInput.confirmQuantityAbove) {
      _confirming = true;
      final ok = await confirmLargeQuantity(context, qty);
      _confirming = false;
      if (!mounted) return;
      if (!ok) {
        _selectAll();
        return;
      }
    }
    Navigator.of(context).pop(qty);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return AlertDialog(
      key: const ValueKey('quantite-dialogue'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isSmartMode)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFFF3D6), borderRadius: BorderRadius.circular(12)),
              child: const Row(children: [
                Icon(Icons.bolt, color: Color(0xFFB45309), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Produit scanné plusieurs fois.\nCombien en reste-t-il ?',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                  ),
                ),
              ]),
            ),
          Text(p.strNAME, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.ink)),
          const SizedBox(height: 8),
          ProduitInfos(prix: p.intPRICE, stock: p.intNUMBERAVAILABLE, cip: p.intCIP),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: QuantiteSaisie(
            controller: _qteController,
            focusNode: _qtyFocusNode,
            prixUnitaire: p.intPRICE,
            stock: p.intNUMBERAVAILABLE,
            onSubmitted: _submit,
          ),
        ),
      ),
      actions: [BoutonsDialogue(confirmLabel: widget.confirmLabel, onConfirm: _submit)],
    );
  }
}

/// Prix unitaire, stock et CIP du produit (pastilles).
class ProduitInfos extends StatelessWidget {
  final int prix;
  final int? stock;
  final String? cip;
  const ProduitInfos({super.key, required this.prix, this.stock, this.cip});

  @override
  Widget build(BuildContext context) {
    final s = stock;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      _pastille('${Constants.formatNumber(prix)} F', 'Prix unitaire', Pal.navy, const Color(0xFFE3ECF7)),
      if (s != null)
        s > 0
            ? _pastille('$s', 'Stock', const Color(0xFF0B6B45), const Color(0xFFDCF5E7))
            : _pastille('0', 'Stock', const Color(0xFF9B1C1C), const Color(0xFFFDE7E7)),
      if (cip != null && cip!.trim().isNotEmpty) _pastille(cip!.trim(), 'CIP', Pal.muted, Pal.page),
    ]);
  }

  static Widget _pastille(String valeur, String libelle, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '$libelle '),
            TextSpan(text: valeur, style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          style: TextStyle(fontSize: 12.5, color: fg),
        ),
      );
}

/// Saisie de la quantité : − / champ centré / +, raccourcis 1/2/3/5/10, total de la ligne en direct
/// et alerte de stock. Le champ reste un [TextFormField] (contrôle 1–9 999 du formulaire).
class QuantiteSaisie extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final int prixUnitaire;

  /// Stock disponible (alerte si la quantité le dépasse ; l'ajout reste possible après confirmation).
  final int? stock;
  final VoidCallback? onSubmitted;
  final bool autofocus;
  const QuantiteSaisie({
    super.key,
    required this.controller,
    this.focusNode,
    required this.prixUnitaire,
    this.stock,
    this.onSubmitted,
    this.autofocus = false,
  });

  static const List<int> raccourcis = [1, 2, 3, 5, 10];

  int? get _qte => VenteInput.parseQuantity(controller.text);

  void _mettre(int v) {
    final t = '${v.clamp(1, VenteInput.maxQuantity)}';
    controller.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }

  @override
  Widget build(BuildContext context) {
    final q = _qte;
    final brut = int.tryParse(controller.text.trim());
    final s = stock;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _gros(
          key: const ValueKey('quantite-moins'),
          icon: Icons.remove,
          tooltip: 'Moins',
          onPressed: brut != null && brut > 1 ? () => _mettre(brut - 1) : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            key: const ValueKey('quantite-champ'),
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Pal.ink),
            decoration: InputDecoration(
              labelText: 'Quantité',
              helperText: '1 à ${VenteInput.maxQuantity}',
              floatingLabelAlignment: FloatingLabelAlignment.center,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: VenteInput.quantityFormatters,
            validator: VenteInput.quantityError,
            onFieldSubmitted: (_) => onSubmitted?.call(),
          ),
        ),
        const SizedBox(width: 8),
        _gros(
          key: const ValueKey('quantite-plus'),
          icon: Icons.add,
          tooltip: 'Plus',
          onPressed: brut == null || brut < VenteInput.maxQuantity ? () => _mettre((brut ?? 0) + 1) : null,
        ),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
        for (final r in raccourcis)
          SizedBox(
            width: 48,
            height: 44,
            child: OutlinedButton(
              key: ValueKey('quantite-raccourci-$r'),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                foregroundColor: q == r ? Colors.white : Pal.navy,
                backgroundColor: q == r ? Pal.navy : null,
                side: BorderSide(color: q == r ? Pal.navy : const Color(0xFFC5D0DE)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              onPressed: () => _mettre(r),
              child: Text('$r'),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Pal.page, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Expanded(child: Text('Total ligne', style: TextStyle(color: Pal.muted, fontSize: 14))),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                q == null ? '—' : '${Constants.formatNumber(q * prixUnitaire)} F',
                key: const ValueKey('quantite-total'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Pal.navy),
              ),
            ),
          ),
        ]),
      ),
      if (s != null && q != null && q > s)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(key: const ValueKey('quantite-alerte-stock'), children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309), size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Au-delà du stock ($s) : confirmation demandée à l\'ajout.',
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E), fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
    ]);
  }

  static Widget _gros({required Key key, required IconData icon, required String tooltip, required VoidCallback? onPressed}) => SizedBox(
        width: 56,
        height: 56,
        child: IconButton.filled(
          key: key,
          tooltip: tooltip,
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFFE3ECF7),
            foregroundColor: Pal.navy,
            disabledBackgroundColor: const Color(0xFFF1F5F9),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          iconSize: 28,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      );
}

/// Annuler / Valider larges, côte à côte (≥ 48 px de haut).
class BoutonsDialogue extends StatelessWidget {
  final String confirmLabel;
  final VoidCallback onConfirm;
  final String cancelLabel;
  const BoutonsDialogue({super.key, required this.confirmLabel, required this.onConfirm, this.cancelLabel = 'Annuler'});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: SizedBox(
            height: 50,
            child: OutlinedButton(style: outlineButton, onPressed: () => Navigator.of(context).pop(), child: Text(cancelLabel)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 50,
            child: ElevatedButton(style: navyButton, onPressed: onConfirm, child: Text(confirmLabel)),
          ),
        ),
      ]);
}

/// Confirmation d'une quantité supérieure à 50 (règle actuelle).
Future<bool> confirmLargeQuantity(BuildContext context, int qty) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Confirmation'),
      content: Text('Ajouter $qty unités ?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('NON')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('OUI, CONFIRMER')),
      ],
    ),
  );
  return ok == true;
}
