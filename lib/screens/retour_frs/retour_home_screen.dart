// lib/screens/retour_frs/retour_home_screen.dart
// Retour fournisseur : choix du BL entré en stock (n° de BL, grossiste).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_gateways.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/retour/retour_gateway.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_bl_screen.dart' show CodeCamera;
import 'package:prestige_vente_app/screens/retour_frs/retour_bl_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';
import 'package:provider/provider.dart';

class RetourHomeScreen extends StatefulWidget {
  /// Remplaçables pour les tests.
  final RetourGateway? gateway;
  final CodeCamera? codeCamera;
  final DateTime Function()? clock;

  /// Présentation imposée (tests) ; sinon celle choisie sur l'appareil (A par défaut).
  final ListPresentation? presentation;

  const RetourHomeScreen({super.key, this.gateway, this.codeCamera, this.clock, this.presentation});

  @override
  State<RetourHomeScreen> createState() => _RetourHomeScreenState();
}

class _RetourHomeScreenState extends State<RetourHomeScreen> {
  late final RetourGateway _gateway =
      // Hors ligne : copie locale et file des opérations (H3) ; en ligne : inchangé.
      widget.gateway ?? OfflineRetourGateway(DioRetourGateway(DioClient.getClient(context.read<SettingsProvider>().baseUrl)));
  List<ReceptionBl> _bls = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String? _grossiste;
  Timer? _debounce;
  late ListPresentation _style = widget.presentation ?? ListPresentation.dashboard;

  // Période d'entrée en stock : aujourd'hui par défaut.
  _Period _period = _Period.today;
  late DateTimeRange _range = _rangeFor(_Period.today);
  static final _fmt = DateFormat('dd/MM/yyyy');

  DateTime get _today {
    final n = (widget.clock ?? DateTime.now)();
    return DateTime(n.year, n.month, n.day);
  }

  DateTimeRange _rangeFor(_Period p) => switch (p) {
        _Period.today => DateTimeRange(start: _today, end: _today),
        _Period.week => DateTimeRange(start: _today.subtract(const Duration(days: 6)), end: _today),
        _Period.month => DateTimeRange(start: _today.subtract(const Duration(days: 29)), end: _today),
        _Period.custom => _range,
      };

