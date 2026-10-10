// lib/ventes/prevente/vente_cart.dart
// Panier de la vente : Modifier (quantité + prix contrôlés), Supprimer (confirmé), boutons ≥ 44 px.
// A : cartes ; B : lignes denses (toucher = modifier, glisser = supprimer) ; C : cartes à bande de couleur
// (vert normal, ambre stock dépassé / forcé). Si la relecture échoue, l'ancien panier reste affiché.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/common/vente_dialogs.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

class VenteCart extends StatelessWidget {
  /// Remet le curseur dans la recherche après une action.
  final VoidCallback? onDone;

  /// Présentation (A par défaut).
  final ListPresentation style;

  /// Stock connu au moment de l'ajout (produits ajoutés sur cet appareil), par produit.
  final Map<String, int> stockOf;

  /// Panier vide : action secondaire (ex. « Préventes à encaisser »).
  final Widget? emptyAction;

  const VenteCart({super.key, this.onDone, this.style = ListPresentation.dashboard, this.stockOf = const {}, this.emptyAction});

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

  /// Quantité totale du produit dans le panier au-delà du stock connu.
  int? _stock(SaleItemDetail item) => stockOf[item.lgFAMILLEID];
  bool _over(List<SaleItemDetail> items, SaleItemDetail item) {
    final s = _stock(item);
    if (s == null) return false;
    final total = items.where((i) => i.lgFAMILLEID == item.lgFAMILLEID).fold<int>(0, (a, i) => a + i.intQUANTITY);
    return total > s;
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
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.shopping_cart_outlined, size: 60, color: Color(0xFF9AA8BC)),
            const SizedBox(height: 10),
            const Text('Le panier est vide', style: TextStyle(fontSize: 16, color: Pal.ink, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Scannez ou recherchez un produit', style: TextStyle(fontSize: 13, color: Pal.muted)),
            if (emptyAction != null) ...[const SizedBox(height: 20), emptyAction!],
          ]),
        ),
      );
    }
    final locked = c.finished;
    final edit = locked ? null : (SaleItemDetail i) => _edit(context, c, i);
    final delete = locked ? null : (SaleItemDetail i) => _delete(context, c, i);

    if (style == ListPresentation.compact) {
      return ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: items.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF1F5)),
        itemBuilder: (context, i) {
          if (i == items.length) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Toucher une ligne : modifier · glisser : supprimer',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Pal.muted)),
            );
          }
          final item = items[i];
          final row = _DenseRow(item: item, over: _over(items, item), onEdit: edit, onDelete: delete);
          if (locked) return row;
          return Dismissible(
            key: ValueKey('ligne-${item.lgPREENREGISTREMENTDETAILID}'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red.shade600,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            // La ligne n'est retirée qu'après la réponse du serveur (relecture du panier).
            confirmDismiss: (_) async {
              await _delete(context, c, item);
              return false;
            },
            child: row,
          );
        },
      );
    }

    final guided = style == ListPresentation.guided;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 9),
      itemBuilder: (context, i) {
        final item = items[i];
        final over = _over(items, item);
        return _CartCard(
          item: item,
          stock: _stock(item),
          over: over,
          band: guided ? (over ? Pal.amber : Pal.green) : null,
          onEdit: edit,
          onDelete: delete,
        );
      },
    );
  }
}

/// Bouton carré libellé par une infobulle (≥ 44 px).
class _MiniButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;
  const _MiniButton({required this.icon, required this.tooltip, required this.color, this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 46,
        height: 44,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Pal.line)),
            backgroundColor: Colors.white,
          ),
          icon: Icon(icon, size: 21, color: onPressed == null ? Colors.grey : color),
          onPressed: onPressed,
        ),
      );
}

/// Carte d'une ligne (A ; C avec bande de couleur à gauche).
class _CartCard extends StatelessWidget {
  final SaleItemDetail item;
  final int? stock;
  final bool over;
  final Color? band;
  final void Function(SaleItemDetail)? onEdit;
  final void Function(SaleItemDetail)? onDelete;
  const _CartCard({required this.item, this.stock, required this.over, this.band, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final details = [
      if (item.intCIP.isNotEmpty) 'CIP ${item.intCIP}',
      if (stock != null) 'stock $stock',
    ].join(' · ');
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.strNAME, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: Pal.ink)),
              if (details.isNotEmpty)
                Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Pal.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          Text('${Constants.formatNumber(item.intPRICE)} F', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Pal.ink)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${item.intQUANTITY} × ${Constants.formatNumber(item.intPRICEUNITAIR)} F'),
                if (over) const TextSpan(text: '  ⚠ stock dépassé', style: TextStyle(color: Color(0xFF9A3412), fontWeight: FontWeight.w600)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Pal.muted),
            ),
          ),
          _MiniButton(icon: Icons.edit_outlined, tooltip: 'Modifier', color: Pal.navy, onPressed: onEdit == null ? null : () => onEdit!(item)),
          const SizedBox(width: 6),
          _MiniButton(icon: Icons.delete_outline, tooltip: 'Supprimer', color: Colors.red.shade700, onPressed: onDelete == null ? null : () => onDelete!(item)),
        ]),
      ]),
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x1014213D), blurRadius: 4, offset: Offset(0, 1))],
      ),
      clipBehavior: Clip.antiAlias,
      child: band == null
          ? content
          : IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 5, color: band),
                Expanded(child: content),
              ]),
            ),
    );
  }
}

/// Ligne dense (B) : toucher = modifier ; bouton Supprimer à droite.
class _DenseRow extends StatelessWidget {
  final SaleItemDetail item;
  final bool over;
  final void Function(SaleItemDetail)? onEdit;
  final void Function(SaleItemDetail)? onDelete;
  const _DenseRow({required this.item, required this.over, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        child: InkWell(
          onTap: onEdit == null ? null : () => onEdit!(item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.strNAME, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Pal.ink)),
                  Text('${item.intQUANTITY} × ${Constants.formatNumber(item.intPRICEUNITAIR)}${over ? '  ⚠ stock dépassé' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: over ? const Color(0xFF9A3412) : Pal.muted)),
                ]),
              ),
              const SizedBox(width: 8),
              Text(Constants.formatNumber(item.intPRICE), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Pal.ink)),
              IconButton(
                tooltip: 'Modifier',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(Icons.edit_outlined, size: 20, color: onEdit == null ? Colors.grey : Pal.navy),
                onPressed: onEdit == null ? null : () => onEdit!(item),
              ),
              IconButton(
                tooltip: 'Supprimer',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(Icons.delete_outline, size: 20, color: onDelete == null ? Colors.grey : Colors.red.shade700),
                onPressed: onDelete == null ? null : () => onDelete!(item),
              ),
            ]),
          ),
        ),
      );
}
