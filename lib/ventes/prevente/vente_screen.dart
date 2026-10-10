// lib/ventes/prevente/vente_screen.dart
// Pré-vente / Vente — nouvelle version (copie fiabilisée de lib/screens/pre_vente).
// Un seul panier ; le choix se fait à la fin : « Enregistrer en prévente » ou « Encaisser ».
// Onglet « Préventes » : liste des préventes à encaisser.
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
import 'package:prestige_vente_app/ventes/prevente/prevente_list.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_cart.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

class VenteScreen extends StatelessWidget {
  /// Onglet d'origine : 0 PREVENTE, 1 VENTE (→ panier), 2 LISTE (→ préventes).
  final int initialTabIndex;

  /// Vente à afficher au démarrage (ex. pré-vente créée depuis une ordonnance).
  final String? resumeVenteId;

  /// Accès serveur (simulé dans les tests).
  final VenteGateway? gateway;

  const VenteScreen({super.key, this.initialTabIndex = 0, this.resumeVenteId, this.gateway});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<VenteController>(
        create: (ctx) => VenteController(gateway: gateway ?? DioVenteGateway(Provider.of<ApiService>(ctx, listen: false))),
        child: _VenteView(initialTab: initialTabIndex >= 2 ? 1 : 0, resumeVenteId: resumeVenteId),
      );
}

class _VenteView extends StatefulWidget {
  final int initialTab;
  final String? resumeVenteId;
  const _VenteView({required this.initialTab, this.resumeVenteId});

  @override
  State<_VenteView> createState() => _VenteViewState();
}

