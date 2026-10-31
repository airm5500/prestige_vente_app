// Faux serveur Prestige unifié et réutilisable (tests d'intégration, e2e, ergonomie).
//
// - Routes scriptables (héritées de ServeurJsonLocal : « MÉTHODE suffixe » → réponse), prioritaires sur les
//   routes Prestige par défaut (licence, connexion, officine, préventes, BL, modes de règlement, droits…).
// - Comportements types : 200, `success:false` (refus métier), 401 / 403 « Veuillez vous connecter »,
//   5xx, délai, coupure réseau.
// - Sessions comme le vrai serveur : JSESSIONID NOUVEAU à chaque POST /user/auth, routes non publiques
//   refusées (401 « Veuillez vous connecter », requête NON exécutée) sans cookie valide ; expiration pilotée.
// - Deux transports, même logique :
//     * réseau local (`demarrer()`, vrai HttpServer sur 127.0.0.1) pour les tests `test()` ;
//     * EN MÉMOIRE (`installerEnMemoire()`, HttpOverrides) pour les tests de widgets : aucun socket, le temps
//       est celui du test (délais et dépassements simulés par `tester.pump`).
// - Données fictives seulement (DonneesFictives) : aucune donnée réelle de patient ou de pharmacie.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/io.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';

import 'serveur_json_local.dart';

export 'serveur_json_local.dart';

/// Données fictives (aucune donnée réelle).
class DonneesFictives {
  DonneesFictives._();

  static const officine = 'PHARMACIE DE DEMONSTRATION';
  static const login = 'caisse.demo';
  static const motDePasse = 'Demo#2026';
  static const admin = 'admin';
  static const motDePasseAdmin = 'Admin#2026';

  static Map<String, dynamic> licence({String dateEnd = '2099-12-31'}) =>
      {'id': 'LIC-DEMO', 'dateStart': '2026-01-01', 'dateEnd': dateEnd, 'typeLicence': 'ANNUELLE'};

  static Map<String, dynamic> utilisateur(String login) => {
        'success': true,
        'str_LOGIN': login,
        'str_USER_ID': 'U-$login',
        'str_FIRST_NAME': login == admin ? 'Admin' : 'Awa',
        'str_LAST_NAME': login == admin ? 'Démo' : 'Test',
        'str_OFFICINE': officine,
      };

  static List<Map<String, dynamic>> officines() => [
        {'str_NOM_ABREGE': 'DEMO', 'str_NOM_COMPLET': officine, 'str_FIRST_NAME': 'DR', 'str_LAST_NAME': 'DEMO'},
      ];

  /// Lignes de GET /info (analyse article, fiche produit).
  static List<Map<String, dynamic>> info(String recherche) => [
        {
          'codeCip': '9990001',
          'libelle': 'PARACETAMOL TEST 500MG CP B/16',
          'produitId': 'PF-1',
          'stock': 18,
          'prixVente': 1200,
          'prixAchat': 800,
          'emplacement': 'RAYON A1',
          'grossiste': 'GROSSISTE DEMO',
          'moyenne': 3,
        },
      ];

  // --- Réserve (v1/suggestion-reserve) ---
  static Map<String, dynamic> enteteReserve({String id = 'S1', String cat = 'RAYON', String statut = 'A_TRAITER'}) => {
        'lg_SUGGESTION_RESERVE_ID': id,
        'str_REF': 'SR-RAY-261013-101500',
        'str_CATEGORIE': cat,
        'str_ORIGINE': 'AUTOMATIQUE',
        'str_STATUT': statut,
        'motif_id': 1,
        'motif_libelle': 'Reappro rayon journalier',
        'str_USER_CREATEUR': 'Préparateur Démo',
        'dt_CREATED': '13/10/2026 10:15',
        'nb_produits': 2,
      };

  static Map<String, dynamic> ligneReserve(String id, {int proposee = 5, int rayon = 2, int reserve = 10}) => {
        'lg_SUGGESTION_RESERVE_DETAIL_ID': id,
        'lg_FAMILLE_ID': 'F$id',
        'int_CIP': '999100$id',
        'str_NAME': 'PRODUIT DEMO $id',
        'int_QTE_PROPOSEE': proposee,
        'int_QTE_RETENUE': null,
        'int_STOCK_RAYON': rayon,
        'int_STOCK_RESERVE': reserve,
        'int_STOCK_RAYON_ACTUEL': rayon,
        'int_STOCK_RESERVE_ACTUEL': reserve,
        'str_FORMULE': 'A la creation : rayon $rayon',
        'str_ETAT': 'PROPOSEE',
      };

  // --- Fiche client (v1/ordonnance-client) : patient FICTIF ---
  static Map<String, dynamic> dossierClient({String naissance = '1980-01-01'}) => {
        'success': true,
        'client': {'id': 'C1', 'nom': 'DEMO', 'prenoms': 'Patient Fictif', 'telephone': '0100000000', 'naissance': naissance, 'age': naissance.isEmpty ? null : 46, 'sexe': 'F', 'type': 'STANDARD'},
        'terrains': ['T1'],
        'allergies': 'Allergie fictive',
        'parametres': [
          {'parametreId': 'PARAM_POIDS', 'code': 'POIDS', 'libelle': 'Poids', 'unite': 'kg', 'genre': 'simple', 'decimales': 1, 'nbMesures': 1, 'valeur': 72.5, 'date': '2026-10-01', 'etat': 'normal', 'analyse': 'Normale'},
          {'parametreId': 'PARAM_TENSION', 'code': 'TENSION', 'libelle': 'Tension artérielle', 'unite': 'mmHg', 'genre': 'tension', 'decimales': 0, 'nbMesures': 0},
        ],
        'imc': {'valeur': 24.1, 'etat': 'normal', 'analyse': 'Corpulence normale'},
        'nbOrdonnances': 2,
      };

