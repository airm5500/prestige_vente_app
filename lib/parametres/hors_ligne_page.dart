// lib/parametres/hors_ligne_page.dart
// Rubrique « Hors ligne » des Réglages : état du serveur, interrupteur manuel, copie locale
// (dernière mise à jour et nombre d'éléments par catégorie), « Mettre à jour maintenant »,
// « Vider la copie locale » (avec confirmation).
// H2 : ventes hors ligne (en attente, anomalies), accès à la liste, aux anomalies et au rapport du jour.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_screen.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/rapports_hl_screen.dart';
import 'package:prestige_vente_app/horsligne/ventes_hors_ligne_screen.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_ui.dart';
import 'package:prestige_vente_app/parametres/parametres_widgets.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Résumé de la rubrique : « En ligne · catalogue du 10/10 08:30 ».
String horsLigneSummary([HorsLigne? hl]) {
  final h = hl ?? HorsLigne.instance;
  final etat = switch (h.monitor.etat) {
    EtatServeur.enLigne => 'En ligne',
    EtatServeur.injoignable => 'Serveur injoignable',
    EtatServeur.horsLigne => 'Hors ligne',
  };
  return '$etat · ${h.catalogueLabel}';
}

class HorsLignePage extends StatefulWidget {
  /// Instance utilisée (tests) ; sinon [HorsLigne.instance].
  final HorsLigne? horsLigne;
  const HorsLignePage({super.key, this.horsLigne});

  @override
  State<HorsLignePage> createState() => _HorsLignePageState();
}

class _HorsLignePageState extends State<HorsLignePage> {
  HorsLigne get _hl => widget.horsLigne ?? HorsLigne.instance;

  @override
  void initState() {
    super.initState();
    _hl.sync.refreshStats();
    _hl.ventes.ensureLoaded();
  }

