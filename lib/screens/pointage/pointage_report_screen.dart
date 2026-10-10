// lib/screens/pointage/pointage_report_screen.dart
// Rapport de présence et analyse de comportement des employés.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/pointage/pointage_analytics.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

enum _Period { today, week, month, lastMonth }

class PointageReportScreen extends StatefulWidget {
  final PointageRepository repository;
  final DateTime Function()? clock;

  /// Présentation (A, B, C) ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;
  const PointageReportScreen({super.key, required this.repository, this.clock, this.presentation});

  @override
  State<PointageReportScreen> createState() => _PointageReportScreenState();
}

class _PointageReportScreenState extends State<PointageReportScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  _Period _period = _Period.week;
  List<EmployeeReport> _reports = [];
  List<PointageRecord> _records = [];
  bool _loading = true;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  (DateTime, DateTime) _range() {
    final n = _now();
    final today = DateTime(n.year, n.month, n.day);
    return switch (_period) {
      _Period.today => (today, today.add(const Duration(days: 1))),
      _Period.week => (today.subtract(const Duration(days: 6)), today.add(const Duration(days: 1))),
      _Period.month => (DateTime(n.year, n.month, 1), today.add(const Duration(days: 1))),
      _Period.lastMonth => (DateTime(n.year, n.month - 1, 1), DateTime(n.year, n.month, 1)),
    };
  }

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _load();
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  void _choosePeriod(_Period p) {
    setState(() => _period = p);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final (from, to) = _range();
    final employees = await widget.repository.loadEmployees();
    final records = await widget.repository.loadRecords(from: from, to: to);
    final reports = PointageAnalytics.build(employees: employees, records: records, from: from, to: to, now: _now());
    if (!mounted) return;
    setState(() {
      _records = records;
      _reports = reports;
      _loading = false;
    });
  }

  static const _periodLabels = {
    _Period.today: 'Aujourd\'hui',
    _Period.week: '7 jours',
    _Period.month: 'Ce mois',
    _Period.lastMonth: 'Mois dernier',
  };

  @override
  Widget build(BuildContext context) {
    final (from, to) = _range();
    final df = DateFormat('dd/MM');
    final totalWorked = _reports.fold<int>(0, (s, r) => s + r.workedMinutes);
    final totalLate = _reports.fold<int>(0, (s, r) => s + r.lateDays);
    final totalAbs = _reports.fold<int>(0, (s, r) => s + r.absences);
    final n = _now();
    final presentNow = _reports.where((r) {
      final today = r.days.where((d) => d.day.year == n.year && d.day.month == n.month && d.day.day == n.day);
      return today.isNotEmpty && today.first.lastDeparture == null;
    }).length;

    final rangeText = 'Du ${df.format(from)} au ${df.format(to.subtract(const Duration(days: 1)))} · ${_records.length} pointage(s)';
    final compact = style == ListPresentation.compact;
    final figures = [
      ('$presentNow', 'Présents', Colors.green.shade700),
      (formatMinutes(totalWorked), 'Heures', Pal.navy),
      ('$totalLate', 'Retards', Colors.orange.shade800),
      ('$totalAbs', 'Absences', Colors.red.shade700),
    ];

    return PresentationScaffold(
      style: style,
      title: 'Rapport de pointage',
      subtitle: compact ? null : rangeText,
      actions: (col) => [
        IconButton(icon: Icon(Icons.refresh, color: col), tooltip: 'Actualiser', onPressed: _load),
        PresentationMenuButton(value: style, onChanged: _setStyle, color: col),
      ],
      steps: StepsBar(active: _period.index, steps: [
        for (final p in _Period.values) (title: _periodLabels[p]!, detail: '', onTap: () => _choosePeriod(p)),
      ]),
      header: [
        if (style == ListPresentation.dashboard)
          SegmentedPills(
            labels: [for (final p in _Period.values) _periodLabels[p]!],
            selected: _period.index,
            onSelected: (i) => _choosePeriod(_Period.values[i]),
          ),
        if (style == ListPresentation.dashboard) const SizedBox(height: 10),
        Row(children: [
          for (final (i, f) in figures.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: KpiTile(f.$1, f.$2, highlight: i == 0)),
          ],
        ]),
      ],
      compactHeader: [
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final p in _Period.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(_periodLabels[p]!), selected: _period == p, onSelected: (_) => _choosePeriod(p)),
              ),
          ]),
        ),
        Text(rangeText, style: const TextStyle(color: Pal.muted, fontSize: 12)),
        const SizedBox(height: 6),
        LightFigures(figures),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: compact ? const EdgeInsets.fromLTRB(0, 8, 0, 16) : const EdgeInsets.fromLTRB(16, 16, 16, 16),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (!_loading && _reports.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aucun employé enregistré.', textAlign: TextAlign.center),
              ),
            for (final r in _reports) _employeeCard(r),
          ],
        ),
      ),
    );
  }

  void _openDetail(EmployeeReport r) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => _EmployeeDetailScreen(report: r, repository: widget.repository, style: style)))
      .then((_) => _load());

  Widget _behaviour(EmployeeReport r) {
    final warn = r.behaviour.first != 'Ponctuel et régulier';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final b in r.behaviour)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(warn ? Icons.warning_amber : Icons.check_circle, size: 16, color: warn ? Colors.orange.shade800 : Colors.green.shade700),
              const SizedBox(width: 6),
              Expanded(child: Text(b, style: const TextStyle(fontSize: 13, color: Pal.ink))),
            ],
          ),
        ),
    ]);
  }

  Widget _employeeCard(EmployeeReport r) {
    final warn = r.behaviour.first != 'Ponctuel et régulier';
    final details = '${r.presentDays} j. travaillé(s) · ${formatMinutes(r.workedMinutes)} · '
        'ponctualité ${r.punctualityRate.round()} % · '
        'arrivée moy. ${formatClock(r.averageArrivalMinutes)} · départ moy. ${formatClock(r.averageDepartureMinutes)}';
    final rate = Text('${r.attendanceRate.round()} % présence', style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink));
    if (style == ListPresentation.compact) {
      return InkWell(
        onTap: () => _openDetail(r),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(r.employee.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Pal.ink))),
              rate,
            ]),
            Text(details, style: const TextStyle(fontSize: 12, color: Pal.muted)),
            _behaviour(r),
          ]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openDetail(r),
        child: SoftCard(
          band: style == ListPresentation.guided ? (warn ? Pal.amber : Pal.green) : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GrossisteAvatar(r.employee.name, size: 40),
              const SizedBox(width: 10),
              Expanded(child: Text(r.employee.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Pal.ink))),
              warn
                  ? StatusBadge('À suivre', fg: Colors.orange.shade900, bg: const Color(0xFFFFF4E0))
                  : StatusBadge('Régulier', fg: Colors.green.shade800, bg: const Color(0xFFE6F4EA)),
            ]),
            const SizedBox(height: 10),
            ThinProgress(
              value: r.attendanceRate / 100,
              left: 'Présence',
              right: '${r.attendanceRate.round()} % présence',
              color: r.attendanceRate >= 90 ? Pal.green : (r.attendanceRate >= 70 ? Pal.blue : Colors.orange.shade700),
            ),
            const SizedBox(height: 8),
            Text(details, style: const TextStyle(fontSize: 13, color: Pal.muted)),
            const SizedBox(height: 6),
            _behaviour(r),
          ]),
        ),
      ),
    );
  }
}

