// lib/ventes/prevente/encaissement_page.dart
// Encaissement sur UNE page (remplace mode → espèces → confirmation) : total en grand, tuiles des modes
// activés dans les Réglages, espèces (montant reçu, touches rapides, monnaie), QR du mode mobile money,
// « Imprimer le ticket » coché. Mêmes appels serveur et même ordre que l'enchaînement précédent
// (modes de règlement, puis VenteController.encaisser). Erreurs affichées sur la page.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/settings_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

/// Encaissement confirmé par le serveur ; [copies] = 0 : pas d'impression.
typedef EncaissementDone = ({PaymentMethod method, int? recu, int? remis, bool dejaCloturee, int copies});

/// Monnaie rendue au-delà de laquelle le montant est refusé (erreur de scan), comme avant.
const int maxMonnaie = 500000;
const int _maxCopies = 9;

class EncaissementPage extends StatefulWidget {
  final VenteController controller;
  final String userId;

  /// Numéro de modification du panier vérifié (le panier ne doit pas changer entre-temps).
  final int expectedChanges;
  final SaleSummary summary;
  final int itemCount;
  final ListPresentation? presentation;

  /// Ouverture des Réglages (remplaçable dans les tests).
  final Future<void> Function(BuildContext context)? openSettings;

  const EncaissementPage({
    super.key,
    required this.controller,
    required this.userId,
    required this.expectedChanges,
    required this.summary,
    required this.itemCount,
    this.presentation,
    this.openSettings,
  });

  @override
  State<EncaissementPage> createState() => _EncaissementPageState();
}

/// Échec affiché sur la page.
typedef _Failure = ({String message, bool caisse, bool panne, VenteResult<dynamic> result});