class _VenteViewState extends State<_VenteView> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
  final _searchKey = GlobalKey<VenteProductSearchState>();
  final _listKey = GlobalKey<PreventeListState>();
  bool _paying = false;

  VenteController get _ctrl => context.read<VenteController>();

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      if (_tabs.index == 1) _listKey.currentState?.refresh();
      if (_tabs.index == 0) _focusSearch();
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _focusSearch() => _searchKey.currentState?.requestFocus();

  /// Démarrage : vente demandée (ordonnance) ou proposition de reprendre la vente mémorisée.
  Future<void> _start() async {
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
    final resume = await showResumeSaleDialog(context,
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

  /// Prévente choisie dans la liste : confirmation si un autre panier est en cours.
  Future<void> _openFromList(PreventeListItem item) async {
    final c = _ctrl;
    await c.idle();
    if (!mounted) return;
    if (c.hasCart && !c.finished && c.venteId != item.lgPREENREGISTREMENTID) {
      final ok = await confirmVenteAction(
        context,
        title: 'Un panier est en cours',
        message: 'Le panier en cours (${_cartLabel(c)}) n\'est ni encaissé ni enregistré en prévente. '
            'Il ne sera plus affiché (il reste sur le serveur, non encaissé).\n\n'
            'Pour le retrouver dans la liste, annulez puis touchez « Enregistrer en prévente ».\n\n'
            'Ouvrir la prévente ${item.strREF} ?',
        confirm: 'Ouvrir',
      );
      if (!ok || !mounted) return;
    }
    _tabs.animateTo(0);
    await c.loadVente(item.lgPREENREGISTREMENTID);
    if (!mounted) return;
    if (c.cartError != null) showVenteFailure(context, VenteFailed<void>(c.cartError!), onRetry: c.reload);
    _focusSearch();
  }

  Future<void> _newSale() async {
    final c = _ctrl;
    await c.idle();
    if (!mounted) return;
    if (c.hasCart && !c.finished) {
      final ok = await confirmVenteAction(
        context,
        title: 'Nouvelle vente ?',
        message: 'Le panier en cours (${_cartLabel(c)}) n\'est ni encaissé ni enregistré en prévente. '
            'Il ne sera plus affiché (il reste sur le serveur, non encaissé).',
        confirm: 'Nouvelle vente',
      );
      if (!ok || !mounted) return;
    }
    c.reset();
    _tabs.animateTo(0);
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

  Future<void> _savePrevente() async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      final user = await _readyToFinish();
      if (user == null || !mounted) return;
      final c = _ctrl;
      final summary = c.summary, items = c.items, id = c.venteId;
      final r = await c.terminerPrevente();
      if (!mounted) return;
      if (!r.isOk) {
        if (await handleCaisseFermee(context, r)) return;
        if (mounted) showVenteFailure(context, r, onRetry: _savePrevente);
        return;
      }
      await _afterFinish(prevente: true, venteId: id, summary: summary, items: items, user: user);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _encaisser() async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      final user = await _readyToFinish();
      if (user == null || !mounted) return;
      final c = _ctrl;
      final mr = await c.paymentMethods();
      if (!mounted) return;
      if (mr is! VenteOk<List<PaymentMethod>>) {
        showVenteFailure(context, mr, onRetry: _encaisser);
        return;
      }
      final allowed = Provider.of<SettingsProvider>(context, listen: false).enabledPaymentMethodIds;
      final methods = mr.value.where((m) => allowed.contains(m.id)).toList();
      final method = await showPaymentMethodPicker(context, methods);
      if (method == null || !mounted) return;

      final changes = c.changes, summary = c.summary, items = c.items, id = c.venteId;
      int? recu, remis;
      if (method.id == '1') {
        final cash = await showCashDialog(context, montantNet: summary.montantNet);
        if (cash == null || !mounted) return;
        recu = cash.verse;
        remis = cash.monnaie;
      }
      final ok = await showPaymentConfirmDialog(context,
          methodName: method.name, montantNet: summary.montantNet, qrCode: c.qrFor(method.id)?.qrCode);
      if (!ok || !mounted) return;

      final r = await c.encaisser(method: method, userId: user.userId, expectedChanges: changes, montantRecu: recu, montantRemis: remis);
      if (!mounted) return;
      switch (r) {
        case VenteOk(:final value):
          await _afterFinish(
            prevente: false,
            venteId: id,
            summary: summary,
            items: items,
            user: user,
            method: method,
            montantVerse: recu,
            monnaie: remis,
            dejaCloturee: value.dejaCloturee,
          );
        default:
          if (await handleCaisseFermee(context, r)) return;
          if (mounted) showVenteFailure(context, r, onRetry: _encaisser);
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _afterFinish({
    required bool prevente,
    required String? venteId,
    required SaleSummary summary,
    required List<SaleItemDetail> items,
    required User user,
    PaymentMethod? method,
    int? montantVerse,
    int? monnaie,
    bool dejaCloturee = false,
  }) async {
    final print = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(prevente ? 'Prévente enregistrée' : (dejaCloturee ? 'Vente déjà clôturée' : 'Vente encaissée')),
        content: Text(dejaCloturee
            ? 'Le serveur indique que cette vente est déjà clôturée (aucune seconde clôture).\nVoulez-vous imprimer le ticket ?'
            : 'Voulez-vous imprimer le ticket ?'),
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
      } else if (prevente) {
        await ReceiptService().printPreventeTicket(
          context: context,
          officine: officine,
          saleSummary: summary,
          currentUser: user,
          isTestMode: settings.isTestPrintMode,
          paperWidth: settings.paperWidth,
          ticketCodeType: settings.ticketCodeType,
        );
      } else if (method != null) {
        await ReceiptService().printSaleTicket(
          context: context,
          officine: officine,
          saleSummary: summary,
          items: items,
          paymentMethod: method,
          currentUser: user,
          isTestMode: settings.isTestPrintMode,
          paperWidth: settings.paperWidth,
          showQrCode: settings.showQrCodeOnSaleTicket,
          ticketCodeType: settings.ticketCodeType,
          montantVerse: montantVerse,
          monnaie: monnaie,
        );
      }
    }
    if (!mounted) return;
    _refreshHome(venteId);
    _ctrl.reset();
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
    return PopScope(
      canPop: !c.busy && (!c.hasCart || c.finished),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Pré-vente / Vente'),
            if (c.venteId != null)
              Text(
                '${ref.isEmpty ? 'Vente en cours' : 'Réf. $ref'} · ${_cartLabel(c)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                overflow: TextOverflow.ellipsis,
              ),
          ]),
          actions: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(0, 44)),
              onPressed: _paying ? null : _newSale,
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle'),
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.orange,
            indicatorWeight: 3,
            tabs: const [
              Tab(height: 48, child: _TabLabel(Icons.point_of_sale, 'VENTE')),
              Tab(height: 48, child: _TabLabel(Icons.list_alt, 'PRÉVENTES')),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _saleTab(c),
            PreventeList(key: _listKey, onOpen: _openFromList),
          ],
        ),
      ),
    );
  }

  Widget _saleTab(VenteController c) {
    final search = VenteProductSearch(
      key: _searchKey,
      search: c.search,
      pageSearch: c.searchPage,
      visible: c.visibleProduct,
      addProduct: _addProduct,
      enabled: !_paying && !c.finished,
    );
    final banners = [
      if (c.cartError != null && c.items.isNotEmpty)
        LoadErrorBanner(message: 'Panier non relu : ${venteMessage(c.cartError)} (dernier état affiché).', onRetry: c.busy ? null : c.reload),
      if (c.netError != null && c.cartError == null && c.hasCart)
        LoadErrorBanner(message: 'Net à payer non calculé : ${venteMessage(c.netError)}', onRetry: c.busy ? null : c.reload),
    ];
    if (MediaQuery.of(context).size.width > 800) {
      return Row(children: [
        Expanded(
          flex: 4,
          child: Column(children: [
            search,
            ...banners,
            const Expanded(child: Center(child: Text('Recherchez un produit'))),
            _footer(c),
          ]),
        ),
        const VerticalDivider(width: 1),
        Expanded(flex: 6, child: VenteCart(onDone: _focusSearch)),
      ]);
    }
    return Column(children: [
      search,
      ...banners,
      const Divider(height: 1),
      Expanded(child: VenteCart(onDone: _focusSearch)),
      _footer(c),
    ]);
  }

  Widget _footer(VenteController c) {
    final s = c.summary;
    final reason = c.hasCart && !c.finished ? c.finishBlockedReason : null;
    final enabled = c.canFinish && !_paying && !c.finished;
    final netText = !c.hasCart
        ? '0'
        : c.netUpToDate
            ? Constants.formatNumber(s.montantNet)
            : (c.busy ? 'Calcul…' : '—');
    return Material(
      elevation: 6,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Total : ${Constants.formatNumber(c.hasCart ? s.montant : 0)}'),
                  Text('Net : $netText',
                      key: const ValueKey('vente-net'),
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                ]),
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
                  key: const ValueKey('vente-enregistrer-prevente'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor: Colors.orange.shade800,
                    side: BorderSide(color: enabled ? Colors.orange.shade700 : Colors.grey.shade300, width: 1.5),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: enabled ? _savePrevente : null,
                  icon: const Icon(Icons.save, size: 20),
                  label: const Text('Enregistrer en prévente', textAlign: TextAlign.center, maxLines: 2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  key: const ValueKey('vente-encaisser'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: enabled ? _encaisser : null,
                  icon: const Icon(Icons.check_circle, size: 20),
                  label: const Text('Encaisser', maxLines: 1),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TabLabel(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 20),
        const SizedBox(width: 6),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
      ]);
}
