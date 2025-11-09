// lib/screens/carnet_sale/widgets/create_ayant_droit_dialog.dart
// 09/11/2025 19:00
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/carnet_sale_provider.dart';
import 'package:provider/provider.dart';

class CreateAyantDroitDialog extends StatefulWidget {
  const CreateAyantDroitDialog({super.key});

  @override
  State<CreateAyantDroitDialog> createState() => _CreateAyantDroitDialogState();
}

class _CreateAyantDroitDialogState extends State<CreateAyantDroitDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _matriculeController = TextEditingController();

  @override
  void dispose() {
    _nomController.dispose();
    _prenomController.dispose();
    _matriculeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);
    final success = await provider.createAyantDroit(
      _prenomController.text.trim(), // Prénom(s)
      _nomController.text.trim(),      // Nom
      _matriculeController.text.trim(),
    );

    if (mounted && success) {
      Navigator.of(context).pop(); // Ferme le dialogue
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CarnetSaleProvider>(context, listen: true);

    return AlertDialog(
      title: const Text('Nouvel Ayant Droit'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nomController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom *'),
                validator: (val) => (val?.isEmpty ?? true) ? 'Requis' : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _prenomController,
                decoration: const InputDecoration(labelText: 'Prénom(s)'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _matriculeController,
                decoration: const InputDecoration(labelText: 'Matricule *'),
                validator: (val) => (val?.isEmpty ?? true) ? 'Requis' : null,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => provider.isLoading ? null : _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (provider.isLoading)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: CircularProgressIndicator(),
          ),
        TextButton(
          onPressed: provider.isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: provider.isLoading ? null : _submit,
          child: const Text('Créer'),
        ),
      ],
    );
  }
}