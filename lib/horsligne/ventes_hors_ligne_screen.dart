// lib/horsligne/ventes_hors_ligne_screen.dart
// Écran « Ventes hors ligne » (étape H2) : liste des ventes saisies hors ligne (HL, montant, statut,
// référence serveur une fois envoyée), « Envoyer maintenant », détail d'une vente avec ses actions :
// renvoyer, ouvrir la vente sur le serveur (prévente comptant), marquer comme traitée, supprimer
// (seulement si rien n'existe sur le serveur, avec confirmation). Tablette paysage : liste + détail.
// Aucun envoi sans accord : confirmation avec la liste des ventes (décocher celles déjà ressaisies).
// Accès aux rapports : anomalies de synchronisation, fin de journée.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/rapports_hl_screen.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/common/vente_dialogs.dart';
import 'package:prestige_vente_app/ventes/ventes_version.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

/// Ouvre l'écran (depuis un écran de l'appli, ou depuis le bandeau global sans contexte de navigation).
Future<void> ouvrirVentesHorsLigne([BuildContext? context]) async {
  final nav = (context == null ? null : Navigator.maybeOf(context)) ?? HorsLigne.navigatorKey.currentState;
  await nav?.push(MaterialPageRoute(builder: (_) => const VentesHorsLigneScreen()));
}

/// Confirmation AVANT tout envoi : liste des ventes (HL, heure, montant, articles), à décocher si déjà
/// ressaisies sur le serveur (elles passent « ressaisie », jamais envoyées). [seulement] : ventes proposées.
Future<void> confirmerEnvoiVentes(BuildContext context, {HorsLigne? horsLigne, Iterable<String>? seulement}) async {
  final f = (horsLigne ?? HorsLigne.instance).ventes;
  await f.ensureLoaded();
  final ids = seulement?.toSet();
  final ventes = f.ventes.where((v) => v.aFaire && (ids == null || ids.contains(v.id))).toList();
  if (ventes.isEmpty || !context.mounted) {
    f.confirmationVue();
    return;
  }
  final choix = await showDialog<Set<String>>(context: context, barrierDismissible: false, builder: (_) => _ConfirmationEnvoi(ventes: ventes));
  f.confirmationVue();
  if (choix == null) return; // Plus tard
  await f.exclure([for (final v in ventes) if (!choix.contains(v.id)) v.id]);
  if (choix.isNotEmpty) await f.envoyer(ids: choix);
}

/// Confirmation demandée par le retour du serveur, affichée depuis le bandeau global.
Future<void> confirmerEnvoiGlobal(HorsLigne hl) async {
  final nav = HorsLigne.navigatorKey.currentState;
  final ctx = nav?.overlay?.context ?? nav?.context;
  if (ctx == null) return;
  await confirmerEnvoiVentes(ctx, horsLigne: hl);
}

class _ConfirmationEnvoi extends StatefulWidget {
  final List<VenteHorsLigne> ventes;
  const _ConfirmationEnvoi({required this.ventes});

  @override
  State<_ConfirmationEnvoi> createState() => _ConfirmationEnvoiState();
}

class _ConfirmationEnvoiState extends State<_ConfirmationEnvoi> {
  late final Set<String> _coches = {for (final v in widget.ventes) v.id};

  @override
  Widget build(BuildContext context) {
    final n = widget.ventes.length;
    final exclues = n - _coches.length;
    return AlertDialog(
      key: const Key('confirmation_envoi'),
      scrollable: true,
      title: Text('Envoyer $n vente(s) hors ligne au serveur ?'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Vérifiez qu\'elles n\'ont pas déjà été ressaisies directement sur le serveur (risque de double sortie de stock). '
              'Décochez celles déjà ressaisies : elles seront gardées dans l\'historique, jamais envoyées.',
              style: TextStyle(fontSize: 13.5)),
          const SizedBox(height: 8),
          Column(
            children: [
              for (final v in widget.ventes)
                CheckboxListTile(
                  key: Key('coche_${v.numeroLabel}'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _coches.contains(v.id),
                  onChanged: (c) => setState(() => c == true ? _coches.add(v.id) : _coches.remove(v.id)),
                  title: Text('${v.numeroLabel} · ${DateFormat('HH:mm').format(v.createdAt)} · ${_f(v.netEstime)}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                    '${v.type.label} · ${v.lignes.length} article(s) : ${v.lignes.map((l) => '${l.qte}× ${l.nom}').join(', ')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
            ],
          ),
          if (exclues > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('$exclues vente(s) décochée(s) : marquée(s) « ressaisie sur le serveur », non envoyée(s).',
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF9A3412))),
            ),
        ]),
      ),
      actions: [
        TextButton(
          key: const Key('envoi_plus_tard'),
          style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Plus tard'),
        ),
        ElevatedButton(
          key: const Key('envoyer_selection'),
          style: ElevatedButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.of(context).pop(Set<String>.of(_coches)),
          child: const Text('Envoyer la sélection'),
        ),
      ],
    );
  }
}

