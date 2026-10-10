// lib/ventes/carnet/carnet_products.dart
// Étape 3 de la Vente Carnet (A / B / C) : carte client permanente, champ de scan géant, panier
// (cartes A / lignes B / bandes C), lignes « non enregistrées » en ambre avec « Réessayer » (bloquent
// la validation), pied fixe Total / Part carnet / Part client. Le net est recalculé automatiquement
// après chaque changement ; PRÉVENTE et VALIDER exigent un net à jour.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_controller.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_frame.dart';
import 'package:prestige_vente_app/ventes/common/vente_dialogs.dart';
import 'package:prestige_vente_app/ventes/common/vente_layout.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/common/vente_product_search.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

/// Ajout refusé faute de réponse (panne) : affiché en ambre jusqu'à « Réessayer » ou « Retirer ».
/// [baseQty] = quantité du produit déjà au panier au moment de l'échec (pour ne jamais l'ajouter deux fois).
class CarnetUnsavedLine {
  final ProductSearchResult product;
  final int qty;
  int baseQty;
  CarnetUnsavedLine({required this.product, required this.qty, required this.baseQty});
}

/// Raison qui bloque la fin de vente à cause de lignes non enregistrées (null si aucune).
String? unsavedReason(List<CarnetUnsavedLine> lines) {
  final n = lines.length;
  if (n == 0) return null;
  return n == 1
      ? '1 ligne non enregistrée : touchez « Réessayer » ou retirez-la.'
      : '$n lignes non enregistrées : touchez « Réessayer » ou retirez-les.';
}

class CarnetProductsStep extends StatelessWidget {
  final CarnetFrame frame;
  final GlobalKey<VenteProductSearchState> searchKey;
  final Future<bool> Function(ProductSearchResult product, int qty) addProduct;
  final VoidCallback onPrevente;
  final VoidCallback onValider;

  /// Validation en cours (boutons et recherche bloqués).
  final bool paying;

  /// Lignes non enregistrées sur le serveur.
  final List<CarnetUnsavedLine> unsaved;
  final bool retrying;
  final void Function(CarnetUnsavedLine line) onRetry;
  final VoidCallback onRetryAll;
  final void Function(CarnetUnsavedLine line) onDrop;

  /// Hors ligne : terminer sur l'appareil une vente commencée en ligne.
  final VoidCallback? onTerminerHorsLigne;

  const CarnetProductsStep({
    super.key,
    required this.frame,
    required this.searchKey,
    required this.addProduct,
    required this.onPrevente,
    required this.onValider,
    required this.paying,
    this.unsaved = const [],
    this.retrying = false,
    required this.onRetry,
    required this.onRetryAll,
    required this.onDrop,
    this.onTerminerHorsLigne,
  });

