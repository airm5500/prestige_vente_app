// lib/screens/prescription/prescription_check_screen.dart
// Ordonnance : photo ou PDF -> reconnaissance du texte (sur l'appareil, hors ligne)
// -> un produit du stock par ligne (CIP exact en priorité) -> disponibilité
// -> transformation en pré-vente (circuit Pré/Vente existant).
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/screens/pre_vente/pre_vente_screen.dart';
import 'package:prestige_vente_app/services/ocr_service.dart';
import 'package:prestige_vente_app/services/prescription_parser.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

/// Source de l'ordonnance.
enum PrescriptionSource { camera, gallery, pdf }

/// Lit le texte d'une ordonnance. Renvoie les lignes reconnues, ou `null` si annulé.
typedef PrescriptionTextReader = Future<List<String>?> Function(PrescriptionSource source);

class PrescriptionCheckScreen extends StatefulWidget {
  /// Permet de remplacer la lecture (tests). Par défaut : appareil photo / galerie / PDF + ML Kit.
  final PrescriptionTextReader? textReader;

  /// Ouverture de l'écran Pré/Vente après création (remplaçable pour les tests).
  final Future<void> Function(BuildContext context)? openPrevente;

  const PrescriptionCheckScreen({super.key, this.textReader, this.openPrevente});

  @override
  State<PrescriptionCheckScreen> createState() => _PrescriptionCheckScreenState();
}

enum _LineStatus { searching, available, outOfStock, notFound }

/// Qualité du rapprochement ligne d'ordonnance -> produit du stock.
enum _Match { exactCip, exactName, toVerify, manual, none }

class _RxLine {
  PrescriptionLine line;
  ProductSearchResult? selected;
  List<ProductSearchResult> alternatives = [];
  _Match match = _Match.none;
  bool searching = true;
  int quantity;
  bool include = true;
  _RxLine(this.line) : quantity = line.quantity ?? 1;

  _LineStatus get status {
    if (searching) return _LineStatus.searching;
    final s = selected;
    if (s == null) return _LineStatus.notFound;
    return s.intNUMBERAVAILABLE > 0 ? _LineStatus.available : _LineStatus.outOfStock;
  }

  bool get canBeSold => !searching && selected != null && include && quantity > 0;
}

class _PrescriptionCheckScreenState extends State<PrescriptionCheckScreen> {
  final List<_RxLine> _lines = [];
  List<String> _ocrLines = [];
  bool _reading = false;
  bool _hasScanned = false;
  bool _creating = false;
  int _generation = 0; // Ignore les recherches d'une ordonnance précédente

  // ---------------------------------------------------------------------------
  // Lecture de l'ordonnance
  // ---------------------------------------------------------------------------
  Future<List<String>?> _defaultReader(PrescriptionSource source) {
    switch (source) {
      case PrescriptionSource.camera:
        return OcrService.captureAndRead(ImageSource.camera);
      case PrescriptionSource.gallery:
        return OcrService.captureAndRead(ImageSource.gallery);
      case PrescriptionSource.pdf:
        return OcrService.pickPdfAndRead();
    }
  }

