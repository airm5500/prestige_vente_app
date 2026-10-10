// lib/ventes/assurance/assurance_step_produits.dart
// Étape 3 : carte client permanente dans l'en-tête (client → ayant droit, TP avec taux et bon,
// « ✎ Couverture »), champ de scan (brique commune), panier comme la Pré-vente (cartes A / lignes B /
// bandes C ; ancien panier gardé si la relecture échoue), bandeau d'état et pied fixe : répartition
// toujours visible (Total, part de chaque TP, Part client ; « Calcul… » pendant le recalcul automatique),
// « PRÉVENTE » et « ENCAISSER X F » / « VALIDER (0 F) », désactivés tant que le net n'est pas à jour.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_controller.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_frame.dart';
import 'package:prestige_vente_app/ventes/common/vente_layout.dart';
import 'package:prestige_vente_app/ventes/common/vente_product_search.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_cart.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

class AssuranceStepProduits extends StatefulWidget {
  /// Présentation et en-tête communs.
  final AssuranceFrame frame;
  final Future<bool> Function(ProductSearchResult product, int qty) addProduct;
  final VoidCallback onPrevente;
  final VoidCallback onValider;

  /// Fin de vente en cours (boutons et saisie bloqués).
  final bool paying;
  const AssuranceStepProduits({
    super.key,
    required this.frame,
    required this.addProduct,
    required this.onPrevente,
    required this.onValider,
    required this.paying,
  });

  @override
  State<AssuranceStepProduits> createState() => AssuranceStepProduitsState();
}

class AssuranceStepProduitsState extends State<AssuranceStepProduits> {
  final _searchKey = GlobalKey<VenteProductSearchState>();

  /// Stock connu à l'ajout (produits ajoutés sur cet appareil) : signale un stock dépassé / forcé.
  final Map<String, int> _stockOf = {};

  void focusSearch() => _searchKey.currentState?.requestFocus();

  Future<bool> _add(ProductSearchResult product, int qty) {
    _stockOf[product.lgFAMILLEID] = product.intNUMBERAVAILABLE;
    return widget.addProduct(product, qty);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.frame;
    final c = context.watch<AssuranceController>();
    final locked = widget.paying || c.finished;
    final split = venteSplit(context); // tablette paysage : client et recherche à gauche, panier à droite
    final search = VenteProductSearch(
      key: _searchKey,
      search: c.searchProducts,
      pageSearch: c.searchPage,
      visible: c.visibleProduct,
      addProduct: _add,
      enabled: !locked,
      onDark: !f.compact && !split,
      padding: f.compact || split ? EdgeInsets.zero : null,
    );
    final card = AssuranceClientCard(controller: c, onDark: !f.compact && !split, onCouverture: locked ? null : c.returnToCouverture);
    final ref = c.reference;
    final n = c.items.length;
    final subtitle = c.venteId == null ? 'Nouvelle vente' : '${ref.isEmpty ? 'Vente en cours' : 'Réf. $ref'} · $n article${n > 1 ? 's' : ''}';
    return f.scaffold(
      step: 2,
      title: 'Produits',
      subtitle: subtitle,
      header: split ? const [] : [card, search],
      compactHeader: split ? const [] : [card, search],
      wide: split,
      body: _body(c, locked, split ? [card, search] : null),
      bottom: _footer(c),
    );
  }

  /// Bandeau d'état et panier ; [side] (tablette paysage) : panneau de gauche.
  Widget _body(AssuranceController c, bool locked, List<Widget>? side) {
    final f = widget.frame;
    final cart = LayoutBuilder(
        builder: (context, box) => Column(children: [
          // Bandeau d'état : au plus la moitié de la hauteur (petits écrans), le panier reste visible.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight / 2),
            child: SingleChildScrollView(child: AssuranceStatusBanner(controller: c)),
          ),
          Expanded(
            child: VenteCartList(
              source: CartSource(
                items: c.items,
                cartError: c.cartError,
                hasVente: c.venteId != null,
                busy: c.busy,
                locked: locked,
                reload: c.reload,
                updateLine: c.updateLine,
                removeLine: c.removeLine,
              ),
              onDone: focusSearch,
              style: f.style,
              stockOf: _stockOf,
            ),
          ),
        ]),
    );
    return side == null ? cart : VenteSplitBody(panelKey: const ValueKey('assurance-panneau-client'), side: side, main: cart);
  }

  Widget _split(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Pal.muted))),
          const SizedBox(width: 6),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Pal.ink)),
        ]),
      );

  Widget _footer(AssuranceController c) {
    final f = widget.frame;
    final s = c.summary;
    final upToDate = c.netUpToDate;
    final reason = c.hasCart && !c.finished ? c.finishBlockedReason : null;
    final enabled = c.canFinish && !widget.paying && !c.finished;
    String amount(int v) => !c.hasCart ? '0 F' : (upToDate ? '${Constants.formatNumber(v)} F' : (c.busy ? 'Calcul…' : '—'));
    final net = upToDate && s != null ? s.montantNet : null;
    int partOf(String compteTp) => s?.tierspayants.where((t) => t.compteTp == compteTp).firstOrNull?.tpnet ?? 0;
    final valider = net == 0 ? 'VALIDER (0 F)' : (net == null ? 'ENCAISSER' : 'ENCAISSER ${Constants.formatNumber(net)} F');
    return AssuranceBottomBar(children: [
      // Répartition toujours visible (net recalculé automatiquement) : Total et part de chaque TP à gauche,
      // part client en grand à droite.
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          flex: 3,
          child: Column(key: const ValueKey('assurance-repartition'), mainAxisSize: MainAxisSize.min, children: [
            _split('Total', amount(s?.montant ?? 0)),
            for (final tp in c.activeTiersPayants) _split('${tp.tpFullName} (${tp.taux} %)', amount(partOf(tp.compteTp))),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 2,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (c.busy)
                const Padding(padding: EdgeInsets.only(right: 6), child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))),
              const Flexible(child: Text('Part client', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Pal.muted))),
            ]),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(amount(s?.montantNet ?? 0),
                  key: const ValueKey('assurance-net'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Pal.ink)),
            ),
          ]),
        ),
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
          flex: 2,
          child: Tooltip(
            message: 'Enregistrer en prévente',
            child: OutlinedButton.icon(
              key: const ValueKey('assurance-prevente'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 50),
                foregroundColor: Pal.navy,
                side: BorderSide(color: enabled ? Pal.navy : Pal.line, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: enabled ? widget.onPrevente : null,
              icon: const Icon(Icons.bookmark_add_outlined, size: 20),
              label: const FittedBox(fit: BoxFit.scaleDown, child: Text('PRÉVENTE')),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: ElevatedButton.icon(
            key: const ValueKey('assurance-valider'),
            style: f.mainButton.copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(0, 50)),
              padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
            ),
            onPressed: enabled ? widget.onValider : null,
            icon: Icon(net == 0 ? Icons.check_circle : Icons.point_of_sale, size: 20),
            label: FittedBox(fit: BoxFit.scaleDown, child: Text(valider)),
          ),
        ),
      ]),
    ]);
  }
}
