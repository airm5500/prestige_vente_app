// lib/screens/stock_report/stock_report_screen.dart
// État de Stock : recherche (nom, CIP, scan), filtre de stock, emplacement.
// Présentations A (tableau de bord, défaut), B (liste groupée), C (parcours guidé).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/rayon.dart';
import 'package:prestige_vente_app/api/models/stock_report_models.dart';
import 'package:prestige_vente_app/providers/stock_report_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

class StockReportScreen extends StatefulWidget {
  /// Présentation imposée (tests) ; sinon celle choisie sur l'appareil (A par défaut).
  final ListPresentation? presentation;

  const StockReportScreen({super.key, this.presentation});

  @override
  State<StockReportScreen> createState() => _StockReportScreenState();
}

class _StockReportScreenState extends State<StockReportScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  // Contrôles de saisie
  static const maxQueryLength = 60;
  static const maxStockDigits = 5; // ≤ 99999
  static final _controlChars = RegExp(r'[\u0000-\u001F\u007F]');

  final _searchController = TextEditingController();
  final _stockValueController = TextEditingController();

  final _searchFocusNode = FocusNode();
  final _stockValueFocusNode = FocusNode();

  Timer? _queryDebounce;
  Timer? _valueDebounce;

  String? _selectedRayonId;
  StockFilterType? _selectedFilterType;
  bool _detailOpen = false;

  static const _filterLabels = {
    StockFilterType.EQUAL: 'Égal à (=)',
    StockFilterType.GREATER: 'Supérieur à (>)',
    StockFilterType.LESS: 'Inférieur à (<)',
    StockFilterType.GREATER_EQUAL: 'Sup. ou égal (>=)',
    StockFilterType.LESS_EQUAL: 'Inf. ou égal (<=)',
  };

  @override
  void initState() {
    super.initState();
    loadPresentation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = Provider.of<StockReportProvider>(context, listen: false);
      provider.loadFiltersData();
      provider.clearFilters();

      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _stockValueController.dispose();
    _searchFocusNode.dispose();
    _stockValueFocusNode.dispose();
    _queryDebounce?.cancel();
    _valueDebounce?.cancel();
    super.dispose();
  }

  StockReportProvider get _provider => Provider.of<StockReportProvider>(context, listen: false);

  /// Texte de recherche nettoyé (espaces, caractères de contrôle, longueur).
  static String cleanQuery(String v) {
    final s = v.replaceAll(_controlChars, '').trim();
    return s.length > maxQueryLength ? s.substring(0, maxQueryLength) : s;
  }

  /// Valeur de stock : chiffres seulement, 0 à 99999 ; '' si vide ou invalide.
  static String cleanStockValue(String v) {
    final t = v.trim();
    if (t.isEmpty || t.length > maxStockDigits) return '';
    final n = int.tryParse(t);
    return (n == null || n < 0) ? '' : '$n';
  }

  void _onSearchChanged(String value) {
    _queryDebounce?.cancel();
    _queryDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final q = cleanQuery(value);
      // Même recherche : pas de nouvelle requête.
      if (q == _provider.searchQuery) return;
      _provider.setQuery(q);
    });
  }

  void _onStockValueChanged(String value) {
    setState(() {}); // rafraîchit l'indication « valeur à saisir »
    _valueDebounce?.cancel();
    _valueDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final v = cleanStockValue(value);
      if (v == _provider.stockValue) return;
      _provider.setStockValue(v);
    });
  }

  void _onClearFilters() {
    _queryDebounce?.cancel();
    _valueDebounce?.cancel();
    _searchController.clear();
    _stockValueController.clear();

    setState(() {
      _selectedRayonId = null;
      _selectedFilterType = null;
    });

    _provider.clearFilters();

    _searchFocusNode.requestFocus();
  }

  void _onFilterTypeChanged(StockFilterType? val) {
    final provider = _provider;
    setState(() => _selectedFilterType = val);
    if (val == null) {
      _valueDebounce?.cancel();
      _stockValueController.clear();
      provider.setStockValue('');
      provider.setStockFilter(null);
    } else {
      provider.setStockFilter(val);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).requestFocus(_stockValueFocusNode);
      });
    }
  }

  void _onRayonChanged(String? val, List<Rayon> rayons) {
    // Seules les valeurs de la liste du serveur sont acceptées.
    final id = (val != null && rayons.any((r) => r.id == val)) ? val : null;
    setState(() => _selectedRayonId = id);
    _provider.setRayon(id ?? '');

    // MODIFICATION : Focus retour à la recherche
    _searchFocusNode.requestFocus();
  }

  /// Emplacements du serveur, sans doublon ni identifiant vide (sinon la liste déroulante plante).
  static List<Rayon> uniqueRayons(List<Rayon> rayons) {
    final seen = <String>{};
    return [
      for (final r in rayons)
        if (r.id.isNotEmpty && seen.add(r.id)) r
    ];
  }

  bool _hasCriteria(StockReportProvider p) =>
      p.searchQuery.isNotEmpty || p.selectedRayonId.isNotEmpty || p.selectedGrossisteId.isNotEmpty || p.selectedStockFilter != null;

  // ---------------------------------------------------------------------------
  // Détail d'un article
  // ---------------------------------------------------------------------------
  Future<void> _showDetailDialog(StockReportItem item) async {
    if (_detailOpen) return; // pas de double ouverture
    _detailOpen = true;
    final grossisteName = _provider.getGrossisteName(item.grossisteId);
    final (label, fg, bg) = _status(item);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_txt(item.libelle),
              maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Pal.ink, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          StatusBadge(label, fg: fg, bg: bg),
        ]),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow("Code (CIP):", item.code),
              _detailRow("Code EAN:", item.codeEan),
              _detailRow("Emplacement:", item.rayonLibelle),
              const Divider(),
              _detailRow("Stock:", item.stock.toString(), isBold: true, color: Pal.navy),
              _detailRow("Prix Vente:", Constants.formatNumber(item.prixVente)),
              _detailRow("Prix Achat:", Constants.formatNumber(item.prixAchat)),
              _detailRow("TVA:", item.tva),
              const Divider(),
              _detailRow("Grossiste:", grossisteName),
              _detailRow("Date Entrée:", item.dateEntree),
              _detailRow("Dernière Vente:", item.lastDateVente),
              _detailRow("Date Inventaire:", item.dateInventaire),
              const Divider(),
              _detailRow("Seuil Réappro:", item.seuiRappro.toString()),
              _detailRow("Qté à Réappro:", item.qteReappro.toString()),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Fermer'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
    _detailOpen = false;
  }

  Widget _detailRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(flex: 2, child: Text(label, style: const TextStyle(color: Pal.muted))),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value.trim().isEmpty ? '—' : value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: color ?? Pal.ink,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Affichage : A · Tableau de bord, B · Liste groupée, C · Parcours guidé
  // ---------------------------------------------------------------------------
  static String _txt(String v) => v.trim().isEmpty ? '—' : v.trim();

  /// Statut d'un article : rupture, sous le seuil de réappro, en stock.
  static (String, Color, Color) _status(StockReportItem i) {
    if (i.stock <= 0) return ('Rupture', const Color(0xFF9B1C1C), const Color(0xFFFDE7E7));
    if (i.seuiRappro > 0 && i.stock <= i.seuiRappro) return ('Sous seuil', const Color(0xFF8A5300), const Color(0xFFFFF1D6));
    return ('En stock', const Color(0xFF0B6B45), const Color(0xFFDCF5E7));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StockReportProvider>();
    final items = provider.reportItems;
    final hasCriteria = _hasCriteria(provider);
    final ruptures = items.where((i) => i.stock <= 0).length;
    final sousSeuil = items.where((i) => i.stock > 0 && i.seuiRappro > 0 && i.stock <= i.seuiRappro).length;
    final valeur = items.fold<int>(0, (s, i) => s + (i.stock > 0 ? i.stock * i.prixAchat : 0));
    final shown = hasCriteria && provider.loadError == null && !provider.isLoading;
    String n(int v) => shown ? Constants.formatNumber(v) : '—';

    return PresentationScaffold(
      style: style,
      title: 'État de Stock',
      subtitle: shown ? '${provider.totalItems} article(s) trouvé(s)' : 'Nom, CIP, emplacement, niveau de stock',
      actions: (col) => [
        PresentationMenuButton(value: style, onChanged: _setStyle, color: col),
        IconButton(
          icon: Icon(Icons.cleaning_services, color: col),
          tooltip: 'Vider les filtres',
          onPressed: _onClearFilters,
        ),
      ],
      steps: StepsBar(active: items.isEmpty ? 0 : 1, steps: const [
        (title: 'Critères', detail: 'nom, stock, rayon', onTap: null),
        (title: 'Résultats', detail: 'niveau de stock', onTap: null),
        (title: 'Détail', detail: 'prix, dates', onTap: null),
      ]),
      header: [
        _searchField(fill: Colors.white),
        if (style == ListPresentation.dashboard) ...[
          const SizedBox(height: 2),
          Row(children: [
            Expanded(child: _Kpi(n(provider.totalItems), 'article(s)')),
            const SizedBox(width: 8),
            Expanded(child: _Kpi(n(ruptures), 'rupture(s)', highlight: shown && ruptures > 0)),
            const SizedBox(width: 8),
            Expanded(child: _Kpi(n(valeur), 'valeur achat F')),
          ]),
        ],
      ],
      compactHeader: [
        _searchField(fill: Pal.page),
        if (shown && items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LightFigures([
              (n(provider.totalItems), 'articles', Pal.navy),
              (n(ruptures), 'ruptures', const Color(0xFFB91C1C)),
              (n(sousSeuil), 'sous seuil', const Color(0xFF8A5300)),
              (n(valeur), 'valeur achat F', Pal.green),
            ]),
          ),
      ],
      body: _body(provider, hasCriteria),
    );
  }

  Widget _searchField({required Color fill}) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: _searchController,
        builder: (context, value, _) => TextField(
          key: const Key('stock_search'),
          controller: _searchController,
          focusNode: _searchFocusNode,
          textInputAction: TextInputAction.search,
          inputFormatters: [
            FilteringTextInputFormatter.deny(_controlChars),
            LengthLimitingTextInputFormatter(maxQueryLength),
          ],
          decoration: InputDecoration(
            hintText: 'Rechercher (Nom, CIP, Scan)',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: value.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Effacer',
                    onPressed: () {
                      _queryDebounce?.cancel();
                      _searchController.clear();
                      if (_provider.searchQuery.isNotEmpty) _provider.setQuery('');
                      _searchFocusNode.requestFocus();
                    },
                  )
                : null,
            isDense: true,
            filled: true,
            fillColor: fill,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
          onChanged: _onSearchChanged,
          onSubmitted: (v) {
            _queryDebounce?.cancel();
            final q = cleanQuery(v);
            if (q != _provider.searchQuery) _provider.setQuery(q);
          },
        ),
      );

  // --- Filtres ---
  Widget _filtersPanel(StockReportProvider provider) {
    final rayons = uniqueRayons(provider.rayons);
    final rayonValue = rayons.any((r) => r.id == _selectedRayonId) ? _selectedRayonId : null;
    final missingValue = _selectedFilterType != null && cleanStockValue(_stockValueController.text).isEmpty;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(10));

    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<StockFilterType>(
            key: const Key('stock_filter_type'),
            value: _selectedFilterType,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Filtre Stock', isDense: true, border: border),
            items: [
              const DropdownMenuItem<StockFilterType>(value: null, child: Text('Aucun', maxLines: 1, overflow: TextOverflow.ellipsis)),
              for (final e in _filterLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _onFilterTypeChanged,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextFormField(
            key: const Key('stock_value'),
            controller: _stockValueController,
            focusNode: _stockValueFocusNode,
            decoration: InputDecoration(labelText: 'Valeur', hintText: '0 à 99999', isDense: true, border: border),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(maxStockDigits),
            ],
            enabled: _selectedFilterType != null,
            onChanged: _onStockValueChanged,
          ),
        ),
      ]),
      if (missingValue)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Saisissez une valeur de stock pour appliquer le filtre.', style: TextStyle(fontSize: 12, color: Color(0xFF8A5300))),
        ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        key: const Key('stock_rayon'),
        value: rayonValue,
        isExpanded: true,
        decoration: InputDecoration(labelText: 'Emplacement', isDense: true, border: border),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('Tous les emplacements', maxLines: 1, overflow: TextOverflow.ellipsis)),
          for (final r in rayons) DropdownMenuItem(value: r.id, child: Text(_txt(r.libelle), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (val) => _onRayonChanged(val, rayons),
      ),
    ]);

    return switch (style) {
      ListPresentation.compact => Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Pal.line))),
          child: content,
        ),
      ListPresentation.dashboard =>
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: SoftCard(padding: const EdgeInsets.all(12), child: content)),
      ListPresentation.guided => Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: SoftCard(
            band: Pal.navy,
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('1 · Critères de recherche', style: TextStyle(fontWeight: FontWeight.bold, color: Pal.ink)),
              const SizedBox(height: 10),
              content,
            ]),
          ),
        ),
    };
  }

  // --- Corps : filtres + liste / chargement / erreur / vide ---
  Widget _body(StockReportProvider provider, bool hasCriteria) {
    final items = provider.reportItems;
    final slivers = <Widget>[
      SliverToBoxAdapter(child: _filtersPanel(provider)),
      if (provider.filtersError != null)
        SliverToBoxAdapter(
          child: LoadErrorBanner(
            message: 'Emplacements non chargés. ${provider.filtersError}',
            onRetry: provider.loadFiltersData,
          ),
        ),
    ];

    if (provider.isLoading && items.isEmpty) {
      slivers.add(const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())));
    } else if (provider.loadError != null) {
      slivers.add(SliverFillRemaining(
        hasScrollBody: false,
        child: LoadErrorView(message: provider.loadError!, onRetry: () => provider.search()),
      ));
    } else if (!hasCriteria) {
      slivers.add(SliverFillRemaining(
        hasScrollBody: false,
        child: _emptyState(
          Icons.filter_alt,
          'Saisissez des critères pour rechercher',
          'Nom ou code CIP, niveau de stock ou emplacement.',
          'Rechercher un produit',
          () => _searchFocusNode.requestFocus(),
        ),
      ));
    } else if (items.isEmpty) {
      slivers.add(SliverFillRemaining(
        hasScrollBody: false,
        child: _emptyState(
          Icons.inventory_2_outlined,
          'Aucun article trouvé.',
          'Aucun produit ne correspond à ces critères.',
          'Vider les filtres',
          _onClearFilters,
        ),
      ));
    } else {
      if (provider.totalItems > items.length) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '${items.length} premiers articles sur ${provider.totalItems} — affinez la recherche pour voir les autres.',
              style: const TextStyle(fontSize: 12, color: Pal.muted),
            ),
          ),
        ));
      }
      if (style == ListPresentation.compact) {
        slivers.add(SliverList.builder(itemCount: items.length, itemBuilder: (_, i) => _rowB(items[i])));
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
      } else {
        slivers.add(SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          sliver: SliverList.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => style == ListPresentation.dashboard ? _cardA(items[i]) : _cardC(items[i]),
          ),
        ));
      }
    }

    return Stack(children: [
      CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: slivers,
      ),
      if (provider.isLoading && items.isNotEmpty) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
    ]);
  }

  Widget _emptyState(IconData icon, String title, String detail, String action, VoidCallback onAction) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Pal.muted),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Pal.ink)),
            const SizedBox(height: 4),
            Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted)),
            const SizedBox(height: 12),
            OutlinedButton(style: outlineButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 48))), onPressed: onAction, child: Text(action)),
          ]),
        ),
      );

  Widget _subLine(StockReportItem i) => Text(
        'CIP ${_txt(i.code)} · ${_txt(i.rayonLibelle)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: Pal.muted),
      );

  // --- A ---
  Widget _cardA(StockReportItem i) {
    final (label, fg, bg) = _status(i);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showDetailDialog(i),
      child: SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(_txt(i.libelle),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
            ),
            const SizedBox(width: 8),
            StatusBadge(label, fg: fg, bg: bg),
          ]),
          const SizedBox(height: 4),
          _subLine(i),
          const SizedBox(height: 10),
          Wrap(spacing: 18, runSpacing: 4, children: [
            Figure('${i.stock}', 'en stock'),
            Figure(Constants.formatNumber(i.prixVente), 'F vente'),
          ]),
        ]),
      ),
    );
  }

  // --- B ---
  Widget _rowB(StockReportItem i) {
    final (label, fg, _) = _status(i);
    return InkWell(
      onTap: () => _showDetailDialog(i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_txt(i.libelle),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
              Text(
                'CIP ${_txt(i.code)} · ${_txt(i.rayonLibelle)} · ${Constants.formatNumber(i.prixVente)} F',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Pal.muted),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Stock: ${i.stock}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: fg)),
            Text(label, style: TextStyle(fontSize: 12, color: fg)),
          ]),
        ]),
      ),
    );
  }

  // --- C ---
  Widget _cardC(StockReportItem i) {
    final (label, fg, bg) = _status(i);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showDetailDialog(i),
      child: SoftCard(
        band: fg,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(_txt(i.libelle),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Pal.ink)),
            ),
            const SizedBox(width: 8),
            StatusBadge(label, fg: fg, bg: bg),
          ]),
          const SizedBox(height: 4),
          _subLine(i),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Wrap(spacing: 14, runSpacing: 4, children: [
                Figure('${i.stock}', 'en stock'),
                Figure(Constants.formatNumber(i.prixVente), 'F'),
              ]),
            ),
            ElevatedButton(
              style: amberButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 44))),
              onPressed: () => _showDetailDialog(i),
              child: const Text('Détail'),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Chiffre clé de l'en-tête bleu (le chiffre se réduit s'il est long).
class _Kpi extends StatelessWidget {
  final String value;
  final String label;
  final bool highlight;
  const _Kpi(this.value, this.label, {this.highlight = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: highlight ? Pal.amber : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: highlight ? Pal.onAmber : Colors.white)),
          ),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: highlight ? Pal.onAmber : const Color(0xFFDCE6F2))),
        ]),
      );
}
