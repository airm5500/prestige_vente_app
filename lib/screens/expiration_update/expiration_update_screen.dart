// lib/screens/expiration_update/expiration_update_screen.dart
// 15/10/2025 23:58
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/providers/expiration_update_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class ExpirationUpdateScreen extends StatefulWidget {
  const ExpirationUpdateScreen({super.key});

  @override
  State<ExpirationUpdateScreen> createState() => _ExpirationUpdateScreenState();
}

class _ExpirationUpdateScreenState extends State<ExpirationUpdateScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounce;

  final _dateController = TextEditingController();
  final _lotController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');

  // On a besoin de tous les FocusNodes pour un contrôle manuel
  final _dateFocusNode = FocusNode();
  final _lotFocusNode = FocusNode();
  final _quantityFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose(); _searchFocusNode.dispose(); _debounce?.cancel();
    _dateController.dispose(); _lotController.dispose(); _quantityController.dispose();
    _dateFocusNode.dispose(); _lotFocusNode.dispose(); _quantityFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      Provider.of<ExpirationUpdateProvider>(context, listen: false).search(_searchController.text);
    });
  }

  void _resetForm() {
    final provider = Provider.of<ExpirationUpdateProvider>(context, listen: false);
    provider.clearSelection();
    _dateController.clear();
    _lotController.clear();
    _quantityController.text = '1';
    FocusScope.of(context).requestFocus(_searchFocusNode);
  }

  void _formatAndSetDate(String input) {
    if (input.isEmpty) return;
    String digits = input.replaceAll(RegExp(r'[\/\-\s\.]'), '');
    String day, month, year;
    try {
      if (digits.length == 4) { day = '01'; month = digits.substring(0, 2); year = '20${digits.substring(2, 4)}';
      } else if (digits.length == 6) { day = digits.substring(0, 2); month = digits.substring(2, 4); year = '20${digits.substring(4, 6)}';
      } else if (digits.length == 8) { day = digits.substring(0, 2); month = digits.substring(2, 4); year = digits.substring(4, 8);
      } else { return; }
      final formattedDate = '$day/$month/$year';
      DateFormat('dd/MM/yyyy').parseLoose(formattedDate);
      _dateController.text = formattedDate;
    } catch (e) {
      print("Date invalide: $e");
    }
  }

  Future<void> _submitForm() async {
    final provider = Provider.of<ExpirationUpdateProvider>(context, listen: false);

    _formatAndSetDate(_dateController.text);

    if (_dateController.text.isEmpty || _lotController.text.isEmpty) {
      Constants.showSnackBar(context, "Veuillez remplir la date et le N° de lot.", isError: true);
      return;
    }

    final success = await provider.submitUpdate(
      date: _dateController.text,
      lot: _lotController.text,
      quantity: int.tryParse(_quantityController.text) ?? 1,
    );

    if (mounted) {
      if (success) {
        Constants.showSnackBar(context, 'Date de péremption mise à jour avec succès.');
        _resetForm();
      } else {
        Constants.showSnackBar(context, provider.errorMessage ?? 'Erreur inconnue', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mise à jour Péremption')),
      body: Consumer<ExpirationUpdateProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              _buildSearchBar(provider),
              if (provider.isLoading && provider.selectedProduct == null) const LinearProgressIndicator(),
              Expanded(
                child: provider.selectedProduct == null
                    ? _buildSearchResults(provider)
                    : _buildUpdateForm(provider),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(ExpirationUpdateProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        decoration: InputDecoration(
          labelText: 'Rechercher par CIP, Nom ou Scan',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              provider.clearSearch();
            },
          ),
        ),
        onSubmitted: (_) => _onSearchChanged(),
        textInputAction: TextInputAction.search,
      ),
    );
  }

  Widget _buildSearchResults(ExpirationUpdateProvider provider) {
    if (provider.searchResults.isEmpty && _searchController.text.isNotEmpty) {
      return const Center(child: Text('Aucun produit trouvé.'));
    }
    return ListView.builder(
      itemCount: provider.searchResults.length,
      itemBuilder: (context, index) {
        final product = provider.searchResults[index];
        return Card(
          child: ListTile(
            title: Text(product.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('CIP: ${product.intCIP} | Prix: ${Constants.formatNumber(product.intPRICE)} | Stock: ${product.intNUMBERAVAILABLE}'),
            onTap: () {
              // On retire d'abord le focus de la barre de recherche
              _searchFocusNode.unfocus();
              // Ensuite, on sélectionne le produit, ce qui affichera le formulaire
              provider.selectProduct(product);
            },
          ),
        );
      },
    );
  }

  Widget _buildUpdateForm(ExpirationUpdateProvider provider) {
    final product = provider.selectedProduct!;

    // On utilise cette méthode pour demander le focus APRES que le widget soit construit
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_dateFocusNode);
      }
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(product.strNAME, style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(icon: const Icon(Icons.close), onPressed: _resetForm),
                ],
              ),
              Text('CIP: ${product.intCIP}'),
              const Divider(height: 30),
              Focus(
                onFocusChange: (hasFocus) {
                  if (!hasFocus) { _formatAndSetDate(_dateController.text); }
                },
                child: TextFormField(
                  controller: _dateController,
                  focusNode: _dateFocusNode,
                  decoration: const InputDecoration(labelText: 'Date de Péremption (JJMMYY)'),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) {
                    _formatAndSetDate(_dateController.text);
                    FocusScope.of(context).requestFocus(_lotFocusNode);
                  },
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _lotController,
                focusNode: _lotFocusNode,
                decoration: const InputDecoration(labelText: 'N° de Lot'),
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_quantityFocusNode),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _quantityController,
                focusNode: _quantityFocusNode,
                decoration: const InputDecoration(labelText: 'Quantité'),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submitForm(),
              ),
              const SizedBox(height: 24),
              if(provider.isLoading)
                const Center(child: CircularProgressIndicator())
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitForm,
                    child: const Text('Valider'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}