// lib/ventes/common/quantity_dialog.dart
// Fenêtre de quantité commune (1 à 9 999, confirmation au-delà de 50) ; mode « scan répété ».
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _selectAll();
    });
  }

  void _selectAll() {
    _qtyFocusNode.requestFocus();
    _qteController.selection = TextSelection(baseOffset: 0, extentOffset: _qteController.text.length);
  }

  @override
  void dispose() {
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
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isSmartMode)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: const Row(children: [
                Icon(Icons.bolt, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Produit scanné plusieurs fois.\nCombien en reste-t-il ?',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange),
                  ),
                ),
              ]),
            ),
          Text(p.strNAME, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            'CIP : ${p.intCIP} | Stock : ${p.intNUMBERAVAILABLE} | Prix : ${Constants.formatNumber(p.intPRICE)} F',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _qteController,
          focusNode: _qtyFocusNode,
          decoration: const InputDecoration(labelText: 'Quantité (1 à ${VenteInput.maxQuantity})', border: OutlineInputBorder()),
          keyboardType: TextInputType.number,
          inputFormatters: VenteInput.quantityFormatters,
          validator: VenteInput.quantityError,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
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
