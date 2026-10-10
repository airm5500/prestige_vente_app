// lib/ventes/prevente/vente_cart.dart
// Panier de la vente : Modifier (quantité + prix contrôlés), Supprimer (confirmé), boutons ≥ 44 px.
// Si la relecture échoue, l'ancien panier reste affiché (jamais un panier vide trompeur).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/common/vente_dialogs.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

class VenteCart extends StatelessWidget {
  /// Remet le curseur dans la recherche après une action.
  final VoidCallback? onDone;
  const VenteCart({super.key, this.onDone});

  Future<void> _edit(BuildContext context, VenteController c, SaleItemDetail item) async {
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

  Future<void> _delete(BuildContext context, VenteController c, SaleItemDetail item) async {
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
    final c = context.watch<VenteController>();
    final items = c.items;
    if (items.isEmpty) {
      if (c.cartError != null && c.venteId != null) {
        return LoadErrorView(message: 'Panier non relu : ${venteMessage(c.cartError)}', onRetry: c.reload);
      }
      if (c.busy && c.venteId != null) return const Center(child: CircularProgressIndicator());
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shopping_cart_outlined, size: 60, color: Colors.grey),
          SizedBox(height: 10),
          Text('Le panier est vide', style: TextStyle(fontSize: 16, color: Colors.grey)),
          SizedBox(height: 4),
          Text('Scannez ou recherchez un produit', style: TextStyle(fontSize: 13, color: Colors.grey)),
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
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue)),
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
