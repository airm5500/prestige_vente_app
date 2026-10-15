// lib/screens/product_update/ean_update_screen.dart
// 11/11/2025 12:20 (Utilisation du champ codeEanFabriquant strict)
// 10/10/2026 : présentations A/B/C, pas de double envoi.
// 15/10/2026 : confirmation avant chaque enregistrement (produit, ancien → nouvel EAN), « Oui » par défaut
// (Entrée / OK de la douchette).
// 4.3.0 (décision du pharmacien) : on enregistre la valeur lue, sans AUCUN contrôle (chiffres, longueur, clé de
// contrôle : supprimés) ; la confirmation suffit : « Non » ferme et remet le curseur dans le champ, valeur gardée.
// Champ vide : rien n'est envoyé. Écran commun à la nouvelle et à l'ancienne interface.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/providers/product_update_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/product_paging.dart';
import 'package:provider/provider.dart';

/// Valeur à enregistrer : le code lu ou saisi, tel quel (espaces et retour à la ligne de la douchette retirés aux
/// extrémités). 4.3.0, décision du pharmacien : AUCUN contrôle (ni chiffres, ni longueur, ni clé) ; seule une
/// valeur vide n'est pas envoyée.
String eanAEnregistrer(String? raw) => (raw ?? '').trim();

/// Confirmation AVANT d'enregistrer l'EAN fabricant : produit, ancien EAN → nouvel EAN, « Oui » / « Non ».
/// « Oui » est le bouton par défaut (un appui, ou Entrée / OK de la douchette) ; « Non » ne change rien : la
/// fenêtre se ferme et le curseur revient dans le champ, valeur conservée pour la corriger.
class EanConfirmationDialog extends StatelessWidget {
  final String produit;
  final String cip;
  final String ancien;
  final String nouveau;
  const EanConfirmationDialog({super.key, required this.produit, required this.cip, required this.ancien, required this.nouveau});

  static Future<bool> afficher(BuildContext context, {required String produit, required String cip, required String ancien, required String nouveau}) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => EanConfirmationDialog(produit: produit, cip: cip, ancien: ancien, nouveau: nouveau),
      ) ==
      true;

  Widget _ligne(String libelle, String valeur, {Key? key, Color couleur = Pal.ink, bool fort = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 92, child: Text(libelle, style: const TextStyle(fontSize: 13.5, color: Pal.muted))),
          Expanded(
            child: Text(valeur, key: key, style: TextStyle(fontSize: 15, color: couleur, fontWeight: fort ? FontWeight.bold : FontWeight.w500)),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final identique = ancien.trim() == nouveau.trim();
    return AlertDialog(
      key: const ValueKey('ean-confirmation'),
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(ancien.trim().isEmpty ? 'Enregistrer l\'EAN Fabricant ?' : 'Remplacer l\'EAN Fabricant ?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _ligne('Produit', produit.trim().isEmpty ? '—' : produit, key: const ValueKey('ean-confirmation-produit'), fort: true),
        if (cip.trim().isNotEmpty) _ligne('CIP', cip),
        const Divider(height: 18),
        _ligne('Ancien EAN', ancien.trim().isEmpty ? 'aucun' : ancien, key: const ValueKey('ean-confirmation-ancien'), couleur: Pal.muted),
        _ligne('Nouvel EAN', nouveau, key: const ValueKey('ean-confirmation-nouveau'), couleur: Pal.navy, fort: true),
        if (identique)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Code identique à l\'EAN actuel.', key: ValueKey('ean-confirmation-identique'), style: TextStyle(fontSize: 13, color: Pal.muted)),
          ),
      ]),
      actions: [
        TextButton(
          key: const ValueKey('ean-confirmation-annuler'),
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Non'),
        ),
        ElevatedButton.icon(
          key: const ValueKey('ean-confirmation-enregistrer'),
          autofocus: true, // bouton par défaut : Entrée / OK de la douchette
          style: navyButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(120, 48))),
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.check_circle),
          label: const Text('Oui'),
        ),
      ],
    );
  }
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
      // Panne (réseau, serveur) : jamais « aucun produit trouvé ».
      if (mounted && provider.searchError != null) {
        Constants.showSnackBar(context, 'Recherche impossible : ${provider.searchError}', isError: true);
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

  Future<void> _submitForm() async {
    if (_busy) return; // pas de double envoi
    final provider = Provider.of<ProductUpdateProvider>(context, listen: false);
    if (provider.isLoading || provider.selectedProduct == null) return;
    final ean = eanAEnregistrer(_eanController.text);
    if (ean.isEmpty) {
      // Rien à enregistrer (seul cas sans confirmation) : le curseur reste dans le champ.
      _eanFocusNode.requestFocus();
      return;
    }

    final current = provider.selectedProductDetails?.codeEanFabriquant.trim() ?? '';
    final product = provider.selectedProduct!;
    _busy = true;
    try {
      // Confirmation TOUJOURS demandée avant d'enregistrer (produit, ancien → nouvel EAN).
      final ok = await EanConfirmationDialog.afficher(context, produit: product.strNAME, cip: product.intCIP, ancien: current, nouveau: ean);
      if (!mounted) return;
      if (!ok) {
        // « Non » : rien n'est envoyé ; curseur dans le champ, valeur gardée (sélectionnée : un nouveau scan la
        // remplace, une frappe la corrige).
        _remettreFocusChamp();
        return;
      }
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

  /// Curseur dans le champ EAN après la fermeture de la confirmation (le focus que la fenêtre rend à l'écran est
  /// repris à l'image suivante).
  void _remettreFocusChamp() {
    _eanFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_eanFocusNode.hasFocus) _eanFocusNode.requestFocus();
    });
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
            (title: 'Code EAN', detail: 'scan ou saisie', onTap: null),
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
      } else if (query.isNotEmpty && !provider.isLoading && provider.searchError != null) {
        text = 'Recherche impossible : ${provider.searchError}';
      } else if (query.isNotEmpty && !provider.isLoading) {
        text = provider.searchNotFound ?? 'Aucun produit trouvé.';
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
    final paging = provider.productSearch;
    final footer = ProductPagingFooter.visibleFor(paging);
    final list = ListView.separated(
      padding: EdgeInsets.fromLTRB(compact ? 0 : 12, 10, compact ? 0 : 12, 16),
      itemCount: provider.searchResults.length + (footer ? 1 : 0),
      separatorBuilder: (_, __) => SizedBox(height: compact ? 0 : 8),
      itemBuilder: (context, index) {
        if (index >= provider.searchResults.length) return ProductPagingFooter(paging, onLoadMore: provider.loadMoreProducts);
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
    // Liste par pages : « 50 sur 120 », la suite se charge en faisant défiler.
    return Column(children: [
      ProductPagingCount(paging),
      Expanded(child: ProductPagingScroll(search: paging, onLoadMore: provider.loadMoreProducts, child: list)),
    ]);
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
                  helper: 'Scannez ou saisissez le code : il est enregistré tel quel après confirmation',
                ),
                // Clavier numérique pour la saisie à la main (aide seulement : rien n'est filtré ni tronqué ; la
                // douchette tape le code tel quel).
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submitForm(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
