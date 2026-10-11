// lib/ordonnances/o4/apprentissage_o4.dart
// Étape O4 : apprentissage par correction. Quand le pharmacien valide (ou corrige) le produit d'une ligne
// d'ordonnance, l'appli retient « segment médicament lu → produit » (lgFAMILLEID, CIP, nom) avec un compteur de
// confirmations, de contradictions et la date. Ces associations passent en priorité dans la correspondance O3 :
//  - segment lu identique ou presque (ressemblance ≥ [ApprentissagesO4.ressemblanceMin]) → proposition en tête ;
//  - 1 confirmation : proposée mais « à vérifier » ; à partir de [ApprentissagesO4.confirmationsSures] (2) : « sûre » ;
//  - choisir un autre produit pour le même segment CONTREDIT l'association : poids = confirmations − 2 ×
//    contradictions ; à 0 ou moins elle perd sa priorité (elle reste listée, « inactive »).
// Rien d'autre que le segment (voir segment_medicament.dart) n'est gardé : jamais le texte lu complet.
// Stockage : préférences de l'appareil (JSON), 3 000 associations au plus. Version mémoire pour le banc simulé.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/ordonnances/o3/correspondance_o3.dart';
import 'package:prestige_vente_app/ordonnances/o3/similarite.dart';
import 'package:prestige_vente_app/ordonnances/o4/segment_medicament.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// « segment lu → produit » appris.
class AssociationApprise {
  final String segment;
  final String produitId;
  String cip;
  String nom;
  int confirmations;
  int contradictions;
  DateTime maj;

  AssociationApprise({
    required this.segment,
    required this.produitId,
    this.cip = '',
    this.nom = '',
    this.confirmations = 0,
    this.contradictions = 0,
    required this.maj,
  });

  /// Poids : confirmations − 2 × contradictions.
  int get poids => confirmations - 2 * contradictions;

  /// Prioritaire dans la correspondance.
  bool get active => poids >= 1;

  /// Assez confirmée pour être proposée « sûre ».
  bool get sure => poids >= ApprentissagesO4.confirmationsSures;

  Map<String, dynamic> toJson() => {
        's': segment,
        'p': produitId,
        if (cip.isNotEmpty) 'c': cip,
        if (nom.isNotEmpty) 'n': nom,
        'ok': confirmations,
        'ko': contradictions,
        'm': maj.toIso8601String(),
      };

  static AssociationApprise? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = '${j['s'] ?? ''}', p = '${j['p'] ?? ''}';
    if (s.isEmpty || p.isEmpty) return null;
    int n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    return AssociationApprise(
      segment: s,
      produitId: p,
      cip: '${j['c'] ?? ''}',
      nom: '${j['n'] ?? ''}',
      confirmations: n(j['ok']),
      contradictions: n(j['ko']),
      maj: DateTime.tryParse('${j['m'] ?? ''}') ?? DateTime(2000),
    );
  }
}

/// Proposition tirée d'un apprentissage, pour un segment lu.
class SuggestionApprise {
  final AssociationApprise association;

  /// Ressemblance du segment lu avec le segment appris (1 = identique).
  final double ressemblance;

  /// Confiance 0…1 à donner à la proposition.
  final double confiance;

  /// Proposition « sûre » (assez confirmée, segment identique ou presque).
  final bool sure;
  const SuggestionApprise(this.association, this.ressemblance, this.confiance, this.sure);
}

/// Ce que la correspondance O3 consulte (lecture seule).
abstract class SourceApprentissages {
  /// Associations actives proches du [segment], la meilleure d'abord.
  List<SuggestionApprise> chercher(String segment);

  /// Validations reçues des autres terminaux pour ce produit (bonus « produits vendus »).
  int validationsPartagees(String produitId);

  /// Confirmations des associations actives vers ce produit (bonus des propositions par fragments O3b).
  int confirmationsProduit(String produitId);
}

class ApprentissagesO4 extends ChangeNotifier implements SourceApprentissages {
  /// Confirmations nettes pour une proposition « sûre ».
  static const int confirmationsSures = 2;

  /// Ressemblance minimale entre le segment lu et le segment appris (« presque identique »).
  static const double ressemblanceMin = 0.88;

  /// Associations gardées au plus (les inactives puis les plus anciennes partent d'abord).
  static const int maximum = 3000;

  static const String cle = 'ordonnance_o4_apprentissages_v1';

  final Map<String, AssociationApprise> _parCle = {};
  final Map<String, int> _partagees = {};

  /// false : banc simulé / tests (rien n'est écrit sur l'appareil).
  final bool persistant;
  DateTime Function() horloge;

  ApprentissagesO4._(this.persistant, {DateTime Function()? horloge}) : horloge = horloge ?? DateTime.now;

  /// En mémoire seulement (banc d'essai simulé, tests).
  factory ApprentissagesO4.memoire({DateTime Function()? horloge}) => ApprentissagesO4._(false, horloge: horloge);

  static ApprentissagesO4? _instance;
  static Future<ApprentissagesO4>? _chargement;

  /// Apprentissages de l'appareil (chargés une fois).
  static Future<ApprentissagesO4> charger() {
    final i = _instance;
    if (i != null) return Future.value(i);
    return _chargement ??= () async {
      final a = ApprentissagesO4._(true);
      try {
        final raw = (await SharedPreferences.getInstance()).getString(cle);
        if (raw != null) a._lire(jsonDecode(raw));
      } catch (_) {}
      _instance = a;
      _chargement = null;
      return a;
    }();
  }

  /// Oublie l'instance chargée (tests, changement de préférences).
  @visibleForTesting
  static void reinitialiserInstance() {
    _instance = null;
    _chargement = null;
  }