  Future<void> _scan(PrescriptionSource source) async {
    setState(() => _reading = true);
    List<String>? lines;
    try {
      lines = await (widget.textReader ?? _defaultReader)(source);
    } catch (e) {
      if (mounted) _showError(OcrService.friendlyError(e));
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error, duration: const Duration(seconds: 6)),
    );
  }

  /// Rapprochement d'une ligne avec le stock :
  /// 1) CIP lu -> uniquement le produit ayant exactement ce CIP ;
  /// 2) sinon nom identique -> ce produit ;
  /// 3) sinon meilleur candidat, marqué "à vérifier" (les autres restent accessibles via "Changer").
  Future<void> _search(_RxLine rx, int generation) async {
    final api = Provider.of<ApiService>(context, listen: false);
    setState(() => rx.searching = true);

    ProductSearchResult? chosen;
    var match = _Match.none;
    var alternatives = <ProductSearchResult>[];

    final cip = rx.line.cip;
    if (cip != null) {
      final byCip = await api.searchProducts(cip);
      final exact = byCip.where((p) => p.intCIP.trim() == cip).toList();
      if (exact.length == 1) {
        chosen = exact.first;
        match = _Match.exactCip;
      }
    }

    if (chosen == null) {
      List<ProductSearchResult> results = [];
      for (final q in PrescriptionParser.searchQueries(rx.line)) {
        results = await api.searchProducts(q);
        if (results.isNotEmpty) break;
      }
      final wanted = PrescriptionParser.comparableName(rx.line.text);
      final sameName = results.where((p) => PrescriptionParser.comparableName(p.strNAME) == wanted).toList();
      if (sameName.length == 1) {
        chosen = sameName.first;
        match = _Match.exactName;
      } else {
        final scored = [for (final p in results) MapEntry(p, PrescriptionParser.score(rx.line, p.strNAME))]
          ..sort((a, b) {
            final byScore = b.value.compareTo(a.value);
            return byScore != 0 ? byScore : b.key.intNUMBERAVAILABLE.compareTo(a.key.intNUMBERAVAILABLE);
          });
        final relevant = scored.where((e) => e.value > 0).map((e) => e.key).toList();
        if (relevant.isNotEmpty) {
          chosen = relevant.first;
          match = _Match.toVerify;
          alternatives = relevant.skip(1).take(15).toList();
        }
      }
      if (chosen != null && alternatives.isEmpty) {
        alternatives = results.where((p) => p.lgFAMILLEID != chosen!.lgFAMILLEID).take(15).toList();
      }
    }
    if (!mounted || generation != _generation) return;

    setState(() {
      rx.selected = chosen;
      rx.match = match;
      rx.alternatives = alternatives;
      rx.include = chosen != null && chosen.intNUMBERAVAILABLE > 0;
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
          decoration: const InputDecoration(hintText: 'Ex : Doliprane 1000 mg cp, ou un CIP'),
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
    final parsed = PrescriptionParser.parseLine(cleaned) ?? PrescriptionParser.parseLine(cleaned, force: true);
    if (parsed == null) {
      Constants.showSnackBar(context, 'Nom de produit illisible.', isError: true);
      return;
    }
    late _RxLine rx;
    setState(() {
      _hasScanned = true;
      if (replace != null) {
        rx = replace
          ..line = parsed
          ..quantity = parsed.quantity ?? replace.quantity;
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

  Future<void> _changeProduct(_RxLine rx) async {
    final choices = [if (rx.selected != null) rx.selected!, ...rx.alternatives];
    final picked = await showModalBottomSheet<ProductSearchResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Produit pour « ${rx.line.text} »', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in choices)
                      ListTile(
                        title: Text(p.strNAME),
                        subtitle: Text('CIP: ${p.intCIP} | ${Constants.formatNumber(p.intPRICE)} F'),
                        trailing: _stockChip(p),
                        selected: p.lgFAMILLEID == rx.selected?.lgFAMILLEID,
                        onTap: () => Navigator.of(ctx).pop(p),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (rx.selected != null && rx.selected!.lgFAMILLEID != picked.lgFAMILLEID) {
        rx.alternatives = [rx.selected!, ...rx.alternatives.where((p) => p.lgFAMILLEID != picked.lgFAMILLEID)];
      }
      rx.selected = picked;
      rx.match = _Match.manual;
      rx.include = true;
    });
  }

  // ---------------------------------------------------------------------------
  // Transformation en pré-vente (même circuit que l'écran Pré/Vente)
  // ---------------------------------------------------------------------------
  Future<void> _createPrevente() async {
    final toSell = _lines.where((l) => l.canBeSold).toList();
    if (toSell.isEmpty) return;
    final sale = Provider.of<SaleProvider>(context, listen: false);

    final toVerify = toSell.where((l) => l.match == _Match.toVerify).length;
    final outOfStock = toSell.where((l) => l.status == _LineStatus.outOfStock).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Créer la pré-vente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in toSell) Text('• ${l.quantity} x ${l.selected!.strNAME}'),
            if (toVerify > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('$toVerify produit(s) "à vérifier" : contrôlez-les avant de valider.',
                    style: TextStyle(color: Colors.orange.shade900)),
              ),
            if (outOfStock > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('$outOfStock produit(s) en rupture de stock.', style: TextStyle(color: Colors.red.shade800)),
              ),
            if (sale.currentVenteId != null)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text('Une vente est déjà ouverte à l\'écran Pré/Vente : elle reste dans la liste des pré-ventes.'),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Créer')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _creating = true);
    sale.startNewSale();
    final failed = <String>[];
    for (final l in toSell) {
      final before = sale.cartItems.length;
      final venteBefore = sale.currentVenteId;
      await sale.addProductToCart(l.selected!, l.quantity, isPrevente: true);
      final added = sale.currentVenteId != null && (sale.cartItems.length > before || venteBefore == null);
      if (!added) failed.add(l.selected!.strNAME);
    }
    if (!mounted) return;
    setState(() => _creating = false);

    if (sale.currentVenteId == null) {
      _showError('Création de la pré-vente impossible (connexion ou caisse). Aucun produit ajouté.');
      return;
    }
    if (failed.isNotEmpty) _showError('Non ajouté(s) : ${failed.join(', ')}');
    // L'écran Pré/Vente existant affiche la pré-vente : l'opérateur la vérifie puis l'enregistre.
    final open = widget.openPrevente ??
        (ctx) => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const PreVenteScreen(initialTabIndex: 0)));
    await open(context);
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final sellable = _lines.where((l) => l.canBeSold).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vérification Ordonnance'),
        actions: [
          if (_hasScanned)
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Nouvelle ordonnance', onPressed: _reset),
        ],
      ),
      bottomNavigationBar: _hasScanned && !_reading
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  icon: _creating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.point_of_sale),
                  label: Text('Créer la pré-vente ($sellable produit${sellable > 1 ? 's' : ''})'),
                  onPressed: sellable == 0 || _creating || _lines.any((l) => l.searching) ? null : _createPrevente,
                ),
              ),
            )
          : null,
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
              'Photographiez ou importez l\'ordonnance : chaque produit est rapproché du stock '
              '(par CIP quand il est présent), puis l\'ordonnance peut devenir une pré-vente.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.photo_camera),
                label: const Text('Photographier l\'ordonnance'),
                onPressed: () => _scan(PrescriptionSource.camera),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Importer un PDF (recommandé)'),
                onPressed: () => _scan(PrescriptionSource.pdf),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.photo_library),
                label: const Text('Choisir une photo (galerie)'),
                onPressed: () => _scan(PrescriptionSource.gallery),
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
              'PDF : lecture la plus fiable. Photo : à plat, bien éclairée, sans reflet. '
              'Les ordonnances manuscrites sont moins bien lues : corrigez ou ajoutez les produits si besoin.',
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
    final usedTexts = _lines.map((l) => PrescriptionParser.comparableName(l.line.text)).toSet();
    final unusedOcr = _ocrLines.where((l) {
      final c = PrescriptionParser.comparableName(l);
      return !usedTexts.any((u) => u.isNotEmpty && c.contains(u));
    }).toList();

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
                  onPressed: () => _scan(PrescriptionSource.camera),
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

  Widget _stockChip(ProductSearchResult p) {
    final ok = p.intNUMBERAVAILABLE > 0;
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: ok ? Colors.green.shade50 : Colors.red.shade50,
      label: Text(
        ok ? 'Stock ${p.intNUMBERAVAILABLE}' : 'Rupture',
        style: TextStyle(color: ok ? Colors.green.shade800 : Colors.red.shade800, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _matchBadge(_Match m) {
    final (String text, Color color) = switch (m) {
      _Match.exactCip => ('CIP identique', Colors.green.shade800),
      _Match.exactName => ('Nom identique', Colors.green.shade800),
      _Match.manual => ('Choisi par l\'opérateur', AppColors.primary),
      _Match.toVerify => ('À vérifier', Colors.orange.shade900),
      _Match.none => ('', Colors.grey),
    };
    return Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600));
  }

  Widget _buildLineCard(_RxLine rx) {
    final (Color color, IconData icon, String label) = switch (rx.status) {
      _LineStatus.searching => (Colors.grey, Icons.hourglass_empty, 'Recherche...'),
      _LineStatus.available => (Colors.green.shade700, Icons.check_circle, 'Disponible'),
      _LineStatus.outOfStock => (Colors.red.shade700, Icons.cancel, 'Rupture'),
      _LineStatus.notFound => (Colors.orange.shade800, Icons.help, 'Non trouvé'),
    };
    final details = [
      if (rx.line.cip != null) 'CIP lu : ${rx.line.cip}',
      if (rx.line.quantity != null) 'Qté prescrite : ${rx.line.quantity}',
      if (rx.line.posology != null) rx.line.posology!,
    ].join('  ·  ');
    final p = rx.selected;

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
                      if (details.isNotEmpty) Text(details, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
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
            if (p != null)
              Padding(
                padding: const EdgeInsets.only(left: 32.0, top: 4.0, right: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.strNAME, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text('CIP: ${p.intCIP} | ${Constants.formatNumber(p.intPRICE)} F', style: const TextStyle(fontSize: 12)),
                              _matchBadge(rx.match),
                            ],
                          ),
                        ),
                        _stockChip(p),
                      ],
                    ),
                    Row(
                      children: [
                        Checkbox(
                          value: rx.include,
                          onChanged: (v) => setState(() => rx.include = v ?? false),
                        ),
                        const Text('Pré-vente'),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: rx.quantity > 1 ? () => setState(() => rx.quantity--) : null,
                        ),
                        Text('${rx.quantity}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setState(() => rx.quantity++),
                        ),
                        if (rx.alternatives.isNotEmpty)
                          TextButton(onPressed: () => _changeProduct(rx), child: const Text('Changer')),
                      ],
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
