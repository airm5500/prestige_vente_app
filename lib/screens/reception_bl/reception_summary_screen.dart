// lib/screens/reception_bl/reception_summary_screen.dart
// Bilan du BL avant l'entrée en stock : lignes non saisies, incomplètes, péremptions courtes ou manquantes.
// Validation possible sur ce terminal seulement si le paramètre est actif ET si l'utilisateur a le droit
// « entrée en stock » sur Prestige ; sinon le BL est laissé pour validation sur Prestige.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

class ReceptionSummaryScreen extends StatefulWidget {
  final ReceptionBl bl;
  final ReceptionGateway gateway;
  final ReceptionSettings settings;
  final List<ReceptionLine> lines;
  final DateTime Function()? clock;
  final ListPresentation? presentation;

  const ReceptionSummaryScreen({
    super.key,
    required this.bl,
    required this.gateway,
    required this.settings,
    required this.lines,
    this.clock,
    this.presentation,
  });

  @override
  State<ReceptionSummaryScreen> createState() => _ReceptionSummaryScreenState();
}

class _ReceptionSummaryScreenState extends State<ReceptionSummaryScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  static final _fmt = DateFormat('dd/MM/yyyy');
  bool? _authorized;
  bool _validating = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    loadPresentation();
    if (widget.settings.terminalValidation) {
      widget.gateway.canValidate().then((v) {
        if (mounted) setState(() => _authorized = v);
      });
    }
  }

  Future<void> _validate(ReceptionSummary s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Valider l\'entrée en stock ?'),
        content: Text([
          'BL ${widget.bl.ref} — ${widget.bl.grossiste}',
          '${s.enteredBoxes} boîte(s) saisie(s) sur ${s.orderedBoxes}.',
          if (s.notEntered.isNotEmpty)
            '\nATTENTION : ${s.notEntered.length} ligne(s) non saisie(s) entreront en stock avec la quantité commandée.',
          '\nLe stock sera mis à jour : cette opération ne peut pas être annulée depuis le mobile.',
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Valider')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _validating = true);
    final r = await widget.gateway.validate(widget.bl.id);
    if (!mounted) return;
    setState(() => _validating = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(r.success ? Icons.check_circle : Icons.error, color: r.success ? Colors.green : Colors.red, size: 40),
        title: Text(r.success ? 'Entrée en stock effectuée' : 'Entrée en stock refusée'),
        content: Text(r.message),
        actions: [ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );
    if (r.success && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = ReceptionSummary.of(widget.lines, now: _now(), shortExpiryMonths: widget.settings.shortExpiryMonths);
    final requireDates = !widget.bl.peremptionOptional;
    final blockedReasons = <String>[
      if (s.partial.isNotEmpty) '${s.partial.length} ligne(s) commencée(s) mais incomplète(s) : Prestige refusera l\'entrée en stock.',
      if (requireDates && s.missingExpiry.isNotEmpty) 'Dates de péremption manquantes : Prestige refusera l\'entrée en stock.',
    ];
    final canValidateHere = widget.settings.terminalValidation && _authorized == true && blockedReasons.isEmpty;

    return PresentationScaffold(
      style: style,
      title: 'Bilan BL ${widget.bl.ref}',
      subtitle: widget.bl.grossiste,
      actions: (_) => const [],
      steps: StepsBar(active: 2, steps: const [
        (title: 'Commande', detail: 'BL créé', onTap: null),
        (title: 'Saisie BL', detail: 'terminée', onTap: null),
        (title: 'Stock', detail: 'vérification', onTap: null),
      ]),
      header: [
        Row(children: [
          Expanded(child: KpiTile('${s.lines.length}', 'lignes')),
          const SizedBox(width: 6),
          Expanded(child: KpiTile('${s.complete.length}', 'complètes')),
          const SizedBox(width: 6),
          Expanded(child: KpiTile('${s.partial.length}', 'incomplètes', highlight: s.partial.isNotEmpty)),
          const SizedBox(width: 6),
          Expanded(child: KpiTile('${s.notEntered.length}', 'non saisies', highlight: s.notEntered.isNotEmpty)),
        ]),
        Text('${s.enteredBoxes} boîte(s) saisie(s) sur ${s.orderedBoxes} commandée(s).',
            style: const TextStyle(color: Colors.white, fontSize: 13)),
      ],
      compactHeader: [
        LightFigures([
          ('${s.lines.length}', 'Lignes', Pal.navy),
          ('${s.complete.length}', 'Complètes', Colors.green.shade700),
          ('${s.partial.length}', 'Incomplètes', Colors.orange.shade800),
          ('${s.notEntered.length}', 'Non saisies', Colors.red.shade700),
        ]),
        Text('${s.enteredBoxes} boîte(s) saisie(s) sur ${s.orderedBoxes} commandée(s).', style: const TextStyle(fontSize: 13)),
      ],
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Ce qui empêche l'entrée en stock, en premier.
          for (final r in blockedReasons)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.block, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(r, style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.w600))),
              ]),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: const Text('Continuer la saisie'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ),
          if (widget.settings.terminalValidation && _authorized == false)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Votre compte n\'a pas le droit « Entrée en stock » sur Prestige.', style: TextStyle(color: Colors.red.shade700)),
            ),
          if (s.notEntered.isNotEmpty)
            _section(
              'Non saisies (${s.notEntered.length})',
              'Sans lot saisi, Prestige les entre en stock avec la QUANTITÉ COMMANDÉE.',
              Colors.red.shade700,
              Icons.report_gmailerrorred,
              [for (final l in s.notEntered) '${l.name} — ${l.ordered} commandée(s)'],
            ),
          if (s.partial.isNotEmpty)
            _section(
              'Incomplètes (${s.partial.length})',
              'Complétez la saisie, ou corrigez la quantité du BL sur Prestige (manquants).',
              Colors.orange.shade800,
              Icons.timelapse,
              [for (final l in s.partial) '${l.name} — ${l.entered}/${l.ordered}'],
            ),
          if (s.shortExpiries.isNotEmpty)
            _section(
              'Péremptions courtes (< ${widget.settings.shortExpiryMonths} mois)',
              null,
              Colors.deepOrange,
              Icons.event_busy,
              [
                for (final e in s.shortExpiries)
                  '${e.line.name} — exp. ${_fmt.format(e.expiry)} (${e.expiry.difference(_now()).inDays} j)',
              ],
            ),
          if (s.missingExpiry.isNotEmpty)
            _section(
              'Sans date de péremption (${s.missingExpiry.length})',
              requireDates ? 'Date obligatoire sur cette officine.' : null,
              requireDates ? Colors.red.shade700 : Colors.blueGrey,
              Icons.event_note,
              [for (final l in s.missingExpiry) l.name],
            ),
          if (s.notEntered.isEmpty && s.partial.isEmpty && s.shortExpiries.isEmpty && s.missingExpiry.isEmpty)
            const SoftCard(
              child: Row(children: [
                Icon(Icons.verified, color: Pal.green),
                SizedBox(width: 10),
                Expanded(child: Text('Toutes les lignes sont saisies et conformes.', style: TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ),
        ],
      ),
      // Décisions toujours visibles en bas de l'écran.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.settings.terminalValidation) ...[
              if (_authorized == null) const LinearProgressIndicator(minHeight: 2),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  style: style == ListPresentation.guided ? amberButton : navyButton,
                  icon: _validating
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.inventory),
                  label: const Text('Valider l\'entrée en stock'),
                  onPressed: canValidateHere && !_validating ? () => _validate(s) : null,
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                style: outlineButton,
                icon: const Icon(Icons.schedule_send),
                label: const Text('Laisser pour validation sur Prestige'),
                onPressed: _validating
                    ? null
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('BL ${widget.bl.ref} enregistré : à valider sur Prestige.')),
                        );
                        Navigator.of(context).pop(true);
                      },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _section(String title, String? note, Color color, IconData icon, List<String> rows) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SoftCard(
          padding: EdgeInsets.zero,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: rows.length <= 5,
              leading: Icon(icon, color: color),
              title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              subtitle: note == null ? null : Text(note, style: const TextStyle(fontSize: 12)),
              children: [
                for (final r in rows) ListTile(dense: true, title: Text(r)),
              ],
            ),
          ),
        ),
      );
}
