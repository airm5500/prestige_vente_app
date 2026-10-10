// lib/horsligne/stock/stock_store.dart
// Base locale du stock hors ligne (H3) : copie de référence (BL, commandes, grossistes, motifs…),
// file des opérations saisies hors ligne et anomalies. Dans le même fichier SQLite que le catalogue
// (migration nommée « stock_h3_v1 » de SqfliteLocalStore) ; implémentation mémoire pour les tests.
//
// La copie de référence est remplacée EN UNE TRANSACTION ([replaceRefs]) : si la synchro échoue,
// l'ancienne copie reste entière. Les opérations et anomalies ne sont JAMAIS effacées par
// « Vider la copie locale » (seule la référence l'est).
import 'dart:convert';

import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:sqflite/sqflite.dart';

abstract class StockStore {
  /// Remplace toutes les catégories fournies, en une transaction. Les lignes peuvent porter
  /// '_parent' (BL ou commande de rattachement).
  Future<void> replaceRefs(Map<StockRef, List<Map<String, dynamic>>> rows, DateTime at);

  /// Lignes d'une catégorie (ordre d'enregistrement), éventuellement d'un parent.
  Future<List<Map<String, dynamic>>> refs(StockRef c, {String? parent});

  /// Une ligne par identifiant.
  Future<Map<String, dynamic>?> ref(StockRef c, String id);
  Future<StockRefStats> refStats();
  Future<void> clearRefs();

  Future<List<StockOp>> ops();
  Future<void> saveOp(StockOp op);
  Future<void> deleteOp(String id);

  Future<List<Anomalie>> anomalies();
  Future<void> saveAnomalie(Anomalie a);
}

/// Implémentation en mémoire (tests, ou repli si SQLite est indisponible).
class MemoryStockStore extends StockStore {
  final Map<StockRef, List<Map<String, dynamic>>> _refs = {};
  final Map<StockRef, DateTime> _last = {};
  final Map<String, String> _ops = {};
  final Map<String, Map<String, dynamic>> _anomalies = {};

  /// Fait échouer la prochaine écriture de la référence (tests).
  bool failNextWrite = false;

