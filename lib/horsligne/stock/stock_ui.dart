// lib/horsligne/stock/stock_ui.dart
// Écrans du stock hors ligne (H3) :
// - « Opérations hors ligne (stock) » : liste et statuts (en attente / envoyée / ressaisie / anomalie) ;
// - confirmation d'envoi : opérations en attente (type, BL / grossiste, heure, nb lignes), décocher
//   celles déjà ressaisies sur le serveur ; JAMAIS d'envoi sans cet accord ;
// - les anomalies sont dans l'écran commun « Anomalies de synchronisation » (rapports_hl_screen.dart) ;
// - bandeau « N opération(s) de stock en attente » (rien s'il n'y en a pas) ;
// - section de Réglages › Hors ligne (copie stock : nombre d'éléments par catégorie et date).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/rapports_hl_screen.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_horsligne.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_queue.dart';
import 'package:prestige_vente_app/parametres/parametres_widgets.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Navigateur de l'appli (le bandeau est placé au-dessus de lui) : celui de [HorsLigne].
GlobalKey<NavigatorState> get horsLigneNavigatorKey => HorsLigne.navigatorKey;

final _heure = DateFormat('dd/MM HH:mm');

/// Mention « Disponible en ligne uniquement » (action désactivée hors ligne).
class EnLigneUniquementNote extends StatelessWidget {
  final String? action;
  const EnLigneUniquementNote({super.key, this.action});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          const Icon(Icons.cloud_off, size: 16, color: Color(0xFF475569)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(action == null ? kEnLigneUniquement : '$action : $kEnLigneUniquement',
                key: const Key('en_ligne_uniquement'), style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569))),
          ),
        ]),
      );
}

Color _statutColor(StockOpStatut s) => switch (s) {
      StockOpStatut.enAttente => const Color(0xFFB45309),
      StockOpStatut.envoyee => Pal.green,
      StockOpStatut.ressaisie => Pal.muted,
      StockOpStatut.anomalie => const Color(0xFFDC2626),
    };

String _ligneEtat(StockLineEtat e) => switch (e) {
      StockLineEtat.pending => 'à envoyer',
      StockLineEtat.sending => 'envoi commencé (vérifié avant renvoi)',
      StockLineEtat.applied => 'envoyée',
      StockLineEtat.dejaApplique => 'déjà sur le serveur',
      StockLineEtat.rejected => 'refusée',
      StockLineEtat.ignored => 'non envoyée',
    };

String _ligneTexte(StockOp op, StockOpLine l) {
  final d = l.data;
  final q = switch (op.type) {
    StockOpType.reception => '${d['qty']}${(d['ug'] ?? 0) != 0 ? ' + ${d['ug']} UG' : ''} · lot ${d['numLot']}'
        '${'${d['expiry'] ?? ''}'.isEmpty ? '' : ' · pér. ${d['expiry']}'}',
    StockOpType.peremption => '${d['qty']} · lot ${d['numLot']} · pér. ${d['date']}',
    StockOpType.perime => '${d['qty']} · lot ${d['lot']} · pér. ${d['date']}',
    StockOpType.retour => '${d['qty']} · ${d['motif'] ?? ''}',
    StockOpType.emplacement => '→ ${d['rayon']}',
    _ => 'qté ${d['qty']}',
  };
  return '${l.label} — $q';
}

/// Carte d'une opération (dépliable : lignes et motifs).
class StockOpCard extends StatelessWidget {
  final StockOp op;
  final Widget? leading;
  const StockOpCard({super.key, required this.op, this.leading});

  @override
  Widget build(BuildContext context) {
    final c = _statutColor(op.statut);
    return SettingCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: Key('op_${op.id}'),
          leading: leading,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(op.type.label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Pal.ink)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (op.titre.isNotEmpty) Text(op.titre, style: const TextStyle(fontSize: 12.5, color: Pal.ink)),
            Text('${_heure.format(op.createdAt)} · ${op.lines.length} ligne(s)', style: const TextStyle(fontSize: 12, color: Pal.muted)),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: Text(op.statut.label, key: Key('statut_${op.id}'), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
            ),
            if (op.motif != null && op.statut == StockOpStatut.anomalie)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(op.motif!, style: const TextStyle(fontSize: 12, color: Color(0xFF7F1D1D))),
              ),
          ]),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 12, 10),
          children: [
            for (final l in op.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(_ligneTexte(op, l), style: const TextStyle(fontSize: 12.5, color: Pal.ink))),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      [_ligneEtat(l.etat), if (l.motif != null && l.etat == StockLineEtat.rejected) l.motif!].join(' : '),
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 11.5, color: l.etat == StockLineEtat.rejected ? const Color(0xFFDC2626) : Pal.muted),
                    ),
                  ),
                ]),
              ),
            if (op.meta['retourRef'] != null && '${op.meta['retourRef']}'.isNotEmpty)
              Align(alignment: Alignment.centerLeft, child: Text('Retour Prestige n° ${op.meta['retourRef']}', style: const TextStyle(fontSize: 12, color: Pal.muted))),
          ],
        ),
      ),
    );
  }
}

