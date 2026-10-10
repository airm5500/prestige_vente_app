// lib/ventes/assurance/assurance_step_couverture.dart
// Étape 2 : ayant droit (obligatoire, défaut n°11), tiers payants (taux 0-100) et N° de bon
// (obligatoires, nettoyés, sans doublon). Boutons libellés.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_controller.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_dialogs.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

class AssuranceStepCouverture extends StatefulWidget {
  /// « Changer de client » (confirmation faite par l'écran).
  final VoidCallback onChangeClient;
  const AssuranceStepCouverture({super.key, required this.onChangeClient});

  @override
  State<AssuranceStepCouverture> createState() => _AssuranceStepCouvertureState();
}

class _AssuranceStepCouvertureState extends State<AssuranceStepCouverture> {
  final Map<String, TextEditingController> _bons = {};
  final Map<String, FocusNode> _focus = {};

  /// Erreur de saisie affichée au-dessus du bouton (un bandeau bas le masquerait).
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

  void _focusFirstEmpty() {
    if (!mounted) return;
    final c = context.read<AssuranceController>();
    for (final tp in c.activeTiersPayants) {
      if (VenteInput.cleanBon(_bons[tp.compteTp]?.text).isEmpty) {
        _focus[tp.compteTp]?.requestFocus();
        return;
      }
    }
  }

  void _continue() {
    final c = context.read<AssuranceController>();
    final err = c.validateCouverture(_bonValues);
    setState(() => _error = err);
    if (err != null) _focusFirstEmpty();
  }

  Future<void> _editTp(AssuranceController c, ActiveTiersPayant tp) async {
    await showEditTiersPayantDialog(context, c, tp);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirstEmpty());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AssuranceController>();
    final client = c.client;
    if (client == null) return const Center(child: Text('Aucun client sélectionné. Veuillez recommencer.'));
    _sync(c);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final canAddTp = client.tiersPayants.length < settings.maxTiersPayants;
    final canToggle = client.tiersPayants.length > 1;
    final ads = c.ayantDroits;
    final selected = c.ayantDroit != null && ads.contains(c.ayantDroit) ? c.ayantDroit : null;

    final tps = List<ClientTiersPayant>.from(client.tiersPayants)
      ..sort((a, b) {
        final aa = c.isActive(a.compteTp), bb = c.isActive(b.compteTp);
        if (aa != bb) return aa ? -1 : 1;
        return a.order.compareTo(b.order);
      });

    final form = SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.person, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(client.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Matricule : ${client.strNUMEROSECURITESOCIAL}', style: const TextStyle(fontSize: 12)),
                  ]),
                ),
              ]),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: c.busy ? null : widget.onChangeClient,
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Changer de client'),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text('1. Ayant droit (patient)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        if (c.ayantDroitsError != null)
          LoadErrorBanner(message: 'Ayants droit non chargés : ${venteMessage(c.ayantDroitsError)}', onRetry: c.busy ? null : c.loadAyantDroits),
        DropdownButtonFormField<AyantDroit>(
          key: const ValueKey('assurance-ayant-droit'),
          value: selected,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Ayant droit *',
            border: const OutlineInputBorder(),
            errorText: selected == null && ads.isEmpty && c.ayantDroitsError == null && !c.busy ? 'Aucun ayant droit : créez-en un' : null,
          ),
          hint: const Text('Choisir l\'ayant droit'),
          items: [
            for (final ad in ads)
              DropdownMenuItem<AyantDroit>(value: ad, child: Text('${ad.fullName} (${ad.strNUMEROSECURITESOCIAL})', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: c.busy ? null : c.selectAyantDroit,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: c.busy ? null : () => showCreateAyantDroitDialog(context, c),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Nouvel ayant droit'),
          ),
        ),
        const SizedBox(height: 8),
        Text('2. Tiers payants et N° de bon', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final tp in tps) _tpCard(c, tp, canToggle),
        TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
          icon: const Icon(Icons.add_card),
          label: const Text('Ajouter un tiers payant au client'),
          onPressed: canAddTp && !c.busy ? () => showAddTiersPayantDialog(context, c) : null,
        ),
        if (!canAddTp)
          Text('Nombre maximum de tiers payants (${settings.maxTiersPayants}) atteint.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
      ]),
    );
    // Bouton toujours visible (pied fixe), même sur un petit écran.
    return Column(children: [
      Expanded(child: form),
      Material(
        elevation: 6,
        color: Colors.white,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if ((_error ?? c.couvertureMessage) != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(_error ?? venteMessage(c.couvertureMessage), key: const ValueKey('assurance-couverture-erreur'), style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600)),
                ),
              ElevatedButton.icon(
                key: const ValueKey('assurance-continuer'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: c.busy ? null : _continue,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continuer vers les produits'),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _tpCard(AssuranceController c, ClientTiersPayant tp, bool canToggle) {
    final active = c.activeTiersPayants.where((a) => a.compteTp == tp.compteTp).firstOrNull;
    final ctrl = _bons[tp.compteTp];
    final focus = _focus[tp.compteTp];
    return Card(
      color: active != null ? Colors.white : Colors.grey.shade200,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(children: [
        CheckboxListTile(
          title: Text('${tp.tpFullName} (${active?.taux ?? tp.taux} %)', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('Matricule : ${tp.numSecurity}'),
          value: active != null,
          onChanged: canToggle && !c.busy && !(active != null && c.activeTiersPayants.length <= 1)
              ? (v) => c.toggleTiersPayant(tp, v ?? false)
              : null,
        ),
        if (active != null && ctrl != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
            child: Row(children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('assurance-bon-${tp.compteTp}'),
                  controller: ctrl,
                  focusNode: focus,
                  inputFormatters: VenteInput.bonFormatters,
                  decoration: InputDecoration(labelText: 'N° de bon * (${tp.tpFullName})', border: const OutlineInputBorder(), isDense: true),
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _continue(),
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: c.busy ? null : () => _editTp(c, active),
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Modifier'),
              ),
            ]),
          ),
      ]),
    );
  }
}