class _EmployeeDetailScreen extends StatefulWidget {
  final EmployeeReport report;
  final PointageRepository repository;
  final ListPresentation style;
  const _EmployeeDetailScreen({required this.report, required this.repository, required this.style});

  @override
  State<_EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<_EmployeeDetailScreen> {
  static final _day = DateFormat('EEE dd/MM', 'fr_FR');
  static final _hm = DateFormat('HH:mm');
  final Set<String> _deleted = {};

  Future<void> _deleteRecord(PointageRecord rec) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce pointage ?'),
        content: Text('${rec.type.label} à ${_hm.format(rec.time)} (${rec.method.label})'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) {
      await widget.repository.deleteRecord(rec.id);
      setState(() => _deleted.add(rec.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final style = widget.style;
    final compact = style == ListPresentation.compact;
    Widget card(Widget child, {Color? band}) => compact
        ? Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
            child: child,
          )
        : Padding(padding: const EdgeInsets.only(bottom: 10), child: SoftCard(padding: EdgeInsets.zero, band: band, child: child));
    final methods = r.methods.entries.map((e) => '${e.key.label} ${e.value}').join(', ');
    return PresentationScaffold(
      style: style,
      title: r.employee.name,
      subtitle: 'Horaires ${r.employee.scheduleStart}–${r.employee.scheduleEnd} · tolérance ${r.employee.toleranceMinutes} min',
      actions: (_) => const [],
      header: [
        Row(children: [
          Expanded(child: KpiTile('${r.attendanceRate.round()} %', 'présence', highlight: true)),
          const SizedBox(width: 6),
          Expanded(child: KpiTile('${r.punctualityRate.round()} %', 'ponctualité')),
          const SizedBox(width: 6),
          Expanded(child: KpiTile(formatMinutes(r.workedMinutes), 'travaillé')),
        ]),
      ],
      compactHeader: [
        LightFigures([
          ('${r.attendanceRate.round()} %', 'Présence', Pal.navy),
          ('${r.punctualityRate.round()} %', 'Ponctualité', Pal.navy),
          (formatMinutes(r.workedMinutes), 'Travaillé', Pal.navy),
        ]),
      ],
      body: ListView(
        padding: compact ? const EdgeInsets.only(top: 8, bottom: 16) : const EdgeInsets.all(16),
        children: [
          card(
            Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(spacing: 16, runSpacing: 6, children: [
                Figure(formatMinutes(r.overtimeMinutes), 'heures supp.'),
                Figure('${r.lateDays}', 'retard(s) (${formatMinutes(r.lateMinutesTotal)})'),
                Figure('${r.earlyLeaves}', 'départ(s) anticipé(s)'),
                Figure('${r.missingDepartures}', 'oubli(s) de départ'),
                Figure('${r.absences}', 'absence(s)'),
                if (methods.isNotEmpty) Text('Méthodes : $methods', style: const TextStyle(fontSize: 13, color: Pal.muted)),
              ]),
            ),
            band: style == ListPresentation.guided ? Pal.navy : null,
          ),
          for (final d in r.days.reversed)
            card(
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: Icon(
                    d.late || d.earlyLeave || d.missingDeparture ? Icons.warning_amber : Icons.check_circle_outline,
                    color: d.late || d.earlyLeave || d.missingDeparture ? Colors.orange.shade800 : Colors.green.shade700,
                  ),
                  title: Text(_day.format(d.day), style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
                  subtitle: Text([
                    'Arrivée ${d.firstArrival == null ? '—' : _hm.format(d.firstArrival!)}',
                    'Départ ${d.lastDeparture == null ? (d.missingDeparture ? 'non pointé' : '—') : _hm.format(d.lastDeparture!)}',
                    formatMinutes(d.workedMinutes),
                    if (d.late) 'retard ${formatMinutes(d.lateMinutes)}',
                    if (d.earlyLeave) 'départ anticipé',
                    if (!d.scheduledDay) 'hors planning',
                  ].join(' · '), style: const TextStyle(fontSize: 13, color: Pal.muted)),
                  children: [
                    for (final rec in d.records.where((x) => !_deleted.contains(x.id)))
                      ListTile(
                        dense: true,
                        title: Text('${_hm.format(rec.time)}  ${rec.type.label}'),
                        subtitle: Text(rec.method.label + (rec.device.isEmpty ? '' : ' · ${rec.device}')),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Supprimer',
                          onPressed: () => _deleteRecord(rec),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
