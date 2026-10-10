// lib/ventes/carnet/vente_carnet_screen.dart
// Vente Carnet — nouvelle version (copie fiabilisée de lib/screens/carnet_sale).
// Parcours conservé : Client → Bon & ayant droit → Produits, pied Total / Part carnet / Part client,
// « Enregistrer en prévente » ou « Valider la vente » (clôture carnet sans dialogue de paiement,
// comme l'original). Vente en cours mémorisée : « Reprendre la vente ? » à la réouverture.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_controller.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_history.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_products.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_steps.dart';
import 'package:prestige_vente_app/ventes/common/vente_dialogs.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/common/vente_product_search.dart';
import 'package:prestige_vente_app/ventes/core/pending_sale_store.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:provider/provider.dart';

class VenteCarnetScreen extends StatelessWidget {
  /// Accès serveur (simulé dans les tests).
  final VenteGateway? gateway;

  const VenteCarnetScreen({super.key, this.gateway});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<CarnetController>(
        create: (ctx) => CarnetController(
          gateway: gateway ?? DioVenteGateway(Provider.of<ApiService>(ctx, listen: false)),
          userId: Provider.of<AuthProvider>(ctx, listen: false).user?.userId ?? '',
        ),
        child: const _CarnetView(),
      );
}

class _CarnetView extends StatefulWidget {
  const _CarnetView();

  @override
  State<_CarnetView> createState() => _CarnetViewState();
}

class _CarnetViewState extends State<_CarnetView> {
  final _searchKey = GlobalKey<VenteProductSearchState>();
  bool _paying = false;

  CarnetController get _ctrl => context.read<CarnetController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _focusSearch() => _searchKey.currentState?.requestFocus();

  String _cartLabel(CarnetController c) {
    final n = c.items.length;
    final net = c.summary?.montantNet ?? 0;
    return '$n article${n > 1 ? 's' : ''}${c.netUpToDate && net > 0 ? ' · ${Constants.formatNumber(net)} F' : ''}';
  }

  // ---------------------------------------------------------------------------
  // Reprise
  // ---------------------------------------------------------------------------

  /// Démarrage : proposition de reprendre la vente carnet mémorisée.
  Future<void> _start() async {
    if (!mounted) return;
    final c = _ctrl;
    final pending = await PendingSaleStore.load(VenteMenu.carnet);
    if (pending == null || !mounted) return;
    final restore = CarnetController.restoreFromPending(pending);
    if (restore == null) {
      await PendingSaleStore.clear(VenteMenu.carnet);
      return;
    }
    final closed = await c.isClosedOnServer(pending.venteId);
    if (!mounted) return;
    if (closed == true) {
      await PendingSaleStore.clear(VenteMenu.carnet);
      if (mounted) showVenteSnack(context, 'La vente ${pending.reference} a déjà été clôturée.');
      return;
    }
    final resume =
        await showResumeSaleDialog(context, reference: pending.reference, itemCount: pending.itemCount, total: pending.total, savedAt: pending.savedAt);
    if (!mounted || !resume) return;
    await c.restore(restore);
    if (!mounted) return;
    if (c.cartError != null) showVenteFailure(context, VenteFailed<void>(c.cartError!), onRetry: c.reload);
    _focusSearch();
  }

  /// Une vente non terminée est affichée : confirmation avant de la quitter (elle reste sur le serveur).
  Future<bool> _confirmDropCurrent({required String title, required String confirm}) async {
    final c = _ctrl;
    await c.idle();
    if (!mounted) return false;
    if (!c.hasCart || c.finished) return true;
    return confirmVenteAction(
      context,
      title: title,
      message: 'La vente en cours (${_cartLabel(c)}) n\'est ni validée ni enregistrée en prévente. '
          'Elle ne sera plus affichée (elle reste sur le serveur, non validée).',
      confirm: confirm,
    );
  }

  Future<void> _openHistory() async {
    final item = await showCarnetHistory(context, _ctrl);
    if (item == null || !mounted) return;
    await _resumeFromHistory(item);
  }

