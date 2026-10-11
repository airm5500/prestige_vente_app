// lib/horsligne/vente_hors_ligne.dart
// Ventes saisies hors ligne (étape H2) : modèle et file persistée sur l'appareil.
// Chaque vente a un identifiant local unique et un numéro lisible HL-0001… ; son contenu complet
// (lignes, client / ayant droit / tiers payants / bons, choix final) est gardé jusqu'à l'envoi.
// L'avancement de l'envoi (étape, identifiant de la vente serveur) est enregistré à chaque pas :
// l'appli peut être fermée à tout moment, l'envoi reprend à la bonne étape.
// Deux implémentations : SQLite (fichier séparé du catalogue) pour l'appli, mémoire pour les tests.
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

enum TypeVenteHL { comptant, assurance, carnet }

/// Choix final : prévente (terminerprevente) ou encaissement espèces (clôture).
enum FinVenteHL { prevente, especes }

/// [ressaisie] : décochée à la confirmation d'envoi (déjà ressaisie sur le serveur) : jamais envoyée.
enum StatutVenteHL { enAttente, envoiEnCours, envoyee, aVerifier, traitee, ressaisie }

extension TypeVenteHLInfo on TypeVenteHL {
  String get label => switch (this) {
        TypeVenteHL.comptant => 'Comptant',
        TypeVenteHL.assurance => 'Assurance',
        TypeVenteHL.carnet => 'Carnet',
      };
}

extension StatutVenteHLInfo on StatutVenteHL {
  String get label => switch (this) {
        StatutVenteHL.enAttente => 'En attente d\'envoi',
        StatutVenteHL.envoiEnCours => 'Envoi en cours',
        StatutVenteHL.envoyee => 'Envoyée',
        StatutVenteHL.aVerifier => 'Anomalie à vérifier',
        StatutVenteHL.traitee => 'Traitée',
        StatutVenteHL.ressaisie => 'Non envoyée — ressaisie sur le serveur',
      };

  /// Libellé court (pastille).
  String get court => switch (this) {
        StatutVenteHL.enAttente => 'En attente',
        StatutVenteHL.envoiEnCours => 'Envoi…',
        StatutVenteHL.envoyee => 'Envoyée',
        StatutVenteHL.aVerifier => 'Anomalie',
        StatutVenteHL.traitee => 'Traitée',
        StatutVenteHL.ressaisie => 'Ressaisie',
      };
}

/// « HL-0007 ».
String numeroHL(int n) => 'HL-${n.toString().padLeft(4, '0')}';

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) => values.where((v) => v.name == '$name').firstOrNull ?? fallback;
int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
String? _strOrNull(Object? v) => v == null || '$v'.isEmpty ? null : '$v';

/// Ligne d'une vente hors ligne.
class LigneHL {
  /// Identifiant local de la ligne (ou celui de la ligne serveur si [serveur]).
  final String cle;
  final String produitId;
  final String nom;
  final String cip;
  final int qte;

  /// Prix appliqué (modifiable comme en ligne).
  final int prix;

  /// Prix du catalogue local au moment de l'ajout (comparé au prix du serveur à l'envoi).
  final int prixCatalogue;

  /// Stock connu dans la copie locale au moment de l'ajout.
  final int stockConnu;

  /// Ligne déjà enregistrée sur le serveur (vente commencée en ligne) : jamais renvoyée.
  final bool serveur;

  const LigneHL({
    required this.cle,
    required this.produitId,
    required this.nom,
    this.cip = '',
    required this.qte,
    required this.prix,
    int? prixCatalogue,
    this.stockConnu = 0,
    this.serveur = false,
  }) : prixCatalogue = prixCatalogue ?? prix;

  int get total => qte * prix;

  LigneHL copyWith({int? qte, int? prix}) => LigneHL(
        cle: cle,
        produitId: produitId,
        nom: nom,
        cip: cip,
        qte: qte ?? this.qte,
        prix: prix ?? this.prix,
        prixCatalogue: prixCatalogue,
        stockConnu: stockConnu,
        serveur: serveur,
      );

  Map<String, dynamic> toJson() => {
        'cle': cle,
        'produitId': produitId,
        'nom': nom,
        'cip': cip,
        'qte': qte,
        'prix': prix,
        'prixCatalogue': prixCatalogue,
        'stockConnu': stockConnu,
        'serveur': serveur,
      };

