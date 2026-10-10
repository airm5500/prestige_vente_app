// lib/screens/reception_bl/reception_home_screen.dart
// Réception BL : bons à entrer en stock, et commandes (en cours / passées) à transformer en BL.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_bl_screen.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_summary_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

class ReceptionHomeScreen extends StatefulWidget {
  /// Remplaçables pour les tests.
  final ReceptionGateway? gateway;
  final ReceptionSettings? settings;
  final Future<bool> Function(BuildContext)? adminCheck;
  final CodeCamera? codeCamera;
  final LabelCamera? labelCamera;
  final DateTime Function()? clock;

  /// Présentation imposée (tests) ; sinon celle choisie sur l'appareil (A par défaut).
  final ListPresentation? presentation;

  const ReceptionHomeScreen({
    super.key,
    this.gateway,
    this.settings,
    this.adminCheck,
    this.codeCamera,
    this.labelCamera,
    this.clock,
    this.presentation,
  });

  @override
  State<ReceptionHomeScreen> createState() => _ReceptionHomeScreenState();
}

class _ReceptionHomeScreenState extends State<ReceptionHomeScreen> with SingleTickerProviderStateMixin {
  // Onglet 0 : commandes (point de départ) ; onglet 1 : BL à entrer en stock.
  late final TabController _tabs = TabController(length: 2, vsync: this);
  String? _justCreated;

  static final _money = NumberFormat.decimalPattern('fr_FR');

  late final ReceptionGateway _gateway =
      widget.gateway ?? DioReceptionGateway(DioClient.getClient(context.read<SettingsProvider>().baseUrl));
  ReceptionSettings _settings = const ReceptionSettings();
  List<ReceptionBl> _bls = [];
  List<ReceptionOrder> _orders = [];
  bool _loading = true;
  String? _error;
  String _filter = '';
  String? _grossiste;
  late ListPresentation _style = widget.presentation ?? ListPresentation.dashboard;

