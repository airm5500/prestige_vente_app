import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/pointage/pointage_analytics.dart';
import 'package:prestige_vente_app/pointage/pointage_logic.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';

PointageRecord rec(String emp, PointageType t, DateTime at, [PointageMethod m = PointageMethod.androidBiometric]) =>
    PointageRecord(id: '${emp}_${at.toIso8601String()}_${t.name}', employeeId: emp, type: t, time: at, method: m);

void main() {
  // Lundi 21 → samedi 26 septembre 2026 ; "maintenant" = lundi 28 à 10:00
  final now = DateTime(2026, 9, 28, 10);
  const awa = Employee(id: 'awa', name: 'Awa', scheduleStart: '08:00', scheduleEnd: '17:00', toleranceMinutes: 10);
  const koffi = Employee(id: 'koffi', name: 'Koffi', scheduleStart: '08:00', scheduleEnd: '17:00');
  DateTime d(int day, int h, int m) => DateTime(2026, 9, day, h, m);

  group('Enchaînement des pointages', () {
    test('arrivée, puis pause ou départ, puis fin de pause', () {
      expect(PointageLogic.allowedNext([]), [PointageType.arrivee]);
      expect(PointageLogic.allowedNext([rec('a', PointageType.arrivee, d(21, 8, 0))]),
          [PointageType.depart, PointageType.debutPause]);
      expect(PointageLogic.allowedNext([rec('a', PointageType.arrivee, d(21, 8, 0)), rec('a', PointageType.debutPause, d(21, 12, 0))]),
          [PointageType.finPause]);
    });
    test('proposition : pause en journée, départ en fin de journée', () {
      final day = [rec('a', PointageType.arrivee, d(21, 8, 0))];
      expect(PointageLogic.suggested(awa, day, d(21, 12, 30)), PointageType.debutPause);
      expect(PointageLogic.suggested(awa, day, d(21, 16, 30)), PointageType.depart);
    });
  });

  group('Rapport', () {
    final records = [
      // Awa : lundi à l'heure avec pause, mardi en retard, mercredi départ anticipé, jeudi oubli de départ
      rec('awa', PointageType.arrivee, d(21, 7, 55)),
      rec('awa', PointageType.debutPause, d(21, 12, 0)),
      rec('awa', PointageType.finPause, d(21, 13, 0)),
      rec('awa', PointageType.depart, d(21, 17, 5)),
      rec('awa', PointageType.arrivee, d(22, 8, 40)),
      rec('awa', PointageType.depart, d(22, 17, 0)),
      rec('awa', PointageType.arrivee, d(23, 8, 5)),
      rec('awa', PointageType.depart, d(23, 15, 0)),
      rec('awa', PointageType.arrivee, d(24, 8, 0)),
      // Koffi : dimanche uniquement (hors planning)
      rec('koffi', PointageType.arrivee, d(27, 9, 0)),
      rec('koffi', PointageType.depart, d(27, 12, 0)),
    ];
    final reports = PointageAnalytics.build(
      employees: [awa, koffi],
      records: records,
      from: DateTime(2026, 9, 21),
      to: DateTime(2026, 9, 29),
      now: now,
    );
    final a = reports.firstWhere((r) => r.employee.id == 'awa');
    final k = reports.firstWhere((r) => r.employee.id == 'koffi');

    test('heures travaillées, pauses déduites', () {
      expect(a.days.first.workedMinutes, 4 * 60 + 5 + 4 * 60 + 5); // 07:55-12:00 + 13:00-17:05
      expect(a.days.first.pauseMinutes, 60);
    });

    test('retards, départs anticipés, oublis de départ', () {
      expect(a.lateDays, 1);
      expect(a.lateMinutesTotal, 40);
      expect(a.earlyLeaves, 1);
      expect(a.missingDepartures, 1);
    });

    test('absences : jours prévus écoulés sans arrivée (lundi 28 pas encore compté à 10h)', () {
      // Lun 21 → sam 26 prévus : absent vendredi 25 et samedi 26
      expect(a.scheduledDays, 6);
      expect(a.absences, 2);
      expect(a.attendanceRate.round(), 67);
      expect(k.absences, 6);
      expect(k.offScheduleDays, 1);
    });

    test('analyse de comportement', () {
      expect(a.behaviour, contains(startsWith('2 absence(s)')));
      expect(a.behaviour.any((b) => b.startsWith('Retards')), isTrue);
      expect(a.behaviour, contains('Oublis de pointage de départ (1)'));
      expect(k.behaviour, contains('Présent 1 jour(s) hors planning'));
    });

    test('employé régulier : ponctuel', () {
      final ok = PointageAnalytics.build(
        employees: [awa],
        records: [
          for (var day = 21; day <= 26; day++) ...[
            rec('awa', PointageType.arrivee, d(day, 7, 58)),
            rec('awa', PointageType.depart, d(day, 17, 2)),
          ],
        ],
        from: DateTime(2026, 9, 21),
        to: DateTime(2026, 9, 27),
        now: now,
      ).single;
      expect(ok.behaviour, ['Ponctuel et régulier']);
      expect(ok.punctualityRate, 100);
      expect(formatClock(ok.averageArrivalMinutes), '07:58');
    });
  });
}
