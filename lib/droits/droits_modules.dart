// lib/droits/droits_modules.dart
// Droits des menus « Réserve » et « Ordonnances des clients » (affichage du menu, saisie).
//
// Le serveur Prestige ne renvoie pas la liste des privilèges à la connexion (POST /user/auth ne rend que
// `privileges: [canUpdatePrice, showStock]`). L'application les lit donc par des routes dédiées :
//   - Réserve : AUCUN contrôle de privilège côté serveur sur v1/reserve et v1/suggestion-reserve, et aucun privilège
//     « traiter la réserve » n'existe (seul P_ANNULER_MOUVEMENT_RESERVE, pour l'annulation). Décision du pharmacien :
//     administrateur + droit dédié. Administrateur = compte « admin » de l'application (AuthProvider.isAdmin) OU
//     profil administrateur côté serveur (GET v1/roles/est-admin → {authorize}). Droit dédié : lu sur
//     GET v1/reserve/droits → {success, traiter} si le serveur l'ajoute un jour (route demandée à la session
//     serveur ; aujourd'hui 404 → ignoré). Le menu est donc réservé aux administrateurs tant qu'elle n'existe pas.
//   - Ordonnances des clients : GET v1/ordonnance-client/droits → {consulter (P_ORDONNANCE_CLIENT),
//     modifier (P_ORDONNANCE_CLIENT_MAJ)} ; le serveur revérifie chaque appel.
//   - 4.3.0 (réponse du serveur du 15/10/2026, demandes 4 et 5) : le serveur vérifie désormais P_TRAITER_RESERVE
//     sur la réserve et P_SM_POSOS (ou P_ORDONNANCE_CLIENT) sur Posos, et les expose :
//       GET v1/reserve/droits → {success, traiter, annulerMouvement} : quand la route RÉPOND, elle décide seule
//         du menu Réserve (un administrateur sans le droit verrait un menu dont chaque action serait refusée) ;
//         le compte « admin » de l'application le garde (profil administrateur du serveur, qui a le droit).
//       GET v1/posos/droits → {success, analyser} : menu Analyse posologie masqué si analyser = false.
//     Serveur sans ces routes (404, 405…) : règles d'avant inchangées (Réserve : administrateurs ; Posos : tout
//     compte connecté).
// Tant que les droits ne sont pas connus, les menus concernés restent masqués (sauf administrateur local).
import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/serveur/json_tolerant.dart';

/// Droits de l'utilisateur sur les ordonnances des clients (et donc la fiche client).
class DroitsOrdonnances {
  final bool consulter;
  final bool modifier;
  const DroitsOrdonnances({required this.consulter, required this.modifier});

  factory DroitsOrdonnances.fromJson(Map<String, dynamic> j) =>
      // modifier sans consulter n'a pas de sens : le serveur refuserait toutes les lectures.
      DroitsOrdonnances(consulter: booleen(j['consulter']), modifier: booleen(j['consulter']) && booleen(j['modifier']));
}

/// Menu Réserve visible. Droit dédié connu (GET v1/reserve/droits a répondu) : il décide, le compte « admin » de
/// l'application gardant le menu ; route absente (ancien serveur) : administrateur (local ou serveur).
bool menuReserveVisible({required bool adminLocal, bool? adminServeur, bool? droitDedie}) =>
    droitDedie != null ? (droitDedie || adminLocal) : (adminLocal || adminServeur == true);

/// Menu Analyse posologie visible : utilisateur identifié, sauf refus explicite du serveur (GET v1/posos/droits →
/// analyser = false). Route absente : comme avant (tout compte connecté).
bool menuPososVisible({required bool connu, bool? analyser}) => connu && analyser != false;

/// Menu « Ordonnances des clients » visible : droit de consultation connu et accordé.
bool menuOrdonnancesVisible(DroitsOrdonnances? d) => d?.consulter == true;

/// Saisie dans la fiche client (allergies, terrains, mesures) : droit P_ORDONNANCE_CLIENT_MAJ.
bool saisieFicheClientAutorisee(DroitsOrdonnances? d) => d?.consulter == true && d?.modifier == true;

class DroitsModules extends ChangeNotifier {
  DroitsModules();

  /// Instance de l'application (lue par le catalogue des menus de l'accueil).
  static final DroitsModules instance = DroitsModules();

