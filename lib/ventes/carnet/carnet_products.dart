// lib/ventes/carnet/carnet_products.dart
// Étape 3 de la Vente Carnet : recherche/scan (brique commune), panier (Modifier contrôlé,
// Supprimer confirmé), pied de page Total / Part carnet / Part client. Le net est recalculé
// automatiquement après chaque changement (plus de bouton « Calculer ») ; valider exige un net à jour.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_controller.dart';
import 'package:prestige_vente_app/ventes/common/vente_dialogs.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/common/vente_product_search.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

class CarnetProductsStep extends StatelessWidget {
  final GlobalKey<VenteProductSearchState> searchKey;
  final Future<bool> Function(ProductSearchResult product, int qty) addProduct;
  final VoidCallback onPrevente;
  final VoidCallback onValider;

  /// Validation en cours (boutons et recherche bloqués).
  final bool paying;

  const CarnetProductsStep({
    super.key,
    required this.searchKey,
    required this.addProduct,
    required this.onPrevente,
    required this.onValider,
    required this.paying,
  });

  void _focus() => searchKey.currentState?.requestFocus();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CarnetController>();
    final search = VenteProductSearch(
        key: searchKey, search: c.search, pageSearch: c.searchPage, visible: c.visibleProduct, addProduct: addProduct, enabled: !paying && !c.finished);
    final banners = [
      if (c.cartError != null && c.items.isNotEmpty)
        LoadErrorBanner(message: 'Panier non relu : ${venteMessage(c.cartError)} (dernier état affiché).', onRetry: c.busy ? null : c.reload),
      if (c.netError != null && c.cartError == null && c.hasCart)
        LoadErrorBanner(message: 'Net à payer non calculé : ${venteMessage(c.netError)}', onRetry: c.busy ? null : c.reload),
    ];
    final cart = CarnetCart(onDone: _focus);
    final footer = _CarnetFooter(onPrevente: onPrevente, onValider: onValider, paying: paying);
    final header = _header(context, c);
    if (MediaQuery.of(context).size.width > 800) {
      return Column(children: [
        header,
        const Divider(height: 1),
        Expanded(
          child: Row(children: [
            Expanded(
              flex: 4,
              child: Column(
                  children: [search, ...banners, const Expanded(child: Center(child: Text('Recherchez un produit', style: TextStyle(color: Colors.grey))))]),
            ),
            const VerticalDivider(width: 1),
            Expanded(flex: 6, child: cart),
          ]),
        ),
        footer,
      ]);
    }
    return Column(children: [
      header,
      const Divider(height: 1),
      search,
      ...banners,
      const Divider(height: 1),
      Expanded(child: cart),
      footer,
    ]);
  }

  Widget _header(BuildContext context, CarnetController c) => Container(
        color: Colors.grey.shade100,
        padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
        child: Row(children: [
          const Icon(Icons.person, size: 20, color: Colors.blue),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(style: const TextStyle(color: Colors.black87, fontSize: 13), children: [
                const TextSpan(text: 'Client : ', style: TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: c.client?.fullName ?? '-'),
                const TextSpan(text: '\nAyant droit : ', style: TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: c.ayantDroit?.fullName ?? '-'),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            key: const ValueKey('carnet-retour-bons'),
            style: TextButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: paying || c.finished ? null : c.goToBonStep,
            icon: const Icon(Icons.edit_note, color: Colors.orange),
            label: const Text('Bons'),
          ),
        ]),
      );
}

/// Panier : Modifier (quantité 1-9 999, prix libre borné), Supprimer avec confirmation.
/// Si la relecture échoue, l'ancien panier reste affiché (jamais un panier vide trompeur).
class CarnetCart extends StatelessWidget {
  final VoidCallback? onDone;
  const CarnetCart({super.key, this.onDone});

  Future<void> _edit(BuildContext context, CarnetController c, SaleItemDetail item) async {
    final v = await showEditLineDialog(context, name: item.strNAME, qty: item.intQUANTITY, price: item.intPRICEUNITAIR);
    if (v == null || !context.mounted) {
      onDone?.call();
      return;
    }
    final r = await c.updateLine(item, v.qty, v.price);
    if (!context.mounted) return;
    if (!r.isOk) showVenteFailure(context, r);
    onDone?.call();
  }

