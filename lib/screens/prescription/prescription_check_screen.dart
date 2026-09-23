// lib/screens/prescription/prescription_check_screen.dart
// Scan d'ordonnance : photo -> reconnaissance du texte (sur le téléphone, hors ligne)
// -> extraction des produits -> vérification de la disponibilité dans le stock Prestige.
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/services/prescription_parser.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

/// Lit le texte d'une ordonnance à partir d'une source d'image. Renvoie les lignes
/// reconnues, ou `null` si l'opérateur a annulé la prise de vue.
typedef PrescriptionTextReader = Future<List<String>?> Function(ImageSource source);

class PrescriptionCheckScreen extends StatefulWidget {
  /// Permet de remplacer la lecture (tests). Par défaut : appareil photo + ML Kit.
  final PrescriptionTextReader? textReader;

  const PrescriptionCheckScreen({super.key, this.textReader});

  @override
  State<PrescriptionCheckScreen> createState() => _PrescriptionCheckScreenState();
}

enum _LineStatus { searching, available, outOfStock, notFound }

class _RxLine {
  PrescriptionLine line;
  List<ProductSearchResult> matches = [];
  bool searching = true;
  _RxLine(this.line);

  ProductSearchResult? get best => matches.isEmpty ? null : matches.first;

  _LineStatus get status {
    if (searching) return _LineStatus.searching;
    final b = best;
    if (b == null) return _LineStatus.notFound;
    return b.intNUMBERAVAILABLE > 0 ? _LineStatus.available : _LineStatus.outOfStock;
  }
}

class _PrescriptionCheckScreenState extends State<PrescriptionCheckScreen> {
  final List<_RxLine> _lines = [];
  List<String> _ocrLines = [];
  bool _reading = false;
  bool _hasScanned = false;
  int _generation = 0; // Ignore les recherches d'une ordonnance précédente