  static LigneHL fromJson(Map<String, dynamic> j) => LigneHL(
        cle: '${j['cle'] ?? ''}',
        produitId: '${j['produitId'] ?? ''}',
        nom: '${j['nom'] ?? ''}',
        cip: '${j['cip'] ?? ''}',
        qte: _int(j['qte']),
        prix: _int(j['prix']),
        prixCatalogue: _int(j['prixCatalogue'] ?? j['prix']),
        stockConnu: _int(j['stockConnu']),
        serveur: j['serveur'] == true,
      );
}

/// Tiers payant d'une vente assurance / carnet hors ligne.
class TpHL {
  final String compteTp;
  final String numBon;
  final int taux;
  final String nom;
  const TpHL({required this.compteTp, required this.numBon, required this.taux, this.nom = ''});

  Map<String, dynamic> toJson() => {'compteTp': compteTp, 'numBon': numBon, 'taux': taux, 'nom': nom};
  static TpHL fromJson(Map<String, dynamic> j) =>
      TpHL(compteTp: '${j['compteTp'] ?? ''}', numBon: '${j['numBon'] ?? ''}', taux: _int(j['taux']), nom: '${j['nom'] ?? ''}');
}

/// Étapes de l'envoi (enregistrées AVANT chaque appel « …Envoyee » : si l'appli est fermée pendant
/// l'appel, la reprise sait qu'il faut relire le serveur avant de renvoyer).
abstract final class EtapeHL {
  static const creation = 'creation';
  static const creationEnvoyee = 'creationEnvoyee';

  /// H4 : création envoyée avec la clé client (`X-Client-Ref`) à un serveur qui la gère : si la réponse est
  /// perdue, la création est relue par sa clé (GET /app-vente/client-ref/{ref}) au lieu d'une anomalie.
  static const creationEnvoyeeRef = 'creationEnvoyeeRef';
  static const articles = 'articles';
  static const net = 'net';
  static const fin = 'fin';
  static const finEnvoyee = 'finEnvoyee';
}

class VenteHorsLigne {
  /// Identifiant local unique.
  final String id;
  final int numero;
  final TypeVenteHL type;
  final List<LigneHL> lignes;

  /// Client, ayant droit (JSON du serveur) et tiers payants / bons (assurance, carnet).
  final Map<String, dynamic>? client;
  final Map<String, dynamic>? ayantDroit;
  final List<TpHL> tps;

  final FinVenteHL fin;

  /// Total brut et net estimés sur l'appareil (part client pour l'assurance / le carnet).
  final int totalEstime;
  final int netEstime;

  /// Encaissement espèces provisoire : montant reçu et monnaie rendue.
  final int? montantRecu;
  final int? montantRendu;

  /// Nom du mode espèces (comme en ligne, sert à associer le client « especes »).
  final String modeNom;

  final StatutVenteHL statut;
  final String? etape;

  /// Vente serveur (enregistrée dès sa création ; dès le début si la vente a été commencée en ligne).
  final String? venteId;
  final bool commenceeEnLigne;
  final String? reference;
  final String? motif;

  /// Écarts vus et acceptés par l'utilisateur (« Renvoyer ») : ne bloquent plus l'envoi.
  final List<String> acceptes;
  final int tentatives;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? envoyeeAt;
  final String userId;
  final String userName;

  const VenteHorsLigne({
    required this.id,
    required this.numero,
    required this.type,
    required this.lignes,
    this.client,
    this.ayantDroit,
    this.tps = const [],
    required this.fin,
    required this.totalEstime,
    required this.netEstime,
    this.montantRecu,
    this.montantRendu,
    this.modeNom = 'ESPECES',
    this.statut = StatutVenteHL.enAttente,
    this.etape,
    this.venteId,
    this.commenceeEnLigne = false,
    this.reference,
    this.motif,
    this.acceptes = const [],
    this.tentatives = 0,
    required this.createdAt,
    required this.updatedAt,
    this.envoyeeAt,
    this.userId = '',
    this.userName = '',
  });

  String get numeroLabel => numeroHL(numero);

  /// Ni envoyée ni traitée : encore à faire.
  bool get aFaire => statut == StatutVenteHL.enAttente || statut == StatutVenteHL.envoiEnCours;

