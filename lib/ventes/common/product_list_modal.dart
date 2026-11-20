// lib/ventes/common/product_list_modal.dart
// Liste de choix produit commune (plusieurs résultats) avec filtre local.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/horsligne/horsligne_ui.dart';
import 'package:prestige_vente_app/images/images_reglages.dart';
import 'package:prestige_vente_app/images/produit_image_widget.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';

/// Ouvre la liste et renvoie le produit choisi (null si fermé).
/// [pager] : liste chargée par pages (« 50 sur 252 », la suite se charge en faisant défiler).
/// [initialQuery] (5.1.0) : texte tapé dans la recherche de la vente, repris dans le champ du filtre (curseur à la
/// fin, clavier ouvert) pour continuer à préciser la recherche sans retaper.
Future<ProductSearchResult?> showProductListModal(
  BuildContext context,
  List<ProductSearchResult> results, {
  String initialQuery = '',
  ProductPager? pager,
  bool Function(ProductSearchResult)? visible,
}) =>
    showModalBottomSheet<ProductSearchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProductListModal(
        results: results,
        initialQuery: initialQuery,
        pager: pager,
        visible: visible,
        onProductSelected: (p) => Navigator.pop(ctx, p),
      ),
    );

/// Filtre local de la liste (5.1.0) : chaque mot tapé doit se trouver dans le nom ou le CIP, dans n'importe quel
/// ordre (« DOLI 1000 » trouve « DOLIPRANE 1000MG ») ; % et _ comptent comme des espaces (jokers de « Contient »).
class ProductListFilter {
  ProductListFilter._();

  static final RegExp _sep = RegExp(r'[\s%_]+');

  /// Mots du texte, en minuscules.
  static List<String> words(String text) => text.toLowerCase().split(_sep).where((w) => w.isNotEmpty).toList();

  /// Forme normalisée d'un texte (comparaison « même recherche »).
  static String norm(String text) => words(text).join(' ');

  static bool matches(ProductSearchResult p, String text) {
    final ws = words(text);
    if (ws.isEmpty) return true;
    final name = p.strNAME.toLowerCase();
    final cip = p.intCIP.toString().toLowerCase();
    return ws.every((w) => name.contains(w) || cip.contains(w));
  }

  /// Le texte [text] prolonge-t-il la recherche [base] (même début, plus de caractères) ?
  static bool extends_(String text, String base) {
    final t = norm(text), b = norm(base);
    return b.isNotEmpty && t.length > b.length && t.startsWith(b);
  }
}

/// Liste des résultats de recherche ; [onProductSelected] à la sélection.
class ProductListModal extends StatefulWidget {
  final List<ProductSearchResult> results;
  final String initialQuery;
  final ValueChanged<ProductSearchResult> onProductSelected;
  final ProductPager? pager;
  final bool Function(ProductSearchResult)? visible;

  /// Délai de frappe avant une nouvelle recherche sur le serveur (liste incomplète, texte précisé).
  final Duration refineDebounce;
  const ProductListModal({
    super.key,
    required this.results,
    required this.initialQuery,
    required this.onProductSelected,
    this.pager,
    this.visible,
    this.refineDebounce = const Duration(milliseconds: 400),
  });

  @override
  State<ProductListModal> createState() => _ProductListModalState();
}

class _ProductListModalState extends State<ProductListModal> {
  late List<ProductSearchResult> _all = widget.results;
  late List<ProductSearchResult> _filtered = widget.results;
  late final TextEditingController _ctrl = TextEditingController(text: widget.initialQuery);
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _loadingMore = false;
  String? _loadError;

  /// Liste affichée : celle de la recherche de la vente, ou celle d'une recherche plus précise (5.1.0).
  late ProductPager? _pager = widget.pager;

  /// Texte qui a produit [_all] : tant que le champ le contient, aucun filtre local (les résultats du serveur —
  /// variantes EAN / CIP, « Contient » sur plusieurs mots — ne sont jamais effacés par le filtre).
  late String _resultsQuery = widget.initialQuery;
  Timer? _refineTimer;
  int _refineGen = 0;
  bool _refining = false;
  String? _refineError;