  Future<void> _delete(BuildContext context, CarnetController c, SaleItemDetail item) async {
    final ok = await confirmDeleteLine(context, item.strNAME);
    if (!ok || !context.mounted) {
      onDone?.call();
      return;
    }
    final r = await c.removeLine(item);
    if (!context.mounted) return;
    if (!r.isOk) showVenteFailure(context, r);
    onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CarnetController>();
    final items = c.items;
    if (items.isEmpty) {
      if (c.cartError != null && c.venteId != null) {
        return LoadErrorView(message: 'Panier non relu : ${venteMessage(c.cartError)}', onRetry: c.reload);
      }
      if (c.busy && c.venteId != null) return const Center(child: CircularProgressIndicator());
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shopping_cart_outlined, size: 56, color: Colors.grey),
          SizedBox(height: 8),
          Text('Le panier est vide', style: TextStyle(fontSize: 16, color: Colors.grey)),
        ]),
      );
    }
    final locked = c.finished;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final item = items[i];
        return Material(
          color: Colors.white,
          child: InkWell(
            onTap: locked ? null : () => _edit(context, c, item),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.strNAME, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Expanded(
                        child: Text('${item.intQUANTITY} × ${Constants.formatNumber(item.intPRICEUNITAIR)}',
                            style: TextStyle(color: Colors.grey.shade800, fontSize: 13)),
                      ),
                      Text('${Constants.formatNumber(item.intPRICE)} F',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary)),
                    ]),
                  ]),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.edit, color: AppColors.secondary),
                  tooltip: 'Modifier',
                  onPressed: locked ? null : () => _edit(context, c, item),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  tooltip: 'Supprimer',
                  onPressed: locked ? null : () => _delete(context, c, item),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _CarnetFooter extends StatelessWidget {
  final VoidCallback onPrevente;
  final VoidCallback onValider;
  final bool paying;
  const _CarnetFooter({required this.onPrevente, required this.onValider, required this.paying});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CarnetController>();
    final s = c.summary;
    final upToDate = c.hasCart && c.netUpToDate && s != null;
    final reason = c.hasCart && !c.finished ? c.finishBlockedReason : null;
    final enabled = c.canFinish && !paying && !c.finished;
    String amount(int v) => upToDate ? Constants.formatNumber(v) : (c.busy ? 'Calcul…' : '—');
    final tpNames = {for (final tp in c.client?.tiersPayants ?? const []) tp.compteTp: tp.tpFullName};

    return Material(
      elevation: 6,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (c.hasCart) ...[
              _row('Total brut', amount(s?.montant ?? 0)),
              _row('Part carnet', amount(s?.montantTp ?? 0), color: Colors.red.shade700),
              if (upToDate)
                for (final tp in s.tierspayants)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: _row('∙ ${tpNames[tp.compteTp] ?? tp.compteTp} · Bon ${tp.numBon} (${tp.taux}%)', Constants.formatNumber(tp.tpnet), size: 13),
                  ),
            ],
            Row(children: [
              Expanded(
                child: Text('Part client (net) : ${c.hasCart ? amount(s?.montantNet ?? 0) : '0'}',
                    key: const ValueKey('carnet-net'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
              ),
              if (c.busy) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            ]),
            if (reason != null && !c.busy)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(reason, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('carnet-prevente'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor: Colors.orange.shade800,
                    side: BorderSide(color: enabled ? Colors.orange.shade700 : Colors.grey.shade300, width: 1.5),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: enabled ? onPrevente : null,
                  icon: const Icon(Icons.save, size: 20),
                  label: const Text('Enregistrer en prévente', textAlign: TextAlign.center, maxLines: 2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  key: const ValueKey('carnet-valider'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: enabled ? onValider : null,
                  icon: const Icon(Icons.check_circle, size: 20),
                  label: const Text('Valider la vente', textAlign: TextAlign.center, maxLines: 2),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? color, double size = 15}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: size, color: color ?? Colors.black87))),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(fontSize: size, fontWeight: FontWeight.bold, color: color ?? AppColors.primary)),
        ]),
      );
}