  // ---------------------------------------------------------------------------
  // Lecture de l'ordonnance
  // ---------------------------------------------------------------------------
  Future<List<String>?> _defaultReader(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 92);
    if (file == null) return null;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(InputImage.fromFilePath(file.path));
      return [
        for (final block in recognized.blocks)
          for (final line in block.lines) line.text,
      ];
    } finally {
      recognizer.close();
    }
  }

  Future<void> _scan(ImageSource source) async {
    setState(() => _reading = true);
    List<String>? lines;
    try {
      lines = await (widget.textReader ?? _defaultReader)(source);
    } catch (e) {
      if (mounted) Constants.showSnackBar(context, 'Lecture impossible : $e', isError: true);
    }
    if (!mounted) return;
    setState(() => _reading = false);
    if (lines == null) return;

    final generation = ++_generation;
    final candidates = PrescriptionParser.extract(lines);
    setState(() {
      _hasScanned = true;
      _ocrLines = lines!.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      _lines
        ..clear()
        ..addAll(candidates.map(_RxLine.new));
    });
    if (candidates.isEmpty) {
      Constants.showSnackBar(context, 'Aucun produit reconnu. Ajoutez-les depuis le texte lu ou manuellement.', isError: true);
    }
    for (final rx in List.of(_lines)) {
      await _search(rx, generation);
    }
  }

  Future<void> _search(_RxLine rx, int generation) async {
    final api = Provider.of<ApiService>(context, listen: false);
    setState(() => rx.searching = true);
    List<ProductSearchResult> results = [];
    for (final q in PrescriptionParser.searchQueries(rx.line)) {
      results = await api.searchProducts(q);
      if (results.isNotEmpty) break;
    }
    if (!mounted || generation != _generation) return;

    final scored = [for (final p in results) MapEntry(p, PrescriptionParser.score(rx.line, p.strNAME))];
    scored.sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      if (byScore != 0) return byScore;
      return b.key.intNUMBERAVAILABLE.compareTo(a.key.intNUMBERAVAILABLE);
    });
    setState(() {
      rx.matches = scored.take(5).map((e) => e.key).toList();
      rx.searching = false;
    });
  }

  void _reset() {
    setState(() {
      _generation++;
      _lines.clear();
      _ocrLines = [];
      _hasScanned = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Correction par l'opérateur
  // ---------------------------------------------------------------------------
  Future<String?> _askText({required String title, String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ex : Doliprane 1000 mg cp'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text('Rechercher')),
        ],
      ),
    );
  }

  void _addLine(String text, {_RxLine? replace}) {
    final cleaned = PrescriptionParser.cleanLine(text) ?? text.trim();
    if (cleaned.isEmpty) return;
    final parsed = PrescriptionParser.parseLine(cleaned, force: true);
    if (parsed == null) {
      Constants.showSnackBar(context, 'Nom de produit illisible.', isError: true);
      return;
    }
    late _RxLine rx;
    setState(() {
      _hasScanned = true;
      if (replace != null) {
        rx = replace..line = parsed;
      } else {
        rx = _RxLine(parsed);
        _lines.add(rx);
      }
    });
    _search(rx, _generation);
  }

  Future<void> _editLine(_RxLine rx) async {
    final text = await _askText(title: 'Corriger le produit', initial: rx.line.text);
    if (text != null && mounted) _addLine(text, replace: rx);
  }

  Future<void> _addManual() async {
    final text = await _askText(title: 'Ajouter un produit');
    if (text != null && mounted) _addLine(text);
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vérification Ordonnance'),
        actions: [
          if (_hasScanned)
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Nouvelle ordonnance', onPressed: _reset),
        ],
      ),
      body: _reading
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Lecture de l\'ordonnance...'),
              ]),
            )
          : _hasScanned
              ? _buildResults()
              : _buildStart(),
    );
  }

  Widget _buildStart() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long, size: 72, color: AppColors.primary),
            const SizedBox(height: 16),
            const Text(
              'Photographiez l\'ordonnance : les produits sont repérés puis\nleur disponibilité est vérifiée dans le stock.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.photo_camera),
                label: const Text('Photographier l\'ordonnance'),
                onPressed: () => _scan(ImageSource.camera),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.photo_library),
                label: const Text('Choisir une photo (galerie)'),
                onPressed: () => _scan(ImageSource.gallery),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              icon: const Icon(Icons.edit),
              label: const Text('Saisir les produits manuellement'),
              onPressed: _addManual,
            ),
            const SizedBox(height: 16),
            Text(
              'Conseil : photo à plat, bien éclairée, sans reflet. Les ordonnances manuscrites '
              'sont moins bien lues : corrigez ou ajoutez les produits si besoin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    final available = _lines.where((l) => l.status == _LineStatus.available).length;
    final out = _lines.where((l) => l.status == _LineStatus.outOfStock).length;
    final notFound = _lines.where((l) => l.status == _LineStatus.notFound).length;
    final usedTexts = _lines.map((l) => l.line.text).toSet();
    final unusedOcr = _ocrLines.where((l) => !usedTexts.contains(PrescriptionParser.cleanLine(l) ?? l)).toList();

    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        Card(
          color: Colors.blueGrey.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _summary('Produits', _lines.length, AppColors.primary),
                _summary('Disponibles', available, Colors.green.shade700),
                _summary('Rupture', out, Colors.red.shade700),
                _summary('Non trouvés', notFound, Colors.orange.shade800),
              ],
            ),
          ),
        ),
        for (final rx in _lines) _buildLineCard(rx),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter un produit'),
                  onPressed: _addManual,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Autre ordonnance'),
                  onPressed: () => _scan(ImageSource.camera),
                ),
              ),
            ],
          ),
        ),
        if (unusedOcr.isNotEmpty)
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.text_snippet_outlined),
              title: Text('Texte lu non retenu (${unusedOcr.length} lignes)'),
              subtitle: const Text('Touchez une ligne pour l\'ajouter comme produit'),
              children: [
                for (final l in unusedOcr)
                  ListTile(
                    dense: true,
                    title: Text(l),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => _addLine(l),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _summary(String label, int value, Color color) {
    return Column(
      children: [
        Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildLineCard(_RxLine rx) {
    final (Color color, IconData icon, String label) = switch (rx.status) {
      _LineStatus.searching => (Colors.grey, Icons.hourglass_empty, 'Recherche...'),
      _LineStatus.available => (Colors.green.shade700, Icons.check_circle, 'Disponible'),
      _LineStatus.outOfStock => (Colors.red.shade700, Icons.cancel, 'Rupture'),
      _LineStatus.notFound => (Colors.orange.shade800, Icons.help, 'Non trouvé'),
    };
    final alternativeInStock = rx.status == _LineStatus.outOfStock && rx.matches.skip(1).any((p) => p.intNUMBERAVAILABLE > 0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rx.line.text, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        alternativeInStock ? '$label (autre présentation disponible)' : label,
                        style: TextStyle(color: color, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.edit, size: 20), tooltip: 'Corriger', onPressed: () => _editLine(rx)),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Retirer',
                  onPressed: () => setState(() => _lines.remove(rx)),
                ),
              ],
            ),
            if (rx.searching) const LinearProgressIndicator(),
            for (final p in rx.matches)
              Padding(
                padding: const EdgeInsets.only(left: 32.0, top: 4.0, right: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${p.strNAME}\nCIP: ${p.intCIP} | ${Constants.formatNumber(p.intPRICE)} F',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: p.intNUMBERAVAILABLE > 0 ? Colors.green.shade50 : Colors.red.shade50,
                      label: Text(
                        p.intNUMBERAVAILABLE > 0 ? 'Stock ${p.intNUMBERAVAILABLE}' : 'Rupture',
                        style: TextStyle(
                          color: p.intNUMBERAVAILABLE > 0 ? Colors.green.shade800 : Colors.red.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