  void _focus() => searchKey.currentState?.requestFocus();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CarnetController>();
    final compact = frame.compact;
    final ref = c.items.isNotEmpty ? c.items.first.strREF : '';
    final n = c.items.length;
    final split = venteSplit(context); // tablette paysage : client et recherche à gauche, panier à droite
    final search = VenteProductSearch(
      key: searchKey,
      search: c.search,
      pageSearch: c.searchPage,
      visible: c.visibleProduct,
      addProduct: addProduct,
      enabled: !paying && !c.finished,
      onDark: !compact && !split,
      padding: compact || split ? EdgeInsets.zero : null,
    );
    final onBon = paying || c.finished ? null : c.goToBonStep;
    final cart = LayoutBuilder(
        builder: (context, box) => Column(children: [
          // Bandeaux limités à la moitié de la hauteur (petits écrans) : le panier reste visible.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * 0.5),
            child: SingleChildScrollView(
                child: _CarnetStatus(
                    controller: c,
                    unsaved: unsaved,
                    retrying: retrying,
                    onRetryAll: onRetryAll,
                    onTerminerHorsLigne: paying || c.finished ? null : onTerminerHorsLigne)),
          ),
          Expanded(
            child: CarnetCart(onDone: _focus, style: frame.style, unsaved: unsaved, retrying: retrying, onRetry: onRetry, onDrop: onDrop),
          ),
        ]),
    );
    return frame.scaffold(
      title: 'Produits',
      subtitle: '${ref.isEmpty ? (c.venteId == null ? 'Nouvelle vente' : 'Vente en cours') : ref} · $n article${n > 1 ? 's' : ''}',
      header: split ? const [] : [CarnetClientBanner(controller: c, dark: true, onBon: onBon), search],
      compactHeader: split ? const [] : [CarnetClientBanner(controller: c, dark: false, onBon: onBon), search],
      // A : pas de barre d'étapes ici (en-tête déjà chargé) ; « ✎ Bon » permet le retour.
      // Tablette paysage : barre d'étapes dans l'en-tête, carte client à gauche.
      pills: split,
      wide: split,
      body: split
          ? VenteSplitBody(
              panelKey: const ValueKey('carnet-panneau-client'),
              side: [CarnetClientBanner(controller: c, dark: false, onBon: onBon), search],
              main: cart,
            )
          : cart,
      bottom: _CarnetFooter(frame: frame, onPrevente: onPrevente, onValider: onValider, paying: paying, unsaved: unsaved),
    );
  }
}

/// Bandeau d'état : non relu / net non calculé / lignes non enregistrées / envoi… / enregistré ✓.
class _CarnetStatus extends StatelessWidget {
  final CarnetController controller;
  final List<CarnetUnsavedLine> unsaved;
  final bool retrying;
  final VoidCallback onRetryAll;
  final VoidCallback? onTerminerHorsLigne;
  const _CarnetStatus({required this.controller, required this.unsaved, required this.retrying, required this.onRetryAll, this.onTerminerHorsLigne});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final hl = c.panierHorsLigne;
    if (hl != null && !c.finished) {
      return _Strip(
        key: const ValueKey('carnet-etat-hors-ligne'),
        bg: const Color(0xFFFFF4E0),
        fg: const Color(0xFF7C2D12),
        leading: const Icon(Icons.cloud_off, size: 16, color: Color(0xFF9A3412)),
        text: '${hl.label} enregistrée sur l\'appareil · parts estimées : le net définitif sera celui du serveur',
      );
    }
    if (c.peutTerminerHorsLigne) {
      return _Strip(
        key: const ValueKey('carnet-proposer-hors-ligne'),
        bg: const Color(0xFFFFF4E0),
        fg: const Color(0xFF7C2D12),
        leading: const Icon(Icons.cloud_off, size: 16, color: Color(0xFF9A3412)),
        text: 'Serveur hors ligne : cette vente peut être terminée sur l\'appareil.',
        action: TextButton(
          key: const ValueKey('carnet-terminer-hors-ligne'),
          style: TextButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: Pal.navy, padding: const EdgeInsets.symmetric(horizontal: 8)),
          onPressed: c.busy ? null : onTerminerHorsLigne,
          child: const Text('Terminer hors ligne', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
    }
    final banners = <Widget>[
      if (c.cartError != null && c.items.isNotEmpty)
        LoadErrorBanner(message: 'Panier non relu : ${venteMessage(c.cartError)} (dernier état affiché).', onRetry: c.busy ? null : c.reload),
      if (c.netError != null && c.cartError == null && c.hasCart)
        LoadErrorBanner(message: 'Net à payer non calculé : ${venteMessage(c.netError)}', onRetry: c.busy ? null : c.reload),
      if (unsaved.isNotEmpty)
        _Strip(
          key: const ValueKey('carnet-etat-non-enregistre'),
          bg: const Color(0xFFFFF4E0),
          fg: const Color(0xFF7C2D12),
          border: const Color(0xFFF5D08A),
          leading: const Icon(Icons.sync_problem, size: 18, color: Color(0xFF9A3412)),
          text: '${unsaved.length} ligne${unsaved.length > 1 ? 's' : ''} non enregistrée${unsaved.length > 1 ? 's' : ''} sur le serveur.',
          action: TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(0, 40), foregroundColor: Pal.navy, padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: retrying || c.busy ? null : onRetryAll,
            child: const Text('Réessayer', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
    ];
    if (banners.isNotEmpty) return Column(mainAxisSize: MainAxisSize.min, children: banners);
    if (c.busy && c.venteId != null) {
      return const _Strip(
        key: ValueKey('carnet-etat-envoi'),
        bg: Color(0xFFE3ECF7),
        fg: Pal.navy,
        leading: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        text: 'Envoi au serveur…',
      );
    }
    if (c.hasCart && c.netUpToDate && !c.finished) {
      final n = c.items.length;
      return _Strip(
        key: const ValueKey('carnet-etat-ok'),
        bg: const Color(0xFFE6F4EA),
        fg: const Color(0xFF14532D),
        leading: const Icon(Icons.check_circle, size: 16, color: Color(0xFF16A34A)),
        text: '$n article${n > 1 ? 's' : ''} enregistré${n > 1 ? 's' : ''} sur le serveur',
      );
    }
    return const SizedBox.shrink();
  }
}

class _Strip extends StatelessWidget {
  final Color bg;
  final Color fg;
  final Color? border;
  final Widget leading;
  final String text;
  final Widget? action;
  const _Strip({super.key, required this.bg, required this.fg, this.border, required this.leading, required this.text, this.action});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: EdgeInsets.fromLTRB(11, action == null ? 8 : 2, action == null ? 11 : 2, action == null ? 8 : 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: border == null ? null : Border.all(color: border!)),
        child: Row(children: [
          leading,
          const SizedBox(width: 8),
          Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w500))),
          if (action != null) action!,
        ]),
      );
}