  /// Suppression possible : rien n'existe sur le serveur.
  bool get supprimable => venteId == null && statut != StatutVenteHL.envoyee && !(etape == EtapeHL.creationEnvoyee || etape == EtapeHL.creationEnvoyeeRef);

  String get clientNom => '${client?['fullName'] ?? ''}'.trim().isNotEmpty
      ? '${client!['fullName']}'.trim()
      : '${client?['strFIRSTNAME'] ?? ''} ${client?['strLASTNAME'] ?? ''}'.trim();

  static const _unset = Object();

  VenteHorsLigne copyWith({
    StatutVenteHL? statut,
    Object? etape = _unset,
    Object? venteId = _unset,
    Object? reference = _unset,
    Object? motif = _unset,
    List<String>? acceptes,
    int? tentatives,
    DateTime? updatedAt,
    Object? envoyeeAt = _unset,
  }) =>
      VenteHorsLigne(
        id: id,
        numero: numero,
        type: type,
        lignes: lignes,
        client: client,
        ayantDroit: ayantDroit,
        tps: tps,
        fin: fin,
        totalEstime: totalEstime,
        netEstime: netEstime,
        montantRecu: montantRecu,
        montantRendu: montantRendu,
        modeNom: modeNom,
        statut: statut ?? this.statut,
        etape: identical(etape, _unset) ? this.etape : etape as String?,
        venteId: identical(venteId, _unset) ? this.venteId : venteId as String?,
        commenceeEnLigne: commenceeEnLigne,
        reference: identical(reference, _unset) ? this.reference : reference as String?,
        motif: identical(motif, _unset) ? this.motif : motif as String?,
        acceptes: acceptes ?? this.acceptes,
        tentatives: tentatives ?? this.tentatives,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        envoyeeAt: identical(envoyeeAt, _unset) ? this.envoyeeAt : envoyeeAt as DateTime?,
        userId: userId,
        userName: userName,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'numero': numero,
        'type': type.name,
        'lignes': [for (final l in lignes) l.toJson()],
        'client': client,
        'ayantDroit': ayantDroit,
        'tps': [for (final t in tps) t.toJson()],
        'fin': fin.name,
        'totalEstime': totalEstime,
        'netEstime': netEstime,
        'montantRecu': montantRecu,
        'montantRendu': montantRendu,
        'modeNom': modeNom,
        'statut': statut.name,
        'etape': etape,
        'venteId': venteId,
        'commenceeEnLigne': commenceeEnLigne,
        'reference': reference,
        'motif': motif,
        'acceptes': acceptes,
        'tentatives': tentatives,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'envoyeeAt': envoyeeAt?.toIso8601String(),
        'userId': userId,
        'userName': userName,
      };

  static VenteHorsLigne fromJson(Map<String, dynamic> j) {
    final created = DateTime.tryParse('${j['createdAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0);
    return VenteHorsLigne(
      id: '${j['id']}',
      numero: _int(j['numero']),
      type: _enum(TypeVenteHL.values, j['type'], TypeVenteHL.comptant),
      lignes: [
        if (j['lignes'] is List)
          for (final l in j['lignes'] as List)
            if (l is Map) LigneHL.fromJson(Map<String, dynamic>.from(l)),
      ],
      client: j['client'] is Map ? Map<String, dynamic>.from(j['client'] as Map) : null,
      ayantDroit: j['ayantDroit'] is Map ? Map<String, dynamic>.from(j['ayantDroit'] as Map) : null,
      tps: [
        if (j['tps'] is List)
          for (final t in j['tps'] as List)
            if (t is Map) TpHL.fromJson(Map<String, dynamic>.from(t)),
      ],
      fin: _enum(FinVenteHL.values, j['fin'], FinVenteHL.prevente),
      totalEstime: _int(j['totalEstime']),
      netEstime: _int(j['netEstime']),
      montantRecu: j['montantRecu'] == null ? null : _int(j['montantRecu']),
      montantRendu: j['montantRendu'] == null ? null : _int(j['montantRendu']),
      modeNom: '${j['modeNom'] ?? 'ESPECES'}',
      statut: _enum(StatutVenteHL.values, j['statut'], StatutVenteHL.enAttente),
      etape: _strOrNull(j['etape']),
      venteId: _strOrNull(j['venteId']),
      commenceeEnLigne: j['commenceeEnLigne'] == true,
      reference: _strOrNull(j['reference']),
      motif: _strOrNull(j['motif']),
      acceptes: [if (j['acceptes'] is List) for (final a in j['acceptes'] as List) '$a'],
      tentatives: _int(j['tentatives']),
      createdAt: created,
      updatedAt: DateTime.tryParse('${j['updatedAt']}') ?? created,
      envoyeeAt: DateTime.tryParse('${j['envoyeeAt']}'),
      userId: '${j['userId'] ?? ''}',
      userName: '${j['userName'] ?? ''}',
    );
  }
}

