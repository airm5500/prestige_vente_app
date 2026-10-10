// lib/horsligne/rapports_hl_screen.dart
// Écrans des rapports des ventes hors ligne (étape H2) :
// « Anomalies de synchronisation » (rapport persistant, état traité / non traité) et
// « Rapport de fin de journée » (ventes du jour + total par produit, espèces provisoires).
// Impression sur le ticket (mode test : aperçu) et partage en PDF.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/rapports_hl.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

String _f(int v) => '${Constants.formatNumber(v)} F';

/// Impression d'un rapport texte (réglages d'impression de l'appareil ; aperçu en mode test).
Future<void> imprimerRapport(BuildContext context, {required String titre, required List<String> Function(int cols) lignes}) async {
  SettingsProvider? settings;
  try {
    settings = Provider.of<SettingsProvider>(context, listen: false);
  } catch (_) {}
  final officine = () {
    try {
      return Provider.of<AuthProvider>(context, listen: false).officine;
    } catch (_) {
      return null;
    }
  }();
  final width = settings?.paperWidth ?? 58;
  await ReceiptService().printTextReport(
    context: context,
    officine: officine,
    title: titre,
    lines: lignes(width == 58 ? 32 : 48),
    isTestMode: settings?.isTestPrintMode ?? true,
    paperWidth: width,
  );
}

Future<void> _pdf(BuildContext context, String titre, List<String> lignes, String fichier) async {
  try {
    await partagerRapportPdf(titre: titre, lignes: lignes, fichier: fichier);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF impossible : $e')));
  }
}

List<Widget> _actions(BuildContext context, {required String titre, required List<String> Function(int cols) lignes, required String fichier}) => [
      IconButton(
        key: const Key('rapport_imprimer'),
        tooltip: 'Imprimer le ticket',
        icon: const Icon(Icons.print),
        onPressed: () => imprimerRapport(context, titre: titre, lignes: lignes),
      ),
      IconButton(
        key: const Key('rapport_pdf'),
        tooltip: 'Partager en PDF',
        icon: const Icon(Icons.picture_as_pdf_outlined),
        onPressed: () => _pdf(context, titre, lignes(80), fichier),
      ),
    ];

// -----------------------------------------------------------------------------
// Anomalies de synchronisation
// -----------------------------------------------------------------------------

class AnomaliesHorsLigneScreen extends StatefulWidget {
  final HorsLigne? horsLigne;
  const AnomaliesHorsLigneScreen({super.key, this.horsLigne});

  @override
  State<AnomaliesHorsLigneScreen> createState() => _AnomaliesHorsLigneScreenState();
}

class _AnomaliesHorsLigneScreenState extends State<AnomaliesHorsLigneScreen> {
  HorsLigne get _hl => widget.horsLigne ?? HorsLigne.instance;
  bool _nonTraitees = false;

