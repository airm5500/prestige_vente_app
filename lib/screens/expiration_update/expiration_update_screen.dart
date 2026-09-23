// lib/screens/expiration_update/expiration_update_screen.dart
// 11/11/2025 12:00 (Ajout Auto-Open & Focus)
// 23/09/2026 (Ajout lecture DataMatrix : produit, lot et péremption pré-remplis)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/providers/expiration_update_provider.dart';
import 'package:prestige_vente_app/screens/common/camera_scan_screen.dart';
import 'package:prestige_vente_app/services/datamatrix_parser.dart';
import 'package:prestige_vente_app/services/label_text_parser.dart';
import 'package:prestige_vente_app/services/ocr_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class ExpirationUpdateScreen extends StatefulWidget {
  /// Remplaçables pour les tests. Par défaut : scanner caméra et photo + OCR ML Kit.
  final Future<String?> Function(BuildContext context)? codeScanner;
  final Future<List<String>?> Function(ImageSource source)? labelReader;

  const ExpirationUpdateScreen({super.key, this.codeScanner, this.labelReader});

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
  bool _readingLabel = false;

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

  // ---------------------------------------------------------------------------
  // Aide à la saisie : scan DataMatrix par la caméra, ou photo de l'étiquette
  // ---------------------------------------------------------------------------
  Future<void> _scanWithCamera() async {
    final scanner = widget.codeScanner ?? (ctx) => CameraScanScreen.open(ctx, title: 'Scanner le DataMatrix');
    final value = await scanner(context);
    if (!mounted || value == null || value.isEmpty) return;
    final scan = DataMatrixParser.parse(value);
    if (scan != null) {
      final current = Provider.of<ExpirationUpdateProvider>(context, listen: false).selectedProduct;
      await _handleScan(scan, fallbackProduct: current);
    } else {
      // Code-barres simple (EAN, CIP) : même traitement qu'une saisie dans la recherche.
      _searchController.text = value;
    }
  }

  Future<void> _photoLabel() async {
    List<String>? lines;
    setState(() => _readingLabel = true);
    try {
      lines = await (widget.labelReader ?? OcrService.captureAndRead)(ImageSource.camera);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(OcrService.friendlyError(e)),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 6),
        ));
      }
    }
    if (!mounted) return;
    setState(() => _readingLabel = false);
    if (lines == null) return;

    final label = LabelTextParser.parse(lines);
    if (label.lotCandidates.isEmpty && label.expiryCandidates.isEmpty) {
      Constants.showSnackBar(
        context,
        'Ni lot ni date lisibles sur la photo. Rapprochez-vous, photo à plat et bien éclairée.',
        isError: true,
      );
      return;
    }

    final confirmed = await showDialog<({String lot, DateTime? expiry})>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LabelConfirmDialog(label: label),
    );
    if (confirmed == null || !mounted) return;

    // Valeurs confirmées par l'opérateur : traitées comme un scan fiable.
    final data = DataMatrixData(
      raw: lines.join('\n'),
      format: DataMatrixFormat.ocrLabel,
      gtin: label.gtin,
      lotCandidates: confirmed.lot.isEmpty ? const [] : [confirmed.lot],
      lotCertain: confirmed.lot.isNotEmpty,
      expiryCandidates: confirmed.expiry == null ? const [] : [confirmed.expiry!],
      expiryCertain: confirmed.expiry != null,
    );
    final current = Provider.of<ExpirationUpdateProvider>(context, listen: false).selectedProduct;
    await _handleScan(data, fallbackProduct: current);
  }

  Widget _buildAssistButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scanner DataMatrix'),
              onPressed: _readingLabel ? null : _scanWithCamera,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              icon: _readingLabel
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.document_scanner_outlined),
              label: const Text('Photo étiquette'),
              onPressed: _readingLabel ? null : _photoLabel,
            ),
          ),
        ],
      ),
    );
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
              _buildAssistButtons(),
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
                Text(
                  scan.format == DataMatrixFormat.ocrLabel ? 'Étiquette lue (valeurs confirmées)' : 'DataMatrix lu',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
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


/// Confirmation obligatoire des valeurs lues par photo : l'OCR peut se tromper
/// (0/O, 1/I, 5/S...). Rien n'est enregistré sans validation de l'opérateur.
class _LabelConfirmDialog extends StatefulWidget {
  final LabelData label;
  const _LabelConfirmDialog({required this.label});

  @override
  State<_LabelConfirmDialog> createState() => _LabelConfirmDialogState();
}

class _LabelConfirmDialogState extends State<_LabelConfirmDialog> {
  static final _fmt = DateFormat('dd/MM/yyyy');
  late final _lot = TextEditingController(text: widget.label.lotCandidates.isEmpty ? '' : widget.label.lotCandidates.first);
  late final _date = TextEditingController(
    text: widget.label.expiryCandidates.isEmpty ? '' : _fmt.format(widget.label.expiryCandidates.first),
  );
  String? _dateError;

  @override
  void dispose() {
    _lot.dispose();
    _date.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _date.text.trim();
    DateTime? expiry;
    if (text.isNotEmpty) {
      try {
        expiry = _fmt.parseStrict(text);
      } catch (_) {
        setState(() => _dateError = 'Format attendu : JJ/MM/AAAA');
        return;
      }
    }
    Navigator.of(context).pop((lot: _lot.text.trim().toUpperCase(), expiry: expiry));
  }

  Widget _chips<T>(List<T> values, String Function(T) format, void Function(T) onTap) {
    if (values.length < 2) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      children: [for (final v in values) ActionChip(label: Text(format(v)), onPressed: () => onTap(v))],
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final warn = TextStyle(color: Colors.orange.shade900, fontSize: 12);
    return AlertDialog(
      title: const Text('Vérifiez avec la boîte'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Comparez chaque caractère avec l\'emballage avant de valider.', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: _lot,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'N° de Lot', border: OutlineInputBorder()),
            ),
            if (label.lotCandidates.isNotEmpty && !label.lotFromLabel)
              Text('Lot proposé sans libellé "LOT" : à vérifier.', style: warn),
            _chips<String>(label.lotCandidates, (v) => v, (v) => setState(() => _lot.text = v)),
            const SizedBox(height: 12),
            TextField(
              controller: _date,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                labelText: 'Date de péremption (JJ/MM/AAAA)',
                border: const OutlineInputBorder(),
                errorText: _dateError,
              ),
            ),
            if (label.expiryCandidates.isNotEmpty && !label.expiryFromLabel)
              Text('Date déduite sans libellé "EXP" : à vérifier.', style: warn),
            _chips<DateTime>(label.expiryCandidates, _fmt.format, (d) => setState(() => _date.text = _fmt.format(d))),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Texte lu sur la photo', style: TextStyle(fontSize: 13)),
              children: [
                for (final l in label.rawLines)
                  Align(alignment: Alignment.centerLeft, child: Text(l, style: const TextStyle(fontSize: 12))),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        ElevatedButton(onPressed: _confirm, child: const Text('Valider')),
      ],
    );
  }
}
