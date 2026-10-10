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
import 'package:prestige_vente_app/screens/common/guided_capture_screen.dart';
import 'package:prestige_vente_app/services/datamatrix_parser.dart';
import 'package:prestige_vente_app/services/label_text_parser.dart';
import 'package:prestige_vente_app/services/ocr_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/product_paging.dart';
import 'package:provider/provider.dart';

class ExpirationUpdateScreen extends StatefulWidget {
  /// Remplaçables pour les tests. Par défaut : scanner caméra et photo + OCR ML Kit.
  final Future<String?> Function(BuildContext context)? codeScanner;
  final Future<List<String>?> Function(ImageSource source)? labelReader;

  /// Présentation (A, B, C) ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;

  const ExpirationUpdateScreen({super.key, this.codeScanner, this.labelReader, this.presentation});

  @override
  State<ExpirationUpdateScreen> createState() => _ExpirationUpdateScreenState();
}

class _ExpirationUpdateScreenState extends State<ExpirationUpdateScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

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
  ProductSearchResult? _otherProduct; // Produit auquel correspond le code scanné, s'il diffère

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
    loadPresentation();
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

      // 0. Lecture d'un DataMatrix (douchette Sunmi ou caméra)
      final scan = DataMatrixParser.parse(query);
      if (scan != null) {
        await _onScan(scan);
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

  /// Aiguillage d'un scan :
  /// - un produit est affiché : on ne reprend que le lot et la date pour CE produit ;
  /// - aucun produit : on recherche le produit par son code puis on pré-remplit.
  Future<void> _onScan(DataMatrixData scan) async {
    final current = Provider.of<ExpirationUpdateProvider>(context, listen: false).selectedProduct;
    if (current != null) {
      await _applyLotDateToCurrent(scan, current);
    } else {
      await _handleScan(scan);
    }
  }

  /// Reporte uniquement le lot et la péremption du scan sur le produit affiché,
  /// puis place le curseur sur la quantité. Aucune recherche produit n'est relancée.
  Future<void> _applyLotDateToCurrent(DataMatrixData scan, ProductSearchResult current) async {
    final provider = Provider.of<ExpirationUpdateProvider>(context, listen: false);
    final seq = ++_searchSeq;
    _debounce?.cancel();
    _fieldScanDebounce?.cancel();
    if (_searchController.text.isNotEmpty) _searchController.clear();

    if (scan.lotCandidates.isEmpty && scan.expiryCandidates.isEmpty && !scan.invalidExpiry) {
      Constants.showSnackBar(context, 'Ce code ne contient ni lot ni date. Scannez le DataMatrix de la boîte.', isError: true);
      return;
    }

    _formKey.currentState?.reset();
    setState(() {
      _scanData = scan;
      _scanProductNotFound = false;
      _scanAwaitingProduct = true;
      _otherProduct = null;
    });
    _applyScanToForm();

    // Garde-fou : le code correspond-il à un autre produit de la base ?
    final queries = scan.productSearchQueries;
    if (queries.isEmpty) return;
    final found = await provider.lookupFirstMatch(queries);
    if (!mounted || seq != _searchSeq) return;
    if (found.length == 1 && found.first.lgFAMILLEID != current.lgFAMILLEID) {
      setState(() => _otherProduct = found.first);
    }
  }

  /// Traite un DataMatrix lu (depuis la recherche ou depuis un champ du formulaire) :
  /// retrouve le produit par son GTIN puis pré-remplit le lot et la péremption.
  Future<void> _handleScan(DataMatrixData scan) async {
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
      _otherProduct = null;
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
    if (provider.searchError != null) {
      // Panne : ne pas annoncer « produit introuvable ».
      Constants.showSnackBar(context, 'Recherche impossible : ${provider.searchError}', isError: true);
      FocusScope.of(context).requestFocus(_searchFocusNode);
    } else if (results.length == 1) {
      _selectProduct(results.first);
    } else if (results.isEmpty) {
      setState(() => _scanProductNotFound = true);
      FocusScope.of(context).requestFocus(_searchFocusNode);
    }
    // Plusieurs résultats : l'opérateur choisit dans la liste, le scan sera appliqué.
  }

  // ---------------------------------------------------------------------------
  // Aide à la saisie : scan DataMatrix par la caméra, ou photo de l'étiquette
  // ---------------------------------------------------------------------------
  Future<String?> _openCamera(String title, {bool dataMatrixOnly = false}) {
    final scanner = widget.codeScanner ??
        (ctx) => CameraScanScreen.open(ctx, title: title, dataMatrixOnly: dataMatrixOnly);
    return scanner(context);
  }

  /// Icône caméra de la recherche : équivalent exact d'un scan à la douchette Sunmi.
  Future<void> _scanProductWithCamera() async {
    final value = await _openCamera('Scanner le produit');
    if (!mounted || value == null || value.isEmpty) return;
    _searchController.text = value;
    _searchController.selection = TextSelection.collapsed(offset: value.length);
  }

  /// Bouton du formulaire : lit le DataMatrix et ne reprend que le lot et la date.
  Future<void> _scanLotDateWithCamera() async {
    // DataMatrix uniquement : l'EAN de la boîte ne contient ni lot ni date.
    final value = await _openCamera('Scanner le DataMatrix (lot / date)', dataMatrixOnly: true);
    if (!mounted || value == null || value.isEmpty) return;
    final scan = DataMatrixParser.parse(value);
    if (scan == null) {
      Constants.showSnackBar(
        context,
        'Code-barres simple : il ne contient ni lot ni date. Scannez le DataMatrix (petit carré) ou utilisez Photo étiquette.',
        isError: true,
      );
      return;
    }
    await _onScan(scan);
  }

  /// Photo de l'étiquette : capture guidée (cadre, netteté, lumière, recadrage) puis confirmation.
  /// « Reprendre la photo » relance la capture.
  Future<void> _photoLabel() async {
    while (true) {
      if (!mounted) return;
      List<String>? lines;
      setState(() => _readingLabel = true);
      try {
        lines = await (widget.labelReader != null
            ? widget.labelReader!(ImageSource.camera)
            : GuidedCaptureScreen.open(context));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Ni lot ni date lisibles. Cadrez uniquement LOT et EXP, à plat et bien éclairés.'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: 'Reprendre', textColor: Colors.white, onPressed: _photoLabel),
        ));
        return;
      }

      final confirmed = await showDialog<({String lot, DateTime? expiry, bool retake})>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _LabelConfirmDialog(label: label),
      );
      if (confirmed == null || !mounted) return;
      if (confirmed.retake) continue;

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
      await _onScan(data);
      return;
    }
  }

  /// Aide à la saisie du lot et de la date (dans le formulaire du produit affiché).
  Widget _buildAssistButtons() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                style: outlineButton,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scanner lot / date'),
                onPressed: _readingLabel ? null : _scanLotDateWithCamera,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton.icon(
              style: outlineButton,
              icon: _readingLabel
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.document_scanner_outlined),
              label: const Text('Photo étiquette'),
              onPressed: _readingLabel ? null : _photoLabel,
            ),
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
    _onScan(scan);
    return true;
  }

  void _discardScan() {
    setState(() {
      _scanData = null;
      _scanProductNotFound = false;
      _scanAwaitingProduct = false;
      _otherProduct = null;
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
      _otherProduct = null;
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
    return Consumer<ExpirationUpdateProvider>(
      builder: (context, provider, child) {
        final selected = provider.selectedProduct != null;
        return PresentationScaffold(
          style: style,
          title: 'Mise à jour Péremption',
          subtitle: style == ListPresentation.dashboard ? 'Scannez la boîte : produit, lot et date' : null,
          actions: (c) => [PresentationMenuButton(value: style, onChanged: _setStyle, color: c)],
          steps: StepsBar(active: selected ? 1 : 0, steps: const [
            (title: 'Produit', detail: 'scan ou recherche', onTap: null),
            (title: 'Lot et date', detail: 'DataMatrix, photo', onTap: null),
            (title: 'Valider', detail: 'quantité', onTap: null),
          ]),
          header: [_buildSearchBar(provider, dark: true)],
          compactHeader: [_buildSearchBar(provider, dark: false)],
          body: Column(
            children: [
              if (provider.isLoading) const LinearProgressIndicator(minHeight: 2),
              if (_scanData != null) _buildScanBanner(_scanData!, provider),
              Expanded(
                child: provider.selectedProduct == null ? _buildSearchResults(provider) : _buildUpdateForm(provider),
              ),
            ],
          ),
          // « Valider » toujours visible pendant la saisie d'un produit.
          bottomNavigationBar: selected
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: SizedBox(
                      height: 52,
                      child: provider.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : ElevatedButton(
                              style: style == ListPresentation.guided ? amberButton : navyButton,
                              onPressed: _submitForm,
                              child: const Text('Valider', style: TextStyle(fontSize: 17)),
                            ),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  Widget _buildSearchBar(ExpirationUpdateProvider provider, {required bool dark}) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      decoration: InputDecoration(
        labelText: 'Rechercher par CIP, Nom ou Scan (DataMatrix)',
        floatingLabelBehavior: FloatingLabelBehavior.never,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: dark ? Colors.white : Pal.page,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Scan du code-barres avec la caméra : même effet que la douchette Sunmi.
            IconButton(
              icon: const Icon(Icons.photo_camera),
              tooltip: 'Scanner le produit (caméra)',
              onPressed: _scanProductWithCamera,
            ),
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Effacer',
              onPressed: () {
                _searchController.clear();
                provider.clearSearch();
                // MODIFICATION : Maintien du focus
                _searchFocusNode.requestFocus();
              },
            ),
          ],
        ),
      ),
      onSubmitted: (_) => _onSearchChanged(),
      textInputAction: TextInputAction.search,
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
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFB9D0EE)),
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
                if (_otherProduct != null && provider.selectedProduct != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Attention : ce code correspond à « ${_otherProduct!.strNAME} », '
                      'pas au produit affiché. Vérifiez la boîte.',
                      style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      final other = _otherProduct!;
                      setState(() {
                        _otherProduct = null;
                        _scanAwaitingProduct = true;
                      });
                      _selectProduct(other);
                    },
                    child: Text('Utiliser ${_otherProduct!.strNAME}'),
                  ),
                ],
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
    // Panne (réseau, serveur) : jamais « aucun produit ».
    if (provider.searchError != null && !provider.isLoading && _searchController.text.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 40, color: Colors.red.shade700),
            const SizedBox(height: 8),
            Text('Recherche impossible : ${provider.searchError}', textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade900)),
            TextButton(onPressed: _onSearchChanged, child: const Text('Réessayer')),
          ]),
        ),
      );
    }
    if (provider.searchResults.isEmpty && _searchController.text.isNotEmpty) {
      return Center(child: Text(provider.searchNotFound ?? 'Aucun produit trouvé.', textAlign: TextAlign.center));
    }
    if (provider.searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.qr_code_scanner, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('Scannez le DataMatrix de la boîte (scanner ou caméra), ou recherchez le produit.', textAlign: TextAlign.center),
          ]),
        ),
      );
    }
    final compact = style == ListPresentation.compact;
    final paging = provider.productSearch;
    final footer = ProductPagingFooter.visibleFor(paging);
    final list = ListView.separated(
      padding: EdgeInsets.fromLTRB(compact ? 0 : 12, 10, compact ? 0 : 12, 16),
      itemCount: provider.searchResults.length + (footer ? 1 : 0),
      separatorBuilder: (_, __) => SizedBox(height: compact ? 0 : 8),
      itemBuilder: (context, index) {
        if (index >= provider.searchResults.length) return ProductPagingFooter(paging, onLoadMore: provider.loadMoreProducts);
        final product = provider.searchResults[index];
        void open() {
          _searchFocusNode.unfocus();
          _selectProduct(product);
          _searchController.clear(); // Nettoyage manuel si clic
        }

        final stock = product.intNUMBERAVAILABLE;
        final row = Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.strNAME, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink)),
              Text('CIP: ${product.intCIP} | Prix: ${Constants.formatNumber(product.intPRICE)} | Stock: $stock',
                  style: const TextStyle(fontSize: 13, color: Pal.muted)),
            ]),
          ),
          const Icon(Icons.chevron_right, color: Pal.muted),
        ]);
        if (compact) {
          return InkWell(
            onTap: open,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
              child: row,
            ),
          );
        }
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: open,
          child: SoftCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: row),
        );
      },
    );
    // Liste par pages : « 50 sur 120 », la suite se charge en faisant défiler.
    return Column(children: [
      ProductPagingCount(paging),
      Expanded(child: ProductPagingScroll(search: paging, onLoadMore: provider.loadMoreProducts, child: list)),
    ]);
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

  InputDecoration _fieldDeco(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC5D0DE))),
      );

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
      padding: const EdgeInsets.all(12.0),
      child: SoftCard(
        band: style == ListPresentation.guided ? Pal.navy : null,
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(product.strNAME, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.ink))),
                    IconButton(icon: const Icon(Icons.close), tooltip: 'Fermer', onPressed: _resetForm),
                  ],
                ),
                Text('CIP: ${product.intCIP}', style: const TextStyle(color: Pal.muted)),
                const SizedBox(height: 14),
                _buildAssistButtons(),
                TextFormField(
                  key: _dateFieldKey,
                  controller: _dateController,
                  focusNode: _dateFocusNode,
                  decoration: _fieldDeco('Date de Péremption (JJMMYY)'),
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
                  decoration: _fieldDeco('N° de Lot'),
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
                  decoration: _fieldDeco('Quantité'),
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
                const SizedBox(height: 8),
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
    Navigator.of(context).pop((lot: _lot.text.trim().toUpperCase(), expiry: expiry, retake: false));
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
        TextButton(
          onPressed: () => Navigator.of(context).pop((lot: '', expiry: null, retake: true)),
          child: const Text('Reprendre la photo'),
        ),
        ElevatedButton(onPressed: _confirm, child: const Text('Valider')),
      ],
    );
  }
}