/// Panier : Modifier (quantité 1-9 999, prix libre borné), Supprimer avec confirmation.
/// A : cartes ; B : lignes denses (toucher = modifier) ; C : cartes à bande (vert enregistré, ambre non enregistré).
/// Si la relecture échoue, l'ancien panier reste affiché (jamais un panier vide trompeur).
class CarnetCart extends StatelessWidget {
  final VoidCallback? onDone;
  final ListPresentation style;
  final List<CarnetUnsavedLine> unsaved;
  final bool retrying;
  final void Function(CarnetUnsavedLine line)? onRetry;
  final void Function(CarnetUnsavedLine line)? onDrop;
  const CarnetCart({
    super.key,
    this.onDone,
    this.style = ListPresentation.dashboard,
    this.unsaved = const [],
    this.retrying = false,
    this.onRetry,
    this.onDrop,
  });

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
    if (items.isEmpty && unsaved.isEmpty) {
      if (c.cartError != null && c.venteId != null) {
        return LoadErrorView(message: 'Panier non relu : ${venteMessage(c.cartError)}', onRetry: c.reload);
      }
      if (c.busy && c.venteId != null) return const Center(child: CircularProgressIndicator());
      return const Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shopping_cart_outlined, size: 60, color: Color(0xFF9AA8BC)),
            SizedBox(height: 10),
            Text('Le panier est vide', style: TextStyle(fontSize: 16, color: Pal.ink, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('Scannez ou recherchez un produit', style: TextStyle(fontSize: 13, color: Pal.muted)),
          ]),
        ),
      );
    }
    final locked = c.finished;
    final edit = locked ? null : (SaleItemDetail i) => _edit(context, c, i);
    final delete = locked ? null : (SaleItemDetail i) => _delete(context, c, i);
    final compact = style == ListPresentation.compact;
    final guided = style == ListPresentation.guided;
    final rows = <Widget>[
      for (final item in items)
        compact
            ? _DenseRow(item: item, onEdit: edit, onDelete: delete)
            : _CartCard(item: item, band: guided ? Pal.green : null, onEdit: edit, onDelete: delete),
      for (final u in unsaved)
        _UnsavedLine(
          line: u,
          compact: compact,
          onRetry: retrying || c.busy || onRetry == null ? null : () => onRetry!(u),
          onDrop: retrying || onDrop == null ? null : () => onDrop!(u),
        ),
      if (compact)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Toucher une ligne : modifier', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Pal.muted)),
        ),
    ];
    return ListView.separated(
      padding: compact ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 10, 12, 16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => compact ? const Divider(height: 1, color: Color(0xFFEEF1F5)) : const SizedBox(height: 9),
      itemBuilder: (_, i) => rows[i],
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

/// Carte blanche, avec bande de couleur à gauche en C.
Widget _card({required Widget child, Color? band}) => Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x1014213D), blurRadius: 4, offset: Offset(0, 1))],
      ),
      clipBehavior: Clip.antiAlias,
      child: band == null
          ? child
          : IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 5, color: band),
                Expanded(child: child),
              ]),
            ),
    );

