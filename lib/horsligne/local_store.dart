// lib/horsligne/local_store.dart
// Copie locale du catalogue (hors ligne, étape H1) : produits, clients assurance / carnet,
// tiers payants, modes de paiement (+ QR), date de la dernière synchro par catégorie.
// La recherche locale suit la même règle que le serveur (LIKE 'texte%', joker % accepté) :
// le texte reçu est celui que l'appli enverrait au serveur (serverQuery de search_mode.dart),
// donc « Commence par » et « Contient » se comportent comme en ligne.
// Deux implémentations : SQLite (sqflite) pour l'appli, mémoire pour les tests.
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:sqflite/sqflite.dart';

/// Catégories gardées sur le téléphone (une date de mise à jour chacune).
enum CatalogueCategorie { produits, clientsAssurance, clientsCarnet, tiersPayantsAssurance, tiersPayantsCarnet, modes }

extension CatalogueCategorieInfo on CatalogueCategorie {
  String get label => switch (this) {
        CatalogueCategorie.produits => 'Produits',
        CatalogueCategorie.clientsAssurance => 'Clients assurance',
        CatalogueCategorie.clientsCarnet => 'Clients carnet',
        CatalogueCategorie.tiersPayantsAssurance => 'Tiers payants assurance',
        CatalogueCategorie.tiersPayantsCarnet => 'Tiers payants carnet',
        CatalogueCategorie.modes => 'Modes de paiement',
      };
}

/// État de la copie locale : nombre d'éléments et date de mise à jour par catégorie.
class LocalStats {
  final Map<CatalogueCategorie, int> counts;
  final Map<CatalogueCategorie, DateTime> lastSync;
  const LocalStats({this.counts = const {}, this.lastSync = const {}});

  int count(CatalogueCategorie c) => counts[c] ?? 0;
  int get clients => count(CatalogueCategorie.clientsAssurance) + count(CatalogueCategorie.clientsCarnet);
  bool get isEmpty => counts.values.every((n) => n == 0);
}

