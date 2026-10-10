// lib/screens/retour_frs/retour_home_screen.dart
// Retour fournisseur : choix du BL entré en stock (n° de BL, grossiste).
import 'dart:async';

import 'package:flutter/material.dart';
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

  const RetourHomeScreen({super.key, this.gateway, this.codeCamera});

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
      final bls = await _gateway.bls(query: _query);
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
                helperText: 'Sans n° : BL entrés en stock depuis 6 mois',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _onQuery,
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
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(24), child: Text('Aucun BL trouvé.', textAlign: TextAlign.center))])
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
