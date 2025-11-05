// lib/screens/assurance_sale/widgets/create_ayant_droit_dialog.dart
// 02/11/2025 15:40
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
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
  // Ajoutez d'autres champs si nécessaire (ex: date naissance)

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

    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    final success = await provider.createAyantDroit(
      _prenomController.text.trim(),
      _nomController.text.trim(),
      _matriculeController.text.trim(),
    );

    if (mounted && success) {
      Navigator.of(context).pop(); // Ferme le dialogue
    }
    // L'erreur est gérée par le provider
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

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
                decoration: const InputDecoration(labelText: 'Nom *'),
                validator: (val) => (val?.isEmpty ?? true) ? 'Requis' : null,
              ),
              TextFormField(
                controller: _prenomController,
                decoration: const InputDecoration(labelText: 'Prénom(s)'),
              ),
              TextFormField(
                controller: _matriculeController,
                decoration: const InputDecoration(labelText: 'Matricule *'),
                validator: (val) => (val?.isEmpty ?? true) ? 'Requis' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (provider.isLoading) const CircularProgressIndicator(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
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