  void _ouvrir(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Widget _lien(Key key, IconData icon, String text, Widget page) => ListTile(
        key: key,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Pal.navy),
        title: Text(text, style: const TextStyle(fontSize: 14, color: Pal.ink)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _ouvrir(page),
      );

  String _etat(ServerMonitor m) {
    final depuis = m.depuis == null ? '' : ' depuis ${HorsLigne.formatDate(m.depuis!)}';
    return switch (m.etat) {
      EtatServeur.enLigne => 'En ligne : le serveur répond.',
      EtatServeur.injoignable => 'Serveur injoignable$depuis. Vous pouvez continuer hors ligne.',
      EtatServeur.horsLigne => m.raison == RaisonHorsLigne.manuel
          ? 'Hors ligne (choisi)$depuis. Retour en ligne automatique dès que le serveur répond.'
          : 'Hors ligne$depuis. Retour en ligne automatique dès que le serveur répond.',
    };
  }

  Future<void> _maj() async {
    final ok = await _hl.sync.syncAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(ok ? 'Copie locale mise à jour.' : 'Mise à jour incomplète : ${_hl.sync.error ?? ''}')));
  }

  Future<void> _vider() async {
    final ok = await confirmer(context,
        title: 'Vider la copie locale ?',
        message: 'Les produits, clients, modes de paiement, BL et commandes gardés sur cet appareil seront effacés '
            '(les opérations saisies hors ligne sont conservées). '
            'Sans copie, la recherche hors ligne ne trouvera plus rien jusqu\'à la prochaine mise à jour.',
        action: 'Vider',
        danger: true);
    if (!ok) return;
    try {
      await _hl.store.clear();
      // Copies complémentaires (stock H3) ; les opérations en attente ne sont jamais effacées.
      for (final x in _hl.sync.extensions) {
        await x.clear();
      }
    } catch (_) {}
    await _hl.sync.refreshStats();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copie locale vidée.')));
  }

  Widget _ligne(CatalogueCategorie c, LocalStats s) {
    final at = s.lastSync[c];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text(c.label, style: const TextStyle(fontSize: 14, color: Pal.ink))),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${s.count(c)}', key: Key('compte_${c.name}'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Pal.ink)),
          Text(at == null ? 'jamais' : HorsLigne.formatDate(at), style: const TextStyle(fontSize: 12, color: Pal.muted)),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hl = _hl;
    return ListenableBuilder(
      listenable: Listenable.merge([hl.monitor, hl.sync, hl.ventes]),
      builder: (context, _) {
        final m = hl.monitor;
        final ventes = hl.ventes;
        final sync = hl.sync;
        final s = sync.stats;
        final offline = m.isOffline;
        return RubriquePage(
          title: 'Hors ligne',
          subtitle: 'Continuer à travailler pendant une coupure',
          children: [
            const SectionLabel('État'),
            SettingCard(
              child: Row(children: [
                Icon(
                  switch (m.etat) {
                    EtatServeur.enLigne => Icons.cloud_done,
                    EtatServeur.injoignable => Icons.wifi_off,
                    EtatServeur.horsLigne => Icons.cloud_off,
                  },
                  color: m.etat == EtatServeur.enLigne ? Pal.green : const Color(0xFFB45309),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(_etat(m), key: const Key('etat_serveur'), style: const TextStyle(fontSize: 14, color: Pal.ink))),
              ]),
            ),
            SwitchCard(
              key: const Key('interrupteur_hors_ligne'),
              title: 'Passer en hors ligne',
              subtitle: 'La recherche produit utilise la copie locale. Désactiver pour revenir en ligne.',
              value: offline,
              onChanged: (v) => v ? m.goOffline(manuel: true) : m.goOnline(),
            ),
            const SectionLabel('Ventes hors ligne'),
            SettingCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${ventes.enAttente} en attente d\'envoi · ${ventes.aVerifier} en anomalie',
                    key: const Key('resume_ventes_hl'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Pal.ink)),
                _lien(const Key('ouvrir_ventes_hl'), Icons.cloud_upload_outlined, 'Ventes hors ligne', VentesHorsLigneScreen(horsLigne: widget.horsLigne)),
                _lien(const Key('ouvrir_anomalies_hl'), Icons.report_problem_outlined, 'Anomalies de synchronisation (${ventes.anomaliesNonTraitees})',
                    AnomaliesHorsLigneScreen(horsLigne: widget.horsLigne)),
                _lien(const Key('ouvrir_rapport_jour_hl'), Icons.summarize_outlined, 'Rapport de fin de journée',
                    RapportJourHorsLigneScreen(horsLigne: widget.horsLigne)),
              ]),
            ),
            const SectionLabel('Copie locale'),
            if (sync.storeError != null) InfoBanner.error(sync.storeError!),
            SettingCard(
              child: Column(children: [
                for (final c in CatalogueCategorie.values) _ligne(c, s),
                const Divider(height: 14),
                Row(children: [
                  Expanded(
                    child: Text('${s.count(CatalogueCategorie.produits)} produits · ${s.clients} clients',
                        key: const Key('resume_copie'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Pal.ink)),
                  ),
                  if (sync.lastDuration != null)
                    Text('${(sync.lastDuration!.inMilliseconds / 1000).toStringAsFixed(1)} s',
                        style: const TextStyle(fontSize: 12, color: Pal.muted)),
                ]),
                // H5 : mise à jour différentielle (serveur avec le patch) : « il y a X min (N produits modifiés) ».
                if (sync.deltaLibelle case final String l)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(l, key: const Key('maj_differentielle'), style: const TextStyle(fontSize: 12, color: Pal.muted)),
                    ),
                  ),
              ]),
            ),
            if (sync.running)
              SettingCard(
                key: const Key('carte_progression_maj'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Mise à jour ${sync.etapeNum}/${sync.etapesTotal}${sync.enPause ? ' (en pause : vous travaillez)' : ''}',
                      key: const Key('progression_maj_etapes'), style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
                  const SizedBox(height: 4),
                  // Barre globale déterminée (étapes), puis l'étape en cours (pages).
                  LinearProgressIndicator(
                      key: const Key('barre_maj_globale'), value: sync.avancementGlobal, minHeight: 6, color: Pal.navy, backgroundColor: Pal.line),
                  const SizedBox(height: 8),
                  Text(sync.progressionLabel ?? '', key: const Key('progression_maj'), style: const TextStyle(fontSize: 13, color: Pal.ink)),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(key: const Key('barre_maj_etape'), value: sync.progress, color: Pal.navy, backgroundColor: Pal.line),
                ]),
              ),
            if (!sync.running && sync.error != null) InfoBanner.error('Dernière mise à jour incomplète :\n${sync.error}'),
            for (final w in sync.warnings) InfoBanner.warning(w),
            InfoBanner(sync.deltaActif
                ? 'Les produits modifiés sur le serveur (ventes, entrées, prix…) sont récupérés toutes les 5 min tant que '
                    'le serveur répond, avec une copie complète une fois par jour ; le reste toutes les 30 min. '
                    'Le stock affiché hors ligne est celui connu à la dernière mise à jour. '
                    'BL entrés en stock : les 3 derniers jours (écrans hors ligne : aujourd\'hui par défaut).'
                : 'La copie se met à jour après la connexion si elle a plus de 12 h, puis toutes les 30 min '
                    'tant que le serveur répond. Le stock affiché hors ligne est celui connu à la dernière mise à jour. '
                    'BL entrés en stock : les 3 derniers jours (écrans hors ligne : aujourd\'hui par défaut).'),
            const SizedBox(height: 4),
            ElevatedButton.icon(
              key: const Key('maj_copie'),
              style: navyButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48))),
              onPressed: sync.running || offline || sync.fetch == null ? null : _maj,
              icon: const Icon(Icons.sync),
              label: Text(sync.running ? 'Mise à jour en cours…' : 'Mettre à jour maintenant'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('vider_copie'),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626), minimumSize: const Size.fromHeight(44)),
              onPressed: sync.running ? null : _vider,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Vider la copie locale'),
            ),
            // Stock hors ligne (H3) : copie BL / commandes / retours, opérations et anomalies.
            const StockHorsLigneSection(),
            const SectionLabel('Traçabilité et historique'),
            SettingCard(
              child: _lien(const Key('ouvrir_journal_terminal'), Icons.history, 'Journal du terminal (actions stock et caisse)', const JournalTerminalScreen()),
            ),
            SettingCard(
              child: Row(children: [
                const Expanded(
                  child: Text('Journal du terminal, ventes et opérations envoyées : purge automatique au-delà de',
                      style: TextStyle(fontSize: 13.5, color: Pal.ink)),
                ),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  key: const Key('conservation_jours'),
                  value: JournalTerminal.conservationsPossibles.contains(JournalTerminal.conservationJours) ? JournalTerminal.conservationJours : 90,
                  items: [for (final j in JournalTerminal.conservationsPossibles) DropdownMenuItem(value: j, child: Text('$j jours'))],
                  onChanged: (j) async {
                    if (j == null) return;
                    await JournalTerminal.reglerConservation(j);
                    if (mounted) setState(() {});
                  },
                ),
              ]),
            ),
          ],
        );
      },
    );
  }
}
