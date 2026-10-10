// lib/horsligne/stock/stock_models.dart
// Hors ligne (étape H3) — stock : données de référence gardées sur le téléphone, opérations saisies
// hors ligne (file persistante) et anomalies (refus du serveur à l'envoi).
//
// Le modèle [Anomalie] est GÉNÉRIQUE ({date, type, référence, motif, état traité / non traité}) :
// il sert aussi aux autres modules (ventes H2…) pour un rapport d'anomalies commun.
import 'dart:convert';
import 'dart:math';

import 'package:intl/intl.dart';

// ---------------------------------------------------------------------------
// Copie locale (référence)
// ---------------------------------------------------------------------------

/// Catégories de la copie « stock » (téléchargée avec le catalogue, mêmes déclencheurs).
enum StockRef {
  blsAEntrer,
  blsClotures,
  lignesBl,
  controleReception,
  commandes,
  lignesCommandes,
  grossistes,
  motifsRetour,
  rayons,
  perimesEnCours,
}

extension StockRefInfo on StockRef {
  String get label => switch (this) {
        StockRef.blsAEntrer => 'BL à entrer en stock',
        StockRef.blsClotures => 'BL entrés en stock (3 j)',
        StockRef.lignesBl => 'Lignes de BL',
        StockRef.controleReception => 'Contrôle réception (3 j)',
        StockRef.commandes => 'Commandes en cours / passées',
        StockRef.lignesCommandes => 'Lignes de commandes',
        StockRef.grossistes => 'Grossistes',
        StockRef.motifsRetour => 'Motifs de retour',
        StockRef.rayons => 'Emplacements (rayons)',
        StockRef.perimesEnCours => 'Périmés en cours de saisie',
      };

  /// Clé d'identification d'une ligne du serveur.
  String idOf(Map<String, dynamic> r) => switch (this) {
        StockRef.blsAEntrer || StockRef.blsClotures => '${r['lg_BON_LIVRAISON_ID'] ?? ''}',
        StockRef.lignesBl => '${r['lg_BON_LIVRAISON_DETAIL'] ?? ''}',
        StockRef.controleReception => '${r['lgBONLIVRAISONID'] ?? ''}',
        StockRef.commandes => '${r['lg_ORDER_ID'] ?? ''}',
        StockRef.lignesCommandes => '${r['lg_ORDERDETAIL_ID'] ?? ''}',
        StockRef.grossistes || StockRef.rayons || StockRef.perimesEnCours => '${r['id'] ?? ''}',
        StockRef.motifsRetour => '${r['lgMOTIFRETOUR'] ?? ''}',
      };
}

/// Nombre d'éléments et date par catégorie.
class StockRefStats {
  final Map<StockRef, int> counts;
  final Map<StockRef, DateTime> lastSync;
  const StockRefStats({this.counts = const {}, this.lastSync = const {}});
  int count(StockRef c) => counts[c] ?? 0;

  /// Date de la copie (la plus ancienne des catégories ; null si jamais téléchargée).
  DateTime? get at => lastSync.isEmpty ? null : lastSync.values.reduce((a, b) => a.isBefore(b) ? a : b);
}

/// Copie locale absente ou action impossible hors ligne : message clair (jamais d'erreur réseau brute).
class StockHorsLigneException implements Exception {
  final String message;
  const StockHorsLigneException(this.message);
  @override
  String toString() => message;
}

/// Message des actions qui ne peuvent pas se faire hors ligne.
const String kEnLigneUniquement = 'Disponible en ligne uniquement';

// ---------------------------------------------------------------------------
// Opérations hors ligne
// ---------------------------------------------------------------------------

enum StockOpType { reception, pointageBl, pointageCommande, peremption, perime, retour, emplacement }

extension StockOpTypeInfo on StockOpType {
  String get label => switch (this) {
        StockOpType.reception => 'Réception BL (lots)',
        StockOpType.pointageBl => 'Pointage BL',
        StockOpType.pointageCommande => 'Contrôle commande',
        StockOpType.peremption => 'Dates de péremption',
        StockOpType.perime => 'Saisie de périmés',
        StockOpType.retour => 'Retour fournisseur',
        StockOpType.emplacement => 'Emplacements',
      };
}