String _f(int v) => '${Constants.formatNumber(v)} F';
String _date(DateTime d) => DateFormat('dd/MM HH:mm').format(d);

({Color fg, Color bg, IconData icon}) _look(StatutVenteHL s) => switch (s) {
      StatutVenteHL.enAttente => (fg: const Color(0xFF8A5300), bg: const Color(0xFFFFF1D6), icon: Icons.schedule),
      StatutVenteHL.envoiEnCours => (fg: const Color(0xFF1F4F8F), bg: const Color(0xFFE3ECF7), icon: Icons.sync),
      StatutVenteHL.envoyee => (fg: const Color(0xFF0B6B45), bg: const Color(0xFFDCF5E7), icon: Icons.cloud_done),
      StatutVenteHL.aVerifier => (fg: const Color(0xFFB91C1C), bg: const Color(0xFFFDECEC), icon: Icons.report_problem_outlined),
      StatutVenteHL.traitee => (fg: const Color(0xFF3D4B60), bg: const Color(0xFFE6EBF2), icon: Icons.task_alt),
      StatutVenteHL.ressaisie => (fg: const Color(0xFF3D4B60), bg: const Color(0xFFE6EBF2), icon: Icons.do_not_disturb_on_outlined),
    };

String _finLabel(VenteHorsLigne v) => v.fin == FinVenteHL.especes ? 'encaissée en espèces (provisoire)' : 'prévente provisoire';

class VentesHorsLigneScreen extends StatefulWidget {
  /// Instance utilisée (tests) ; sinon [HorsLigne.instance].
  final HorsLigne? horsLigne;
  const VentesHorsLigneScreen({super.key, this.horsLigne});

  @override
  State<VentesHorsLigneScreen> createState() => _VentesHorsLigneScreenState();
}

