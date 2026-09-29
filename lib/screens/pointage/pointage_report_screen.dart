// lib/screens/pointage/pointage_report_screen.dart
// Rapport de présence et analyse de comportement des employés.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/pointage/pointage_analytics.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/utils/constants.dart';

enum _Period { today, week, month, lastMonth }

class PointageReportScreen extends StatefulWidget {
  final PointageRepository repository;
  final DateTime Function()? clock;
  const PointageReportScreen({super.key, required this.repository, this.clock});

  @override
  State<PointageReportScreen> createState() => _PointageReportScreenState();
}

class _PointageReportScreenState extends State<PointageReportScreen> {
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

    return Scaffold(
      appBar: AppBar(title: const Text('Rapport de pointage')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(8),
          children: [
            Wrap(
              spacing: 6,
              children: [
                for (final p in _Period.values)
                  ChoiceChip(
                    label: Text(_periodLabels[p]!),
                    selected: _period == p,
                    onSelected: (_) {
                      setState(() => _period = p);
                      _load();
                    },
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('Du ${df.format(from)} au ${df.format(to.subtract(const Duration(days: 1)))} · ${_records.length} pointage(s)',
                  style: TextStyle(color: Colors.grey.shade700)),
            ),
            if (_loading) const LinearProgressIndicator(),
            Card(
              color: Colors.blueGrey.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _kpi('Présents', '$presentNow', Colors.green.shade700),
                    _kpi('Heures', formatMinutes(totalWorked), AppColors.primary),
                    _kpi('Retards', '$totalLate', Colors.orange.shade800),
                    _kpi('Absences', '$totalAbs', Colors.red.shade700),
                  ],
                ),
              ),
            ),
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

  Widget _kpi(String label, String value, Color color) => Column(
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );

  Widget _employeeCard(EmployeeReport r) {
    final warn = r.behaviour.first != 'Ponctuel et régulier';
    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => _EmployeeDetailScreen(report: r, repository: widget.repository)))
            .then((_) => _load()),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(r.employee.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                  Text('${r.attendanceRate.round()} % présence', style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${r.presentDays} j. travaillé(s) · ${formatMinutes(r.workedMinutes)} · '
                'ponctualité ${r.punctualityRate.round()} % · '
                'arrivée moy. ${formatClock(r.averageArrivalMinutes)} · départ moy. ${formatClock(r.averageDepartureMinutes)}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 6),
              for (final b in r.behaviour)
                Row(
                  children: [
                    Icon(warn ? Icons.warning_amber : Icons.check_circle, size: 16, color: warn ? Colors.orange.shade800 : Colors.green.shade700),
                    const SizedBox(width: 6),
                    Expanded(child: Text(b, style: const TextStyle(fontSize: 13))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeDetailScreen extends StatefulWidget {
  final EmployeeReport report;
  final PointageRepository repository;
  const _EmployeeDetailScreen({required this.report, required this.repository});

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
    return Scaffold(
      appBar: AppBar(title: Text(r.employee.name)),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Horaires prévus ${r.employee.scheduleStart}–${r.employee.scheduleEnd} (tolérance ${r.employee.toleranceMinutes} min)\n'
                'Présence ${r.attendanceRate.round()} % · ponctualité ${r.punctualityRate.round()} %\n'
                'Travaillé ${formatMinutes(r.workedMinutes)} · heures supp. ${formatMinutes(r.overtimeMinutes)}\n'
                'Retards ${r.lateDays} (${formatMinutes(r.lateMinutesTotal)}) · départs anticipés ${r.earlyLeaves} · '
                'oublis de départ ${r.missingDepartures} · absences ${r.absences}\n'
                'Méthodes : ${r.methods.entries.map((e) => '${e.key.label} ${e.value}').join(', ')}',
              ),
            ),
          ),
          for (final d in r.days.reversed)
            Card(
              child: ExpansionTile(
                title: Text(_day.format(d.day)),
                subtitle: Text([
                  'Arrivée ${d.firstArrival == null ? '—' : _hm.format(d.firstArrival!)}',
                  'Départ ${d.lastDeparture == null ? (d.missingDeparture ? 'non pointé' : '—') : _hm.format(d.lastDeparture!)}',
                  formatMinutes(d.workedMinutes),
                  if (d.late) 'retard ${formatMinutes(d.lateMinutes)}',
                  if (d.earlyLeave) 'départ anticipé',
                  if (!d.scheduledDay) 'hors planning',
                ].join(' · ')),
                children: [
                  for (final rec in d.records.where((x) => !_deleted.contains(x.id)))
                    ListTile(
                      dense: true,
                      title: Text('${_hm.format(rec.time)}  ${rec.type.label}'),
                      subtitle: Text(rec.method.label + (rec.device.isEmpty ? '' : ' · ${rec.device}')),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteRecord(rec)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
