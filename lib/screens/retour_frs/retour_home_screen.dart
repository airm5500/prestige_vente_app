// lib/screens/retour_frs/retour_home_screen.dart
// Retour fournisseur : choix du BL entré en stock (n° de BL, grossiste).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/retour/retour_gateway.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_bl_screen.dart' show CodeCamera;
import 'package:prestige_vente_app/screens/retour_frs/retour_bl_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class RetourHomeScreen extends StatefulWidget {
  /// Remplaçables pour les tests.
  final RetourGateway? gateway;
  final CodeCamera? codeCamera;
  final DateTime Function()? clock;

  const RetourHomeScreen({super.key, this.gateway, this.codeCamera, this.clock});

  @override
  State<RetourHomeScreen> createState() => _RetourHomeScreenState();
}

class _RetourHomeScreenState extends State<RetourHomeScreen> {
  late final RetourGateway _gateway =
      widget.gateway ?? DioRetourGateway(DioClient.getClient(context.read<SettingsProvider>().baseUrl));
  List<ReceptionBl> _bls = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String? _grossiste;
  Timer? _debounce;

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
    _load();
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
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Liste des BL non chargée. Vérifiez la connexion au serveur.';
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
      builder: (_) => RetourBlScreen(bl: bl, gateway: _gateway, codeCamera: widget.codeCamera),
    ));
    if (done == true && mounted) Constants.showSnackBar(context, 'Retour enregistré en préparation.');
  }

  @override
  Widget build(BuildContext context) {
    final grossistes = {for (final b in _bls) b.grossiste}.where((g) => g.isNotEmpty).toList()..sort();
    final list = _bls.where((b) => _grossiste == null || b.grossiste == _grossiste).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retour fournisseur'),
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Actualiser', onPressed: _load)],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'N° du BL',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _onQuery,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              for (final p in _Period.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    avatar: p == _Period.custom ? const Icon(Icons.date_range, size: 18) : null,
                    label: Text(switch (p) {
                      _Period.today => 'Aujourd\'hui',
                      _Period.week => '7 jours',
                      _Period.month => '30 jours',
                      _Period.custom => 'Période…',
                    }),
                    selected: _period == p,
                    onSelected: (_) => _choosePeriod(p),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _range.start == _range.end
                    ? 'Entrés en stock le ${_fmt.format(_range.start)} · ${_bls.length} BL'
                    : 'Entrés en stock du ${_fmt.format(_range.start)} au ${_fmt.format(_range.end)} · ${_bls.length} BL',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ),
          ),
          if (grossistes.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: const Text('Tous'), selected: _grossiste == null, onSelected: (_) => setState(() => _grossiste = null)),
                ),
                for (final g in grossistes)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(label: Text(g), selected: _grossiste == g, onSelected: (_) => setState(() => _grossiste = g)),
                  ),
              ]),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [Text(_error!, textAlign: TextAlign.center), TextButton(onPressed: _load, child: const Text('Réessayer'))]),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: list.isEmpty && !_loading
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(24), child: Text('Aucun BL entré en stock sur cette période.\nChoisissez « 7 jours », « 30 jours » ou une période.', textAlign: TextAlign.center))])
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final b = list[i];
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.receipt_long, color: AppColors.primary),
                            title: Text('BL ${b.ref} — ${b.grossiste}'),
                            subtitle: Text('${b.date} · ${b.lines} ligne(s) · ${b.boxes} boîte(s)'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _open(b),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Period { today, week, month, custom }