  /// « Reprendre la prévente » depuis l'historique du client.
  Future<void> _resumeFromHistory(PreventeListItem item) async {
    final c = _ctrl;
    if (c.venteId == item.lgPREENREGISTREMENTID && !c.finished) return;
    if (!await _confirmDropCurrent(title: 'Une vente est en cours', confirm: 'Reprendre ${item.strREF}')) return;
    if (!mounted) return;
    final r = await c.gateway.fullSale(item.lgPREENREGISTREMENTID);
    if (!mounted) return;
    if (r is! VenteOk<Map<String, dynamic>>) {
      showVenteFailure(context, r, onRetry: () => _resumeFromHistory(item));
      return;
    }
    if (CarnetController.statutOf(r.value) == 'is_Closed') {
      showVenteSnack(context, 'La vente ${item.strREF} est déjà clôturée : réimpression seulement.', error: true);
      return;
    }
    final restore = CarnetController.restoreFromServer(item.lgPREENREGISTREMENTID, r.value);
    if (restore == null) {
      showVenteSnack(context, 'Vente ${item.strREF} illisible (client manquant) : reprise impossible.', error: true);
      return;
    }
    await c.restore(restore);
    if (!mounted) return;
    if (c.cartError != null) showVenteFailure(context, VenteFailed<void>(c.cartError!), onRetry: c.reload);
    _focusSearch();
  }

  Future<void> _changeClient() async {
    final c = _ctrl;
    await c.idle();
    if (!mounted) return;
    if (c.hasCart && !c.finished) {
      if (!await _confirmDropCurrent(title: 'Changer de client ?', confirm: 'Changer de client')) return;
    } else if (c.bons.values.any((b) => b.isNotEmpty)) {
      final ok = await confirmVenteAction(context, title: 'Changer de client ?', message: 'Les N° de bon saisis seront perdus.', confirm: 'Changer de client');
      if (!ok) return;
    }
    if (mounted) _ctrl.startNew();
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

  // ---------------------------------------------------------------------------
  // Fin de vente
  // ---------------------------------------------------------------------------

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

  Future<void> _prevente() async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      final user = await _readyToFinish();
      if (user == null || !mounted) return;
      final c = _ctrl;
      final snap = _snapshot(c);
      if (snap == null) return;
      final r = await c.terminerPrevente(expectedChanges: c.changes);
      if (!mounted) return;
      if (!r.isOk) {
        if (await handleCaisseFermee(context, r)) return;
        if (mounted) showVenteFailure(context, r, onRetry: _prevente);
        return;
      }
      await _afterFinish(prevente: true, snap: snap, user: user);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _valider() async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      final user = await _readyToFinish();
      if (user == null || !mounted) return;
      final c = _ctrl;
      final snap = _snapshot(c);
      if (snap == null) return;
      final r = await c.valider(expectedChanges: c.changes);
      if (!mounted) return;
      switch (r) {
        case VenteOk(:final value):
          await _afterFinish(prevente: false, snap: snap, user: user, dejaCloturee: value.dejaCloturee);
        default:
          if (await handleCaisseFermee(context, r)) return;
          if (mounted) showVenteFailure(context, r, onRetry: c.step == CarnetStep.productSearch ? _valider : null);
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  ({AssuranceSaleSummary summary, List<SaleItemDetail> items, ClientAssurance client, AyantDroit ayantDroit})? _snapshot(CarnetController c) {
    final s = c.summary, cl = c.client, ad = c.ayantDroit;
    if (s == null || cl == null || ad == null) return null;
    return (summary: s, items: List.of(c.items), client: cl, ayantDroit: ad);
  }

  Future<void> _afterFinish({
    required bool prevente,
    required ({AssuranceSaleSummary summary, List<SaleItemDetail> items, ClientAssurance client, AyantDroit ayantDroit}) snap,
    required User user,
    bool dejaCloturee = false,
  }) async {
    final print = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(prevente ? 'Prévente carnet enregistrée' : (dejaCloturee ? 'Vente déjà clôturée' : 'Vente carnet validée')),
        content: Text(dejaCloturee
            ? 'Le serveur indique que cette vente est déjà clôturée (aucune seconde clôture).\nVoulez-vous imprimer le ticket ?'
            : 'Voulez-vous imprimer le ticket ?'),
        actions: [
          TextButton(style: TextButton.styleFrom(minimumSize: const Size(64, 44)), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Non')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(88, 44)), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Imprimer')),
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
        await ReceiptService().printAssurancePreventeTicket(
          context: context,
          officine: officine,
          saleSummary: snap.summary,
          items: snap.items,
          client: snap.client,
          ayantDroit: snap.ayantDroit,
          currentUser: user,
          isTestMode: settings.isTestPrintMode,
          paperWidth: settings.paperWidth,
          ticketCodeType: settings.ticketCodeType,
          numberOfCopies: settings.numberOfTicketsAssurance,
        );
      } else {
        await ReceiptService().printAssuranceSaleTicket(
          context: context,
          officine: officine,
          saleSummary: snap.summary,
          items: snap.items,
          client: snap.client,
          ayantDroit: snap.ayantDroit,
          paymentMethod: PaymentMethod(id: '1', name: 'CARNET'),
          currentUser: user,
          isTestMode: settings.isTestPrintMode,
          paperWidth: settings.paperWidth,
          ticketCodeType: settings.ticketCodeType,
          numberOfCopies: settings.numberOfTicketsAssurance,
          showQrCode: settings.showQrCodeOnSaleTicket,
        );
      }
    }
    if (!mounted) return;
    _ctrl.startNew();
  }