/// File des ventes hors ligne sur l'appareil.
/// Anomalie de synchronisation (rapport persistant) : refus du serveur ou écart à l'envoi.
class AnomalieHL {
  final String id;
  final DateTime date;
  final String venteLocaleId;
  final int numero;
  final TypeVenteHL type;
  final String client;

  /// N° de bon(s) concerné(s) (assurance / carnet).
  final String bons;
  final String motif;

  /// Nature : bon, plafond, stock, prix, caisse, produit, net, creation, autre.
  final String nature;
  final bool traitee;

  const AnomalieHL({
    required this.id,
    required this.date,
    required this.venteLocaleId,
    required this.numero,
    required this.type,
    this.client = '',
    this.bons = '',
    required this.motif,
    this.nature = 'autre',
    this.traitee = false,
  });

  String get numeroLabel => numeroHL(numero);

  String get natureLabel => switch (nature) {
        'bon' => 'Bon déjà utilisé / refusé',
        'plafond' => 'Plafond',
        'stock' => 'Stock',
        'prix' => 'Prix modifié',
        'caisse' => 'Caisse fermée',
        'produit' => 'Produit introuvable',
        'net' => 'Net ≠ encaissé',
        'creation' => 'Création non confirmée',
        _ => 'Refus du serveur',
      };

  /// Nature d'après le motif.
  static String natureDe(String motif) {
    final m = motif.toLowerCase();
    if (m.contains('déjà utilisé') || m.contains('deja utilise')) return 'bon';
    if (m.contains('plafond')) return 'plafond';
    if (m.contains('caisse')) return 'caisse';
    if (m.contains('prix modifié')) return 'prix';
    if (m.contains('stock')) return 'stock';
    if (m.contains('introuvable')) return 'produit';
    if (m.contains('net du serveur')) return 'net';
    if (m.contains('création')) return 'creation';
    if (RegExp(r'\bbons?\b').hasMatch(m)) return 'bon';
    return 'autre';
  }

  AnomalieHL copyWith({bool? traitee}) => AnomalieHL(
        id: id,
        date: date,
        venteLocaleId: venteLocaleId,
        numero: numero,
        type: type,
        client: client,
        bons: bons,
        motif: motif,
        nature: nature,
        traitee: traitee ?? this.traitee,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'venteLocaleId': venteLocaleId,
        'numero': numero,
        'type': type.name,
        'client': client,
        'bons': bons,
        'motif': motif,
        'nature': nature,
        'traitee': traitee,
      };

  static AnomalieHL fromJson(Map<String, dynamic> j) => AnomalieHL(
        id: '${j['id']}',
        date: DateTime.tryParse('${j['date']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        venteLocaleId: '${j['venteLocaleId'] ?? ''}',
        numero: _int(j['numero']),
        type: _enum(TypeVenteHL.values, j['type'], TypeVenteHL.comptant),
        client: '${j['client'] ?? ''}',
        bons: '${j['bons'] ?? ''}',
        motif: '${j['motif'] ?? ''}',
        nature: '${j['nature'] ?? 'autre'}',
        traitee: j['traitee'] == true,
      );
}

abstract class VentesHLStore {
  /// Rapport d'anomalies (ordre chronologique).
  Future<List<AnomalieHL>> anomalies();
  Future<void> putAnomalie(AnomalieHL a);

  /// Toutes les ventes, dans l'ordre de saisie (numéro croissant).
  Future<List<VenteHorsLigne>> all();

