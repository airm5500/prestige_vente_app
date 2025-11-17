// lib/widgets/cash_payment_dialog.dart
// 09/11/2025 21:00
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/utils/constants.dart';

/// Un dialogue pour gérer le paiement en espèces.
/// Il demande le montant versé et calcule la monnaie.
/// Renvoie une Map {'verse': int, 'monnaie': int} en cas de succès.
class CashPaymentDialog extends StatefulWidget {
  final int montantNet;
  const CashPaymentDialog({super.key, required this.montantNet});

  @override
  State<CashPaymentDialog> createState() => _CashPaymentDialogState();
}

class _CashPaymentDialogState extends State<CashPaymentDialog> {
  final _verseController = TextEditingController();
  final _verseFocusNode = FocusNode();
  int _monnaie = 0;
  bool _canValidate = false;

  @override
  void initState() {
    super.initState();
    _verseController.addListener(_calculateMonnaie);

    // Met le focus sur le champ de saisie
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_verseFocusNode);
    });
  }

  @override
  void dispose() {
    _verseController.removeListener(_calculateMonnaie);
    _verseController.dispose();
    _verseFocusNode.dispose();
    super.dispose();
  }

  void _calculateMonnaie() {
    final int montantVerse = int.tryParse(_verseController.text) ?? 0;
    setState(() {
      if (montantVerse >= widget.montantNet) {
        _monnaie = montantVerse - widget.montantNet;
        _canValidate = true;
      } else {
        _monnaie = 0;
        _canValidate = false;
      }
    });
  }

  void _submit() {
    if (!_canValidate) return;
    final int montantVerse = int.tryParse(_verseController.text) ?? 0;
    Navigator.of(context).pop({
      'verse': montantVerse,
      'monnaie': _monnaie,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paiement en Espèces'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Net à Payer: ${Constants.formatNumber(widget.montantNet)}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _verseController,
            focusNode: _verseFocusNode,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Montant Versé *',
              prefixIcon: Icon(Icons.money),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          // Affichage dynamique de la monnaie
          Text(
            'Monnaie: ${Constants.formatNumber(_monnaie)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _canValidate ? AppColors.error : Colors.grey,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          child: const Text('Annuler'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        ElevatedButton(
          // Le bouton est désactivé si le montant versé est insuffisant
          onPressed: _canValidate ? _submit : null,
          child: const Text('Valider'),
        ),
      ],
    );
  }
}