/// En attente / envoyée / non envoyée car ressaisie sur le serveur / anomalie (refus du serveur).
enum StockOpStatut { enAttente, envoyee, ressaisie, anomalie }

extension StockOpStatutInfo on StockOpStatut {
  String get label => switch (this) {
        StockOpStatut.enAttente => 'En attente',
        StockOpStatut.envoyee => 'Envoyée',
        StockOpStatut.ressaisie => 'Non envoyée — ressaisie sur le serveur',
        StockOpStatut.anomalie => 'Anomalie',
      };
}

/// État d'une ligne : [sending] = envoi commencé sans réponse connue (on vérifie sur le serveur
/// avant de renvoyer : idempotence).
enum StockLineEtat { pending, sending, applied, dejaApplique, rejected, ignored }

class StockOpLine {
  final String key;

  /// Libellé lisible (produit…).
  final String label;
  final Map<String, dynamic> data;
  StockLineEtat etat;
  String? motif;

  /// Valeur relevée sur le serveur juste avant l'envoi (détection « déjà appliqué »).
  int? avant;

  StockOpLine({required this.key, required this.label, required this.data, this.etat = StockLineEtat.pending, this.motif, this.avant});

  bool get done => etat == StockLineEtat.applied || etat == StockLineEtat.dejaApplique || etat == StockLineEtat.ignored;

  Map<String, dynamic> toJson() => {'key': key, 'label': label, 'data': data, 'etat': etat.name, 'motif': motif, 'avant': avant};

  factory StockOpLine.fromJson(Map<String, dynamic> j) => StockOpLine(
        key: '${j['key']}',
        label: '${j['label'] ?? ''}',
        data: Map<String, dynamic>.from(j['data'] as Map? ?? const {}),
        etat: StockLineEtat.values.firstWhere((e) => e.name == j['etat'], orElse: () => StockLineEtat.pending),
        motif: j['motif'] as String?,
        avant: (j['avant'] as num?)?.toInt(),
      );
}

/// Opération saisie hors ligne. [id] = clé d'opération (unique, idempotence).
class StockOp {
  final String id;
  final StockOpType type;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Identifiant serveur de l'objet visé (BL, commande…) et libellés (n° BL, grossiste).
  final String refId;
  final String reference;
  final String grossiste;

  /// Données propres à l'opération (ex. n° BL, commentaire du retour, id du retour créé).
  final Map<String, dynamic> meta;
  final List<StockOpLine> lines;
  StockOpStatut statut;
  String? motif;
  DateTime? sentAt;

  StockOp({
    required this.id,
    required this.type,
    required this.createdAt,
    DateTime? updatedAt,
    required this.refId,
    this.reference = '',
    this.grossiste = '',
    Map<String, dynamic>? meta,
    List<StockOpLine>? lines,
    this.statut = StockOpStatut.enAttente,
    this.motif,
    this.sentAt,
  })  : updatedAt = updatedAt ?? createdAt,
        meta = meta ?? {},
        lines = lines ?? [];

  bool get pending => statut == StockOpStatut.enAttente;

  /// Lignes à envoyer (ni envoyées ni refusées).
  List<StockOpLine> get toSend => lines.where((l) => !l.done && l.etat != StockLineEtat.rejected).toList();

  /// « BL 0308… · DPCI ».
  String get titre => [if (reference.isNotEmpty) reference, if (grossiste.isNotEmpty) grossiste].join(' · ');

  static final _rnd = Random();