class _VentesHorsLigneScreenState extends State<VentesHorsLigneScreen> {
  HorsLigne get _hl => widget.horsLigne ?? HorsLigne.instance;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _hl.ventes.ensureLoaded();
  }

  /// À vérifier d'abord, puis à envoyer (ordre de saisie), puis envoyées / traitées (plus récentes d'abord).
  List<VenteHorsLigne> _ordre(List<VenteHorsLigne> all) {
    int rang(VenteHorsLigne v) => switch (v.statut) {
          StatutVenteHL.aVerifier => 0,
          StatutVenteHL.envoiEnCours || StatutVenteHL.enAttente => 1,
          _ => 2,
        };
    final list = List.of(all);
    list.sort((a, b) {
      final r = rang(a).compareTo(rang(b));
      if (r != 0) return r;
      return rang(a) == 2 ? b.numero.compareTo(a.numero) : a.numero.compareTo(b.numero);
    });
    return list;
  }

  Future<void> _ouvrir(VenteHorsLigne v, bool split) async {
    if (split) {
      setState(() => _selected = v.id);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Pal.page,
        appBar: AppBar(title: Text(v.numeroLabel)),
        body: ListenableBuilder(
          listenable: _hl.ventes,
          builder: (context, _) {
            final cur = _hl.ventes.byId(v.id);
            if (cur == null) return const Center(child: Text('Vente supprimée.'));
            return VenteHorsLigneDetail(vente: cur, horsLigne: _hl, onDeleted: () => Navigator.of(context).maybePop());
          },
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hl = _hl;
    return ListenableBuilder(
      listenable: Listenable.merge([hl.ventes, hl.monitor]),
      builder: (context, _) {
        final f = hl.ventes;
        final ventes = _ordre(f.ventes);
        final split = Responsive.isExpanded(context);
        final list = ListView(
          key: const Key('liste_ventes_hl'),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            _entete(hl),
            const SizedBox(height: 12),
            if (f.storeError != null) _note(f.storeError!, error: true),
            if (f.loaded && ventes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Column(children: [
                  Icon(Icons.cloud_done_outlined, size: 56, color: Color(0xFF9AA8BC)),
                  SizedBox(height: 10),
                  Text('Aucune vente hors ligne', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Pal.ink)),
                ]),
              ),
            for (final v in ventes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _VenteTile(vente: v, selected: split && _selected == v.id, onTap: () => _ouvrir(v, split)),
              ),
          ],
        );
        final sel = _selected == null ? null : f.byId(_selected!);
        return Scaffold(
          backgroundColor: Pal.page,
          appBar: AppBar(title: const Text('Ventes hors ligne')),
          body: SafeArea(
            top: false,
            child: !split
                ? list
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 420, child: list),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: sel == null
                          ? const Center(child: Text('Choisissez une vente.', style: TextStyle(color: Pal.muted)))
                          : VenteHorsLigneDetail(
                              key: ValueKey(sel.id), vente: sel, horsLigne: hl, onDeleted: () => setState(() => _selected = null)),
                    ),
                  ]),
          ),
        );
      },
    );
  }

  Widget _entete(HorsLigne hl) {
    final f = hl.ventes;
    final m = hl.monitor;
    final envoyees = f.ventes.where((v) => v.statut == StatutVenteHL.envoyee).length;
    final etat = switch (m.etat) {
      EtatServeur.enLigne => 'Serveur joignable',
      EtatServeur.injoignable => 'Serveur injoignable',
      EtatServeur.horsLigne => 'Hors ligne',
    };
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(m.etat == EtatServeur.enLigne ? Icons.cloud_done : Icons.cloud_off,
              color: m.etat == EtatServeur.enLigne ? Pal.green : const Color(0xFFB45309), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(etat, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink))),
        ]),
        const SizedBox(height: 6),
        Text('${f.enAttente} en attente · ${f.aVerifier} à vérifier · $envoyees envoyée(s)',
            key: const Key('compteurs_ventes_hl'), style: const TextStyle(fontSize: 13, color: Pal.muted)),
        if (f.running) ...[
          const SizedBox(height: 8),
          Text('Envoi ${f.index}/${f.total}…', key: const Key('envoi_progression'), style: const TextStyle(fontSize: 13, color: Pal.navy)),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: f.total == 0 ? null : f.index / f.total, color: Pal.navy, backgroundColor: Pal.line),
        ],
        if (!f.running && f.panne != null) ...[const SizedBox(height: 8), _note('Envoi arrêté : ${f.panne}. Nouvel essai au retour du serveur.', error: true)],
        const SizedBox(height: 10),
        ElevatedButton.icon(
          key: const Key('envoyer_maintenant'),
          style: navyButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48))),
          onPressed: f.running || f.enAttente == 0 ? null : () => confirmerEnvoiVentes(context, horsLigne: hl),
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('Envoyer maintenant'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('ouvrir_anomalies'),
              style: outlineButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 44))),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnomaliesHorsLigneScreen(horsLigne: hl))),
              icon: const Icon(Icons.report_problem_outlined, size: 18),
              label: FittedBox(fit: BoxFit.scaleDown, child: Text('Anomalies (${f.anomaliesNonTraitees})')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('ouvrir_rapport_jour'),
              style: outlineButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 44))),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RapportJourHorsLigneScreen(horsLigne: hl))),
              icon: const Icon(Icons.summarize_outlined, size: 18),
              label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Rapport du jour')),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        const Text('Rien n\'est envoyé sans votre accord. Une vente à la fois, dans l\'ordre, sans doublon. '
            'Les écarts (prix, stock, bon, caisse) sont listés en anomalie : rien n\'est perdu.',
            style: TextStyle(fontSize: 12, color: Pal.muted)),
      ]),
    );
  }
}

Widget _note(String text, {bool error = false}) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFDECEC) : const Color(0xFFFFF4E0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: error ? const Color(0xFFF5C2C2) : const Color(0xFFF5D08A)),
      ),
      child: Text(text, style: TextStyle(fontSize: 13, color: error ? const Color(0xFF7F1D1D) : const Color(0xFF7C2D12))),
    );

