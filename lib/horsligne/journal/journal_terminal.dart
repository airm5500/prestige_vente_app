// lib/horsligne/journal/journal_terminal.dart
// Journal des actions du terminal (traçabilité) : chaque action ayant un effet sur le STOCK ou la
// CAISSE, en ligne comme hors ligne, est ajoutée à un journal local APPEND-ONLY (jamais modifié,
// seulement purgé au-delà de la durée de conservation, 90 jours par défaut, réglable).
// Chaque entrée : horodatage, utilisateur, terminal, type, action, référence locale (HL…) et serveur,
// montant / modes, quantités par produit, résultat (ok / refus + motif / échec réseau / déjà appliqué).
// Aucune donnée sensible : ni mot de passe, ni jeton, ni cookie (seuls des champs choisis sont gardés).
//
// Branchement par points uniques : intercepteur Dio des routes d'écriture (journal_interceptor.dart)
// et appels explicites des files hors ligne (ventes H2, stock H3, panier hors ligne).
// SQLite : table `journal` ajoutée au fichier du catalogue par la migration nommée « journal_terminal_v1 »
// (« Vider la copie locale » n'y touche pas) ; implémentation mémoire pour les tests.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

enum TypeJournal { vente, encaissement, prevente, venteHL, stock, caisse, confirmation, connexion, reseau, ordonnance }

extension TypeJournalInfo on TypeJournal {
  String get label => switch (this) {
        TypeJournal.vente => 'Vente (lignes)',
        TypeJournal.encaissement => 'Encaissement',
        TypeJournal.prevente => 'Prévente',
        TypeJournal.venteHL => 'Vente hors ligne',
        TypeJournal.stock => 'Stock',
        TypeJournal.caisse => 'Caisse',
        TypeJournal.confirmation => 'Confirmation d\'envoi',
        TypeJournal.connexion => 'Connexion',
        TypeJournal.reseau => 'En ligne / hors ligne',
        TypeJournal.ordonnance => 'Apprentissage ordonnances',
      };
}

enum ResultatJournal { ok, refus, echecReseau, dejaApplique, info, doublonBloque }

extension ResultatJournalInfo on ResultatJournal {
  String get label => switch (this) {
        ResultatJournal.ok => 'OK',
        ResultatJournal.refus => 'Refusé',
        ResultatJournal.echecReseau => 'Échec réseau',
        ResultatJournal.dejaApplique => 'Déjà appliqué',
        ResultatJournal.info => 'Info',
        ResultatJournal.doublonBloque => 'Doublon bloqué',
      };
}

/// Source de l'action : saisie en ligne, saisie hors ligne, ou envoi d'une file hors ligne.
abstract final class SourceJournal {
  static const enLigne = 'en ligne';
  static const horsLigne = 'hors ligne';

  /// Requête envoyée par la file des ventes hors ligne (l'encaissement a déjà été compté à la saisie).
  static const fileHL = 'envoi file HL';
}

/// Quantité d'un produit dans une entrée. [remplace] : la quantité REMPLACE la précédente de la même
/// clé (modification de ligne, pointage) au lieu de s'y ajouter.
class JournalProduit {
  final String id;
  final String nom;
  final int qte;
  final bool remplace;
  const JournalProduit({required this.id, this.nom = '', required this.qte, this.remplace = false});

  Map<String, dynamic> toJson() => {'id': id, 'nom': nom, 'qte': qte, if (remplace) 'r': true};
  static JournalProduit fromJson(Map<String, dynamic> j) =>
      JournalProduit(id: '${j['id'] ?? ''}', nom: '${j['nom'] ?? ''}', qte: _int(j['qte']), remplace: j['r'] == true);
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

class JournalEntree {
  final int? id;
  final DateTime at;
  final String utilisateur;
  final String terminal;
  final TypeJournal type;
  final String action;
  final String refLocale;
  final String refServeur;
  final int? montant;

