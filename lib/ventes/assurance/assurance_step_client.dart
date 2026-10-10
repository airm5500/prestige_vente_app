// lib/ventes/assurance/assurance_step_client.dart
// Étape 1 : recherche du client (≥ 2 caractères, comme avant) dans l'en-tête, cartes clients (nom,
// matricule, TP + taux). Une panne s'affiche comme une panne avec « Réessayer » et SANS « Nouveau client »
// (défaut n°14 : plus de clients en double) ; « + NOUVEAU CLIENT » seulement si le serveur a répondu
// « aucun client ». « HISTORIQUE » : reprendre ou réimprimer une prévente.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_controller.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_dialogs.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_frame.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

class AssuranceStepClient extends StatefulWidget {
  /// Présentation et en-tête communs.
  final AssuranceFrame frame;

  /// Ouvre l'historique (Reprendre / Réimprimer).
  final VoidCallback onHistory;
  const AssuranceStepClient({super.key, required this.frame, required this.onHistory});

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
    setState(() {});
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

  void _clear() {
    _ctrl.clear();
    _changed('');
    _focus.requestFocus();
  }

  Widget _searchField({required bool onDark}) => TextField(
        key: const ValueKey('assurance-client-recherche'),
        controller: _ctrl,
        focusNode: _focus,
        inputFormatters: VenteInput.queryFormatters,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 16, color: Pal.ink),
        decoration: InputDecoration(
          hintText: 'Nom ou matricule du client',
          hintStyle: const TextStyle(color: Pal.muted),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          prefixIcon: _loading
              ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : const Icon(Icons.search, color: Pal.muted),
          suffixIcon: _ctrl.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), tooltip: 'Effacer', onPressed: _clear),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: onDark ? BorderSide.none : const BorderSide(color: Color(0xFFC5D0DE)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: onDark ? BorderSide.none : const BorderSide(color: Color(0xFFC5D0DE)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: onDark ? Pal.amber : Pal.navy, width: 2),
          ),
        ),
        onChanged: _changed,
      );

  Widget _hint(IconData icon, String title, String text) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: const Color(0xFF9AA8BC)),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Pal.ink, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Pal.muted, height: 1.35)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final f = widget.frame;
    final results = _results;
    // « Nouveau client » seulement si le serveur a bien répondu « aucun client » (jamais sur une panne).
    final canCreate = _error == null && !_loading && results != null && results.isEmpty;

    Widget body;
    if (_error != null) {
      body = ListView(padding: const EdgeInsets.only(top: 4), children: [
        LoadErrorBanner(message: 'Recherche impossible : $_error', onRetry: _loading ? null : () => _search(_query)),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Le serveur n\'a pas répondu : le client existe peut-être. Réessayez avant de créer une fiche.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Pal.muted)),
        ),
      ]);
    } else if (_loading && results == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (results == null) {
      body = _hint(Icons.person_search_outlined, 'Recherchez le client',
          'Saisissez au moins 2 caractères du nom ou du matricule.\n« Historique » : reprendre ou réimprimer une prévente.');
    } else if (results.isEmpty) {
      body = _hint(Icons.person_off_outlined, 'Ce client est introuvable (« $_query »).', 'Vérifiez la saisie, ou créez la fiche avec « Nouveau client ».');
    } else {
      body = Column(children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: f.compact ? _denseList(results) : _cards(results, guided: f.guided)),
      ]);
    }

    return f.scaffold(
      step: 0,
      title: 'Vente assurance',
      subtitle: f.guided ? null : 'Choisir le client',
      header: [_searchField(onDark: true)],
      compactHeader: [_searchField(onDark: false)],
      body: body,
      bottom: AssuranceBottomBar(children: [
        SizedBox(
          height: 50,
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('assurance-historique'),
                style: outlineButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 50))),
                onPressed: widget.onHistory,
                icon: const Icon(Icons.history, size: 20),
                label: const FittedBox(fit: BoxFit.scaleDown, child: Text('HISTORIQUE')),
              ),
            ),
            if (canCreate) ...[
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  key: const ValueKey('assurance-nouveau-client'),
                  style: f.mainButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 50))),
                  onPressed: _create,
                  icon: const Icon(Icons.add, size: 20),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('NOUVEAU CLIENT')),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  String _tps(ClientAssurance c) => c.tiersPayants.map((tp) => '${tp.tpFullName} ${tp.taux} %').join(' · ');

  String _name(ClientAssurance c) => '${c.strFIRSTNAME} ${c.strLASTNAME}'.trim().isEmpty ? c.fullName : '${c.strFIRSTNAME} ${c.strLASTNAME}'.trim();

  /// A / C : cartes (C : bande bleue).
  Widget _cards(List<ClientAssurance> list, {required bool guided}) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 9),
        itemBuilder: (context, i) {
          final client = list[i];
          return AssuranceCard(
            band: guided ? Pal.navy : null,
            onTap: () => _select(client),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_name(client), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Pal.ink)),
                  const SizedBox(height: 2),
                  Text('Mat. ${client.strNUMEROSECURITESOCIAL.isEmpty ? '—' : client.strNUMEROSECURITESOCIAL}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
                  if (client.tiersPayants.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final tp in client.tiersPayants)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: const Color(0xFFE3ECF7), borderRadius: BorderRadius.circular(20)),
                          child: Text('${tp.tpFullName} ${tp.taux} %',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Pal.navy)),
                        ),
                    ]),
                  ],
                ]),
              ),
              const SizedBox(width: 8),
              const StatusBadge('Choisir', fg: Pal.navy, bg: Color(0xFFE3ECF7)),
            ]),
          );
        },
      );

  /// B : lignes denses.
  Widget _denseList(List<ClientAssurance> list) => ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF1F5)),
        itemBuilder: (context, i) {
          final client = list[i];
          final tps = _tps(client);
          return Material(
            color: Colors.white,
            child: InkWell(
              onTap: () => _select(client),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_name(client), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Pal.ink)),
                        Text('Mat. ${client.strNUMEROSECURITESOCIAL}${tps.isEmpty ? '' : ' · $tps'}',
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
                      ]),
                    ),
                    const Icon(Icons.chevron_right, color: Pal.muted),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}