/// « Opérations hors ligne (stock) ».
class StockOperationsScreen extends StatefulWidget {
  final StockHorsLigne? stock;
  const StockOperationsScreen({super.key, this.stock});

  @override
  State<StockOperationsScreen> createState() => _StockOperationsScreenState();
}

class _StockOperationsScreenState extends State<StockOperationsScreen> {
  StockHorsLigne get _stock => widget.stock ?? StockHorsLigne.instance;

  @override
  void initState() {
    super.initState();
    _stock.queue.load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final q = _stock.queue;
    final hl = HorsLigne.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([q, hl.monitor]),
      builder: (context, _) {
        final enAttente = q.pending;
        final historique = q.ops.where((o) => !o.pending).toList().reversed.toList();
        final enLigne = hl.monitor.etat == EtatServeur.enLigne;
        return RubriquePage(
          title: 'Opérations hors ligne (stock)',
          subtitle: '${enAttente.length} en attente · ${q.anomaliesNonTraitees} anomalie(s) non traitée(s)',
          bottom: BottomBar(children: [
            ElevatedButton.icon(
              key: const Key('envoyer_maintenant'),
              style: navyButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48))),
              onPressed: enAttente.isEmpty || !enLigne || q.sending ? null : () => ouvrirEnvoiStock(context, stock: _stock),
              icon: const Icon(Icons.cloud_upload),
              label: Text(q.sending ? (q.progress ?? 'Envoi…') : 'Envoyer maintenant'),
            ),
            if (!enLigne && enAttente.isNotEmpty) const EnLigneUniquementNote(action: 'Envoi'),
          ]),
          children: [
            if (q.error != null) InfoBanner.error(q.error!),
            const InfoBanner('Les saisies faites hors ligne sont gardées sur cet appareil (même après redémarrage). '
                'Elles ne partent qu\'après votre confirmation, une opération à la fois.'),
            LinkCard(
              icon: Icons.report_problem_outlined,
              title: 'Anomalies de synchronisation',
              subtitle: 'Stock : ${q.anomaliesList.length} anomalie(s), dont ${q.anomaliesNonTraitees} non traitée(s)',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnomaliesHorsLigneScreen())),
            ),
            SectionLabel('En attente (${enAttente.length})'),
            if (enAttente.isEmpty)
              const SettingCard(child: Text('Aucune opération en attente.', style: TextStyle(color: Pal.muted))),
            for (final op in enAttente) StockOpCard(op: op),
            SectionLabel('Historique (${historique.length})'),
            if (historique.isEmpty) const SettingCard(child: Text('Aucune opération envoyée.', style: TextStyle(color: Pal.muted))),
            for (final op in historique) StockOpCard(op: op),
          ],
        );
      },
    );
  }
}

/// Ouvre la confirmation d'envoi (une seule à la fois).
Future<void> ouvrirEnvoiStock(BuildContext? context, {StockHorsLigne? stock}) async {
  if (_envoiOuvert) return;
  final nav = context != null ? Navigator.of(context) : horsLigneNavigatorKey.currentState;
  if (nav == null) return;
  _envoiOuvert = true;
  try {
    await nav.push(MaterialPageRoute(builder: (_) => StockEnvoiScreen(stock: stock)));
  } finally {
    _envoiOuvert = false;
  }
}

bool _envoiOuvert = false;

/// Confirmation avant envoi : chaque opération cochée est envoyée ; une opération décochée est
/// marquée « non envoyée — ressaisie sur le serveur » (gardée dans l'historique).
class StockEnvoiScreen extends StatefulWidget {
  final StockHorsLigne? stock;
  const StockEnvoiScreen({super.key, this.stock});

