// lib/ventes/carnet/carnet_steps.dart
// Étapes 1 (client) et 2 (bon & ayant droit) de la Vente Carnet (nouvelle version, A / B / C).
// Recherche client : une panne s'affiche comme une panne (« Réessayer »), jamais « introuvable » ;
// « + NOUVEAU CLIENT » seulement si le serveur a répondu « aucun client » (défaut n°14).
// Bons obligatoires, nettoyés, sans doublon ; « Continuer » désactivé avec la raison exacte.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_controller.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_dialogs.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_frame.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

const _badgeChoisir = StatusBadge('Choisir', fg: Pal.navy, bg: Color(0xFFE3ECF7));
const _badgeChoisi = StatusBadge('✓ Choisi', fg: Color(0xFF166534), bg: Color(0xFFE6F4EA));

/// Étiquette de section (majuscules discrètes).
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Pal.muted, letterSpacing: 0.5)),
      );
}

/// Carte blanche (A), ligne à filet (B) ou carte à bande (C).
class _Tile extends StatelessWidget {
  final CarnetFrame frame;
  final Widget child;
  final Color? band;
  final VoidCallback? onTap;
  const _Tile({required this.frame, required this.child, this.band, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: const EdgeInsets.fromLTRB(12, 10, 10, 10), child: child);
    if (frame.compact) {
      return Material(
        color: Colors.white,
        shape: const Border(bottom: BorderSide(color: Color(0xFFEEF1F5))),
        child: InkWell(onTap: onTap, child: content),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        elevation: 0.6,
        shadowColor: const Color(0x3314213D),
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (frame.guided && band != null) Container(width: 5, color: band),
              Expanded(child: content),
            ]),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Étape 1 : client
// =============================================================================

class CarnetClientStep extends StatefulWidget {
  final CarnetFrame frame;
  final VoidCallback onHistory;
  const CarnetClientStep({super.key, required this.frame, required this.onHistory});

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

  CarnetFrame get _f => widget.frame;

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

  /// Le serveur a répondu « aucun client » pour la recherche affichée.
  bool get _noClient => _error == null && _results != null && _results!.isEmpty && !_loading;

  Future<void> _create() async {
    final c = context.read<CarnetController>();
    await showCreateClientCarnetPage(context, c, initialName: _noClient ? _searched : '', presentation: _f.style);
  }

  Widget _field({required bool dark}) => TextField(
        key: const ValueKey('carnet-client-recherche'),
        controller: _query,
        focusNode: _focus,
        inputFormatters: VenteInput.queryFormatters,
        onChanged: _onChanged,
        onSubmitted: _search,
        style: const TextStyle(fontSize: 16.5),
        decoration: InputDecoration(
          hintText: 'Nom ou matricule du client',
          hintStyle: const TextStyle(color: Pal.muted, fontSize: 15),
          prefixIcon: _loading
              ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : const Icon(Icons.search),
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
          isDense: true,
          filled: true,
          fillColor: dark ? Colors.white : Pal.page,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: dark ? BorderSide.none : const BorderSide(color: Color(0xFFC5D0DE))),
          enabledBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: dark ? BorderSide.none : const BorderSide(color: Color(0xFFC5D0DE))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Pal.amber, width: 2.5)),
        ),
      );

  Widget _clientTile(ClientAssurance client) {
    final carnets = client.tiersPayants.map((tp) => '${tp.tpFullName} ${tp.taux} %').join(' · ');
    return _Tile(
      frame: _f,
      band: Pal.navy,
      onTap: () {
        _query.clear();
        context.read<CarnetController>().selectClient(client);
      },
      child: Row(children: [
        if (!_f.compact) ...[
          GrossisteAvatar(carnetName(client.fullName, client.strFIRSTNAME, client.strLASTNAME), size: 40),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${client.strFIRSTNAME} ${client.strLASTNAME}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Pal.ink)),
            Text('Mat. ${client.strNUMEROSECURITESOCIAL.isEmpty ? '—' : client.strNUMEROSECURITESOCIAL}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
            if (carnets.isNotEmpty)
              Text(carnets, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Pal.navy, fontWeight: FontWeight.w500)),
          ]),
        ),
        const SizedBox(width: 6),
        _badgeChoisir,
      ]),
    );
  }

  Widget _message(IconData icon, String title, String text) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: const Color(0xFF9AA8BC)),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Pal.ink, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Pal.muted)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final results = _results;
    Widget body;
    if (_error != null) {
      body = LoadErrorView(message: 'Recherche impossible : $_error', onRetry: () => _search(_query.text));
    } else if (_loading && results == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (results == null) {
      body = _message(Icons.person_search_outlined, 'Rechercher le client carnet', 'Saisissez le nom ou le matricule du client (2 caractères min.)');
    } else if (results.isEmpty) {
      body = _message(Icons.person_off_outlined, 'Aucun client carnet pour « $_searched ».', 'Vérifiez l\'orthographe ou créez la fiche du client.');
    } else {
      body = ListView.builder(
        padding: _f.compact ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 10, 12, 16),
        itemCount: results.length,
        itemBuilder: (context, i) => _clientTile(results[i]),
      );
    }

    final history = OutlinedButton.icon(
      key: const ValueKey('carnet-historique'),
      style: outlineButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 50))),
      onPressed: widget.onHistory,
      icon: const Icon(Icons.history),
      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Historique')),
    );
    return _f.scaffold(
      title: 'Vente carnet',
      subtitle: 'Étape 1 sur 4',
      header: [_field(dark: true)],
      compactHeader: [_field(dark: false)],
      body: Column(children: [
        if (_loading && results != null) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: body),
      ]),
      bottom: CarnetBottomBar(
        child: Row(children: [
          Expanded(child: history),
          if (_noClient) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                key: const ValueKey('carnet-nouveau-client'),
                style: _f.mainButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 50))),
                onPressed: _create,
                icon: const Icon(Icons.person_add_alt_1),
                label: const FittedBox(fit: BoxFit.scaleDown, child: Text('+ NOUVEAU CLIENT')),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// =============================================================================
