// lib/ventes/assurance/vente_assurance_screen.dart
// Pré-vente Assurance — nouvelle version, présentations A / B / C (menu « Présentation » mémorisé).
// Étapes Client → Couverture → Produits → Encaisser (retour possible aux étapes précédentes).
// Le contrôleur appartient à l'écran (plus de vente perdue en pleine saisie) ; net recalculé
// automatiquement ; part client > 0 : page d'encaissement unique (comme la Pré-vente) ; part client 0 :
// validation directe après une confirmation simple ; un seul choix d'impression (case + copies) ;
// « Reprendre » / « Réimprimer » depuis l'historique.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_controller.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_frame.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_history.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_print.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_step_client.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_step_couverture.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_step_produits.dart';
import 'package:prestige_vente_app/ventes/common/vente_dialogs.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/pending_sale_store.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/encaissement_page.dart';
import 'package:prestige_vente_app/ventes/prevente/prevente_dialogs.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

class VenteAssuranceScreen extends StatelessWidget {
  /// Accès serveur (simulé dans les tests).
  final VenteGateway? gateway;

  /// Présentation (A, B, C) ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;
  const VenteAssuranceScreen({super.key, this.gateway, this.presentation});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<AssuranceController>(
        create: (ctx) => AssuranceController(
          gateway: gateway ?? DioVenteGateway(Provider.of<ApiService>(ctx, listen: false)),
          userId: Provider.of<AuthProvider>(ctx, listen: false).user?.userId ?? '',
        ),
        child: _AssuranceView(presentation: presentation),
      );
}

class _AssuranceView extends StatefulWidget {
  final ListPresentation? presentation;
  const _AssuranceView({this.presentation});

  @override
  State<_AssuranceView> createState() => _AssuranceViewState();
}