  /// Montant encaissé par mode de règlement.
  final Map<String, int> modes;
  final List<JournalProduit> produits;
  final ResultatJournal resultat;
  final String motif;
  final String source;

  const JournalEntree({
    this.id,
    required this.at,
    this.utilisateur = '',
    this.terminal = '',
    required this.type,
    required this.action,
    this.refLocale = '',
    this.refServeur = '',
    this.montant,
    this.modes = const {},
    this.produits = const [],
    this.resultat = ResultatJournal.ok,
    this.motif = '',
    this.source = SourceJournal.enLigne,
  });

  /// Quantité totale (somme des produits).
  int get quantite => produits.fold(0, (s, p) => s + p.qte);

  JournalEntree avecId(int id) => JournalEntree(
        id: id,
        at: at,
        utilisateur: utilisateur,
        terminal: terminal,
        type: type,
        action: action,
        refLocale: refLocale,
        refServeur: refServeur,
        montant: montant,
        modes: modes,
        produits: produits,
        resultat: resultat,
        motif: motif,
        source: source,
      );

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'utilisateur': utilisateur,
        'terminal': terminal,
        'type': type.name,
        'action': action,
        'refLocale': refLocale,
        'refServeur': refServeur,
        'montant': montant,
        'modes': modes,
        'produits': [for (final p in produits) p.toJson()],
        'resultat': resultat.name,
        'motif': motif,
        'source': source,
      };

  static JournalEntree fromJson(Map<String, dynamic> j, {int? id}) => JournalEntree(
        id: id,
        at: DateTime.tryParse('${j['at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        utilisateur: '${j['utilisateur'] ?? ''}',
        terminal: '${j['terminal'] ?? ''}',
        type: TypeJournal.values.where((t) => t.name == j['type']).firstOrNull ?? TypeJournal.vente,
        action: '${j['action'] ?? ''}',
        refLocale: '${j['refLocale'] ?? ''}',
        refServeur: '${j['refServeur'] ?? ''}',
        montant: j['montant'] == null ? null : _int(j['montant']),
        modes: {if (j['modes'] is Map) for (final e in (j['modes'] as Map).entries) '${e.key}': _int(e.value)},
        produits: [
          if (j['produits'] is List)
            for (final p in j['produits'] as List)
              if (p is Map) JournalProduit.fromJson(Map<String, dynamic>.from(p)),
        ],
        resultat: ResultatJournal.values.where((r) => r.name == j['resultat']).firstOrNull ?? ResultatJournal.ok,
        motif: '${j['motif'] ?? ''}',
        source: '${j['source'] ?? SourceJournal.enLigne}',
      );
}

/// Critères de lecture du journal.
class JournalFiltre {
  /// Bornes incluses (jours entiers si [au] est une date sans heure : jusqu'à 23:59:59).
  final DateTime? du;
  final DateTime? au;
  final Set<TypeJournal>? types;
  final String? utilisateur;

  /// Recherche par référence (locale ou serveur), début ou partie du texte, insensible à la casse.
  final String recherche;
  const JournalFiltre({this.du, this.au, this.types, this.utilisateur, this.recherche = ''});

  DateTime? get _fin => au == null ? null : DateTime(au!.year, au!.month, au!.day).add(const Duration(days: 1));

  bool accepte(JournalEntree e) {
    if (du != null && e.at.isBefore(DateTime(du!.year, du!.month, du!.day))) return false;
    final fin = _fin;
    if (fin != null && !e.at.isBefore(fin)) return false;
    if (types != null && !types!.contains(e.type)) return false;
    if (utilisateur != null && utilisateur!.isNotEmpty && e.utilisateur != utilisateur) return false;
    final q = recherche.trim().toUpperCase();
    if (q.isNotEmpty && !'${e.refLocale} ${e.refServeur} ${e.action}'.toUpperCase().contains(q)) return false;
    return true;
  }
}

abstract class JournalStore {
  /// Ajoute une entrée (jamais de modification) ; renvoie son numéro.
  Future<int> ajouter(JournalEntree e);

