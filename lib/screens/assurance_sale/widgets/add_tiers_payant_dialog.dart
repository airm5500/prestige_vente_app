// lib/screens/assurance_sale/widgets/add_tiers_payant_dialog.dart
// 02/11/2025 15:40
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class AddTiersPayantDialog extends StatefulWidget {
  const AddTiersPayantDialog({super.key});

  @override
  State<AddTiersPayantDialog> createState() => _AddTiersPayantDialogState();
}

class _AddTiersPayantDialogState extends State<AddTiersPayantDialog> {
  final _formKey = GlobalKey<FormState>();
  final _matriculeController = TextEditingController();
  final _pourcentageController = TextEditingController();
  final _assuranceController = TextEditingController();

  TiersPayantAssurance? _selectedTiersPayant;
  Timer? _debounce;

  @override
  void dispose() {
    _matriculeController.dispose();
    _pourcentageController.dispose();
    _assuranceController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onAssuranceSearchChanged(AssuranceSaleProvider provider) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      provider.searchTiersPayantAssurance(_assuranceController.text);
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_selectedTiersPayant == null) {
      Constants.showSnackBar(context, "Veuillez sélectionner une assurance.", isError: true);
      return;
    }

    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    final success = await provider.addTiersPayantToClient(
      _selectedTiersPayant!,
      _matriculeController.text.trim(),
      int.tryParse(_pourcentageController.text) ?? 0,
    );

    if (mounted && success) {
      Navigator.of(context).pop(); // Ferme le dialogue
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AssuranceSaleProvider>(
      builder: (context, provider, child) {
        return AlertDialog(
          title: const Text('Ajouter un Tiers Payant'),
          content: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Client: ${provider.selectedClient?.fullName ?? ''}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Autocomplete<TiersPayantAssurance>(
                    fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                      _assuranceController.text = textEditingController.text;
                      _onAssuranceSearchChanged(provider);
                      return TextFormField(
                        controller: textEditingController,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Rechercher Assurance *',
                        ),
                        onChanged: (_) => _onAssuranceSearchChanged(provider),
                        validator: (_) => _selectedTiersPayant == null ? 'Veuillez sélectionner une assurance' : null,
                      );
                    },
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text == '') {
                        return const Iterable<TiersPayantAssurance>.empty();
                      }
                      return provider.tiersPayantSearchResults.where((tp) => tp
                          .strFULLNAME
                          .toLowerCase()
                          .contains(textEditingValue.text.toLowerCase()));
                    },
                    displayStringForOption: (TiersPayantAssurance option) => option.strFULLNAME,
                    onSelected: (TiersPayantAssurance selection) {
                      setState(() {
                        _selectedTiersPayant = selection;
                      });
                      _assuranceController.text = selection.strFULLNAME;
                    },
                  ),
                  TextFormField(
                    controller: _matriculeController,
                    decoration: const InputDecoration(labelText: 'Matricule (pour ce TP) *'),
                    validator: (val) => (val?.isEmpty ?? true) ? 'Requis' : null,
                  ),
                  TextFormField(
                    controller: _pourcentageController,
                    decoration: const InputDecoration(labelText: 'Pourcentage % *'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (val) {
                      if (val?.isEmpty ?? true) return 'Requis';
                      final int? p = int.tryParse(val!);
                      if (p == null || p <= 0 || p > 100) {
                        return 'Invalide (1-100)';
                      }
                      return null;
                    },
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
              child: const Text('Ajouter'),
            ),
          ],
        );
      },
    );
  }
}