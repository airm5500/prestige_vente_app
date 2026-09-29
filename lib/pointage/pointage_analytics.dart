// lib/pointage/pointage_analytics.dart
// Rapport de présence et analyse de comportement par employé.
import 'dart:math' as math;

import 'package:prestige_vente_app/pointage/pointage_logic.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';

class DayPresence {
  final DateTime day;
  final DateTime? firstArrival;
  final DateTime? lastDeparture;
  final int workedMinutes;
  final int pauseMinutes;
  final int lateMinutes; // 0 si à l'heure
  final bool earlyLeave;
  final bool missingDeparture;
  final bool scheduledDay;
  final List<PointageRecord> records;

  const DayPresence({
    required this.day,
    required this.records,
    this.firstArrival,
    this.lastDeparture,
    this.workedMinutes = 0,
    this.pauseMinutes = 0,
    this.lateMinutes = 0,
    this.earlyLeave = false,
    this.missingDeparture = false,
    this.scheduledDay = true,
  });

  bool get present => firstArrival != null;
  bool get late => lateMinutes > 0;
}

class EmployeeReport {
  final Employee employee;
  final List<DayPresence> days; // jours travaillés
  final int scheduledDays; // jours prévus écoulés
  final int absences;
  final int workedMinutes;
  final int overtimeMinutes;
  final int lateDays;
  final int lateMinutesTotal;
  final int earlyLeaves;
  final int missingDepartures;
  final int offScheduleDays; // pointages un jour non prévu
  final double? averageArrivalMinutes;
  final double? averageDepartureMinutes;
  final double? arrivalSpreadMinutes; // écart-type des heures d'arrivée
  final Map<PointageMethod, int> methods;

  const EmployeeReport({
    required this.employee,
    required this.days,
    required this.scheduledDays,
    required this.absences,
    required this.workedMinutes,
    required this.overtimeMinutes,
    required this.lateDays,
    required this.lateMinutesTotal,
    required this.earlyLeaves,
    required this.missingDepartures,
    required this.offScheduleDays,
    required this.averageArrivalMinutes,
    required this.averageDepartureMinutes,
    required this.arrivalSpreadMinutes,
    required this.methods,
  });

  int get presentDays => days.length;

  /// Taux de présence sur les jours prévus écoulés (0-100).
  double get attendanceRate => scheduledDays == 0 ? 100 : 100 * (scheduledDays - absences) / scheduledDays;

  /// Part des jours travaillés sans retard (0-100).
  double get punctualityRate => presentDays == 0 ? 100 : 100 * (presentDays - lateDays) / presentDays;

  /// Constats de comportement, du plus important au moins important.
  List<String> get behaviour {
    final out = <String>[];
    if (presentDays == 0 && scheduledDays > 0) return ['Aucune présence sur la période'];
    if (absences > 0) out.add('$absences absence(s) sur $scheduledDays jour(s) prévu(s)');
    if (presentDays > 0 && lateDays / presentDays >= 0.3) {
      out.add('Retards fréquents ($lateDays j., ${lateMinutesTotal ~/ lateDays} min en moyenne)');
    } else if (lateDays > 0) {
      out.add('Retards occasionnels ($lateDays j.)');
    }
    if (presentDays > 0 && earlyLeaves / presentDays >= 0.3) out.add('Départs anticipés fréquents ($earlyLeaves j.)');
    if (missingDepartures > 0) out.add('Oublis de pointage de départ ($missingDepartures)');
    if ((arrivalSpreadMinutes ?? 0) > 30) out.add('Heures d\'arrivée irrégulières (±${arrivalSpreadMinutes!.round()} min)');
    if (offScheduleDays > 0) out.add('Présent $offScheduleDays jour(s) hors planning');
    if (overtimeMinutes >= 120) out.add('Heures supplémentaires : ${formatMinutes(overtimeMinutes)}');
    if (out.isEmpty) out.add('Ponctuel et régulier');
    return out;
  }
}

String formatMinutes(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  return h == 0 ? '$m min' : '${h}h${m.toString().padLeft(2, '0')}';
}

