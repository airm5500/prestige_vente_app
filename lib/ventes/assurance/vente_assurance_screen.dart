// lib/ventes/assurance/vente_assurance_screen.dart
// Pré-vente Assurance — nouvelle version (copie fiabilisée de lib/screens/assurance_sale).
// Mêmes 3 étapes : Client → Bon & ayant droit → Produits. Le contrôleur appartient à l'écran
// (plus de vente perdue en pleine saisie) ; net recalculé automatiquement ; un seul dialogue
// d'impression avec le nombre de copies ; « Reprendre » / « Réimprimer » depuis l'historique.
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
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_controller.dart';
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
import 'package:provider/provider.dart';

class VenteAssuranceScreen extends StatelessWidget {
  /// Accès serveur (simulé dans les tests).
  final VenteGateway? gateway;
  const VenteAssuranceScreen({super.key, this.gateway});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<AssuranceController>(
        create: (ctx) => AssuranceController(
          gateway: gateway ?? DioVenteGateway(Provider.of<ApiService>(ctx, listen: false)),
          userId: Provider.of<AuthProvider>(ctx, listen: false).user?.userId ?? '',
        ),
        child: const _AssuranceView(),
      );
}

class _AssuranceView extends StatefulWidget {
  const _AssuranceView();

  @override
  State<_AssuranceView> createState() => _AssuranceViewState();
}

class _AssuranceViewState extends State<_AssuranceView> {
  final _produitsKey = GlobalKey<AssuranceStepProduitsState>();
  bool _paying = false;

  AssuranceController get _ctrl => context.read<AssuranceController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
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
    final resume = await showResumeSaleDialog(context,
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
      await _afterFinish(snap, prevente: true);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _valider() async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      if (!await _readyToFinish() || !mounted) return;
      final c = _ctrl;
      final summary = c.summary;
      if (summary == null) return;
      final changes = c.changes;
      PaymentMethod? method;
      int? recu, remis;
      if (summary.montantNet > 0) {
        final mr = await c.paymentMethods();
        if (!mounted) return;
        if (mr is! VenteOk<List<PaymentMethod>>) {
          showVenteFailure(context, mr, onRetry: _valider);
          return;
        }
        final allowed = Provider.of<SettingsProvider>(context, listen: false).enabledPaymentMethodIds;
        method = await showPaymentMethodPicker(context, mr.value.where((m) => allowed.contains(m.id)).toList());
        if (method == null || !mounted) return;
        if (method.id == '1') {
          // Espèces : le dialogue du montant versé vaut confirmation (un dialogue de moins).
          final cash = await showCashDialog(context, montantNet: summary.montantNet);
          if (cash == null || !mounted) return;
          recu = cash.verse;
          remis = cash.monnaie;
        } else {
          final ok = await showPaymentConfirmDialog(context,
              methodName: method.name, montantNet: summary.montantNet, qrCode: c.qrFor(method.id)?.qrCode);
          if (!ok || !mounted) return;
        }
      }
      final snap = _Snapshot.of(c);
      if (snap == null) return;
      final r = await c.cloturer(method: method, expectedChanges: changes, montantRecu: recu, montantRemis: remis);
      if (!mounted) return;
      switch (r) {
        case VenteOk(:final value):
          await _afterFinish(snap, prevente: false, method: method, montantVerse: recu, monnaie: remis, dejaCloturee: value.dejaCloturee);
        default:
          if (await handleCaisseFermee(context, r)) return;
          // Bon déjà utilisé : message affiché à l'étape des bons (retour automatique).
          if (mounted && c.step == AssuranceStep.productSearch) showVenteFailure(context, r, onRetry: _valider);
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  /// Un seul dialogue : résultat + impression avec le nombre de copies (défaut n°21).
  Future<void> _afterFinish(
    _Snapshot s, {
    required bool prevente,
    PaymentMethod? method,
    int? montantVerse,
    int? monnaie,
    bool dejaCloturee = false,
  }) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final copies = await showPrintCopiesDialog(
      context,
      title: prevente ? 'Prévente enregistrée' : (dejaCloturee ? 'Vente déjà clôturée' : 'Vente validée'),
      message: dejaCloturee
          ? 'Le serveur indique que cette vente est déjà clôturée (aucune seconde clôture).'
          : (s.reference.isEmpty ? null : 'Réf. ${s.reference}'),
      initialCopies: settings.numberOfTicketsAssurance,
    );
    if (!mounted) return;
    if (copies > 0) {
      await printAssuranceTicket(
        context,
        prevente: prevente,
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

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------

  Widget _stepBar(AssuranceStep step) {
    Widget item(int n, String label, AssuranceStep s) {
      final active = step == s, done = step.index > s.index;
      final color = active ? AppColors.primary : (done ? Colors.green.shade700 : Colors.grey);
      return Expanded(
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: color,
            child: done ? const Icon(Icons.check, size: 14, color: Colors.white) : Text('$n', style: const TextStyle(fontSize: 12, color: Colors.white)),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: color, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
          ),
        ]),
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(children: [
        item(1, 'Client', AssuranceStep.clientSearch),
        item(2, 'Bons & patient', AssuranceStep.bonAndAyantDroit),
        item(3, 'Produits', AssuranceStep.productSearch),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AssuranceController>();
    final ref = c.reference;
    return PopScope(
      canPop: !c.busy && (c.client == null || c.finished),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Vente Assurance'),
            if (c.venteId != null)
              Text(
                '${ref.isEmpty ? 'Vente en cours' : 'Réf. $ref'} · ${c.items.length} article${c.items.length > 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                overflow: TextOverflow.ellipsis,
              ),
          ]),
          actions: [
            if (c.client != null)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(0, 44)),
                onPressed: _paying ? null : _newSale,
                icon: const Icon(Icons.add),
                label: const Text('Nouvelle'),
              ),
          ],
        ),
        body: Column(children: [
          _stepBar(c.step),
          if (c.busy && c.step != AssuranceStep.productSearch) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: switch (c.step) {
              AssuranceStep.clientSearch => AssuranceStepClient(onHistory: _history),
              AssuranceStep.bonAndAyantDroit => AssuranceStepCouverture(onChangeClient: _changeClient),
              AssuranceStep.productSearch => AssuranceStepProduits(
                  key: _produitsKey,
                  addProduct: _addProduct,
                  onPrevente: _savePrevente,
                  onValider: _valider,
                  paying: _paying,
                ),
            },
          ),
        ]),
      ),
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
