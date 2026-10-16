// Faux serveur RH des EMPREINTES PARTAGÉES (demande 43), en mémoire, avec les règles du vrai serveur
// (EmpreinteServiceImpl, 16/10/2026) : paramètre KEY_EMPREINTES_PARTAGEES, consentement obligatoire, 1 à 10
// gabarits, X-Client-Ref (même référence = même réponse), lecture incrémentale « depuis » (création ≥ depuis),
// suppressions signalées, employés inactifs purgés. Gabarits FACTICES (octets générés), jamais réels.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:prestige_vente_app/rh/rh_api.dart';

/// Gabarit factice (aucune empreinte réelle) : [n] octets pseudo-aléatoires reproductibles.
Uint8List gabaritFactice(int graine, [int n = 480]) {
  final r = Random(graine);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

class _Modele {
  final String id, employeId, format, modele;
  final int cree;
  int? supprime;
  _Modele(this.id, this.employeId, this.format, this.modele, this.cree);
}

class FauxServeurEmpreintes implements RhServeur, RhEmpreintes {
  /// KEY_EMPREINTES_PARTAGEES = 1.
  bool actif = true;

  /// Serveur sans les routes (version plus ancienne) : 404.
  bool sansRoutes = false;

  /// Réseau coupé : chaque appel lève RhHorsLigne.
  bool coupe = false;

  /// Coupure APRÈS traitement côté serveur du prochain POST (réponse perdue).
  bool perdreReponseEnvoi = false;

  /// Droit RH refusé.
  bool refus = false;

  final Set<String> employesActifs = {};
  final List<_Modele> _modeles = [];
  final Map<String, Map<String, dynamic>> _refs = {};
  int _horloge = 1000; // secondes fictives
  int _n = 0;

  /// Appels reçus (méthode + chemin), pour les tests.
  final appels = <String>[];
  final journalServeur = <String>[];

  static String iso(int s) => DateTime.utc(2026, 10, 16, 8).add(Duration(seconds: s)).toIso8601String().substring(0, 19);
  static int? _lire(String? s) => s == null ? null : DateTime.tryParse('${s}Z')?.difference(DateTime.utc(2026, 10, 16, 8)).inSeconds;

  int get nombreModeles => _modeles.where((m) => m.supprime == null).length;
  List<String> modelesDe(String employeId) => [for (final m in _modeles) if (m.employeId == employeId && m.supprime == null) m.modele];

  void _avancer() => _horloge += 1;

  ReponseRh _desactive() =>
      (status: 200, body: {'success': false, 'code': 'DESACTIVE', 'msg': 'Empreintes partagées désactivées (paramètre KEY_EMPREINTES_PARTAGEES).'});

  void _purger() {
    for (final m in _modeles) {
      if (m.supprime == null && !employesActifs.contains(m.employeId)) m.supprime = _horloge;
    }
  }

  void _controle(String appel) {
    appels.add(appel);
    if (coupe) throw const RhHorsLigne();
  }

  @override
  Future<ReponseRh> get(String chemin, [Map<String, dynamic> query = const {}]) async {
    _controle('GET $chemin');
    if (chemin == '/rh/droits') return (status: 200, body: {'success': !refus, 'valider': true, if (refus) 'message': 'Accès refusé.'});
    if (chemin == '/rh/employes') {
      return (
        status: 200,
        body: {
          'success': true,
          'data': [for (final id in employesActifs) {'id': id, 'matricule': 'M-$id', 'badge': 'B-$id', 'nom': 'TEST', 'prenoms': id, 'statut': 'ACTIF'}]
        }
      );
    }
    if (chemin != '/rh/empreintes') return (status: 404, body: null);
    if (sansRoutes) return (status: 404, body: null);
    if (refus) return (status: 200, body: {'success': false, 'message': 'Vous n\'avez pas accès aux ressources humaines.'});
    if (!actif) return _desactive();
    final format = '${query['format'] ?? ''}';
    final depuis = _lire(query['depuis'] as String?) ?? 0;
    _purger();
    final horodatage = iso(_horloge);
    final r = {
      'success': true,
      'horodatage': horodatage,
      'modeles': [
        for (final m in _modeles)
          if (m.supprime == null && m.format == format && m.cree >= depuis && employesActifs.contains(m.employeId))
            {'id': m.id, 'employeId': m.employeId, 'format': m.format, 'capteur': 'A400', 'modele': m.modele, 'dtCreation': iso(m.cree)}
      ],
      'suppressions': [
        for (final m in _modeles)
          if (m.supprime != null && m.supprime! >= depuis && m.format == format) {'id': m.id, 'employeId': m.employeId, 'dtSuppression': iso(m.supprime!)}
      ],
    };
    journalServeur.add('LIRE ${(r['modeles'] as List).length}');
    _avancer();
    return (status: 200, body: r);
  }

  @override
  Future<ReponseRh> post(String chemin, Map<String, dynamic> corps) async {
    _controle('POST $chemin');
    return (status: 404, body: null);
  }

  @override
  Future<ReponseRh> envoyerEmpreintes(String employeId, Map<String, dynamic> corps, String clientRef) async {
    _controle('POST /rh/employes/$employeId/empreintes');
    if (sansRoutes) return (status: 404, body: null);
    if (refus) return (status: 200, body: {'success': false, 'message': 'Vous n\'avez pas accès aux ressources humaines.'});
    if (clientRef.isNotEmpty && _refs.containsKey(clientRef)) return (status: 200, body: _refs[clientRef]);
    if (!actif) return _desactive();
    _purger();
    if (!employesActifs.contains(employeId)) return (status: 200, body: {'success': false, 'code': 'EMPLOYE', 'msg': 'Employé introuvable ou inactif.'});
    final c = corps['consentement'];
    if (c is! Map || '${c['le'] ?? ''}'.length < 19 || '${c['par'] ?? ''}'.trim().isEmpty) {
      return (status: 200, body: {'success': false, 'code': 'CONSENTEMENT', 'msg': 'Consentement écrit obligatoire : date (le) et personne (par).'});
    }
    final modeles = corps['modeles'];
    if (modeles is! List || modeles.isEmpty || modeles.length > 10) return (status: 200, body: {'success': false, 'code': 'MODELES', 'msg': 'Entre 1 et 10 gabarits par envoi.'});
    final ids = <String>[];
    for (final m in modeles) {
      base64Decode('$m'); // illisible → exception, comme un refus du serveur
      final id = 'EMP-${++_n}';
      _modeles.add(_Modele(id, employeId, '${corps['format']}', '$m', _horloge));
      ids.add(id);
    }
    final r = {'success': true, 'nombre': ids.length, 'ids': ids};
    if (clientRef.isNotEmpty) _refs[clientRef] = r;
    journalServeur.add('ENROLER $employeId ${ids.length}');
    _avancer();
    if (perdreReponseEnvoi) {
      perdreReponseEnvoi = false;
      throw const RhHorsLigne(); // enregistré, mais la réponse n'arrive jamais
    }
    return (status: 200, body: r);
  }

  @override
  Future<ReponseRh> supprimerEmpreintes(String employeId) async {
    _controle('DELETE /rh/employes/$employeId/empreintes');
    if (sansRoutes) return (status: 404, body: null);
    var n = 0;
    for (final m in _modeles) {
      if (m.employeId == employeId && m.supprime == null) {
        m.supprime = _horloge;
        n++;
      }
    }
    journalServeur.add('SUPPRIMER $employeId $n');
    _avancer();
    return (status: 200, body: {'success': true, 'nombre': n});
  }
}