/// Texte en majuscules sans accents (recherche insensible aux accents, comme le serveur).
String foldText(String s) {
  const from = 'ÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝŸŒÆ';
  const to = 'AAAAAACEEEEIIIINOOOOOUUUUYYOA';
  final b = StringBuffer();
  for (final r in s.toUpperCase().runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  return b.toString();
}

/// Motif LIKE du serveur pour [query] : « texte% » (le % tapé reste un joker).
String likePattern(String query) => '${foldText(query.trim())}%';

/// Même motif en expression régulière (implémentation mémoire).
RegExp likeRegExp(String pattern) {
  final b = StringBuffer('^');
  for (final r in pattern.runes) {
    final c = String.fromCharCode(r);
    b.write(c == '%' ? '.*' : c == '_' ? '.' : RegExp.escape(c));
  }
  b.write(r'$');
  return RegExp(b.toString(), dotAll: true);
}

/// Champs de recherche d'un client (nom complet, prénom, nom, n° sécu, code interne).
List<String> clientSearchFields(Map<String, dynamic> c) => [
      for (final k in ['fullName', 'strFIRSTNAME', 'strLASTNAME', 'strNUMEROSECURITESOCIAL', 'strCODEINTERNE']) foldText('${c[k] ?? ''}'),
    ];

List<String> tiersPayantSearchFields(Map<String, dynamic> t) => [foldText('${t['strNAME'] ?? ''}'), foldText('${t['strFULLNAME'] ?? ''}')];

/// Champs de recherche d'un produit, comme /vente/search (CIP, nom, EAN fabricant, identifiant).
List<String> productSearchFields(Map<String, dynamic> p) => [
      foldText('${p['strNAME'] ?? ''}'),
      '${p['intCIP'] ?? ''}'.trim(),
      '${p['codeEanFabriquant'] ?? ''}'.trim(),
      '${p['lgFAMILLEID'] ?? ''}',
    ];

String _idOf(CatalogueCategorie c, Map<String, dynamic> row) => switch (c) {
      CatalogueCategorie.produits => '${row['lgFAMILLEID'] ?? ''}',
      CatalogueCategorie.clientsAssurance || CatalogueCategorie.clientsCarnet => '${row['lgCLIENTID'] ?? ''}',
      CatalogueCategorie.tiersPayantsAssurance || CatalogueCategorie.tiersPayantsCarnet => '${row['lgTIERSPAYANTID'] ?? ''}',
      CatalogueCategorie.modes => '${row['_kind']}:${row['lgTYPEREGLEMENTID'] ?? row['id'] ?? ''}',
    };

/// Base locale. [replace] remplace une catégorie entière en une transaction :
/// si elle échoue, l'ancienne copie reste intacte.
/// [meta] (H5, mise à jour différentielle) : valeurs `meta` écrites dans la MÊME transaction (null = effacée).
abstract class LocalStore {
  Future<void> replace(CatalogueCategorie c, List<Map<String, dynamic>> rows, DateTime at, {Map<String, String?> meta = const {}});

  /// H5 : changements du catalogue produits (ajouts / modifications, suppressions par identifiant) et [meta],
  /// en UNE transaction : si elle échoue, rien n'est appliqué (ni produits, ni curseur).
  Future<void> appliquerProduits(List<Map<String, dynamic>> upserts, List<String> suppressions, DateTime at,
      {Map<String, String?> meta = const {}});

  /// Valeurs `meta` dont la clé commence par [prefixe] (H5 : état de la mise à jour différentielle).
  Future<Map<String, String>> metas(String prefixe);

  /// Recherche produit par pages ; [query] = texte envoyé au serveur (LIKE 'query%').
  Future<ProductPage> searchProducts(String query, int start, int limit);

  /// Clients d'un type ('1' assurance, '2' carnet) ; JSON brut du serveur.
  Future<List<Map<String, dynamic>>> searchClients(String query, {required String typeClientId, int limit = 50});
  Future<List<Map<String, dynamic>>> searchTiersPayants(String query, {required bool carnet, int limit = 50});

  /// Modes de paiement : /common/reglement ([qr] false) ou /modereglement/all ([qr] true).
  Future<List<Map<String, dynamic>>> modes({required bool qr});
  Future<LocalStats> stats();
  Future<void> clear();

  /// Recherche texte « Commence par » / « Contient » (réglage de l'appareil par défaut).
  Future<ProductPage> searchProductsText(String text, {SearchMode? mode, int start = 0, int limit = ProductLookup.pageSize}) {
    final q = serverQuery(text, modeFor(text, mode));
    if (q.isEmpty) return Future.value(const ProductPage([], 0));
    return searchProducts(q, start, limit);
  }

  /// Produit EXACT pour un code (CIP, EAN fabricant), avec les variantes de [ProductLookup.codeCandidates].
  Future<ProductSearchResult?> productByCode(String raw) async {
    for (final code in ProductLookup.codeCandidates(raw)) {
      final page = await searchProducts(code.replaceAll(RegExp(r'[%_]'), ''), 0, ProductLookup.pageSize);
      for (final prod in page.items) {
        if (prod.intCIP.trim() == code) return prod;
      }
      if (page.items.length == 1 && page.total <= 1) return page.items.first;
    }
    return null;
  }
}

/// Implémentation en mémoire (tests, ou repli si SQLite est indisponible).
class MemoryLocalStore extends LocalStore {
  final Map<CatalogueCategorie, List<Map<String, dynamic>>> _rows = {};
  final Map<CatalogueCategorie, DateTime> _last = {};

  final Map<String, String> _meta = {};

  /// Fait échouer la prochaine écriture (tests).
  bool failNextWrite = false;

  void _ecrireMeta(Map<String, String?> meta) => meta.forEach((k, v) => v == null ? _meta.remove(k) : _meta[k] = v);

  static void _trier(List<Map<String, dynamic>> l) => l.sort((a, b) => foldText('${a['strNAME']}').compareTo(foldText('${b['strNAME']}')));

  @override
  Future<void> appliquerProduits(List<Map<String, dynamic>> upserts, List<String> suppressions, DateTime at,
      {Map<String, String?> meta = const {}}) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('écriture refusée');
    }
    const c = CatalogueCategorie.produits;
    final byId = {for (final r in _rows[c] ?? const <Map<String, dynamic>>[]) _idOf(c, r): r};
    for (final id in suppressions) {
      byId.remove(id);
    }
    for (final r in upserts) {
      byId[_idOf(c, r)] = Map<String, dynamic>.from(r);
    }
    final list = byId.values.toList();
    _trier(list);
    _rows[c] = list;
    _last[c] = at;
    _ecrireMeta(meta);
  }

  @override
  Future<Map<String, String>> metas(String prefixe) async => {for (final e in _meta.entries) if (e.key.startsWith(prefixe)) e.key: e.value};

  @override
  Future<void> replace(CatalogueCategorie c, List<Map<String, dynamic>> rows, DateTime at, {Map<String, String?> meta = const {}}) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('écriture refusée');
    }
    final byId = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      byId[_idOf(c, r)] = Map<String, dynamic>.from(r);
    }
    final list = byId.values.toList();
    if (c == CatalogueCategorie.produits) _trier(list);
    _rows[c] = list;
    _last[c] = at;
    _ecrireMeta(meta);
  }

  Iterable<Map<String, dynamic>> _match(CatalogueCategorie c, String query, List<String> Function(Map<String, dynamic>) fields) {
    final re = likeRegExp(likePattern(query));
    return (_rows[c] ?? const []).where((r) => fields(r).any(re.hasMatch));
  }

  @override
  Future<ProductPage> searchProducts(String query, int start, int limit) async {
    final all = _match(CatalogueCategorie.produits, query, productSearchFields).toList();
    final page = all.skip(start).take(limit).map(ProductSearchResult.fromJson).toList();
    return ProductPage(page, all.length);
  }

  @override
  Future<List<Map<String, dynamic>>> searchClients(String query, {required String typeClientId, int limit = 50}) async {
    final c = typeClientId == '2' ? CatalogueCategorie.clientsCarnet : CatalogueCategorie.clientsAssurance;
    return _match(c, query, clientSearchFields).take(limit).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> searchTiersPayants(String query, {required bool carnet, int limit = 50}) async {
    final c = carnet ? CatalogueCategorie.tiersPayantsCarnet : CatalogueCategorie.tiersPayantsAssurance;
    return _match(c, query, tiersPayantSearchFields).take(limit).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> modes({required bool qr}) async =>
      (_rows[CatalogueCategorie.modes] ?? const []).where((r) => r['_kind'] == (qr ? 'qr' : 'reglement')).toList();

  @override
  Future<LocalStats> stats() async => LocalStats(
        counts: {for (final c in CatalogueCategorie.values) c: _rows[c]?.length ?? 0},
        lastSync: Map.of(_last),
      );

  @override
  Future<void> clear() async {
    _rows.clear();
    _last.clear();
    _meta.clear();
  }
}

/// Implémentation SQLite (fichier prestige_horsligne.db de l'appli).
class SqfliteLocalStore extends LocalStore {
  final DatabaseFactory? _factory;
  final String? _path;
  SqfliteLocalStore({DatabaseFactory? factory, String? path})
      : _factory = factory,
        _path = path;

  Future<Database>? _db;

  static const _version = 1;

  /// Lignes converties entre deux reprises de main (mise à jour sans ralentir l'appli).
  static int paquet = 200;

  Future<Database> get _database => _db ??= _open();

  Future<Database> _open() async {
    final f = _factory ?? databaseFactory;
    final path = _path ?? p.join(await f.getDatabasesPath(), 'prestige_horsligne.db');
    return f.openDatabase(path, options: OpenDatabaseOptions(version: _version, onCreate: (db, _) => _create(db)));
  }

  static Future<void> _create(Database db) async {
    final b = db.batch();
    b.execute('CREATE TABLE produits (id TEXT PRIMARY KEY, cip TEXT, ean TEXT, nom TEXT, nom_n TEXT, prix INTEGER, '
        'stock INTEGER, libelle TEXT, maj TEXT, json TEXT)');
    b.execute('CREATE INDEX produits_nom ON produits(nom_n)');
    b.execute('CREATE INDEX produits_cip ON produits(cip)');
    b.execute('CREATE TABLE clients (id TEXT, type TEXT, nom_n TEXT, prenom_n TEXT, famille_n TEXT, secu TEXT, code TEXT, '
        'json TEXT, PRIMARY KEY (id, type))');
    b.execute('CREATE TABLE tiers_payants (id TEXT, carnet INTEGER, nom_n TEXT, complet_n TEXT, json TEXT, PRIMARY KEY (id, carnet))');
    b.execute('CREATE TABLE modes (cle TEXT PRIMARY KEY, kind TEXT, pos INTEGER, json TEXT)');
    b.execute('CREATE TABLE meta (cle TEXT PRIMARY KEY, valeur TEXT)');
    await b.commit(noResult: true);
  }

  /// Base ouverte, avec la migration [name] appliquée une seule fois (tables d'autres modules,
  /// ex. stock hors ligne H3). Migrations NOMMÉES (table `migrations`) : plusieurs modules peuvent
  /// en ajouter sans se disputer le numéro de version de la base.
  Future<Database> withMigration(String name, Future<void> Function(Transaction txn) migrate) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.execute('CREATE TABLE IF NOT EXISTS migrations (nom TEXT PRIMARY KEY, at TEXT)');
      if ((await txn.query('migrations', where: 'nom = ?', whereArgs: [name])).isNotEmpty) return;
      await migrate(txn);
      await txn.insert('migrations', {'nom': name, 'at': DateTime.now().toIso8601String()});
    });
    return db;
  }

  /// Ferme la base (tests).
  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) await (await db).close();
  }

  /// Ligne SQLite d'un produit (JSON brut de /vente/search).
  static Map<String, Object?> _produitRow(Map<String, dynamic> r, String maj) => {
        'id': '${r['lgFAMILLEID'] ?? ''}',
        'cip': '${r['intCIP'] ?? ''}'.trim(),
        'ean': '${r['codeEanFabriquant'] ?? ''}'.trim(),
        'nom': '${r['strNAME'] ?? ''}',
        'nom_n': foldText('${r['strNAME'] ?? ''}'),
        'prix': (r['intPRICE'] as num?)?.toInt() ?? 0,
        'stock': (r['intNUMBERAVAILABLE'] as num?)?.toInt() ?? 0,
        'libelle': '${r['strLIBELLEE'] ?? ''}',
        'maj': maj,
        'json': jsonEncode(r),
      };

  static void _metaBatch(Batch b, Map<String, String?> meta) => meta.forEach((k, v) => v == null
      ? b.delete('meta', where: 'cle = ?', whereArgs: [k])
      : b.insert('meta', {'cle': k, 'valeur': v}, conflictAlgorithm: ConflictAlgorithm.replace));

  @override
  Future<void> appliquerProduits(List<Map<String, dynamic>> upserts, List<String> suppressions, DateTime at,
      {Map<String, String?> meta = const {}}) async {
    final db = await _database;
    final maj = at.toIso8601String();
    await db.transaction((txn) async {
      final b = txn.batch();
      for (var i = 0; i < suppressions.length; i += 200) {
        final ids = suppressions.sublist(i, (i + 200).clamp(0, suppressions.length));
        b.delete('produits', where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
      }
      var n = 0;
      for (final r in upserts) {
        if (++n % paquet == 0) await Future<void>.delayed(Duration.zero);
        b.insert('produits', _produitRow(r, maj), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      b.insert('meta', {'cle': 'maj_${CatalogueCategorie.produits.name}', 'valeur': maj}, conflictAlgorithm: ConflictAlgorithm.replace);
      _metaBatch(b, meta);
      await b.commit(noResult: true);
    });
  }

  @override
  Future<Map<String, String>> metas(String prefixe) async {
    final db = await _database;
    final rows = await db.query('meta', where: 'substr(cle, 1, ?) = ?', whereArgs: [prefixe.length, prefixe]);
    return {for (final r in rows) '${r['cle']}': '${r['valeur']}'};
  }

  @override
  Future<void> replace(CatalogueCategorie c, List<Map<String, dynamic>> rows, DateTime at, {Map<String, String?> meta = const {}}) async {
    final db = await _database;
    final maj = at.toIso8601String();
    await db.transaction((txn) async {
      final b = txn.batch();
      // Conversion par paquets : la main est rendue à l'interface tous les [paquet] produits.
      var n = 0;
      Future<void> cede() async {
        if (++n % paquet == 0) await Future<void>.delayed(Duration.zero);
      }
      switch (c) {
        case CatalogueCategorie.produits:
          b.delete('produits');
          for (final r in rows) {
            await cede();
            b.insert('produits', _produitRow(r, maj), conflictAlgorithm: ConflictAlgorithm.replace);
          }
        case CatalogueCategorie.clientsAssurance || CatalogueCategorie.clientsCarnet:
          final type = c == CatalogueCategorie.clientsCarnet ? '2' : '1';
          b.delete('clients', where: 'type = ?', whereArgs: [type]);
          for (final r in rows) {
            await cede();
            final f = clientSearchFields(r);
            b.insert(
                'clients',
                {'id': _idOf(c, r), 'type': type, 'nom_n': f[0], 'prenom_n': f[1], 'famille_n': f[2], 'secu': f[3], 'code': f[4], 'json': jsonEncode(r)},
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
        case CatalogueCategorie.tiersPayantsAssurance || CatalogueCategorie.tiersPayantsCarnet:
          final carnet = c == CatalogueCategorie.tiersPayantsCarnet ? 1 : 0;
          b.delete('tiers_payants', where: 'carnet = ?', whereArgs: [carnet]);
          for (final r in rows) {
            await cede();
            final f = tiersPayantSearchFields(r);
            b.insert('tiers_payants', {'id': _idOf(c, r), 'carnet': carnet, 'nom_n': f[0], 'complet_n': f[1], 'json': jsonEncode(r)},
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
        case CatalogueCategorie.modes:
          b.delete('modes');
          var pos = 0;
          for (final r in rows) {
            await cede();
            b.insert('modes', {'cle': _idOf(c, r), 'kind': '${r['_kind']}', 'pos': pos++, 'json': jsonEncode(r)},
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
      }
      b.insert('meta', {'cle': 'maj_${c.name}', 'valeur': maj}, conflictAlgorithm: ConflictAlgorithm.replace);
      _metaBatch(b, meta);
      await b.commit(noResult: true);
    });
  }

  static List<Map<String, dynamic>> _json(List<Map<String, Object?>> rows) =>
      [for (final r in rows) Map<String, dynamic>.from(jsonDecode('${r['json']}') as Map)];

  @override
  Future<ProductPage> searchProducts(String query, int start, int limit) async {
    final db = await _database;
    final like = likePattern(query);
    const where = 'nom_n LIKE ?1 OR cip LIKE ?1 OR ean LIKE ?1 OR id LIKE ?1';
    final n = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM produits WHERE $where', [like])) ?? 0;
    if (n == 0) return const ProductPage([], 0);
    final rows = await db.rawQuery('SELECT json FROM produits WHERE $where ORDER BY nom_n LIMIT ?2 OFFSET ?3', [like, limit, start]);
    return ProductPage(_json(rows).map(ProductSearchResult.fromJson).toList(), n);
  }

  @override
  Future<List<Map<String, dynamic>>> searchClients(String query, {required String typeClientId, int limit = 50}) async {
    final db = await _database;
    final rows = await db.rawQuery(
        'SELECT json FROM clients WHERE type = ?2 AND (nom_n LIKE ?1 OR prenom_n LIKE ?1 OR famille_n LIKE ?1 OR secu LIKE ?1 OR code LIKE ?1) '
        'ORDER BY nom_n LIMIT ?3',
        [likePattern(query), typeClientId == '2' ? '2' : '1', limit]);
    return _json(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> searchTiersPayants(String query, {required bool carnet, int limit = 50}) async {
    final db = await _database;
    final rows = await db.rawQuery(
        'SELECT json FROM tiers_payants WHERE carnet = ?2 AND (nom_n LIKE ?1 OR complet_n LIKE ?1) ORDER BY nom_n LIMIT ?3',
        [likePattern(query), carnet ? 1 : 0, limit]);
    return _json(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> modes({required bool qr}) async {
    final db = await _database;
    return _json(await db.rawQuery('SELECT json FROM modes WHERE kind = ? ORDER BY pos', [qr ? 'qr' : 'reglement']));
  }

  @override
  Future<LocalStats> stats() async {
    final db = await _database;
    Future<int> count(String sql, [List<Object?> args = const []]) async => Sqflite.firstIntValue(await db.rawQuery(sql, args)) ?? 0;
    final counts = {
      CatalogueCategorie.produits: await count('SELECT COUNT(*) FROM produits'),
      CatalogueCategorie.clientsAssurance: await count('SELECT COUNT(*) FROM clients WHERE type = ?', ['1']),
      CatalogueCategorie.clientsCarnet: await count('SELECT COUNT(*) FROM clients WHERE type = ?', ['2']),
      CatalogueCategorie.tiersPayantsAssurance: await count('SELECT COUNT(*) FROM tiers_payants WHERE carnet = 0'),
      CatalogueCategorie.tiersPayantsCarnet: await count('SELECT COUNT(*) FROM tiers_payants WHERE carnet = 1'),
      CatalogueCategorie.modes: await count('SELECT COUNT(*) FROM modes'),
    };
    final last = <CatalogueCategorie, DateTime>{};
    for (final r in await db.query('meta')) {
      final key = '${r['cle']}';
      if (!key.startsWith('maj_')) continue;
      final c = CatalogueCategorie.values.where((c) => 'maj_${c.name}' == key).firstOrNull;
      final d = DateTime.tryParse('${r['valeur']}');
      if (c != null && d != null) last[c] = d;
    }
    return LocalStats(counts: counts, lastSync: last);
  }

  @override
  Future<void> clear() async {
    final db = await _database;
    await db.transaction((txn) async {
      for (final t in ['produits', 'clients', 'tiers_payants', 'modes', 'meta']) {
        await txn.delete(t);
      }
    });
  }
}
