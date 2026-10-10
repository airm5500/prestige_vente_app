// lib/screens/depot_sale/depot_sale_list_screen.dart
// Ventes dépôt en cours : présentations A (tableau de bord), B (liste groupée), C (parcours guidé).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/api/models/depot_model.dart';
import 'package:prestige_vente_app/providers/depot_sale_provider.dart';
import 'package:prestige_vente_app/screens/depot_sale/depot_sale_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';

enum _Period { all, today, week, month }

class DepotSaleListScreen extends StatefulWidget {
  /// Présentation imposée (tests) ; sinon celle choisie sur l'appareil (A par défaut).
  final ListPresentation? presentation;

  /// Date du jour remplaçable (tests).
  final DateTime Function()? clock;

  const DepotSaleListScreen({super.key, this.presentation, this.clock});

  @override
  State<DepotSaleListScreen> createState() => _DepotSaleListScreenState();
}

class _DepotSaleListScreenState extends State<DepotSaleListScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  String _query = '';
  _Period _period = _Period.all;
  bool _opening = false;

  static const _periodLabels = {
    _Period.all: 'Tout',
    _Period.today: 'Aujourd\'hui',
    _Period.week: '7 jours',
    _Period.month: '30 jours',
  };

  @override
  void initState() {
    super.initState();
    loadPresentation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Provider.of<DepotSaleProvider>(context, listen: false).fetchOngoingSales();
    });
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  String _money(int amount) => "${Constants.formatNumber(amount)} F";

  // --- Navigation (mêmes appels qu'avant) ---
  Future<void> _resumeSale(String saleId) async {
    if (_opening) return;
    setState(() => _opening = true);
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    final ok = await provider.loadExistingSale(saleId);
    if (!mounted) return;
    setState(() => _opening = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red.shade700,
        content: Text(provider.errorMessage.isNotEmpty ? provider.errorMessage : "Impossible de charger la vente."),
      ));
      provider.resetSale();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DepotSaleScreen(presentation: style)),
    ).then((_) {
      provider.fetchOngoingSales();
    });
  }

  void _createNewSale() {
    if (_opening) return;
    final provider = Provider.of<DepotSaleProvider>(context, listen: false);
    provider.resetSale();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DepotSaleScreen(presentation: style)),
    ).then((_) {
      provider.fetchOngoingSales();
    });
  }

  // --- Filtres locaux (recherche, période) ---
  static DateTime? _parseDate(String s) {
    final t = s.trim();
    final fr = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})').firstMatch(t);
    if (fr != null) {
      final d = int.parse(fr.group(1)!), m = int.parse(fr.group(2)!), y = int.parse(fr.group(3)!);
      if (m < 1 || m > 12 || d < 1 || d > 31) return null;
      return DateTime(y, m, d);
    }
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
    if (iso != null) {
      final y = int.parse(iso.group(1)!), m = int.parse(iso.group(2)!), d = int.parse(iso.group(3)!);
      if (m < 1 || m > 12 || d < 1 || d > 31) return null;
      return DateTime(y, m, d);
    }
    return null;
  }

  bool _inPeriod(DepotSaleListItem s) {
    if (_period == _Period.all) return true;
    final d = _parseDate(s.dtUPDATED);
    if (d == null) return true; // date illisible : on ne cache pas la vente
    final n = (widget.clock ?? DateTime.now)();
    final today = DateTime(n.year, n.month, n.day);
    final days = switch (_period) { _Period.today => 0, _Period.week => 6, _Period.month => 29, _Period.all => 0 };
    return !d.isBefore(today.subtract(Duration(days: days)));
  }

  List<DepotSaleListItem> _visible(List<DepotSaleListItem> all) {
    final q = _query.toLowerCase();
    return all.where((s) {
      if (!_inPeriod(s)) return false;
      if (q.isEmpty) return true;
      return s.strREF.toLowerCase().contains(q) ||
          s.strClientFullName.toLowerCase().contains(q) ||
          s.userFullName.toLowerCase().contains(q);
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Consumer<DepotSaleProvider>(builder: (context, provider, _) {
      final list = _visible(provider.ongoingSales);
      final total = list.fold<int>(0, (s, e) => s + e.intPRICE);
      final guided = style == ListPresentation.guided;
      return PresentationScaffold(
        style: style,
        title: 'Ventes Dépôt en cours',
        subtitle: 'Reprenez une vente ou créez-en une',
        actions: (col) => [
          PresentationMenuButton(value: style, onChanged: _setStyle, color: col),
          IconButton(
            icon: Icon(Icons.refresh, color: col),
            tooltip: 'Actualiser',
            onPressed: provider.isLoading ? null : provider.fetchOngoingSales,
          ),
        ],
        header: [
          if (style == ListPresentation.dashboard)
            Row(children: [
              Expanded(child: KpiTile('${list.length}', 'vente(s) en cours')),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: _kpiMoney(total)),
            ]),
          _searchField(),
          if (style == ListPresentation.dashboard)
            SegmentedPills(
              labels: [for (final p in _Period.values) _periodLabels[p]!],
              selected: _period.index,
              onSelected: (i) => setState(() => _period = _Period.values[i]),
            ),
        ],
        compactHeader: [
          _searchField(fill: Pal.page),
          LightFigures([
            ('${list.length}', 'vente(s) en cours', Pal.navy),
            (_money(total), 'montant total', Pal.green),
          ]),
        ],
        steps: const StepsBar(active: 0, steps: [
          (title: 'Choisir', detail: 'vente ou nouvelle', onTap: null),
          (title: 'Panier', detail: 'produits, quantités', onTap: null),
          (title: 'Clôture', detail: 'sur Prestige', onTap: null),
        ]),
        body: Column(children: [
          if (style != ListPresentation.dashboard) _periodChips(),
          if (provider.isLoading || _opening) const LinearProgressIndicator(minHeight: 2),
          if (provider.listError != null && provider.ongoingSales.isNotEmpty)
            LoadErrorBanner(message: provider.listError!, onRetry: provider.fetchOngoingSales),
          Expanded(child: _listBody(provider, list)),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: guided ? amberButton : navyButton,
                onPressed: _opening ? null : _createNewSale,
                icon: const Icon(Icons.add),
                label: const Text("Nouvelle Vente"),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _kpiMoney(int total) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Pal.amber, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_money(total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Pal.onAmber)),
          ),
          const Text('montant total', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Pal.onAmber)),
        ]),
      );

  Widget _searchField({Color fill = Colors.white}) => TextField(
        maxLength: 50,
        inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]'))],
        decoration: InputDecoration(
          counterText: '',
          prefixIcon: const Icon(Icons.search),
          hintText: 'Référence, client ou vendeur',
          filled: true,
          fillColor: fill,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        onChanged: (v) => setState(() => _query = v.trim()),
      );

  Widget _periodChips() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: [
          for (final p in _Period.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(_periodLabels[p]!),
                selected: _period == p,
                onSelected: (_) => setState(() => _period = p),
              ),
            ),
        ]),
      );

  Widget _listBody(DepotSaleProvider provider, List<DepotSaleListItem> list) {
    if (provider.listError != null && provider.ongoingSales.isEmpty) {
      return LoadErrorView(message: provider.listError!, onRetry: provider.fetchOngoingSales);
    }
    if (list.isEmpty) {
      if (provider.isLoading) return const Center(child: CircularProgressIndicator());
      final filtered = provider.ongoingSales.isNotEmpty;
      return RefreshIndicator(
        onRefresh: provider.fetchOngoingSales,
        child: ListView(padding: const EdgeInsets.all(32), children: [
          const Icon(Icons.shopping_basket_outlined, size: 60, color: Colors.grey),
          const SizedBox(height: 10),
          Text(
            filtered ? "Aucune vente ne correspond à la recherche ou à la période." : "Aucune vente en cours",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Pal.muted, fontSize: 15),
          ),
          const SizedBox(height: 12),
          Center(
            child: filtered
                ? OutlinedButton(
                    style: outlineButton,
                    onPressed: () => setState(() => _period = _Period.all),
                    child: const Text('Afficher toute la période'),
                  )
                : OutlinedButton.icon(
                    style: outlineButton,
                    onPressed: _createNewSale,
                    icon: const Icon(Icons.add),
                    label: const Text('Nouvelle Vente'),
                  ),
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: provider.fetchOngoingSales,
      child: switch (style) {
        ListPresentation.compact => ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: list.length,
            itemBuilder: (_, i) => _rowB(list[i]),
          ),
        _ => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => style == ListPresentation.guided ? _cardC(list[i]) : _cardA(list[i]),
          ),
      },
    );
  }

  String _ref(DepotSaleListItem s) => s.strREF.isEmpty ? "Sans Référence" : s.strREF;
  String _client(DepotSaleListItem s) => s.strClientFullName.trim().isEmpty ? '—' : s.strClientFullName;
  String _when(DepotSaleListItem s) => [s.dtUPDATED, s.heure].where((e) => e.trim().isNotEmpty).join(' à ');

  Widget _amount(DepotSaleListItem s, {double size = 16}) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(_money(s.intPRICE), style: TextStyle(fontWeight: FontWeight.bold, color: Pal.green, fontSize: size)),
      );

  // --- A ---
  Widget _cardA(DepotSaleListItem s) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _resumeSale(s.lgPREENREGISTREMENTID),
        child: SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              GrossisteAvatar(_client(s)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_ref(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Pal.ink)),
                  Text("Client: ${_client(s)}", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
                ]),
              ),
              StatusBadge.enCours(),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Text(
                  [_when(s), if (s.userFullName.trim().isNotEmpty) s.userFullName].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Pal.muted),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: _amount(s, size: 17)),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                style: navyButton,
                onPressed: _opening ? null : () => _resumeSale(s.lgPREENREGISTREMENTID),
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text('Reprendre'),
              ),
            ),
          ]),
        ),
      );

  // --- B ---
  Widget _rowB(DepotSaleListItem s) => InkWell(
        onTap: () => _resumeSale(s.lgPREENREGISTREMENTID),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_ref(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
                Text("Client: ${_client(s)}", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.ink)),
                Text(_when(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Pal.muted)),
              ]),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 120), child: _amount(s)),
            const Icon(Icons.chevron_right, color: Pal.muted),
          ]),
        ),
      );

  // --- C ---
  Widget _cardC(DepotSaleListItem s) => SoftCard(
        band: GrossisteAvatar.colorsFor(_client(s)).$2,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_ref(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Pal.ink)),
              Text(_client(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
              Text(_when(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Pal.muted)),
              Align(alignment: Alignment.centerLeft, child: _amount(s)),
            ]),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: amberButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 44))),
            onPressed: _opening ? null : () => _resumeSale(s.lgPREENREGISTREMENTID),
            child: const Text('Reprendre'),
          ),
        ]),
      );
}