  /// Clé d'opération : « HL3-yyyyMMddHHmmss-xxxx ».
  static String newId(DateTime at) =>
      'HL3-${DateFormat('yyyyMMddHHmmss').format(at)}-${_rnd.nextInt(1 << 20).toRadixString(36).padLeft(4, '0')}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'refId': refId,
        'reference': reference,
        'grossiste': grossiste,
        'meta': meta,
        'lines': [for (final l in lines) l.toJson()],
        'statut': statut.name,
        'motif': motif,
        'sentAt': sentAt?.toIso8601String(),
      };

  factory StockOp.fromJson(Map<String, dynamic> j) => StockOp(
        id: '${j['id']}',
        type: StockOpType.values.firstWhere((e) => e.name == j['type']),
        createdAt: DateTime.parse('${j['createdAt']}'),
        updatedAt: DateTime.tryParse('${j['updatedAt']}'),
        refId: '${j['refId'] ?? ''}',
        reference: '${j['reference'] ?? ''}',
        grossiste: '${j['grossiste'] ?? ''}',
        meta: Map<String, dynamic>.from(j['meta'] as Map? ?? const {}),
        lines: [for (final l in (j['lines'] as List? ?? const [])) StockOpLine.fromJson(Map<String, dynamic>.from(l as Map))],
        statut: StockOpStatut.values.firstWhere((e) => e.name == j['statut'], orElse: () => StockOpStatut.enAttente),
        motif: j['motif'] as String?,
        sentAt: DateTime.tryParse('${j['sentAt'] ?? ''}'),
      );

  String encode() => jsonEncode(toJson());
  static StockOp decode(String s) => StockOp.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
}

// ---------------------------------------------------------------------------
// Anomalies (modèle générique, commun aux modules hors ligne)
// ---------------------------------------------------------------------------

/// Anomalie d'envoi : {date, type, référence, motif, état traité / non traité}.
/// [source] : module d'origine ('stock', 'ventes'…) ; [operationId] : clé de l'opération concernée.
class Anomalie {
  final String id;
  final String source;
  final DateTime date;
  final String type;
  final String reference;
  final String motif;
  bool traitee;
  final String? operationId;

  /// Détail (lignes refusées…), affiché et imprimé sous le motif.
  final List<String> details;

  Anomalie({
    required this.id,
    required this.source,
    required this.date,
    required this.type,
    required this.reference,
    required this.motif,
    this.traitee = false,
    this.operationId,
    this.details = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source,
        'date': date.toIso8601String(),
        'type': type,
        'reference': reference,
        'motif': motif,
        'traitee': traitee,
        'operationId': operationId,
        'details': details,
      };

  factory Anomalie.fromJson(Map<String, dynamic> j) => Anomalie(
        id: '${j['id']}',
        source: '${j['source'] ?? ''}',
        date: DateTime.parse('${j['date']}'),
        type: '${j['type'] ?? ''}',
        reference: '${j['reference'] ?? ''}',
        motif: '${j['motif'] ?? ''}',
        traitee: j['traitee'] == true,
        operationId: j['operationId'] as String?,
        details: [for (final d in (j['details'] as List? ?? const [])) '$d'],
      );
}

/// Source d'anomalies (stock H3, ventes H2…) : un écran commun peut fusionner plusieurs sources.
abstract class AnomalieSource {
  /// Toutes les anomalies (les plus récentes d'abord).
  Future<List<Anomalie>> anomalies();

  /// Marque traitée / non traitée.
  Future<void> setTraitee(String id, bool traitee);
}

/// Lignes du rapport d'anomalies (ticket [cols] colonnes, PDF, partage) — même présentation que les ventes.
List<String> lignesAnomaliesGeneriques(List<Anomalie> list, {int cols = 32}) {
  final f = DateFormat('dd/MM HH:mm');
  String coupe(String s) => s.length <= cols ? s : s.substring(0, cols);
  final out = <String>['${list.length} anomalie(s) · ${list.where((a) => !a.traitee).length} non traitée(s)', ''];
  for (final a in list) {
    out.add('${f.format(a.date)} ${a.traitee ? '[traitée]' : '[à traiter]'}');
    out.add(coupe('  ${a.type}'));
    out.add(coupe('  ${a.reference}'));
    out.add('  ${a.motif}');
    for (final d in a.details) {
      out.add('  - $d');
    }
  }
  return out;
}
