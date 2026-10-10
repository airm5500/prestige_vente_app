// lib/ventes/common/product_list_modal.dart
// Liste de choix produit commune (plusieurs résultats) avec filtre local.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/utils/constants.dart';

/// Ouvre la liste et renvoie le produit choisi (null si fermé).
Future<ProductSearchResult?> showProductListModal(BuildContext context, List<ProductSearchResult> results, {String initialQuery = ''}) =>
    showModalBottomSheet<ProductSearchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProductListModal(
        results: results,
        initialQuery: initialQuery,
        onProductSelected: (p) => Navigator.pop(ctx, p),
      ),
    );

/// Liste des résultats de recherche ; [onProductSelected] à la sélection.
class ProductListModal extends StatefulWidget {
  final List<ProductSearchResult> results;
  final String initialQuery;
  final ValueChanged<ProductSearchResult> onProductSelected;
  const ProductListModal({super.key, required this.results, required this.initialQuery, required this.onProductSelected});

  @override
  State<ProductListModal> createState() => _ProductListModalState();
}

class _ProductListModalState extends State<ProductListModal> {
  late List<ProductSearchResult> _filtered = widget.results;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.initialQuery;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _filter(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      _filtered = q.isEmpty
          ? widget.results
          : widget.results.where((p) => p.strNAME.toLowerCase().contains(q) || p.intCIP.toString().contains(q)).toList();
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
              'Résultats (${_filtered.length})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(icon: const Icon(Icons.close), tooltip: 'Fermer', onPressed: () => Navigator.pop(context)),
        ]),
        const SizedBox(height: 6),
        TextField(
          controller: _ctrl,
          decoration: const InputDecoration(hintText: 'Filtrer dans la liste...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
          onChanged: _filter,
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(
          child: _filtered.isEmpty
              ? const Center(child: Text('Aucun produit dans cette liste'))
              : ListView.separated(
                  padding: EdgeInsets.only(bottom: keyboard + 20),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final p = _filtered[i];
                    return ListTile(
                      minVerticalPadding: 8,
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
}