// Étape 2 : bons et ayant droit
// =============================================================================

class CarnetBonStep extends StatefulWidget {
  final CarnetFrame frame;

  /// Changer de client (confirmation faite par l'écran).
  final VoidCallback onChangeClient;
  const CarnetBonStep({super.key, required this.frame, required this.onChangeClient});

  @override
  State<CarnetBonStep> createState() => _CarnetBonStepState();
}

class _CarnetBonStepState extends State<CarnetBonStep> {
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, FocusNode> _focus = {};
  String? _bonError;
  String? _bonErrorTp;

  CarnetFrame get _f => widget.frame;

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

  /// Ce qui empêche de continuer (mêmes règles que CarnetController.validateBons), ou null.
  String? _blocked(CarnetController c) {
    final ad = c.ayantDroit;
    if (c.client == null) return 'Aucun client sélectionné.';
    if (ad == null || ad.lgAYANTSDROITSID.isEmpty) return 'Choisissez l\'ayant droit (patient).';
    if (c.activeTps.isEmpty) return 'Aucun carnet n\'est actif pour ce client.';
    final cleaned = <String, String>{};
    for (final tp in c.activeTps) {
      final b = VenteInput.cleanBon(_ctrl(c, tp.compteTp).text);
      if (b.isEmpty) return 'Le N° de bon pour ${tp.tpFullName} est requis.';
      cleaned[tp.compteTp] = b;
    }
    if (VenteInput.hasDuplicateBons(cleaned)) return 'Le même N° de bon est saisi deux fois.';
    return null;
  }

  void _continue() {
    final c = context.read<CarnetController>();
    final err = c.validateBons({for (final e in _ctrls.entries) e.key: e.value.text});
    if (err == null) return;
    setState(() {
      _bonError = err.message;
      _bonErrorTp = err.compteTp;
    });
    final tp = err.compteTp;
    if (tp != null) _focus[tp]?.requestFocus();
  }

  static String _adName(AyantDroit a) => carnetName(a.fullName, a.strFIRSTNAME, a.strLASTNAME);