  @override
  void initState() {
    super.initState();
    _hl.ventes.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final f = _hl.ventes;
    return ListenableBuilder(
      listenable: f,
      builder: (context, _) {
        final all = f.anomalies.reversed.toList();
        final list = _nonTraitees ? all.where((a) => !a.traitee).toList() : all;
        const titre = 'ANOMALIES DE SYNCHRONISATION';
        return Scaffold(
          backgroundColor: Pal.page,
          appBar: AppBar(
            title: const Text('Anomalies de synchronisation'),
            actions: _actions(context,
                titre: titre,
                lignes: (cols) => lignesAnomalies(list, cols: cols),
                fichier: 'Anomalies_hors_ligne_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf'),
          ),
          body: ListView(
            key: const Key('liste_anomalies'),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              Text('${all.length} anomalie(s) · ${f.anomaliesNonTraitees} non traitée(s)',
                  key: const Key('compteur_anomalies'), style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Non traitées seulement'),
                value: _nonTraitees,
                onChanged: (v) => setState(() => _nonTraitees = v),
              ),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('Aucune anomalie', style: TextStyle(color: Pal.muted))),
                ),
              for (final a in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SoftCard(
                    band: a.traitee ? Pal.line : const Color(0xFFDC2626),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(
                          child: Text('${a.numeroLabel} · ${a.type.label}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink)),
                        ),
                        Text(DateFormat('dd/MM HH:mm').format(a.date), style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
                      ]),
                      if (a.client.isNotEmpty) Text('Client : ${a.client}', style: const TextStyle(fontSize: 13, color: Pal.ink)),
                      if (a.bons.isNotEmpty) Text('Bon : ${a.bons}', style: const TextStyle(fontSize: 13, color: Pal.ink)),
                      const SizedBox(height: 4),
                      Text(a.natureLabel, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFFB91C1C))),
                      Text(a.motif, style: const TextStyle(fontSize: 13, color: Pal.ink)),
                      CheckboxListTile(
                        key: Key('anomalie_traitee_${a.id}'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(a.traitee ? 'Traitée' : 'Non traitée'),
                        value: a.traitee,
                        onChanged: (v) => f.marquerAnomalie(a.id, v ?? false),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Rapport de fin de journée
// -----------------------------------------------------------------------------

class RapportJourHorsLigneScreen extends StatefulWidget {
  final HorsLigne? horsLigne;

  /// Jour affiché (aujourd'hui par défaut).
  final DateTime? jour;
  const RapportJourHorsLigneScreen({super.key, this.horsLigne, this.jour});

  @override
  State<RapportJourHorsLigneScreen> createState() => _RapportJourHorsLigneScreenState();
}

class _RapportJourHorsLigneScreenState extends State<RapportJourHorsLigneScreen> {
  HorsLigne get _hl => widget.horsLigne ?? HorsLigne.instance;
  late DateTime _jour = widget.jour ?? _hl.ventes.now;

  @override
  void initState() {
    super.initState();
    _hl.ventes.ensureLoaded();
  }

  void _decaler(int jours) => setState(() => _jour = DateTime(_jour.year, _jour.month, _jour.day + jours));

  Widget _row(String a, String b, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(a, style: TextStyle(fontSize: 13.5, color: strong ? Pal.ink : Pal.muted, fontWeight: strong ? FontWeight.bold : null))),
          const SizedBox(width: 8),
          Text(b, style: TextStyle(fontSize: 13.5, fontWeight: strong ? FontWeight.bold : FontWeight.w600, color: Pal.ink)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final f = _hl.ventes;
    return ListenableBuilder(
      listenable: f,
      builder: (context, _) {
        final r = rapportDuJour(f.ventes, _jour);
        final jour = DateFormat('dd/MM/yyyy').format(_jour);
        final h = DateFormat('HH:mm');
        return Scaffold(
          backgroundColor: Pal.page,
          appBar: AppBar(
            title: const Text('Rapport de fin de journée'),
            actions: _actions(context,
                titre: 'VENTES HORS LIGNE — $jour',
                lignes: (cols) => lignesRapportJour(r, cols: cols),
                fichier: 'Ventes_hors_ligne_${DateFormat('yyyyMMdd').format(_jour)}.pdf'),
          ),
          body: ListView(
            key: const Key('rapport_jour'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              Row(children: [
                IconButton(tooltip: 'Jour précédent', onPressed: () => _decaler(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Text('Journée du $jour',
                      key: const Key('rapport_jour_date'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.ink)),
                ),
                IconButton(tooltip: 'Jour suivant', onPressed: () => _decaler(1), icon: const Icon(Icons.chevron_right)),
              ]),
              SoftCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _row('Ventes hors ligne', '${r.ventes.length}'),
                  _row('Envoyées', '${r.compte(StatutVenteHL.envoyee)}'),
                  _row('Non envoyées', '${r.compte(StatutVenteHL.enAttente) + r.compte(StatutVenteHL.envoiEnCours)}'),
                  _row('Ressaisies sur le serveur', '${r.compte(StatutVenteHL.ressaisie)}'),
                  _row('Anomalies', '${r.compte(StatutVenteHL.aVerifier)}'),
                  const Divider(height: 14, color: Pal.line),
                  _row('Montant total', _f(r.montantTotal)),
                  _row('Espèces encaissées (provisoire)', _f(r.especes), strong: true),
                ]),
              ),
              const SizedBox(height: 12),
              const Text('TOTAL PAR PRODUIT (quantité sortie)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Pal.muted)),
              const SizedBox(height: 6),
              SoftCard(
                key: const Key('rapport_produits'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (r.produits.isEmpty) const Text('Aucun produit', style: TextStyle(color: Pal.muted)),
                  for (final p in r.produits)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.nom, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
                            if (p.cip.isNotEmpty) Text(p.cip, style: const TextStyle(fontSize: 12, color: Pal.muted)),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('× ${p.qte}', key: Key('total_produit_${p.produitId}'), style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.ink)),
                          Text(_f(p.montant), style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
                        ]),
                      ]),
                    ),
                  if (r.produits.isNotEmpty) ...[
                    const Divider(height: 14, color: Pal.line),
                    _row('Total', '${r.quantiteTotale} boîte(s)', strong: true),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              const Text('VENTES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Pal.muted)),
              const SizedBox(height: 6),
              for (final v in r.ventes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SoftCard(
                    padding: const EdgeInsets.all(10),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${v.numeroLabel} · ${h.format(v.createdAt)} · ${v.type.label}',
                              style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
                          Text(
                            '${statutCourt(v.statut)}${v.reference == null ? '' : ' → ${v.reference}'}${v.userName.isEmpty ? '' : ' · ${v.userName}'}',
                            style: const TextStyle(fontSize: 12.5, color: Pal.muted),
                          ),
                        ]),
                      ),
                      Text(_f(v.netEstime), style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.ink)),
                    ]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