  /// Lignes de chaque BL à entrer (avancement de la saisie).
  Map<String, List<ReceptionLine>> _blLines = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _settings = widget.settings ?? await ReceptionSettings.load();
    if (widget.presentation == null) {
      final style = await PresentationPrefs.load();
      if (mounted) setState(() => _style = style);
    }
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
    await _load();
  }

  void _setStyle(ListPresentation p) {
    setState(() => _style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  DateTime get _now => (widget.clock ?? DateTime.now)();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bls = await _gateway.bls();
      final orders = await _gateway.orders();
      // Avancement de chaque BL (une lecture par BL, en parallèle).
      final lines = <String, List<ReceptionLine>>{};
      await Future.wait(bls.take(40).map((b) async {
        try {
          lines[b.id] = await _gateway.lines(b.id);
        } catch (_) {}
      }));
      if (!mounted) return;
      setState(() {
        _bls = bls;
        _orders = orders;
        _blLines = lines;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Liste non chargée. Vérifiez la connexion au serveur.';
        });
      }
    }
  }

  bool _match(String s) => _filter.isEmpty || s.toLowerCase().contains(_filter.toLowerCase());

  Future<void> _openBl(ReceptionBl bl) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReceptionBlScreen(
        bl: bl,
        gateway: _gateway,
        settings: _settings,
        codeCamera: widget.codeCamera,
        labelCamera: widget.labelCamera,
        clock: widget.clock,
      ),
    ));
    if (mounted) _load();
  }

  Future<void> _createBl(ReceptionOrder order) async {
    ReceptionResult? result;
    String? ref;
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _CreateBlScreen(
        order: order,
        today: (widget.clock ?? DateTime.now)(),
        onCreate: (input) async {
          final r = await _gateway.createBl(orderId: order.id, ref: input.ref, date: input.date, amountHt: input.ht, tva: input.tva);
          result = r;
          ref = input.ref;
          return r;
        },
      ),
    ));
    if (created != true || !mounted) return;
    final data = result?.data['data'];
    final missing = data is List ? data.map((e) => '$e').toList() : const <String>[];
    if (missing.isNotEmpty) {
      await _info(
        'BL créé avec réserves',
        '${missing.length} produit(s) sans stock à votre emplacement n\'ont pas été repris dans le BL :\n${missing.join(', ')}',
      );
    }
    await _load();
    if (!mounted) return;
    // Le BL créé apparaît dans l'onglet « BL à entrer », mis en évidence.
    setState(() => _justCreated = ref);
    _tabs.animateTo(1);
    Constants.showSnackBar(context, 'BL $ref créé : touchez-le pour commencer la saisie.');
  }

  Future<void> _info(String title, String message, {bool error = false}) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: error ? const Icon(Icons.error_outline, color: Colors.red, size: 40) : null,
          title: Text(title),
          content: Text(message),
          actions: [ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );

  Future<void> _editSettings() async {
    if (!await (widget.adminCheck ?? PinCodeDialog.show)(context) || !mounted) return;
    var draft = _settings;
    final saved = await showDialog<ReceptionSettings>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Réglages de la réception'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Péremption courte en dessous de :'),
              Wrap(spacing: 6, children: [
                for (final m in const [3, 6, 9, 12])
                  ChoiceChip(
                    label: Text('$m mois'),
                    selected: draft.shortExpiryMonths == m,
                    onSelected: (_) => setLocal(() => draft = draft.copyWith(shortExpiryMonths: m)),
                  ),
              ]),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Valider l\'entrée en stock sur ce terminal'),
                subtitle: const Text('Le droit « Entrée en stock » de l\'utilisateur est aussi vérifié par Prestige.'),
                value: draft.terminalValidation,
                onChanged: (v) => setLocal(() => draft = draft.copyWith(terminalValidation: v)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(draft), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (saved == null) return;
    if (widget.settings == null) await saved.save();
    if (mounted) setState(() => _settings = saved);
  }

  Future<void> _openSummary(ReceptionBl bl) async {
    final lines = _blLines[bl.id];
    if (lines == null) return _openBl(bl);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReceptionSummaryScreen(bl: bl, gateway: _gateway, settings: _settings, lines: lines, clock: widget.clock),
    ));
    if (mounted) _load();
  }

  // ---------------------------------------------------------------------------
  // Données affichées
  // ---------------------------------------------------------------------------
  List<ReceptionOrder> get _visibleOrders => _orders
      .where((o) => _match('${o.ref} ${o.grossiste}') && (_grossiste == null || o.grossiste == _grossiste))
      .toList();
  List<ReceptionBl> get _visibleBls => _bls
      .where((b) => _match('${b.ref} ${b.grossiste} ${b.orderRef}') && (_grossiste == null || b.grossiste == _grossiste))
      .toList();

  ReceptionSummary? _summaryOf(ReceptionBl b) {
    final l = _blLines[b.id];
    return l == null ? null : ReceptionSummary.of(l, now: _now, shortExpiryMonths: _settings.shortExpiryMonths);
  }

  int get _linesToEnter => _bls.fold(0, (s, b) {
        final sum = _summaryOf(b);
        return s + (sum == null ? b.lines : sum.lines.length - sum.complete.length);
      });

  StatusBadge _blBadge(ReceptionBl b, ReceptionSummary? s) {
    if (b.ref == _justCreated) return StatusBadge.nouveau();
    if (s == null || s.enteredBoxes == 0) return StatusBadge.aCommencer();
    if (s.complete.length == s.lines.length) return StatusBadge.pret();
    return StatusBadge.enSaisie();
  }

  static String _longDate(DateTime d) {
    try {
      final t = DateFormat('EEEE d MMMM', 'fr_FR').format(d);
      return t[0].toUpperCase() + t.substring(1);
    } catch (_) {
      return DateFormat('dd/MM/yyyy').format(d);
    }
  }

  String _shortDate(String d) => d.length >= 5 ? d.substring(0, 5) : d;

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) => switch (_style) {
        ListPresentation.dashboard => _buildDashboard(),
        ListPresentation.compact => _buildCompact(),
        ListPresentation.guided => _buildGuided(),
      };

  List<Widget> _headerActions(Color color) => [
        PresentationMenuButton(value: _style, onChanged: _setStyle, color: color),
        IconButton(icon: Icon(Icons.tune, color: color), tooltip: 'Réglages', onPressed: _editSettings),
        IconButton(icon: Icon(Icons.refresh, color: color), tooltip: 'Actualiser', onPressed: _load),
      ];

  Widget _searchField({Color fill = Colors.white}) => TextField(
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: 'N° de BL, commande ou grossiste',
          filled: true,
          fillColor: fill,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        onChanged: (v) => setState(() => _filter = v.trim()),
      );

  Widget _grossisteChips() {
    final names = {for (final o in _orders) o.grossiste, for (final b in _bls) b.grossiste}.where((g) => g.isNotEmpty).toList()..sort();
    if (names.length < 2) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(label: const Text('Tous'), selected: _grossiste == null, onSelected: (_) => setState(() => _grossiste = null)),
        ),
        for (final g in names)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(label: Text(g), selected: _grossiste == g, onSelected: (_) => setState(() => _grossiste = _grossiste == g ? null : g)),
          ),
      ]),
    );
  }

  Widget _status() => Column(children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [Text(_error!, textAlign: TextAlign.center), TextButton(onPressed: _load, child: const Text('Réessayer'))]),
          ),
      ]);

  Widget _empty(String text) => ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Text(text, textAlign: TextAlign.center))]);

  static const _noOrder = 'Aucune commande en cours ou passée.';
  static const _noBl = 'Aucun BL à entrer en stock.\nCréez-le depuis les commandes.';

  // --- A · Tableau de bord ------------------------------------------------------
  Widget _buildDashboard() {
    final orders = _visibleOrders, bls = _visibleBls;
    return Scaffold(
      backgroundColor: Pal.page,
      body: Column(children: [
        NavyHeader(
          title: 'Réception BL',
          subtitle: _longDate(_now),
          actions: _headerActions(Colors.white),
          children: [
            Row(children: [
              Expanded(child: KpiTile('${_orders.length}', 'commandes')),
              const SizedBox(width: 8),
              Expanded(child: KpiTile('${_bls.length}', 'BL à entrer')),
              const SizedBox(width: 8),
              Expanded(child: KpiTile('$_linesToEnter', 'lignes à saisir', highlight: true)),
            ]),
            SegmentedPills(
              labels: ['Commandes · ${_orders.length}', 'BL à entrer · ${_bls.length}'],
              selected: _tabs.index,
              onSelected: (i) => setState(() => _tabs.animateTo(i)),
            ),
          ],
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 6), child: _searchField()),
        _grossisteChips(),
        _status(),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            RefreshIndicator(
              onRefresh: _load,
              child: orders.isEmpty && !_loading
                  ? _empty(_noOrder)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _orderCardA(orders[i]),
                    ),
            ),
            RefreshIndicator(
              onRefresh: _load,
              child: bls.isEmpty && !_loading
                  ? _empty(_noBl)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: bls.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _blCardA(bls[i]),
                    ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _orderCardA(ReceptionOrder o) => SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            GrossisteAvatar(o.grossiste),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.grossiste, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Pal.ink)),
                Text('Cde ${o.ref} · ${_shortDate(o.date)}', style: const TextStyle(fontSize: 13, color: Pal.muted)),
              ]),
            ),
            o.passed ? StatusBadge.passee() : StatusBadge.enCours(),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Figure('${o.products}', o.products > 1 ? 'produits' : 'produit'),
            const SizedBox(width: 18),
            Figure(_money.format(o.amount), 'F HT'),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: ElevatedButton(style: navyButton, onPressed: () => _createBl(o), child: const Text('Créer le BL')),
          ),
        ]),
      );

  Widget _blCardA(ReceptionBl b) {
    final s = _summaryOf(b);
    final started = s != null && s.enteredBoxes > 0;
    return SoftCard(
      highlighted: b.ref == _justCreated,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          GrossisteAvatar(b.grossiste),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('BL ${b.ref}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Pal.ink)),
              Text('${b.grossiste}${b.orderRef.isEmpty ? '' : ' · Cde ${b.orderRef}'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
            ]),
          ),
          _blBadge(b, s),
        ]),
        const SizedBox(height: 12),
        ThinProgress(
          value: s == null || s.lines.isEmpty ? 0 : s.complete.length / s.lines.length,
          left: s == null ? '${b.lines} ligne(s)' : '${s.complete.length} / ${s.lines.length} lignes saisies',
          right: s == null ? '${b.boxes} boîtes' : '${s.enteredBoxes} / ${s.orderedBoxes} boîtes',
          color: s != null && s.complete.length == s.lines.length ? Pal.green : Pal.blue,
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                style: navyButton,
                icon: const Icon(Icons.qr_code_scanner, size: 20),
                label: Text(started ? 'Continuer' : 'Commencer la saisie'),
                onPressed: () => _openBl(b),
              ),
            ),
          ),
          if (started) ...[
            const SizedBox(width: 8),
            Expanded(child: SizedBox(height: 44, child: OutlinedButton(style: outlineButton, onPressed: () => _openSummary(b), child: const Text('Bilan')))),
          ],
        ]),
      ]),
    );
  }

  // --- B · Liste groupée --------------------------------------------------------
  Widget _buildCompact() {
    final orders = _visibleOrders, bls = _visibleBls;
    final total = orders.fold<int>(0, (s, o) => s + o.amount);
    Widget tab(String label, int count, bool on) => Tab(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(color: on ? Pal.navy : Pal.line, borderRadius: BorderRadius.circular(999)),
              child: Text('$count', style: TextStyle(fontSize: 12, color: on ? Colors.white : Pal.ink)),
            ),
          ]),
        );
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Pal.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Réception BL', style: TextStyle(fontWeight: FontWeight.bold, color: Pal.navy)),
        actions: _headerActions(Pal.navy),
        bottom: TabBar(
          controller: _tabs,
          labelColor: Pal.navy,
          unselectedLabelColor: const Color(0xFF4A5A70),
          indicatorColor: Pal.navy,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          tabs: [tab('Commandes', _orders.length, _tabs.index == 0), tab('BL à entrer', _bls.length, _tabs.index == 1)],
        ),
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: _searchField(fill: Pal.page)),
        _grossisteChips(),
        _status(),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            RefreshIndicator(
              onRefresh: _load,
              child: orders.isEmpty && !_loading ? _empty(_noOrder) : ListView(children: _groupedOrdersB(orders)),
            ),
            RefreshIndicator(
              onRefresh: _load,
              child: bls.isEmpty && !_loading ? _empty(_noBl) : ListView(children: [for (final b in bls) _blRowB(b)]),
            ),
          ]),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(color: Color(0xFFF8FAFC), border: Border(top: BorderSide(color: Pal.line))),
          child: SafeArea(
            top: false,
            child: Row(children: [
              Expanded(
                child: Text(
                  _tabs.index == 0
                      ? '${orders.length} commande(s) · ${{for (final o in orders) o.grossiste}.length} grossiste(s)'
                      : '${bls.length} BL · $_linesToEnter ligne(s) à saisir',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF4A5A70)),
                ),
              ),
              if (_tabs.index == 0) Text('Total ${_money.format(total)} F HT', style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
            ]),
          ),
        ),
      ]),
    );
  }

  List<Widget> _groupedOrdersB(List<ReceptionOrder> orders) {
    final groups = <String, List<ReceptionOrder>>{};
    for (final o in orders) {
      groups.putIfAbsent(o.grossiste, () => []).add(o);
    }
    return [
      for (final e in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            Expanded(child: Text(e.key.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: Color(0xFF4A5A70)))),
            Text('${e.value.length} CDE · ${_money.format(e.value.fold<int>(0, (s, o) => s + o.amount))} F',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4A5A70))),
          ]),
        ),
        for (final o in e.value)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.ref, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
                  Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: Pal.muted), children: [
                    TextSpan(text: '${_shortDate(o.date)} · ${o.products} produit(s) · '),
                    TextSpan(
                      text: o.statutLabel,
                      style: TextStyle(fontWeight: FontWeight.w500, color: o.passed ? const Color(0xFF1F4F8F) : const Color(0xFF8A5300)),
                    ),
                  ])),
                ]),
              ),
              Text('${_money.format(o.amount)} F', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
              const SizedBox(width: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Pal.navy,
                  side: const BorderSide(color: Pal.navy),
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _createBl(o),
                child: const Text('Créer BL'),
              ),
            ]),
          ),
      ],
    ];
  }

  Widget _blRowB(ReceptionBl b) {
    final s = _summaryOf(b);
    final isNew = b.ref == _justCreated;
    return InkWell(
      onTap: () => _openBl(b),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isNew ? const Color(0xFFF2FBF5) : null,
          border: const Border(bottom: BorderSide(color: Color(0xFFEEF1F5))),
        ),
        child: Row(children: [
          RingProgress(done: s?.complete.length ?? 0, total: s?.lines.length ?? b.lines),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text('BL ${b.ref}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink))),
                if (isNew) ...[const SizedBox(width: 8), StatusBadge.nouveau()],
              ]),
              Text(
                [
                  b.grossiste,
                  s == null ? '${b.boxes} boîtes' : '${s.enteredBoxes} / ${s.orderedBoxes} boîtes',
                  if (s != null && s.shortExpiries.isNotEmpty) '${s.shortExpiries.length} péremption(s) courte(s)',
                ].join(' · '),
                style: const TextStyle(fontSize: 13, color: Pal.muted),
              ),
            ]),
          ),
          const Icon(Icons.chevron_right, color: Pal.muted),
        ]),
      ),
    );
  }

  // --- C · Parcours guidé -------------------------------------------------------
  Widget _buildGuided() {
    final orders = _visibleOrders, bls = _visibleBls;
    final ready = _bls.where((b) {
      final s = _summaryOf(b);
      return s != null && s.lines.isNotEmpty && s.complete.length == s.lines.length;
    }).length;
    return Scaffold(
      backgroundColor: const Color(0xFFEEF2F7),
      body: Column(children: [
        NavyHeader(
          title: 'Réception BL',
          rounded: false,
          actions: _headerActions(Colors.white),
          children: [
            StepsBar(active: _tabs.index, steps: [
              (title: 'Commandes', detail: '${_orders.length} à recevoir', onTap: () => setState(() => _tabs.animateTo(0))),
              (title: 'Saisie BL', detail: '${_bls.length} en cours', onTap: () => setState(() => _tabs.animateTo(1))),
              (title: 'Stock', detail: ready == 0 ? 'validation' : '$ready prêt(s)', onTap: null),
            ]),
          ],
        ),
        _status(),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
                _searchField(),
                const SizedBox(height: 10),
                const Text('Choisissez la commande livrée, puis saisissez le n° du BL.', style: TextStyle(fontSize: 13, color: Color(0xFF4A5A70))),
                const SizedBox(height: 12),
                if (orders.isEmpty && !_loading) const Padding(padding: EdgeInsets.all(24), child: Text(_noOrder, textAlign: TextAlign.center)),
                for (var i = 0; i < orders.length; i++) ...[
                  i == 0 ? _orderFeaturedC(orders[i]) : _orderCompactC(orders[i]),
                  const SizedBox(height: 12),
                ],
              ]),
            ),
            RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
                if (bls.isEmpty && !_loading) const Padding(padding: EdgeInsets.all(24), child: Text(_noBl, textAlign: TextAlign.center)),
                for (var i = 0; i < bls.length; i++) ...[
                  i == 0 ? _blFeaturedC(bls[i]) : _blCompactC(bls[i]),
                  const SizedBox(height: 12),
                ],
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Color _band(String grossiste) => GrossisteAvatar.colorsFor(grossiste).$2;

  Widget _metricBox(String value, String label, {Color bg = Pal.page, Color fg = Pal.ink}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: fg)),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF4A5A70))),
        ]),
      );

  Widget _orderFeaturedC(ReceptionOrder o) => SoftCard(
        band: _band(o.grossiste),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.grossiste, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.ink)),
                Text('Commande ${o.ref} · ${_shortDate(o.date)}', style: const TextStyle(fontSize: 13, color: Pal.muted)),
              ]),
            ),
            o.passed ? StatusBadge.passee() : StatusBadge.enCours(),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _metricBox('${o.products}', o.products > 1 ? 'produits' : 'produit')),
            const SizedBox(width: 10),
            Expanded(child: _metricBox('${_money.format(o.amount)} F', 'montant HT')),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              style: amberButton,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Recevoir cette livraison', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              onPressed: () => _createBl(o),
            ),
          ),
        ]),
      );

  Widget _orderCompactC(ReceptionOrder o) => SoftCard(
        band: _band(o.grossiste),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.grossiste, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Pal.ink)),
              Text('${o.ref} · ${o.products} produit(s) · ${_money.format(o.amount)} F', style: const TextStyle(fontSize: 13, color: Pal.muted)),
            ]),
          ),
          IconButton.filled(
            tooltip: 'Recevoir la livraison ${o.grossiste}',
            style: IconButton.styleFrom(backgroundColor: Pal.navy, foregroundColor: Colors.white, minimumSize: const Size(44, 44)),
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => _createBl(o),
          ),
        ]),
      );

  Widget _blFeaturedC(ReceptionBl b) {
    final s = _summaryOf(b);
    return SoftCard(
      band: _band(b.grossiste),
      highlighted: b.ref == _justCreated,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('BL ${b.ref}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.ink)),
              Text('${b.grossiste}${b.orderRef.isEmpty ? '' : ' · Commande ${b.orderRef}'}', style: const TextStyle(fontSize: 13, color: Pal.muted)),
            ]),
          ),
          _blBadge(b, s),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _metricBox('${s?.complete.length ?? 0}', 'complète(s)', bg: const Color(0xFFEAF7EF), fg: const Color(0xFF0B6B45))),
          const SizedBox(width: 8),
          Expanded(child: _metricBox('${s?.partial.length ?? 0}', 'incomplète(s)', bg: const Color(0xFFFFF4E0), fg: const Color(0xFF8A5300))),
          const SizedBox(width: 8),
          Expanded(child: _metricBox('${s?.notEntered.length ?? b.lines}', 'à saisir')),
        ]),
        if (s != null && s.shortExpiries.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFFFFF8EA), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.warning_amber, size: 18, color: Color(0xFF8A5300)),
              const SizedBox(width: 8),
              Text('${s.shortExpiries.length} péremption(s) courte(s)', style: const TextStyle(fontSize: 13, color: Color(0xFF8A5300))),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            style: navyButton,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(s != null && s.enteredBoxes > 0 ? 'Continuer le scan' : 'Commencer le scan', style: const TextStyle(fontSize: 16)),
            onPressed: () => _openBl(b),
          ),
        ),
      ]),
    );
  }

  Widget _blCompactC(ReceptionBl b) {
    final s = _summaryOf(b);
    return SoftCard(
      band: _band(b.grossiste),
      highlighted: b.ref == _justCreated,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('BL ${b.ref}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Pal.ink)),
            Text('${b.grossiste} · ${s == null ? b.lines : '${s.complete.length}/${s.lines.length}'} ligne(s)', style: const TextStyle(fontSize: 13, color: Pal.muted)),
          ]),
        ),
        ElevatedButton(
          style: amberButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 44))),
          onPressed: () => _openBl(b),
          child: Text(s != null && s.enteredBoxes > 0 ? 'Continuer' : 'Commencer'),
        ),
      ]),
    );
  }
}

