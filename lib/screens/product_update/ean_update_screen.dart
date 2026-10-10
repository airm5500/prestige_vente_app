// lib/screens/product_update/ean_update_screen.dart
// 11/11/2025 12:20 (Utilisation du champ codeEanFabriquant strict)
// 10/10/2026 : présentations A/B/C, contrôle du code EAN (longueur, clé EAN-13), pas de double envoi.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/providers/product_update_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

/// Longueurs acceptées pour un code EAN / GTIN.
const List<int> eanLengths = [8, 12, 13, 14];

/// Clé de contrôle EAN-13 calculée sur les 12 premiers chiffres.
int ean13CheckDigit(String first12) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += (first12.codeUnitAt(i) - 48) * (i.isEven ? 1 : 3);
  }
  return (10 - sum % 10) % 10;
}

/// Contrôle d'un code EAN saisi : null si valide, sinon le message à afficher.
String? validateEanCode(String? raw) {
  final code = (raw ?? '').trim();
  if (code.isEmpty) return 'Veuillez saisir un code';
  if (!RegExp(r'^\d+$').hasMatch(code)) return 'Le code EAN ne doit contenir que des chiffres.';
  if (!eanLengths.contains(code.length)) {
    return 'Longueur invalide (${code.length} chiffres) : un EAN fait 8, 12, 13 ou 14 chiffres.';
  }
  if (code.length == 13) {
    final expected = ean13CheckDigit(code.substring(0, 12));
    if (code.codeUnitAt(12) - 48 != expected) {
      return 'Clé EAN-13 incorrecte : le dernier chiffre devrait être $expected. Vérifiez le code.';
    }
  }
  return null;
}

class EanUpdateScreen extends StatefulWidget {
  /// Présentation (A, B, C) ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;
  const EanUpdateScreen({super.key, this.presentation});
  @override
  State<EanUpdateScreen> createState() => _EanUpdateScreenState();
}

