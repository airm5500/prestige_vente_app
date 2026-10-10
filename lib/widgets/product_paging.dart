// lib/widgets/product_paging.dart
// Éléments communs des listes de produits chargées par pages (menus hors ventes) :
// compteur « 50 sur 120 », ligne « Charger la suite » / « Réessayer », chargement en défilant.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/services/product_finder.dart';
import 'package:prestige_vente_app/services/search_mode.dart';

/// Compteur « Résultats : 50 sur 120 » (affiché seulement si la liste dépasse une page).
class ProductPagingCount extends StatelessWidget {
  final PagedProductSearch search;
  final EdgeInsetsGeometry padding;
  final Color? color;
  const ProductPagingCount(this.search, {super.key, this.padding = const EdgeInsets.fromLTRB(16, 6, 16, 2), this.color});

  @override
  Widget build(BuildContext context) {
    if (!search.showCount) return const SizedBox.shrink();
    final c = color ?? Colors.grey.shade700;
    return Padding(
      padding: padding,
      child: Text(
        search.hasMore
            ? 'Résultats : ${search.countLabel} — faites défiler pour la suite, ou '
                '${SearchModePrefs.current == SearchMode.contient ? 'ajoutez un mot' : 'précisez le début du nom'}.'
            : 'Résultats : ${search.countLabel}',
        style: TextStyle(fontSize: 12, color: c),
      ),
    );
  }
}

/// Dernière ligne de la liste : chargement de la suite, « Charger la suite » ou erreur avec « Réessayer ».
/// Rien si tout est chargé.
class ProductPagingFooter extends StatelessWidget {
  final PagedProductSearch search;
  final VoidCallback onLoadMore;
  const ProductPagingFooter(this.search, {super.key, required this.onLoadMore});

  /// La liste doit-elle afficher cette ligne ?
  static bool visibleFor(PagedProductSearch s) => s.hasMore || s.loadMoreError != null;

  @override
  Widget build(BuildContext context) {
    if (search.loadMoreError != null) {
      return ListTile(
        leading: Icon(Icons.cloud_off, color: Colors.red.shade700),
        title: Text(search.loadMoreError!, style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
        trailing: TextButton(onPressed: onLoadMore, child: const Text('Réessayer')),
      );
    }
    if (!search.hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: search.loadingMore
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton.icon(
                onPressed: onLoadMore,
                icon: const Icon(Icons.expand_more),
                label: Text('Charger la suite (${search.countLabel})'),
              ),
      ),
    );
  }
}

/// Charge la suite quand on approche du bas de la liste.
class ProductPagingScroll extends StatelessWidget {
  final PagedProductSearch search;
  final VoidCallback onLoadMore;
  final Widget child;
  const ProductPagingScroll({super.key, required this.search, required this.onLoadMore, required this.child});

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis == Axis.vertical &&
              n.metrics.extentAfter < 300 &&
              search.hasMore &&
              !search.loadingMore &&
              search.loadMoreError == null) {
            onLoadMore();
          }
          return false;
        },
        child: child,
      );
}
