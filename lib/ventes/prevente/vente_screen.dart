// lib/ventes/prevente/vente_screen.dart
// Pré-vente / Vente — nouvelle version, présentations A / B / C (menu « Présentation » mémorisé).
// Un seul panier ; le choix se fait à la fin : « Prévente » (terminerprevente) ou « Encaisser »
// (page d'encaissement unique). « Préventes à encaisser » : page de liste (bouton de l'en-tête).
// La logique (file d'opérations, réponses perdues, net à jour, reprise) reste dans VenteController.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/common/vente_dialogs.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/common/vente_product_search.dart';
import 'package:prestige_vente_app/ventes/core/pending_sale_store.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/encaissement_page.dart';
import 'package:prestige_vente_app/ventes/prevente/prevente_dialogs.dart';
import 'package:prestige_vente_app/ventes/prevente/prevente_list.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_cart.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

class VenteScreen extends StatelessWidget {
  /// Onglet d'origine : 0 PREVENTE, 1 VENTE (→ panier), 2 LISTE (→ préventes à encaisser).
  final int initialTabIndex;

  /// Vente à afficher au démarrage (ex. pré-vente créée depuis une ordonnance).
  final String? resumeVenteId;

  /// Accès serveur (simulé dans les tests).
  final VenteGateway? gateway;

  /// Présentation (A, B, C) ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;

  const VenteScreen({super.key, this.initialTabIndex = 0, this.resumeVenteId, this.gateway, this.presentation});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<VenteController>(
        create: (ctx) => VenteController(gateway: gateway ?? DioVenteGateway(Provider.of<ApiService>(ctx, listen: false))),
        child: _VenteView(openList: initialTabIndex >= 2, resumeVenteId: resumeVenteId, presentation: presentation),
      );
}

class _VenteView extends StatefulWidget {
  final bool openList;
  final String? resumeVenteId;
  final ListPresentation? presentation;
  const _VenteView({required this.openList, this.resumeVenteId, this.presentation});

  @override
  State<_VenteView> createState() => _VenteViewState();
}