class _VenteTile extends StatelessWidget {
  final VenteHorsLigne vente;
  final bool selected;
  final VoidCallback onTap;
  const _VenteTile({required this.vente, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final v = vente;
    final look = _look(v.statut);
    final ref = v.reference;
    return Material(
      color: selected ? const Color(0xFFE3ECF7) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: Key('vente_hl_${v.numeroLabel}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(look.icon, size: 20, color: look.fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ref != null && v.statut == StatutVenteHL.envoyee ? '${v.numeroLabel} → $ref' : v.numeroLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink),
                ),
              ),
              const SizedBox(width: 8),
              Text(_f(v.netEstime), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Text(
                  '${v.type.label} · ${_finLabel(v)} · ${_date(v.createdAt)}${v.clientNom.isEmpty ? '' : ' · ${v.clientNom}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: Pal.muted),
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(v.statut.court, fg: look.fg, bg: look.bg),
            ]),
            if (v.statut == StatutVenteHL.aVerifier && v.motif != null) ...[
              const SizedBox(height: 4),
              Text(v.motif!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: look.fg)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Détail d'une vente hors ligne et ses actions.
class VenteHorsLigneDetail extends StatefulWidget {
  final VenteHorsLigne vente;
  final HorsLigne horsLigne;
  final VoidCallback? onDeleted;
  const VenteHorsLigneDetail({super.key, required this.vente, required this.horsLigne, this.onDeleted});

  @override
  State<VenteHorsLigneDetail> createState() => _VenteHorsLigneDetailState();
}

class _VenteHorsLigneDetailState extends State<VenteHorsLigneDetail> {
  bool _busy = false;

  Future<void> _act(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renvoyer() async {
    final v = widget.vente;
    if (v.aFaire) {
      // Envoi d'une vente en attente : même confirmation (risque de double saisie).
      await _act(() => confirmerEnvoiVentes(context, horsLigne: widget.horsLigne, seulement: [v.id]));
      return;
    }
    if (v.statut == StatutVenteHL.aVerifier && v.motif != null) {
      final ok = await confirmVenteAction(
        context,
        title: 'Renvoyer ${v.numeroLabel} ?',
        message: '${v.motif}\n\nLa vente sera renvoyée en acceptant cet écart (le serveur fait foi : prix, net). '
            'Si le serveur refuse encore, elle restera « à vérifier ».',
        confirm: 'Renvoyer',
      );
      if (!ok || !mounted) return;
    }
    await _act(() => widget.horsLigne.ventes.renvoyer(v.id));
  }

  Future<void> _traitee() async {
    final v = widget.vente;
    final ok = await confirmVenteAction(
      context,
      title: 'Marquer ${v.numeroLabel} comme traitée ?',
      message: 'Elle ne sera plus envoyée automatiquement et reste dans la liste. '
          'À faire seulement si la vente a été régularisée sur le serveur.',
      confirm: 'Marquer traitée',
    );
    if (!ok || !mounted) return;
    await _act(() => widget.horsLigne.ventes.marquerTraitee(v.id));
  }

  Future<void> _supprimer() async {
    final v = widget.vente;
    final ok = await confirmVenteAction(
      context,
      title: 'Supprimer ${v.numeroLabel} ?',
      message: 'Cette vente n\'a pas été envoyée au serveur (${_f(v.netEstime)}). Elle sera définitivement effacée de l\'appareil.',
      confirm: 'Supprimer',
      danger: true,
    );
    if (!ok || !mounted) return;
    var done = false;
    await _act(() async => done = await widget.horsLigne.ventes.supprimer(v.id));
    if (done) widget.onDeleted?.call();
  }

  Future<void> _ouvrirServeur() async {
    final id = widget.vente.venteId;
    if (id == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VentesVersion.preVente(resumeVenteId: id)));
  }

  Widget _row(String label, String value, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5, color: Pal.muted))),
          const SizedBox(width: 8),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: strong ? 16 : 13.5, fontWeight: strong ? FontWeight.bold : FontWeight.w600, color: Pal.ink)),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final v = widget.vente;
    final look = _look(v.statut);
    final running = widget.horsLigne.ventes.running;
    final assurance = v.type != TypeVenteHL.comptant;
    final peutRenvoyer = v.statut == StatutVenteHL.aVerifier || (v.aFaire && !running);
    return ListView(
      key: const Key('detail_vente_hl'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(v.numeroLabel, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Pal.ink))),
              StatusBadge(v.statut.court, fg: look.fg, bg: look.bg),
            ]),
            const SizedBox(height: 4),
            Text('${v.statut.label} · ${v.type.label} · ${_finLabel(v)}', style: const TextStyle(color: Pal.muted)),
            Text('Saisie le ${_date(v.createdAt)}${v.userName.isEmpty ? '' : ' par ${v.userName}'}', style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
            if (v.statut == StatutVenteHL.aVerifier && v.motif != null) ...[
              const SizedBox(height: 10),
              Container(
                key: const Key('motif_vente_hl'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: look.bg, borderRadius: BorderRadius.circular(10)),
                child: Text(v.motif!, style: TextStyle(color: look.fg, fontWeight: FontWeight.w600)),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 10),
        if (assurance)
          SoftCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _row('Client', v.clientNom.isEmpty ? '—' : v.clientNom),
              _row('Ayant droit', '${v.ayantDroit?['fullName'] ?? '—'}'),
              for (final t in v.tps) _row('${t.nom.isEmpty ? t.compteTp : t.nom} (${t.taux} %)', 'bon ${t.numBon}'),
            ]),
          ),
        if (assurance) const SizedBox(height: 10),
        SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final l in v.lignes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.nom, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
                      Text('${l.qte} × ${Constants.formatNumber(l.prix)}${l.serveur ? ' · déjà sur le serveur' : ''}',
                          style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Text(Constants.formatNumber(l.total), style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.ink)),
                ]),
              ),
            const Divider(height: 16, color: Pal.line),
            _row('Total (estimé)', _f(v.totalEstime)),
            if (assurance) _row('Part client (estimée)', _f(v.netEstime), strong: true) else _row('Net', _f(v.netEstime), strong: true),
            if (v.fin == FinVenteHL.especes) ...[
              _row('Reçu', _f(v.montantRecu ?? v.netEstime)),
              _row('Rendu', _f(v.montantRendu ?? 0)),
            ],
          ]),
        ),
        const SizedBox(height: 10),
        SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _row('Vente serveur', v.reference ?? (v.venteId == null ? 'pas encore créée' : 'créée')),
            if (v.envoyeeAt != null) _row('Envoyée le', _date(v.envoyeeAt!)),
            if (v.commenceeEnLigne) _row('Origine', 'commencée en ligne'),
            if (v.tentatives > 0) _row('Essais d\'envoi', '${v.tentatives}'),
          ]),
        ),
        const SizedBox(height: 14),
        if (peutRenvoyer)
          ElevatedButton.icon(
            key: const Key('hl_renvoyer'),
            style: navyButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48))),
            onPressed: _busy || running ? null : _renvoyer,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(v.statut == StatutVenteHL.aVerifier ? 'Renvoyer' : 'Envoyer maintenant'),
          ),
        if (v.venteId != null && v.type == TypeVenteHL.comptant) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('hl_ouvrir'),
            style: outlineButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48))),
            onPressed: _busy ? null : _ouvrirServeur,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Ouvrir la vente sur le serveur'),
          ),
        ],
        if (v.venteId != null && assurance && v.statut != StatutVenteHL.envoyee)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Vente ${v.reference ?? ''} sur le serveur : retrouvez-la dans l\'historique du menu ${v.type.label}.'.replaceAll('  ', ' '),
                style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
          ),
        if (v.statut == StatutVenteHL.aVerifier) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('hl_traitee'),
            style: outlineButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48))),
            onPressed: _busy ? null : _traitee,
            icon: const Icon(Icons.task_alt),
            label: const Text('Marquer comme traitée'),
          ),
        ],
        if (v.supprimable && v.statut != StatutVenteHL.envoiEnCours) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('hl_supprimer'),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626), minimumSize: const Size.fromHeight(44)),
            onPressed: _busy || running ? null : _supprimer,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Supprimer (non envoyée)'),
          ),
        ],
      ],
    );
  }
}