  // ---------------------------------------------------------------------------
  // Quitter
  // ---------------------------------------------------------------------------

  Future<void> _confirmLeave() async {
    final c = _ctrl;
    await c.idle();
    if (!mounted) return;
    if (c.client == null || c.finished) {
      Navigator.of(context).pop();
      return;
    }
    final bool leave;
    if (c.hasCart) {
      leave = await confirmVenteAction(
        context,
        title: 'Quitter la vente en cours ?',
        message: 'Cette vente carnet (${_cartLabel(c)}) n\'est ni validée ni enregistrée en prévente.\n\n'
            'Elle est conservée : à la réouverture du menu, « Reprendre la vente ? » vous sera proposé.',
        confirm: 'Quitter',
        cancel: 'Rester',
      );
    } else {
      leave = await confirmVenteAction(
        context,
        title: 'Abandonner la saisie ?',
        message: 'Le client choisi et les N° de bon saisis ne seront pas conservés.',
        confirm: 'Quitter',
        cancel: 'Rester',
      );
    }
    if (leave && mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CarnetController>();
    final ref = c.items.isNotEmpty ? c.items.first.strREF : '';
    final Widget body = switch (c.step) {
      CarnetStep.clientSearch => CarnetClientStep(onHistory: _openHistory),
      CarnetStep.bonAndAyantDroit => CarnetBonStep(onChangeClient: _changeClient),
      CarnetStep.productSearch => CarnetProductsStep(
          searchKey: _searchKey,
          addProduct: _addProduct,
          onPrevente: _prevente,
          onValider: _valider,
          paying: _paying,
        ),
    };
    return PopScope(
      canPop: !c.busy && !_paying && (c.client == null || c.finished),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Vente Carnet'),
            if (c.venteId != null)
              Text(
                '${ref.isEmpty ? 'Vente en cours' : 'Réf. $ref'} · ${_cartLabel(c)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                overflow: TextOverflow.ellipsis,
              ),
          ]),
          actions: [
            if (c.step != CarnetStep.clientSearch)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(0, 44)),
                onPressed: _paying ? null : _openHistory,
                icon: const Icon(Icons.history),
                label: const Text('Historique'),
              ),
          ],
        ),
        body: KeyedSubtree(key: ValueKey(c.step), child: body),
      ),
    );
  }
}
