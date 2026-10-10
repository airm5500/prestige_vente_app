// lib/screens/reception_control/reception_list_screen.dart
// Contrôle Réception : bons de livraison de la période (à faire / en cours, terminés).
// Présentations au choix : A · Tableau de bord, B · Liste groupée, C · Parcours guidé.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/reception_model.dart';
import 'package:prestige_vente_app/providers/reception_provider.dart';
import 'package:prestige_vente_app/screens/reception_control/reception_detail_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

class ReceptionListScreen extends StatefulWidget {
  /// Présentation imposée (tests) ; sinon celle choisie sur l'appareil (A par défaut).
  final ListPresentation? presentation;

  /// Horloge remplaçable (tests).
  final DateTime Function()? clock;

  const ReceptionListScreen({super.key, this.presentation, this.clock});

  @override
  State<ReceptionListScreen> createState() => _ReceptionListScreenState();
}

/// Contrôles de la période et de la recherche (testables sans écran).
class ReceptionPeriod {
  ReceptionPeriod._();
  static final DateTime minDate = DateTime(2020);
  static const int maxSearchLength = 50;

  /// Remet la période dans l'ordre (début ≤ fin).
  static (DateTime, DateTime) ordered(DateTime start, DateTime end) => start.isAfter(end) ? (end, start) : (start, end);

  /// Texte de recherche nettoyé : sans caractères de contrôle, sans espaces autour, longueur bornée.
  static String cleanQuery(String raw) {
    final t = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    return t.length > maxSearchLength ? t.substring(0, maxSearchLength) : t;
  }
}