  /// Entrées dans l'ordre chronologique.
  Future<List<JournalEntree>> lire(JournalFiltre f, {int limit = 20000});

  /// Supprime les entrées antérieures à [avant] ; renvoie le nombre supprimé.
  Future<int> purger(DateTime avant);
  Future<int> compte();
}

class MemoryJournalStore implements JournalStore {
  final List<JournalEntree> _rows = [];
  int _n = 0;

  @override
  Future<int> ajouter(JournalEntree e) async {
    final id = ++_n;
    _rows.add(e.avecId(id));
    return id;
  }

  @override
  Future<List<JournalEntree>> lire(JournalFiltre f, {int limit = 20000}) async {
    final out = _rows.where(f.accepte).toList()..sort((a, b) => a.at.compareTo(b.at));
    return out.length > limit ? out.sublist(out.length - limit) : out;
  }

  @override
  Future<int> purger(DateTime avant) async {
    final n = _rows.length;
    _rows.removeWhere((e) => e.at.isBefore(avant));
    return n - _rows.length;
  }

  @override
  Future<int> compte() async => _rows.length;
}

/// SQLite : table `journal` du fichier du catalogue (migration nommée).
class SqfliteJournalStore implements JournalStore {
  final SqfliteLocalStore local;
  SqfliteJournalStore(this.local);

  static const migration = 'journal_terminal_v1';

  Future<Database> get _db => local.withMigration(migration, (txn) async {
        await txn.execute('CREATE TABLE IF NOT EXISTS journal (id INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT, type TEXT, '
            'utilisateur TEXT, refs TEXT, json TEXT)');
        await txn.execute('CREATE INDEX IF NOT EXISTS journal_at ON journal(at)');
      });

  @override
  Future<int> ajouter(JournalEntree e) async {
    final db = await _db;
    return db.insert('journal', {
      'at': e.at.toIso8601String(),
      'type': e.type.name,
      'utilisateur': e.utilisateur,
      'refs': '${e.refLocale} ${e.refServeur}'.toUpperCase(),
      'json': jsonEncode(e.toJson()),
    });
  }

  @override
  Future<List<JournalEntree>> lire(JournalFiltre f, {int limit = 20000}) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];
    if (f.du != null) {
      where.add('at >= ?');
      args.add(DateTime(f.du!.year, f.du!.month, f.du!.day).toIso8601String());
    }
    if (f._fin != null) {
      where.add('at < ?');
      args.add(f._fin!.toIso8601String());
    }
    if (f.types != null) {
      if (f.types!.isEmpty) return const [];
      where.add('type IN (${List.filled(f.types!.length, '?').join(',')})');
      args.addAll(f.types!.map((t) => t.name));
    }
    final rows = await db.query('journal',
        columns: ['id', 'json'], where: where.isEmpty ? null : where.join(' AND '), whereArgs: args, orderBy: 'at DESC, id DESC', limit: limit);
    return [
      for (final r in rows.reversed) JournalEntree.fromJson(Map<String, dynamic>.from(jsonDecode('${r['json']}') as Map), id: (r['id'] as num).toInt()),
    ].where(f.accepte).toList();
  }

  @override
  Future<int> purger(DateTime avant) async {
    final db = await _db;
    return db.delete('journal', where: 'at < ?', whereArgs: [avant.toIso8601String()]);
  }

  @override
  Future<int> compte() async {
    final db = await _db;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM journal')) ?? 0;
  }
}

/// Journal du terminal (instance de l'appli dans [instance]).
class JournalTerminal extends ChangeNotifier {
  final JournalStore store;
  final DateTime Function() _clock;
  JournalTerminal({JournalStore? store, DateTime Function()? clock})
      : store = store ?? MemoryJournalStore(),
        _clock = clock ?? DateTime.now;