typedef _BlInput = ({String ref, DateTime date, int ht, int tva});

/// Création d'un BL depuis une commande : page entière, champs espacés, date au calendrier.
/// En cas de refus (n° déjà utilisé…), le message s'affiche ici et la saisie est conservée.
class _CreateBlScreen extends StatefulWidget {
  final ReceptionOrder order;
  final DateTime today;
  final Future<ReceptionResult> Function(_BlInput input) onCreate;
  const _CreateBlScreen({required this.order, required this.today, required this.onCreate});

  @override
  State<_CreateBlScreen> createState() => _CreateBlScreenState();
}

class _CreateBlScreenState extends State<_CreateBlScreen> {
  static final _fmt = DateFormat('dd/MM/yyyy');
  static final _money = NumberFormat.decimalPattern('fr_FR');
  final _form = GlobalKey<FormState>();
  final _ref = TextEditingController();
  late final _ht = TextEditingController(text: '${widget.order.amount}');
  final _tva = TextEditingController(text: '0');
  late DateTime _date = DateTime(widget.today.year, widget.today.month, widget.today.day);
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ht.addListener(() => setState(() {}));
    _tva.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_ref, _ht, _tva]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _date.subtract(const Duration(days: 365)),
      lastDate: widget.today.add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await widget.onCreate((
      ref: _ref.text.trim(),
      date: _date,
      ht: int.parse(_ht.text.trim()),
      tva: int.parse(_tva.text.trim()),
    ));
    if (!mounted) return;
    if (r.success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = r.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final total = (int.tryParse(_ht.text.trim()) ?? 0) + (int.tryParse(_tva.text.trim()) ?? 0);
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau BL')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Card(
              margin: EdgeInsets.zero,
              color: Colors.blueGrey.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.grossiste, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Commande ${o.ref} · ${o.statutLabel}'),
                  Text('${o.products} produit(s) · ${_money.format(o.amount)} F'),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _ref,
              autofocus: true,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                labelText: 'N° du BL *',
                helperText: 'Tel qu\'imprimé sur le bon du grossiste',
                prefixIcon: Icon(Icons.receipt_long),
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'N° de BL obligatoire';
                if (t.length > 20) return '20 caractères au plus';
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date du BL', prefixIcon: Icon(Icons.event)),
                child: Row(children: [
                  Expanded(child: Text(_fmt.format(_date), style: const TextStyle(fontSize: 16))),
                  const Text('Modifier', style: TextStyle(color: AppColors.primary)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextFormField(
                  controller: _ht,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Montant HT'),
                  validator: (v) => int.tryParse((v ?? '').trim()) == null ? 'Montant' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _tva,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'TVA'),
                  validator: (v) => int.tryParse((v ?? '').trim()) == null ? 'Montant' : null,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text('Total TTC : ${_money.format(total)} F', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
                child: Row(children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade900))),
                ]),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                icon: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check),
                label: const Text('Créer le BL', style: TextStyle(fontSize: 17)),
                onPressed: _saving ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
