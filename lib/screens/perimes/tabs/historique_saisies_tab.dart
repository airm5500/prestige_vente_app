// lib/screens/perimes/tabs/historique_saisies_tab.dart
// Historique des saisies de périmés, filtré par période (présentations A, B, C).
// Dates choisies au calendrier uniquement ; début toujours ≤ fin.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/perime_models.dart';
import 'package:prestige_vente_app/providers/perime_provider.dart';
import 'package:prestige_vente_app/screens/perimes/perime_widgets.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

class HistoriqueSaisiesTab extends StatefulWidget {
  /// Présentation imposée par l'écran parent ; celle de l'appareil sinon.
  final ListPresentation? presentation;
  const HistoriqueSaisiesTab({super.key, this.presentation});

  @override
  State<HistoriqueSaisiesTab> createState() => _HistoriqueSaisiesTabState();
}

class _HistoriqueSaisiesTabState extends State<HistoriqueSaisiesTab> with PresentationAware, AutomaticKeepAliveClientMixin {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  @override
  bool get wantKeepAlive => true;

  final _dtStartController = TextEditingController();
  final _dtEndController = TextEditingController();
  late DateTime _start;
  late DateTime _end;

  static final _display = DateFormat('dd/MM/yyyy');
  static final _api = DateFormat('yyyy-MM-dd');

  String get _dtStart => _api.format(_start);
  String get _dtEnd => _api.format(_end);

  @override
  void initState() {
    super.initState();
    loadPresentation();
    // Par défaut, charge les données du jour
    final today = DateUtils.dateOnly(DateTime.now());
    _start = today;
    _end = today;
    _syncControllers();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchData();
    });
  }

  @override
  void didUpdateWidget(covariant HistoriqueSaisiesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final p = widget.presentation;
    if (p != null && p != style) style = p;
  }

  @override
  void dispose() {
    _dtStartController.dispose();
    _dtEndController.dispose();
    super.dispose();
  }

  void _syncControllers() {
    _dtStartController.text = _display.format(_start);
    _dtEndController.text = _display.format(_end);
  }

  void _fetchData() {
    final provider = Provider.of<PerimeProvider>(context, listen: false);
    if (_start.isAfter(_end)) {
      Constants.showSnackBar(context, 'La date de début doit précéder la date de fin.', isError: true);
      return;
    }
    provider.loadSaisieHistory(dtStart: _dtStart, dtEnd: _dtEnd);
  }

  Future<void> _selectDate({required bool start}) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final current = start ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(today) ? today : current,
      firstDate: DateTime(2020),
      lastDate: today,
      helpText: start ? 'Date de début' : 'Date de fin',
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end.isBefore(_start)) _end = _start; // garde début ≤ fin
      } else {
        _end = picked;
        if (_start.isAfter(_end)) _start = _end;
      }
      _syncControllers();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final compact = style == ListPresentation.compact;
    return Container(
      color: compact ? Colors.white : null,
      child: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: Consumer<PerimeProvider>(
              builder: (context, provider, child) {
                final list = provider.saisieHistoryList;
                if (provider.isLoading && list.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Column(children: [
                  if (provider.isLoading) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async => _fetchData(),
                      child: list.isEmpty
                          ? PerimeEmptyState(
                              icon: Icons.history,
                              text: 'Aucun historique de saisie pour cette période.',
                              detail: 'Choisissez d\'autres dates puis touchez la loupe.',
                              actionLabel: 'Actualiser',
                              onAction: _fetchData,
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(compact ? 0 : 12, 8, compact ? 0 : 12, 24),
                              itemCount: list.length,
                              separatorBuilder: (_, __) => SizedBox(height: compact ? 0 : 10),
                              itemBuilder: (context, index) => _itemTile(list[index]),
                            ),
                    ),
                  ),
                ]);
              },
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dateDeco(String label) => InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_today, size: 18),
        isDense: true,
        filled: true,
        fillColor: style == ListPresentation.compact ? Pal.page : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC5D0DE))),
      );

  Widget _buildFilters() {
    final loading = context.select<PerimeProvider, bool>((p) => p.isLoading);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _dtStartController,
              readOnly: true,
              decoration: _dateDeco('Date Début'),
              onTap: () => _selectDate(start: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: _dtEndController,
              readOnly: true,
              decoration: _dateDeco('Date Fin'),
              onTap: () => _selectDate(start: false),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              tooltip: 'Rechercher',
              icon: const Icon(Icons.search),
              onPressed: loading ? null : _fetchData,
              style: IconButton.styleFrom(
                backgroundColor: style == ListPresentation.guided ? Pal.amber : Pal.navy,
                foregroundColor: style == ListPresentation.guided ? Pal.onAmber : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemTile(SaisiePerimeItem item) {
    final compact = style == ListPresentation.compact;
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Text('${perimeOrDash(item.strNAME)} (Qté: ${item.intQUANTITY})',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink)),
        ),
        const SizedBox(width: 8),
        Text(Constants.formatNumber(item.intPRICE), style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.ink)),
      ]),
      const SizedBox(height: 2),
      Text('CIP: ${perimeOrDash(item.intCIP)} | Lot: ${perimeOrDash(item.ticketNum)} | Péremption: ${perimeOrDash(item.dtCREATED)}',
          style: const TextStyle(fontSize: 13, color: Pal.muted)),
      const SizedBox(height: 4),
      Wrap(spacing: 12, runSpacing: 4, children: [
        Text('Opération: ${perimeOrDash(item.dateOperation)}', style: const TextStyle(fontSize: 12, color: Pal.muted)),
        Text('Stock: ${item.stockInitial} -> ${item.stockFinal}', style: const TextStyle(fontSize: 12, color: Pal.ink, fontWeight: FontWeight.w600)),
      ]),
    ]);
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
        child: body,
      );
    }
    return SoftCard(band: style == ListPresentation.guided ? Pal.green : null, child: body);
  }
}
