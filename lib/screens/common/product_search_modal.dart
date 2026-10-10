import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/ajustement_provider.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/services/product_finder.dart';
import 'package:prestige_vente_app/widgets/product_paging.dart';

class ProductSearchModal extends StatefulWidget {
  final String initialQuery;
  final Function(ProductSearchResult) onProductSelected;

  const ProductSearchModal({
    super.key,
    required this.initialQuery,
    required this.onProductSelected,
  });

  @override
  State<ProductSearchModal> createState() => _ProductSearchModalState();
}

class _ProductSearchModalState extends State<ProductSearchModal> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  // Code → produit exact (EAN-13 → CIP7…) ; texte → liste par pages (« 50 sur 120 »).
  PagedProductSearch? _search;
  List<ProductSearchResult> _results = [];
  bool _isLoading = false;
  String? _error; // panne (≠ aucun résultat)
  String? _notFound; // code inconnu

  @override
  void initState() {
    super.initState();
    // 1. Initialiser avec le texte déjà saisi
    _controller = TextEditingController(text: widget.initialQuery);

    // 2. Lancer la recherche immédiatement
    _performSearch(widget.initialQuery);

    // 3. Focus automatique et placement du curseur à la fin
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      if (_controller.text.isNotEmpty) {
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    if (query.trim().isEmpty) {
      _search?.clear();
      setState(() {
        _results = [];
        _error = null;
        _notFound = null;
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final provider = Provider.of<AjustementProvider>(context, listen: false);
      final search = _search ??= await provider.newProductSearch();
      final current = await search.run(query);
      if (!current || !mounted) return; // remplacée par une saisie plus récente
      setState(() {
        _results = search.items;
        _error = search.error;
        _notFound = search.notFound;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Recherche impossible : $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Charge la page suivante (liste par pages).
  Future<void> _loadMore() async {
    final search = _search;
    if (search == null || !search.hasMore || search.loadingMore) return;
    final f = search.loadMore();
    setState(() {});
    await f;
    if (!mounted) return;
    setState(() => _results = search.items);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85, // 85% de la hauteur
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    labelText: "Recherche produit...",
                    hintText: "Continuez à saisir...",
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _isLoading
                        ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _controller.clear();
                              _performSearch("");
                            }),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Fermer"),
              )
            ],
          ),
          const SizedBox(height: 10),
          const Divider(),
          if (_search != null) ProductPagingCount(_search!, padding: const EdgeInsets.only(bottom: 4)),
          Expanded(
            child: _error != null && !_isLoading
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.cloud_off, color: Colors.red.shade700),
                      const SizedBox(height: 6),
                      Text('Recherche impossible : $_error', textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade900)),
                      TextButton(onPressed: () => _performSearch(_controller.text), child: const Text('Réessayer')),
                    ]),
                  )
                : _search == null || (_results.isEmpty && !_search!.hasMore)
                    ? _isLoading
                        ? const SizedBox.shrink()
                        : Center(
                            child: Text(
                              _controller.text.isEmpty ? "Saisissez un nom ou un code" : (_notFound ?? "Aucun résultat"),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          )
                    : ProductPagingScroll(
                        search: _search!,
                        onLoadMore: _loadMore,
                        child: ListView.separated(
                          itemCount: _results.length + (ProductPagingFooter.visibleFor(_search!) ? 1 : 0),
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, index) {
                            if (index >= _results.length) return ProductPagingFooter(_search!, onLoadMore: _loadMore);
                            final p = _results[index];
                            return ListTile(
                              dense: true,
                              title: Text(p.strNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text("CIP: ${p.intCIP} | Stock: ${p.intNUMBERAVAILABLE}"),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                              onTap: () {
                                widget.onProductSelected(p);
                                Navigator.pop(context); // Ferme le modal
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