  @override
  State<StockEnvoiScreen> createState() => _StockEnvoiScreenState();
}

class _StockEnvoiScreenState extends State<StockEnvoiScreen> {
  StockHorsLigne get _stock => widget.stock ?? StockHorsLigne.instance;
  final Set<String> _decochees = {};
  StockEnvoiResultat? _resultat;

  Future<void> _envoyer() async {
    final pending = _stock.queue.pending;
    final selection = {for (final o in pending) if (!_decochees.contains(o.id)) o.id};
    final ressaisies = {for (final o in pending) if (_decochees.contains(o.id)) o.id};
    if (ressaisies.isNotEmpty) {
      final ok = await confirmer(context,
          title: 'Opérations décochées',
          message: '${ressaisies.length} opération(s) ne seront PAS envoyées et seront marquées '
              '« non envoyée — ressaisie sur le serveur » (gardées dans l\'historique).',
          action: 'Continuer');
      if (!ok || !mounted) return;
    }
    final r = await _stock.queue.envoyer(selection: selection, ressaisies: ressaisies);
    if (mounted) setState(() => _resultat = r);
  }

  @override
  Widget build(BuildContext context) {
    final q = _stock.queue;
    return ListenableBuilder(
      listenable: q,
      builder: (context, _) {
        final pending = q.pending;
        final r = _resultat;
        final nb = pending.where((o) => !_decochees.contains(o.id)).length;
        return RubriquePage(
          title: 'Envoyer les opérations de stock',
          subtitle: '${pending.length} opération(s) saisie(s) hors ligne',
          bottom: BottomBar(children: [
            if (r == null || pending.isNotEmpty)
              ElevatedButton.icon(
                key: const Key('confirmer_envoi'),
                style: navyButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48))),
                onPressed: q.sending || pending.isEmpty ? null : _envoyer,
                icon: q.sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload),
                label: Text(q.sending ? (q.progress ?? 'Envoi…') : (nb == pending.length ? 'Envoyer $nb opération(s)' : 'Envoyer $nb · ${pending.length - nb} ressaisie(s)')),
              ),
            const SizedBox(height: 6),
            TextButton(
              key: const Key('plus_tard'),
              onPressed: q.sending ? null : () => Navigator.of(context).pop(),
              child: Text(r == null ? 'Plus tard (rien n\'est envoyé)' : 'Fermer'),
            ),
          ]),
          children: [
            if (r != null)
              r.anomalies > 0 || r.interruption != null
                  ? InfoBanner.warning('Résultat : ${r.resume}')
                  : InfoBanner('Résultat : ${r.resume}', icon: Icons.check_circle_outline, fg: Pal.green, bg: const Color(0xFFDCFCE7)),
            if (r != null && r.anomalies > 0)
              LinkCard(
                icon: Icons.report_problem_outlined,
                title: 'Voir les anomalies de synchronisation',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnomaliesHorsLigneScreen())),
              ),
            if (pending.isNotEmpty)
              const InfoBanner('Cochées : envoyées une à une, dans l\'ordre. Décochez celles déjà ressaisies sur le serveur '
                  '(elles seront marquées « non envoyée — ressaisie sur le serveur »).'),
            for (final op in pending)
              StockOpCard(
                op: op,
                leading: Checkbox(
                  key: Key('coche_${op.id}'),
                  value: !_decochees.contains(op.id),
                  onChanged: q.sending ? null : (v) => setState(() => v == true ? _decochees.remove(op.id) : _decochees.add(op.id)),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Bandeau « N opération(s) de stock en attente » (sous le bandeau hors ligne ; rien s'il n'y en a pas).
/// Au retour du serveur, ouvre la confirmation d'envoi (sans rien envoyer seul).
class StockBandeau extends StatefulWidget {
  final HorsLigne horsLigne;
  final StockHorsLigne? stock;
  const StockBandeau({super.key, required this.horsLigne, this.stock});

  /// Le bandeau est-il affiché ?
  static bool visible(StockHorsLigne s) => s.queue.pendingCount > 0 || s.queue.sending;

  @override
  State<StockBandeau> createState() => _StockBandeauState();
}

class _StockBandeauState extends State<StockBandeau> {
  StockHorsLigne get _stock => widget.stock ?? StockHorsLigne.instance;
  DateTime? _retourVu;

  @override
  void initState() {
    super.initState();
    _retourVu = widget.horsLigne.monitor.retourAt;
    widget.horsLigne.monitor.addListener(_onMonitor);
  }

  @override
  void dispose() {
    widget.horsLigne.monitor.removeListener(_onMonitor);
    super.dispose();
  }

  void _onMonitor() {
    final m = widget.horsLigne.monitor;
    final r = m.retourAt;
    if (m.etat != EtatServeur.enLigne || r == null || r == _retourVu) return;
    _retourVu = r;
    if (!StockHorsLigne.confirmerAuRetour || _stock.queue.pendingCount == 0) return;
    // Ventes en attente : leur confirmation s'ouvre d'abord, celle du stock suit (HorsLigneScope).
    if (widget.horsLigne.ventes.enAttente > 0) return;
    // Après le message « Serveur de nouveau joignable » : la confirmation (rien n'est envoyé sans accord).
    scheduleMicrotask(() => ouvrirEnvoiStock(null, stock: _stock));
  }

  @override
  Widget build(BuildContext context) {
    final q = _stock.queue;
    return ListenableBuilder(
      listenable: Listenable.merge([q, widget.horsLigne.monitor]),
      builder: (context, _) {
        if (!StockBandeau.visible(_stock)) return const SizedBox.shrink();
        final enLigne = widget.horsLigne.monitor.etat == EtatServeur.enLigne;
        final n = q.pendingCount;
        final text = q.sending
            ? (q.progress ?? 'Envoi des opérations de stock…')
            : enLigne
                ? '$n opération(s) de stock en attente d\'envoi'
                : '$n opération(s) de stock enregistrée(s) hors ligne';
        const fg = Color(0xFF7C2D12);
        return Material(
          key: const Key('bandeau_stock'),
          color: const Color(0xFFFFEDD5),
          child: SafeArea(
            bottom: false,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                child: Row(children: [
                  const Icon(Icons.inventory_2_outlined, size: 16, color: fg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                  if (!q.sending)
                    TextButton(
                      key: const Key('bandeau_stock_action'),
                      style: TextButton.styleFrom(
                        foregroundColor: fg,
                        minimumSize: const Size(44, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => enLigne
                          ? ouvrirEnvoiStock(null, stock: _stock)
                          : horsLigneNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => StockOperationsScreen(stock: _stock))),
                      child: Text(enLigne ? 'Envoyer…' : 'Voir'),
                    ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Section de Réglages › Hors ligne : copie « stock » et opérations hors ligne.
class StockHorsLigneSection extends StatefulWidget {
  final StockHorsLigne? stock;
  const StockHorsLigneSection({super.key, this.stock});

  @override
  State<StockHorsLigneSection> createState() => _StockHorsLigneSectionState();
}

class _StockHorsLigneSectionState extends State<StockHorsLigneSection> {
  StockHorsLigne get _stock => widget.stock ?? StockHorsLigne.instance;

  @override
  void initState() {
    super.initState();
    _stock.refs.refreshStats();
    _stock.queue.load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _stock;
    return ListenableBuilder(
      listenable: Listenable.merge([s.refs, s.queue]),
      builder: (context, _) {
        final st = s.refs.stats;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionLabel('Copie locale — stock'),
          if (s.refs.error != null) InfoBanner.error(s.refs.error!),
          SettingCard(
            child: Column(children: [
              for (final c in StockRef.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(child: Text(c.label, style: const TextStyle(fontSize: 14, color: Pal.ink))),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${st.count(c)}', key: Key('compte_stock_${c.name}'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Pal.ink)),
                      Text(st.lastSync[c] == null ? 'jamais' : HorsLigne.formatDate(st.lastSync[c]!), style: const TextStyle(fontSize: 12, color: Pal.muted)),
                    ]),
                  ]),
                ),
            ]),
          ),
          const SectionLabel('Opérations hors ligne'),
          LinkCard(
            key: const Key('lien_operations_stock'),
            icon: Icons.inventory_2_outlined,
            title: 'Opérations hors ligne (stock)',
            subtitle: '${s.queue.pendingCount} en attente · ${s.queue.anomaliesNonTraitees} anomalie(s) non traitée(s)',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockOperationsScreen(stock: widget.stock))),
          ),
        ]);
      },
    );
  }
}
