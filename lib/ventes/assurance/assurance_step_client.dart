// lib/ventes/assurance/assurance_step_client.dart
// Étape 1 : recherche du client (≥ 2 caractères, comme avant). Une panne s'affiche comme une panne
// avec « Réessayer » et SANS bouton « Créer » (défaut n°14 : plus de clients en double).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_controller.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_dialogs.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

class AssuranceStepClient extends StatefulWidget {
  /// Ouvre l'historique (Reprendre / Réimprimer).
  final VoidCallback onHistory;
  const AssuranceStepClient({super.key, required this.onHistory});

  @override
  State<AssuranceStepClient> createState() => _AssuranceStepClientState();
}

class _AssuranceStepClientState extends State<AssuranceStepClient> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  String? _error;
  List<ClientAssurance>? _results;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    final q = VenteInput.cleanQuery(text);
    if (q.length < 2) {
      setState(() {
        _query = q;
        _results = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
    });
    final r = await context.read<AssuranceController>().searchClients(q);
    if (!mounted || q != _query) return;
    setState(() {
      _loading = false;
      if (r case VenteOk(:final value)) {
        _results = value;
        _error = null;
      } else {
        _results = null;
        _error = venteMessage(r.message);
      }
    });
  }

  Future<void> _select(ClientAssurance client) async {
    _ctrl.clear();
    await context.read<AssuranceController>().selectClient(client);
  }

  Future<void> _create() async {
    final c = context.read<AssuranceController>();
    final ok = await showCreateClientDialog(context, c, initialName: _query);
    if (ok && mounted) _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_error != null) {
      body = LoadErrorView(message: 'Recherche impossible : $_error', onRetry: () => _search(_query));
    } else if (_loading && _results == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_results == null) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Saisissez au moins 2 caractères du nom ou du matricule.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        ),
      );
    } else if (_results!.isEmpty) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Ce client est introuvable (« $_query »).'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.person_add),
            label: const Text('Créer un nouveau client'),
            onPressed: _create,
          ),
        ]),
      );
    } else {
      final list = _results!;
      body = ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final client = list[i];
          return ListTile(
            minVerticalPadding: 8,
            leading: CircleAvatar(child: Text(client.strFIRSTNAME.isNotEmpty ? client.strFIRSTNAME[0] : '?')),
            title: Text('${client.strFIRSTNAME} ${client.strLASTNAME}'.trim(), style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Matricule : ${client.strNUMEROSECURITESOCIAL}'),
              for (final tp in client.tiersPayants)
                Text('${tp.tpFullName} (${tp.taux} %)', style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.secondary)),
            ]),
            onTap: () => _select(client),
          );
        },
      );
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('assurance-client-recherche'),
              controller: _ctrl,
              focusNode: _focus,
              inputFormatters: VenteInput.queryFormatters,
              decoration: InputDecoration(
                labelText: 'Rechercher client (nom / matricule)',
                prefixIcon: _loading
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                    : const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Effacer',
                  onPressed: () {
                    _ctrl.clear();
                    _changed('');
                    _focus.requestFocus();
                  },
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: _changed,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const ValueKey('assurance-historique'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              foregroundColor: Colors.orange.shade800,
              side: BorderSide(color: Colors.orange.shade300),
            ),
            onPressed: widget.onHistory,
            icon: const Icon(Icons.history),
            label: const Text('Historique', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
      if (_loading && _results != null) const LinearProgressIndicator(minHeight: 2),
      Expanded(child: body),
    ]);
  }
}
