// lib/screens/assurance_sale/widgets/create_client_dialog.dart
// 05/11/2025 18:05 (Corrigé)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class CreateClientDialog extends StatefulWidget {
  const CreateClientDialog({super.key});

  @override
  State<CreateClientDialog> createState() => _CreateClientDialogState();
}

class _CreateClientDialogState extends State<CreateClientDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _matriculeController = TextEditingController();
  final _pourcentageController = TextEditingController();

  final _assuranceTextController = TextEditingController();

  final _nomFocusNode = FocusNode();
  final _prenomFocusNode = FocusNode();
  final _matriculeFocusNode = FocusNode();
  final _assuranceFocusNode = FocusNode();
  final _pourcentageFocusNode = FocusNode();

  TiersPayantAssurance? _selectedTiersPayant;

  bool _isSubmitting = false;
  Timer? _debounce;

  // MODIFICATION : Ajout du listener de recherche
  @override
  void initState() {
    super.initState();
    // Ajoute un listener au controller de texte
    _assuranceTextController.addListener(_onAssuranceSearchChanged);
  }

  @override
  void dispose() {
    _nomController.dispose();
    _prenomController.dispose();
    _matriculeController.dispose();
    _pourcentageController.dispose();
    _assuranceTextController.removeListener(_onAssuranceSearchChanged); // Nettoyer
    _assuranceTextController.dispose();
    _nomFocusNode.dispose();
    _prenomFocusNode.dispose();
    _matriculeFocusNode.dispose();
    _assuranceFocusNode.dispose();
    _pourcentageFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // MODIFICATION : Appel au provider via le listener
  void _onAssuranceSearchChanged() {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final query = _assuranceTextController.text;
      if (query.length >= 3) {
        provider.searchTiersPayantAssurance(query);
      } else {
        provider.searchTiersPayantAssurance(""); // Vide la liste si moins de 3 chars
      }
    });

    // Si l'utilisateur change le texte, invalide la sélection
    if (_assuranceTextController.text != _selectedTiersPayant?.strFULLNAME) {
      _selectedTiersPayant = null;
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    // Validation du formulaire
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    // Vérification manuelle de la sélection
    if (_selectedTiersPayant == null || _assuranceTextController.text != _selectedTiersPayant!.strFULLNAME) {
      Constants.showSnackBar(context, "Veuillez sélectionner une assurance valide dans la liste.", isError: true);
      _assuranceFocusNode.requestFocus();
      return;
    }

    setState(() { _isSubmitting = true; });

    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

    try {
      // Rappel : strFIRSTNAME = Nom, strLASTNAME = Prénom(s)
      final success = await provider.createClient(
        _nomController.text.trim(),      // Nom -> strFIRSTNAME
        _prenomController.text.trim(), // Prénom(s) -> strLASTNAME
        _matriculeController.text.trim(),
        _selectedTiersPayant!,
        int.tryParse(_pourcentageController.text) ?? 0,
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
      title: const Text('Créer un Client Assurance'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nomController, // Le Nom (strFIRSTNAME)
                focusNode: _nomFocusNode,
                decoration: const InputDecoration(labelText: 'Nom *'),
                validator: (val) => (val?.isEmpty ?? true) ? 'Requis' : null,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_prenomFocusNode),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _prenomController, // Le Prénom (strLASTNAME)
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

              // MODIFICATION : Remplacement par DropdownMenu
              // Il a besoin d'un Consumer pour mettre à jour sa liste
              Consumer<AssuranceSaleProvider>(
                  builder: (context, provider, child) {
                    return DropdownMenu<TiersPayantAssurance>(
                      // Utilise notre controller pour la saisie de texte
                      controller: _assuranceTextController,
                      focusNode: _assuranceFocusNode,
                      label: const Text('Rechercher Assurance *'),
                      // Occupe toute la largeur
                      expandedInsets: EdgeInsets.zero,
                      // Permet la saisie
                      enableFilter: true,
                      // Affiche le menu de recherche
                      enableSearch: true,

                      // Construit la liste des résultats depuis le provider
                      dropdownMenuEntries: provider.tiersPayantSearchResults.map((tp) {
                        return DropdownMenuEntry<TiersPayantAssurance>(
                          value: tp,
                          label: tp.strFULLNAME,
                        );
                      }).toList(),

                      // Quand un item est sélectionné
                      onSelected: (TiersPayantAssurance? selection) {
                        _selectedTiersPayant = selection;
                        // Règle le texte du champ
                        _assuranceTextController.text = selection?.strFULLNAME ?? "";
                        FocusScope.of(context).requestFocus(_pourcentageFocusNode);
                      },

                      // Validateur
                  //    inputDecorationTheme: InputDecorationTheme(
                  //      errorText: (_selectedTiersPayant == null && _assuranceTextController.text.isNotEmpty)
                  //          ? 'Veuillez sélectionner dans la liste'
                  //          : null,
                  //    ),
                    );
                  }
              ),
              // FIN MODIFICATION

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