  static Map<String, dynamic> produitRecherche() => {
        'lgFAMILLEID': 'PF-1',
        'strNAME': 'PARACETAMOL TEST 500MG CP B/16',
        'intCIP': '9990001',
        'intPRICE': 1200,
        'intNUMBERAVAILABLE': 18,
        'strLIBELLEE': 'ANTALGIQUE',
        'intPAF': 800,
      };
}

/// Routes publiques côté serveur Prestige (sans cookie) — même liste que l'application.
bool routePubliquePrestige(String chemin) {
  var p = chemin;
  while (p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  // 4.8.0 : /appareil/nom (demande 56) : le filtre le laisse passer ; le PUT vérifie la session lui-même.
  const publiques = ['/user/auth', '/user/logout', '/licence/find', '/officine', '/app/info', '/appareil/nom'];
  return publiques.any(p.endsWith) || p.contains('/licence/save') || p.contains('/mobile/') || p.contains('/espace-produit/');
}

class FauxServeurPrestige extends ServeurJsonLocal {
  FauxServeurPrestige({this.exigerSession = true, Map<String, String>? comptes, this.hoteEnMemoire = hoteMemoire})
      : comptes = comptes ?? {DonneesFictives.login: DonneesFictives.motDePasse, DonneesFictives.admin: DonneesFictives.motDePasseAdmin};

  /// Nom d'hôte de ce serveur dans le transport en mémoire (deux serveurs : « local » et « distant »).
  final String hoteEnMemoire;

  /// HTTPS en mémoire : le certificat présenté est refusé par l'appareil (poignée de main TLS en échec).
  bool certificatRefuse = false;

  // ---------------------------------------------------------------------------
  // Comportements types (utilisables dans les routes scriptées)
  // ---------------------------------------------------------------------------

  static ReponseLocale ok(Object? corps, {Duration delai = Duration.zero}) => ReponseLocale(corps, delai: delai);
  static ReponseLocale refus(String message, {String? code}) =>
      ReponseLocale({'success': false, 'message': message, 'msg': message, if (code != null) 'code': code});
  static const ReponseLocale nonConnecte401 = ReponseLocale(messageDeconnecte, statut: 401);
  static const ReponseLocale nonConnecte403 = ReponseLocale(messageDeconnecte, statut: 403);
  static ReponseLocale erreurServeur([int statut = 500]) => ReponseLocale('<html><body>Erreur $statut</body></html>', statut: statut);
  static ReponseLocale lent(Object? corps, Duration delai) => ReponseLocale(corps, delai: delai);

  /// Réponse annoncée en JSON mais illisible (JSON partiel ou invalide) : statut 200, connexion normale.
  static ReponseLocale jsonInvalide(String texte, {Duration delai = Duration.zero}) =>
      ReponseLocale(texte, delai: delai, entetes: const {'content-type': 'application/json; charset=utf-8'});

  /// Réponse TRONQUÉE : la connexion se ferme après [part] du corps (réseau qui lâche pendant la réponse).
  static ReponseLocale coupeeEnCours(Object? corps, {double part = 0.5}) {
    final r = ReponseLocale(corps);
    return ReponseLocale(corps, coupeeApres: (utf8.encode(r.texte).length * part).floor());
  }

  static const messageDeconnecte = 'Veuillez vous connecter';

  /// 4.5.1 : refus de droit du serveur (403 `{success:false, interdit:true, msg}`), rien n'est enregistré.
  static ReponseLocale interdit([String msg = 'Droit manquant : vous ne pouvez pas terminer cette vente.']) =>
      ReponseLocale({'success': false, 'interdit': true, 'msg': msg}, statut: 403);

  /// 4.5.1 : droits de chaque compte (GET v1/user/droits) ; compte absent de la table : [droitsComplets] (serveur à
  /// jour, comptes de démonstration autorisés) ; null = route absente (serveur ancien : 404 de Payara).
  Map<String, List<String>>? droitsComptes = {};

  /// Droits d'un compte non listé dans [droitsComptes].
  static const droitsComplets = ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE', 'P_SM_VENTEDEPOT', 'P_BT_ANNULER_VENTE'];

  /// 4.5.1 : compte de chaque session (JSESSIONID → login) ; [basculerSession] simule un autre compte connecté sur
  /// la même session (filtre UtilisateurOngletFilter : 409 sessionChangee si l'en-tête ne correspond plus).
  final Map<String, String> compteSession = {};

  /// Requêtes refusées en 409 sessionChangee.
  int refus409 = 0;

  void basculerSession(String login) {
    final id = derniereSession;
    if (id != null) compteSession[id] = login;
  }

  // ---------------------------------------------------------------------------
  // État pilotable
  // ---------------------------------------------------------------------------

  /// Routes non publiques refusées sans JSESSIONID valide (filtre d'authentification de Prestige).
  bool exigerSession;

  /// Refus de session en 403 « Veuillez vous connecter » au lieu de 401.
  bool refusEn403 = false;

  /// Comptes acceptés par POST /user/auth (identifiant → mot de passe).
  final Map<String, String> comptes;

  /// Réponse de GET /licence/find (licence valide par défaut).
  ReponseLocale licence = ReponseLocale(DonneesFictives.licence());

  /// Coupure réseau : toutes les requêtes échouent (connexion refusée).
  bool get coupe => _coupe;
  bool _coupe = false;

  /// Délai ajouté à toutes les réponses.
  Duration latence = Duration.zero;

  /// Sessions valides (JSESSIONID).
  final Set<String> sessions = {};
  int _prochaineSession = 1;

  /// Nombre de POST /user/auth réussis.
  int connexions = 0;

  /// Requêtes refusées par le filtre de session.
  int refusSession = 0;

  /// Dernier JSESSIONID délivré.
  String? derniereSession;

  /// Toutes les sessions expirent (durée de session dépassée côté serveur).
  void expirerSessions() => sessions.clear();

  /// Coupure réseau (en mémoire : connexion refusée ; réseau local : port fermé).
  Future<void> couper() async {
    _coupe = true;
    if (ecoute) await arreter();
  }

  /// Fin de la coupure.
  Future<void> retablir() async {
    final relancer = _coupe && _reseauLocal;
    _coupe = false;
    if (relancer) await demarrer();
  }

  bool _reseauLocal = false;

  @override
  Future<void> demarrer() async {
    SondeDeploiement.vider();
    _reseauLocal = true;
    await super.demarrer();
  }

  // ---------------------------------------------------------------------------
  // Traitement
  // ---------------------------------------------------------------------------

  /// Routes par défaut (après les routes scriptées).
  final Map<String, FutureOr<ReponseLocale> Function(RequeteRecue r)> routesParDefaut = {};

  /// 4.10.1 : date de naissance du client fictif C1 ('' = absente), complétée par POST client/C1/identite.
  String naissanceC1 = '1980-01-01';

  /// Modules Réserve, Analyse posologie et Fiche client avec des données fictives (droits accordés si [droits]).
  void activerModules({bool droits = true}) {
    routesParDefaut.addAll({
      'GET /roles/est-admin': (_) => ReponseLocale({'authorize': droits}),
      'GET /ordonnance-client/droits': (_) => ReponseLocale({'success': true, 'consulter': droits, 'modifier': droits}),
      'GET /ordonnance-client/clients': (_) => const ReponseLocale({
            'success': true,
            'data': [
              {'lgCLIENTID': 'C1', 'strFIRSTNAME': 'DEMO', 'strLASTNAME': 'Patient Fictif', 'strADRESSE': '', 'strTELEPHONE': '0100000000'}
            ]
          }),
      'GET /client/C1/dossier': (_) => ReponseLocale(DonneesFictives.dossierClient(naissance: naissanceC1)),
      // 4.10.1 : POST client/{id}/identite, règles de DossierClientService.completerIdentite (serveur a2bb8cc8) :
      // complète une date ABSENTE seulement, AAAA-MM-JJ, ni à venir ni avant 1900, droit de saisie.
      'POST /client/C1/identite': (r) {
        if (!droits) return const ReponseLocale({'success': false, 'message': 'Votre profil ne permet pas de saisir ou de modifier une ordonnance.'});
        final n = '${r.json['naissance'] ?? ''}'.trim();
        final d = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(n) ? DateTime.tryParse(n) : null;
        if (d == null) return const ReponseLocale({'success': false, 'message': 'Date de naissance illisible : jj/mm/aaaa attendu.'});
        if (d.isAfter(DateTime.now())) return const ReponseLocale({'success': false, 'message': 'La date de naissance ne peut pas être dans le futur.'});
        if (d.year < 1900) return const ReponseLocale({'success': false, 'message': 'Date de naissance improbable.'});
        if (naissanceC1.isNotEmpty) return const ReponseLocale({'success': false, 'message': 'Déjà renseigné : la fiche n\'a pas été modifiée.'});
        naissanceC1 = n;
        return const ReponseLocale({'success': true, 'message': 'Fiche complétée : date de naissance.'});
      },
      'GET /ordonnance-client/terrains': (_) => const ReponseLocale({
            'success': true,
            'data': [
              {'id': 'T1', 'libelle': 'Diabète'},
              {'id': 'T2', 'libelle': 'Pénicilline', 'categorie': 'ALLERGIE'},
            ]
          }),
      'GET /ordonnance-client/parametres': (_) => const ReponseLocale({
            'success': true,
            'data': [
              {'id': 'PARAM_POIDS', 'code': 'POIDS', 'libelle': 'Poids', 'unite': 'kg', 'decimales': 1, 'saisieMin': 0.5, 'saisieMax': 400},
              {'id': 'PARAM_TENSION', 'code': 'TENSION', 'libelle': 'Tension artérielle', 'unite': 'mmHg', 'genre': 'tension', 'saisieMin': 40, 'saisieMax': 260},
            ]
          }),
      'GET /client/C1/mesures': (_) => const ReponseLocale({'success': true, 'data': []}),
      'GET /client/C1/consommation': (_) => const ReponseLocale({'success': true, 'data': []}),
      'GET /suggestion-reserve/en-attente': (_) => ReponseLocale({'results': [DonneesFictives.enteteReserve()], 'total': 1}),
      'GET /suggestion-reserve/motifs': (_) => const ReponseLocale([
            {'id': 1, 'libelle': 'Reappro rayon journalier', 'categorie': 'RAYON'}
          ]),
      'PUT /S1/ouvrir': (_) => ReponseLocale({
            'success': true,
            'entete': DonneesFictives.enteteReserve(),
            'lignes': [DonneesFictives.ligneReserve('1'), DonneesFictives.ligneReserve('2', proposee: 4, reserve: 3)],
            'modifiable': true,
          }),
      'PUT /S1/liberer': (_) => const ReponseLocale({'success': true}),
      'GET /posos/status': (_) => const ReponseLocale({'success': true, 'configuree': false, 'mode': 'demonstration'}),
    });
  }

  // ---------------------------------------------------------------------------
  // 4.4.0 : pointage par téléphone (v1/mobile, jeton Bearer) — comptes et employés FICTIFS
  // ---------------------------------------------------------------------------

  /// Employé rattaché à chaque compte (identifiant → nom affiché) pour v1/mobile.
  final Map<String, String> employesMobile = {};

  /// Jetons délivrés (jeton → identifiant du compte).
  final Map<String, String> jetonsMobile = {};

  /// Pointages reçus par v1/mobile : compte du JETON (jamais celui que l'appli prétendrait) et sens.
  final List<({String login, String sens})> pointagesMobile = [];

  /// Connexions v1/mobile reçues (identifiants demandés).
  final List<String> connexionsMobile = [];

  Map<String, dynamic> _moiMobile(String login) => {
        'success': true,
        'utilisateur': {'id': 'U-$login', 'login': login, 'nom': employesMobile[login] ?? login},
        'employe': employesMobile.containsKey(login) ? {'id': 'E-$login', 'matricule': 'M-$login', 'nom': employesMobile[login]} : null,
        'droits': {'pointage': true, 'photos': false},
        'pointage': {'qr': false, 'gps': false},
      };

  /// Active v1/mobile (connexion, moi, pointages) pour [employes] (identifiant → nom fictif).
  void activerPointageMobile(Map<String, String> employes) {
    employesMobile.addAll(employes);
    var n = 0;
    String? compteDuJeton(RequeteRecue r) => r.jeton == null ? null : jetonsMobile[r.jeton];
    routesParDefaut.addAll({
      'POST /mobile/connexion': (r) {
        final j = _jsonOuVide(r.corps);
        final login = '${j['login'] ?? ''}';
        if (login.isEmpty) return refus('Identifiant et mot de passe obligatoires.');
        connexionsMobile.add(login);
        if (comptes[login] != '${j['motDePasse'] ?? ''}') return refus('Identifiant ou mot de passe incorrect.');
        final jeton = 'JETON-FICTIF-${++n}';
        jetonsMobile[jeton] = login;
        return ReponseLocale({..._moiMobile(login), 'jeton': jeton, 'expiration': '2099-12-31T23:59:00Z'});
      },
      'GET /mobile/moi': (r) {
        final login = compteDuJeton(r);
        return login == null ? const ReponseLocale({'success': false, 'expire': true, 'message': 'Session expirée.'}, statut: 401) : ReponseLocale(_moiMobile(login));
      },
      'GET /mobile/pointages': (r) {
        final login = compteDuJeton(r);
        if (login == null) return const ReponseLocale({'success': false, 'expire': true}, statut: 401);
        return ReponseLocale({
          'success': true,
          'data': [
            for (final p in pointagesMobile)
              if (p.login == login) {'heure': '08:0${pointagesMobile.indexOf(p) % 10}', 'sens': p.sens, 'source': 'MOBILE'}
          ]
        });
      },
      'POST /mobile/pointages': (r) {
        final login = compteDuJeton(r);
        if (login == null) return const ReponseLocale({'success': false, 'expire': true}, statut: 401);
        final sens = '${_jsonOuVide(r.corps)['sens'] ?? 'ENTREE'}';
        pointagesMobile.add((login: login, sens: sens));
        return ReponseLocale({'success': true, 'sens': sens, 'heure': '08:02', 'message': '${sens == 'SORTIE' ? 'Sortie' : 'Entrée'} enregistrée à 08:02.'});
      },
    });
  }

  // ---------------------------------------------------------------------------
  // 4.6.0 : « Mon pointage » sous la session (demande 51) et terminal avec P_RH_POINTER (demande 52)
  // ---------------------------------------------------------------------------

  /// Pointages reçus par POST v1/rh/moi/pointages : compte de la SESSION et clé client.
  final List<({String login, String sens, String cle})> pointagesSession = [];

  /// Active GET v1/rh/moi, GET / POST v1/rh/moi/pointages (session, X-Client-Ref) pour [employes].
  void activerPointageSession(Map<String, String> employes) {
    employesMobile.addAll(employes);
    String? compte(RequeteRecue r) => r.jsessionid == null ? null : compteSession[r.jsessionid];
    final dejaVus = <String, Map<String, dynamic>>{};
    routesParDefaut.addAll({
      'GET /rh/moi': (r) {
        final login = compte(r);
        return login == null ? nonConnecte401 : ReponseLocale(_moiMobile(login));
      },
      'GET /rh/moi/pointages': (r) {
        final login = compte(r);
        if (login == null) return nonConnecte401;
        return ReponseLocale({
          'success': true,
          'data': [
            for (final p in pointagesSession)
              if (p.login == login) {'heure': '08:0${pointagesSession.indexOf(p) % 10}', 'sens': p.sens, 'source': 'MOBILE'}
          ]
        });
      },
      'POST /rh/moi/pointages': (r) {
        final login = compte(r);
        if (login == null) return nonConnecte401;
        final deja = dejaVus[r.clientRef];
        if (r.clientRef.isNotEmpty && deja != null) return ReponseLocale(deja);
        // Comme le serveur : employeId / login du corps ignorés, le pointage va au compte de la session.
        final sens = '${_jsonOuVide(r.corps)['sens'] ?? 'ENTREE'}';
        pointagesSession.add((login: login, sens: sens, cle: r.clientRef));
        final rep = {'success': true, 'sens': sens, 'heure': '08:02', 'message': '${sens == 'SORTIE' ? 'Sortie' : 'Entrée'} enregistrée à 08:02.'};
        if (r.clientRef.isNotEmpty) dejaVus[r.clientRef] = rep;
        return ReponseLocale(rep);
      },
    });
  }

  /// Droits RH de chaque compte (GET v1/rh/droits) : `{pointer, gerer}` ; compte absent : refus comme le serveur.
  final Map<String, ({bool pointer, bool gerer})> droitsRh = {};

  /// Employés fictifs du terminal (GET v1/rh/employes) ; sans `gerer`, seulement les champs réduits du serveur.
  List<Map<String, dynamic>> employesRh = [
    {'id': 'E1', 'matricule': '01', 'nom': 'KOUASSI', 'prenoms': 'Awa', 'badge': 'B001', 'statut': 'ACTIF', 'poste': 'Vendeuse', 'telephone': '0000'},
    {'id': 'E2', 'matricule': '02', 'nom': 'TRAORE', 'prenoms': 'Ali', 'badge': 'B002', 'statut': 'ACTIF', 'poste': 'Caissier', 'telephone': '0000'},
  ];

  /// Pointages reçus par POST v1/rh/pointages (terminal).
  final List<Map<String, dynamic>> pointagesTerminal = [];

  /// Active les routes du terminal (droits, employés, pointages) selon [droitsRh].
  /// 4.8.0 — demande 56 : noms d'appareils gardés par empreinte (GET sans session, PUT avec la session).
  final Map<String, String> nomsAppareils = {};

  /// Statut forcé de GET v1/appareil/nom (429, 404…) ; null = réponse normale.
  int? statutLectureNom;

  /// Délai de GET v1/appareil/nom.
  Duration delaiLectureNom = Duration.zero;

  /// Nom renvoyé par le PUT à partir du nom reçu (le serveur nettoie comme X-Poste) ; remplaçable.
  String Function(String recu) nomEnregistreServeur = (n) => n.trim();

  /// Statut forcé du PUT (404 = serveur ancien…) ; null = réponse normale.
  int? statutEnvoiNom;

  void activerNomAppareil() {
    routesParDefaut.addAll({
      'GET /appareil/nom': (r) {
        if (statutLectureNom != null) {
          return ReponseLocale({'success': false, 'code': statutLectureNom == 429 ? 'TROP_DE_DEMANDES' : 'X'}, statut: statutLectureNom!, delai: delaiLectureNom);
        }
        final e = r.query['empreinte'] ?? '';
        if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(e)) return const ReponseLocale({'success': false, 'code': 'INVALIDE'}, statut: 400);
        return ReponseLocale({'success': true, 'nom': nomsAppareils[e.toLowerCase()]}, delai: delaiLectureNom);
      },
      'PUT /appareil/nom': (r) {
        if (statutEnvoiNom != null) return ReponseLocale('<html>$statutEnvoiNom</html>', statut: statutEnvoiNom!);
        if (!_sessionValide(r)) return const ReponseLocale({'success': false, 'code': 'SESSION'}, statut: 401);
        final j = _jsonOuVide(r.corps);
        final e = '${j['empreinte'] ?? ''}';
        if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(e)) return const ReponseLocale({'success': false, 'code': 'INVALIDE'}, statut: 400);
        final nom = nomEnregistreServeur('${j['nom'] ?? ''}');
        if (nom.isEmpty) return const ReponseLocale({'success': false, 'code': 'INVALIDE'}, statut: 400);
        nomsAppareils[e.toLowerCase()] = nom;
        return ReponseLocale({'success': true, 'nom': nom});
      },
    });
  }

  void activerTerminalRh() {
    String? compte(RequeteRecue r) => r.jsessionid == null ? null : compteSession[r.jsessionid];
    ({bool pointer, bool gerer})? d(RequeteRecue r) => droitsRh[compte(r)];
    const interditRh = ReponseLocale({'success': false, 'interdit': true, 'msg': 'Droit manquant : gestion RH (P_SM_RH).'}, statut: 403);
    routesParDefaut.addAll({
      'GET /rh/droits': (r) {
        final x = d(r);
        if (x == null) return const ReponseLocale({'success': false, 'msg': 'Vous n\'avez pas accès aux ressources humaines.'});
        return ReponseLocale({'success': true, 'pointer': true, 'gerer': x.gerer, 'valider': x.gerer, 'photoRetentionJours': 30});
      },
      'GET /rh/employes': (r) {
        final x = d(r);
        if (x == null) return interditRh;
        const reduits = ['id', 'matricule', 'nom', 'prenoms', 'badge', 'statut'];
        return ReponseLocale({
          'success': true,
          'data': [for (final e in employesRh) x.gerer ? e : {for (final k in reduits) k: e[k]}],
        });
      },
      'POST /rh/pointages': (r) {
        if (d(r) == null) return interditRh;
        final j = _jsonOuVide(r.corps);
        pointagesTerminal.add(j);
        return ReponseLocale({'success': true, 'id': 'P${pointagesTerminal.length}', 'sens': 'ENTREE', 'heure': '08:05', 'controle': false});
      },
      'GET /rh/presence': (r) => d(r)?.gerer == true ? const ReponseLocale({'success': true, 'data': []}) : interditRh,
      'GET /rh/tableau': (r) => d(r)?.gerer == true ? const ReponseLocale({'success': true, 'data': []}) : interditRh,
    });
  }

  bool _sessionValide(RequeteRecue r) => r.jsessionid != null && sessions.contains(r.jsessionid);

  @override
  Future<ReponseLocale> repondre(RequeteRecue r) async {
    final rep = await _repondre(r);
    if (latence > Duration.zero && rep.delai == Duration.zero) {
      return ReponseLocale(rep.corps, statut: rep.statut, delai: latence, entetes: rep.entetes);
    }
    return rep;
  }

  /// 4.3.3 : Prestige NON DÉPLOYÉ (démarrage / redéploiement) : Payara répond [statutAbsent] (404 par défaut, page
  /// HTML « Error report ») sur toutes les routes, /officine et /user/auth compris.
  bool prestigeAbsent = false;
  int statutAbsent = 404;

  /// Page d'erreur de Payara (application absente, ou route inconnue d'un serveur ancien : même corps).
  static const ReponseLocale payara404 = ReponseLocale(
      '<!DOCTYPE html><html><head><title>Payara Server  5.2022.5 #badassfish - Error report</title></head>'
      '<body><h1>HTTP Status 404 - Not Found</h1></body></html>',
      statut: 404);

  /// 4.10.0 (Prestige Pointage, demande 57) : filtre exécuté AVANT celui de la session (comme celui du serveur pour
  /// v1/borne-pointage/* et l'en-tête X-Borne) ; null = requête non concernée. Voir test/outils/faux_serveur_borne.dart.
  FutureOr<ReponseLocale?> Function(RequeteRecue r)? filtreAvantSession;

  Future<ReponseLocale> _repondre(RequeteRecue r) async {
    if (prestigeAbsent) {
      return statutAbsent == 404 ? payara404 : ReponseLocale('<html><body>$statutAbsent</body></html>', statut: statutAbsent);
    }
    final f = filtreAvantSession;
    if (f != null) {
      final rep = await f(r);
      if (rep != null) return rep;
    }
    // Filtre d'authentification : requête refusée AVANT d'être exécutée.
    if (exigerSession && !routePubliquePrestige(r.chemin) && !_sessionValide(r)) {
      refusSession++;
      return refusEn403 ? nonConnecte403 : nonConnecte401;
    }
    // 4.5.1 : filtre UtilisateurOngletFilter du serveur (en-tête X-Prestige-Utilisateur ≠ compte de la session).
    final compte = r.jsessionid == null ? null : compteSession[r.jsessionid];
    if (r.utilisateur.isNotEmpty && compte != null && r.utilisateur != 'U-$compte' && !r.chemin.endsWith('/user/logout')) {
      refus409++;
      return ReponseLocale({
        'success': false,
        'sessionChangee': true,
        'msg': 'Un autre compte ($compte) s\'est connecté sur ce navigateur. Rien n\'a été enregistré : la page se recharge au nom de ce compte.'
      }, statut: 409);
    }
    final scriptee = routePour(r);
    if (scriptee != null) return await scriptee(r);
    for (final e in routesParDefaut.entries) {
      final sp = e.key.indexOf(' ');
      if (r.methode == e.key.substring(0, sp) && r.chemin.endsWith(e.key.substring(sp + 1))) return await e.value(r);
    }
    return _prestige(r);
  }

  /// Routes Prestige de base.
  ReponseLocale _prestige(RequeteRecue r) {
    final c = r.chemin;
    if (r.methode == 'GET' && c.endsWith('/licence/find')) return licence;
    if (r.methode == 'POST' && c.endsWith('/user/auth')) {
      final j = _jsonOuVide(r.corps);
      final login = '${j['login'] ?? ''}';
      final mdp = '${j['password'] ?? ''}';
      if (login.isEmpty || comptes[login] != mdp) return const ReponseLocale({'success': false, 'msg': 'Identifiants incorrects'});
      final id = 'FAUX${_prochaineSession++}';
      sessions.add(id);
      derniereSession = id;
      compteSession[id] = login;
      connexions++;
      return ReponseLocale(DonneesFictives.utilisateur(login), entetes: {'set-cookie': 'JSESSIONID=$id; Path=/prestige; HttpOnly'});
    }
    if (c.endsWith('/user/logout')) {
      if (r.jsessionid != null) sessions.remove(r.jsessionid);
      return const ReponseLocale({'success': true});
    }
    if (r.methode == 'GET' && c.endsWith('/officine')) return ReponseLocale(DonneesFictives.officines());
    if (r.methode == 'GET' && c.endsWith('/user/droits')) {
      final d = droitsComptes;
      final login = r.jsessionid == null ? null : compteSession[r.jsessionid];
      if (d == null) return payara404;
      return ReponseLocale({'success': true, 'profil': 'mainmenumanager', 'droits': d[login] ?? droitsComplets});
    }
    if (r.methode == 'GET' && c.endsWith('/user/account')) {
      final login = r.jsessionid == null ? null : compteSession[r.jsessionid];
      if (login == null) return const ReponseLocale({'accountInfo': {}});
      final u = DonneesFictives.utilisateur(login);
      return ReponseLocale({
        // Noms JSON de l'AccountInfoDTO du serveur (@JSONPropertyName).
        'accountInfo': {'lg_USER_ID': u['str_USER_ID'], 'str_LOGIN': login, 'str_FIRST_NAME': u['str_FIRST_NAME'], 'str_LAST_NAME': u['str_LAST_NAME']}
      });
    }
    if (c.endsWith('/ventestats/preventes')) return const ReponseLocale({'data': [], 'total': 0});
    if (c.endsWith('/commande/list-bons')) return const ReponseLocale({'data': [], 'total': 0});
    if (c.endsWith('/modereglement/all') || c.endsWith('/common/reglement')) return const ReponseLocale({'data': []});
    if (c.endsWith('/roles/est-admin')) return const ReponseLocale({'authorize': false});
    if (c.endsWith('/ordonnance-client/droits')) return const ReponseLocale({'success': true, 'consulter': false, 'modifier': false});
    if (r.methode == 'GET' && c.endsWith('/info')) return ReponseLocale(DonneesFictives.info(r.query['search'] ?? ''));
    if (c.endsWith('/vente/search')) return ReponseLocale({'data': [DonneesFictives.produitRecherche()], 'total': 1});
    return _ventes(r) ?? reponseInconnue;
  }

  // ---------------------------------------------------------------------------
  // Ventes comptant simulées (création au 1er article, panier, net, prévente) — état gardé en mémoire.
  // ---------------------------------------------------------------------------

  /// Ventes créées : identifiant → lignes ; statut Prestige (is_Process / is_Closed).
  final Map<String, List<Map<String, dynamic>>> ventes = {};
  final Map<String, String> statutVentes = {};

  ReponseLocale? _ventes(RequeteRecue r) {
    final c = r.chemin;
    Map<String, dynamic> ligne(String venteId, Map<String, dynamic> j) {
      final p = DonneesFictives.produitRecherche();
      final qte = (j['qte'] as num?)?.toInt() ?? 1;
      final pu = (j['itemPu'] as num?)?.toInt() ?? p['intPRICE'] as int;
      return {
        'lgPREENREGISTREMENTDETAILID': '$venteId-L${(ventes[venteId]?.length ?? 0) + 1}',
        'lgFAMILLEID': '${j['produitId']}',
        'strNAME': j['produitId'] == p['lgFAMILLEID'] ? p['strNAME'] : 'PRODUIT ${j['produitId']}',
        'intCIP': j['produitId'] == p['lgFAMILLEID'] ? p['intCIP'] : '',
        'intQUANTITY': qte,
        'intPRICEUNITAIR': pu,
        'intPRICE': qte * pu,
        'strREF': 'REF-$venteId',
      };
    }

    if (r.methode == 'POST' && c.endsWith('/vente/add/vno')) {
      final id = 'V-${ventes.length + 1}';
      ventes[id] = [ligne(id, r.json)];
      statutVentes[id] = 'is_Process';
      return ReponseLocale({'success': true, 'data': {'lgPREENREGISTREMENTID': id}});
    }
    if (r.methode == 'POST' && c.endsWith('/vente/add/item')) {
      final id = '${r.json['venteId']}';
      if (!ventes.containsKey(id)) return refus('Vente introuvable');
      ventes[id]!.add(ligne(id, r.json));
      return ReponseLocale({'success': true, 'data': {'lgPREENREGISTREMENTID': id}});
    }
    if (r.methode == 'GET' && c.endsWith('/vente/deatails')) {
      final l = ventes[r.query['venteId']] ?? const [];
      return ReponseLocale({'data': l, 'total': l.length});
    }
    if (r.methode == 'POST' && c.endsWith('/vente/net/vno')) {
      final id = '${r.json['venteId']}';
      final total = (ventes[id] ?? const []).fold<int>(0, (s, l) => s + (l['intPRICE'] as int));
      return ReponseLocale({
        'success': true,
        'data': {'montant': total, 'montantNet': total, 'remise': 0, 'marge': 0, 'montantTva': 0},
        'lgPREENREGISTREMENTID': id,
        'strREF': 'REF-$id',
      });
    }
    final terminer = RegExp(r'/vente/terminerprevente/([^/]+)$').firstMatch(c);
    if (r.methode == 'PUT' && terminer != null) {
      final id = terminer.group(1)!;
      if (!ventes.containsKey(id)) return refus('Vente introuvable');
      statutVentes[id] = 'is_Process';
      return const ReponseLocale({'success': true});
    }
    final lire = RegExp(r'/ventestats/(V-[^/]+)$').firstMatch(c);
    if (r.methode == 'GET' && lire != null) {
      final s = statutVentes[lire.group(1)];
      return s == null ? refus('Vente introuvable') : ReponseLocale({'data': {'strSTATUT': s}});
    }
    return null;
  }

  static Map<String, dynamic> _jsonOuVide(String corps) {
    try {
      final v = jsonDecode(corps);
      return v is Map ? Map<String, dynamic>.from(v) : const {};
    } catch (_) {
      return const {};
    }
  }

  // ---------------------------------------------------------------------------
  // Transport en mémoire (tests de widgets)
  // ---------------------------------------------------------------------------

  /// Adresse fictive (aucune résolution DNS : tout passe par le client HTTP en mémoire).
  static const hoteMemoire = 'prestige.test';
  static const portMemoire = '8080';

  bool _enMemoire = false;

  /// Client en mémoire : TOUTES les adresses demandées par l'application, dans l'ordre, y compris celles refusées
  /// (autre hôte que [hoteMemoire], par ex. http://localhost:8080, ou serveur coupé). Voir ANO-08.
  final List<Uri> tentatives = [];

  @override
  String get hote => _enMemoire ? '$hoteEnMemoire:$portMemoire' : super.hote;

  /// Serveurs installés en mémoire, par nom d'hôte.
  static final Map<String, FauxServeurPrestige> _actifs = {};
  HttpOverrides? _precedent;

  /// Remplace le client HTTP de l'application par un client en mémoire relié à ce serveur (toutes les
  /// instances Dio de l'appli). À appeler dans le test ; [desinstaller] (ou addTearDown) remet l'ancien.
  void installerEnMemoire() {
    SondeDeploiement.vider(); // 4.3.3 : vérifications « Prestige déployé ? » d'un test précédent oubliées
    _enMemoire = true;
    _precedent = HttpOverrides.current;
    _actifs[hoteEnMemoire] = this;
    HttpOverrides.global = _FauxHttpOverrides();
    // Le client Dio partagé garde son HttpClient : on lui en donne un neuf (créé avec ces overrides).
    DioClient.getClient(base).httpClientAdapter = IOHttpClientAdapter();
  }

  void desinstaller() {
    if (identical(_actifs[hoteEnMemoire], this)) _actifs.remove(hoteEnMemoire);
    HttpOverrides.global = _precedent;
    DioClient.getClient('').httpClientAdapter = IOHttpClientAdapter();
  }

  /// Traitement d'une requête du client en mémoire.
  Future<ReponseLocale> _traiterMemoire(RequeteRecue r) async {
    recues.add(r);
    return repondre(r);
  }
}

