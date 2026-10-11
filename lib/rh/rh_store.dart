// lib/rh/rh_store.dart
// Voie B — copie locale des employés (retrouver un badge hors ligne) et file persistante des pointages
// par badge (envoyés au retour du serveur). SQLite : tables ajoutées au fichier du catalogue par la
// migration nommée « rh_pointage_v1 » (LocalStore.withMigration) ; implémentation mémoire pour les tests.
// « Vider la copie locale » efface les employés, jamais la file des pointages.
import 'dart:convert';

import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:sqflite/sqflite.dart';

abstract class RhStore {
  Future<List<EmployeRh>> employes();

  /// Remplace la copie des employés en une transaction (l'ancienne reste si l'écriture échoue).
  Future<void> remplacerEmployes(List<EmployeRh> employes, DateTime at);
  Future<DateTime?> employesAt();
  Future<void> viderEmployes();

  /// File des pointages par badge (tous statuts, plus anciens d'abord).
  Future<List<PointageBadge>> pointages();
  Future<void> enregistrer(PointageBadge p);

  /// Purge des pointages terminés lus avant [avant] (jamais ceux en attente ou en anomalie non traitée).
  Future<int> purger(DateTime avant);
}

class MemoryRhStore implements RhStore {
  List<EmployeRh> _employes = [];
  DateTime? _at;
  final Map<String, PointageBadge> _file = {};

  @override
  Future<List<EmployeRh>> employes() async => List.of(_employes);
  @override
  Future<void> remplacerEmployes(List<EmployeRh> employes, DateTime at) async {
    _employes = List.of(employes);
    _at = at;
  }

  @override
  Future<DateTime?> employesAt() async => _at;
  @override
  Future<void> viderEmployes() async {
    _employes = [];
    _at = null;
  }

  @override
  Future<List<PointageBadge>> pointages() async => _file.values.toList()..sort((a, b) => a.lu.compareTo(b.lu));
  @override
  Future<void> enregistrer(PointageBadge p) async => _file[p.id] = p;
  @override
  Future<int> purger(DateTime avant) async {
    final ids = [for (final p in _file.values) if (_purgeable(p, avant)) p.id];
    ids.forEach(_file.remove);
    return ids.length;
  }
}

bool _purgeable(PointageBadge p, DateTime avant) =>
    p.lu.isBefore(avant) && p.statut.termine && (p.statut != StatutPointageBadge.refuse || p.traitee);

class SqfliteRhStore implements RhStore {
  final SqfliteLocalStore local;
  SqfliteRhStore(this.local);

  static const migration = 'rh_pointage_v1';

  Future<Database> get _db => local.withMigration(migration, (txn) async {
        await txn.execute('CREATE TABLE rh_employes (id TEXT PRIMARY KEY, json TEXT)');
        await txn.execute('CREATE TABLE rh_pointages (id TEXT PRIMARY KEY, lu TEXT, statut TEXT, json TEXT)');
        await txn.execute('CREATE INDEX rh_pointages_lu ON rh_pointages(lu)');
      });

  static const _metaEmployes = 'rh_employes_at';

  @override
  Future<List<EmployeRh>> employes() async {
    final rows = await (await _db).query('rh_employes');
    return [for (final r in rows) EmployeRh.fromJson(Map<String, dynamic>.from(jsonDecode('${r['json']}') as Map))];
  }

  @override
  Future<void> remplacerEmployes(List<EmployeRh> employes, DateTime at) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('rh_employes');
      final b = txn.batch();
      for (final e in employes) {
        b.insert('rh_employes', {'id': e.id, 'json': jsonEncode(e.toJson())}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      b.insert('meta', {'cle': _metaEmployes, 'valeur': at.toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
      await b.commit(noResult: true);
    });
  }

  @override
  Future<DateTime?> employesAt() async {
    final r = await (await _db).query('meta', where: 'cle = ?', whereArgs: [_metaEmployes]);
    return r.isEmpty ? null : DateTime.tryParse('${r.first['valeur']}');
  }

  @override
  Future<void> viderEmployes() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('rh_employes');
      await txn.delete('meta', where: 'cle = ?', whereArgs: [_metaEmployes]);
    });
  }

  @override
  Future<List<PointageBadge>> pointages() async {
    final rows = await (await _db).query('rh_pointages', orderBy: 'lu');
    return [for (final r in rows) PointageBadge.fromJson(Map<String, dynamic>.from(jsonDecode('${r['json']}') as Map))];
  }

  @override
  Future<void> enregistrer(PointageBadge p) async {
    await (await _db).insert('rh_pointages', {'id': p.id, 'lu': p.lu.toIso8601String(), 'statut': p.statut.name, 'json': jsonEncode(p.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<int> purger(DateTime avant) async {
    final db = await _db;
    final ids = [for (final p in await pointages()) if (_purgeable(p, avant)) p.id];
    if (ids.isEmpty) return 0;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.delete('rh_pointages', where: 'id = ?', whereArgs: [id]);
      }
    });
    return ids.length;
  }
}