String formatClock(double? minutesOfDay) {
  if (minutesOfDay == null) return '—';
  final m = minutesOfDay.round();
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

class PointageAnalytics {
  PointageAnalytics._();

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);
  static int _mod(DateTime t) => t.hour * 60 + t.minute;

  static DayPresence analyseDay(Employee e, DateTime day, List<PointageRecord> recs) {
    final sorted = List.of(recs)..sort((a, b) => a.time.compareTo(b.time));
    final scheduled = e.workdays.contains(day.weekday);
    if (!sorted.any((r) => r.type == PointageType.arrivee)) {
      return DayPresence(day: day, records: sorted, scheduledDay: scheduled);
    }
    DateTime? firstArrival, lastDeparture, openSince, pauseSince;
    var worked = 0, pause = 0;
    for (final r in sorted) {
      switch (r.type) {
        case PointageType.arrivee:
          firstArrival ??= r.time;
          openSince ??= r.time;
        case PointageType.debutPause:
          if (openSince != null) worked += r.time.difference(openSince).inMinutes;
          openSince = null;
          pauseSince = r.time;
        case PointageType.finPause:
          if (pauseSince != null) pause += r.time.difference(pauseSince).inMinutes;
          pauseSince = null;
          openSince = r.time;
        case PointageType.depart:
          if (openSince != null) worked += r.time.difference(openSince).inMinutes;
          openSince = null;
          lastDeparture = r.time;
      }
    }
    final missingDeparture = openSince != null || pauseSince != null;
    final arrivalMin = _mod(firstArrival!);
    final late = scheduled && arrivalMin > e.startMinutes + e.toleranceMinutes ? arrivalMin - e.startMinutes : 0;
    final early = scheduled && lastDeparture != null && !missingDeparture && _mod(lastDeparture) < e.endMinutes - e.toleranceMinutes;
    return DayPresence(
      day: day,
      records: sorted,
      firstArrival: firstArrival,
      lastDeparture: missingDeparture ? null : lastDeparture,
      workedMinutes: worked,
      pauseMinutes: pause,
      lateMinutes: late,
      earlyLeave: early,
      missingDeparture: missingDeparture,
      scheduledDay: scheduled,
    );
  }

  /// Rapport de chaque employé sur [from, to[. Les jours postérieurs à [now] ne comptent
  /// pas comme absences ; le jour même n'est une absence qu'après l'heure de fin prévue.
  static List<EmployeeReport> build({
    required List<Employee> employees,
    required List<PointageRecord> records,
    required DateTime from,
    required DateTime to,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final reports = <EmployeeReport>[];
    for (final e in employees) {
      final mine = records.where((r) => r.employeeId == e.id && !r.time.isBefore(from) && r.time.isBefore(to));
      final byDay = <DateTime, List<PointageRecord>>{};
      for (final r in mine) {
        byDay.putIfAbsent(_day(r.time), () => []).add(r);
      }
      final days = <DayPresence>[];
      var scheduledDays = 0, absences = 0;
      for (var d = _day(from); d.isBefore(to); d = DateTime(d.year, d.month, d.day + 1)) {
        final recs = byDay[d] ?? const [];
        final p = analyseDay(e, d, recs);
        final elapsed = d.isBefore(_day(current)) ||
            (PointageLogic.sameDay(d, current) && _mod(current) >= e.endMinutes);
        if (e.workdays.contains(d.weekday) && elapsed) {
          scheduledDays++;
          if (!p.present) absences++;
        }
        if (p.present) days.add(p);
      }
      final arrivals = days.map((d) => _mod(d.firstArrival!).toDouble()).toList();
      final departures = days.where((d) => d.lastDeparture != null).map((d) => _mod(d.lastDeparture!).toDouble()).toList();
      double? mean(List<double> v) => v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
      final avgArr = mean(arrivals);
      final spread = arrivals.length < 2
          ? null
          : math.sqrt(arrivals.map((a) => (a - avgArr!) * (a - avgArr)).reduce((a, b) => a + b) / arrivals.length);
      final scheduledLength = e.endMinutes - e.startMinutes;
      final methods = <PointageMethod, int>{};
      for (final r in mine) {
        methods[r.method] = (methods[r.method] ?? 0) + 1;
      }
      reports.add(EmployeeReport(
        employee: e,
        days: days,
        scheduledDays: scheduledDays,
        absences: absences,
        workedMinutes: days.fold(0, (s, d) => s + d.workedMinutes),
        overtimeMinutes: days.fold(0, (s, d) => s + math.max(0, d.workedMinutes - scheduledLength)),
        lateDays: days.where((d) => d.late).length,
        lateMinutesTotal: days.fold(0, (s, d) => s + d.lateMinutes),
        earlyLeaves: days.where((d) => d.earlyLeave).length,
        missingDepartures: days.where((d) => d.missingDeparture && !PointageLogic.sameDay(d.day, current)).length,
        offScheduleDays: days.where((d) => !d.scheduledDay).length,
        averageArrivalMinutes: avgArr,
        averageDepartureMinutes: mean(departures),
        arrivalSpreadMinutes: spread,
        methods: methods,
      ));
    }
    return reports;
  }
}