  /// Instance de l'appli (mémoire par défaut ; SQLite configuré au démarrage, voir [JournalTerminal.app]).
  static JournalTerminal instance = JournalTerminal();

  /// Journal SQLite dans le fichier du catalogue (repli mémoire si ce n'est pas SQLite).
  factory JournalTerminal.app(LocalStore local) => JournalTerminal(store: local is SqfliteLocalStore ? SqfliteJournalStore(local) : MemoryJournalStore());

  /// Utilisateur connecté (nom affiché) — jamais de mot de passe.
  String utilisateur = '';

  /// Identifiant du terminal (créé une fois, gardé sur l'appareil) et nom (modèle).
  String terminalId = '';
  String terminalNom = '';

  /// Le terminal est-il hors ligne ? (branché sur la surveillance du serveur).
  bool Function() horsLigne = () => false;

  String get terminal => [if (terminalId.isNotEmpty) terminalId, if (terminalNom.isNotEmpty) terminalNom].join(' · ');

  DateTime get now => _clock();

  Future<void> _chaine = Future.value();
  int _ajouts = 0;

  /// Nombre d'entrées ajoutées depuis le démarrage (rafraîchissement des écrans).
  int get ajouts => _ajouts;

  /// Toutes les écritures en cours sont terminées (tests, export).
  Future<void> get idle => _chaine;

  /// Ajoute une entrée (ordre garanti, jamais d'exception : le journal ne bloque jamais une vente).
  Future<void> noter({
    required TypeJournal type,
    required String action,
    String refLocale = '',
    String refServeur = '',
    int? montant,
    Map<String, int> modes = const {},
    List<JournalProduit> produits = const [],
    ResultatJournal resultat = ResultatJournal.ok,
    String motif = '',
    String? source,
    String? utilisateur,
  }) {
    final e = JournalEntree(
      at: _clock(),
      utilisateur: utilisateur ?? this.utilisateur,
      terminal: terminal,
      type: type,
      action: action,
      refLocale: refLocale,
      refServeur: refServeur,
      montant: montant,
      modes: modes,
      produits: produits,
      resultat: resultat,
      motif: nettoyerMotif(motif),
      source: source ?? (_safe(horsLigne) ? SourceJournal.horsLigne : SourceJournal.enLigne),
    );
    return _chaine = _chaine.then((_) async {
      try {
        await store.ajouter(e);
        _ajouts++;
        notifyListeners();
      } catch (err) {
        debugPrint('Journal du terminal : écriture impossible ($err)');
      }
    });
  }

  static bool _safe(bool Function() f) {
    try {
      return f();
    } catch (_) {
      return false;
    }
  }

  /// Motif lisible, sans balises HTML ni donnée sensible (mot de passe, jeton), borné.
  static String nettoyerMotif(String m) {
    var t = m.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceAll(RegExp(r'(password|mot de passe|token|jeton|cookie|jsessionid)\s*[:=]\s*\S+', caseSensitive: false), r'$1=***');
    return t.length > 300 ? '${t.substring(0, 300)}…' : t;
  }

