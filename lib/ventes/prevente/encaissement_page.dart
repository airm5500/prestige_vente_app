// lib/ventes/prevente/encaissement_page.dart
// Encaissement sur UNE page (remplace mode → espèces → confirmation) : total en grand, tuiles des modes
// activés dans les Réglages, espèces (montant reçu, touches rapides, monnaie), QR du mode mobile money,
// « Imprimer le ticket » coché. Mêmes appels serveur et même ordre que l'enchaînement précédent
// (modes de règlement, puis VenteController.encaisser). Erreurs affichées sur la page.
// Réutilisée par la Pré-vente Assurance via [EncaissementActions] (part client, ses propres appels).
// « + Ajouter un mode » : paiement en 2 modes (somme = net exactement, une seule clôture) ; sans ce
// bouton, la page reste exactement le paiement en un seul mode.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/settings_screen.dart';
import 'package:prestige_vente_app/services/receipt_service.dart' show TicketReglement;
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/paiement_multiple.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart' show maxReglements;
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

/// Encaissement confirmé par le serveur ; [copies] = 0 : pas d'impression.
/// [reglements] : détail du paiement en plusieurs modes (vide pour un seul mode).
typedef EncaissementDone = ({
  PaymentMethod method,
  int? recu,
  int? remis,
  bool dejaCloturee,
  int copies,
  List<ReglementLigne> reglements,
});

/// Détail par mode pour le ticket (null = un seul mode : ticket d'origine).
List<TicketReglement>? ticketReglementsOf(EncaissementDone d) => d.reglements.length < 2
    ? null
    : [
        for (final l in d.reglements)
          (mode: l.method.name, montant: l.montant, recu: l.especes ? l.recu : null, rendu: l.especes ? l.monnaie : null),
      ];

/// Monnaie rendue au-delà de laquelle le montant est refusé (erreur de scan), comme avant.
const int maxMonnaie = maxMonnaieRendue;
const int _maxCopies = 9;

/// Appels de l'encaissement fournis par un autre menu (ex. Assurance) ; mêmes règles d'affichage.
class EncaissementActions {
  final Future<VenteResult<List<PaymentMethod>>> Function() paymentMethods;
  final Future<void> Function() loadQrMethods;
  final PaymentMethodQr? Function(String methodId) qrFor;

  /// Clôture avec le mode choisi (montants reçu / rendu pour les espèces).
  final Future<VenteResult<ClotureOk>> Function(PaymentMethod method, int? recu, int? remis) encaisser;

  /// Clôture en plusieurs modes (montant reçu total / monnaie) ; null : un seul mode possible.
  final Future<VenteResult<ClotureOk>> Function(List<ReglementLigne> lignes, int recu, int remis)? encaisserReglements;

  /// Échec après lequel la page se ferme (le menu affiche lui-même le message).
  final bool Function(VenteResult<ClotureOk> result)? leaveOn;

  const EncaissementActions({
    required this.paymentMethods,
    required this.loadQrMethods,
    required this.qrFor,
    required this.encaisser,
    this.encaisserReglements,
    this.leaveOn,
  });
}

class EncaissementPage extends StatefulWidget {
  /// Vente de la Pré-vente (ou [actions] pour un autre menu).
  final VenteController? controller;
  final String userId;

  /// Numéro de modification du panier vérifié (le panier ne doit pas changer entre-temps).
  final int expectedChanges;
  final SaleSummary summary;
  final int itemCount;
  final ListPresentation? presentation;

  /// Ouverture des Réglages (remplaçable dans les tests).
  final Future<void> Function(BuildContext context)? openSettings;

  /// Appels d'un autre menu (remplacent ceux de [controller]).
  final EncaissementActions? actions;

  /// Copies proposées (sinon le réglage « Nombre de tickets »).
  final int? initialCopies;

  /// Libellé du montant (« Total à payer » par défaut).
  final String totalLabel;

  /// Étapes du menu affichées en haut dans les trois présentations (remplacent la barre d'étapes C).
  final Widget Function(bool onDark)? stepsHeader;

  const EncaissementPage({
    super.key,
    this.controller,
    this.userId = '',
    required this.expectedChanges,
    required this.summary,
    required this.itemCount,
    this.presentation,
    this.openSettings,
    this.actions,
    this.initialCopies,
    this.totalLabel = 'Total à payer',
    this.stepsHeader,
  }) : assert(controller != null || actions != null);

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

  /// Paiement en plusieurs modes (null = un seul mode, comportement d'origine).
  PaiementMultiple? _multi;
  final Map<String, TextEditingController> _parts = {};
  final Map<String, TextEditingController> _recus = {};

