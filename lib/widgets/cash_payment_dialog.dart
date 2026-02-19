// lib/widgets/cash_payment_dialog.dart
// Mise à jour : Sécurité anti-scan et limite de rendu de monnaie
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

  // Nouvelle variable pour afficher l'erreur
  String? _errorText;

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
    final text = _verseController.text.trim();

    // Si le champ est vide, on réinitialise tout proprement
    if (text.isEmpty) {
      setState(() {
        _monnaie = 0;
        _canValidate = false;
        _errorText = null;
      });
      return;
    }

    final int? montantVerse = int.tryParse(text);

    setState(() {
      if (montantVerse == null) {
        // Cas d'une saisie non numérique (impossible normalement avec le clavier num, mais sécurité au cas où)
        _monnaie = 0;
        _canValidate = false;
        _errorText = "Valeur invalide";
      }
      // SÉCURITÉ ANTI-SCAN :
      // Si la monnaie à rendre dépasse 500 000 FCFA, c'est obligatoirement
      // une erreur de frappe ou le scan d'un code-barres (CIP/EAN).
      else if ((montantVerse - widget.montantNet) > 500000) {
        _monnaie = 0;
        _canValidate = false;
        _errorText = "Montant aberrant (Erreur de scan ?)";

        // On sélectionne tout le texte pour que l'utilisateur puisse
        // re-saisir immédiatement sans avoir à appuyer sur "effacer"
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _verseController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _verseController.text.length,
          );
        });
      }
      else if (montantVerse >= widget.montantNet) {
        // Le montant est suffisant et cohérent, tout est OK
        _monnaie = montantVerse - widget.montantNet;
        _canValidate = true;
        _errorText = null;
      }
      else {
        // Le montant saisi est inférieur au net à payer
        _monnaie = 0;
        _canValidate = false;
        _errorText = null; // On n'affiche pas d'erreur car l'utilisateur est peut-être encore en train de taper
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
            decoration: InputDecoration(
              labelText: 'Montant Versé *',
              prefixIcon: const Icon(Icons.money),
              errorText: _errorText, // Affichage dynamique du message d'erreur
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
          // Le bouton est désactivé si le montant versé est insuffisant ou absurde
          onPressed: _canValidate ? _submit : null,
          child: const Text('Valider'),
        ),
      ],
    );
  }
}