class _VenteViewState extends State<_VenteView> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  final _searchKey = GlobalKey<VenteProductSearchState>();
  bool _paying = false;

  /// Stock connu à l'ajout (produits ajoutés sur cet appareil) : signale un stock dépassé / forcé.
  final Map<String, int> _stockOf = {};

  VenteController get _ctrl => context.read<VenteController>();

  @override
  void initState() {
    super.initState();
    loadPresentation();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  void _focusSearch() => _searchKey.currentState?.requestFocus();

  /// Démarrage : vente demandée (ordonnance) ou proposition de reprendre la vente mémorisée.
  Future<void> _start() async {
    await _resumeOnStart();
    if (mounted && widget.openList) await _openList();
  }

  Future<void> _resumeOnStart() async {
    if (!mounted) return;
    final c = _ctrl;
    unawaited(c.loadQrMethods());
    final id = widget.resumeVenteId;
    if (id != null && id.isNotEmpty) {
      await c.loadVente(id);
      if (mounted && c.cartError != null) showVenteFailure(context, VenteFailed<void>(c.cartError!), onRetry: c.reload);
      return;
    }
    final pending = await PendingSaleStore.load(VenteMenu.prevente);
    if (pending == null || !mounted) return;
    final closed = await c.isClosedOnServer(pending.venteId);
    if (!mounted) return;
    if (closed == true) {
      await PendingSaleStore.clear(VenteMenu.prevente);
      if (mounted) showVenteSnack(context, 'La vente ${pending.reference} a déjà été clôturée.');
      return;
    }
    final resume = await showReprendreVenteDialog(context,
        reference: pending.reference, itemCount: pending.itemCount, total: pending.total, savedAt: pending.savedAt);
    if (!mounted || !resume) {
      _focusSearch();
      return;
    }
    await c.loadVente(pending.venteId);
    if (mounted) _focusSearch();
  }

  // ---------------------------------------------------------------------------
  // Panier
  // ---------------------------------------------------------------------------

  Future<bool> _addProduct(ProductSearchResult product, int qty) async {
    _stockOf[product.lgFAMILLEID] = product.intNUMBERAVAILABLE;
    final r = await _ctrl.addProduct(product, qty);
    if (!mounted) return false;
    if (!r.isOk) {
      if (await handleCaisseFermee(context, r)) return false;
      if (mounted) showVenteFailure(context, r);
    }
    return r.isOk;
  }

  String _cartLabel(VenteController c) =>
      '${c.items.length} article${c.items.length > 1 ? 's' : ''}${c.summary.montantNet > 0 ? ' · ${Constants.formatNumber(c.summary.montantNet)} F' : ''}';

  String _panier(VenteController c) =>
      'La vente ${panierLabel(reference: c.summary.reference, itemCount: c.items.length, total: c.summary.montantNet)}';

  int _boxes(VenteController c) => c.items.fold<int>(0, (s, i) => s + i.intQUANTITY);

  /// « Préventes à encaisser » : page de liste ; la prévente choisie est chargée dans le panier.
  Future<void> _openList() async {
    if (_paying || !mounted) return;
    final c = _ctrl;
    final item = await Navigator.of(context).push<PreventeListItem>(MaterialPageRoute(
      builder: (_) => PreventeListScreen(load: c.preventes, onSelect: _confirmSwitch, presentation: style),
    ));
    if (item == null || !mounted) {
      _focusSearch();
      return;
    }
    await c.loadVente(item.lgPREENREGISTREMENTID);
    if (!mounted) return;
    if (c.cartError != null) showVenteFailure(context, VenteFailed<void>(c.cartError!), onRetry: c.reload);
    _focusSearch();
  }

  /// Prévente choisie dans la liste : true = l'ouvrir, null = revenir au panier, false = rester sur la liste.
  Future<bool?> _confirmSwitch(PreventeListItem item) async {
    final c = _ctrl;
    await c.idle();
    if (!mounted) return false;
    if (!c.hasCart || c.finished || c.venteId == item.lgPREENREGISTREMENTID) return true;
    final choice = await showPanierEnCoursDialog(
      context,
      panier: _panier(c),
      action: 'ouvrir ${item.strREF}',
      abandonLabel: 'Ouvrir ${item.strREF} sans l\'enregistrer',
    );
    if (!mounted) return false;
    switch (choice) {
      case PanierEnCoursChoice.garder:
        return null;
      case PanierEnCoursChoice.abandonner:
        return true;
      case PanierEnCoursChoice.enregistrer:
        return await _savePrevente();
    }
  }

  Future<void> _newSale() async {
    final c = _ctrl;
    await c.idle();
    if (!mounted) return;
    if (c.hasCart && !c.finished) {
      final choice = await showPanierEnCoursDialog(
        context,
        panier: _panier(c),
        action: 'commencer une nouvelle vente',
        abandonLabel: 'Nouvelle vente sans l\'enregistrer',
      );
      if (!mounted) return;
      switch (choice) {
        case PanierEnCoursChoice.garder:
          _focusSearch();
          return;
        case PanierEnCoursChoice.enregistrer:
          await _savePrevente(); // remet un panier vide si l'enregistrement réussit
          return;
        case PanierEnCoursChoice.abandonner:
          break;
      }
    }
    c.reset();
    _focusSearch();
  }

  // ---------------------------------------------------------------------------
  // Fin de vente
  // ---------------------------------------------------------------------------

  /// Contrôles communs avant de terminer ; renvoie l'utilisateur ou null (message affiché).
  Future<User?> _readyToFinish() async {
    final c = _ctrl;
    await c.idle();
    if (!mounted) return null;
    final reason = c.finishBlockedReason;
    if (reason != null) {
      showVenteSnack(context, reason, error: true);
      return null;
    }
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) {
      showVenteSnack(context, 'Utilisateur non connecté : reconnectez-vous.', error: true);
      return null;
    }
    return user;
  }

  /// « Prévente » : terminerprevente. Renvoie true si la vente est enregistrée.
  Future<bool> _savePrevente() async {
    if (_paying) return false;
    setState(() => _paying = true);
    try {
      final user = await _readyToFinish();
      if (user == null || !mounted) return false;
      final c = _ctrl;
      final summary = c.summary, id = c.venteId;
      final r = await c.terminerPrevente();
      if (!mounted) return false;
      if (!r.isOk) {
        if (await handleCaisseFermee(context, r)) return false;
        if (mounted) showVenteFailure(context, r, onRetry: _savePrevente);
        return false;
      }
      await _afterPrevente(venteId: id, summary: summary, user: user);
      return true;
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  /// « Encaisser » : page d'encaissement (modes de règlement puis clôture, comme avant).
  Future<void> _encaisser() async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      final user = await _readyToFinish();
      if (user == null || !mounted) return;
      final c = _ctrl;
      final changes = c.changes, summary = c.summary, items = c.items, id = c.venteId;
      final done = await Navigator.of(context).push<EncaissementDone>(MaterialPageRoute(
        builder: (_) => EncaissementPage(
          controller: c,
          userId: user.userId,
          expectedChanges: changes,
          summary: summary,
          itemCount: items.length,
          presentation: style,
        ),
      ));
      if (done == null || !mounted) return;
      await _afterEncaissement(done, venteId: id, summary: summary, items: items, user: user);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _afterEncaissement(EncaissementDone done,
      {required String? venteId, required SaleSummary summary, required List<SaleItemDetail> items, required User user}) async {
    final ref = summary.reference.isEmpty ? '' : ' (${summary.reference})';
    showVenteSnack(
      context,
      done.dejaCloturee
          ? 'Vente déjà clôturée sur le serveur$ref : aucune seconde clôture.'
          : 'Vente encaissée ✓$ref',
      color: Colors.green.shade700,
    );
    if (done.copies > 0) {
      final officine = Provider.of<AuthProvider>(context, listen: false).officine;
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      if (officine == null) {
        showVenteSnack(context, 'Données officine manquantes : ticket non imprimé.', error: true);
      } else {
        for (var i = 0; i < done.copies && mounted; i++) {
          await ReceiptService().printSaleTicket(
            context: context,
            officine: officine,
            saleSummary: summary,
            items: items,
            paymentMethod: done.method,
            currentUser: user,
            isTestMode: settings.isTestPrintMode,
            paperWidth: settings.paperWidth,
            showQrCode: settings.showQrCodeOnSaleTicket,
            ticketCodeType: settings.ticketCodeType,
            montantVerse: done.recu,
            monnaie: done.remis,
            reglements: ticketReglementsOf(done),
          );
        }
      }
    }
    if (!mounted) return;
    _refreshHome(venteId);
    _ctrl.reset();
    _stockOf.clear();
    _focusSearch();
  }

  Future<void> _afterPrevente({required String? venteId, required SaleSummary summary, required User user}) async {
    final print = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Prévente enregistrée'),
        content: Text('${summary.reference.isEmpty ? 'La prévente' : 'La prévente ${summary.reference}'} est dans la liste des préventes à encaisser.\n'
            'Voulez-vous imprimer le ticket ?'),
        actions: [
          TextButton(style: TextButton.styleFrom(minimumSize: const Size(64, 44)), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Non')),
          ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size(88, 44)), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Imprimer')),
        ],
      ),
    );
    if (!mounted) return;
    if (print == true) {
      final officine = Provider.of<AuthProvider>(context, listen: false).officine;
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      if (officine == null) {
        showVenteSnack(context, 'Données officine manquantes : ticket non imprimé.', error: true);
      } else {
        await ReceiptService().printPreventeTicket(
          context: context,
          officine: officine,
          saleSummary: summary,
          currentUser: user,
          isTestMode: settings.isTestPrintMode,
          paperWidth: settings.paperWidth,
          ticketCodeType: settings.ticketCodeType,
        );
      }
    }
    if (!mounted) return;
    _refreshHome(venteId);
    _ctrl.reset();
    _stockOf.clear();
    _focusSearch();
  }

  /// Compteur des préventes de l'accueil (SaleProvider global, lu seulement s'il existe).
  void _refreshHome(String? venteId) {
    try {
      final sp = Provider.of<SaleProvider>(context, listen: false);
      if (venteId != null && sp.currentVenteId == venteId) sp.startNewSale();
      unawaited(sp.fetchPreventes());
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Quitter en pleine vente
  // ---------------------------------------------------------------------------

  Future<void> _confirmLeave() async {
    final c = _ctrl;
    await c.idle();
    if (!mounted) return;
    if (!c.hasCart || c.finished) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await confirmVenteAction(
      context,
      title: 'Quitter la vente en cours ?',
      message: 'Cette vente (${_cartLabel(c)}) n\'est ni encaissée ni enregistrée en prévente.\n\n'
          'Elle est conservée : à la réouverture du menu, « Reprendre la vente ? » vous sera proposé.',
      confirm: 'Quitter',
      cancel: 'Rester',
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.watch<VenteController>();
    final ref = c.summary.reference;
    final n = c.items.length;
    final compact = style == ListPresentation.compact;
    final String subtitle;
    if (c.venteId == null) {
      subtitle = 'Nouvelle vente';
    } else if (compact) {
      subtitle = '${ref.isEmpty ? 'Vente en cours' : ref} · $n article${n > 1 ? 's' : ''}';
    } else {
      subtitle = '${ref.isEmpty ? 'Vente en cours' : 'Réf. $ref'} · ${c.finished ? 'terminée' : 'non encaissée'}';
    }
    final search = VenteProductSearch(
      key: _searchKey,
      search: c.search,
      pageSearch: c.searchPage,
      visible: c.visibleProduct,
      addProduct: _addProduct,
      enabled: !_paying && !c.finished,
      onDark: !compact,
      padding: compact ? EdgeInsets.zero : null,
    );
    final total = c.hasCart ? c.summary.montantNet : 0;
    return PopScope(
      canPop: !c.busy && (!c.hasCart || c.finished),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: PresentationScaffold(
        style: style,
        title: 'Vente',
        subtitle: subtitle,
        actions: (col) => [
          IconButton(
            icon: Icon(Icons.receipt_long_outlined, color: col),
            tooltip: 'Préventes à encaisser',
            onPressed: _paying ? null : _openList,
          ),
          IconButton(
            icon: Icon(Icons.add_shopping_cart, color: col),
            tooltip: 'Nouvelle vente',
            onPressed: _paying ? null : _newSale,
          ),
          PresentationMenuButton(value: style, onChanged: _setStyle, color: col),
        ],
        steps: StepsBar(active: c.hasCart ? 1 : 0, steps: [
          (title: 'Panier', detail: n == 0 ? 'scanner' : '$n article${n > 1 ? 's' : ''}', onTap: null),
          (title: 'Vérifier', detail: 'total, lignes', onTap: null),
          (title: 'Encaisser', detail: 'paiement', onTap: null),
        ]),
        header: [
          if (style == ListPresentation.dashboard)
            Row(children: [
              Expanded(child: KpiTile('$n', n > 1 ? 'articles' : 'article')),
              const SizedBox(width: 8),
              Expanded(child: KpiTile('${_boxes(c)}', 'boîtes')),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: _TotalKpi(total)),
            ]),
          search,
        ],
        compactHeader: [
          LightFigures([
            ('$n', n > 1 ? 'articles' : 'article', Pal.navy),
            ('${_boxes(c)}', 'boîtes', Pal.blue),
            ('${Constants.formatNumber(total)} F', 'total', Pal.green),
          ]),
          search,
        ],
        body: Column(children: [
          _StatusBanner(controller: c),
          Expanded(
            child: VenteCart(
              onDone: _focusSearch,
              style: style,
              stockOf: _stockOf,
              emptyAction: OutlinedButton.icon(
                style: outlineButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 48))),
                onPressed: _paying ? null : _openList,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Préventes à encaisser'),
              ),
            ),
          ),
        ]),
        bottomNavigationBar: _footer(c),
      ),
    );
  }

  Widget _footer(VenteController c) {
    final s = c.summary;
    final reason = c.hasCart && !c.finished ? c.finishBlockedReason : null;
    final enabled = c.canFinish && !_paying && !c.finished;
    final netText = !c.hasCart
        ? '0 F'
        : c.netUpToDate
            ? '${Constants.formatNumber(s.montantNet)} F'
            : (c.busy ? 'Calcul…' : '—');
    final compact = style == ListPresentation.compact;
    final label = compact ? 'Total · ${_boxes(c)} boîte${_boxes(c) > 1 ? 's' : ''}' : 'Total à payer';
    final remise = c.hasCart && c.netUpToDate && s.montant != s.montantNet;
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 13, color: Pal.muted)),
                  if (remise)
                    Text('Brut ${Constants.formatNumber(s.montant)} F · remise ${Constants.formatNumber(s.montant - s.montantNet)} F',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Pal.muted)),
                ]),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(netText, key: const ValueKey('vente-net'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Pal.ink)),
                ),
              ),
            ]),
            if (reason != null && !c.busy)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(reason, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                ),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Tooltip(
                  message: 'Enregistrer en prévente',
                  child: OutlinedButton.icon(
                    key: const ValueKey('vente-enregistrer-prevente'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      foregroundColor: Pal.navy,
                      side: BorderSide(color: enabled ? Pal.navy : Pal.line, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: enabled ? _savePrevente : null,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                    label: const FittedBox(fit: BoxFit.scaleDown, child: Text('PRÉVENTE')),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  key: const ValueKey('vente-encaisser'),
                  style: (style == ListPresentation.guided ? amberButton : navyButton).copyWith(
                    minimumSize: const WidgetStatePropertyAll(Size(0, 50)),
                    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
                  ),
                  onPressed: enabled ? _encaisser : null,
                  icon: const Icon(Icons.point_of_sale, size: 20),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('ENCAISSER')),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Tuile « total » ambre de l'en-tête (A) : montant ajusté à la largeur.
class _TotalKpi extends StatelessWidget {
  final int total;
  const _TotalKpi(this.total);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Pal.amber, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('${Constants.formatNumber(total)} F', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Pal.onAmber)),
          ),
          const Text('total', style: TextStyle(fontSize: 12, color: Pal.onAmber, fontWeight: FontWeight.w500)),
        ]),
      );
}