/// Carte d'une ligne enregistrée (A ; C avec bande verte).
class _CartCard extends StatelessWidget {
  final SaleItemDetail item;
  final Color? band;
  final void Function(SaleItemDetail)? onEdit;
  final void Function(SaleItemDetail)? onDelete;
  const _CartCard({required this.item, this.band, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) => _card(
        band: band,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.strNAME, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: Pal.ink)),
                  if (item.intCIP.isNotEmpty)
                    Text('CIP ${item.intCIP}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Pal.muted)),
                ]),
              ),
              const SizedBox(width: 8),
              Text('${Constants.formatNumber(item.intPRICE)} F', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Pal.ink)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Text('${item.intQUANTITY} × ${Constants.formatNumber(item.intPRICEUNITAIR)} F',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
              ),
              _MiniButton(icon: Icons.edit_outlined, tooltip: 'Modifier', color: Pal.navy, onPressed: onEdit == null ? null : () => onEdit!(item)),
              const SizedBox(width: 6),
              _MiniButton(icon: Icons.delete_outline, tooltip: 'Supprimer', color: Colors.red.shade700, onPressed: onDelete == null ? null : () => onDelete!(item)),
            ]),
          ]),
        ),
      );
}

/// Ligne dense (B) : toucher = modifier ; Modifier / Supprimer à droite.
class _DenseRow extends StatelessWidget {
  final SaleItemDetail item;
  final void Function(SaleItemDetail)? onEdit;
  final void Function(SaleItemDetail)? onDelete;
  const _DenseRow({required this.item, this.onEdit, this.onDelete});

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
                  Text('${item.intQUANTITY} × ${Constants.formatNumber(item.intPRICEUNITAIR)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
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

/// Ligne non enregistrée sur le serveur : bande ambre, « Réessayer » / « Retirer ».
class _UnsavedLine extends StatelessWidget {
  final CarnetUnsavedLine line;
  final bool compact;
  final VoidCallback? onRetry;
  final VoidCallback? onDrop;
  const _UnsavedLine({required this.line, required this.compact, this.onRetry, this.onDrop});

  @override
  Widget build(BuildContext context) {
    final p = line.product;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(compact ? 14 : 12, 8, 4, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(p.strNAME, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: Pal.ink)),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text('${Constants.formatNumber(line.qty * p.intPRICE)} F',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF9A3412))),
          ),
        ]),
        Row(children: [
          Expanded(
            child: Text('${line.qty} × ${Constants.formatNumber(p.intPRICE)} F · ⟳ non enregistrée',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Color(0xFF9A3412), fontWeight: FontWeight.w500)),
          ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: Pal.navy, padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: onRetry,
            child: const Text('Réessayer', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          IconButton(
            tooltip: 'Retirer (non enregistrée)',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(Icons.close, size: 20, color: onDrop == null ? Colors.grey : Colors.red.shade700),
            onPressed: onDrop,
          ),
        ]),
      ]),
    );
    if (compact) return Container(color: const Color(0xFFFFF8EC), child: content);
    return _card(band: Pal.amber, child: Container(color: const Color(0xFFFFFBF3), child: content));
  }
}

