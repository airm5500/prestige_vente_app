// lib/screens/expiration_update/expiration_update_screen.dart
// 11/11/2025 12:00 (Ajout Auto-Open & Focus)
// 23/09/2026 (Ajout lecture DataMatrix : produit, lot et péremption pré-remplis)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/providers/expiration_update_provider.dart';
import 'package:prestige_vente_app/services/datamatrix_parser.dart';
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
  final _dateFieldKey = GlobalKey<FormFieldState<String>>();
  final _lotFieldKey = GlobalKey<FormFieldState<String>>();
  final _dateController = TextEditingController();
  final _lotController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');

  final _dateFocusNode = FocusNode();
  final _lotFocusNode = FocusNode();
  final _quantityFocusNode = FocusNode();

  static final _displayDateFormat = DateFormat('dd/MM/yyyy');

  // --- DataMatrix ---
  DataMatrixData? _scanData; // Dernier DataMatrix lu (lot / péremption à reporter)
  bool _scanProductNotFound = false;
  bool _scanAwaitingProduct = false; // Scan pas encore reporté sur un produit
  List<String> _lotChoices = const [];
  List<DateTime> _expiryChoices = const [];
  Timer? _fieldScanDebounce;
  int _searchSeq = 0; // Ignore les réponses de recherche devenues obsolètes
  String? _focusedProductId; // Produit pour lequel le focus initial a déjà été donné

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
    _searchController.dispose(); _searchFocusNode.dispose(); _debounce?.cancel(); _fieldScanDebounce?.cancel();
    _dateController.dispose(); _lotController.dispose(); _quantityController.dispose();
    _dateFocusNode.dispose(); _lotFocusNode.dispose(); _quantityFocusNode.dispose();
    super.dispose();
  }

  // MODIFICATION : Logique Auto-Open
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final provider = Provider.of<ExpirationUpdateProvider>(context, listen: false);
      final query = _searchController.text;

      if (query.isEmpty) return;

      // 0. Lecture d'un DataMatrix : recherche par GTIN + pré-remplissage lot / date
      final scan = DataMatrixParser.parse(query);
      if (scan != null) {
        await _handleScan(scan);
        return;
      }

      // 1. Lance la recherche
      final seq = ++_searchSeq;
      await provider.search(query);
      if (seq != _searchSeq) return;

      // 2. Si résultat unique, on sélectionne automatiquement
      if (mounted && provider.searchResults.length == 1) {
        final product = provider.searchResults.first;

        _selectProduct(product);
        _searchController.clear(); // Nettoyage immédiat
        // Le focus ira sur le formulaire grâce au bloc 'else' du build (via selectProduct)
      }
    });
  }

  /// Traite un DataMatrix lu (depuis la recherche ou depuis un champ du formulaire) :
  /// retrouve le produit par son GTIN puis pré-remplit le lot et la péremption.
  /// Si le produit n'est pas trouvé, [fallbackProduct] (produit déjà affiché) est conservé.
  Future<void> _handleScan(DataMatrixData scan, {ProductSearchResult? fallbackProduct}) async {
    final provider = Provider.of<ExpirationUpdateProvider>(context, listen: false);
    final seq = ++_searchSeq;
    _debounce?.cancel();
    _fieldScanDebounce?.cancel();

    _clearFormFields();
    provider.clearSearch();
    _searchController.clear();
    setState(() {
      _scanData = scan;
      _scanProductNotFound = false;
      _scanAwaitingProduct = true;
      _lotChoices = const [];
      _expiryChoices = const [];
      _focusedProductId = null;
    });

    final queries = scan.productSearchQueries;
    if (queries.isNotEmpty) {
      await provider.searchFirstMatch(queries);
      if (!mounted || seq != _searchSeq) return;
    }

    final results = provider.searchResults;
    if (results.length == 1) {
      _selectProduct(results.first);
    } else if (results.isEmpty) {
      setState(() => _scanProductNotFound = true);
      if (fallbackProduct != null) {
        _selectProduct(fallbackProduct);
      } else {
        FocusScope.of(context).requestFocus(_searchFocusNode);
      }
    }
    // Plusieurs résultats : l'opérateur choisit dans la liste, le scan sera appliqué.
  }

  void _selectProduct(ProductSearchResult product) {
    if (_scanData != null && !_scanAwaitingProduct) {
      // Le scan a déjà été reporté sur un autre produit : il ne concerne pas celui-ci.
      _discardScan();
      _dateController.clear();
      _lotController.clear();
      _quantityController.text = '1';
    }
    Provider.of<ExpirationUpdateProvider>(context, listen: false).selectProduct(product);
    _applyScanToForm();
  }

  void _applyScanToForm() {
    final scan = _scanData;
    if (scan == null || !_scanAwaitingProduct) return;
    final expiry = scan.expiry;
    _dateController.text = expiry != null ? _displayDateFormat.format(expiry) : '';
    _lotController.text = scan.lot ?? '';
    _quantityController.text = '1';
    setState(() {
      _lotChoices = scan.lot == null ? scan.lotCandidates : const [];
      _expiryChoices = expiry == null ? scan.expiryCandidates : const [];
      _scanAwaitingProduct = false;
      _focusedProductId = null;
    });
  }

  bool _isExpired(DateTime date) => date.isBefore(DateTime.now().subtract(const Duration(days: 1)));

  /// Premier champ à renseigner : date, lot puis quantité.
  FocusNode _initialFormFocus() {
    final expiry = _scanData?.expiry;
    if (_dateController.text.isEmpty || (expiry != null && _isExpired(expiry))) return _dateFocusNode;
    if (_lotController.text.isEmpty) return _lotFocusNode;
    return _quantityFocusNode;
  }

  /// Un DataMatrix lu alors que le curseur est dans un champ du formulaire.
  void _onFormFieldChanged(String value) {
    _fieldScanDebounce?.cancel();
    if (value.length < 16) return;
    _fieldScanDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _interceptScan(value);
    });
  }

  bool _interceptScan(String value) {
    if (value.length < 16) return false;
    final scan = DataMatrixParser.parse(value);
    if (scan == null) return false;
    _fieldScanDebounce?.cancel();
    final current = Provider.of<ExpirationUpdateProvider>(context, listen: false).selectedProduct;
    _handleScan(scan, fallbackProduct: current);
    return true;
  }

  void _discardScan() {
    setState(() {
      _scanData = null;
      _scanProductNotFound = false;
      _scanAwaitingProduct = false;
      _lotChoices = const [];
      _expiryChoices = const [];
    });
  }

  void _clearFormFields() {
    if (_formKey.currentState != null) {
      _formKey.currentState!.reset();
    }
    _dateController.clear();
    _lotController.clear();
    _quantityController.text = '1';
  }

  void _resetForm() {
    final provider = Provider.of<ExpirationUpdateProvider>(context, listen: false);
    _searchSeq++;
    _fieldScanDebounce?.cancel();
    provider.clearSelection();
    _clearFormFields();
    setState(() {
      _scanData = null;
      _scanProductNotFound = false;
      _scanAwaitingProduct = false;
      _lotChoices = const [];
      _expiryChoices = const [];
      _focusedProductId = null;
    });

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
    // Un DataMatrix lu dans un champ ne doit jamais être envoyé comme valeur.
    for (final controller in [_dateController, _lotController, _quantityController]) {
      if (_interceptScan(controller.text)) return;
    }

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
              if (_scanData != null) _buildScanBanner(_scanData!, provider),
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
          labelText: 'Rechercher par CIP, Nom ou Scan (DataMatrix)',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              provider.clearSearch();
              // MODIFICATION : Maintien du focus
              _searchFocusNode.requestFocus();
            },
          ),
        ),
        onSubmitted: (_) => _onSearchChanged(),
        textInputAction: TextInputAction.search,
      ),
    );
  }

  Widget _buildScanBanner(DataMatrixData scan, ExpirationUpdateProvider provider) {
    final expiry = scan.expiry;
    final code = scan.ean13 ?? scan.gtin ?? scan.productCode ?? 'non lu';
    final lotText = scan.lot ?? (scan.isLotAmbiguous ? 'à choisir' : 'non lu');
    final dateText = expiry != null
        ? _displayDateFormat.format(expiry)
        : scan.isExpiryAmbiguous
            ? 'à choisir'
            : scan.invalidExpiry
                ? 'invalide'
                : 'non lue';

    final warnings = <String>[
      if (expiry != null && _isExpired(expiry)) 'Produit périmé : la date ne peut pas être enregistrée.',
      if (scan.invalidExpiry) 'Date de péremption illisible dans le code : saisissez-la.',
      if (scan.isLotAmbiguous) 'Lot ambigu dans le code : choisissez la valeur imprimée sur la boîte.',
      if (scan.isExpiryAmbiguous) 'Date ambiguë dans le code : choisissez la valeur imprimée sur la boîte.',
      if (_scanProductNotFound && provider.selectedProduct != null)
        'Code produit introuvable : vérifiez que la boîte correspond bien au produit affiché.',
      if (_scanProductNotFound && provider.selectedProduct == null)
        'Produit introuvable pour ce code : recherchez-le par nom ou CIP, le lot et la date seront repris.',
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 8.0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2.0, right: 8.0),
            child: Icon(Icons.qr_code_2, color: AppColors.primary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('DataMatrix lu', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Code : $code'),
                Text('Lot : $lotText  |  Péremption : $dateText'),
                for (final w in warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(w, style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w500)),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Ignorer ce scan',
            onPressed: _discardScan,
          ),
        ],
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
              _selectProduct(product);
              _searchController.clear(); // Nettoyage manuel si clic
            },
          ),
        );
      },
    );
  }

  Widget _buildChoices<T>({
    required String label,
    required List<T> values,
    required String Function(T) format,
    required void Function(T) onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.orange.shade900, fontSize: 12)),
          Wrap(
            spacing: 8.0,
            children: [
              for (final v in values)
                ActionChip(label: Text(format(v)), onPressed: () => onSelected(v)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateForm(ExpirationUpdateProvider provider) {
    final product = provider.selectedProduct!;

    // Focus initial une seule fois par produit (et non à chaque reconstruction)
    if (_focusedProductId != product.lgFAMILLEID) {
      _focusedProductId = product.lgFAMILLEID;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          FocusScope.of(context).requestFocus(_initialFormFocus());
        }
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
                Text('CIP: ${product.intCIP}'),
                const Divider(height: 30),
                TextFormField(
                  key: _dateFieldKey,
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
                  onChanged: _onFormFieldChanged,
                  onFieldSubmitted: (value) {
                    if (_interceptScan(value)) return;
                    if (_dateFieldKey.currentState?.validate() ?? false) {
                      FocusScope.of(context).requestFocus(_lotFocusNode);
                    }
                  },
                ),
                if (_expiryChoices.isNotEmpty)
                  _buildChoices<DateTime>(
                    label: 'Date ambiguë dans le DataMatrix, choisissez :',
                    values: _expiryChoices,
                    format: _displayDateFormat.format,
                    onSelected: (d) {
                      _dateController.text = _displayDateFormat.format(d);
                      setState(() => _expiryChoices = const []);
                      FocusScope.of(context).requestFocus(_lotController.text.isEmpty ? _lotFocusNode : _quantityFocusNode);
                    },
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  key: _lotFieldKey,
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
                  onChanged: _onFormFieldChanged,
                  onFieldSubmitted: (value) {
                    if (_interceptScan(value)) return;
                    if (_lotFieldKey.currentState?.validate() ?? false) {
                      FocusScope.of(context).requestFocus(_quantityFocusNode);
                    }
                  },
                ),
                if (_lotChoices.isNotEmpty)
                  _buildChoices<String>(
                    label: 'Lot ambigu dans le DataMatrix, choisissez :',
                    values: _lotChoices,
                    format: (v) => v,
                    onSelected: (v) {
                      _lotController.text = v;
                      setState(() => _lotChoices = const []);
                      FocusScope.of(context).requestFocus(_quantityFocusNode);
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
                  onChanged: _onFormFieldChanged,
                  onFieldSubmitted: (value) {
                    if (_interceptScan(value)) return;
                    _submitForm();
                  },
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
