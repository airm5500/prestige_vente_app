// lib/ventes/carnet/vente_carnet_screen.dart
// Vente Carnet — nouvelle version, présentations A / B / C (menu « Présentation » mémorisé).
// Parcours : Client → Bon & ayant droit → Produits → Valider (barre d'étapes, retour possible),
// pied Total / Part carnet / Part client, « PRÉVENTE » ou « VALIDER » (clôture carnet sans dialogue
// de paiement, comme l'original). Vente en cours mémorisée : « Reprendre la vente ? » à la réouverture.
// La logique (file d'opérations, réponses perdues, net à jour, reprise) reste dans CarnetController.
// Hors ligne (H2) : prévente PROVISOIRE (HL-0007) mise dans la file d'envoi, ticket « PROVISOIRE ».
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_controller.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_frame.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_history.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_products.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_steps.dart';
import 'package:prestige_vente_app/ventes/common/vente_dialogs.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/common/vente_product_search.dart';
import 'package:prestige_vente_app/ventes/core/pending_sale_store.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

class VenteCarnetScreen extends StatelessWidget {
  /// Accès serveur (simulé dans les tests).
  final VenteGateway? gateway;

  /// Présentation (A, B, C) ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;

  const VenteCarnetScreen({super.key, this.gateway, this.presentation});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<CarnetController>(
        create: (ctx) => CarnetController(
          gateway: gateway ?? DioVenteGateway(Provider.of<ApiService>(ctx, listen: false)),
          userId: Provider.of<AuthProvider>(ctx, listen: false).user?.userId ?? '',
        ),
        child: _CarnetView(presentation: presentation),
      );
}

class _CarnetView extends StatefulWidget {
  final ListPresentation? presentation;
  const _CarnetView({this.presentation});

  @override
  State<_CarnetView> createState() => _CarnetViewState();
}