class _CarnetFooter extends StatelessWidget {
  final CarnetFrame frame;
  final VoidCallback onPrevente;
  final VoidCallback onValider;
  final bool paying;
  final List<CarnetUnsavedLine> unsaved;
  const _CarnetFooter({required this.frame, required this.onPrevente, required this.onValider, required this.paying, required this.unsaved});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CarnetController>();
    final s = c.summary;
    final upToDate = c.hasCart && c.netUpToDate && s != null;
    final blocked = unsavedReason(unsaved);
    final reason = c.hasCart && !c.finished ? (blocked ?? c.finishBlockedReason) : (blocked);
    final enabled = c.canFinish && blocked == null && !paying && !c.finished;
    String amount(int v) => upToDate ? '${Constants.formatNumber(v)} F' : (c.busy ? 'Calcul…' : '—');
    final tpNames = {for (final tp in c.client?.tiersPayants ?? const []) tp.compteTp: tp.tpFullName};
    final taux = c.activeTps.fold<int>(0, (a, tp) => a + tp.taux);
    final several = upToDate && s.tierspayants.length > 1;
    final hl = c.horsLigne;
    final est = hl ? ' (estimée)' : '';

    return CarnetBottomBar(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (c.hasCart) ...[
          _row(hl ? 'Total (estimé)' : 'Total', amount(s?.montant ?? 0)),
          _row('Part carnet${c.activeTps.isEmpty ? '' : ' $taux %'}$est', amount(s?.montantTp ?? 0)),
          if (several)
            for (final tp in s.tierspayants)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: _row('∙ ${tpNames[tp.compteTp] ?? tp.compteTp} · bon ${tp.numBon} (${tp.taux} %)', '${Constants.formatNumber(tp.tpnet)} F', size: 12),
              ),
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Text('Part client$est', style: const TextStyle(fontSize: 14, color: Pal.muted))),
          if (c.busy) const Padding(padding: EdgeInsets.only(right: 8, bottom: 4), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(c.hasCart ? amount(s?.montantNet ?? 0) : '0 F',
                  key: const ValueKey('carnet-net'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Pal.ink)),
            ),
          ),
        ]),
        if (reason != null && (!c.busy || blocked != null))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(reason, key: const ValueKey('carnet-fin-raison'), style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
            ),
          ),
        const SizedBox(height: 8),
        if (hl)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const ValueKey('carnet-hl-prevente'),
              style: frame.mainButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 50))),
              onPressed: enabled ? onPrevente : null,
              icon: const Icon(Icons.bookmark_add_outlined, size: 20),
              label: const FittedBox(fit: BoxFit.scaleDown, child: Text('ENREGISTRER (PRÉVENTE PROVISOIRE)')),
            ),
          )
        else
        Row(children: [
          Expanded(
            child: Tooltip(
              message: 'Enregistrer en prévente',
              child: OutlinedButton.icon(
                key: const ValueKey('carnet-prevente'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  foregroundColor: Pal.navy,
                  side: BorderSide(color: enabled ? Pal.navy : Pal.line, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: enabled ? onPrevente : null,
                icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                label: const FittedBox(fit: BoxFit.scaleDown, child: Text('PRÉVENTE')),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: 'Valider la vente carnet',
              child: ElevatedButton.icon(
                key: const ValueKey('carnet-valider'),
                style: frame.mainButton.copyWith(
                  minimumSize: const WidgetStatePropertyAll(Size(0, 50)),
                  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
                ),
                onPressed: enabled ? onValider : null,
                icon: const Icon(Icons.check_circle, size: 20),
                label: const FittedBox(fit: BoxFit.scaleDown, child: Text('VALIDER')),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _row(String label, String value, {double size = 13.5}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: size, color: Pal.muted))),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(fontSize: size, fontWeight: FontWeight.bold, color: Pal.ink)),
        ]),
      );
}