class _EncaissementPageState extends State<EncaissementPage> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  final _cash = TextEditingController();
  List<PaymentMethod>? _methods;
  String? _loadError;
  bool _loading = false;
  PaymentMethod? _selected;
  bool _print = true;
  int _copies = 1;
  bool _busy = false;
  bool _retrying = false;
  _Failure? _failure;

  int get _net => widget.summary.montantNet;

  @override
  void initState() {
    super.initState();
    loadPresentation();
    try {
      _copies = Provider.of<SettingsProvider>(context, listen: false).numberOfTickets.clamp(1, _maxCopies);
    } catch (_) {}
    _loadMethods();
  }

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  List<String> _allowed(BuildContext context) {
    try {
      return context.watch<SettingsProvider>().enabledPaymentMethodIds;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _loadMethods() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final c = widget.controller;
    final r = await c.paymentMethods();
    await c.loadQrMethods();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r case VenteOk(:final value)) {
        _methods = value;
      } else {
        _loadError = venteMessage(r.message);
      }
    });
  }

  /// Modes activés sur l'appareil ; Espèces choisi d'office s'il existe (ou le seul mode).
  List<PaymentMethod> _enabled(List<String> allowed) => (_methods ?? const <PaymentMethod>[]).where((m) => allowed.contains(m.id)).toList();

  PaymentMethod? _current(List<PaymentMethod> methods) {
    final s = _selected;
    if (s != null && methods.any((m) => m.id == s.id)) return s;
    return methods.where((m) => m.id == '1').firstOrNull ?? (methods.length == 1 ? methods.first : null);
  }

  // --- Espèces ---------------------------------------------------------------
  int? get _recu => int.tryParse(_cash.text.trim());

  /// null = montant correct ; sinon message (vide = rien saisi).
  String? get _cashError {
    final t = _cash.text.trim();
    if (t.isEmpty) return '';
    final v = _recu;
    if (v == null) return 'Valeur invalide';
    if (v - _net > maxMonnaie) return 'Montant aberrant (erreur de scan ?)';
    if (v < _net) return 'Montant insuffisant : il manque ${Constants.formatNumber(_net - v)} F';
    return null;
  }

  void _setCash(int v) {
    _cash.text = '$v';
    _cash.selection = TextSelection.collapsed(offset: _cash.text.length);
    setState(() {});
  }

  // --- Validation --------------------------------------------------------------
  Future<void> _validate(PaymentMethod method) async {
    if (_busy) return;
    int? recu, remis;
    if (method.id == '1') {
      if (_cashError != null) return;
      recu = _recu;
      remis = (recu ?? 0) - _net;
    }
    final retry = _failure?.panne ?? false;
    setState(() {
      _busy = true;
      _retrying = retry;
      _failure = null;
    });
    final r = await widget.controller.encaisser(
      method: method,
      userId: widget.userId,
      expectedChanges: widget.expectedChanges,
      montantRecu: recu,
      montantRemis: remis,
    );
    if (!mounted) return;
    if (r case VenteOk(:final value)) {
      final EncaissementDone done = (method: method, recu: recu, remis: remis, dejaCloturee: value.dejaCloturee, copies: _print ? _copies : 0);
      Navigator.of(context).pop(done);
      return;
    }
    final caisse = r is VenteRefused<ClotureOk> && r.caisseFermee;
    setState(() {
      _busy = false;
      _retrying = false;
      _failure = (message: venteMessage(r.message), caisse: caisse, panne: r is VenteFailed, result: r);
    });
    // Caisse fermée : même proposition qu'avant (ouvrir la caisse).
    if (caisse) await handleCaisseFermee(context, r);
  }

  Future<void> _openSettings() async {
    final open = widget.openSettings;
    if (open != null) {
      await open(context);
    } else {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    }
    if (mounted) setState(() {});
  }

  // --- Affichage --------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final methods = _enabled(_allowed(context));
    final method = _methods == null ? null : _current(methods);
    final ref = widget.summary.reference;
    final n = widget.itemCount;
    final subtitle = '${ref.isEmpty ? 'Vente en cours' : ref} · $n article${n > 1 ? 's' : ''}';
    final totalText = '${Constants.formatNumber(_net)} F';

    Widget body;
    if (_methods == null && _loadError != null) {
      body = LoadErrorView(message: 'Modes de règlement non chargés : $_loadError', onRetry: _loadMethods);
    } else if (_methods == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (methods.isEmpty) {
      body = _noMethod();
    } else {
      body = _form(methods, method);
    }

    return PopScope(
      canPop: !_busy,
      child: PresentationScaffold(
        style: style,
        title: 'Encaissement',
        subtitle: subtitle,
        actions: (col) => const [],
        steps: const StepsBar(active: 2, steps: [
          (title: 'Panier', detail: 'produits', onTap: null),
          (title: 'Vérifier', detail: 'total', onTap: null),
          (title: 'Encaisser', detail: 'paiement', onTap: null),
        ]),
        header: [
          Column(children: [
            const Text('Total à payer', style: TextStyle(fontSize: 13, color: Pal.headerMuted)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(totalText,
                  key: const ValueKey('encaissement-total'), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ]),
        ],
        compactHeader: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: Pal.line)),
            child: Row(children: [
              const Expanded(child: Text('Total à payer', style: TextStyle(fontSize: 14, color: Pal.muted))),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(totalText,
                      key: const ValueKey('encaissement-total'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Pal.navy)),
                ),
              ),
            ]),
          ),
        ],
        body: body,
        bottomNavigationBar: _bottom(methods, method),
      ),
    );
  }

  Widget _noMethod() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.payments_outlined, size: 56, color: Colors.orange.shade700),
            const SizedBox(height: 12),
            const Text('Aucun mode de règlement activé', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.ink)),
            const SizedBox(height: 8),
            const Text(
              'Aucun mode de règlement n\'est activé sur cet appareil.\n'
              'Activez-en au moins un dans Réglages › Modes de paiement, puis revenez encaisser.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Pal.muted, height: 1.35),
            ),
          ]),
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Pal.muted, letterSpacing: 0.5)),
      );

  Widget _form(List<PaymentMethod> methods, PaymentMethod? method) {
    final f = _failure;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: [
        if (f != null) ..._failureViews(f),
        _label('Mode de paiement'),
        LayoutBuilder(builder: (context, box) {
          final w = (box.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in methods)
              SizedBox(width: w, child: _tile(m, selected: method?.id == m.id)),
          ]);
        }),
        const SizedBox(height: 14),
        if (method == null)
          const Text('Choisissez le mode de paiement.', style: TextStyle(color: Pal.muted))
        else if (method.id == '1')
          ..._cashViews()
        else
          _otherView(method),
        const SizedBox(height: 10),
        _printRow(),
      ],
    );
  }

  List<Widget> _failureViews(_Failure f) {
    if (f.caisse) {
      return [
        _Notice(
          key: const ValueKey('encaissement-caisse-fermee'),
          error: true,
          icon: Icons.lock_outline,
          text: 'Caisse fermée : ouvrez-la avant de valider.',
          action: 'Ouvrir',
          onAction: _busy ? null : () => handleCaisseFermee(context, f.result),
        ),
        const SizedBox(height: 10),
      ];
    }
    if (f.panne) {
      return [
        const _Notice(icon: Icons.hourglass_bottom, text: 'Pas de réponse du serveur : la vente a été vérifiée.'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Pal.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Vente non encaissée', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Pal.ink)),
            const SizedBox(height: 4),
            Text(f.message, style: const TextStyle(fontSize: 13, color: Pal.muted)),
            const SizedBox(height: 4),
            const Text('Le panier est conservé : réessayer est sans risque de double encaissement.', style: TextStyle(fontSize: 13, color: Pal.muted)),
          ]),
        ),
        const SizedBox(height: 10),
      ];
    }
    return [_Notice(error: true, icon: Icons.error_outline, text: f.message), const SizedBox(height: 10)];
  }

  IconData _iconFor(PaymentMethod m) {
    final n = m.name.toLowerCase();
    if (m.id == '1' || n.contains('esp')) return Icons.payments_outlined;
    if (n.contains('carte') || n.contains('card') || n.contains('tpe') || n.contains('visa')) return Icons.credit_card;
    if (n.contains('ch') && n.contains('que')) return Icons.receipt_long_outlined;
    if (n.contains('wave') || n.contains('orange') || n.contains('mtn') || n.contains('moov') || n.contains('money') || n.contains('momo')) {
      return Icons.phone_android;
    }
    return Icons.account_balance_wallet_outlined;
  }

  Widget _tile(PaymentMethod m, {required bool selected}) => Material(
        color: selected ? const Color(0xFFE3ECF7) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? Pal.navy : Pal.line, width: selected ? 2 : 1.5),
        ),
        child: InkWell(
          key: ValueKey('mode-${m.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: _busy
              ? null
              : () => setState(() {
                    _selected = m;
                    if (_failure?.caisse != true) _failure = null;
                  }),
          child: SizedBox(
            height: 74,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(_iconFor(m), color: selected ? Pal.navy : Pal.muted, size: 24),
                const SizedBox(height: 4),
                Text(m.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: selected ? Pal.navy : Pal.ink)),
              ]),
            ),
          ),
        ),
      );

  List<Widget> _cashViews() {
    final err = _cashError;
    final ok = err == null;
    final monnaie = ok ? (_recu ?? 0) - _net : 0;
    final rounded = <int>{for (final step in [1000, 5000, 10000]) ((_net + step - 1) ~/ step) * step}.where((v) => v > _net).take(3);
    Widget chip(String label, int value) {
      final on = _recu == value;
      return ChoiceChip(
        label: Text(label),
        selected: on,
        showCheckmark: false,
        labelStyle: TextStyle(fontWeight: FontWeight.w600, color: on ? Colors.white : Pal.navy),
        selectedColor: Pal.navy,
        backgroundColor: Colors.white,
        side: BorderSide(color: on ? Pal.navy : const Color(0xFFC5D0DE)),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        onSelected: _busy ? null : (_) => _setCash(value),
      );
    }

    return [
      TextField(
        key: const ValueKey('encaissement-recu'),
        controller: _cash,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Montant reçu (F)',
          prefixIcon: const Icon(Icons.money),
          errorText: err == null || err.isEmpty ? null : err,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Pal.navy, width: 2)),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 0, children: [
        chip('Exact', _net),
        for (final v in rounded) chip(Constants.formatNumber(v), v),
      ]),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: ok ? const Color(0xFFE6F4EA) : const Color(0xFFF1F4F8), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(child: Text('Monnaie à rendre', style: TextStyle(color: ok ? const Color(0xFF14532D) : Pal.muted, fontSize: 14))),
          Text('${Constants.formatNumber(monnaie)} F',
              key: const ValueKey('encaissement-monnaie'),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: ok ? const Color(0xFF14532D) : Pal.muted)),
        ]),
      ),
    ];
  }

  Widget _otherView(PaymentMethod m) {
    final qr = widget.controller.qrFor(m.id)?.qrCode;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Pal.line)),
      child: Column(children: [
        if (qr != null) ...[
          SizedBox(
            key: const ValueKey('encaissement-qr'),
            width: 150,
            height: 150,
            child: Image.memory(qr, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Center(child: Text('QR illisible'))),
          ),
          const SizedBox(height: 8),
          const Text('Faites scanner ce QR au client', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
        ] else
          Text('Encaissez le montant par ${m.name}, puis validez.', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
        const SizedBox(height: 2),
        Text('${m.name} · ${Constants.formatNumber(_net)} F', textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted)),
      ]),
    );
  }

  Widget _printRow() => Container(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.line)),
        child: Row(children: [
          Expanded(
            child: InkWell(
              onTap: _busy ? null : () => setState(() => _print = !_print),
              child: Row(children: [
                Checkbox(
                  key: const ValueKey('encaissement-imprimer'),
                  value: _print,
                  activeColor: Pal.navy,
                  onChanged: _busy ? null : (v) => setState(() => _print = v ?? false),
                ),
                const Flexible(child: Text('Imprimer le ticket', style: TextStyle(fontSize: 14.5, color: Pal.ink))),
              ]),
            ),
          ),
          if (_print) ...[
            IconButton(
              tooltip: 'Moins de copies',
              onPressed: _busy || _copies <= 1 ? null : () => setState(() => _copies--),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$_copies', key: const ValueKey('encaissement-copies'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            IconButton(
              tooltip: 'Plus de copies',
              onPressed: _busy || _copies >= _maxCopies ? null : () => setState(() => _copies++),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ]),
      );

  Widget _bottom(List<PaymentMethod> methods, PaymentMethod? method) {
    final guided = style == ListPresentation.guided;
    final back = OutlinedButton(
      style: outlineButton,
      onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
      child: const Text('RETOUR'),
    );
    Widget content;
    if (_methods != null && methods.isEmpty) {
      content = Row(children: [
        Expanded(child: back),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            style: navyButton,
            onPressed: _openSettings,
            icon: const Icon(Icons.settings, size: 20),
            label: const FittedBox(fit: BoxFit.scaleDown, child: Text('OUVRIR LES RÉGLAGES')),
          ),
        ),
      ]);
    } else {
      final cash = method?.id == '1';
      final ready = method != null && !_busy && (!cash || _cashError == null);
      final panne = _failure?.panne ?? false;
      final label = _busy
          ? (_retrying ? 'VÉRIFICATION…' : 'VALIDATION…')
          : panne
              ? 'RÉESSAYER'
              : (method == null || cash ? 'VALIDER L\'ENCAISSEMENT' : 'PAIEMENT REÇU — VALIDER');
      final main = ElevatedButton(
        key: const ValueKey('encaissement-valider'),
        style: guided ? amberButton : navyButton,
        onPressed: ready ? () => _validate(method) : null,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_busy) ...[
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4)),
            const SizedBox(width: 10),
          ],
          Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label))),
        ]),
      );
      content = panne ? Row(children: [Expanded(child: back), const SizedBox(width: 8), Expanded(flex: 2, child: main)]) : main;
    }
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: SizedBox(height: 54, width: double.infinity, child: content),
        ),
      ),
    );
  }
}

/// Bandeau d'avertissement (ambre) ou d'erreur (rouge) avec action éventuelle.
class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool error;
  final String? action;
  final VoidCallback? onAction;
  const _Notice({super.key, required this.icon, required this.text, this.error = false, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    final bg = error ? const Color(0xFFFDECEC) : const Color(0xFFFFF4E0);
    final border = error ? const Color(0xFFF5C2C2) : const Color(0xFFF5D08A);
    final fg = error ? const Color(0xFF7F1D1D) : const Color(0xFF7C2D12);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
      child: Row(children: [
        Icon(icon, color: fg, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: fg, fontSize: 13.5))),
        if (action != null)
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(64, 44), foregroundColor: Pal.navy, textStyle: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: onAction,
            child: Text(action!),
          ),
      ]),
    );
  }
}
