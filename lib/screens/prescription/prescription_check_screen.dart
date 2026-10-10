// lib/screens/prescription/prescription_check_screen.dart
// Ordonnance : photo ou PDF -> reconnaissance du texte (sur l'appareil, hors ligne)
// -> un produit du stock par ligne (CIP exact en priorité) -> disponibilité
// -> transformation en pré-vente (circuit Pré/Vente existant).
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/ventes/ventes_version.dart';
import 'package:prestige_vente_app/services/ocr_service.dart';
import 'package:prestige_vente_app/services/prescription_parser.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/services/product_finder.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
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

  /// Présentation imposée (tests) ; sinon celle choisie sur l'appareil (A par défaut).
  final ListPresentation? presentation;

  const PrescriptionCheckScreen({super.key, this.textReader, this.openPrevente, this.presentation});

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
  late ListPresentation _style = widget.presentation ?? ListPresentation.dashboard;

  @override
  void initState() {
    super.initState();
    if (widget.presentation == null) {
      PresentationPrefs.load().then((p) {
        if (mounted) setState(() => _style = p);
      });
    }
  }

  void _setStyle(ListPresentation p) {
    setState(() => _style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

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
  /// Nombre maximal de produits examinés pour un nom (pages de 50).
  static const int _maxNameResults = 200;

  Future<void> _search(_RxLine rx, int generation) async {
    final api = Provider.of<ApiService>(context, listen: false);
    setState(() => rx.searching = true);

    ProductSearchResult? chosen;
    var match = _Match.none;
    var alternatives = <ProductSearchResult>[];

    final search = apiPageSearch(api);
    String? failure; // panne (≠ produit introuvable)

    final cip = rx.line.cip;
    if (cip != null) {
      // Code exact, quel que soit le nombre de produits qui commencent pareil
      // (avec les variantes : EAN-13 34009… → CIP7). Seul un produit portant l'un de ces codes est retenu.
      final r = await ProductLookup.byCode(cip, search);
      final found = r.valueOrNull;
      if (found == null) failure = r.message;
      final exact = found?.exact;
      if (exact != null && found!.tried.contains(exact.intCIP.trim())) {
        chosen = exact;
        match = _Match.exactCip;
      }
    }

    if (chosen == null) {
      List<ProductSearchResult> results = [];
      for (final q in PrescriptionParser.searchQueries(rx.line)) {
        // Plusieurs pages (jusqu'à _maxNameResults produits) au lieu des 30 premiers seulement.
        // Toujours « commence par », texte envoyé tel quel (pas de réglage « Contient ») : la
        // correspondance (1ʳᵉ requête non vide, score, limite) suppose cette recherche.
        final pager = ProductPager(search, q);
        while (pager.items.length < _maxNameResults && (pager.total == 0 || pager.hasMore)) {
          if (!await pager.loadMore()) {
            failure = pager.error;
            break;
          }
          if (pager.total == 0) break;
        }
        results = List.of(pager.items);
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
    if (chosen == null && failure != null) {
      _showError('Recherche impossible pour « ${rx.line.text} » : $failure');
    }

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
        (ctx) => Navigator.of(ctx).push(MaterialPageRoute(
              builder: (_) => VentesVersion.preVente(initialTabIndex: 0, resumeVenteId: sale.currentVenteId),
            ));
    await open(context);
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final sellable = _lines.where((l) => l.canBeSold).length;
    final bottom = _hasScanned && !_reading
        ? SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                style: navyButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(50))),
                icon: _creating
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.point_of_sale),
                label: Text('Créer la pré-vente ($sellable produit${sellable > 1 ? 's' : ''})'),
                onPressed: sellable == 0 || _creating || _lines.any((l) => l.searching) ? null : _createPrevente,
              ),
            ),
          )
        : null;
    final body = _reading
        ? const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Lecture de l\'ordonnance...'),
            ]),
          )
        : _hasScanned
            ? _buildResults()
            : _buildStart();
    final actions = [
      PresentationMenuButton(value: _style, onChanged: _setStyle, color: _style == ListPresentation.compact ? Pal.navy : Colors.white),
      if (_hasScanned)
        IconButton(
          icon: Icon(Icons.refresh, color: _style == ListPresentation.compact ? Pal.navy : Colors.white),
          tooltip: 'Nouvelle ordonnance',
          onPressed: _reset,
        ),
    ];

    switch (_style) {
      case ListPresentation.compact:
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: Pal.navy,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: const Text('Vérification Ordonnance', style: TextStyle(fontWeight: FontWeight.bold, color: Pal.navy)),
            actions: actions,
            bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Pal.line)),
          ),
          bottomNavigationBar: bottom,
          body: body,
        );
      case ListPresentation.dashboard:
      case ListPresentation.guided:
        final dashboard = _style == ListPresentation.dashboard;
        return Scaffold(
          backgroundColor: dashboard ? Pal.page : const Color(0xFFEEF2F7),
          bottomNavigationBar: bottom,
          body: Column(children: [
            NavyHeader(
              title: 'Vérification ordonnance',
              subtitle: dashboard ? 'Ordonnance -> stock -> pré-vente' : null,
              rounded: dashboard,
              actions: actions,
              children: [
                if (!dashboard)
                  StepsBar(active: _hasScanned ? 1 : 0, steps: [
                    (title: 'Ordonnance', detail: 'photo ou PDF', onTap: null),
                    (title: 'Vérification', detail: _hasScanned ? '${_lines.length} produit(s)' : 'stock, CIP', onTap: null),
                    (title: 'Pré-vente', detail: 'en caisse', onTap: null),
                  ]),
                if (dashboard && _hasScanned && !_reading) _headerKpis(),
              ],
            ),
            Expanded(child: body),
          ]),
        );
    }
  }

  Widget _headerKpis() {
    int count(_LineStatus st) => _lines.where((l) => l.status == st).length;
    return Row(children: [
      Expanded(child: KpiTile('${_lines.length}', 'produits')),
      const SizedBox(width: 6),
      Expanded(child: KpiTile('${count(_LineStatus.available)}', 'disponibles')),
      const SizedBox(width: 6),
      Expanded(child: KpiTile('${count(_LineStatus.outOfStock)}', 'en rupture')),
      const SizedBox(width: 6),
      Expanded(child: KpiTile('${count(_LineStatus.notFound)}', 'non trouvés', highlight: count(_LineStatus.notFound) > 0)),
    ]);
  }

  /// Les quatre façons de commencer (mêmes actions dans toutes les présentations).
  List<({IconData icon, String label, String hint, VoidCallback onTap})> get _startOptions => [
        (icon: Icons.photo_camera, label: 'Photographier l\'ordonnance', hint: 'À plat, bien éclairée', onTap: () => _scan(PrescriptionSource.camera)),
        (icon: Icons.picture_as_pdf, label: 'Importer un PDF (recommandé)', hint: 'Lecture la plus fiable', onTap: () => _scan(PrescriptionSource.pdf)),
        (icon: Icons.photo_library, label: 'Choisir une photo (galerie)', hint: 'Photo déjà prise', onTap: () => _scan(PrescriptionSource.gallery)),
        (icon: Icons.edit, label: 'Saisir les produits manuellement', hint: 'Sans document', onTap: _addManual),
      ];

  static const _startHelp = 'PDF : lecture la plus fiable. Photo : à plat, bien éclairée, sans reflet. '
      'Les ordonnances manuscrites sont moins bien lues : corrigez ou ajoutez les produits si besoin.';

  Widget _buildStart() => switch (_style) {
        ListPresentation.dashboard => _startDashboard(),
        ListPresentation.compact => _startCompact(),
        ListPresentation.guided => _startGuided(),
      };

  Widget _startDashboard() {
    final o = _startOptions;
    Widget tile(int i) => Expanded(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            elevation: 1,
            shadowColor: const Color(0x3314213D),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: o[i].onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 120),
                padding: const EdgeInsets.all(14),
                decoration: i == 1 ? BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Pal.amber, width: 2)) : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: const Color(0xFFE3ECF7), borderRadius: BorderRadius.circular(10)),
                    child: Icon(o[i].icon, color: Pal.navy),
                  ),
                  const SizedBox(height: 12),
                  Text(o[i].label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Pal.ink)),
                  Text(o[i].hint, style: const TextStyle(fontSize: 12, color: Pal.muted)),
                ]),
              ),
            ),
          ),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text(
        'Photographiez ou importez l\'ordonnance : chaque produit est rapproché du stock '
        '(par CIP quand il est présent), puis l\'ordonnance peut devenir une pré-vente.',
        style: TextStyle(fontSize: 13, color: Color(0xFF4A5A70)),
      ),
      const SizedBox(height: 14),
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [tile(0), const SizedBox(width: 12), tile(1)])),
      const SizedBox(height: 12),
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [tile(2), const SizedBox(width: 12), tile(3)])),
      const SizedBox(height: 16),
      Text(_startHelp, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
    ]);
  }

  Widget _startCompact() => ListView(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Photographiez ou importez l\'ordonnance : chaque produit est rapproché du stock '
            '(par CIP quand il est présent), puis l\'ordonnance peut devenir une pré-vente.',
            style: TextStyle(fontSize: 13, color: Color(0xFF4A5A70)),
          ),
        ),
        for (final o in _startOptions)
          InkWell(
            onTap: o.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
              child: Row(children: [
                Icon(o.icon, color: Pal.navy),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(o.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
                    Text(o.hint, style: const TextStyle(fontSize: 13, color: Pal.muted)),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: Pal.muted),
              ]),
            ),
          ),
        Padding(padding: const EdgeInsets.all(16), child: Text(_startHelp, style: TextStyle(color: Colors.grey.shade700, fontSize: 12))),
      ]);

  Widget _startGuided() {
    final o = _startOptions;
    return ListView(padding: const EdgeInsets.all(16), children: [
      SoftCard(
        band: Pal.amber,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Commencez par l\'ordonnance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.ink)),
          const Text('Le PDF donne la lecture la plus fiable ; la photo convient aussi.', style: TextStyle(fontSize: 13, color: Pal.muted)),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(style: amberButton, icon: Icon(o[1].icon), label: Text(o[1].label), onPressed: o[1].onTap),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(style: navyButton, icon: Icon(o[0].icon), label: Text(o[0].label), onPressed: o[0].onTap),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton.icon(style: outlineButton, icon: Icon(o[2].icon, size: 18), label: const Text('Galerie'), onPressed: o[2].onTap)),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(style: outlineButton, icon: Icon(o[3].icon, size: 18), label: const Text('Saisie manuelle'), onPressed: o[3].onTap)),
      ]),
      const SizedBox(height: 16),
      Text(_startHelp, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
    ]);
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
        // En présentation A, ces chiffres sont dans l'en-tête bleu.
        if (_style != ListPresentation.dashboard)
          Card(
            color: _style == ListPresentation.compact ? const Color(0xFFF8FAFC) : Colors.white,
            elevation: _style == ListPresentation.compact ? 0 : 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final w in [
                    _summary('Produits', _lines.length, AppColors.primary),
                    _summary('Disponibles', available, Colors.green.shade700),
                    _summary('Rupture', out, Colors.red.shade700),
                    _summary('Non trouvés', notFound, Colors.orange.shade800),
                  ])
                    Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: w)),
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
      elevation: _style == ListPresentation.compact ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_style == ListPresentation.compact ? 8 : 14),
        side: _style == ListPresentation.compact ? const BorderSide(color: Pal.line) : BorderSide.none,
      ),
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
                        const Expanded(child: Text('Pré-vente', overflow: TextOverflow.ellipsis)),
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