/// Bandeau d'état du panier : enregistré ✓ / envoi… / non relu / net non calculé.
class _StatusBanner extends StatelessWidget {
  final VenteController controller;
  const _StatusBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.cartError != null && c.items.isNotEmpty) {
      return LoadErrorBanner(message: 'Panier non relu : ${venteMessage(c.cartError)} (dernier état affiché).', onRetry: c.busy ? null : c.reload);
    }
    if (c.netError != null && c.cartError == null && c.hasCart) {
      return LoadErrorBanner(message: 'Net à payer non calculé : ${venteMessage(c.netError)}', onRetry: c.busy ? null : c.reload);
    }
    if (c.busy && c.venteId != null) {
      return const _Strip(
        key: ValueKey('vente-etat-envoi'),
        bg: Color(0xFFE3ECF7),
        fg: Pal.navy,
        leading: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        text: 'Envoi au serveur…',
      );
    }
    if (c.hasCart && c.netUpToDate && !c.finished) {
      final n = c.items.length;
      return _Strip(
        key: const ValueKey('vente-etat-ok'),
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
  final Widget leading;
  final String text;
  const _Strip({super.key, required this.bg, required this.fg, required this.leading, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          leading,
          const SizedBox(width: 8),
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w500))),
        ]),
      );
}
