// lib/screens/product_update/emplacement_update_screen.dart
// 11/11/2025 12:00 (Ajout Auto-Open & Focus)
// 10/10/2026 : présentations A/B/C, emplacement pris dans la liste du serveur, confirmation
// avant remplacement, pas de double envoi, recherche nettoyée, échec du chargement des rayons visible.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/rayon.dart';
import 'package:prestige_vente_app/providers/product_update_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

/// Longueur max d'une recherche produit ou d'un libellé d'emplacement saisi.
const int emplacementMaxLength = 60;

final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');

/// Nettoie un texte saisi : caractères de contrôle retirés, espaces aux bords, longueur bornée.
String cleanSearchQuery(String raw) {
  var s = raw.replaceAll(_controlChars, '').trim();
  if (s.length > emplacementMaxLength) s = s.substring(0, emplacementMaxLength).trim();
  return s;
}

/// Retrouve l'emplacement saisi dans la liste du serveur (null si inconnu).
/// Le rayon déjà choisi est prioritaire tant que le texte n'a pas été modifié.
Rayon? resolveRayon(List<Rayon> rayons, String typed, String? selectedId) {
  final text = cleanSearchQuery(typed).toLowerCase();
  if (text.isEmpty) return null;
  for (final r in rayons) {
    if (r.id.isNotEmpty && r.id == selectedId && r.libelle.trim().toLowerCase() == text) return r;
  }
  for (final r in rayons) {
    if (r.id.isNotEmpty && r.libelle.trim().toLowerCase() == text) return r;
  }
  return null;
}

/// Message d'erreur pour un emplacement saisi, null s'il est dans la liste.
String? validateEmplacement(List<Rayon> rayons, String typed, String? selectedId) {
  final text = cleanSearchQuery(typed);
  if (text.isEmpty) return 'Choisissez un emplacement dans la liste.';
  if (resolveRayon(rayons, typed, selectedId) == null) {
    return '« $text » n\'est pas un emplacement connu : choisissez-le dans la liste.';
  }
  return null;
}

class EmplacementUpdateScreen extends StatefulWidget {
  /// Présentation (A, B, C) ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;
  const EmplacementUpdateScreen({super.key, this.presentation});
  @override
  State<EmplacementUpdateScreen> createState() => _EmplacementUpdateScreenState();
}