  static String _k(String segment, String produitId) => '$segment\u0001$produitId';

  void _lire(Object? j) {
    if (j is! Map) return;
    for (final e in (j['a'] as List? ?? const [])) {
      final a = AssociationApprise.fromJson(e);
      if (a != null) _parCle[_k(a.segment, a.produitId)] = a;
    }
    final p = j['v'];
    if (p is Map) {
      for (final e in p.entries) {
        final n = e.value is num ? (e.value as num).toInt() : 0;
        if (n > 0) _partagees['${e.key}'] = n;
      }
    }
  }

  Future<void> _sauver() async {
    if (!persistant) return;
    try {
      await (await SharedPreferences.getInstance()).setString(
        cle,
        jsonEncode({'a': [for (final a in _parCle.values) a.toJson()], 'v': _partagees}),
      );
    } catch (_) {}
  }

  /// Toutes les associations (les plus récentes d'abord).
  List<AssociationApprise> get liste => _parCle.values.toList()..sort((a, b) => b.maj.compareTo(a.maj));

  int get nombre => _parCle.length;

  /// Recherche dans la liste (segment ou nom du produit, sans accents ni casse).
  List<AssociationApprise> rechercher(String q) {
    final t = SegmentMedicament.compact(q.toLowerCase().trim());
    if (t.isEmpty) return liste;
    return [
      for (final a in liste)
        if (SegmentMedicament.compact(a.segment).contains(t) || a.nom.toLowerCase().replaceAll(' ', '').contains(t) || a.cip.contains(t)) a,
    ];
  }

  @override
  int validationsPartagees(String produitId) => _partagees[produitId] ?? 0;

  @override
  int confirmationsProduit(String produitId) =>
      _parCle.values.where((a) => a.produitId == produitId && a.active).fold(0, (s, a) => s + a.confirmations);

  /// Ressemblance de deux segments (forme compacte), 0 si trop différents.
  static double ressemblance(String a, String b) {
    if (a == b) return 1;
    final x = SegmentMedicament.compact(a), y = SegmentMedicament.compact(b);
    if (x == y) return 1;
    if ((x.length - y.length).abs() > math.max(2, x.length ~/ 5)) return 0;
    return Similarite.ressemblance(x, y);
  }

  @override
  List<SuggestionApprise> chercher(String segment) {
    final out = <SuggestionApprise>[];
    for (final a in _parCle.values) {
      if (!a.active) continue;
      final r = ressemblance(segment, a.segment);
      if (r < ressemblanceMin) continue;
      final sure = a.sure && r >= 0.95;
      final base = a.sure ? 0.92 : 0.75;
      out.add(SuggestionApprise(a, r, (base - (1 - r)).clamp(0.0, 1.0), sure));
    }
    out.sort((x, y) {
      var c = y.confiance.compareTo(x.confiance);
      if (c != 0) return c;
      c = y.association.poids.compareTo(x.association.poids);
      return c != 0 ? c : y.association.maj.compareTo(x.association.maj);
    });
    return out;
  }

  /// Le pharmacien a validé [produitId] pour la ligne dont le segment est [segment] :
  /// confirmation de cette association, contradiction des associations du même segment vers un autre produit.
  /// [partagee] : validation reçue d'un autre terminal (compte aussi pour le bonus « produits vendus »).
  Future<void> apprendre({
    required String segment,
    required String produitId,
    String cip = '',
    String nom = '',
    DateTime? at,
    bool partagee = false,
  }) async {
    final quand = at ?? horloge();
    for (final a in _parCle.values) {
      if (a.produitId != produitId && ressemblance(segment, a.segment) >= ressemblanceMin) {
        a.contradictions++;
        if (quand.isAfter(a.maj)) a.maj = quand;
      }
    }
    final k = _k(segment, produitId);
    final a = _parCle[k] ??= AssociationApprise(segment: segment, produitId: produitId, maj: quand);
    a.confirmations++;
    if (cip.isNotEmpty) a.cip = cip;
    if (nom.isNotEmpty) a.nom = nom;
    if (quand.isAfter(a.maj)) a.maj = quand;
    if (partagee) _partagees[produitId] = (_partagees[produitId] ?? 0) + 1;
    _borner();
    notifyListeners();
    await _sauver();
  }

  void _borner() {
    if (_parCle.length <= maximum) return;
    final tri = _parCle.entries.toList()
      ..sort((x, y) {
        final c = (x.value.active ? 1 : 0).compareTo(y.value.active ? 1 : 0);
        return c != 0 ? c : x.value.maj.compareTo(y.value.maj);
      });
    for (final e in tri.take(_parCle.length - maximum)) {
      _parCle.remove(e.key);
    }
  }

  /// Oublie une association (écran de gestion).
  Future<void> oublier(AssociationApprise a) async {
    _parCle.remove(_k(a.segment, a.produitId));
    notifyListeners();
    await _sauver();
  }

  /// Oublie tout (associations et validations reçues).
  Future<void> reinitialiser() async {
    _parCle.clear();
    _partagees.clear();
    notifyListeners();
    await _sauver();
  }
}

/// Bonus « produits vendus » d'O3 nourri par les validations : compteur de l'appareil + validations reçues des
/// autres terminaux (partage O4).
class PopulariteAvecApprentissages implements PopulariteProduits {
  final PopulariteProduits base;
  final SourceApprentissages apprentissages;
  const PopulariteAvecApprentissages(this.base, this.apprentissages);

  @override
  int ventes(String produitId) => base.ventes(produitId) + apprentissages.validationsPartagees(produitId);
}
