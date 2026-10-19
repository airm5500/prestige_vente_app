// lib/droits/droits_vente.dart
// 4.5.1 — Droits de VENTE de la session (demande du serveur du 19/10/2026 : un stagiaire au profil « Pre-vente » avait
// pu terminer une vente depuis l'application ; docs/serveur/DEMANDE_SERVEUR_DROITS_VENTE_2026-10-19.md).
//
// Lus sur GET v1/user/droits → `{success, profil, role, droits:[noms]}` après CHAQUE connexion (mot de passe, connexion
// automatique, reconnexion silencieuse, borne) et à chaque retour de l'application au premier plan. Gardés en
// MÉMOIRE seulement (jamais sur disque), oubliés à la déconnexion et au changement de compte.
//
// | Action                                                     | Droit (l'un des)                                                  |
// |------------------------------------------------------------|-------------------------------------------------------------------|
// | Terminer une vente comptant, assurance ou carnet           | P_SM_CLOTURER_CAISSE, P_SM_DEPOT_EXTENSION, P_BT_MODIFICATION_DE_VENTE |
// | Paiement mobile money avec clôture (`cloturer:true`)       | les mêmes                                                         |
// | Terminer une vente en dépôt                                | P_SM_VENTEDEPOT, P_SM_DEPOT_EXTENSION, P_SM_CLOTURER_CAISSE       |
// | Annuler une vente                                          | P_BT_ANNULER_VENTE (aucun écran de l'application n'annule une vente) |
// « Terminer la prévente » reste ouvert à tous.
//
// REPLI (serveur sans la route, 404 / 405, ou droits jamais lus) : comportement d'avant la 4.5.1, tout est affiché ;
// le serveur reste juge à chaque appel (403 `interdit` → message, vente gardée, pas de déconnexion). Lecture en échec
// (réseau) : les droits déjà lus pour CE compte sont gardés (« dernière lecture », utile hors ligne).
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/api/session_expiree.dart';

class DroitsVente extends ChangeNotifier {
  DroitsVente();

  static final DroitsVente instance = DroitsVente();

  static const terminerVenteDroits = {'P_SM_CLOTURER_CAISSE', 'P_SM_DEPOT_EXTENSION', 'P_BT_MODIFICATION_DE_VENTE'};
  static const venteDepotDroits = {'P_SM_VENTEDEPOT', 'P_SM_DEPOT_EXTENSION', 'P_SM_CLOTURER_CAISSE'};
  static const annulerVenteDroits = {'P_BT_ANNULER_VENTE'};

  /// 4.6.0 (décision 12) : scanner et saisir les lots d'un BL, créer un BL (`commande/add-lot`, `commande/creerbl`).
  static const scannerBlDroit = 'P_BL_MOBILE_SCANNER';
  static const messageScannerBl = 'Réception par scan réservée : droit « P_BL_MOBILE_SCANNER » à demander à l\'administrateur.';

  /// Message affiché à la place d'un bouton masqué.
  static const messageReserve = 'Encaissement réservé aux comptes autorisés : terminez en prévente.';
  static const messageDepotReserve = 'Clôture des ventes en dépôt réservée aux comptes autorisés.';
  static const messageHorsLigne = 'Ce compte ne peut pas terminer une vente : enregistrez-la en prévente.';

  String? _utilisateur;
  Set<String>? _droits;
  bool _routeAbsente = false;
  String _profil = '';
  Future<void>? _enCours;

  /// Diagnostic (tests) : lectures de GET v1/user/droits.
  int lectures = 0;

  /// Droits connus (la route a répondu pour ce compte).
  bool get connus => _droits != null;

  /// Serveur sans GET v1/user/droits (repli : comportement d'avant).
  bool get routeAbsente => _routeAbsente;

  String get profil => _profil;
  String? get utilisateur => _utilisateur;
  Set<String> get droits => Set.unmodifiable(_droits ?? const <String>{});

  bool _unDe(Set<String> requis) => _droits == null || _droits!.any(requis.contains);

  /// « Terminer la vente » (comptant, assurance, carnet), encaissement d'une prévente, clôture espèces hors ligne.
  bool get terminerVente => _unDe(terminerVenteDroits);