class _EanUpdateScreenState extends State<EanUpdateScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounce;

  final _eanController = TextEditingController();
  final _eanFocusNode = FocusNode();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false; // garde contre le double envoi (confirmation comprise)
  bool _sending = false; // envoi en cours : bouton remplacé par l'indicateur
  String? _prefilledFor;
  String? _focusedFor;

  void _setupFocusNodeSelection(FocusNode node, TextEditingController controller) {
    node.addListener(() {
      if (node.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    loadPresentation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<ProductUpdateProvider>(context, listen: false).clearAll();
      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
    _searchController.addListener(_onSearchChanged);
    _setupFocusNodeSelection(_eanFocusNode, _eanController);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    _eanController.dispose();
    _eanFocusNode.dispose();
    super.dispose();
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      final provider = Provider.of<ProductUpdateProvider>(context, listen: false);
      final query = _searchController.text.trim();

      if (query.isEmpty) return;

      try {
        await provider.search(query);
      } catch (_) {
        if (mounted) Constants.showSnackBar(context, 'Recherche impossible. Vérifiez la connexion au serveur.', isError: true);
        return;
      }

      if (mounted && provider.searchResults.length == 1) {
        _openProduct(provider, provider.searchResults.first);
      }
    });
  }

  void _openProduct(ProductUpdateProvider provider, ProductSearchResult product) {
    _searchFocusNode.unfocus();
    _eanController.clear();
    _prefilledFor = null;
    _focusedFor = null;
    provider.selectProduct(product).catchError((_) {
      if (mounted) Constants.showSnackBar(context, 'Fiche produit non chargée. Vérifiez la connexion au serveur.', isError: true);
    });
    _searchController.clear();
  }

  void _resetForm() {
    Provider.of<ProductUpdateProvider>(context, listen: false).clearSelection();
    _eanController.clear();
    _prefilledFor = null;
    _focusedFor = null;
    FocusScope.of(context).requestFocus(_searchFocusNode);
    _searchController.selection = TextSelection(baseOffset: 0, extentOffset: _searchController.text.length);
  }

  Future<bool> _confirmReplace(String current, String next) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Remplacer l\'EAN Fabricant ?'),
        content: Text('Code actuel : $current\nNouveau code : $next'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          ElevatedButton(style: navyButton, onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Remplacer')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _submitForm() async {
    if (_busy) return; // pas de double envoi
    final provider = Provider.of<ProductUpdateProvider>(context, listen: false);
    if (provider.isLoading || provider.selectedProduct == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      _eanFocusNode.requestFocus();
      return;
    }

    final ean = _eanController.text.trim();
    final current = provider.selectedProductDetails?.codeEanFabriquant.trim() ?? '';
    _busy = true;
    try {
      if (current.isNotEmpty && current != ean && !await _confirmReplace(current, ean)) return;
      if (!mounted) return;
      setState(() => _sending = true);

      bool success;
      try {
        success = await provider.updateEAN(ean);
      } catch (_) {
        success = false;
      }

      if (!mounted) return;
      if (success) {
        Constants.showSnackBar(context, 'EAN mis à jour avec succès.');
        _resetForm();
      } else {
        Constants.showSnackBar(context, provider.errorMessage ?? 'Échec de la mise à jour', isError: true);
      }
    } finally {
      _busy = false;
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProductUpdateProvider>(
      builder: (context, provider, child) {
        final selected = provider.selectedProduct != null;
        final waiting = provider.isLoading || _sending;
        return PresentationScaffold(
          style: style,
          title: 'Mise à jour EAN Fabricant',
          subtitle: style == ListPresentation.dashboard ? 'Scannez ou recherchez le produit' : null,
          actions: (c) => [PresentationMenuButton(value: style, onChanged: _setStyle, color: c)],
          steps: StepsBar(active: selected ? 1 : 0, steps: const [
            (title: 'Produit', detail: 'scan ou recherche', onTap: null),
            (title: 'Code EAN', detail: '8 à 14 chiffres', onTap: null),
            (title: 'Validation', detail: 'sur Prestige', onTap: null),
          ]),
          header: [_buildSearchBar(provider, dark: true)],
          compactHeader: [_buildSearchBar(provider, dark: false)],
          body: Column(
            children: [
              if (provider.isLoading && provider.selectedProduct == null) const LinearProgressIndicator(minHeight: 2),
              Expanded(child: selected ? _buildUpdateForm(provider) : _buildSearchResults(provider)),
            ],
          ),
          // « Valider » toujours visible pendant la saisie.
          bottomNavigationBar: selected
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: SizedBox(
                      height: 52,
                      child: waiting
                          ? const Center(child: CircularProgressIndicator())
                          : ElevatedButton.icon(
                              style: style == ListPresentation.guided ? amberButton : navyButton,
                              icon: const Icon(Icons.check_circle),
                              onPressed: _submitForm,
                              label: const Text('Valider', style: TextStyle(fontSize: 17)),
                            ),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildSearchBar(ProductUpdateProvider provider, {required bool dark}) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      inputFormatters: [LengthLimitingTextInputFormatter(60)],
      decoration: InputDecoration(
        hintText: 'Rechercher par CIP, Nom ou Scan',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: dark ? Colors.white : Pal.page,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        suffixIcon: IconButton(
          icon: const Icon(Icons.clear),
          tooltip: 'Effacer',
          onPressed: () {
            _searchController.clear();
            _eanController.clear();
            provider.clearAll();
            _searchFocusNode.requestFocus();
          },
        ),
      ),
      onSubmitted: (_) => _onSearchChanged(),
      textInputAction: TextInputAction.search,
    );
  }

  Widget _buildSearchResults(ProductUpdateProvider provider) {
    final query = _searchController.text.trim();
    if (provider.searchResults.isEmpty) {
      final String text;
      if (query.isNotEmpty && query.length < 3) {
        text = 'Saisissez au moins 3 caractères.';
      } else if (query.isNotEmpty && !provider.isLoading) {
        text = 'Aucun produit trouvé.';
      } else {
        text = 'Scannez le code du produit ou recherchez-le par nom ou CIP.';
      }
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Icon(Icons.qr_code_scanner, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: Pal.ink)),
          ]),
        ),
      ]);
    }
    final compact = style == ListPresentation.compact;
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(compact ? 0 : 12, 10, compact ? 0 : 12, 16),
      itemCount: provider.searchResults.length,
      separatorBuilder: (_, __) => SizedBox(height: compact ? 0 : 8),
      itemBuilder: (context, index) {
        final product = provider.searchResults[index];
        void open() => _openProduct(provider, product);
        final row = Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.strNAME.trim().isEmpty ? '—' : product.strNAME,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink)),
              Text('CIP: ${product.intCIP} | Stock: ${product.intNUMBERAVAILABLE}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
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
  }

  InputDecoration _fieldDeco(String label, {String? helper}) => InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: const Icon(Icons.qr_code_scanner),
        errorMaxLines: 3,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC5D0DE))),
      );

  Widget _buildUpdateForm(ProductUpdateProvider provider) {
    final product = provider.selectedProduct!;
    final details = provider.selectedProductDetails;

    // On ne pré-remplit (une seule fois par produit) que si le "vrai" code Fabricant existe.
    if (details != null && _prefilledFor != product.lgFAMILLEID) {
      _prefilledFor = product.lgFAMILLEID;
      if (_eanController.text.isEmpty && details.codeEanFabriquant.isNotEmpty) {
        _eanController.value = TextEditingValue(text: details.codeEanFabriquant);
      }
    }

    // Focus sur le champ EAN une seule fois par produit, une fois la fiche chargée.
    if (!provider.isLoading && _focusedFor != product.lgFAMILLEID) {
      _focusedFor = product.lgFAMILLEID;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).requestFocus(_eanFocusNode);
      });
    }

    final String eanDisplay;
    if (provider.isLoading && details == null) {
      eanDisplay = 'EAN Fabricant : …';
    } else if (details != null && details.codeEanFabriquant.isNotEmpty) {
      eanDisplay = 'EAN Fabricant actuel : ${details.codeEanFabriquant}';
    } else {
      eanDisplay = 'Aucun EAN Fabricant enregistré';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: SoftCard(
        band: style == ListPresentation.guided ? Pal.navy : null,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(product.strNAME.trim().isEmpty ? '—' : product.strNAME,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.ink)),
                  ),
                  IconButton(icon: const Icon(Icons.close), tooltip: 'Fermer', onPressed: _sending ? null : _resetForm),
                ],
              ),
              Text('CIP: ${product.intCIP.trim().isEmpty ? '—' : product.intCIP}', style: const TextStyle(color: Pal.muted)),
              Text(eanDisplay, style: const TextStyle(color: Pal.muted)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _eanController,
                focusNode: _eanFocusNode,
                enabled: !_sending,
                decoration: _fieldDeco(
                  'Code EAN Fabricant',
                  helper: '8, 12, 13 ou 14 chiffres (clé EAN-13 vérifiée)',
                ),
                maxLength: 14, // compteur de chiffres affiché
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(14)],
                textInputAction: TextInputAction.done,
                validator: validateEanCode,
                onFieldSubmitted: (_) => _submitForm(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