  Widget _clientCard(CarnetController c, ClientAssurance client) => _Tile(
        frame: _f,
        band: Pal.navy,
        child: Row(children: [
          const Icon(Icons.person, color: Pal.navy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(client.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink)),
              Text('Mat. ${client.strNUMEROSECURITESOCIAL.isEmpty ? '—' : client.strNUMEROSECURITESOCIAL}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
            ]),
          ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 8), foregroundColor: Pal.navy),
            onPressed: widget.onChangeClient,
            child: const Text('Changer de client'),
          ),
        ]),
      );

  Widget _ayantDroitTile(CarnetController c, AyantDroit a) {
    final chosen = a == c.ayantDroit;
    final self = a.lgAYANTSDROITSID == c.client?.lgCLIENTID;
    final locked = c.ayantDroitLocked;
    return _Tile(
      frame: _f,
      band: chosen ? Pal.green : Pal.line,
      onTap: locked || chosen ? null : () => c.selectAyantDroit(a),
      child: Row(children: [
        Icon(chosen ? Icons.radio_button_checked : Icons.radio_button_off, color: chosen ? Pal.green : Pal.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_adName(a), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: Pal.ink)),
            if (self) const Text('Le client lui-même', style: TextStyle(fontSize: 12.5, color: Pal.muted)),
            Text('Mat. ${a.strNUMEROSECURITESOCIAL.isEmpty ? '—' : a.strNUMEROSECURITESOCIAL}${self ? ' · par défaut' : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Pal.muted)),
          ]),
        ),
        const SizedBox(width: 6),
        if (chosen) _badgeChoisi else if (!locked) _badgeChoisir,
      ]),
    );
  }

  Widget _tpCard(CarnetController c, ClientTiersPayant tp, bool canToggle) {
    final active = c.isActive(tp);
    final ctrl = _ctrl(c, tp.compteTp);
    final focus = _focus.putIfAbsent(tp.compteTp, () => FocusNode());
    return _Tile(
      frame: _f,
      band: active ? Pal.navy : Pal.line,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (canToggle)
            SizedBox(
              width: 44,
              height: 44,
              child: Checkbox(value: active, onChanged: (v) => setState(() => c.toggleTp(tp, v ?? false))),
            )
          else
            const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.menu_book, color: Pal.navy)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tp.tpFullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: Pal.ink)),
              Text('Taux ${tp.taux} % · Mat. ${tp.numSecurity.isEmpty ? '—' : tp.numSecurity}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
            ]),
          ),
        ]),
        if (active)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              key: ValueKey('carnet-bon-${tp.compteTp}'),
              controller: ctrl,
              focusNode: focus,
              inputFormatters: VenteInput.bonFormatters,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: 'N° de bon *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Pal.navy, width: 2)),
                errorText: _bonErrorTp == tp.compteTp ? _bonError : null,
                isDense: true,
              ),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {
                _bonError = null;
                _bonErrorTp = null;
              }),
              onSubmitted: (_) {
                if (_blocked(c) == null) _continue();
              },
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CarnetController>();
    final client = c.client;
    if (client == null) {
      return _f.scaffold(title: 'Vente carnet', body: const Center(child: Text('Aucun client sélectionné. Veuillez recommencer.')));
    }
    final canToggle = client.tiersPayants.length > 1;
    final locked = c.ayantDroitLocked;
    final ads = locked ? [if (c.ayantDroit != null) c.ayantDroit!] : c.ayantDroits;
    final reason = _blocked(c);
    final pad = _f.compact ? const EdgeInsets.symmetric(horizontal: 12) : EdgeInsets.zero;

    return _f.scaffold(
      title: 'Vente carnet',
      subtitle: 'Étape 2 sur 4',
      body: ListView(
        padding: _f.compact ? const EdgeInsets.only(bottom: 16) : const EdgeInsets.fromLTRB(12, 10, 12, 16),
        children: [
          _clientCard(c, client),
          if (c.ayantDroitsError != null && !locked)
            LoadErrorBanner(message: 'Ayants droit non chargés : ${venteMessage(c.ayantDroitsError)}', onRetry: c.loadAyantDroits),
          Padding(
            padding: pad,
            child: Row(children: [
              const Expanded(child: _Label('Ayant droit (patient)')),
              if (c.ayantDroitsLoading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
          ),
          for (final a in ads) _ayantDroitTile(c, a),
          if (locked)
            Padding(
              padding: pad.add(const EdgeInsets.only(bottom: 6)),
              child: const Text('Fixé à la création de la vente (panier déjà commencé).', style: TextStyle(fontSize: 12, color: Pal.muted)),
            )
          else
            Padding(
              padding: pad.add(EdgeInsets.only(top: _f.compact ? 8 : 0)),
              child: OutlinedButton.icon(
                style: outlineButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 46))),
                onPressed: () => showCreateAyantDroitDialog(context, c),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Nouvel ayant droit'),
              ),
            ),
          const SizedBox(height: 8),
          Padding(padding: pad, child: const _Label('N° de bon')),
          for (final tp in client.tiersPayants) _tpCard(c, tp, canToggle),
          if (_bonError != null && _bonErrorTp == null)
            Padding(
              padding: pad,
              child: Text(_bonError!, style: TextStyle(color: Colors.red.shade700)),
            ),
        ],
      ),
      bottom: CarnetBottomBar(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ElevatedButton.icon(
            key: const ValueKey('carnet-continuer'),
            style: _f.mainButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 52))),
            onPressed: reason == null ? _continue : null,
            icon: const Icon(Icons.arrow_forward),
            label: const FittedBox(fit: BoxFit.scaleDown, child: Text('CONTINUER VERS LES PRODUITS')),
          ),
          if (reason != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(reason,
                  key: const ValueKey('carnet-continuer-raison'),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: Colors.red.shade700)),
            ),
        ]),
      ),
    );
  }
}
