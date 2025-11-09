// lib/screens/perimes/tabs/saisie_en_cours_tab.dart
// 09/11/2025 18:15 (Correction Bug affichage recherche)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
//import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/providers/perime_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class SaisieEnCoursTab extends StatefulWidget {
  const SaisieEnCoursTab({super.key});

  @override
  State<SaisieEnCoursTab> createState() => _SaisieEnCoursTabState();
}

class _SaisieEnCoursTabState extends State<SaisieEnCoursTab> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounce;

  final _formKey = GlobalKey<FormState>();
  final _lotController = TextEditingController();
  final _qteController = TextEditingController(text: '1');
  final _dateController = TextEditingController();

  final _lotFocusNode = FocusNode();
  final _qteFocusNode = FocusNode();
  final _dateFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PerimeProvider>(context, listen: false).loadSaisieEnCours();
    });
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    _lotController.dispose();
    _qteController.dispose();
    _dateController.dispose();
    _lotFocusNode.dispose();
    _qteFocusNode.dispose();
    _dateFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      Provider.of<PerimeProvider>(context, listen: false)
          .searchProduct(_searchController.text);
    });
  }

  void _resetForm() {
    Provider.of<PerimeProvider>(context, listen: false).clearSelection();
    _searchController.clear();
    _lotController.clear();
    _qteController.text = '1';
    _dateController.clear();
    _searchFocusNode.requestFocus();
  }

  bool _formatAndValidateDate(String input) {
    if (input.isEmpty) return false;
    String digits = input.replaceAll(RegExp(r'[\/\-\s\.]'), '');
    String day, month, year;
    try {
      if (digits.length == 4) { // MMYY -> 01/MM/20YY
        day = '01';
        month = digits.substring(0, 2);
        year = '20${digits.substring(2, 4)}';
      } else if (digits.length == 6) { // JJMMYY -> JJ/MM/20YY
        day = digits.substring(0, 2);
        month = digits.substring(2, 4);
        year = '20${digits.substring(4, 6)}';
      } else if (digits.length == 8) { // JJMMYYYY
        day = digits.substring(0, 2);
        month = digits.substring(2, 4);
        year = digits.substring(4, 8);
      } else {
        return false;
      }

      final formattedDate = '$day/$month/$year';
      // Valide si la date est réelle
      DateFormat('dd/MM/yyyy').parseLoose(formattedDate);
      _dateController.text = formattedDate; // Met à jour le champ
      return true;
    } catch (e) {
      print("Date invalide: $e");
      return false;
    }
  }

  String _getFormattedDateForApi() {
    try {
      final parsedDate = DateFormat('dd/MM/yyyy').parseLoose(_dateController.text);
      return DateFormat('yyyy-MM-dd').format(parsedDate);
    } catch (e) {
      return ''; // Devrait être bloqué par le validateur
    }
  }

  Future<void> _submitItem() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final provider = Provider.of<PerimeProvider>(context, listen: false);
    if (provider.selectedProduct == null) {
      provider.clearMessages();
      _setError("Veuillez sélectionner un produit.");
      return;
    }

    await provider.addSaisieItem(
      lot: _lotController.text,
      datePeremption: _getFormattedDateForApi(),
      quantite: int.tryParse(_qteController.text) ?? 0,
    );

    // Si succès, on réinitialise le formulaire pour la saisie suivante
    if (provider.errorMessage == null) {
      _resetForm();
    }
  }

  Future<void> _validateSaisie() async {
    final provider = Provider.of<PerimeProvider>(context, listen: false);

    final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Valider la Saisie ?'),
          content: Text('Vous êtes sur le point de valider la sortie de ${provider.saisieEnCoursList.length} produit(s) du stock. Cette action est irréversible.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Valider')),
          ],
        )
    );

    if (confirm == true) {
      await provider.validateSaisie();
      if (context.mounted && provider.errorMessage != null) {
        Constants.showSnackBar(context, provider.errorMessage!, isError: true);
      } else if (context.mounted && provider.successMessage.isNotEmpty) {
        Constants.showSnackBar(context, provider.successMessage);
      }
    }
  }

  // Helper local pour afficher l'erreur
  void _setError(String msg) {
    Constants.showSnackBar(context, msg, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PerimeProvider>(context);

    // MODIFICATION : Utilisation d'un Stack à la racine
    return Stack(
      children: [
        // 1. Contenu principal (Formulaire + Liste)
        Column(
          children: [
            // 1a. Zone de Saisie (n'est plus un Stack)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: provider.selectedProduct == null
                  ? _buildSearchField(provider) // Etape 1: Recherche
                  : _buildEntryForm(provider), // Etape 2: Saisie
            ),

            // 1b. Liste des produits en cours
            if (provider.isLoading && provider.saisieEnCoursList.isEmpty)
              const LinearProgressIndicator(),

            Expanded(
              child: RefreshIndicator(
                onRefresh: () => provider.loadSaisieEnCours(),
                child: ListView.builder(
                  itemCount: provider.saisieEnCoursList.length,
                  itemBuilder: (context, index) {
                    final item = provider.saisieEnCoursList[index];
                    return Card(
                      child: ListTile(
                        title: Text(item.produitLibelle, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Lot: ${item.lot} | Qté: ${item.quantity} | Péremption: ${item.datePeremption}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: AppColors.error),
                          onPressed: () => provider.deleteSaisieItem(item.id),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // 1c. Bouton de validation
            if (provider.saisieEnCoursList.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Valider la Saisie'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                  onPressed: provider.isLoading ? null : _validateSaisie,
                ),
              )
          ],
        ),

        // 2. Overlay de recherche
        // Affiche la liste des résultats de recherche par-dessus
        if (provider.productSearchResults.isNotEmpty)
          _buildSearchResults(provider),
      ],
    );
  }

  // CETTE FONCTION N'EST PLUS UTILISEE
  /*
  Widget _buildSaisieForm(PerimeProvider provider) {
    // MODIFICATION : Ajout de 'clipBehavior: Clip.none'
    return Stack(
      clipBehavior: Clip.none, // Permet à la liste de "dépasser"
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: provider.selectedProduct == null
              ? _buildSearchField(provider) // Etape 1: Recherche
              : _buildEntryForm(provider), // Etape 2: Saisie
        ),

        // Affiche la liste des résultats de recherche par-dessus
        if (provider.productSearchResults.isNotEmpty)
          _buildSearchResults(provider),
      ],
    );
  }
  */

  Widget _buildSearchField(PerimeProvider provider) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      decoration: InputDecoration(
        labelText: 'Rechercher Produit (CIP, Nom, Scan)',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: provider.isLoading
            ? const Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator())
            : (_searchController.text.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
          _searchController.clear();
          provider.searchProduct('');
        })
            : null),
      ),
      onSubmitted: (_) => _onSearchChanged(),
    );
  }

  Widget _buildEntryForm(PerimeProvider provider) {
    final product = provider.selectedProduct!;
    return Form(
      key: _formKey,
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                        product.strNAME,
                        style: Theme.of(context).textTheme.titleMedium
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _resetForm,
                  )
                ],
              ),
              Text('CIP: ${product.intCIP} | Stock: ${product.intNUMBERAVAILABLE}',
                style: const TextStyle(color: Colors.black54),
              ),
              const Divider(),
              TextFormField(
                controller: _dateController,
                focusNode: _dateFocusNode,
                decoration: const InputDecoration(labelText: 'Date Péremption (JJMMYY ou MMYY) *'),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (!_formatAndValidateDate(value ?? '')) {
                    return 'Date invalide (JJMMYY ou MMYY)';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_lotFocusNode),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _lotController,
                      focusNode: _lotFocusNode,
                      decoration: const InputDecoration(labelText: 'N° Lot *'),
                      textInputAction: TextInputAction.next,
                      validator: (val) => (val?.isEmpty ?? true) ? 'Requis' : null,
                      onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_qteFocusNode),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      controller: _qteController,
                      focusNode: _qteFocusNode,
                      decoration: const InputDecoration(labelText: 'Quantité *'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submitItem(),
                      validator: (val) {
                        final q = int.tryParse(val ?? '0');
                        if (q == null || q <= 0) return 'Invalide';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter à la liste'),
                  onPressed: provider.isLoading ? null : _submitItem,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults(PerimeProvider provider) {
    // MODIFICATION : Positionné par rapport au Stack racine
    return Positioned(
      top: 65, // En dessous de la barre de recherche
      left: 8,
      right: 8,
      child: Container(
        // S'assure que le 'z-index' est élevé
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.4,
        ),
        child: Card(
          elevation: 0, // Géré par le BoxDecoration au-dessus
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: provider.productSearchResults.length,
            itemBuilder: (context, index) {
              final product = provider.productSearchResults[index];
              return ListTile(
                title: Text(product.strNAME),
                subtitle: Text('CIP: ${product.intCIP} | Stock: ${product.intNUMBERAVAILABLE}'),
                onTap: () {
                  _searchFocusNode.unfocus();
                  provider.selectProduct(product);
                  // Met le focus sur le premier champ du formulaire
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      FocusScope.of(context).requestFocus(_dateFocusNode);
                    }
                  });
                },
              );
            },
          ),
        ),
      ),
    );
  }
}