class _ReceptionListScreenState extends State<ReceptionListScreen> with SingleTickerProviderStateMixin, PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  late DateTime _startDate = _today;
  late DateTime _endDate = _today;
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabs = TabController(length: 2, vsync: this);
  bool _searching = false;
  bool _opening = false;

  static final _dayFmt = DateFormat('dd/MM/yyyy');

  DateTime get _today {
    final n = (widget.clock ?? DateTime.now)();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime get _lastDate {
    final limit = DateTime(_today.year + 1, 12, 31);
    return limit.isAfter(DateTime(2030)) ? limit : DateTime(2030);
  }

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchData();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  // Chargement silencieux (utilisé au démarrage et au pull-to-refresh)
  Future<void> _fetchData() async {
    final (start, end) = ReceptionPeriod.ordered(_startDate, _endDate);
    final startStr = DateFormat('yyyy-MM-dd').format(start);
    final endStr = DateFormat('yyyy-MM-dd').format(end);
    await Provider.of<ReceptionProvider>(context, listen: false)
        .fetchReceptionBons(dtStart: startStr, dtEnd: endStr, query: ReceptionPeriod.cleanQuery(_searchController.text));
  }

  // --- Recherche manuelle avec Popup bloquant ---
  Future<void> _searchWithPopup() async {
    if (_searching) return;
    _searching = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => const _BlockingDialog('Recherche en cours...'),
    );

    try {
      await _fetchData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur réseau : recherche impossible.'), backgroundColor: Colors.red),
        );
      }
    } finally {
      _searching = false;
      if (mounted) {
        Navigator.of(context).pop(); // Ferme le popup
      }
    }
  }

  Future<void> _selectDate(bool isStart) async {
    // Bornes du calendrier : le début ne dépasse pas la fin, la fin ne précède pas le début.
    final first = isStart ? ReceptionPeriod.minDate : _startDate;
    final last = isStart ? _endDate : _lastDate;
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
      helpText: isStart ? 'Début de la période' : 'Fin de la période',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
      final (s, e) = ReceptionPeriod.ordered(_startDate, _endDate);
      _startDate = s;
      _endDate = e;
    });
    _fetchData();
  }

  void _quickPeriod(int days) {
    setState(() {
      _endDate = _today;
      _startDate = _today.subtract(Duration(days: days));
    });
    _fetchData();
  }

  Future<void> _openBon(ReceptionBon bon) async {
    if (_opening) return; // pas de double ouverture
    _opening = true;
    var popupOpen = true;
    // --- SÉCURITÉ : POPUP DE CHARGEMENT BLOQUANT ---
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => const _BlockingDialog('Ouverture de la réception...'),
    );

    try {
      Provider.of<ReceptionProvider>(context, listen: false).selectBon(bon);

      // Petit délai artificiel pour laisser le temps au popup de s'animer (100 ms)
      await Future.delayed(const Duration(milliseconds: 100));

      // Fermeture du popup
      if (!mounted) return;
      Navigator.of(context).pop();
      popupOpen = false;

      // Ouverture de l'écran des détails
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReceptionDetailScreen(presentation: style)),
      );

      // Rafraichissement au retour
      if (mounted) _fetchData();
    } catch (e) {
      if (mounted) {
        if (popupOpen) Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur lors de l'ouverture de la réception."), backgroundColor: Colors.red),
        );
      }
    } finally {
      _opening = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Données affichées
  // ---------------------------------------------------------------------------
  static int _checkedLines(ReceptionBon b) => b.details.where((d) => d.quantiteControle > 0).length;
  static int _gapLines(ReceptionBon b) => b.details.where((d) => d.quantiteControle > 0 && d.quantiteControle != d.qteRecue).length;

  StatusBadge _badge(ReceptionBon b) => switch (b.statutTraitement) {
        'TERMINE' => const StatusBadge('Terminé', fg: Color(0xFF0B6B45), bg: Color(0xFFDCF5E7)),
        'EN_COURS' => StatusBadge.enCours(),
        _ => StatusBadge.aCommencer(),
      };

  static String _text(String s) => s.trim().isEmpty ? '—' : s.trim();

  String get _periodLabel {
    final (s, e) = ReceptionPeriod.ordered(_startDate, _endDate);
    return s == e ? 'Le ${_dayFmt.format(s)}' : 'Du ${_dayFmt.format(s)} au ${_dayFmt.format(e)}';
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Consumer<ReceptionProvider>(builder: (context, provider, _) {
      final aFaire = provider.bonsAFaire;
      final termines = provider.bonsTermines;
      final lines = aFaire.fold<int>(0, (s, b) => s + b.nbreLignes - _checkedLines(b));
      final dark = style != ListPresentation.compact;
      return PresentationScaffold(
        style: style,
        title: 'Contrôle Réception',
        subtitle: _periodLabel,
        actions: (col) => [
          IconButton(icon: Icon(Icons.refresh, color: col), tooltip: 'Actualiser', onPressed: _fetchData),
          PresentationMenuButton(value: style, onChanged: _setStyle, color: col),
        ],
        steps: StepsBar(active: _tabs.index == 0 ? 0 : 2, steps: [
          (title: 'À contrôler', detail: '${aFaire.length} bon(s)', onTap: () => _tabs.animateTo(0)),
          (title: 'Comptage', detail: 'quantités reçues', onTap: null),
          (title: 'Terminés', detail: '${termines.length} bon(s)', onTap: () => _tabs.animateTo(1)),
        ]),
        header: [
          if (style == ListPresentation.dashboard) ...[
            Row(children: [
              Expanded(child: KpiTile('${aFaire.length}', 'à faire')),
              const SizedBox(width: 8),
              Expanded(child: KpiTile('${termines.length}', 'terminés')),
              const SizedBox(width: 8),
              Expanded(child: KpiTile('$lines', 'lignes à compter', highlight: true)),
            ]),
            SegmentedPills(
              labels: ['À faire · ${aFaire.length}', 'Terminés · ${termines.length}'],
              selected: _tabs.index,
              onSelected: (i) => _tabs.animateTo(i),
            ),
          ],
          _periodBar(dark: dark),
        ],
        compactHeader: [
          LightFigures([
            ('${aFaire.length}', 'À faire', const Color(0xFF8A5300)),
            ('${termines.length}', 'Terminés', Pal.green),
            ('$lines', 'Lignes à compter', Pal.navy),
          ]),
          _periodBar(dark: false),
          TabBar(
            controller: _tabs,
            labelColor: Pal.navy,
            unselectedLabelColor: const Color(0xFF4A5A70),
            indicatorColor: Pal.navy,
            indicatorWeight: 3,
            tabs: [Tab(text: 'À FAIRE / EN COURS (${aFaire.length})'), Tab(text: 'TERMINÉS (${termines.length})')],
          ),
        ],
        body: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 4), child: _searchField()),
          if (provider.isLoading) const LinearProgressIndicator(minHeight: 2),
          if (provider.loadError != null && !provider.isLoading && (aFaire.isNotEmpty || termines.isNotEmpty))
            LoadErrorBanner(message: provider.loadError!, onRetry: _searchWithPopup),
          Expanded(
            child: provider.isLoading && aFaire.isEmpty && termines.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : provider.loadError != null && aFaire.isEmpty && termines.isEmpty
                ? LoadErrorView(message: provider.loadError!, onRetry: _searchWithPopup)
                : TabBarView(controller: _tabs, children: [
                    RefreshIndicator(onRefresh: _fetchData, child: _buildBonList(aFaire, done: false)),
                    RefreshIndicator(onRefresh: _fetchData, child: _buildBonList(termines, done: true)),
                  ]),
          ),
        ]),
      );
    });
  }

  Widget _dateButton(DateTime d, bool isStart, {required bool dark}) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: dark ? Colors.white : Pal.navy,
          side: BorderSide(color: dark ? Colors.white.withValues(alpha: 0.45) : const Color(0xFFC5D0DE)),
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.calendar_today, size: 18),
        label: FittedBox(fit: BoxFit.scaleDown, child: Text(_dayFmt.format(d))),
        onPressed: () => _selectDate(isStart),
      );

  Widget _periodBar({required bool dark}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Semantics(label: 'Date de début', child: _dateButton(_startDate, true, dark: dark))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward, size: 18, color: dark ? Pal.headerMuted : Colors.grey),
          ),
          Expanded(child: Semantics(label: 'Date de fin', child: _dateButton(_endDate, false, dark: dark))),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final (label, days) in const [("Aujourd'hui", 0), ('7 jours', 6), ('30 jours', 29)])
            ActionChip(
              label: Text(label, style: TextStyle(fontSize: 12, color: dark ? Colors.white : Pal.navy)),
              backgroundColor: dark ? Colors.white.withValues(alpha: 0.12) : Pal.page,
              side: BorderSide(color: dark ? Colors.white.withValues(alpha: 0.3) : Pal.line),
              visualDensity: VisualDensity.compact,
              onPressed: () => _quickPeriod(days),
            ),
        ]),
      ]);

  Widget _searchField() => TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        inputFormatters: [
          FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]')),
          LengthLimitingTextInputFormatter(ReceptionPeriod.maxSearchLength),
        ],
        decoration: InputDecoration(
          hintText: 'Rechercher un bon...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(icon: const Icon(Icons.search), tooltip: 'Rechercher', onPressed: _searchWithPopup),
          filled: true,
          fillColor: style == ListPresentation.compact ? Pal.page : Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Pal.line)),
        ),
        onSubmitted: (_) => _searchWithPopup(),
      );

  Widget _buildBonList(List<ReceptionBon> bons, {required bool done}) {
    if (bons.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 40),
        Icon(done ? Icons.inventory_outlined : Icons.fact_check_outlined, size: 56, color: Pal.muted),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text('Aucun bon trouvé pour cette période.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Pal.ink)),
        ),
        const SizedBox(height: 4),
        const Text('Élargissez la période ou actualisez.', textAlign: TextAlign.center, style: TextStyle(color: Pal.muted)),
        const SizedBox(height: 12),
        Center(
          child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            OutlinedButton.icon(style: outlineButton, icon: const Icon(Icons.date_range), label: const Text('30 derniers jours'), onPressed: () => _quickPeriod(29)),
            OutlinedButton.icon(style: outlineButton, icon: const Icon(Icons.refresh), label: const Text('Actualiser'), onPressed: _fetchData),
          ]),
        ),
      ]);
    }
    final compact = style == ListPresentation.compact;
    return ListView.separated(
      padding: compact ? const EdgeInsets.only(bottom: 24) : const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: bons.length,
      separatorBuilder: (_, __) => SizedBox(height: compact ? 0 : 10),
      itemBuilder: (_, i) => switch (style) {
        ListPresentation.dashboard => _cardA(bons[i]),
        ListPresentation.compact => _rowB(bons[i]),
        ListPresentation.guided => InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openBon(bons[i]),
            child: _cardC(bons[i], featured: i == 0 && !done),
          ),
      },
    );
  }

  String _actionLabel(ReceptionBon b) => switch (b.statutTraitement) {
        'TERMINE' => 'Voir le contrôle',
        'EN_COURS' => 'Continuer',
        _ => 'Contrôler',
      };

  // --- A · Tableau de bord ------------------------------------------------------
  Widget _cardA(ReceptionBon b) {
    final checked = _checkedLines(b);
    final gaps = _gapLines(b);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openBon(b),
      child: SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            GrossisteAvatar(b.grossiste),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_text(b.ref), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Pal.ink)),
                Text(_text(b.grossiste), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
              ]),
            ),
            const SizedBox(width: 6),
            _badge(b),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 16, runSpacing: 4, children: [
            Figure('${b.nbreLignes}', 'lignes'),
            Figure(Constants.formatNumber(b.montantHt), 'F HT'),
            Text('Livraison : ${_text(b.dateLivraison)}', style: const TextStyle(fontSize: 13, color: Pal.muted)),
          ]),
          const SizedBox(height: 10),
          ThinProgress(
            value: b.nbreLignes == 0 ? 0 : checked / b.nbreLignes,
            left: '$checked / ${b.nbreLignes} lignes comptées',
            right: gaps == 0 ? '' : '$gaps écart(s)',
            color: checked == b.nbreLignes && b.nbreLignes > 0 ? Pal.green : Pal.blue,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              style: navyButton,
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              label: Text(_actionLabel(b)),
              onPressed: () => _openBon(b),
            ),
          ),
        ]),
      ),
    );
  }

  // --- B · Liste groupée --------------------------------------------------------
  Widget _rowB(ReceptionBon b) => InkWell(
        onTap: () => _openBon(b),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
          child: Row(children: [
            RingProgress(done: _checkedLines(b), total: b.nbreLignes),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_text(b.ref), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
                Text('${_text(b.grossiste)} · ${_text(b.dateLivraison)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${b.nbreLignes} lignes', style: const TextStyle(fontSize: 12, color: Pal.muted)),
              Text(Constants.formatNumber(b.montantHt), style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.blue)),
            ]),
            const Icon(Icons.chevron_right, color: Pal.muted),
          ]),
        ),
      );

  // --- C · Parcours guidé -------------------------------------------------------
  Widget _cardC(ReceptionBon b, {required bool featured}) {
    final band = GrossisteAvatar.colorsFor(b.grossiste).$2;
    final checked = _checkedLines(b);
    if (!featured) {
      return SoftCard(
        band: band,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_text(b.ref), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Pal.ink)),
              Text('${_text(b.grossiste)} · $checked/${b.nbreLignes} ligne(s)',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: amberButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 44))),
            onPressed: () => _openBon(b),
            child: Text(b.statutTraitement == 'TERMINE' ? 'Voir' : (b.statutTraitement == 'EN_COURS' ? 'Continuer' : 'Contrôler')),
          ),
        ]),
      );
    }
    return SoftCard(
      band: band,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_text(b.ref), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.ink)),
              Text('${_text(b.grossiste)} · livré le ${_text(b.dateLivraison)}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
            ]),
          ),
          const SizedBox(width: 6),
          _badge(b),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _metricBox('$checked/${b.nbreLignes}', 'lignes comptées')),
          const SizedBox(width: 8),
          Expanded(child: _metricBox(Constants.formatNumber(b.montantHt), 'F HT')),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            style: amberButton,
            icon: const Icon(Icons.arrow_forward),
            label: Text(_actionLabel(b), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: () => _openBon(b),
          ),
        ),
      ]),
    );
  }

  Widget _metricBox(String value, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Pal.page, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Pal.ink))),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF4A5A70))),
        ]),
      );
}

/// Popup de chargement bloquant.
class _BlockingDialog extends StatelessWidget {
  final String text;
  const _BlockingDialog(this.text);

  @override
  Widget build(BuildContext context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Flexible(child: Text(text)),
          ]),
        ),
      );
}
