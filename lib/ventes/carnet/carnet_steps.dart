// lib/ventes/carnet/carnet_steps.dart
// Étapes 1 (client) et 2 (bon & ayant droit) de la Vente Carnet (nouvelle version).
// Recherche client : une panne s'affiche comme une panne (« Réessayer »), jamais « introuvable »
// avec le bouton Créer (défaut n°14). Bons obligatoires, nettoyés, sans doublon.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_controller.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_dialogs.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

// =============================================================================
// Étape 1 : client
// =============================================================================

class CarnetClientStep extends StatefulWidget {
  final VoidCallback onHistory;
  const CarnetClientStep({super.key, required this.onHistory});

  @override
  State<CarnetClientStep> createState() => _CarnetClientStepState();
}

class _CarnetClientStepState extends State<CarnetClientStep> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<ClientAssurance>? _results;
  String? _error;
  bool _loading = false;
  int _seq = 0;
  String _searched = '';

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
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(v));
  }

  Future<void> _search(String v) async {
    final q = VenteInput.cleanQuery(v);
    final seq = ++_seq;
    if (q.length < 2) {
      setState(() {
        _results = null;
        _error = null;
        _loading = false;
        _searched = '';
      });
      return;
    }
    setState(() => _loading = true);
    final r = await context.read<CarnetController>().searchClients(q);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      _searched = q;
      if (r case VenteOk(:final value)) {
        _results = value;
        _error = null;
      } else {
        _results = null;
        _error = venteMessage(r.message);
      }
    });
  }

  Future<void> _create() async {
    final c = context.read<CarnetController>();
    await showCreateClientCarnetDialog(context, c, initialName: _results != null && _results!.isEmpty ? _searched : '');
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    Widget body;
    if (_error != null) {
      body = LoadErrorView(message: 'Recherche impossible : $_error', onRetry: () => _search(_query.text));
    } else if (_loading && results == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (results == null) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Saisissez le nom ou le matricule du client (2 caractères min.)', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        ),
      );
    } else if (results.isEmpty) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Aucun client carnet pour « $_searched ».'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.person_add),
            label: const Text('Créer un nouveau client carnet'),
            onPressed: _create,
          ),
        ]),
      );
    } else {
      body = ListView.builder(
        itemCount: results.length,
        itemBuilder: (context, i) {
          final client = results[i];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(child: Text(client.strFIRSTNAME.isNotEmpty ? client.strFIRSTNAME[0] : '?')),
              title: Text('${client.strFIRSTNAME} ${client.strLASTNAME}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Matricule : ${client.strNUMEROSECURITESOCIAL}'),
                ...client.tiersPayants.map((tp) => Text('${tp.tpFullName} (${tp.taux}%)', style: const TextStyle(fontStyle: FontStyle.italic))),
              ]),
              onTap: () {
                _query.clear();
                context.read<CarnetController>().selectClient(client);
              },
            ),
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
              key: const ValueKey('carnet-client-recherche'),
              controller: _query,
              focusNode: _focus,
              inputFormatters: VenteInput.queryFormatters,
              onChanged: _onChanged,
              onSubmitted: _search,
              decoration: InputDecoration(
                labelText: 'Rechercher client carnet',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Effacer',
                        onPressed: () {
                          _query.clear();
                          _search('');
                          _focus.requestFocus();
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const ValueKey('carnet-historique'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56), padding: const EdgeInsets.symmetric(horizontal: 10)),
            onPressed: widget.onHistory,
            icon: const Icon(Icons.history),
            label: const Text('Historique'),
          ),
        ]),
      ),
      if (_loading && results != null) const LinearProgressIndicator(minHeight: 2),
      Expanded(child: body),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: _create,
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Nouveau client carnet'),
          ),
        ),
      ),
    ]);
  }
}

// =============================================================================
// Étape 2 : bons et ayant droit
// =============================================================================

class CarnetBonStep extends StatefulWidget {
  /// Changer de client (confirmation faite par l'écran).
  final VoidCallback onChangeClient;
  const CarnetBonStep({super.key, required this.onChangeClient});

  @override
  State<CarnetBonStep> createState() => _CarnetBonStepState();
}

class _CarnetBonStepState extends State<CarnetBonStep> {
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, FocusNode> _focus = {};
  String? _bonError;
  String? _bonErrorTp;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = context.read<CarnetController>();
      final first = c.activeTps.where((tp) => (c.bons[tp.compteTp] ?? '').isEmpty).firstOrNull ?? c.activeTps.firstOrNull;
      if (first != null) _focus[first.compteTp]?.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(CarnetController c, String compteTp) => _ctrls.putIfAbsent(compteTp, () => TextEditingController(text: c.bons[compteTp] ?? ''));

  void _continue() {
    final c = context.read<CarnetController>();
    final err = c.validateBons({for (final e in _ctrls.entries) e.key: e.value.text});
    if (err == null) return;
    setState(() {
      _bonError = err.message;
      _bonErrorTp = err.compteTp;
    });
    // Erreur affichée sous le champ concerné (ou au-dessus du bouton) : pas de bandeau qui masquerait « Continuer ».
    final tp = err.compteTp;
    if (tp != null) _focus[tp]?.requestFocus();
  }