class _CarnetViewState extends State<_CarnetView> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  final _searchKey = GlobalKey<VenteProductSearchState>();
  bool _paying = false;

  /// Ajouts restés sans réponse du serveur (affichés en ambre, bloquent la validation).
  final List<CarnetUnsavedLine> _unsaved = [];
  bool _retrying = false;

  CarnetController get _ctrl => context.read<CarnetController>();

  /// Surveillance du serveur (proposition « Terminer hors ligne »).
  late final ServerMonitor _monitor = HorsLigne.instance.monitor;

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _monitor.addListener(_onMonitor);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _monitor.removeListener(_onMonitor);
    super.dispose();
  }

  void _onMonitor() {
    if (mounted) setState(() {});
  }

  Future<void> _terminerHorsLigne() async {
    final r = await _ctrl.passerHorsLigne();
    if (!mounted) return;
    if (!r.isOk) {
      showVenteFailure(context, r);
      return;
    }
    showVenteSnack(context, 'Vente continuée hors ligne (${_ctrl.panierHorsLigne?.label ?? ''}) : seuls les nouveaux articles seront envoyés.');
    _focusSearch();
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  /// Nouvelle vente / autre client : les lignes non enregistrées de l'ancienne vente sont oubliées.
  void _clearUnsaved() {
    if (_unsaved.isEmpty) return;
    setState(_unsaved.clear);
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
    // Hors ligne : la vente mémorisée sera proposée au retour du serveur.
    if (CarnetController.serveurHorsLigne) return;
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
    _clearUnsaved();
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
    _clearUnsaved();
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
    if (!mounted) return;
    _clearUnsaved();
    _ctrl.startNew();
  }

  // ---------------------------------------------------------------------------
  // Panier
  // ---------------------------------------------------------------------------

  static int _qtyIn(List<SaleItemDetail> items, String produitId) =>
      items.where((i) => i.lgFAMILLEID == produitId).fold(0, (s, i) => s + i.intQUANTITY);

  Future<bool> _addProduct(ProductSearchResult product, int qty) async {
    final c = _ctrl;
    final r = await c.addProduct(product, qty);
    if (!mounted) return false;
    if (r.isOk) {
      // Ajout confirmé du même produit : la base de comparaison des lignes en attente suit.
      for (final u in _unsaved.where((u) => u.product.lgFAMILLEID == product.lgFAMILLEID)) {
        u.baseQty += qty;
      }
      return true;
    }
    if (await handleCaisseFermee(context, r)) return false;
    if (!mounted) return false;
    showVenteFailure(context, r);
    // Panne sans réponse : la ligne reste visible en ambre (« Réessayer »). Jamais quand la vente a pu
    // être créée sans réponse (uncertain) : un nouvel essai créerait une seconde vente.
    if (r is VenteFailed && !r.uncertain && !c.finished && c.client != null) {
      setState(() => _unsaved.add(CarnetUnsavedLine(product: product, qty: qty, baseQty: _qtyIn(c.items, product.lgFAMILLEID))));
    }
    return false;
  }

  /// « Réessayer » une ligne non enregistrée : relecture du panier d'abord, jamais de doublon.
  Future<bool> _retryUnsaved(CarnetUnsavedLine u) async {
    final c = _ctrl;
    await c.idle();
    if (!mounted || !_unsaved.contains(u)) return false;
    if (c.venteId != null) {
      await c.reload();
      if (!mounted || !_unsaved.contains(u)) return false;
      if (c.cartError != null) {
        showVenteFailure(context, VenteFailed<void>(c.cartError!), onRetry: () => _retryUnsaved(u));
        return false;
      }
      if (_qtyIn(c.items, u.product.lgFAMILLEID) >= u.baseQty + u.qty) {
        setState(() => _unsaved.remove(u));
        showVenteSnack(context, '${u.product.strNAME} était déjà enregistré : aucun doublon.');
        return true;
      }
    }
    setState(() => _unsaved.remove(u));
    return _addProduct(u.product, u.qty);
  }

  Future<void> _retry(CarnetUnsavedLine u) async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await _retryUnsaved(u);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
    _focusSearch();
  }

  Future<void> _retryAll() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      for (final u in List.of(_unsaved)) {
        if (!mounted || !await _retryUnsaved(u)) break;
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
    _focusSearch();
  }

  Future<void> _dropUnsaved(CarnetUnsavedLine u) async {
    final ok = await confirmVenteAction(
      context,
      title: 'Retirer la ligne ?',
      message: '${u.product.strNAME} (${u.qty}) n\'a pas été enregistré sur le serveur. Le retirer de l\'écran ?',
      confirm: 'Retirer',
    );
    if (ok && mounted) setState(() => _unsaved.remove(u));
    _focusSearch();
  }

  // ---------------------------------------------------------------------------
  // Fin de vente
  // ---------------------------------------------------------------------------

  Future<User?> _readyToFinish() async {
    final c = _ctrl;
    await c.idle();
    if (!mounted) return null;
    final reason = unsavedReason(_unsaved) ?? c.finishBlockedReason;
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
      final hl = c.panierHorsLigne;
      if (hl != null) {
        // Hors ligne : prévente provisoire dans la file des ventes hors ligne.
        final r = await c.enregistrerHorsLigne(userName: user.fullName, expectedChanges: c.changes);
        if (!mounted) return;
        if (!r.isOk) {
          showVenteFailure(context, r);
          return;
        }
        await _afterFinish(prevente: true, snap: snap, user: user, provisoire: hl.label);
        return;
      }
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
    String? provisoire,
  }) async {
    final print = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(provisoire != null
            ? 'Prévente carnet provisoire enregistrée'
            : prevente
                ? 'Prévente carnet enregistrée'
                : (dejaCloturee ? 'Vente déjà clôturée' : 'Vente carnet validée')),
        content: Text(provisoire != null
            ? 'La prévente $provisoire est enregistrée sur l\'appareil. Elle sera envoyée au serveur à son retour '
                '(Ventes hors ligne).\nVoulez-vous imprimer le ticket provisoire ?'
            : dejaCloturee
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
          numberOfCopies: 1, // prévente : un seul ticket
          provisoire: provisoire,
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
    _clearUnsaved();
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

  /// Barre d'étapes : Client → Bon & ayant droit → Produits → Valider (retour possible).
  CarnetFrame _frame(CarnetController c) {
    final step = switch (c.step) { CarnetStep.clientSearch => 0, CarnetStep.bonAndAyantDroit => 1, CarnetStep.productSearch => 2 };
    final active = _paying ? 3 : step;
    final cl = c.client;
    final bons = [for (final tp in c.activeTps) c.bons[tp.compteTp] ?? ''].where((b) => b.isNotEmpty).join(' · ');
    final n = c.items.length;
    final free = !_paying && !c.busy && !c.finished;
    return CarnetFrame(
      style: style,
      active: active,
      steps: [
        (
          title: 'Client',
          short: 'Client',
          detail: cl == null ? 'rechercher' : carnetName(cl.fullName, cl.strFIRSTNAME, cl.strLASTNAME),
          onTap: step > 0 && free ? _changeClient : null,
        ),
        (title: 'Bon & ayant droit', short: 'Bon', detail: bons.isEmpty ? 'ayant droit' : bons, onTap: step > 1 && free ? c.goToBonStep : null),
        (title: 'Produits', short: 'Produits', detail: n == 0 ? 'scanner' : '$n article${n > 1 ? 's' : ''}', onTap: null),
        (title: 'Valider', short: 'Valider', detail: 'part client', onTap: null),
      ],
      actions: (col) => [
        if (c.step != CarnetStep.clientSearch)
          IconButton(icon: Icon(Icons.history, color: col), tooltip: 'Historique', onPressed: _paying ? null : _openHistory),
        PresentationMenuButton(value: style, onChanged: _setStyle, color: col),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CarnetController>();
    final frame = _frame(c);
    final Widget body = switch (c.step) {
      CarnetStep.clientSearch => CarnetClientStep(frame: frame, onHistory: _openHistory),
      CarnetStep.bonAndAyantDroit => CarnetBonStep(frame: frame, onChangeClient: _changeClient),
      CarnetStep.productSearch => CarnetProductsStep(
          frame: frame,
          searchKey: _searchKey,
          addProduct: _addProduct,
          onPrevente: _prevente,
          onValider: _valider,
          paying: _paying,
          unsaved: _unsaved,
          retrying: _retrying,
          onRetry: _retry,
          onRetryAll: _retryAll,
          onDrop: _dropUnsaved,
          onTerminerHorsLigne: _terminerHorsLigne,
        ),
    };
    return PopScope(
      canPop: !c.busy && !_paying && (c.client == null || c.finished),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: KeyedSubtree(key: ValueKey(c.step), child: body),
    );
  }
}
