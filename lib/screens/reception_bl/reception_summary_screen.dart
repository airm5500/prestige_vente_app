// lib/screens/reception_bl/reception_summary_screen.dart
// Bilan du BL avant l'entrée en stock : lignes non saisies, incomplètes, péremptions courtes ou manquantes.
// Validation possible sur ce terminal seulement si le paramètre est actif ET si l'utilisateur a le droit
// « entrée en stock » sur Prestige ; sinon le BL est laissé pour validation sur Prestige.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_ui.dart';
import 'package:prestige_vente_app/reception/manquants_bl.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/screens/reception_bl/bilan_recu_dialog.dart';
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

  /// 4.11.0 (demande 59) : le serveur sait entrer seulement ce qui a été reçu ; null = pas encore lu.
  bool? _clotureRecu;

  /// 4.12.0 (demande 59) : le serveur sait relire les écarts et créer le retour des manquants ; null = pas encore lu.
  bool? _retourManquants;

  /// Clé `X-Client-Ref` de la clôture « au reçu » : la même pour chaque essai sur ce bilan (un délai dépassé puis un
  /// nouvel essai n'entrent jamais deux fois ; un refus n'est pas gardé par le serveur).
  final String _cleRecu = nouvelleCleClotureRecu();

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    loadPresentation();
    if (widget.settings.terminalValidation) {
      widget.gateway.canValidate().then((v) {
        if (mounted) setState(() => _authorized = v);
      });
      final g = widget.gateway;
      if (g is ClotureRecuGateway) {
        (g as ClotureRecuGateway).clotureRecuDisponible().then((v) {
          if (mounted) setState(() => _clotureRecu = v);
        });
      }
      if (g is RetourManquantsGateway) {
        (g as RetourManquantsGateway).retourManquantsDisponible().then((v) {
          if (mounted) setState(() => _retourManquants = v);
        });
      }
    }
  }

  /// 4.11.0 (plan du 08/11) : BL incomplet entré « au reçu » : seulement les lots saisis entrent en stock, les lignes
  /// non saisies n'entrent pas (0) ; l'écart (commandé − reçu) va au rapport.
  Future<void> _validateRecu(ReceptionSummary s) async {
    final ecarts = [...s.partial, ...s.notEntered];
    var nbEcarts = ecarts.length;
    var manquant = ecarts.fold<int>(0, (t, l) => t + (l.ordered - l.entered).clamp(0, l.ordered));
    // 4.12.0 : écarts PROVISOIRES calculés par Prestige sur les lots enregistrés (même règle que la clôture) ; en cas
    // d'échec de lecture, le calcul de l'écran (4.11.0).
    final mg = widget.gateway;
    if (_retourManquants == true && mg is RetourManquantsGateway) {
      setState(() => _validating = true);
      final p = await (mg as RetourManquantsGateway).ecartsBl(widget.bl.id);
      if (!mounted) return;
      setState(() => _validating = false);
      if (p.success && p.provisoire) {
        nbEcarts = p.ecarts.length;
        manquant = p.totalManquant;
      }
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('bl_cloture_recu_confirmation'),
        title: const Text('Entrer ce qui a été reçu ?'),
        content: Text([
          'BL ${widget.bl.ref} — ${widget.bl.grossiste}',
          '${s.enteredBoxes} boîte(s) reçue(s) sur ${s.orderedBoxes} commandée(s).',
          '\nSeules les boîtes saisies entrent en stock. $nbEcarts ligne(s) en écart, $manquant boîte(s) manquante(s) : '
              'l\'écart va au rapport du BL.',
          '\nLe stock sera mis à jour : cette opération ne peut pas être annulée depuis le mobile.',
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Entrer le reçu')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _validating = true);
    final r = await (widget.gateway as ClotureRecuGateway).validateRecu(widget.bl.id, clientRef: _cleRecu);
    if (!mounted) return;
    setState(() => _validating = false);
    // 4.12.0 : aucune ligne n'a de lot : rien n'est entré, le BL reste ouvert (on reste sur le bilan).
    if (estAucunRecu(r)) {
      await afficherAucunRecu(context, r);
      return;
    }
    if (!r.success) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const Key('bl_cloture_recu_refus'),
          icon: const Icon(Icons.error, color: Colors.red, size: 40),
          title: const Text('Entrée en stock refusée'),
          content: Text(r.message),
          actions: [ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BilanRecuDialog(
        bl: widget.bl,
        resultat: r,
        manquants: _retourManquants == true && mg is RetourManquantsGateway ? mg as RetourManquantsGateway : null,
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
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
    // 4.6.0 (décision 12) : entrée en stock refusée, produits non saisis nommés par le serveur.
    final manquants = produitsNonSaisis(r);
    if (manquants != null) {
      await afficherProduitsNonSaisis(context, manquants);
      return;
    }
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
    // 4.11.0 (demande 59) : BL incomplet (lignes incomplètes ou non saisies) entré « au reçu » si le serveur le sait.
    final incomplet = s.partial.isNotEmpty || s.notEntered.isNotEmpty;
    final datesBloquent = requireDates && s.missingExpiry.any((l) => l.entered > 0);
    final canRecuHere = widget.settings.terminalValidation && _authorized == true && _clotureRecu == true && incomplet && !datesBloquent;

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
          if (incomplet)
            _section(
              'Écarts reçu / BL (${s.partial.length + s.notEntered.length})',
              _clotureRecu == true
                  ? '« Entrer le reçu » : seules les boîtes saisies entrent en stock ; l\'écart va au rapport du BL.'
                  : 'Ce serveur Prestige n\'entre pas encore un BL incomplet : laissez-le ouvert (rien n\'est entré), '
                      'complétez-le, ou corrigez les quantités du BL sur Prestige.',
              Colors.orange.shade900,
              Icons.difference_outlined,
              [
                for (final l in [...s.partial, ...s.notEntered])
                  '${l.name} — reçu ${l.entered}/${l.ordered}, manquant ${(l.ordered - l.entered).clamp(0, l.ordered)}',
              ],
              cle: 'bl_ecarts',
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
              if (HorsLigne.instance.offline) const EnLigneUniquementNote(action: 'Entrée en stock'),
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
              if (canRecuHere) ...[
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    key: const Key('bl_entrer_recu'),
                    style: style == ListPresentation.guided ? amberButton : navyButton,
                    icon: const Icon(Icons.difference_outlined),
                    label: const Text('Entrer le reçu (écart au rapport)'),
                    onPressed: _validating || HorsLigne.instance.offline ? null : () => _validateRecu(s),
                  ),
                ),
                const SizedBox(height: 8),
              ],
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

  Widget _section(String title, String? note, Color color, IconData icon, List<String> rows, {String? cle}) => Padding(
        key: cle == null ? null : Key(cle),
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

/// 4.6.0 (décision 12) : refus `PRODUITS_NON_SAISIS` de l'entrée en stock — liste des produits à saisir, lisible et
/// défilable (petits écrans : hauteur bornée, une ligne par produit, texte qui passe à la ligne).
Future<void> afficherProduitsNonSaisis(BuildContext context, List<String> produits) => showDialog<void>(
      context: context,
      builder: (ctx) {
        final hauteur = MediaQuery.sizeOf(ctx).height;
        return AlertDialog(
          key: const Key('bl_produits_non_saisis'),
          icon: const Icon(Icons.error, color: Colors.red, size: 36),
          title: const Text('Entrée en stock refusée'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${produits.length} produit${produits.length > 1 ? 's' : ''} non saisi${produits.length > 1 ? 's' : ''} : '
                  'saisissez leurs lots puis validez à nouveau.'),
              const SizedBox(height: 8),
              // Flexible : sur un petit écran, la liste prend la place restante et défile (jamais de débordement).
              Flexible(
                child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: hauteur * 0.45),
                child: Scrollbar(
                  thumbVisibility: produits.length > 6,
                  child: ListView.separated(
                    key: const Key('bl_produits_non_saisis_liste'),
                    shrinkWrap: true,
                    itemCount: produits.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Padding(padding: EdgeInsets.only(top: 2, right: 6), child: Icon(Icons.inventory_2_outlined, size: 18)),
                        Expanded(child: Text(produits[i], style: const TextStyle(fontSize: 14))),
                      ]),
                    ),
                  ),
                ),
              ),
              ),
            ]),
          ),
          actions: [ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        );
      },
    );