  Future<void> _chooseAyantDroit(CarnetController c) async {
    final chosen = await showDialog<Object>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ayant droit (patient)'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [
            for (final a in c.ayantDroits)
              ListTile(
                minTileHeight: 48,
                leading: Icon(a == c.ayantDroit ? Icons.radio_button_checked : Icons.radio_button_off, color: AppColors.primary),
                title: Text(_adName(a)),
                subtitle: Text(
                    '${a.lgAYANTSDROITSID == c.client?.lgCLIENTID ? 'Le client lui-même · ' : ''}Matricule : ${a.strNUMEROSECURITESOCIAL.isEmpty ? '-' : a.strNUMEROSECURITESOCIAL}'),
                onTap: () => Navigator.of(ctx).pop(a),
              ),
            ListTile(
              minTileHeight: 48,
              leading: const Icon(Icons.person_add, color: AppColors.primary),
              title: const Text('Nouvel ayant droit'),
              onTap: () => Navigator.of(ctx).pop('new'),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler'))],
      ),
    );
    if (!mounted) return;
    if (chosen is AyantDroit) {
      c.selectAyantDroit(chosen);
    } else if (chosen == 'new') {
      await showCreateAyantDroitDialog(context, c);
    }
  }

  static String _adName(AyantDroit a) => a.fullName.isNotEmpty ? a.fullName : '${a.strFIRSTNAME} ${a.strLASTNAME}'.trim();

  Widget _ayantDroitCard(CarnetController c) {
    final ad = c.ayantDroit;
    final self = ad != null && ad.lgAYANTSDROITSID == c.client?.lgCLIENTID;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.personal_injury, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Ayant droit (patient)', style: TextStyle(fontSize: 12, color: Colors.black54)),
                Text(ad == null ? '-' : _adName(ad), key: const ValueKey('carnet-ayant-droit'), style: const TextStyle(fontWeight: FontWeight.bold)),
                if (self) const Text('Le client lui-même', style: TextStyle(fontSize: 12, color: Colors.black54)),
              ]),
            ),
            if (c.ayantDroitsLoading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          if (c.ayantDroitLocked)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Fixé à la création de la vente (panier déjà commencé).', style: TextStyle(fontSize: 12, color: Colors.black54)),
            )
          else
            Wrap(spacing: 8, children: [
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => _chooseAyantDroit(c),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Changer'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => showCreateAyantDroitDialog(context, c),
                icon: const Icon(Icons.person_add),
                label: const Text('Nouvel ayant droit'),
              ),
            ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CarnetController>();
    final client = c.client;
    if (client == null) return const Center(child: Text('Aucun client sélectionné. Veuillez recommencer.'));
    final canToggle = client.tiersPayants.length > 1;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.person, color: AppColors.primary),
                title: Text(client.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Matricule : ${client.strNUMEROSECURITESOCIAL}'),
                trailing: TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: widget.onChangeClient,
                  child: const Text('Changer de client'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (c.ayantDroitsError != null && !c.ayantDroitLocked)
              LoadErrorBanner(message: 'Ayants droit non chargés : ${venteMessage(c.ayantDroitsError)}', onRetry: c.loadAyantDroits),
            _ayantDroitCard(c),
            const SizedBox(height: 16),
            Text('N° de bon (Réf. bon)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final tp in client.tiersPayants) _tpCard(c, tp, canToggle),
            if (_bonError != null && _bonErrorTp == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_bonError!, style: TextStyle(color: Colors.red.shade700)),
              ),
          ]),
        ),
      ),
      Material(
        elevation: 6,
        color: Colors.white,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: ElevatedButton.icon(
              key: const ValueKey('carnet-continuer'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 52)),
              onPressed: _continue,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continuer vers la saisie des produits'),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _tpCard(CarnetController c, ClientTiersPayant tp, bool canToggle) {
    final active = c.isActive(tp);
    final ctrl = _ctrl(c, tp.compteTp);
    final focus = _focus.putIfAbsent(tp.compteTp, () => FocusNode());
    return Card(
      color: active ? Colors.white : Colors.grey.shade100,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(children: [
        CheckboxListTile(
          title: Text('${tp.tpFullName} (${tp.taux}%)', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('Matricule : ${tp.numSecurity}'),
          value: active,
          onChanged: canToggle ? (v) => c.toggleTp(tp, v ?? false) : null,
        ),
        if (active)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              key: ValueKey('carnet-bon-${tp.compteTp}'),
              controller: ctrl,
              focusNode: focus,
              inputFormatters: VenteInput.bonFormatters,
              decoration: InputDecoration(
                labelText: 'N° bon pour ${tp.tpFullName} *',
                border: const OutlineInputBorder(),
                errorText: _bonErrorTp == tp.compteTp ? _bonError : null,
              ),
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_bonError != null) {
                  setState(() {
                    _bonError = null;
                    _bonErrorTp = null;
                  });
                }
              },
              onSubmitted: (_) => _continue(),
            ),
          ),
      ]),
    );
  }
}