  Future<void> _choosePeriod(_Period p) async {
    if (p == _Period.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: _today.subtract(const Duration(days: 730)),
        lastDate: _today,
        initialDateRange: _range,
      );
      if (picked == null) return;
      setState(() {
        _period = p;
        _range = picked;
      });
    } else {
      setState(() {
        _period = p;
        _range = _rangeFor(p);
      });
    }
    _load();
  }

  @override
  void initState() {
    super.initState();
    if (widget.presentation == null) {
      PresentationPrefs.load().then((p) {
        if (mounted) setState(() => _style = p);
      });
    }
    _load();
  }

  void _setStyle(ListPresentation p) {
    setState(() => _style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bls = await _gateway.bls(query: _query, from: _range.start, to: _range.end);
      if (!mounted) return;
      setState(() {
        _bls = bls;
        _loading = false;
        if (_grossiste != null && !bls.any((b) => b.grossiste == _grossiste)) _grossiste = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e is StockHorsLigneException ? e.message : 'Liste des BL non chargée. Vérifiez la connexion au serveur.';
        });
      }
    }
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _query = v.trim();
      _load();
    });
  }

  Future<void> _open(ReceptionBl bl) async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RetourBlScreen(bl: bl, gateway: _gateway, codeCamera: widget.codeCamera, presentation: _style),
    ));
    if (done == true && mounted) Constants.showSnackBar(context, 'Retour enregistré en préparation.');
  }

  // ---------------------------------------------------------------------------
  // Affichage : A · Tableau de bord, B · Liste groupée, C · Parcours guidé
  // ---------------------------------------------------------------------------
  static const _periodLabels = {
    _Period.today: 'Aujourd\'hui',
    _Period.week: '7 jours',
    _Period.month: '30 jours',
    _Period.custom: 'Période…',
  };

  List<ReceptionBl> get _visible => _bls.where((b) => _grossiste == null || b.grossiste == _grossiste).toList();

  String get _periodText => _range.start == _range.end
      ? 'Entrés en stock le ${_fmt.format(_range.start)} · ${_bls.length} BL'
      : 'Entrés en stock du ${_fmt.format(_range.start)} au ${_fmt.format(_range.end)} · ${_bls.length} BL';

  @override
  Widget build(BuildContext context) => switch (_style) {
        ListPresentation.dashboard => _buildDashboard(),
        ListPresentation.compact => _buildCompact(),
        ListPresentation.guided => _buildGuided(),
      };

  List<Widget> _actions(Color color) => [
        PresentationMenuButton(value: _style, onChanged: _setStyle, color: color),
        IconButton(icon: Icon(Icons.refresh, color: color), tooltip: 'Actualiser', onPressed: _load),
      ];

  Widget _search({Color fill = Colors.white}) => TextField(
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: 'N° du BL',
          filled: true,
          fillColor: fill,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        onChanged: _onQuery,
      );

  Widget _periodChips() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          for (final p in _Period.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                avatar: p == _Period.custom ? const Icon(Icons.date_range, size: 18) : null,
                label: Text(_periodLabels[p]!),
                selected: _period == p,
                onSelected: (_) => _choosePeriod(p),
              ),
            ),
        ]),
      );

  Widget _grossisteChips() {
    final names = {for (final b in _bls) b.grossiste}.where((g) => g.isNotEmpty).toList()..sort();
    if (names.length < 2) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
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

  Widget _periodLine() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
        child: Text(_periodText, style: const TextStyle(fontSize: 12, color: Color(0xFF4A5A70))),
      );

  Widget _status() => Column(children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [Text(_error!, textAlign: TextAlign.center), TextButton(onPressed: _load, child: const Text('Réessayer'))]),
          ),
      ]);

  static const _emptyText = 'Aucun BL entré en stock sur cette période.\nChoisissez « 7 jours », « 30 jours » ou une période.';
  Widget _empty() => ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Text(_emptyText, textAlign: TextAlign.center))]);

  // --- A ---
  Widget _buildDashboard() {
    final list = _visible;
    final boxes = _bls.fold<int>(0, (s, b) => s + b.boxes);
    return Scaffold(
      backgroundColor: Pal.page,
      body: Column(children: [
        NavyHeader(
          title: 'Retour fournisseur',
          wide: true,
          subtitle: 'Choisissez le BL dont des produits repartent',
          actions: _actions(Colors.white),
          children: [
            Row(children: [
              Expanded(child: KpiTile('${_bls.length}', 'BL sur la période')),
              const SizedBox(width: 8),
              Expanded(child: KpiTile('${{for (final b in _bls) b.grossiste}.length}', 'grossiste(s)')),
              const SizedBox(width: 8),
              Expanded(child: KpiTile('$boxes', 'boîtes reçues', highlight: true)),
            ]),
            SegmentedPills(
              labels: [for (final p in _Period.values) _periodLabels[p]!],
              selected: _period.index,
              onSelected: (i) => _choosePeriod(_Period.values[i]),
            ),
          ],
        ),
        Expanded(
          child: ContentWidth(
            wide: true,
            child: Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 0), child: _search()),
              _grossisteChips(),
              _periodLine(),
              _status(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: list.isEmpty && !_loading
                      ? _empty()
                      : AdaptiveCardList(
                          columns: Responsive.columns(context),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) => _cardA(list[i]),
                        ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _cardA(ReceptionBl b) => SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            GrossisteAvatar(b.grossiste),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('BL ${b.ref}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Pal.ink)),
                Text('${b.grossiste} · ${b.date}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Figure('${b.lines}', 'ligne(s)'),
            const SizedBox(width: 18),
            Figure('${b.boxes}', 'boîte(s)'),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              style: navyButton,
              icon: const Icon(Icons.assignment_return, size: 20),
              label: const Text('Retourner des produits'),
              onPressed: () => _open(b),
            ),
          ),
        ]),
      );

  // --- B ---
  Widget _buildCompact() {
    final list = _visible;
    final groups = <String, List<ReceptionBl>>{};
    for (final b in list) {
      groups.putIfAbsent(b.grossiste, () => []).add(b);
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Pal.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Retour fournisseur', style: TextStyle(fontWeight: FontWeight.bold, color: Pal.navy)),
        actions: _actions(Pal.navy),
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Pal.line)),
      ),
      body: Column(children: [
        Expanded(
          child: ContentWidth(
            child: Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: _search(fill: Pal.page)),
              _periodChips(),
              _grossisteChips(),
              _periodLine(),
              _status(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: list.isEmpty && !_loading
                      ? _empty()
                      : ListView(children: [
                          for (final e in groups.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                              child: Row(children: [
                                Expanded(child: Text(e.key.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: Color(0xFF4A5A70)))),
                                Text('${e.value.length} BL', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4A5A70))),
                              ]),
                            ),
                            for (final b in e.value)
                              InkWell(
                                onTap: () => _open(b),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
                                  child: Row(children: [
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text('BL ${b.ref}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
                                        Text('${b.date} · ${b.lines} ligne(s) · ${b.boxes} boîte(s)', style: const TextStyle(fontSize: 13, color: Pal.muted)),
                                      ]),
                                    ),
                                    const Icon(Icons.chevron_right, color: Pal.muted),
                                  ]),
                                ),
                              ),
                          ],
                        ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // --- C ---
  Widget _buildGuided() {
    final list = _visible;
    return Scaffold(
      backgroundColor: const Color(0xFFEEF2F7),
      body: Column(children: [
        NavyHeader(
          title: 'Retour fournisseur',
          wide: true,
          rounded: false,
          actions: _actions(Colors.white),
          children: const [
            StepsBar(active: 0, steps: [
              (title: 'Choisir le BL', detail: 'entré en stock', onTap: null),
              (title: 'Produits', detail: 'quantité, motif', onTap: null),
              (title: 'Validation', detail: 'sur Prestige', onTap: null),
            ]),
          ],
        ),
        Expanded(
          child: ContentWidth(
            wide: true,
            child: Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), child: _search()),
              _periodChips(),
              _grossisteChips(),
              _periodLine(),
              _status(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: list.isEmpty && !_loading
                      ? _empty()
                      : AdaptiveCardList(
                          columns: Responsive.columns(context),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final b = list[i];
                            return SoftCard(
                              band: GrossisteAvatar.colorsFor(b.grossiste).$2,
                              child: Row(children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('BL ${b.ref}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Pal.ink)),
                                    Text('${b.grossiste} · ${b.lines} ligne(s) · ${b.boxes} boîte(s)', style: const TextStyle(fontSize: 13, color: Pal.muted)),
                                  ]),
                                ),
                                ElevatedButton(
                                  style: amberButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 44))),
                                  onPressed: () => _open(b),
                                  child: const Text('Choisir'),
                                ),
                              ]),
                            );
                          },
                        ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

enum _Period { today, week, month, custom }
