// lib/ventes/assurance/assurance_step_couverture.dart
// Étape 2 : ayant droit (obligatoire, défaut n°11 ; carte + Changer / Nouvel ayant droit), tiers payants
// en cartes (case, taux ✎ 0-100, « Changer l'assurance » dans la même fenêtre), N° de bon obligatoire
// (rouge s'il manque, nettoyé, sans doublon). « CONTINUER VERS LES PRODUITS » fixé en bas, désactivé
// avec la raison exacte affichée.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_controller.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_dialogs.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_frame.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

class AssuranceStepCouverture extends StatefulWidget {
  /// Présentation et en-tête communs.
  final AssuranceFrame frame;

  /// « Changer de client » (confirmation faite par l'écran).
  final VoidCallback onChangeClient;
  const AssuranceStepCouverture({super.key, required this.frame, required this.onChangeClient});

  @override
  State<AssuranceStepCouverture> createState() => _AssuranceStepCouvertureState();
}

class _AssuranceStepCouvertureState extends State<AssuranceStepCouverture> {
  final Map<String, TextEditingController> _bons = {};
  final Map<String, FocusNode> _focus = {};

  /// Erreur renvoyée par la validation de l'étape (affichée au-dessus du bouton).
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirstEmpty());
  }

  @override
  void dispose() {
    for (final c in _bons.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// Champs des bons synchronisés avec le contrôleur (bons conservés après une modification de la fiche).
  void _sync(AssuranceController c) {
    for (final tp in c.client?.tiersPayants ?? const <ClientTiersPayant>[]) {
      _bons.putIfAbsent(tp.compteTp, () => TextEditingController(text: c.bonNumbers[tp.compteTp] ?? ''));
      _focus.putIfAbsent(tp.compteTp, FocusNode.new);
    }
    for (final tp in c.activeTiersPayants) {
      _bons.putIfAbsent(tp.compteTp, () => TextEditingController(text: c.bonNumbers[tp.compteTp] ?? ''));
      _focus.putIfAbsent(tp.compteTp, FocusNode.new);
    }
  }

  Map<String, String> get _bonValues => {for (final e in _bons.entries) e.key: e.value.text};

  bool _bonEmpty(String compteTp) => VenteInput.cleanBon(_bons[compteTp]?.text).isEmpty;

  void _focusFirstEmpty() {
    if (!mounted) return;
    final c = context.read<AssuranceController>();
    for (final tp in c.activeTiersPayants) {
      if (_bonEmpty(tp.compteTp)) {
        _focus[tp.compteTp]?.requestFocus();
        return;
      }
    }
  }

  /// Ce qui empêche de continuer (null = possible) : mêmes règles que la validation du contrôleur.
  String? _blockReason(AssuranceController c) {
    if (c.client == null) return 'Aucun client sélectionné.';
    if (c.ayantDroit == null) {
      return c.ayantDroitsError != null
          ? 'Ayants droit non chargés : touchez « Réessayer ».'
          : 'Choisissez ou créez un ayant droit (patient) avant de continuer.';
    }
    if (c.activeTiersPayants.isEmpty) return 'Veuillez activer au moins un tiers payant pour cette vente.';
    for (final tp in c.activeTiersPayants) {
      if (_bonEmpty(tp.compteTp)) return 'Saisissez le n° de bon ${tp.tpFullName}';
    }
    return c.checkBons(_bonValues);
  }

  void _continue() {
    final c = context.read<AssuranceController>();
    if (c.busy || _blockReason(c) != null) {
      _focusFirstEmpty();
      return;
    }
    final err = c.validateCouverture(_bonValues);
    setState(() => _error = err);
    if (err != null) _focusFirstEmpty();
  }

  Future<void> _editTp(AssuranceController c, ActiveTiersPayant tp) async {
    await showEditTiersPayantDialog(context, c, tp);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirstEmpty());
  }

  Future<void> _chooseAyantDroit(AssuranceController c) async {
    if (c.busy) return;
    final ads = c.ayantDroits;
    if (ads.isEmpty) {
      await showCreateAyantDroitDialog(context, c);
      return;
    }
    final picked = await showDialog<AyantDroit>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choisir l\'ayant droit'),
        children: [
          for (final ad in ads)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, ad),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Row(children: [
                  Icon(ad == c.ayantDroit ? Icons.radio_button_checked : Icons.radio_button_off, color: Pal.navy, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${ad.fullName} (${ad.strNUMEROSECURITESOCIAL})', maxLines: 2, overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ),
        ],
      ),
    );
    if (picked != null && mounted) c.selectAyantDroit(picked);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.frame;
    final c = context.watch<AssuranceController>();
    final client = c.client;
    if (client == null) {
      return f.scaffold(step: 1, title: 'Couverture', body: const Center(child: Text('Aucun client sélectionné. Veuillez recommencer.')));
    }
    _sync(c);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final canAddTp = client.tiersPayants.length < settings.maxTiersPayants;
    final canToggle = client.tiersPayants.length > 1;

    final tps = List<ClientTiersPayant>.from(client.tiersPayants)
      ..sort((a, b) {
        final aa = c.isActive(a.compteTp), bb = c.isActive(b.compteTp);
        if (aa != bb) return aa ? -1 : 1;
        return a.order.compareTo(b.order);
      });

    final mat = client.strNUMEROSECURITESOCIAL.isEmpty ? '' : ' · Mat. ${client.strNUMEROSECURITESOCIAL}';
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: Pal.navy),
            onPressed: c.busy ? null : widget.onChangeClient,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Changer de client'),
          ),
        ),
        if (c.ayantDroitsError != null)
          LoadErrorBanner(message: 'Ayants droit non chargés : ${venteMessage(c.ayantDroitsError)}', onRetry: c.busy ? null : c.loadAyantDroits),
        AssuranceSectionLabel('Ayant droit (patient)',
            trailing: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, 40), foregroundColor: Pal.navy),
              onPressed: c.busy ? null : () => showCreateAyantDroitDialog(context, c),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Nouvel ayant droit'),
            )),
        _ayantDroitCard(c),
        const SizedBox(height: 10),
        const AssuranceSectionLabel('Tiers payants et N° de bon'),
        for (final tp in tps) Padding(padding: const EdgeInsets.only(bottom: 9), child: _tpCard(c, tp, canToggle)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: Pal.navy),
            icon: const Icon(Icons.add_card),
            label: const Text('Ajouter un tiers payant au client'),
            onPressed: canAddTp && !c.busy ? () => showAddTiersPayantDialog(context, c) : null,
          ),
        ),
        if (!canAddTp)
          Text('Nombre maximum de tiers payants (${settings.maxTiersPayants}) atteint.',
              textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted, fontSize: 12)),
      ],
    );

    final reason = _blockReason(c);
    final message = _error ?? (c.couvertureMessage == null ? null : venteMessage(c.couvertureMessage));
    return f.scaffold(
      step: 1,
      title: 'Couverture',
      subtitle: '${client.fullName}$mat',
      body: body,
      bottom: AssuranceBottomBar(children: [
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(message, key: const ValueKey('assurance-couverture-erreur'), style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600)),
          ),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            key: const ValueKey('assurance-continuer'),
            style: f.mainButton.copyWith(padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10))),
            onPressed: c.busy || reason != null ? null : _continue,
            icon: const Icon(Icons.arrow_forward),
            label: const FittedBox(fit: BoxFit.scaleDown, child: Text('CONTINUER VERS LES PRODUITS')),
          ),
        ),
        if (reason != null && message != reason)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(reason,
                key: const ValueKey('assurance-continuer-raison'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.red.shade700, fontWeight: FontWeight.w500)),
          ),
      ]),
    );
  }

  Widget _ayantDroitCard(AssuranceController c) {
    final ads = c.ayantDroits;
    final selected = c.ayantDroit;
    final band = widget.frame.guided ? (selected == null ? Colors.red.shade400 : Pal.navy) : null;
    final empty = selected == null && ads.isEmpty && c.ayantDroitsError == null && !c.busy;
    return AssuranceCard(
      key: const ValueKey('assurance-ayant-droit'),
      band: band,
      onTap: c.busy ? null : () => _chooseAyantDroit(c),
      child: Row(children: [
        Icon(Icons.person_outline, color: selected == null ? Colors.red.shade700 : Pal.navy),
        const SizedBox(width: 10),
        Expanded(
          child: selected == null
              ? Text(empty ? 'Aucun ayant droit : créez-en un' : 'Choisir l\'ayant droit',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red.shade700))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(selected.fullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Pal.ink)),
                  Text('Mat. ${selected.strNUMEROSECURITESOCIAL.isEmpty ? '—' : selected.strNUMEROSECURITESOCIAL}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
                ]),
        ),
        const SizedBox(width: 8),
        if (ads.isNotEmpty) StatusBadge(selected == null ? 'Choisir' : 'Changer', fg: Pal.navy, bg: const Color(0xFFE3ECF7)),
      ]),
    );
  }

  Widget _tpCard(AssuranceController c, ClientTiersPayant tp, bool canToggle) {
    final active = c.activeTiersPayants.where((a) => a.compteTp == tp.compteTp).firstOrNull;
    final ctrl = _bons[tp.compteTp];
    final focus = _focus[tp.compteTp];
    final missing = active != null && _bonEmpty(tp.compteTp);
    final guided = widget.frame.guided;
    final red = Colors.red.shade700;
    return AssuranceCard(
      color: active != null ? Colors.white : const Color(0xFFF1F4F8),
      band: guided ? (active == null ? Pal.line : (missing ? Pal.amber : Pal.green)) : null,
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Checkbox(
            key: ValueKey('assurance-tp-${tp.compteTp}'),
            value: active != null,
            activeColor: Pal.navy,
            onChanged: canToggle && !c.busy && !(active != null && c.activeTiersPayants.length <= 1)
                ? (v) => c.toggleTiersPayant(tp, v ?? false)
                : null,
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tp.tpFullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: Pal.ink)),
              Text(active == null ? 'Non utilisé · ${tp.taux} %' : 'Mat. ${tp.numSecurity.isEmpty ? '—' : tp.numSecurity}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Pal.muted)),
            ]),
          ),
          if (active != null)
            Tooltip(
              message: 'Taux / changer l\'assurance',
              child: OutlinedButton(
                key: ValueKey('assurance-taux-${tp.compteTp}'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  foregroundColor: Pal.navy,
                  side: const BorderSide(color: Color(0xFFC5D0DE)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: c.busy ? null : () => _editTp(c, active),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${active.taux} %', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_outlined, size: 16),
                ]),
              ),
            ),
        ]),
        if (active != null && ctrl != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 0, 0),
            child: TextFormField(
              key: ValueKey('assurance-bon-${tp.compteTp}'),
              controller: ctrl,
              focusNode: focus,
              inputFormatters: VenteInput.bonFormatters,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: missing ? 'N° de bon — obligatoire' : 'N° de bon *',
                labelStyle: TextStyle(color: missing ? red : Pal.muted),
                floatingLabelStyle: TextStyle(color: missing ? red : Pal.navy),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: missing ? red : const Color(0xFFC5D0DE), width: missing ? 1.5 : 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: missing ? red : Pal.navy, width: 2),
                ),
              ),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() => _error = null),
              onFieldSubmitted: (_) => _continue(),
            ),
          ),
      ]),
    );
  }
}
