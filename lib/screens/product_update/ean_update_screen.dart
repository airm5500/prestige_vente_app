// lib/screens/product_update/ean_update_screen.dart
// 09/11/2025 20:30 (Correction Focus)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/providers/product_update_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class EanUpdateScreen extends StatefulWidget {
  const EanUpdateScreen({super.key});
  @override
  State<EanUpdateScreen> createState() => _EanUpdateScreenState();
}

class _EanUpdateScreenState extends State<EanUpdateScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounce;

  final _eanController = TextEditingController();
  final _eanFocusNode = FocusNode();
  final _formKey = GlobalKey<FormState>();

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
      Provider.of<ProductUpdateProvider>(context, listen: false).clearAll();
      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
    _searchController.addListener(_onSearchChanged);
    _setupFocusNodeSelection(_eanFocusNode, _eanController);
  }

  @override
  void dispose() {
    _searchController.dispose(); _searchFocusNode.dispose(); _debounce?.cancel();
    _eanController.dispose(); _eanFocusNode.dispose();
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
    _eanController.clear();
    FocusScope.of(context).requestFocus(_searchFocusNode);
    _searchController.selection = TextSelection(baseOffset: 0, extentOffset: _searchController.text.length);
  }

  Future<void> _submitForm() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final provider = Provider.of<ProductUpdateProvider>(context, listen: false);
    final success = await provider.updateEAN(_eanController.text);

    if (mounted) {
      if (success) {
        Constants.showSnackBar(context, 'EAN mis à jour avec succès.');
        _resetForm();
      } else {
        Constants.showSnackBar(context, provider.errorMessage ?? 'Échec de la mise à jour', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mise à jour EAN Fabricant')),
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
              _eanController.clear();
              provider.selectProduct(product);
            },
          ),
        );
      },
    );
  }

  Widget _buildUpdateForm(ProductUpdateProvider provider) {
    final product = provider.selectedProduct!;
    final details = provider.selectedProductDetails;

    if (details != null && _eanController.text.isEmpty) {
      if (details.intEan13.isNotEmpty && details.intEan13 != 'N/A') {
        _eanController.text = details.intEan13;
      }
    }

    String eanDisplay = "";
    if (provider.isLoading && details == null) {
      eanDisplay = ' (EAN Fabricant: ...)';
    } else if (details != null && details.intEan13.isNotEmpty && details.intEan13 != 'N/A') {
      eanDisplay = ' (EAN Fabricant: ${details.intEan13})';
    }

    if (!provider.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).requestFocus(_eanFocusNode);
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
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
                Text('CIP: ${product.intCIP}$eanDisplay'),
                const Divider(height: 30),
                TextFormField(
                  controller: _eanController,
                  focusNode: _eanFocusNode,
                  decoration: const InputDecoration(labelText: 'Code EAN Fabricant', prefixIcon: Icon(Icons.qr_code_scanner)),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.done,
                  validator: (value) => (value == null || value.isEmpty) ? 'Veuillez saisir un code' : null,
                  onFieldSubmitted: (_) => _submitForm(),
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