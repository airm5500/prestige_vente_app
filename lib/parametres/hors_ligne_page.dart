// lib/parametres/hors_ligne_page.dart
// Rubrique « Hors ligne » des Réglages : état du serveur, interrupteur manuel, copie locale
// (dernière mise à jour et nombre d'éléments par catégorie), « Mettre à jour maintenant »,
// « Vider la copie locale » (avec confirmation).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
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
  }

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
        message: 'Les produits, clients et modes de paiement gardés sur cet appareil seront effacés. '
            'Sans copie, la recherche hors ligne ne trouvera plus rien jusqu\'à la prochaine mise à jour.',
        action: 'Vider',
        danger: true);
    if (!ok) return;
    try {
      await _hl.store.clear();
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
      listenable: Listenable.merge([hl.monitor, hl.sync]),
      builder: (context, _) {
        final m = hl.monitor;
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
              ]),
            ),
            if (sync.running)
              SettingCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      'Mise à jour : ${sync.etape ?? ''}${sync.total == null ? (sync.done > 0 ? ' ${sync.done}' : '') : ' ${sync.done} / ${sync.total}'}',
                      style: const TextStyle(fontSize: 13, color: Pal.ink)),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: sync.progress, color: Pal.navy, backgroundColor: Pal.line),
                ]),
              ),
            if (!sync.running && sync.error != null) InfoBanner.error('Dernière mise à jour incomplète :\n${sync.error}'),
            for (final w in sync.warnings) InfoBanner.warning(w),
            const InfoBanner('La copie se met à jour après la connexion si elle a plus de 12 h, puis toutes les 30 min '
                'tant que le serveur répond. Le stock affiché hors ligne est celui connu à la dernière mise à jour.'),
            const SizedBox(height: 4),
            ElevatedButton.icon(
              key: const Key('maj_copie'),
              style: navyButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48))),
              onPressed: sync.running || offline || sync.fetch == null ? null : _maj,
              icon: const Icon(Icons.sync),
              label: const Text('Mettre à jour maintenant'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('vider_copie'),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626), minimumSize: const Size.fromHeight(44)),
              onPressed: sync.running ? null : _vider,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Vider la copie locale'),
            ),
          ],
        );
      },
    );
  }
}