class _AssuranceViewState extends State<_AssuranceView> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  final _produitsKey = GlobalKey<AssuranceStepProduitsState>();
  bool _paying = false;

  AssuranceController get _ctrl => context.read<AssuranceController>();

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

  /// Démarrage : proposition de reprendre la vente mémorisée.
  Future<void> _start() async {
    if (!mounted) return;
    final c = _ctrl;
    unawaited(c.loadQrMethods());
    final pending = await PendingSaleStore.load(VenteMenu.assurance);
    if (pending == null || !mounted) return;
    final closed = await c.isClosedOnServer(pending.venteId);
    if (!mounted) return;
    if (closed == true) {
      await PendingSaleStore.clear(VenteMenu.assurance);
      if (mounted) showVenteSnack(context, 'La vente ${pending.reference} a déjà été clôturée.');
      return;
    }
    final resume = await showReprendreVenteDialog(context,
        reference: pending.reference, itemCount: pending.itemCount, total: pending.total, savedAt: pending.savedAt);
    if (!mounted || !resume) return;
    await _resume(pending.venteId);
  }

  // ---------------------------------------------------------------------------
  // Historique : Reprendre / Réimprimer
  // ---------------------------------------------------------------------------

  String _cartLabel(AssuranceController c) =>
      '${c.client?.fullName ?? ''} · ${c.items.length} article${c.items.length > 1 ? 's' : ''}';

  Future<void> _history() async {
    final c = _ctrl;
    final choice = await showAssuranceHistory(context, c.history);
    if (choice == null || !mounted) return;
    switch (choice.action) {
      case AssuranceHistoryAction.resume:
        await c.idle();
        if (!mounted) return;
        if (c.hasCart && !c.finished && c.venteId != choice.item.lgPREENREGISTREMENTID) {
          final ok = await confirmVenteAction(
            context,
            title: 'Une vente est en cours',
            message: 'La vente en cours (${_cartLabel(c)}) n\'est ni validée ni enregistrée en prévente. '
                'Elle ne sera plus affichée (elle reste sur le serveur, non encaissée).\n\n'
                'Reprendre la vente ${choice.item.strREF} ?',
            confirm: 'Reprendre',
          );
          if (!ok || !mounted) return;
        }
        await _resume(choice.item.lgPREENREGISTREMENTID);
      case AssuranceHistoryAction.reprint:
        await _reprint(choice.item);
    }
  }

  Future<void> _resume(String venteId) async {
    final r = await _ctrl.resumeSale(venteId);
    if (!mounted) return;
    switch (r) {
      case VenteOk(:final value):
        if (value.missing.isNotEmpty) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Informations à compléter'),
              content: Text('La vente a été rechargée, mais ces informations n\'ont pas pu être retrouvées : '
                  '${value.missing.join(', ')}.\n\nComplétez-les avant de continuer.'),
              actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Compléter'))],
            ),
          );
        } else {
          showVenteSnack(context, 'Vente ${_ctrl.reference} reprise.', color: Colors.green.shade700);
        }
        final c = _ctrl;
        if (c.cartError != null && mounted) showVenteFailure(context, VenteFailed<void>(c.cartError!), onRetry: c.reload);
      default:
        showVenteFailure(context, r, onRetry: () => _resume(venteId));
    }
  }

  Future<void> _reprint(PreventeListItem item) async {
    final c = _ctrl;
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    final r = await c.loadForPrint(item);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (r is! VenteOk<({AssuranceSaleData data, List<SaleItemDetail> items})>) {
      showVenteFailure(context, r, onRetry: () => _reprint(item));
      return;
    }
    final data = r.value.data;
    final client = data.client, ad = data.ticketAyantDroit;
    if (client == null || ad == null) {
      showVenteSnack(context, 'Client introuvable dans cette vente : réimpression impossible.', error: true);
      return;
    }
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final copies = await showPrintCopiesDialog(context,
        title: 'Réimprimer ${data.reference}', initialCopies: settings.numberOfTicketsAssurance);
    if (copies < 1 || !mounted) return;
    await printAssuranceTicket(
      context,
      prevente: true,
      copies: copies,
      summary: data.summary,
      items: r.value.items,
      client: client,
      ayantDroit: ad,
      reference: data.reference,
    );
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  Future<void> _changeClient() async {
    final c = _ctrl;
    await c.idle();
    if (!mounted) return;
    final ok = await confirmVenteAction(
      context,
      title: 'Changer de client ?',
      message: c.hasCart && !c.finished
          ? 'La vente en cours (${_cartLabel(c)}) n\'est ni validée ni enregistrée en prévente. '
              'Elle ne sera plus affichée (elle reste sur le serveur ; retrouvez-la dans l\'historique).'
          : 'Les bons et l\'ayant droit saisis seront perdus.',
      confirm: 'Changer de client',
    );
    if (ok && mounted) c.reset();
  }

  Future<void> _newSale() async {
    final c = _ctrl;
    await c.idle();
    if (!mounted) return;
    if (c.client != null && !c.finished) {
      final ok = await confirmVenteAction(
        context,
        title: 'Nouvelle vente ?',
        message: c.hasCart
            ? 'La vente en cours (${_cartLabel(c)}) n\'est ni validée ni enregistrée en prévente. '
                'Elle ne sera plus affichée (elle reste sur le serveur ; retrouvez-la dans l\'historique).'
            : 'La saisie en cours (client, bons) sera perdue.',
        confirm: 'Nouvelle vente',
      );
      if (!ok || !mounted) return;
    }
    c.reset();
  }

  Future<void> _confirmLeave() async {
    final c = _ctrl;
    await c.idle();
    if (!mounted) return;
    if (c.client == null || c.finished) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await confirmVenteAction(
      context,
      title: c.hasCart ? 'Quitter la vente en cours ?' : 'Abandonner la saisie ?',
      message: c.hasCart
          ? 'Cette vente (${_cartLabel(c)}) n\'est ni validée ni enregistrée en prévente.\n\n'
              'Elle est conservée : à la réouverture du menu, « Reprendre la vente ? » vous sera proposé.'
          : 'Le client et les bons saisis seront perdus.',
      confirm: 'Quitter',
      cancel: 'Rester',
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // Panier / fin de vente
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

  /// Contrôles communs avant de terminer (null = message affiché).
  Future<bool> _readyToFinish() async {
    final c = _ctrl;
    await c.idle();
    if (!mounted) return false;
    final reason = c.finishBlockedReason;
    if (reason != null) {
      showVenteSnack(context, reason, error: true);
      return false;
    }
    return true;
  }

  Future<void> _savePrevente() async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      if (!await _readyToFinish() || !mounted) return;
      final c = _ctrl;
      final snap = _Snapshot.of(c);
      if (snap == null) return;
      final r = await c.terminerPrevente(expectedChanges: c.changes);
      if (!mounted) return;
      if (!r.isOk) {
        if (await handleCaisseFermee(context, r)) return;
        if (mounted) showVenteFailure(context, r, onRetry: _savePrevente);
        return;
      }
      await _afterPrevente(snap);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  /// Part client > 0 : page d'encaissement (modes de règlement puis clôture, comme avant) ;
  /// part client 0 : confirmation simple puis validation directe (ESPECES, comme avant).
  Future<void> _valider() async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      if (!await _readyToFinish() || !mounted) return;
      final c = _ctrl;
      final summary = c.summary;
      if (summary == null) return;
      final changes = c.changes;
      final snap = _Snapshot.of(c);
      if (snap == null) return;
      final copiesDefault = Provider.of<SettingsProvider>(context, listen: false).numberOfTicketsAssurance;
      if (summary.montantNet <= 0) {
        final copies = await showValidationZeroDialog(context, reference: snap.reference, initialCopies: copiesDefault);
        if (copies == null || !mounted) return;
        final r = await c.cloturer(expectedChanges: changes);
        if (!mounted) return;
        switch (r) {
          case VenteOk(:final value):
            await _afterValidation(snap, copies: copies, dejaCloturee: value.dejaCloturee);
          default:
            if (await handleCaisseFermee(context, r)) return;
            // Bon déjà utilisé : message affiché à l'étape Couverture (retour automatique).
            if (mounted && c.step == AssuranceStep.productSearch) showVenteFailure(context, r, onRetry: _valider);
        }
        return;
      }
      final done = await Navigator.of(context).push<EncaissementDone>(MaterialPageRoute(
        builder: (_) => EncaissementPage(
          actions: EncaissementActions(
            paymentMethods: c.paymentMethods,
            loadQrMethods: c.loadQrMethods,
            qrFor: c.qrFor,
            encaisser: (method, recu, remis) => c.cloturer(method: method, expectedChanges: changes, montantRecu: recu, montantRemis: remis),
            // Bon déjà utilisé : retour à l'étape Couverture, où le message du serveur est affiché.
            leaveOn: (_) => c.step != AssuranceStep.productSearch,
          ),
          expectedChanges: changes,
          summary: SaleSummary(montant: summary.montant, montantNet: summary.montantNet, reference: snap.reference, venteId: c.venteId ?? ''),
          itemCount: snap.items.length,
          presentation: style,
          initialCopies: copiesDefault,
          totalLabel: 'Part client à payer',
          stepsHeader: (onDark) => AssuranceStepsBar(active: 3, onDark: onDark),
        ),
      ));
      if (done == null || !mounted) return;
      await _afterValidation(snap,
          copies: done.copies, dejaCloturee: done.dejaCloturee, method: done.method, montantVerse: done.recu, monnaie: done.remis);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  /// Vente validée : message, impression choisie avant la validation (copies), nouvelle vente.
  Future<void> _afterValidation(
    _Snapshot s, {
    required int copies,
    required bool dejaCloturee,
    PaymentMethod? method,
    int? montantVerse,
    int? monnaie,
  }) async {
    final ref = s.reference.isEmpty ? '' : ' (${s.reference})';
    showVenteSnack(
      context,
      dejaCloturee ? 'Vente déjà clôturée sur le serveur$ref : aucune seconde clôture.' : 'Vente validée ✓$ref',
      color: Colors.green.shade700,
    );
    if (copies > 0) {
      await printAssuranceTicket(
        context,
        prevente: false,
        copies: copies,
        summary: s.summary,
        items: s.items,
        client: s.client,
        ayantDroit: s.ayantDroit,
        reference: s.reference,
        method: method,
        montantVerse: montantVerse,
        monnaie: monnaie,
      );
    }
    if (!mounted) return;
    try {
      unawaited(Provider.of<SaleProvider>(context, listen: false).fetchPreventes());
    } catch (_) {}
    _ctrl.reset();
  }

  /// Prévente enregistrée : un seul dialogue (résultat + impression avec le nombre de copies, défaut n°21).
  Future<void> _afterPrevente(_Snapshot s) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final copies = await showPrintCopiesDialog(
      context,
      title: 'Prévente enregistrée',
      message: s.reference.isEmpty ? null : 'Réf. ${s.reference}',
      initialCopies: settings.numberOfTicketsAssurance,
    );
    if (!mounted) return;
    if (copies > 0) {
      await printAssuranceTicket(
        context,
        prevente: true,
        copies: copies,
        summary: s.summary,
        items: s.items,
        client: s.client,
        ayantDroit: s.ayantDroit,
        reference: s.reference,
      );
    }
    if (!mounted) return;
    try {
      unawaited(Provider.of<SaleProvider>(context, listen: false).fetchPreventes());
    } catch (_) {}
    _ctrl.reset();
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------

  /// Retour par la barre d'étapes : Client (changer de client, confirmé) ; Couverture depuis Produits.
  VoidCallback? _stepTap(AssuranceController c, int index) {
    if (_paying || c.finished) return null;
    if (index == 0 && c.step != AssuranceStep.clientSearch) return _changeClient;
    if (index == 1 && c.step == AssuranceStep.productSearch) return c.returnToCouverture;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AssuranceController>();
    final frame = AssuranceFrame(
      style: style,
      progress: c.busy && c.step != AssuranceStep.productSearch,
      stepTap: (i) => _stepTap(c, i),
      actions: (col) => [
        if (c.client != null)
          IconButton(
            icon: Icon(Icons.add_circle_outline, color: col),
            tooltip: 'Nouvelle vente',
            onPressed: _paying ? null : _newSale,
          ),
        PresentationMenuButton(value: style, onChanged: _setStyle, color: col),
      ],
    );
    return PopScope(
      canPop: !c.busy && (c.client == null || c.finished),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: switch (c.step) {
        AssuranceStep.clientSearch => AssuranceStepClient(frame: frame, onHistory: _history),
        AssuranceStep.bonAndAyantDroit => AssuranceStepCouverture(frame: frame, onChangeClient: _changeClient),
        AssuranceStep.productSearch => AssuranceStepProduits(
            key: _produitsKey,
            frame: frame,
            addProduct: _addProduct,
            onPrevente: _savePrevente,
            onValider: _valider,
            paying: _paying,
          ),
      },
    );
  }
}

/// État de la vente au moment de la terminer (pour le ticket, après remise à zéro).
class _Snapshot {
  final AssuranceSaleSummary summary;
  final List<SaleItemDetail> items;
  final ClientAssurance client;
  final AyantDroit ayantDroit;
  final String reference;
  const _Snapshot(this.summary, this.items, this.client, this.ayantDroit, this.reference);

  static _Snapshot? of(AssuranceController c) {
    final ref = c.reference;
    final s = c.summary, client = c.client, ad = c.ayantDroit;
    if (s == null || client == null || ad == null) return null;
    return _Snapshot(
      AssuranceSaleSummary(
        montant: s.montant,
        remise: s.remise,
        montantNet: s.montantNet,
        montantTp: s.montantTp,
        marge: s.marge,
        tierspayants: s.tierspayants,
        reference: ref,
        venteId: c.venteId ?? '',
      ),
      List.of(c.items),
      client,
      ad,
      ref,
    );
  }
}