  @override
  void initState() {
    super.initState();
    _applyFilter(_ctrl.text);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
    // Comme avant la nouvelle interface : le texte tapé est repris, le curseur à la fin, le clavier reste ouvert.
    if (widget.initialQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focus.requestFocus();
        _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
      });
    }
  }

  /// Charge la page suivante (liste par pages).
  Future<void> _loadMore() async {
    final pager = _pager;
    if (pager == null || !pager.hasMore || _loadingMore || _refining) return;
    setState(() {
      _loadingMore = true;
      _loadError = null;
    });
    final ok = await pager.loadMore();
    if (!mounted || !identical(pager, _pager)) return;
    setState(() {
      _loadingMore = false;
      _loadError = ok ? null : (pager.error ?? 'Chargement impossible');
      _all = _visibleItems(pager);
    });
    _filter(_ctrl.text);
  }

  List<ProductSearchResult> _visibleItems(ProductPager p) => p.items.where((x) => widget.visible?.call(x) ?? true).toList();

  @override
  void dispose() {
    _refineTimer?.cancel();
    _refineGen++;
    _scroll.dispose();
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _applyFilter(String query) {
    _filtered = ProductListFilter.norm(query) == ProductListFilter.norm(_resultsQuery)
        ? _all
        : _all.where((p) => ProductListFilter.matches(p, query)).toList();
  }

  void _filter(String query) => setState(() => _applyFilter(query));

  void _onChanged(String text) {
    _filter(text);
    _scheduleRefine(text);
  }

  /// Liste incomplète (« 50 sur 252 ») et texte qui prolonge la recherche : nouvelle recherche sur le serveur après
  /// le délai de frappe (la précédente est abandonnée) ; le filtre local s'affiche en attendant.
  void _scheduleRefine(String text) {
    _refineTimer?.cancel();
    final base = widget.pager;
    if (base == null) return;
    final t = ProductListFilter.norm(text);
    // Texte d'origine, ou qui ne prolonge plus la recherche : liste d'origine (filtre local), sans requête.
    if (t == ProductListFilter.norm(base.query) || !ProductListFilter.extends_(text, base.query)) {
      _refineGen++;
      if (!identical(_pager, base) || _refining) {
        setState(() {
          _refining = false;
          _refineError = null;
          _pager = base;
          _resultsQuery = widget.initialQuery;
          _all = _visibleItems(base);
          _applyFilter(text);
        });
      }
      return;
    }
    if (!base.hasMore) return;
    final current = _pager;
    // Liste précise déjà complète et texte qui la prolonge : le filtre local suffit.
    if (current != null && !identical(current, base) && !current.hasMore &&
        (t == ProductListFilter.norm(current.query) || ProductListFilter.extends_(text, current.query))) {
      return;
    }
    _refineTimer = Timer(widget.refineDebounce, () => _refine(text));
  }

  Future<void> _refine(String text) async {
    final base = widget.pager;
    if (base == null || !mounted) return;
    final gen = ++_refineGen;
    final p = base.refine(text.trim());
    setState(() {
      _refining = true;
      _refineError = null;
    });
    final ok = await p.loadMore();
    if (!mounted || gen != _refineGen) return; // recherche remplacée par une plus récente
    setState(() {
      _refining = false;
      if (ok) {
        _pager = p;
        _resultsQuery = text;
        _loadError = null;
        _all = _visibleItems(p);
        _applyFilter(_ctrl.text);
      } else {
        _refineError = 'Recherche sur le serveur impossible : ${p.error ?? 'erreur'}. Liste filtrée sur les produits déjà chargés.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Text(
              _pager != null && _pager!.total > 0
                  ? 'Résultats (${_pager!.items.length} sur ${_pager!.total})'
                  : 'Résultats (${_filtered.length})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(icon: const Icon(Icons.close), tooltip: 'Fermer', onPressed: () => Navigator.pop(context)),
        ]),
        const HorsLigneCatalogueNote(padding: EdgeInsets.only(bottom: 4)),
        const SizedBox(height: 6),
        if (_pager?.hasMore ?? false)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              SearchModePrefs.current == SearchMode.contient
                  ? 'Faites défiler pour charger la suite, ou ajoutez un mot (ex. « DOLI 1000 »).'
                  : 'Faites défiler pour charger la suite, ou précisez le début du nom (ex. « DOLIPRANE 1000 »).',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
        TextField(
          key: const ValueKey('liste-produits-filtre'),
          controller: _ctrl,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Filtrer dans la liste...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _refining
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, key: ValueKey('liste-produits-recherche'))),
                  )
                : null,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: _onChanged,
          // Entrée : le clavier reste ouvert (on continue à préciser ou on touche un produit).
          onEditingComplete: () {},
        ),
        if (_refineError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_refineError!, style: TextStyle(fontSize: 12, color: Colors.red.shade800)),
          ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(
          child: _filtered.isEmpty && !(_pager?.hasMore ?? false) && !_refining
              ? const Center(child: Text('Aucun produit dans cette liste'))
              : ListView.separated(
                  controller: _scroll,
                  padding: EdgeInsets.only(bottom: keyboard + 20),
                  itemCount: _filtered.length + ((_pager?.hasMore ?? false) || _loadError != null ? 1 : 0),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    if (i >= _filtered.length) return _moreRow();
                    final p = _filtered[i];
                    return ListTile(
                      minVerticalPadding: 8,
                      // B2 : vignette seulement si le réglage « vignettes dans les listes de vente » est activé.
                      leading: ImagesReglages.courant.value.vignettesVentes && ImagesReglages.courant.value.actif
                          ? ProduitImage(
                              familleId: p.lgFAMILLEID,
                              taille: 40,
                              rayon: BorderRadius.circular(8),
                              placeholder: const SizedBox(width: 40, height: 40, child: Icon(Icons.medication_outlined, color: Colors.black38)),
                            )
                          : null,
                      title: Text(p.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text.rich(TextSpan(style: const TextStyle(fontSize: 12, color: Colors.black87), children: [
                        TextSpan(text: 'CIP : ${p.intCIP} | '),
                        TextSpan(
                          text: 'Stock : ${p.intNUMBERAVAILABLE}',
                          style: TextStyle(fontWeight: FontWeight.bold, color: p.intNUMBERAVAILABLE > 0 ? Colors.blue : Colors.red),
                        ),
                        const TextSpan(text: ' | '),
                        TextSpan(text: 'Prix : ${Constants.formatNumber(p.intPRICE)} F', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      ])),
                      onTap: () => widget.onProductSelected(p),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  /// Dernière ligne : chargement de la suite, ou erreur avec « Réessayer ».
  Widget _moreRow() {
    if (_loadError != null) {
      return ListTile(
        leading: Icon(Icons.cloud_off, color: Colors.red.shade700),
        title: Text(_loadError!, style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
        trailing: TextButton(onPressed: _loadMore, child: const Text('Réessayer')),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: _loadingMore
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton(onPressed: _loadMore, child: const Text('Charger la suite')),
      ),
    );
  }
}