  String? _utilisateur;
  bool _adminLocal = false;
  bool? _adminServeur;
  bool? _reserveDedie;
  bool? _pososAnalyser;
  DroitsOrdonnances? _ordonnances;
  DateTime? _luA;
  Future<void>? _enCours;

  /// Durée pendant laquelle des droits lus ne sont pas relus (retours à l'accueil).
  static const Duration validite = Duration(minutes: 5);

  bool get reserve => menuReserveVisible(adminLocal: _adminLocal, adminServeur: _adminServeur, droitDedie: _reserveDedie);
  DroitsOrdonnances? get ordonnances => _ordonnances;
  bool get ordonnancesConsulter => menuOrdonnancesVisible(_ordonnances);
  bool get ordonnancesModifier => saisieFicheClientAutorisee(_ordonnances);
  bool? get adminServeur => _adminServeur;

  /// Menu Analyse posologie (demande 5) : voir [menuPososVisible].
  bool get posos => menuPososVisible(connu: connu, analyser: _pososAnalyser);

  /// Un utilisateur connecté est identifié (droits lus ou en cours de lecture).
  bool get connu => (_utilisateur ?? '').isNotEmpty;

  /// Relit les droits de [utilisateur] (au plus toutes les 5 minutes, sauf [forcer]).
  /// Changement d'utilisateur : les droits du précédent sont oubliés AVANT la lecture.
  Future<void> actualiser(ClientPrestige client,
      {required String utilisateur, required bool adminLocal, bool forcer = false, DateTime Function()? maintenant}) {
    final now = (maintenant ?? DateTime.now)();
    if (utilisateur != _utilisateur) {
      _utilisateur = utilisateur;
      _adminServeur = null;
      _reserveDedie = null;
      _pososAnalyser = null;
      _ordonnances = null;
      _luA = null;
      _enCours = null;
    }
    if (_adminLocal != adminLocal) {
      _adminLocal = adminLocal;
      notifyListeners();
    }
    if (utilisateur.isEmpty) return Future.value();
    if (!forcer && _luA != null && now.difference(_luA!) < validite) return Future.value();
    return _enCours ??= _lire(client, utilisateur, now).whenComplete(() => _enCours = null);
  }

  Future<void> _lire(ClientPrestige client, String utilisateur, DateTime now) async {
    Future<T?> essai<T>(Future<T> Function() f) async {
      try {
        return await f();
      } on ErreurPrestige {
        return null;
      }
    }

    final admin = essai(() async => booleen((await client.get('/roles/est-admin'))['authorize']));
    final dedie = essai(() async => booleen((await client.get('/reserve/droits'))['traiter']));
    final ordo = essai(() async => DroitsOrdonnances.fromJson(await client.get('/ordonnance-client/droits')));
    // Demande 5 (4.3.0) : route absente sur un ancien serveur (404) → null, menu comme avant.
    final pos = essai(() async {
      final j = await client.get('/posos/droits');
      return j.containsKey('analyser') ? booleen(j['analyser']) : null;
    });
    final a = await admin, d = await dedie, o = await ordo, p = await pos;
    if (utilisateur != _utilisateur) return; // changement d'utilisateur pendant la lecture
    // Échec de lecture (réseau) : on garde ce qui était connu pour cet utilisateur.
    _adminServeur = a ?? _adminServeur;
    _reserveDedie = d ?? _reserveDedie;
    _pososAnalyser = p ?? _pososAnalyser;
    _ordonnances = o ?? _ordonnances;
    if (a != null || o != null) _luA = now;
    notifyListeners();
  }

  /// Déconnexion / changement de serveur.
  void oublier() {
    _utilisateur = null;
    _adminLocal = false;
    _adminServeur = null;
    _reserveDedie = null;
    _pososAnalyser = null;
    _ordonnances = null;
    _luA = null;
    _enCours = null;
    notifyListeners();
  }

  /// Tests : fixe les droits sans serveur.
  @visibleForTesting
  void fixer(
      {bool adminLocal = false, bool? adminServeur, bool? reserveDedie, bool? pososAnalyser, DroitsOrdonnances? ordonnances, String utilisateur = 'test'}) {
    _utilisateur = utilisateur;
    _adminLocal = adminLocal;
    _adminServeur = adminServeur;
    _reserveDedie = reserveDedie;
    _pososAnalyser = pososAnalyser;
    _ordonnances = ordonnances;
    _luA = DateTime.now();
    notifyListeners();
  }
}