  /// Ajoute ou remplace (écriture immédiate).
  Future<void> put(VenteHorsLigne v);
  Future<void> remove(String id);

  /// Numéro HL suivant (compteur persisté, jamais réutilisé).
  Future<int> nextNumero();
}

class MemoryVentesHLStore implements VentesHLStore {
  final Map<String, String> _rows = {};
  int _compteur = 0;

  /// Fait échouer la prochaine écriture (tests).
  bool failNextWrite = false;

  @override
  Future<List<VenteHorsLigne>> all() async =>
      [for (final r in _rows.values) VenteHorsLigne.fromJson(Map<String, dynamic>.from(jsonDecode(r) as Map))]..sort((a, b) => a.numero.compareTo(b.numero));

  @override
  Future<void> put(VenteHorsLigne v) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('écriture refusée');
    }
    _rows[v.id] = jsonEncode(v.toJson());
  }

  @override
  Future<void> remove(String id) async => _rows.remove(id);

  @override
  Future<int> nextNumero() async => ++_compteur;

  final Map<String, String> _anomalies = {};

  @override
  Future<List<AnomalieHL>> anomalies() async =>
      [for (final r in _anomalies.values) AnomalieHL.fromJson(Map<String, dynamic>.from(jsonDecode(r) as Map))]..sort((a, b) => a.date.compareTo(b.date));

  @override
  Future<void> putAnomalie(AnomalieHL a) async => _anomalies[a.id] = jsonEncode(a.toJson());
}

/// SQLite : fichier prestige_ventes_hl.db (séparé du catalogue : vider le catalogue ne touche pas aux ventes).
class SqfliteVentesHLStore implements VentesHLStore {
  final DatabaseFactory? _factory;
  final String? _path;
  SqfliteVentesHLStore({DatabaseFactory? factory, String? path})
      : _factory = factory,
        _path = path;

  Future<Database>? _db;
  Future<Database> get _database => _db ??= _open();

  Future<Database> _open() async {
    final f = _factory ?? databaseFactory;
    final path = _path ?? p.join(await f.getDatabasesPath(), 'prestige_ventes_hl.db');
    return f.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('CREATE TABLE ventes (id TEXT PRIMARY KEY, numero INTEGER, statut TEXT, maj TEXT, json TEXT)');
            await db.execute('CREATE TABLE meta (cle TEXT PRIMARY KEY, valeur TEXT)');
            await db.execute('CREATE TABLE anomalies (id TEXT PRIMARY KEY, date TEXT, json TEXT)');
          },
        ));
  }

  /// Ferme la base (tests : simule un redémarrage).
  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) await (await db).close();
  }

  @override
  Future<List<VenteHorsLigne>> all() async {
    final db = await _database;
    final rows = await db.query('ventes', columns: ['json'], orderBy: 'numero');
    return [for (final r in rows) VenteHorsLigne.fromJson(Map<String, dynamic>.from(jsonDecode('${r['json']}') as Map))];
  }

  @override
  Future<void> put(VenteHorsLigne v) async {
    final db = await _database;
    await db.insert('ventes', {'id': v.id, 'numero': v.numero, 'statut': v.statut.name, 'maj': v.updatedAt.toIso8601String(), 'json': jsonEncode(v.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> remove(String id) async {
    final db = await _database;
    await db.delete('ventes', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<AnomalieHL>> anomalies() async {
    final db = await _database;
    final rows = await db.query('anomalies', columns: ['json'], orderBy: 'date');
    return [for (final r in rows) AnomalieHL.fromJson(Map<String, dynamic>.from(jsonDecode('${r['json']}') as Map))];
  }

  @override
  Future<void> putAnomalie(AnomalieHL a) async {
    final db = await _database;
    await db.insert('anomalies', {'id': a.id, 'date': a.date.toIso8601String(), 'json': jsonEncode(a.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<int> nextNumero() async {
    final db = await _database;
    return db.transaction((txn) async {
      final rows = await txn.query('meta', where: 'cle = ?', whereArgs: ['compteur']);
      final n = (rows.isEmpty ? 0 : int.tryParse('${rows.first['valeur']}') ?? 0) + 1;
      await txn.insert('meta', {'cle': 'compteur', 'valeur': '$n'}, conflictAlgorithm: ConflictAlgorithm.replace);
      return n;
    });
  }
}
