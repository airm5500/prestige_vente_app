// lib/screens/product_update/emplacement_update_screen.dart
// 09/11/2025 20:30 (Correction Focus)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/rayon.dart';
import 'package:prestige_vente_app/providers/product_update_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class EmplacementUpdateScreen extends StatefulWidget {
  const EmplacementUpdateScreen({super.key});
  @override
  State<EmplacementUpdateScreen> createState() => _EmplacementUpdateScreenState();
}

class _EmplacementUpdateScreenState extends State<EmplacementUpdateScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounce;

  final _rayonController = TextEditingController();
  String? _selectedRayonId;
  final _rayonFocusNode = FocusNode();

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ProductUpdateProvider>(context, listen: false);
      provider.clearAll();
      provider.loadRayons();
      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
    _searchController.addListener(_onSearchChanged);
    _setupFocusNodeSelection(_rayonFocusNode, _rayonController);
  }

  @override
  void dispose() {
    _searchController.dispose(); _searchFocusNode.dispose(); _debounce?.cancel();
    _rayonController.dispose(); _rayonFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      Provider.of<ProductUpdateProvider>(context, listen: false).search(_searchController.text);
    });
  }

  void _resetForm() {
    Provider.of<ProductUpdateProvider>(context, listen: false).clearSelection();
    _rayonController.clear();
    _selectedRayonId = null;
    FocusScope.of(context).requestFocus(_searchFocusNode);
    _searchController.selection = TextSelection(baseOffset: 0, extentOffset: _searchController.text.length);
  }

  Future<void> _submitForm() async {
    if (_selectedRayonId == null) {
      final provider = Provider.of<ProductUpdateProvider>(context, listen: false);
      final text = _rayonController.text.toLowerCase().trim();
      final matchingRayon = provider.rayons.firstWhere(
            (r) => r.libelle.toLowerCase() == text,
        orElse: () => Rayon(id: '', libelle: ''),
      );

      if (matchingRayon.id.isNotEmpty) {
        _selectedRayonId = matchingRayon.id;
      } else {
        Constants.showSnackBar(context, "Veuillez sélectionner un emplacement valide dans la liste.", isError: true);
        return;
      }
    }

    final provider = Provider.of<ProductUpdateProvider>(context, listen: false);
    final success = await provider.updateEmplacement(_selectedRayonId!);

    if (mounted) {
      if (success) {
        Constants.showSnackBar(context, 'Emplacement mis à jour avec succès.');
        _resetForm();
      } else {
        Constants.showSnackBar(context, provider.errorMessage ?? 'Échec de la mise à jour', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mise à jour Emplacement')),
      body: Consumer<ProductUpdateProvider>(
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

  Widget _buildSearchBar(ProductUpdateProvider provider) {
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
              provider.clearAll();
              // MODIFICATION : Ajout du Focus
              _searchFocusNode.requestFocus();
            },
          ),
        ),
        onSubmitted: (_) => _onSearchChanged(),
        textInputAction: TextInputAction.search,
      ),
    );
  }

  Widget _buildSearchResults(ProductUpdateProvider provider) {
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
            subtitle: Text('CIP: ${product.intCIP} | Stock: ${product.intNUMBERAVAILABLE}'),
            onTap: () {
              _searchFocusNode.unfocus();
              provider.selectProduct(product);
            },
          ),
        );
      },
    );
  }

  Widget _buildUpdateForm(ProductUpdateProvider provider) {
    final product = provider.selectedProduct!;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(_rayonFocusNode);
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
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
                Text(
                  'Emplacement actuel: ${product.strLIBELLEE}',
                  style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black54),
                ),
                const Divider(height: 30),
                DropdownMenu<Rayon>(
                  controller: _rayonController,
                  focusNode: _rayonFocusNode,
                  label: const Text('Nouvel Emplacement'),
                  expandedInsets: EdgeInsets.zero,
                  enableFilter: true,
                  requestFocusOnTap: true,
                  dropdownMenuEntries: provider.rayons.map((Rayon rayon) {
                    return DropdownMenuEntry<Rayon>(
                      value: rayon,
                      label: rayon.libelle,
                    );
                  }).toList(),
                  onSelected: (Rayon? rayon) {
                    if (rayon != null) {
                      _selectedRayonId = rayon.id;
                      _rayonController.text = rayon.libelle;
                      _submitForm();
                    }
                  },
                ),
                const SizedBox(height: 24),
                if(provider.isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle),
                      onPressed: _submitForm,
                      label: const Text('Valider'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}