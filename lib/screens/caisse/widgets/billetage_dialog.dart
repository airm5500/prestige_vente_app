// lib/screens/caisse/widgets/billetage_dialog.dart
// 09/11/2025 02:20 (Amélioration Focus et Saisie)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/caisse_models.dart';
import 'package:prestige_vente_app/providers/caisse_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class BilletageDialog extends StatefulWidget {
  final ClotureData clotureData;

  const BilletageDialog({super.key, required this.clotureData});

  @override
  State<BilletageDialog> createState() => _BilletageDialogState();
}

class _BilletageDialogState extends State<BilletageDialog> {
  final _formKey = GlobalKey<FormState>();

  final _dixMilleController = TextEditingController(text: '0');
  final _cinqMilleController = TextEditingController(text: '0');
  final _deuxMilleController = TextEditingController(text: '0');
  final _milleController = TextEditingController(text: '0');
  final _cinqCentController = TextEditingController(text: '0');
  final _autreController = TextEditingController(text: '0');

  // MODIFICATION : Ajout des FocusNodes pour la navigation et la sélection
  final _dixMilleFocusNode = FocusNode();
  final _cinqMilleFocusNode = FocusNode();
  final _deuxMilleFocusNode = FocusNode();
  final _milleFocusNode = FocusNode();
  final _cinqCentFocusNode = FocusNode();
  final _autreFocusNode = FocusNode();

  int _totalCalcule = 0;

  @override
  void initState() {
    super.initState();
    _dixMilleController.addListener(_calculateTotal);
    _cinqMilleController.addListener(_calculateTotal);
    _deuxMilleController.addListener(_calculateTotal);
    _milleController.addListener(_calculateTotal);
    _cinqCentController.addListener(_calculateTotal);
    _autreController.addListener(_calculateTotal);

    // MODIFICATION (Req 2) : Ajout des listeners pour la sélection auto
    _setupFocusNodeSelection(_dixMilleFocusNode, _dixMilleController);
    _setupFocusNodeSelection(_cinqMilleFocusNode, _cinqMilleController);
    _setupFocusNodeSelection(_deuxMilleFocusNode, _deuxMilleController);
    _setupFocusNodeSelection(_milleFocusNode, _milleController);
    _setupFocusNodeSelection(_cinqCentFocusNode, _cinqCentController);
    _setupFocusNodeSelection(_autreFocusNode, _autreController);

    // MODIFICATION (Req 1) : Focus automatique sur le premier champ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_dixMilleFocusNode);
      }
    });
  }

  @override
  void dispose() {
    _dixMilleController.dispose();
    _cinqMilleController.dispose();
    _deuxMilleController.dispose();
    _milleController.dispose();
    _cinqCentController.dispose();
    _autreController.dispose();

    // MODIFICATION : Nettoyage des FocusNodes
    _dixMilleFocusNode.dispose();
    _cinqMilleFocusNode.dispose();
    _deuxMilleFocusNode.dispose();
    _milleFocusNode.dispose();
    _cinqCentFocusNode.dispose();
    _autreFocusNode.dispose();

    super.dispose();
  }

  // MODIFICATION (Req 2) : Fonction helper pour la sélection auto
  void _setupFocusNodeSelection(FocusNode node, TextEditingController controller) {
    node.addListener(() {
      if (node.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          );
        });
      }
    });
  }

  int _parse(TextEditingController c) => int.tryParse(c.text) ?? 0;

  void _calculateTotal() {
    setState(() {
      _totalCalcule =
          (_parse(_dixMilleController) * 10000) +
              (_parse(_cinqMilleController) * 5000) +
              (_parse(_deuxMilleController) * 2000) +
              (_parse(_milleController) * 1000) +
              (_parse(_cinqCentController) * 500) +
              _parse(_autreController);
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final provider = Provider.of<CaisseProvider>(context, listen: false);

    final billetage = {
      "dixMille": _parse(_dixMilleController),
      "cinqMille": _parse(_cinqMilleController),
      "deuxMille": _parse(_deuxMilleController),
      "mille": _parse(_milleController),
      "cinqCent": _parse(_cinqCentController),
      "autre": _parse(_autreController),
    };

    final success = await provider.cloturerCaisse(billetage);

    if (mounted && success) {
      Navigator.of(context).pop(); // Ferme ce dialogue
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CaisseProvider>(context);
    final ecart = _totalCalcule - widget.clotureData.solde;

    return AlertDialog(
      title: const Text('Billetage de Clôture'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Solde Théorique: ${Constants.formatNumber(widget.clotureData.solde)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Divider(height: 20),

              // MODIFICATION (Req 3) : Ajout des FocusNodes et actions
              _buildBilletRow(
                _dixMilleController,
                _dixMilleFocusNode,
                '10 000 F',
                TextInputAction.next,
                    (_) => FocusScope.of(context).requestFocus(_cinqMilleFocusNode),
              ),
              _buildBilletRow(
                _cinqMilleController,
                _cinqMilleFocusNode,
                '5 000 F',
                TextInputAction.next,
                    (_) => FocusScope.of(context).requestFocus(_deuxMilleFocusNode),
              ),
              _buildBilletRow(
                _deuxMilleController,
                _deuxMilleFocusNode,
                '2 000 F',
                TextInputAction.next,
                    (_) => FocusScope.of(context).requestFocus(_milleFocusNode),
              ),
              _buildBilletRow(
                _milleController,
                _milleFocusNode,
                '1 000 F',
                TextInputAction.next,
                    (_) => FocusScope.of(context).requestFocus(_cinqCentFocusNode),
              ),
              _buildBilletRow(
                _cinqCentController,
                _cinqCentFocusNode,
                '500 F',
                TextInputAction.next,
                    (_) => FocusScope.of(context).requestFocus(_autreFocusNode),
              ),
              _buildBilletRow(
                _autreController,
                _autreFocusNode,
                'Autres (Pièces)',
                TextInputAction.done,
                    (_) => _submit(), // Le dernier champ valide le formulaire
              ),
              // FIN MODIFICATION

              const Divider(height: 20),
              ListTile(
                title: const Text('Total Compté', style: TextStyle(fontWeight: FontWeight.bold)),
                trailing: Text(Constants.formatNumber(_totalCalcule),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              ListTile(
                title: const Text('Écart', style: TextStyle(fontWeight: FontWeight.bold)),
                trailing: Text(Constants.formatNumber(ecart),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: ecart == 0 ? AppColors.success : AppColors.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (provider.isLoading) const CircularProgressIndicator(),
        TextButton(
          onPressed: provider.isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: provider.isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Valider la Clôture'),
        ),
      ],
    );
  }

  // MODIFICATION (Req 3) : Mise à jour de la signature de la fonction
  Widget _buildBilletRow(
      TextEditingController controller,
      FocusNode focusNode,
      String label,
      TextInputAction textInputAction,
      void Function(String) onFieldSubmitted,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          SizedBox(
            width: 80,
            child: TextFormField(
              controller: controller,
              focusNode: focusNode, // Ajouté
              textAlign: TextAlign.center,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (val) => (val == null || val.isEmpty) ? 'Requis' : null,
              textInputAction: textInputAction, // Ajouté
              onFieldSubmitted: onFieldSubmitted, // Ajouté
            ),
          ),
        ],
      ),
    );
  }
}