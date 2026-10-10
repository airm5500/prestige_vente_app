// lib/ventes/assurance/assurance_step_produits.dart
// Étape 3 : recherche / scan (brique commune), panier (Modifier / Supprimer confirmé, ancien panier
// gardé si la relecture échoue) et pied de page : répartition toujours visible, net recalculé
// automatiquement (plus de bouton « Calculer »), boutons libellés.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_controller.dart';
import 'package:prestige_vente_app/ventes/common/vente_dialogs.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/common/vente_product_search.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

class AssuranceStepProduits extends StatefulWidget {
  final Future<bool> Function(ProductSearchResult product, int qty) addProduct;
  final VoidCallback onPrevente;
  final VoidCallback onValider;

  /// Fin de vente en cours (boutons et saisie bloqués).
  final bool paying;
  const AssuranceStepProduits({super.key, required this.addProduct, required this.onPrevente, required this.onValider, required this.paying});

  @override
  State<AssuranceStepProduits> createState() => AssuranceStepProduitsState();
}

class AssuranceStepProduitsState extends State<AssuranceStepProduits> {
  final _searchKey = GlobalKey<VenteProductSearchState>();

  void focusSearch() => _searchKey.currentState?.requestFocus();

  Future<void> _edit(AssuranceController c, SaleItemDetail item) async {
    final v = await showEditLineDialog(context, name: item.strNAME, qty: item.intQUANTITY, price: item.intPRICEUNITAIR);
    if (v == null || !mounted) {
      focusSearch();
      return;
    }
    final r = await c.updateLine(item, v.qty, v.price);
    if (!mounted) return;
    if (!r.isOk) showVenteFailure(context, r);
    focusSearch();
  }