  Future<List<JournalEntree>> lire([JournalFiltre f = const JournalFiltre()]) async {
    await idle;
    try {
      return await store.lire(f);
    } catch (e) {
      throw StateError('Journal illisible : $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Conservation de l'historique (journal, ventes et opérations envoyées)
  // ---------------------------------------------------------------------------

  /// Durée de conservation (jours) : au moins 90 ; réglable (Réglages › Hors ligne).
  static int conservationJours = 90;
  static const List<int> conservationsPossibles = [90, 180, 365, 730];
  static const _prefConservation = 'hl_conservation_jours';
  static const _prefTerminal = 'hl_terminal_id';

  static Future<void> chargerReglages() async {
    try {
      final p = await SharedPreferences.getInstance();
      conservationJours = max(90, p.getInt(_prefConservation) ?? 90);
    } catch (_) {}
  }

  static Future<void> reglerConservation(int jours) async {
    conservationJours = max(90, jours);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_prefConservation, conservationJours);
    } catch (_) {}
  }

  /// Date limite : ce qui est plus ancien est purgé.
  DateTime get limiteConservation {
    final n = _clock();
    return DateTime(n.year, n.month, n.day).subtract(Duration(days: conservationJours));
  }

  /// Purge le journal au-delà de la durée de conservation.
  Future<int> purger() async {
    await idle;
    try {
      return await store.purger(limiteConservation);
    } catch (_) {
      return 0;
    }
  }

  /// Identité du terminal : identifiant créé une fois (gardé sur l'appareil) + modèle de l'appareil.
  Future<void> chargerIdentite({Future<Map<String, Object?>> Function()? materiel}) async {
    try {
      final p = await SharedPreferences.getInstance();
      var id = p.getString(_prefTerminal);
      if (id == null || id.isEmpty) {
        final r = Random();
        id = 'T-${List.generate(6, (_) => '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ'[r.nextInt(34)]).join()}';
        await p.setString(_prefTerminal, id);
      }
      terminalId = id;
    } catch (_) {
      if (terminalId.isEmpty) terminalId = 'terminal';
    }
    if (materiel == null) return;
    try {
      final hw = await materiel();
      terminalNom = '${hw['manufacturer'] ?? ''} ${hw['model'] ?? ''}'.trim();
    } catch (_) {}
  }
}

// -----------------------------------------------------------------------------
// Appels explicites des files hors ligne (une ligne à chaque point clé)
// -----------------------------------------------------------------------------

/// Vente hors ligne (H2) : création, envoi, résultat, anomalie, ressaisie…
Future<void> journalVenteHL(VenteHorsLigne v, String action,
    {ResultatJournal resultat = ResultatJournal.ok, String motif = '', bool encaissement = false, String? source}) {
  final j = JournalTerminal.instance;
  return j.noter(
    type: TypeJournal.venteHL,
    action: action,
    refLocale: v.numeroLabel,
    refServeur: v.reference ?? v.venteId ?? '',
    montant: v.netEstime,
    // Espèces encaissées à la saisie hors ligne (provisoire) : comptées UNE fois, à la création.
    modes: encaissement && v.fin == FinVenteHL.especes ? {'ESPECES (hors ligne)': v.netEstime} : const {},
    produits: encaissement ? [for (final l in v.lignes) if (!l.serveur) JournalProduit(id: l.produitId, nom: l.nom, qte: l.qte)] : const [],
    resultat: resultat,
    motif: motif,
    source: source ?? SourceJournal.horsLigne,
    utilisateur: v.userName.isNotEmpty ? v.userName : null,
  );
}

/// Opération de stock (H3) saisie hors ligne ou envoyée.
Future<void> journalStockOp(StockOp op, String action,
    {StockOpLine? ligne, ResultatJournal resultat = ResultatJournal.ok, String motif = '', String? source}) {
  JournalProduit? p(StockOpLine l) {
    final q = l.data['qty'];
    if (q is! num) return null;
    final id = '${l.data['produitId'] ?? l.data['detailId'] ?? ''}';
    final pointage = op.type == StockOpType.pointageBl || op.type == StockOpType.pointageCommande;
    return JournalProduit(id: id, nom: l.label, qte: q.toInt(), remplace: pointage);
  }

  final lignes = ligne == null ? const <StockOpLine>[] : [ligne];
  return JournalTerminal.instance.noter(
    type: TypeJournal.stock,
    action: '${op.type.label} : $action',
    refLocale: op.id,
    refServeur: [op.titre, if ('${op.meta['retourRef'] ?? ''}'.isNotEmpty) 'retour ${op.meta['retourRef']}'].where((s) => s.isNotEmpty).join(' · '),
    produits: [for (final l in lignes) if (p(l) case final x?) x],
    resultat: resultat,
    motif: motif,
    source: source ?? SourceJournal.horsLigne,
  );
}
