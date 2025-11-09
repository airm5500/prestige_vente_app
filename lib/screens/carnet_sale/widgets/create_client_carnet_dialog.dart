// lib/screens/carnet_sale/widgets/create_client_carnet_dialog.dart
// 09/11/2025 19:00
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/providers/carnet_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class CreateClientCarnetDialog extends StatefulWidget {
  const CreateClientCarnetDialog({super.key});

  @override
  State<CreateClientCarnetDialog> createState() => _CreateClientCarnetDialogState();
}

class _CreateClientCarnetDialogState extends State<CreateClientCarnetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _matriculeController = TextEditingController();

  final _assuranceTextController = TextEditingController();

  final _nomFocusNode = FocusNode();
  final _prenomFocusNode = FocusNode();
  final _matriculeFocusNode = FocusNode();
  final _assuranceFocusNode = FocusNode();

  TiersPayantAssurance? _selectedTiersPayant;

  bool _isSubmitting = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _assuranceTextController.addListener(_onCarnetSearchChanged);

    // Focus auto sur le nom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nomFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _nomController.dispose();
    _prenomController.dispose();
    _matriculeController.dispose();
    _assuranceTextController.removeListener(_onCarnetSearchChanged);
    _assuranceTextController.dispose();
    _nomFocusNode.dispose();
    _prenomFocusNode.dispose();
    _matriculeFocusNode.dispose();
    _assuranceFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onCarnetSearchChanged() {
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final query = _assuranceTextController.text;
      if (query.length >= 3) {
        provider.searchTiersPayantCarnet(query);
      } else {
        provider.searchTiersPayantCarnet("");
      }
    });

    if (_assuranceTextController.text != _selectedTiersPayant?.strFULLNAME) {
      _selectedTiersPayant = null;
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (_selectedTiersPayant == null || _assuranceTextController.text != _selectedTiersPayant!.strFULLNAME) {
      Constants.showSnackBar(context, "Veuillez sélectionner un carnet valide dans la liste.", isError: true);
      _assuranceFocusNode.requestFocus();
      return;
    }

    setState(() { _isSubmitting = true; });

    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);

    try {
      final success = await provider.createClient(
        _nomController.text.trim(),      // Nom -> strFIRSTNAME
        _prenomController.text.trim(), // Prénom(s) -> strLASTNAME
        _matriculeController.text.trim(),
        _selectedTiersPayant!,
        // Le pourcentage est 100% (géré par l'API)
      );

      if (mounted && success) {
        Navigator.of(context).pop(); // Ferme le dialogue
      }
    } catch (e) {
      if(mounted) {
        Constants.showSnackBar(context, "Erreur: $e", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() { _isSubmitting = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return AlertDialog(
      title: const Text('Créer un Client Carnet'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nomController,
                focusNode: _nomFocusNode,
                autofocus: true, // Focus auto
                decoration: const InputDecoration(labelText: 'Nom *'),
                validator: (val) => (val?.isEmpty ?? true) ? 'Requis' : null,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_prenomFocusNode),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _prenomController,
                focusNode: _prenomFocusNode,
                decoration: const InputDecoration(labelText: 'Prénom(s) *'),
                validator: (val) => (val?.isEmpty ?? true) ? 'Requis' : null,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_matriculeFocusNode),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _matriculeController,
                focusNode: _matriculeFocusNode,
                decoration: const InputDecoration(labelText: 'Matricule *'),
                validator: (val) => (val?.isEmpty ?? true) ? 'Requis' : null,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_assuranceFocusNode),
              ),
              const SizedBox(height: 16),

              Consumer<CarnetSaleProvider>(
                  builder: (context, provider, child) {
                    return DropdownMenu<TiersPayantAssurance>(
                      controller: _assuranceTextController,
                      focusNode: _assuranceFocusNode,
                      label: const Text('Rechercher Carnet *'),
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
                        _assuranceTextController.text = selection?.strFULLNAME ?? "";
                        // Le formulaire est complet, on peut valider
                        _submit();
                      },
                    );
                  }
              ),
              // Le champ Pourcentage est caché car il est fixé à 100%
            ],
          ),
        ),
      ),
      actions: [
        if (_isSubmitting)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: CircularProgressIndicator(),
          )
        else
          ElevatedButton(
            onPressed: _submit,
            child: const Text('Valider'),
          ),
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
      ],
    );
  }
}