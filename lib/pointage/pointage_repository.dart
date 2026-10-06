// lib/pointage/pointage_repository.dart
// Stockage du pointage. Version locale (sur l'appareil) pour les tests ; la même interface
// servira pour la synchronisation avec le serveur Prestige quand les employés y seront configurés.
import 'dart:convert';

import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class PointageRepository {
  Future<List<Employee>> loadEmployees();
  Future<void> saveEmployee(Employee e);
  Future<void> deleteEmployee(String id);
  Future<List<PointageRecord>> loadRecords({DateTime? from, DateTime? to});
  Future<void> addRecord(PointageRecord r);
  Future<void> deleteRecord(String id);
  Future<PointageSettings> loadSettings();
  Future<void> saveSettings(PointageSettings s);
}

class LocalPointageRepository implements PointageRepository {
  static const _employeesKey = 'pointage_employees_v1';
  static const _recordsKey = 'pointage_records_v1';
  static const _settingsKey = 'pointage_settings_v1';

  @override
  Future<PointageSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return const PointageSettings();
    return PointageSettings.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }

  @override
  Future<void> saveSettings(PointageSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(s.toJson()));
  }

  Future<List<Map<String, dynamic>>> _read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _write(String key, List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(items));
  }

  @override
  Future<List<Employee>> loadEmployees() async {
    final list = (await _read(_employeesKey)).map(Employee.fromJson).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  Future<void> saveEmployee(Employee e) async {
    final items = await _read(_employeesKey);
    final i = items.indexWhere((m) => m['id'] == e.id);
    if (i >= 0) {
      items[i] = e.toJson();
    } else {
      items.add(e.toJson());
    }
    await _write(_employeesKey, items);
  }

  @override
  Future<void> deleteEmployee(String id) async {
    final items = await _read(_employeesKey);
    items.removeWhere((m) => m['id'] == id);
    await _write(_employeesKey, items);
  }

  @override
  Future<List<PointageRecord>> loadRecords({DateTime? from, DateTime? to}) async {
    final list = (await _read(_recordsKey)).map(PointageRecord.fromJson).where((r) {
      if (from != null && r.time.isBefore(from)) return false;
      if (to != null && !r.time.isBefore(to)) return false;
      return true;
    }).toList();
    list.sort((a, b) => a.time.compareTo(b.time));
    return list;
  }

  @override
  Future<void> addRecord(PointageRecord r) async {
    final items = await _read(_recordsKey);
    items.add(r.toJson());
    await _write(_recordsKey, items);
  }

  @override
  Future<void> deleteRecord(String id) async {
    final items = await _read(_recordsKey);
    items.removeWhere((m) => m['id'] == id);
    await _write(_recordsKey, items);
  }
}

/// Stockage en mémoire (tests).
class MemoryPointageRepository implements PointageRepository {
  final List<Employee> employees = [];
  final List<PointageRecord> records = [];
  PointageSettings settings = const PointageSettings();

  @override
  Future<PointageSettings> loadSettings() async => settings;

  @override
  Future<void> saveSettings(PointageSettings s) async => settings = s;

  @override
  Future<List<Employee>> loadEmployees() async => List.of(employees)..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<void> saveEmployee(Employee e) async {
    employees.removeWhere((x) => x.id == e.id);
    employees.add(e);
  }

  @override
  Future<void> deleteEmployee(String id) async => employees.removeWhere((x) => x.id == id);

  @override
  Future<List<PointageRecord>> loadRecords({DateTime? from, DateTime? to}) async => records
      .where((r) => (from == null || !r.time.isBefore(from)) && (to == null || r.time.isBefore(to)))
      .toList()
    ..sort((a, b) => a.time.compareTo(b.time));

  @override
  Future<void> addRecord(PointageRecord r) async => records.add(r);

  @override
  Future<void> deleteRecord(String id) async => records.removeWhere((r) => r.id == id);
}