// -----------------------------------------------------------------------------
// Client HTTP en mémoire (dart:io HttpClient minimal, suffisant pour Dio IOHttpClientAdapter)
// -----------------------------------------------------------------------------

class _FauxHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FauxHttpClient();
}

class _FauxHttpClient implements HttpClient {
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  bool autoUncompress = true;
  @override
  String? userAgent;
  @override
  int? maxConnectionsPerHost;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final actifs = FauxServeurPrestige._actifs;
    final s = actifs[url.host];
    // Adresse inconnue : notée chez le serveur principal (ANO-08 : adresses refusées comprises).
    (s ?? actifs[FauxServeurPrestige.hoteMemoire] ?? (actifs.isEmpty ? null : actifs.values.first))?.tentatives.add(url);
    if (s == null || s.coupe) {
      throw SocketException('Connection refused', osError: const OSError('Connection refused', 111), address: InternetAddress.loopbackIPv4, port: url.port);
    }
    if (s.certificatRefuse && url.scheme == 'https') {
      throw const HandshakeException('Handshake error in client', OSError('CERTIFICATE_VERIFY_FAILED: self signed certificate(handshake.cc:393)', 0));
    }
    return _FauxRequete(s, method, url);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('HttpClient en mémoire : ${invocation.memberName}');
}