  @override
  Future<void> replaceRefs(Map<StockRef, List<Map<String, dynamic>>> rows, DateTime at) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('écriture refusée');
    }
    for (final e in rows.entries) {
      final byId = <String, Map<String, dynamic>>{};
      for (final r in e.value) {
        byId['${r['_parent'] ?? ''}|${e.key.idOf(r)}'] = jsonDecode(jsonEncode(r)) as Map<String, dynamic>;
      }
      _refs[e.key] = byId.values.toList();
      _last[e.key] = at;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> refs(StockRef c, {String? parent}) async => [
        for (final r in _refs[c] ?? const <Map<String, dynamic>>[])
          if (parent == null || '${r['_parent']}' == parent) Map<String, dynamic>.from(r),
      ];

  @override
  Future<Map<String, dynamic>?> ref(StockRef c, String id) async {
    for (final r in _refs[c] ?? const <Map<String, dynamic>>[]) {
      if (c.idOf(r) == id) return Map<String, dynamic>.from(r);
    }
    return null;
  }

  @override
  Future<StockRefStats> refStats() async =>
      StockRefStats(counts: {for (final c in StockRef.values) c: _refs[c]?.length ?? 0}, lastSync: Map.of(_last));

  @override
  Future<void> clearRefs() async {
    _refs.clear();
    _last.clear();
  }

  @override
  Future<List<StockOp>> ops() async {
    final list = _ops.values.map(StockOp.decode).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  @override
  Future<void> saveOp(StockOp op) async => _ops[op.id] = op.encode();

  @override
  Future<void> deleteOp(String id) async => _ops.remove(id);

  @override
  Future<List<Anomalie>> anomalies() async =>
      _anomalies.values.map(Anomalie.fromJson).toList()..sort((a, b) => b.date.compareTo(a.date));

  @override
  Future<void> saveAnomalie(Anomalie a) async => _anomalies[a.id] = a.toJson();
}

/// Implémentation SQLite : tables ajoutées au fichier du catalogue par une migration nommée.
class SqfliteStockStore extends StockStore {
  final SqfliteLocalStore local;
  SqfliteStockStore(this.local);

  static const migration = 'stock_h3_v1';

  Future<Database> get _db => local.withMigration(migration, (txn) async {
        await txn.execute('CREATE TABLE IF NOT EXISTS stock_refs (cat TEXT, id TEXT, parent TEXT, pos INTEGER, json TEXT, '
            'PRIMARY KEY (cat, parent, id))');
        await txn.execute('CREATE INDEX IF NOT EXISTS stock_refs_parent ON stock_refs(cat, parent)');
        await txn.execute('CREATE TABLE IF NOT EXISTS stock_meta (cle TEXT PRIMARY KEY, valeur TEXT)');
        await txn.execute('CREATE TABLE IF NOT EXISTS stock_ops (id TEXT PRIMARY KEY, created TEXT, statut TEXT, json TEXT)');
        await txn.execute('CREATE TABLE IF NOT EXISTS anomalies (id TEXT PRIMARY KEY, source TEXT, date TEXT, traitee INTEGER, json TEXT)');
      });

  @override
  Future<void> replaceRefs(Map<StockRef, List<Map<String, dynamic>>> rows, DateTime at) async {
    final db = await _db;
    await db.transaction((txn) async {
      final b = txn.batch();
      var n = 0;
      for (final e in rows.entries) {
        b.delete('stock_refs', where: 'cat = ?', whereArgs: [e.key.name]);
        var pos = 0;
        for (final r in e.value) {
          // Conversion par paquets : la main est rendue à l'interface.
          if (++n % SqfliteLocalStore.paquet == 0) await Future<void>.delayed(Duration.zero);
          b.insert(
              'stock_refs',
              {'cat': e.key.name, 'id': e.key.idOf(r), 'parent': '${r['_parent'] ?? ''}', 'pos': pos++, 'json': jsonEncode(r)},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        b.insert('stock_meta', {'cle': 'maj_${e.key.name}', 'valeur': at.toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await b.commit(noResult: true);
    });
  }

  static List<Map<String, dynamic>> _json(List<Map<String, Object?>> rows) =>
      [for (final r in rows) Map<String, dynamic>.from(jsonDecode('${r['json']}') as Map)];

  @override
  Future<List<Map<String, dynamic>>> refs(StockRef c, {String? parent}) async {
    final db = await _db;
    return _json(parent == null
        ? await db.query('stock_refs', columns: ['json'], where: 'cat = ?', whereArgs: [c.name], orderBy: 'pos')
        : await db.query('stock_refs', columns: ['json'], where: 'cat = ? AND parent = ?', whereArgs: [c.name, parent], orderBy: 'pos'));
  }

  @override
  Future<Map<String, dynamic>?> ref(StockRef c, String id) async {
    final db = await _db;
    final rows = _json(await db.query('stock_refs', columns: ['json'], where: 'cat = ? AND id = ?', whereArgs: [c.name, id], limit: 1));
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<StockRefStats> refStats() async {
    final db = await _db;
    final counts = <StockRef, int>{for (final c in StockRef.values) c: 0};
    for (final r in await db.rawQuery('SELECT cat, COUNT(*) AS n FROM stock_refs GROUP BY cat')) {
      final c = StockRef.values.where((c) => c.name == r['cat']).firstOrNull;
      if (c != null) counts[c] = (r['n'] as num).toInt();
    }
    final last = <StockRef, DateTime>{};
    for (final r in await db.query('stock_meta')) {
      final c = StockRef.values.where((c) => 'maj_${c.name}' == r['cle']).firstOrNull;
      final d = DateTime.tryParse('${r['valeur']}');
      if (c != null && d != null) last[c] = d;
    }
    return StockRefStats(counts: counts, lastSync: last);
  }

  @override
  Future<void> clearRefs() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('stock_refs');
      await txn.delete('stock_meta');
    });
  }

  @override
  Future<List<StockOp>> ops() async {
    final db = await _db;
    return [for (final r in await db.query('stock_ops', orderBy: 'created, id')) StockOp.decode('${r['json']}')];
  }

  @override
  Future<void> saveOp(StockOp op) async {
    final db = await _db;
    await db.insert('stock_ops', {'id': op.id, 'created': op.createdAt.toIso8601String(), 'statut': op.statut.name, 'json': op.encode()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteOp(String id) async {
    final db = await _db;
    await db.delete('stock_ops', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<Anomalie>> anomalies() async {
    final db = await _db;
    return [
      for (final r in await db.query('anomalies', orderBy: 'date DESC'))
        Anomalie.fromJson(Map<String, dynamic>.from(jsonDecode('${r['json']}') as Map)),
    ];
  }

  @override
  Future<void> saveAnomalie(Anomalie a) async {
    final db = await _db;
    await db.insert('anomalies', {'id': a.id, 'source': a.source, 'date': a.date.toIso8601String(), 'traitee': a.traitee ? 1 : 0, 'json': jsonEncode(a.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