  Future<void> _delete(AssuranceController c, SaleItemDetail item) async {
    final ok = await confirmDeleteLine(context, item.strNAME);
    if (!ok || !mounted) {
      focusSearch();
      return;
    }
    final r = await c.removeLine(item);
    if (!mounted) return;
    if (!r.isOk) showVenteFailure(context, r);
    focusSearch();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AssuranceController>();
    final wide = MediaQuery.of(context).size.width > 800;
    final search = VenteProductSearch(
      key: _searchKey,
      search: c.searchProducts,
      pageSearch: c.searchPage,
      visible: c.visibleProduct,
      addProduct: widget.addProduct,
      enabled: !widget.paying && !c.finished,
    );
    final banners = [
      if (c.cartError != null && c.items.isNotEmpty)
        LoadErrorBanner(message: 'Panier non relu : ${venteMessage(c.cartError)} (dernier état affiché).', onRetry: c.busy ? null : c.reload),
      if (c.netError != null && c.cartError == null && c.hasCart)
        LoadErrorBanner(message: 'Net à payer non calculé : ${venteMessage(c.netError)}', onRetry: c.busy ? null : c.reload),
    ];
    return Column(children: [
      _header(c),
      const Divider(height: 1),
      Expanded(
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 4, child: Column(children: [search, ...banners, const Expanded(child: Center(child: Text('Recherchez un produit')))])),
                const VerticalDivider(width: 1),
                Expanded(flex: 6, child: _cart(c)),
              ])
            : Column(children: [search, ...banners, const Divider(height: 1), Expanded(child: _cart(c))]),
      ),
      _footer(c),
    ]);
  }

  Widget _header(AssuranceController c) {
    final tps = c.activeTiersPayants;
    final tpLabel = tps.isEmpty ? '-' : tps.map((t) => '${t.tpFullName} ${t.taux} %').join(' + ');
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      child: Row(children: [
        const Icon(Icons.person, size: 20, color: Colors.blue),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c.client?.fullName ?? '-'} · Patient : ${c.ayantDroit?.fullName ?? '-'}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            Text(tpLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ),
        TextButton.icon(
          key: const ValueKey('assurance-couverture'),
          style: TextButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: Colors.orange.shade800),
          onPressed: widget.paying || c.finished ? null : c.returnToCouverture,
          icon: const Icon(Icons.edit_note, size: 20),
          label: const Text('Bons / TP'),
        ),
      ]),
    );
  }

  Widget _cart(AssuranceController c) {
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
    final locked = c.finished || widget.paying;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final item = items[i];
        return Material(
          color: Colors.white,
          child: InkWell(
            onTap: locked ? null : () => _edit(c, item),
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
                      Text('${Constants.formatNumber(item.intPRICE)} F', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue)),
                    ]),
                  ]),
                ),
                const SizedBox(width: 4),
                IconButton(icon: const Icon(Icons.edit, color: AppColors.secondary), tooltip: 'Modifier', onPressed: locked ? null : () => _edit(c, item)),
                IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.error), tooltip: 'Supprimer', onPressed: locked ? null : () => _delete(c, item)),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _row(String label, String value, {Color? color, double size = 14, bool bold = false, Key? key}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: size, color: color ?? Colors.black87))),
          const SizedBox(width: 8),
          Text(value, key: key, style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color ?? AppColors.primary)),
        ]),
      );

  Widget _footer(AssuranceController c) {
    final s = c.summary;
    final upToDate = c.netUpToDate;
    final reason = c.hasCart && !c.finished ? c.finishBlockedReason : null;
    final enabled = c.canFinish && !widget.paying && !c.finished;
    String amount(int v) => upToDate ? Constants.formatNumber(v) : (c.busy ? 'Calcul…' : '—');
    final net = upToDate && s != null ? s.montantNet : null;
    final client = c.client;
    return Material(
      elevation: 6,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Répartition compacte, toujours visible (lisible à 360 px).
            if (c.hasCart) ...[
              Text(
                'Total ${amount(s?.montant ?? 0)} F · Part TP ${amount(s?.montantTp ?? 0)} F',
                key: const ValueKey('assurance-repartition'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              if (upToDate && s != null && s.tierspayants.isNotEmpty)
                Text(
                  s.tierspayants
                      .map((tp) =>
                          '${(client?.tiersPayants.where((x) => x.compteTp == tp.compteTp).firstOrNull ?? _unknownTp).tpFullName} ${tp.taux} % : ${Constants.formatNumber(tp.tpnet)}')
                      .join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
            ],
            Row(children: [
              Expanded(child: _row('Part client (net)', c.hasCart ? amount(s?.montantNet ?? 0) : '0', size: 18, bold: true, key: const ValueKey('assurance-net'))),
              if (c.busy) const Padding(padding: EdgeInsets.only(left: 8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))),
            ]),
            // Raison du blocage (sauf si un bandeau « Réessayer » l'explique déjà).
            if (reason != null && !c.busy && c.cartError == null && c.netError == null)
              Row(children: [
                Expanded(child: Text(reason, style: TextStyle(fontSize: 12, color: Colors.red.shade700))),
                if (!upToDate && c.hasCart)
                  TextButton(style: TextButton.styleFrom(minimumSize: const Size(0, 40)), onPressed: c.reload, child: const Text('Réessayer')),
              ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('assurance-prevente'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor: Colors.orange.shade800,
                    side: BorderSide(color: enabled ? Colors.orange.shade700 : Colors.grey.shade300, width: 1.5),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: enabled ? widget.onPrevente : null,
                  icon: const Icon(Icons.save, size: 20),
                  label: const Text('Enregistrer en prévente', textAlign: TextAlign.center, maxLines: 2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  key: const ValueKey('assurance-valider'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: enabled ? widget.onValider : null,
                  icon: const Icon(Icons.check_circle, size: 20),
                  label: Text(
                    net == 0 ? 'Valider (part client 0 F)' : (net == null ? 'Encaisser' : 'Encaisser ${Constants.formatNumber(net)} F'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

final _unknownTp = ClientTiersPayant(lgTIERSPAYANTID: '', tpFullName: 'N/A', taux: 0, numSecurity: '', compteTp: '', order: 0, principal: false);