class _Entetes implements HttpHeaders {
  final Map<String, List<String>> valeurs = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) => valeurs[name.toLowerCase()] = ['$value'];
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) => (valeurs[name.toLowerCase()] ??= []).add('$value');
  @override
  String? value(String name) => valeurs[name.toLowerCase()]?.join(', ');
  @override
  List<String>? operator [](String name) => valeurs[name.toLowerCase()];
  @override
  void forEach(void Function(String name, List<String> values) action) => valeurs.forEach(action);
  @override
  void remove(String name, Object value) => valeurs[name.toLowerCase()]?.remove('$value');
  @override
  void removeAll(String name) => valeurs.remove(name.toLowerCase());
  @override
  ContentType? contentType;
  @override
  int contentLength = -1;
  @override
  bool chunkedTransferEncoding = false;
  @override
  bool persistentConnection = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FauxRequete implements HttpClientRequest {
  final FauxServeurPrestige serveur;
  @override
  final String method;
  @override
  final Uri uri;
  _FauxRequete(this.serveur, this.method, this.uri);

  @override
  final HttpHeaders headers = _Entetes();
  final _corps = BytesBuilder();
  final _fin = Completer<HttpClientResponse>();
  bool _abandon = false;

  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;
  @override
  bool bufferOutput = true;
  @override
  int contentLength = -1;
  @override
  Encoding encoding = utf8;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final b in stream) {
      _corps.add(b);
    }
  }

  @override
  void add(List<int> data) => _corps.add(data);
  @override
  void write(Object? object) => _corps.add(utf8.encode('$object'));

  @override
  Future<HttpClientResponse> get done => _fin.future;

  @override
  Future<HttpClientResponse> close() {
    if (!_fin.isCompleted) _envoyer();
    return _fin.future;
  }

  Future<void> _envoyer() async {
    try {
      final octets = _corps.takeBytes();
      final entetes = <String, String>{};
      headers.forEach((k, v) => entetes[k.toLowerCase()] = v.join(','));
      final r = RequeteRecue(method, uri.path, uri.queryParameters, utf8.decode(octets, allowMalformed: true), headers.value('cookie') ?? '',
          autorisation: headers.value('authorization') ?? '', clientRef: headers.value('x-client-ref') ?? '',
          utilisateur: headers.value('x-prestige-utilisateur') ?? '', poste: headers.value('x-poste') ?? '',
          octets: octets, cible: uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path, entetes: entetes);
      final rep = await serveur._traiterMemoire(r);
      if (rep.delai > Duration.zero) await Future<void>.delayed(rep.delai);
      if (serveur.coupe) throw const SocketException('Connection reset by peer');
      if (_abandon || _fin.isCompleted) return;
      _fin.complete(_FauxReponse(rep));
    } catch (e, st) {
      if (!_fin.isCompleted) _fin.completeError(e, st);
    }
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    _abandon = true;
    if (!_fin.isCompleted) _fin.completeError(exception ?? const HttpException('Requête abandonnée'), stackTrace);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('HttpClientRequest en mémoire : ${invocation.memberName}');
}