  /// Paiement mobile money avec clôture automatique (`cloturer:true`).
  bool get cloturerPaiementMobile => terminerVente;

  /// Clôture d'une vente en dépôt.
  bool get venteDepot => _unDe(venteDepotDroits);

  /// Annulation d'une vente.
  bool get annulerVente => _unDe(annulerVenteDroits);

  /// Droits dont le serveur a PROUVÉ le contrôle pendant cette session (un 403 `interdit` reçu sur la route).
  final Set<String> _controles = {};

  /// 4.6.0 (décision 12) : scan et saisie des lots, création de BL. Un serveur ancien ne connaît pas ce droit (il
  /// n'est dans la liste de personne) : son absence ne suffit pas. Masqué seulement quand le droit manque ET que le
  /// serveur l'a contrôlé (403 `interdit` sur add-lot / creerbl) ; sinon comportement d'avant.
  bool get scannerBl => _droits == null || _droits!.contains(scannerBlDroit) || !_controles.contains(scannerBlDroit);

  /// Changement de serveur (et tests) : contrôles constatés oubliés (ils appartiennent au serveur, pas au compte).
  void oublierControles() {
    if (_controles.isEmpty) return;
    _controles.clear();
    notifyListeners();
  }

  /// Le serveur a refusé une route faute de [droit] (403 `interdit`) : il le contrôle.
  void controleConstate(String droit) {
    if (_controles.add(droit)) notifyListeners();
  }

  /// Profil prévente seulement : droits connus, sans droit de terminer une vente.
  bool get preventeSeule => connus && !terminerVente;

  /// Lit les droits de [utilisateur] (GET v1/user/droits avec [dio], client de la session). Changement de compte :
  /// les droits du précédent sont oubliés AVANT la lecture. Jamais d'exception.
  Future<void> actualiser(Dio dio, {required String utilisateur}) {
    if (utilisateur != _utilisateur) {
      _utilisateur = utilisateur;
      _droits = null;
      _routeAbsente = false;
      _profil = '';
      _enCours = null;
      notifyListeners();
    }
    if (utilisateur.isEmpty) return Future.value();
    return _enCours ??= _lire(dio, utilisateur).whenComplete(() => _enCours = null);
  }

  Future<void> _lire(Dio dio, String utilisateur) async {
    lectures++;
    try {
      final r = await dio.get<dynamic>('/user/droits',
          options: Options(
              validateStatus: (_) => true,
              receiveTimeout: const Duration(seconds: 8),
              sendTimeout: const Duration(seconds: 8),
              // Lecture d'information : un 401 ne déclenche jamais de reconnexion (l'appel qui suit s'en charge).
              extra: {IntercepteurSession.cleRejouee: true}));
      if (utilisateur != _utilisateur) return;
      final s = r.statusCode ?? 0;
      final j = r.data;
      if (s == 200 && j is Map && j['droits'] is List) {
        _droits = {for (final d in j['droits'] as List) if (d != null && '$d'.isNotEmpty) '$d'};
        _profil = '${j['profil'] ?? ''}';
        _routeAbsente = false;
        notifyListeners();
      } else if (s == 404 || s == 405 || s == 501) {
        // Serveur ancien : repli documenté (tout est affiché, le serveur reste juge).
        _droits = null;
        _routeAbsente = true;
        notifyListeners();
      }
      // 401 (session absente), 5xx, réponse illisible : rien ne change (dernière lecture gardée).
    } catch (_) {
      // Réseau : dernière lecture gardée pour ce compte.
    }
  }

  /// Déconnexion, changement de compte, changement de serveur.
  void oublier() {
    _utilisateur = null;
    _droits = null;
    _routeAbsente = false;
    _profil = '';
    _enCours = null;
    notifyListeners();
  }

  /// Tests : fixe les droits sans serveur ([droits] null = repli).
  @visibleForTesting
  void fixer(Set<String>? droits, {String utilisateur = 'test'}) {
    _utilisateur = utilisateur;
    _droits = droits;
    _routeAbsente = droits == null;
    notifyListeners();
  }
}