  /// Dernier montant corrigé (mode, message).
  ({String id, String text})? _correction;

  int get _net => widget.summary.montantNet;

  /// Appels : ceux du menu appelant, sinon ceux de la Pré-vente.
  late final EncaissementActions _actions = widget.actions ?? _preventeActions(widget.controller!);

  EncaissementActions _preventeActions(VenteController c) => EncaissementActions(
        paymentMethods: c.paymentMethods,
        loadQrMethods: c.loadQrMethods,
        qrFor: c.qrFor,
        encaisser: (method, recu, remis) => c.encaisser(
          method: method,
          userId: widget.userId,
          expectedChanges: widget.expectedChanges,
          montantRecu: recu,
          montantRemis: remis,
        ),
        encaisserReglements: (lignes, recu, remis) => c.encaisserReglements(
          lignes: lignes,
          userId: widget.userId,
          expectedChanges: widget.expectedChanges,
          montantRecu: recu,
          montantRemis: remis,
        ),
      );

  @override
  void initState() {
    super.initState();
    loadPresentation();
    final initial = widget.initialCopies;
    if (initial != null) {
      _copies = initial.clamp(1, _maxCopies);
    } else {
      try {
        _copies = Provider.of<SettingsProvider>(context, listen: false).numberOfTickets.clamp(1, _maxCopies);
      } catch (_) {}
    }
    _loadMethods();
  }

  @override
  void dispose() {
    _cash.dispose();
    for (final c in [..._parts.values, ..._recus.values]) {
      c.dispose();
    }
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
    final a = _actions;
    final r = await a.paymentMethods();
    await a.loadQrMethods();
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
    await _submit(
      () => _actions.encaisser(method, recu, remis),
      (deja) => (method: method, recu: recu, remis: remis, dejaCloturee: deja, copies: _print ? _copies : 0, reglements: const []),
    );
  }

  /// Paiement en plusieurs modes : une seule clôture avec la liste des règlements.
  Future<void> _validateMulti() async {
    final p = _multi, call = _actions.encaisserReglements;
    if (_busy || p == null || call == null || !p.valide) return;
    final lignes = p.lignes, recu = p.montantRecu, remis = p.monnaie, principal = p.principal.method;
    await _submit(
      () => call(lignes, recu, remis),
      (deja) => (method: principal, recu: recu, remis: remis, dejaCloturee: deja, copies: _print ? _copies : 0, reglements: lignes),
    );
  }