class _FauxReponse extends Stream<List<int>> implements HttpClientResponse {
  final ReponseLocale rep;
  late final List<int> _octets;
  @override
  final HttpHeaders headers = _Entetes();

  _FauxReponse(this.rep) {
    _octets = utf8.encode(rep.texte);
    headers.set('content-type', rep.typeContenu);
    rep.entetes.forEach((k, v) {
      if (k.toLowerCase() != 'content-type') headers.add(k, v);
    });
  }

  @override
  int get statusCode => rep.statut;
  @override
  String get reasonPhrase => rep.statut == 200 ? 'OK' : 'Statut ${rep.statut}';
  @override
  int get contentLength => _octets.length;
  @override
  bool get isRedirect => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  X509Certificate? get certificate => null;
  @override
  bool get persistentConnection => true;
  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;
  @override
  List<Cookie> get cookies => const [];

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    final coupe = rep.coupeeApres;
    if (coupe == null || coupe >= _octets.length) {
      return Stream<List<int>>.fromIterable([Uint8List.fromList(_octets)]).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
    }
    // Réponse tronquée : une partie du corps, puis la connexion se ferme (comme dart:io).
    Stream<List<int>> tronquee() async* {
      yield Uint8List.fromList(_octets.sublist(0, coupe));
      throw const HttpException('Connection closed while receiving data');
    }

    return tronquee().listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('HttpClientResponse en mémoire : ${invocation.memberName}');
}
