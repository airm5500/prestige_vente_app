// lib/screens/expiration_update/expiration_update_screen.dart
// 09/11/2025 20:30 (Correction Focus)
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

  final _formKey = GlobalKey<FormState>();
  final _dateController = TextEditingController();
  final _lotController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');

  final _dateFocusNode = FocusNode();
  final _lotFocusNode = FocusNode();
  final _quantityFocusNode = FocusNode();

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
      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
    _searchController.addListener(_onSearchChanged);

    _setupFocusNodeSelection(_dateFocusNode, _dateController);
    _setupFocusNodeSelection(_lotFocusNode, _lotController);
    _setupFocusNodeSelection(_quantityFocusNode, _quantityController);
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
    if (_formKey.currentState != null) {
      _formKey.currentState!.reset();
    }
    _dateController.clear();
    _lotController.clear();
    _quantityController.text = '1';

    FocusScope.of(context).requestFocus(_searchFocusNode);
    _searchController.selection = TextSelection(baseOffset: 0, extentOffset: _searchController.text.length);
  }

  bool _formatAndValidateDate(String input) {
    if (input.isEmpty) return false;
    String digits = input.replaceAll(RegExp(r'[\/\-\s\.]'), '');
    String day, month, year;
    try {
      if (digits.length == 4) { day = '01'; month = digits.substring(0, 2); year = '20${digits.substring(2, 4)}';
      } else if (digits.length == 6) { day = digits.substring(0, 2); month = digits.substring(2, 4); year = '20${digits.substring(4, 6)}';
      } else if (digits.length == 8) { day = digits.substring(0, 2); month = digits.substring(2, 4); year = digits.substring(4, 8);
      } else { return false; }

      final formattedDate = '$day/$month/$year';
      final parsedDate = DateFormat('dd/MM/yyyy').parseLoose(formattedDate);
      if (parsedDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
        return false;
      }
      _dateController.text = formattedDate;
      return true;
    } catch (e) {
      print("Date invalide: $e");
      return false;
    }
  }

  Future<void> _submitForm() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final provider = Provider.of<ExpirationUpdateProvider>(context, listen: false);
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
              if (provider.isLoading) const LinearProgressIndicator(),
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
              _searchFocusNode.unfocus();
              provider.selectProduct(product);
            },
          ),
        );
      },
    );
  }

  Widget _buildUpdateForm(ExpirationUpdateProvider provider) {
    final product = provider.selectedProduct!;

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
                Text('CIP: ${product.intCIP}'),
                const Divider(height: 30),
                TextFormField(
                  controller: _dateController,
                  focusNode: _dateFocusNode,
                  decoration: const InputDecoration(labelText: 'Date de Péremption (JJMMYY)'),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (!_formatAndValidateDate(value ?? '')) {
                      return 'Date invalide ou passée';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) {
                    if (_formKey.currentState?.validate() ?? false) {
                      FocusScope.of(context).requestFocus(_lotFocusNode);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _lotController,
                  focusNode: _lotFocusNode,
                  decoration: const InputDecoration(labelText: 'N° de Lot'),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Le N° de lot est requis';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) {
                    if (_formKey.currentState?.validate() ?? false) {
                      FocusScope.of(context).requestFocus(_quantityFocusNode);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _quantityController,
                  focusNode: _quantityFocusNode,
                  decoration: const InputDecoration(labelText: 'Quantité'),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  validator: (value) {
                    final int? quantity = int.tryParse(value ?? '1');
                    if (quantity == null || quantity == 0) {
                      return 'La quantité ne peut pas être 0';
                    }
                    return null;
                  },
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
      ),
    );
  }
}