// lib/ordonnances/banc_essai/banc_essai_screen.dart
// Écran caché « Banc d'essai ordonnances » (Réglages › Ventes, code administrateur) :
// l'utilisateur choisit des images d'ordonnances (ou un dossier), l'appli exécute le pipeline de
// référence (scan actuel) et, au choix, un candidat, puis affiche le score par ordonnance et global.
// Historique local ; export texte / CSV sans le texte reconnu. Rien n'est envoyé au serveur
// (seule la recherche catalogue habituelle du scan est utilisée).
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/historique_banc.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/pipeline_ordonnance.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/pipelines_disponibles.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/score_banc.dart';
import 'package:prestige_vente_app/ordonnances/o4/banc_o4.dart';
import 'package:prestige_vente_app/services/product_finder.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';
import 'package:provider/provider.dart';

/// Choix d'images : renvoie les chemins, ou null si annulé.
typedef ChoixImages = Future<List<String>?> Function();

/// Export d'un rapport (nom de fichier proposé, contenu).
typedef ExportRapport = Future<void> Function(String nomFichier, String contenu);

class BancEssaiScreen extends StatefulWidget {
  /// Pipelines (tests) ; sinon [pipelinesBanc] sur le catalogue de l'[ApiService].
  final List<PipelineOrdonnance>? pipelines;
  final ChoixImages? choisirImages;
  final ChoixImages? choisirDossier;

  /// Vérité terrain (tests) ; sinon l'asset [VeriteTerrain.asset].
  final VeriteTerrain? verite;
  final ExportRapport? exporter;

  const BancEssaiScreen({super.key, this.pipelines, this.choisirImages, this.choisirDossier, this.verite, this.exporter});

  @override
  State<BancEssaiScreen> createState() => _BancEssaiScreenState();
}

class _BancEssaiScreenState extends State<BancEssaiScreen> {
  late final List<PipelineOrdonnance> _pipelines =
      widget.pipelines ?? pipelinesBanc(apiPageSearch(Provider.of<ApiService>(context, listen: false)));
  VeriteTerrain? _verite;
  String? _veriteErreur;
  List<String> _images = [];
  late String _reference = _pipelines.first.id;
  String? _candidat;
  bool _running = false;
  int _done = 0, _total = 0;
  Map<String, ScoreGlobal> _scores = {};

  /// O4 : apprentissage simulé (2 passages, apprentissages en mémoire) pour un candidat qui apprend.
  bool _simule = false;
  bool get _candidatApprend => _candidat != null && _pipeline(_candidat!) is PipelineApprenant;
  List<EntreeHistorique> _historique = [];

  @override
  void initState() {
    super.initState();
    if (_pipelines.length > 1) _candidat = _pipelines[1].id;
    _chargerVerite();
    HistoriqueBanc.charger().then((h) {
      if (mounted) setState(() => _historique = h);
    });
  }

  Future<void> _chargerVerite() async {
    if (widget.verite != null) {
      _verite = widget.verite;
      return;
    }
    try {
      final s = await rootBundle.loadString(VeriteTerrain.asset);
      if (mounted) setState(() => _verite = VeriteTerrain.fromJsonString(s));
    } catch (e) {
      if (mounted) setState(() => _veriteErreur = 'Vérité terrain illisible : $e');
    }
  }

  PipelineOrdonnance _pipeline(String id) => _pipelines.firstWhere((p) => p.id == id);

  // ---------------------------------------------------------------------------
  // Choix des images
  // ---------------------------------------------------------------------------
  static const _extensions = ['jpg', 'jpeg', 'png', 'webp'];

