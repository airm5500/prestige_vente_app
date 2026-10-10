// lib/screens/reception_bl/reception_summary_screen.dart
// Bilan du BL avant l'entrée en stock : lignes non saisies, incomplètes, péremptions courtes ou manquantes.
// Validation possible sur ce terminal seulement si le paramètre est actif ET si l'utilisateur a le droit
// « entrée en stock » sur Prestige ; sinon le BL est laissé pour validation sur Prestige.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';

class ReceptionSummaryScreen extends StatefulWidget {
  final ReceptionBl bl;
  final ReceptionGateway gateway;
  final ReceptionSettings settings;
  final List<ReceptionLine> lines;
  final DateTime Function()? clock;

  const ReceptionSummaryScreen({
    super.key,
    required this.bl,
    required this.gateway,
    required this.settings,
    required this.lines,
    this.clock,
  });

  @override
  State<ReceptionSummaryScreen> createState() => _ReceptionSummaryScreenState();
}

class _ReceptionSummaryScreenState extends State<ReceptionSummaryScreen> {
  static final _fmt = DateFormat('dd/MM/yyyy');
  bool? _authorized;
  bool _validating = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
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

    return Scaffold(
      appBar: AppBar(title: Text('Bilan BL ${widget.bl.ref}')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _kpi('Lignes', '${s.lines.length}', Colors.blueGrey),
                  _kpi('Complètes', '${s.complete.length}', Colors.green.shade700),
                  _kpi('Incomplètes', '${s.partial.length}', Colors.orange.shade800),
                  _kpi('Non saisies', '${s.notEntered.length}', Colors.red.shade700),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('${s.enteredBoxes} boîte(s) saisie(s) sur ${s.orderedBoxes} commandée(s).', textAlign: TextAlign.center),
          ),
          if (s.notEntered.isNotEmpty)
            _section(
              'Non saisies (${s.notEntered.length})',
              'Sans lot saisi, Prestige les entre en stock avec la QUANTITÉ COMMANDÉE.',
              Colors.red.shade700,
              [for (final l in s.notEntered) '${l.name} — ${l.ordered} commandée(s)'],
            ),
          if (s.partial.isNotEmpty)
            _section(
              'Incomplètes (${s.partial.length})',
              'Complétez la saisie, ou corrigez la quantité du BL sur Prestige (manquants).',
              Colors.orange.shade800,
              [for (final l in s.partial) '${l.name} — ${l.entered}/${l.ordered}'],
            ),
          if (s.shortExpiries.isNotEmpty)
            _section(
              'Péremptions courtes (< ${widget.settings.shortExpiryMonths} mois)',
              null,
              Colors.deepOrange,
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
              [for (final l in s.missingExpiry) l.name],
            ),
          const SizedBox(height: 16),
          for (final r in blockedReasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(r, style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600)),
            ),
          if (widget.settings.terminalValidation) ...[
            if (_authorized == null) const LinearProgressIndicator(),
            if (_authorized == false)
              Text('Votre compte n\'a pas le droit « Entrée en stock » sur Prestige.', style: TextStyle(color: Colors.red.shade700)),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                icon: _validating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.inventory),
                label: const Text('Valider l\'entrée en stock'),
                onPressed: canValidateHere && !_validating ? () => _validate(s) : null,
              ),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
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
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Continuer la saisie')),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, Color color) => Column(children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);

  Widget _section(String title, String? note, Color color, List<String> rows) => Card(
        child: ExpansionTile(
          initiallyExpanded: rows.length <= 5,
          title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          subtitle: note == null ? null : Text(note, style: const TextStyle(fontSize: 12)),
          children: [
            for (final r in rows) ListTile(dense: true, title: Text(r)),
          ],
        ),
      );
}