  Future<void> _submit(Future<VenteResult<ClotureOk>> Function() call, EncaissementDone Function(bool dejaCloturee) done) async {
    if (_busy) return;
    final retry = _failure?.panne ?? false;
    setState(() {
      _busy = true;
      _retrying = retry;
      _failure = null;
    });
    final r = await call();
    if (!mounted) return;
    if (r case VenteOk(:final value)) {
      Navigator.of(context).pop(done(value.dejaCloturee));
      return;
    }
    if (_actions.leaveOn?.call(r) ?? false) {
      Navigator.of(context).pop();
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

  // --- Plusieurs modes ----------------------------------------------------------
  bool get _multiPossible => _actions.encaisserReglements != null;

  TextEditingController _partCtl(String id) => _parts.putIfAbsent(id, TextEditingController.new);
  TextEditingController _recuCtl(String id) => _recus.putIfAbsent(id, TextEditingController.new);

  /// Recopie les parts du modèle dans les champs (sauf celui en cours de saisie).
  void _syncParts({String? except}) {
    final p = _multi;
    if (p == null) return;
    for (final l in p.lignes) {
      if (l.method.id == except) continue;
      final c = _partCtl(l.method.id);
      final want = l.montant == 0 ? '' : '${l.montant}';
      if (c.text != want) c.text = want;
    }
  }

  /// Modes pouvant être ajoutés (activés et pas encore utilisés).
  List<PaymentMethod> _candidates(List<PaymentMethod> methods, Set<String> used) => methods.where((m) => !used.contains(m.id)).toList();

  Future<PaymentMethod?> _pickMode(List<PaymentMethod> candidates) => showModalBottomSheet<PaymentMethod>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('Ajouter un mode de paiement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Pal.ink)),
            ),
            for (final m in candidates)
              ListTile(
                key: ValueKey('ajout-mode-${m.id}'),
                leading: Icon(_iconFor(m), color: Pal.navy),
                title: Text(m.name),
                onTap: () => Navigator.of(ctx).pop(m),
              ),
          ]),
        ),
      );

  /// « + Ajouter un mode » : passe au paiement en plusieurs modes (le nouveau mode reçoit le reste).
  Future<void> _addMode(List<PaymentMethod> methods, PaymentMethod? current) async {
    if (_busy) return;
    final p = _multi;
    final used = p == null ? {if (current != null) current.id} : {for (final l in p.lignes) l.method.id};
    final candidates = _candidates(methods, used);
    if (candidates.isEmpty || (p == null && current == null) || (p != null && !p.peutAjouter)) return;
    final m = candidates.length == 1 ? candidates.first : await _pickMode(candidates);
    if (m == null || !mounted || _busy) return;
    setState(() {
      final multi = p ?? PaiementMultiple(_net, current!, max: maxReglements);
      final err = multi.ajouter(m);
      if (err != null) {
        _correction = (id: m.id, text: err);
        return;
      }
      _multi = multi;
      _recuCtl(m.id).clear();
      if (p == null) _recuCtl(current!.id).clear();
      _correction = null;
      _syncParts();
      if (_failure?.caisse != true) _failure = null;
    });
  }

  /// Retour au paiement en un seul mode (comportement d'origine) avec [m].
  void _leaveMulti(PaymentMethod m) {
    _multi = null;
    _selected = m;
    _correction = null;
    _cash.clear();
  }

  void _setPart(int i, String text) {
    final p = _multi;
    if (p == null || i >= p.lignes.length) return;
    final id = p.lignes[i].method.id;
    final msg = p.modifier(i, int.tryParse(text.trim()) ?? 0);
    setState(() {
      _correction = msg == null ? null : (id: id, text: msg);
      if (msg != null) {
        final c = _partCtl(id);
        c.text = '${p.lignes[i].montant}';
        c.selection = TextSelection.collapsed(offset: c.text.length);
      }
      _syncParts(except: id);
    });
  }

  void _removeLine(int i) {
    final p = _multi;
    if (_busy || p == null) return;
    setState(() {
      p.retirer(i);
      if (p.lignes.length < 2) {
        _leaveMulti(p.lignes.first.method);
      } else {
        _correction = null;
        _syncParts();
      }
    });
  }

  void _toutEn(PaymentMethod m) {
    if (_busy || _multi == null) return;
    setState(() => _leaveMulti(m));
  }

  void _moitie() {
    final p = _multi;
    if (_busy || p == null) return;
    setState(() {
      p.moitie();
      _correction = null;
      _syncParts();
    });
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
    final top = widget.stepsHeader;

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
        steps: top != null
            ? null
            : const StepsBar(active: 2, steps: [
                (title: 'Panier', detail: 'produits', onTap: null),
                (title: 'Vérifier', detail: 'total', onTap: null),
                (title: 'Encaisser', detail: 'paiement', onTap: null),
              ]),
        header: [
          if (top != null) top(true),
          Column(children: [
            Text(widget.totalLabel, style: const TextStyle(fontSize: 13, color: Pal.headerMuted)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(totalText,
                  key: const ValueKey('encaissement-total'), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ]),
        ],
        compactHeader: [
          if (top != null) top(false),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: Pal.line)),
            child: Row(children: [
              Expanded(child: Text(widget.totalLabel, style: const TextStyle(fontSize: 14, color: Pal.muted))),
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
    final p = _multi;
    if (p != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          if (f != null) ..._failureViews(f),
          _label('Règlements'),
          for (var i = 0; i < p.lignes.length; i++) ...[_line(p, i), const SizedBox(height: 8)],
          _addButton(methods, method),
          const SizedBox(height: 8),
          _shortcuts(p, methods),
          const SizedBox(height: 10),
          _resteRow(p),
          const SizedBox(height: 10),
          _printRow(),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: [
        if (f != null) ..._failureViews(f),
        if (_multiPossible && methods.length > 1)
          // Même hauteur que le titre seul : la page d'origine ne bouge pas.
          SizedBox(
            height: 28,
            child: Row(children: [
              Expanded(child: _label('Mode de paiement')),
              _addLink(methods, method),
            ]),
          )
        else
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

  bool _canAdd(List<PaymentMethod> methods, PaymentMethod? method) {
    final p = _multi;
    final used = p == null ? {if (method != null) method.id} : {for (final l in p.lignes) l.method.id};
    return !_busy && _candidates(methods, used).isNotEmpty && (p == null ? method != null : p.peutAjouter);
  }

  /// Paiement en un seul mode : lien discret « + Ajouter un mode » à côté du titre.
  Widget _addLink(List<PaymentMethod> methods, PaymentMethod? method) => TextButton.icon(
        key: const ValueKey('paiement-ajouter-mode'),
        style: TextButton.styleFrom(
          foregroundColor: Pal.navy,
          minimumSize: const Size(0, 28),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        onPressed: _canAdd(methods, method) ? () => _addMode(methods, method) : null,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Ajouter un mode'),
      );

  Widget _addButton(List<PaymentMethod> methods, PaymentMethod? method) {
    final can = _canAdd(methods, method);
    return OutlinedButton.icon(
      key: const ValueKey('paiement-ajouter-mode'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        foregroundColor: Pal.navy,
        side: BorderSide(color: can ? Pal.navy : Pal.line, style: BorderStyle.solid),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: can ? () => _addMode(methods, method) : null,
      icon: const Icon(Icons.add),
      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Ajouter un mode ($maxReglements maximum)')),
    );
  }

  String _f(int v) => '${Constants.formatNumber(v)} F';

  /// Un mode du paiement multiple : part modifiable, ✕ retirer ; espèces (reçu, monnaie) ou QR + « Reçu ».
  Widget _line(PaiementMultiple p, int i) {
    final l = p.lignes[i];
    final id = l.method.id;
    final last = i == p.lignes.length - 1;
    final corr = _correction?.id == id ? _correction?.text : null;
    final String status;
    if (l.montant <= 0) {
      status = 'Saisissez la part de ce mode';
    } else if (l.especes) {
      status = l.erreur == null ? 'Reçu ${Constants.formatNumber(l.recu ?? 0)} · à rendre ${Constants.formatNumber(l.monnaie)}' : 'Montant reçu à saisir';
    } else {
      status = l.confirme ? '✓ reçu' : 'En attente du paiement…';
    }
    final ok = l.erreur == null;
    return Container(
      key: ValueKey('reglement-$id'),
      padding: const EdgeInsets.fromLTRB(10, 8, 2, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ok ? const Color(0xFF86C79A) : Pal.line, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_iconFor(l.method), color: Pal.navy, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.method.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.ink, fontSize: 15)),
              Text(last ? '$status · reste auto' : status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: ok ? const Color(0xFF14532D) : Pal.muted)),
            ]),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 112,
            child: TextField(
              key: ValueKey('reglement-montant-$id'),
              controller: _partCtl(id),
              enabled: !_busy,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              onChanged: (t) => _setPart(i, t),
              decoration: InputDecoration(
                isDense: true,
                hintText: '0',
                suffixText: 'F',
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          IconButton(
            key: ValueKey('reglement-retirer-$id'),
            tooltip: 'Retirer ce mode',
            onPressed: _busy ? null : () => _removeLine(i),
            icon: const Icon(Icons.close),
          ),
        ]),
        if (corr != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Text('✋ $corr', key: ValueKey('reglement-correction-$id'), style: const TextStyle(color: Color(0xFF9A3412), fontSize: 13)),
          ),
        if (l.montant > 0) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: l.especes ? _cashPart(p, i) : _mobilePart(p, i),
          ),
        ],
      ]),
    );
  }

  /// Espèces : montant reçu (≥ part) et monnaie calculée sur la part espèces seulement.
  Widget _cashPart(PaiementMultiple p, int i) {
    final l = p.lignes[i];
    final id = l.method.id;
    final c = _recuCtl(id);
    final err = l.erreur;
    final showErr = c.text.trim().isNotEmpty && err != null && err.isNotEmpty;
    final rounded = <int>{for (final step in [1000, 5000, 10000]) ((l.montant + step - 1) ~/ step) * step}.where((v) => v > l.montant).take(2);
    Widget chip(String label, int value) {
      final on = l.recu == value;
      return ChoiceChip(
        label: Text(label),
        selected: on,
        showCheckmark: false,
        labelStyle: TextStyle(fontWeight: FontWeight.w600, color: on ? Colors.white : Pal.navy),
        selectedColor: Pal.navy,
        backgroundColor: Colors.white,
        side: BorderSide(color: on ? Pal.navy : const Color(0xFFC5D0DE)),
        onSelected: _busy
            ? null
            : (_) => setState(() {
                  c.text = '$value';
                  c.selection = TextSelection.collapsed(offset: c.text.length);
                  p.setRecu(i, value);
                }),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            key: ValueKey('reglement-recu-montant-$id'),
            controller: c,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            onChanged: (t) => setState(() => p.setRecu(i, int.tryParse(t.trim()))),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Montant reçu (F)',
              errorText: showErr ? err : null,
              errorMaxLines: 2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('À rendre', style: TextStyle(fontSize: 12, color: Pal.muted)),
          Text(_f(l.monnaie),
              key: const ValueKey('reglement-monnaie'),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: err == null ? const Color(0xFF14532D) : Pal.muted)),
        ]),
      ]),
      const SizedBox(height: 4),
      Wrap(spacing: 6, children: [
        chip('Exact', l.montant),
        for (final v in rounded) chip(Constants.formatNumber(v), v),
      ]),
    ]);
  }

  /// Autre mode : QR du mode pour SA part, case « Reçu » obligatoire.
  Widget _mobilePart(PaiementMultiple p, int i) {
    final l = p.lignes[i];
    final id = l.method.id;
    final qr = _actions.qrFor(id)?.qrCode;
    return Column(children: [
      if (qr != null) ...[
        SizedBox(
          key: ValueKey('reglement-qr-$id'),
          width: 120,
          height: 120,
          child: Image.memory(qr, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Center(child: Text('QR illisible'))),
        ),
        const SizedBox(height: 4),
        Text('Faites scanner · ${_f(l.montant)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
      ] else
        Text('Encaissez ${_f(l.montant)} par ${l.method.name}.', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
      InkWell(
        onTap: _busy ? null : () => setState(() => p.setConfirme(i, !l.confirme)),
        child: Row(children: [
          Checkbox(
            key: ValueKey('reglement-recu-$id'),
            value: l.confirme,
            activeColor: Pal.green,
            onChanged: _busy ? null : (v) => setState(() => p.setConfirme(i, v ?? false)),
          ),
          Expanded(child: Text('Reçu : ${_f(l.montant)} par ${l.method.name}', style: const TextStyle(fontSize: 14, color: Pal.ink))),
        ]),
      ),
    ]);
  }

  /// Raccourcis : « Tout en espèces », « Tout en <mode> », « 50 / 50 ».
  Widget _shortcuts(PaiementMultiple p, List<PaymentMethod> methods) {
    final especes = methods.where(estEspeces).firstOrNull;
    final targets = <PaymentMethod>[
      if (especes != null) especes,
      for (final l in p.lignes)
        if (!l.especes) l.method,
    ];
    Widget chip(Key key, String label, VoidCallback onTap) => ActionChip(
          key: key,
          label: Text(label, overflow: TextOverflow.ellipsis),
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: Pal.navy),
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFC5D0DE)),
          onPressed: _busy ? null : onTap,
        );
    return Wrap(spacing: 6, runSpacing: 4, children: [
      for (final m in targets)
        chip(ValueKey('raccourci-tout-${m.id}'), estEspeces(m) ? 'Tout en espèces' : 'Tout en ${m.name}', () => _toutEn(m)),
      if (p.lignes.length == 2) chip(const ValueKey('raccourci-moitie'), '50 / 50', _moitie),
    ]);
  }

  Widget _resteRow(PaiementMultiple p) {
    final zero = p.reste == 0;
    final fg = zero ? const Color(0xFF14532D) : const Color(0xFF7F1D1D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: zero ? const Color(0xFFE6F4EA) : const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(child: Text('Reste à payer', style: TextStyle(color: fg, fontSize: 14))),
        Text('${_f(p.reste)}${zero ? ' ✓' : ''}', key: const ValueKey('paiement-reste'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: fg)),
      ]),
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
    final qr = _actions.qrFor(m.id)?.qrCode;
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
      final p = _multi;
      final cash = method?.id == '1';
      final ready = p != null ? !_busy && p.valide : method != null && !_busy && (!cash || _cashError == null);
      final panne = _failure?.panne ?? false;
      final label = _busy
          ? (_retrying ? 'VÉRIFICATION…' : 'VALIDATION…')
          : panne
              ? 'RÉESSAYER'
              : p != null
                  ? (p.nbRecus < p.lignes.length ? 'EN ATTENTE DES PAIEMENTS (${p.nbRecus}/${p.lignes.length})' : 'VALIDER L\'ENCAISSEMENT')
                  : (method == null || cash ? 'VALIDER L\'ENCAISSEMENT' : 'PAIEMENT REÇU — VALIDER');
      final main = ElevatedButton(
        key: const ValueKey('encaissement-valider'),
        style: guided ? amberButton : navyButton,
        onPressed: !ready
            ? null
            : p != null
                ? _validateMulti
                : () => _validate(method!),
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
