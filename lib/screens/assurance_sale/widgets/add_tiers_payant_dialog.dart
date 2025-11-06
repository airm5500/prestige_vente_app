// lib/screens/assurance_sale/widgets/add_tiers_payant_dialog.dart
// 06/11/2025 00:15 (Corrigé - Espacement et Recherche)
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

  // MODIFICATIONS : Ajout du controller et focus node (comme in create_client_dialog.dart)
  final _assuranceController = TextEditingController();
  final _assuranceFocusNode = FocusNode();
  final _matriculeFocusNode = FocusNode();
  final _pourcentageFocusNode = FocusNode();


  TiersPayantAssurance? _selectedTiersPayant;
  Timer? _debounce;

  // MODIFICATION : Ajout du listener
  @override
  void initState() {
    super.initState();
    _assuranceController.addListener(_onAssuranceSearchChanged);
  }

  @override
  void dispose() {
    _matriculeController.dispose();
    _pourcentageController.dispose();
    _assuranceController.removeListener(_onAssuranceSearchChanged); // Nettoyer
    _assuranceController.dispose();
    _assuranceFocusNode.dispose();
    _matriculeFocusNode.dispose();
    _pourcentageFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // MODIFICATION : Ajout de la fonction (comme in create_client_dialog.dart)
  // La recherche se fait à partir de 3 caractères
  void _onAssuranceSearchChanged() {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final query = _assuranceController.text;
      if (query.length >= 3) { // <-- Respect de la règle des 3 caractères
        provider.searchTiersPayantAssurance(query);
      } else {
        provider.searchTiersPayantAssurance(""); // Vide la liste
      }
    });

    // Si l'utilisateur change le texte, invalide la sélection
    if (_assuranceController.text != _selectedTiersPayant?.strFULLNAME) {
      _selectedTiersPayant = null;
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    // MODIFICATION : Vérification manuelle de la sélection
    if (_selectedTiersPayant == null || _assuranceController.text != _selectedTiersPayant!.strFULLNAME) {
      Constants.showSnackBar(context, "Veuillez sélectionner une assurance valide dans la liste.", isError: true);
      _assuranceFocusNode.requestFocus();
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
    // Pas besoin de Consumer autour de l'AlertDialog,
    // on le mettra autour du DropdownMenu.
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

    return AlertDialog(
      title: const Text('Ajouter un Tiers Payant'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Client: ${provider.selectedClient?.fullName ?? ''}", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16), // Espacement

              // MODIFICATION : Remplacement de Autocomplete par DropdownMenu
              Consumer<AssuranceSaleProvider>(
                  builder: (context, provider, child) {
                    return DropdownMenu<TiersPayantAssurance>(
                      controller: _assuranceController,
                      focusNode: _assuranceFocusNode,
                      label: const Text('Rechercher Assurance *'),
                      expandedInsets: EdgeInsets.zero,
                      enableFilter: true,
                      enableSearch: true,
                      dropdownMenuEntries: provider.tiersPayantSearchResults.map((tp) {
                        return DropdownMenuEntry<TiersPayantAssurance>(
                          value: tp,
                          label: tp.strFULLNAME,
                        );
                      }).toList(),
                      onSelected: (TiersPayantAssurance? selection) {
                        _selectedTiersPayant = selection;
                        _assuranceController.text = selection?.strFULLNAME ?? "";
                        FocusScope.of(context).requestFocus(_matriculeFocusNode);
                      },
                    );
                  }
              ),
              // FIN MODIFICATION

              // MODIFICATION (Bug 1) : Ajout d'espacement
              const SizedBox(height: 16),

              TextFormField(
                controller: _matriculeController,
                focusNode: _matriculeFocusNode,
                decoration: const InputDecoration(labelText: 'Matricule (pour ce TP) *'),
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_pourcentageFocusNode),
                validator: (val) => (val?.isEmpty ?? true) ? 'Requis' : null,
              ),

              // MODIFICATION (Bug 1) : Ajout d'espacement
              const SizedBox(height: 16),

              TextFormField(
                controller: _pourcentageController,
                focusNode: _pourcentageFocusNode,
                decoration: const InputDecoration(labelText: 'Pourcentage % *'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
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
        // On écoute le isLoading du provider pour le spinner
        Consumer<AssuranceSaleProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading) {
                return const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                );
              }
              return const SizedBox.shrink();
            }
        ),
        TextButton(
          // On désactive si le provider charge
          onPressed: provider.isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          // On désactive si le provider charge
          onPressed: provider.isLoading ? null : _submit,
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}