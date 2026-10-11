// lib/ventes/common/product_list_modal.dart
// Liste de choix produit commune (plusieurs résultats) avec filtre local.
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

/// Liste des résultats de recherche ; [onProductSelected] à la sélection.
class ProductListModal extends StatefulWidget {
  final List<ProductSearchResult> results;
  final String initialQuery;
  final ValueChanged<ProductSearchResult> onProductSelected;
  final ProductPager? pager;
  final bool Function(ProductSearchResult)? visible;
  const ProductListModal({
    super.key,
    required this.results,
    required this.initialQuery,
    required this.onProductSelected,
    this.pager,
    this.visible,
  });

  @override
  State<ProductListModal> createState() => _ProductListModalState();
}

class _ProductListModalState extends State<ProductListModal> {
  late List<ProductSearchResult> _all = widget.results;
  late List<ProductSearchResult> _filtered = widget.results;
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _loadingMore = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.initialQuery;
    if (widget.initialQuery.isNotEmpty) _filter(widget.initialQuery);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
  }

  /// Charge la page suivante (liste par pages).
  Future<void> _loadMore() async {
    final pager = widget.pager;
    if (pager == null || !pager.hasMore || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _loadError = null;
    });
    final ok = await pager.loadMore();
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      _loadError = ok ? null : (pager.error ?? 'Chargement impossible');
      _all = pager.items.where((p) => widget.visible?.call(p) ?? true).toList();
    });
    _filter(_ctrl.text);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _filter(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      _filtered = q.isEmpty
          ? _all
          : _all.where((p) => p.strNAME.toLowerCase().contains(q) || p.intCIP.toString().contains(q)).toList();
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
              widget.pager != null && widget.pager!.total > 0
                  ? 'Résultats (${widget.pager!.items.length} sur ${widget.pager!.total})'
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
        if (widget.pager?.hasMore ?? false)
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
          controller: _ctrl,
          decoration: const InputDecoration(hintText: 'Filtrer dans la liste...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
          onChanged: _filter,
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(
          child: _filtered.isEmpty && !(widget.pager?.hasMore ?? false)
              ? const Center(child: Text('Aucun produit dans cette liste'))
              : ListView.separated(
                  controller: _scroll,
                  padding: EdgeInsets.only(bottom: keyboard + 20),
                  itemCount: _filtered.length + ((widget.pager?.hasMore ?? false) || _loadError != null ? 1 : 0),
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
