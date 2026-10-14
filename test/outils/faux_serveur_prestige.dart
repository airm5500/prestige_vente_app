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
  static Map<String, dynamic> dossierClient() => {
        'success': true,
        'client': {'id': 'C1', 'nom': 'DEMO', 'prenoms': 'Patient Fictif', 'telephone': '0100000000', 'naissance': '1980-01-01', 'age': 46, 'sexe': 'F', 'type': 'STANDARD'},
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
  const publiques = ['/user/auth', '/user/logout', '/licence/find', '/officine', '/app/info'];
  return publiques.any(p.endsWith) || p.contains('/licence/save') || p.contains('/mobile/') || p.contains('/espace-produit/');
}

class FauxServeurPrestige extends ServeurJsonLocal {
  FauxServeurPrestige({this.exigerSession = true, Map<String, String>? comptes})
      : comptes = comptes ?? {DonneesFictives.login: DonneesFictives.motDePasse, DonneesFictives.admin: DonneesFictives.motDePasseAdmin};

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

  static const messageDeconnecte = 'Veuillez vous connecter';

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
    _reseauLocal = true;
    await super.demarrer();
  }

  // ---------------------------------------------------------------------------
  // Traitement
  // ---------------------------------------------------------------------------

  /// Routes par défaut (après les routes scriptées).
  final Map<String, FutureOr<ReponseLocale> Function(RequeteRecue r)> routesParDefaut = {};

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
      'GET /client/C1/dossier': (_) => ReponseLocale(DonneesFictives.dossierClient()),
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

  bool _sessionValide(RequeteRecue r) => r.jsessionid != null && sessions.contains(r.jsessionid);

  @override
  Future<ReponseLocale> repondre(RequeteRecue r) async {
    final rep = await _repondre(r);
    if (latence > Duration.zero && rep.delai == Duration.zero) {
      return ReponseLocale(rep.corps, statut: rep.statut, delai: latence, entetes: rep.entetes);
    }
    return rep;
  }

  Future<ReponseLocale> _repondre(RequeteRecue r) async {
    // Filtre d'authentification : requête refusée AVANT d'être exécutée.
    if (exigerSession && !routePubliquePrestige(r.chemin) && !_sessionValide(r)) {
      refusSession++;
      return refusEn403 ? nonConnecte403 : nonConnecte401;
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
      connexions++;
      return ReponseLocale(DonneesFictives.utilisateur(login), entetes: {'set-cookie': 'JSESSIONID=$id; Path=/prestige; HttpOnly'});
    }
    if (c.endsWith('/user/logout')) {
      if (r.jsessionid != null) sessions.remove(r.jsessionid);
      return const ReponseLocale({'success': true});
    }
    if (r.methode == 'GET' && c.endsWith('/officine')) return ReponseLocale(DonneesFictives.officines());
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
  String get hote => _enMemoire ? '$hoteMemoire:$portMemoire' : super.hote;

  static FauxServeurPrestige? _actif;
  HttpOverrides? _precedent;

  /// Remplace le client HTTP de l'application par un client en mémoire relié à ce serveur (toutes les
  /// instances Dio de l'appli). À appeler dans le test ; [desinstaller] (ou addTearDown) remet l'ancien.
  void installerEnMemoire() {
    _enMemoire = true;
    _precedent = HttpOverrides.current;
    _actif = this;
    HttpOverrides.global = _FauxHttpOverrides();
    // Le client Dio partagé garde son HttpClient : on lui en donne un neuf (créé avec ces overrides).
    DioClient.getClient(base).httpClientAdapter = IOHttpClientAdapter();
  }

  void desinstaller() {
    if (identical(_actif, this)) _actif = null;
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
    final s = FauxServeurPrestige._actif;
    s?.tentatives.add(url);
    if (s == null || s.coupe || url.host != FauxServeurPrestige.hoteMemoire) {
      throw SocketException('Connection refused', osError: const OSError('Connection refused', 111), address: InternetAddress.loopbackIPv4, port: url.port);
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
      final r = RequeteRecue(method, uri.path, uri.queryParameters, utf8.decode(_corps.takeBytes(), allowMalformed: true), headers.value('cookie') ?? '');
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
    final texte = rep.corps is String ? rep.corps as String : jsonEncode(rep.corps);
    _octets = utf8.encode(texte);
    headers.set('content-type', rep.corps is String ? 'text/plain; charset=utf-8' : 'application/json; charset=utf-8');
    rep.entetes.forEach((k, v) => headers.add(k, v));
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
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.fromIterable([Uint8List.fromList(_octets)]).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('HttpClientResponse en mémoire : ${invocation.memberName}');
}