class _EmplacementUpdateScreenState extends State<EmplacementUpdateScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounce;

  final _rayonController = TextEditingController();
  String? _selectedRayonId;
  final _rayonFocusNode = FocusNode();
  String? _rayonError;

  bool _busy = false; // garde contre le double envoi (confirmation comprise)
  bool _sending = false; // envoi en cours : bouton remplacé par l'indicateur
  bool _rayonsLoading = false;
  bool _rayonsFailed = false;
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
      final provider = Provider.of<ProductUpdateProvider>(context, listen: false);
      provider.clearAll();
      _loadRayons();
      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
    _searchController.addListener(_onSearchChanged);
    _setupFocusNodeSelection(_rayonFocusNode, _rayonController);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    _rayonController.dispose();
    _rayonFocusNode.dispose();
    super.dispose();
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  // Chargement des rayons : un échec (ou une liste vide) est signalé avec « Réessayer ».
  Future<void> _loadRayons() async {
    if (_rayonsLoading) return;
    final provider = Provider.of<ProductUpdateProvider>(context, listen: false);
    setState(() {
      _rayonsLoading = true;
      _rayonsFailed = false;
    });
    var failed = false;
    try {
      await provider.loadRayons();
      failed = provider.rayons.isEmpty;
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _rayonsLoading = false;
      _rayonsFailed = failed;
    });
  }

  // Logique Auto-Open : un seul résultat → fiche ouverte directement.
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      final provider = Provider.of<ProductUpdateProvider>(context, listen: false);
      final query = cleanSearchQuery(_searchController.text);

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
    _rayonController.clear();
    _selectedRayonId = null;
    _rayonError = null;
    _focusedFor = null;
    provider.selectProduct(product).catchError((_) {
      if (mounted) Constants.showSnackBar(context, 'Fiche produit non chargée. Vérifiez la connexion au serveur.', isError: true);
    });
    _searchController.clear();
  }

  void _resetForm() {
    Provider.of<ProductUpdateProvider>(context, listen: false).clearSelection();
    _rayonController.clear();
    _selectedRayonId = null;
    _rayonError = null;
    _focusedFor = null;
    FocusScope.of(context).requestFocus(_searchFocusNode);
    _searchController.selection = TextSelection(baseOffset: 0, extentOffset: _searchController.text.length);
  }

  Future<bool> _confirmReplace(String current, String next) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Remplacer l\'emplacement ?'),
        content: Text('Emplacement actuel : $current\nNouvel emplacement : $next'),
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

    if (provider.rayons.isEmpty) {
      Constants.showSnackBar(context, 'Liste des emplacements indisponible. Touchez « Réessayer ».', isError: true);
      return;
    }

    // L'emplacement doit exister dans la liste du serveur (pas de valeur fantaisiste).
    final error = validateEmplacement(provider.rayons, _rayonController.text, _selectedRayonId);
    if (error != null) {
      setState(() => _rayonError = error);
      Constants.showSnackBar(context, 'Veuillez sélectionner un emplacement valide dans la liste.', isError: true);
      _rayonFocusNode.requestFocus();
      return;
    }
    final rayon = resolveRayon(provider.rayons, _rayonController.text, _selectedRayonId)!;
    _selectedRayonId = rayon.id;
    if (_rayonError != null) setState(() => _rayonError = null);

    final current = provider.selectedProduct!.strLIBELLEE.trim();
    _busy = true;
    try {
      if (current.isNotEmpty &&
          current.toLowerCase() != rayon.libelle.trim().toLowerCase() &&
          !await _confirmReplace(current, rayon.libelle)) {
        return;
      }
      if (!mounted) return;
      setState(() => _sending = true);

      bool success;
      try {
        success = await provider.updateEmplacement(rayon.id);
      } catch (_) {
        success = false;
      }

      if (!mounted) return;
      if (success) {
        Constants.showSnackBar(context, 'Emplacement mis à jour avec succès.');
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
          title: 'Mise à jour Emplacement',
          subtitle: style == ListPresentation.dashboard ? 'Scannez ou recherchez le produit' : null,
          actions: (c) => [PresentationMenuButton(value: style, onChanged: _setStyle, color: c)],
          steps: StepsBar(active: selected ? 1 : 0, steps: const [
            (title: 'Produit', detail: 'scan ou recherche', onTap: null),
            (title: 'Emplacement', detail: 'dans la liste', onTap: null),
            (title: 'Validation', detail: 'sur Prestige', onTap: null),
          ]),
          header: [_buildSearchBar(provider, dark: true)],
          compactHeader: [_buildSearchBar(provider, dark: false)],
          body: Column(
            children: [
              if (provider.isLoading && provider.selectedProduct == null) const LinearProgressIndicator(minHeight: 2),
              if (_rayonsFailed && !_rayonsLoading) _buildRayonsError(),
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
                              onPressed: provider.rayons.isEmpty ? null : _submitForm,
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

  Widget _buildRayonsError() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFDECEC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF5C2C2)),
        ),
        child: Row(children: [
          const Icon(Icons.cloud_off, color: Color(0xFFB42318)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Impossible de charger la liste des emplacements. Vérifiez la connexion au serveur.',
              style: TextStyle(color: Color(0xFF7A1A12), fontSize: 13),
            ),
          ),
          TextButton(onPressed: _loadRayons, child: const Text('Réessayer')),
        ]),
      ),
    );
  }

  Widget _buildSearchBar(ProductUpdateProvider provider, {required bool dark}) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      inputFormatters: [
        FilteringTextInputFormatter.deny(_controlChars),
        LengthLimitingTextInputFormatter(emplacementMaxLength),
      ],
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
            _rayonController.clear();
            _selectedRayonId = null;
            _rayonError = null;
            provider.clearAll();
            // Maintien du Focus
            _searchFocusNode.requestFocus();
          },
        ),
      ),
      onSubmitted: (_) => _onSearchChanged(),
      textInputAction: TextInputAction.search,
    );
  }

  Widget _buildSearchResults(ProductUpdateProvider provider) {
    final query = cleanSearchQuery(_searchController.text);
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
        final place = product.strLIBELLEE.trim();
        final row = Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.strNAME.trim().isEmpty ? '—' : product.strNAME,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink)),
              Text('CIP: ${product.intCIP} | Stock: ${product.intNUMBERAVAILABLE}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
              if (place.isNotEmpty)
                Text('Emplacement : $place',
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

  Widget _buildUpdateForm(ProductUpdateProvider provider) {
    final product = provider.selectedProduct!;

    // Focus sur le champ emplacement une seule fois par produit.
    if (!provider.isLoading && _focusedFor != product.lgFAMILLEID && provider.rayons.isNotEmpty) {
      _focusedFor = product.lgFAMILLEID;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).requestFocus(_rayonFocusNode);
      });
    }

    final current = product.strLIBELLEE.trim();
    final rayons = provider.rayons.where((r) => r.id.isNotEmpty && r.libelle.trim().isNotEmpty).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: SoftCard(
        band: style == ListPresentation.guided ? Pal.navy : null,
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
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Pal.page, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.location_on, color: Pal.muted, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    current.isEmpty ? 'Aucun emplacement enregistré' : 'Emplacement actuel : $current',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Pal.ink, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            if (rayons.isEmpty)
              Text(
                _rayonsLoading ? 'Chargement des emplacements…' : 'Liste des emplacements indisponible.',
                style: const TextStyle(color: Pal.muted),
              )
            else
              DropdownMenu<Rayon>(
                controller: _rayonController,
                focusNode: _rayonFocusNode,
                enabled: !_sending,
                label: const Text('Nouvel Emplacement'),
                leadingIcon: const Icon(Icons.shelves),
                helperText: 'Choisissez dans la liste (${rayons.length} emplacements)',
                errorText: _rayonError,
                expandedInsets: EdgeInsets.zero,
                menuHeight: 320,
                enableFilter: true,
                requestFocusOnTap: true,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(_controlChars),
                  LengthLimitingTextInputFormatter(emplacementMaxLength),
                ],
                dropdownMenuEntries: rayons.map((Rayon rayon) {
                  return DropdownMenuEntry<Rayon>(value: rayon, label: rayon.libelle);
                }).toList(),
                onSelected: (Rayon? rayon) {
                  if (rayon != null) {
                    _selectedRayonId = rayon.id;
                    _rayonController.text = rayon.libelle;
                    _submitForm();
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