  static Future<List<String>?> _pickImages() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true);
    if (r == null) return null;
    return [for (final f in r.files) if (f.path != null) f.path!];
  }

  static Future<List<String>?> _pickDossier() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return null;
    final files = <String>[];
    await for (final e in Directory(dir).list()) {
      if (e is File && _extensions.contains(e.path.split('.').last.toLowerCase())) files.add(e.path);
    }
    return files;
  }

  /// Tri naturel : « ordonnance (2) » avant « ordonnance (10) ».
  static int _ordre(String a, String b) {
    final na = VeriteTerrain.cleFichier(a), nb = VeriteTerrain.cleFichier(b);
    final ia = int.tryParse(RegExp(r'(\d+)').firstMatch(na)?.group(1) ?? '');
    final ib = int.tryParse(RegExp(r'(\d+)').firstMatch(nb)?.group(1) ?? '');
    final pa = na.replaceAll(RegExp(r'\d+.*'), ''), pb = nb.replaceAll(RegExp(r'\d+.*'), '');
    if (ia != null && ib != null && pa == pb) return ia.compareTo(ib);
    return na.compareTo(nb);
  }

  Future<void> _choisir(bool dossier) async {
    List<String>? paths;
    try {
      paths = await (dossier ? (widget.choisirDossier ?? _pickDossier) : (widget.choisirImages ?? _pickImages))();
    } catch (e) {
      _message(dossier ? 'Dossier illisible ($e). Choisissez plutôt les images.' : 'Choix impossible : $e');
      return;
    }
    if (paths == null || !mounted) return;
    if (paths.isEmpty) {
      _message('Aucune image trouvée.');
      return;
    }
    setState(() {
      _images = [...paths!]..sort(_ordre);
      _scores = {};
    });
  }

  void _message(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------------------------------------------------------------------
  // Exécution
  // ---------------------------------------------------------------------------
  Future<void> _lancer() async {
    final verite = _verite;
    if (_images.isEmpty || verite == null) return;
    final ids = [_reference, if (_candidat != null && _candidat != _reference) _candidat!];
    final simule = _simule && _candidatApprend && ids.length > 1;
    setState(() {
      _running = true;
      _done = 0;
      _total = _images.length * (ids.length + (simule ? 1 : 0));
      _scores = {};
    });
    final res = <String, ScoreGlobal>{};
    for (final id in ids) {
      final p = _pipeline(id);
      if (simule && p is PipelineApprenant) {
        // Apprentissage simulé : rien de réel n'est enregistré (ni apprentissage, ni historique).
        final s = await simulerApprentissage(p, _images, verite, progres: () {
          if (mounted) setState(() => _done++);
        });
        if (!mounted) return;
        res['${p.libelle} · 2ᵉ passage (après apprentissage simulé)'] = s.passage2;
        res['${p.libelle} · 1ᵉʳ passage (apprentissage de ${s.lignesApprises} ligne(s))'] = s.passage1;
        continue;
      }
      final par = <ScoreOrdonnance>[];
      for (final img in _images) {
        final nom = img.split(RegExp(r'[\\/]')).last;
        ResultatPipeline r;
        try {
          r = await p.analyser(img);
        } catch (e) {
          r = ResultatPipeline(produits: const [], erreur: 'Échec : ${e.runtimeType}');
        }
        par.add(BancScore.evaluer(nom, verite.pour(img), r.produits, erreur: r.erreur));
        if (!mounted) return;
        setState(() => _done++);
      }
      res[p.libelle] = ScoreGlobal(par);
    }
    var hist = _historique;
    for (final id in simule ? const <String>[] : ids) {
      final p = _pipeline(id);
      try {
        hist = await HistoriqueBanc.ajouter(EntreeHistorique.depuis(res[p.libelle]!, pipeline: p.libelle));
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _scores = res;
      _historique = hist;
      _running = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------
  Future<void> _exporter(bool csv) async {
    if (_scores.isEmpty) return;
    final stamp = DateTime.now().toIso8601String().substring(0, 16).replaceAll(RegExp(r'[:T]'), '-');
    final nom = 'banc_ordonnances_$stamp.${csv ? 'csv' : 'txt'}';
    final contenu = csv ? RapportBanc.csv(_scores) : RapportBanc.texte(_scores);
    try {
      if (widget.exporter != null) {
        await widget.exporter!(nom, contenu);
      } else if (csv) {
        final bytes = Uint8List.fromList(utf8.encode('﻿$contenu'));
        final out = await FilePicker.platform.saveFile(fileName: nom, bytes: bytes);
        if (out == null) return;
      } else {
        await Clipboard.setData(ClipboardData(text: contenu));
      }
      _message(csv ? 'Rapport CSV enregistré.' : 'Rapport copié (à coller dans un message).');
    } catch (e) {
      _message('Export impossible : $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Interface
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final verite = _verite;
    final avecVerite = verite == null ? 0 : _images.where((i) => verite.pour(i)?.scorable ?? false).length;
    return Scaffold(
      backgroundColor: Pal.page,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Pal.navy,
        title: const Text('Banc d\'essai ordonnances', style: TextStyle(fontWeight: FontWeight.bold, color: Pal.navy)),
      ),
      body: ContentWidth(
        child: ListView(
          key: const Key('banc_liste'),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            _bandeau('Mesure sur l\'appareil : les images et le texte lu ne quittent pas le téléphone et ne sont ni affichés '
                'ni exportés. Seule la recherche habituelle dans le catalogue est utilisée.'),
            if (_veriteErreur != null) _bandeau(_veriteErreur!, erreur: true),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                key: const Key('banc_images'),
                onPressed: _running ? null : () => _choisir(false),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choisir des images'),
              ),
              OutlinedButton.icon(
                key: const Key('banc_dossier'),
                onPressed: _running ? null : () => _choisir(true),
                icon: const Icon(Icons.folder_open),
                label: const Text('Choisir un dossier'),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              _images.isEmpty
                  ? 'Aucune image choisie. Nommez les images « ordonnance (N).jpeg » pour les comparer à la vérité terrain.'
                  : '${_images.length} image(s) choisie(s), dont $avecVerite avec vérité terrain.',
              key: const Key('banc_compte'),
              style: const TextStyle(color: Pal.muted),
            ),
            const SizedBox(height: 12),
            _choixPipeline('Référence', _reference, (v) => setState(() => _reference = v!), aucun: false),
            if (_pipelines.length > 1) ...[
              const SizedBox(height: 8),
              _choixPipeline('Candidat', _candidat, (v) => setState(() => _candidat = v), aucun: true),
            ],
            if (_candidatApprend)
              CheckboxListTile(
                key: const Key('banc_simule'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _simule,
                onChanged: _running ? null : (v) => setState(() => _simule = v ?? false),
                title: const Text('Apprentissage simulé (2 passages)'),
                subtitle: const Text('1ᵉʳ passage : les bonnes réponses sont apprises comme des corrections du pharmacien ; '
                    '2ᵉ passage : mesure. Rien n\'est enregistré ni envoyé.'),
              ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              key: const Key('banc_lancer'),
              style: navyButton,
              onPressed: _running || _images.isEmpty || verite == null ? null : _lancer,
              icon: const Icon(Icons.play_arrow),
              label: Text(_running ? 'Analyse $_done/$_total…' : 'Lancer la mesure'),
            ),
            if (_running) Padding(padding: const EdgeInsets.only(top: 8), child: LinearProgressIndicator(value: _total == 0 ? null : _done / _total)),
            if (_scores.isNotEmpty) ..._resultats(),
            const SizedBox(height: 16),
            _historiqueCarte(),
          ],
        ),
      ),
    );
  }

  Widget _bandeau(String texte, {bool erreur = false}) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: erreur ? const Color(0xFFFDECEC) : const Color(0xFFE3ECF7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(erreur ? Icons.error_outline : Icons.lock_outline, size: 18, color: erreur ? const Color(0xFFB91C1C) : Pal.navy),
          const SizedBox(width: 8),
          Expanded(child: Text(texte, style: TextStyle(fontSize: 12.5, color: erreur ? const Color(0xFF7F1D1D) : Pal.navy))),
        ]),
      );

  Widget _choixPipeline(String label, String? value, ValueChanged<String?> onChanged, {required bool aucun}) =>
      DropdownButtonFormField<String?>(
        key: Key('banc_choix_${label.toLowerCase()}'),
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true, filled: true, fillColor: Colors.white, border: const OutlineInputBorder()),
        items: [
          if (aucun) const DropdownMenuItem<String?>(value: null, child: Text('Aucun')),
          for (final p in _pipelines)
            DropdownMenuItem<String?>(value: p.id, child: Text(p.libelle, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: _running ? null : onChanged,
      );

  List<Widget> _resultats() {
    final entries = _scores.entries.toList();
    final ref = entries.first.value;
    final cand = entries.length > 1 ? entries[1].value : null;
    return [
      const SizedBox(height: 16),
      for (final e in entries) _carteGlobale(e.key, e.value),
      if (cand != null) _verdict(ref, cand),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          key: const Key('banc_export_texte'),
          onPressed: () => _exporter(false),
          icon: const Icon(Icons.copy),
          label: const Text('Copier le rapport'),
        ),
        OutlinedButton.icon(
          key: const Key('banc_export_csv'),
          onPressed: () => _exporter(true),
          icon: const Icon(Icons.table_view),
          label: const Text('Enregistrer en CSV'),
        ),
      ]),
      const SizedBox(height: 12),
      const Text('Par ordonnance', style: TextStyle(fontWeight: FontWeight.w700, color: Pal.ink)),
      const SizedBox(height: 6),
      for (var i = 0; i < ref.ordonnances.length; i++) _carteOrdonnance(entries, i),
    ];
  }

  Widget _carteGlobale(String libelle, ScoreGlobal s) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(libelle, style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.navy)),
            const SizedBox(height: 6),
            Wrap(spacing: 16, runSpacing: 4, children: [
              _chiffre('Correctes', s.correctes),
              _chiffre('Rappel', ScoreGlobal.pourcent(s.rappel)),
              _chiffre('Précision', ScoreGlobal.pourcent(s.precision)),
              _chiffre('Trouvés', '${s.nbTrouves}/${s.nbAttendus}'),
              _chiffre('En trop', '${s.nbFauxPositifs}'),
            ]),
          ]),
        ),
      );

  Widget _chiffre(String label, String valeur) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(valeur, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.ink)),
        Text(label, style: const TextStyle(fontSize: 11.5, color: Pal.muted)),
      ]);

  Widget _verdict(ScoreGlobal ref, ScoreGlobal cand) {
    final mieux = cand.nbCorrectes > ref.nbCorrectes || (cand.nbCorrectes == ref.nbCorrectes && cand.rappel > ref.rappel && cand.precision >= ref.precision);
    final pire = cand.nbCorrectes < ref.nbCorrectes || cand.rappel < ref.rappel;
    final (txt, color) = pire
        ? ('Candidat MOINS BON que la référence : ne pas l\'activer.', const Color(0xFFB91C1C))
        : mieux
            ? ('Candidat meilleur que la référence.', Pal.green)
            : ('Candidat équivalent à la référence.', Pal.muted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(txt, key: const Key('banc_verdict'), style: TextStyle(fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _carteOrdonnance(List<MapEntry<String, ScoreGlobal>> entries, int i) {
    final first = entries.first.value.ordonnances[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ExpansionTile(
        key: Key('banc_ord_$i'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text(first.fichier, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [for (final e in entries) '${entries.length > 1 ? '${e.key.split(' ').first} ' : ''}${e.value.ordonnances[i].statut}'].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          first.entierementCorrecte ? Icons.check_circle : (first.compte ? Icons.error_outline : Icons.help_outline),
          color: first.entierementCorrecte ? Pal.green : (first.compte ? Pal.amber : Pal.muted),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in entries) ...[
            if (entries.length > 1) Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.navy)),
            ..._details(e.value.ordonnances[i]),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  List<Widget> _details(ScoreOrdonnance o) {
    Widget l(IconData icon, Color c, String t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 6),
            Expanded(child: Text(t, style: const TextStyle(fontSize: 13))),
          ]),
        );
    return [
      if (o.verite?.doublonDe != null)
        l(Icons.copy_all, Pal.muted, 'Doublon de ${o.verite!.doublonDe} : exclue du score.')
      else if (o.verite != null && !o.verite!.scorable)
        l(Icons.edit_note, Pal.muted, 'Vérité à compléter : exclue du score.'),
      if (o.verite == null) l(Icons.help_outline, Pal.muted, 'Pas de vérité terrain pour ce fichier : exclue du score.'),
      for (final t in o.trouves) l(Icons.check, Pal.green, '${t.$1.nom} → ${t.$2}'),
      for (final m in o.manques) l(Icons.close, const Color(0xFFB91C1C), 'Manqué : ${m.nom}'),
      for (final f in o.fauxPositifs) l(Icons.add_circle_outline, Pal.amber, 'En trop : $f'),
      if (!o.compte)
        for (final p in o.proposes) l(Icons.remove, Pal.muted, 'Proposé : $p'),
      if (o.erreur != null) l(Icons.warning_amber, const Color(0xFFB91C1C), o.erreur!),
    ];
  }

  Widget _historiqueCarte() => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Historique (cet appareil)', style: TextStyle(fontWeight: FontWeight.w700, color: Pal.ink))),
              if (_historique.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await HistoriqueBanc.vider();
                    if (mounted) setState(() => _historique = []);
                  },
                  child: const Text('Vider'),
                ),
            ]),
            if (_historique.isEmpty)
              const Text('Aucune mesure enregistrée.', style: TextStyle(color: Pal.muted))
            else
              for (final h in _historique.take(30))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '${_date(h.date)} · v${h.version} · ${h.pipeline} : ${h.correctes}/${h.comptees} correctes, '
                    'rappel ${ScoreGlobal.pourcent(h.rappel)}, précision ${ScoreGlobal.pourcent(h.precision)}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
          ]),
        ),
      );

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
