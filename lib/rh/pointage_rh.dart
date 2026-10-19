// lib/rh/pointage_rh.dart
// Module « Pointage RH » : branchement sur l'appli et logique de la voie B (terminal commun + badge).
//
// Voie B, en ligne : badge → employé (copie locale) → sens proposé (inverse du dernier pointage du jour
// connu : présence du serveur + lectures du terminal) → POST v1/rh/pointages avec l'heure de LECTURE.
// Anti double lecture : le même employé relu moins de 2 minutes après n'est pas renvoyé ; message clair
// « Awa, vous avez déjà pointé (ENTRÉE à 08:02) » (information, orange).
// Doublon du serveur (même minute : « existe déjà ») : déjà enregistré, sans erreur (idempotent), même message.
// Hors ligne (ou serveur injoignable) : pointage mis en FILE persistante avec l'heure de lecture,
// envoyé au retour après confirmation (liste décochable) ; refus du serveur → rapport d'anomalies
// commun ([AnomalieSourceListe]) ; chaque étape notée dans le journal du terminal.
// Session Prestige expirée (401) : le pointage n'est JAMAIS perdu — gardé en file, envoyé après reconnexion.
// Badge inconnu en ligne : la copie des employés est relue (employé créé depuis l'ouverture du terminal).
// Photo de contrôle (badge, jamais l'empreinte) : prise par la caméra frontale avant l'enregistrement, gardée sur le
// terminal et liée au pointage par son identifiant — voir photo_controle.dart.
// 4.3.0 (réponse du serveur du 15/10/2026, demande 31) : le pointage part avec son identifiant (`id`, le même dans
// la file hors ligne : un renvoi répond `deja:true`, rien n'est créé deux fois) et son contrôle (`controle`), puis
// la photo est envoyée (POST rh/pointages/{id}/photo) une fois le pointage enregistré ; photo non envoyée (réseau)
// → réessayée au prochain envoi ; route absente (ancien serveur, 404 / 405) → plus d'essai pendant la session, la
// photo reste sur le terminal comme avant. Jamais bloquant pour le pointage.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/mobile_api.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/rh/rh_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';

/// Accès du compte connecté au terminal de pointage (voie B).
enum AccesRh {
  /// Pas encore vérifié.
  inconnu,

  /// Droit P_SM_RH présent.
  autorise,

  /// Compte sans le droit RH (ou session expirée) : entrée masquée / expliquée.
  refuse,

  /// Version du serveur sans les routes RH (404).
  absent,
}

/// Résultat de la lecture d'un badge.
sealed class LectureBadge {
  const LectureBadge();
}

class BadgeInconnu extends LectureBadge {
  final String code;
  const BadgeInconnu(this.code);
}

/// Même badge relu moins de 2 minutes après : aucun nouveau pointage, « vous avez déjà pointé ».
class BadgeIgnore extends LectureBadge {
  final EmployeRh employe;

  /// « Awa, vous avez déjà pointé (ENTRÉE à 08:02) ».
  final String message;

  /// Sens et heure du pointage déjà fait (sens inconnu si l'enregistrement est encore en cours).
  final SensPointage? sens;
  final DateTime? at;
  const BadgeIgnore(this.employe, this.message, {this.sens, this.at});
}

/// Employé reconnu : sens proposé, à confirmer (ou corriger) sur l'écran de confirmation.
class BadgeAConfirmer extends LectureBadge {
  final EmployeRh employe;
  final SensPointage sens;
  final DateTime lu;

  /// Moyen d'identification (motif « Badge terminal … » ou « Empreinte terminal … »).
  final MoyenIdentification moyen;
  const BadgeAConfirmer(this.employe, this.sens, this.lu, [this.moyen = MoyenIdentification.scan]);
}

/// Issue d'un enregistrement de pointage par badge.
enum IssueBadge { enregistre, dejaEnregistre, refuse, enFile }

/// Confirmations affichées à l'employé (capture seule) : où en est l'envoi à Prestige.
const String etatEnvoyePrestige = 'Envoyé à Prestige ✓';
const String etatEnAttenteEnvoi = 'En attente d\'envoi (hors ligne)';
const String etatRefusPrestige = 'Refusé par Prestige';

/// Message d'un pointage gardé faute de session Prestige (401) : envoyé après reconnexion de l'application.
String messageSessionExpireeFile(String heure) =>
    'Session Prestige expirée : pointage gardé sur le terminal ($heure), envoyé après reconnexion de l\'application.';

class ResultatBadge {
  final IssueBadge issue;
  final String message;
  final PointageBadge pointage;
  const ResultatBadge(this.issue, this.message, this.pointage);
  bool get accepte => issue != IssueBadge.refuse;
}

/// Bilan d'un envoi de la file.
class BilanEnvoiRh {
  final int envoyes;
  final int dejaAppliques;
  final int refuses;
  final bool interrompu;

  /// Session Prestige expirée (401) : envoi arrêté, pointages restants gardés en attente.
  final bool sessionExpiree;

  /// 4.3.3 : cause d'une interruption (serveur injoignable ≠ Prestige indisponible).
  final PanneServeur panne;
  const BilanEnvoiRh(
      {this.envoyes = 0, this.dejaAppliques = 0, this.refuses = 0, this.interrompu = false, this.sessionExpiree = false, this.panne = PanneServeur.injoignable});
  String get message => [
        '$envoyes pointage(s) envoyé(s) à Prestige',
        if (dejaAppliques > 0) '$dejaAppliques déjà enregistré(s)',
        if (refuses > 0) '$refuses refusé(s) (voir les anomalies)',
        if (interrompu && !sessionExpiree) 'envoi interrompu : ${MessagesServeur.titre(panne).toLowerCase()}',
        if (sessionExpiree) 'session Prestige expirée : reconnectez l\'application, les autres restent en attente',
      ].join(' · ');
}

class PointageRh extends ChangeNotifier implements AnomalieSourceListe, CatalogueExtension {
  final RhStore store;
  RhServeur? serveur;
  MobileApi? mobile;

  /// Identification sur le terminal (empreinte Sunmi, NFC, coffre des empreintes).
  IdentificationEmploye? identification;

  /// Photo de contrôle au pointage par badge (caméra frontale, registre du terminal) ; null : pas de photo.
  PhotoControle? photos;
  final DateTime Function() _clock;

  /// Le serveur est-il considéré hors ligne ? (surveillance du serveur de l'appli par défaut).
  bool Function() horsLigne;

  /// Nom du terminal (motif « Badge terminal <nom> ») ; par défaut celui du journal du terminal.
  String Function() nomTerminal;
  JournalTerminal Function() journal;

  /// Délai de l'anti double lecture.
  static const Duration antiDoubleLecture = Duration(minutes: 2);

  PointageRh({
    RhStore? store,
    this.serveur,
    this.mobile,
    this.identification,
    this.photos,
    DateTime Function()? clock,
    bool Function()? horsLigne,
    String Function()? nomTerminal,
    JournalTerminal Function()? journal,
  })  : store = store ?? MemoryRhStore(),
        _clock = clock ?? DateTime.now,
        horsLigne = horsLigne ?? (() => HorsLigne.instance.offline),
        nomTerminal = nomTerminal ?? _nomTerminalJournal,
        journal = journal ?? (() => JournalTerminal.instance);

  static String _nomTerminalJournal() {
    final j = JournalTerminal.instance;
    return [j.terminalNom, j.terminalId].where((s) => s.trim().isNotEmpty).join(' ').trim();
  }

  /// Copie SQLite dans le fichier du catalogue (repli mémoire si ce n'est pas SQLite).
  factory PointageRh.forStore(LocalStore local) => PointageRh(store: local is SqfliteLocalStore ? SqfliteRhStore(local) : MemoryRhStore());

  static PointageRh? _instance;

  /// Instance de l'appli (remplaçable dans les tests).
  static PointageRh get instance => _instance ??= PointageRh.forStore(HorsLigne.instance.store);
  static set instance(PointageRh? v) => _instance = v;

  DateTime get now => _clock();

  // ---------------------------------------------------------------------------
  // Branchement sur l'appli
  // ---------------------------------------------------------------------------

  HorsLigne? _attache;
  String _baseUrl = '';

  /// Copie des employés ajoutée à la mise à jour de la copie hors ligne ; anomalies dans le rapport commun ;
  /// au retour du serveur, la file des pointages est signalée (confirmation avant envoi).
  /// La copie des employés n'est ajoutée qu'une fois le terminal ouvert avec le droit RH sur cet appareil :
  /// les autres appareils n'envoient aucune requête RH de plus.
  void attach(HorsLigne hl) {
    if (!sourcesAnomaliesCommunes.contains(this)) sourcesAnomaliesCommunes.add(this);
    if (identical(_attache, hl)) return;
    _attache?.monitor.removeListener(_onMonitor);
    _attache = hl;
    hl.monitor.addListener(_onMonitor);
    _autoriseMemorise().then((v) {
      if (v) _activerCopie();
    });
  }

  void _activerCopie() {
    final hl = _attache;
    if (hl != null && !hl.sync.extensions.contains(this)) hl.sync.extensions.add(this);
  }

  Future<bool> _autoriseMemorise() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_prefAutorise) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Même adresse que l'appli : session (cookies) pour `v1/rh`, client séparé (Bearer) pour `v1/mobile`.
  void bind(ApiService api) {
    _baseUrl = api.dio.options.baseUrl;
    serveur ??= DioRhServeur(() => _baseUrl);
    identification ??= IdentificationEmploye();
    photos ??= PhotoControle.instance ??= PhotoControle();
    // Pointages par badge sans photo : signalés dans le rapport d'anomalies commun.
    final reg = photos!.registre;
    if (!sourcesAnomaliesCommunes.contains(reg)) sourcesAnomaliesCommunes.add(reg);
    // Purge automatique des photos au-delà de la durée de conservation (au démarrage, puis à chaque ouverture).
    unawaited(reg.charger().catchError((_) {}));
    mobile ??= MobileApi(
      transport: DioTransportMobile(() => _baseUrl),
      // 4.6.0 (demande 51) : « Mon pointage » sous la session de l'application quand le serveur a v1/rh/moi.
      transportSession: TransportSessionRh(() => serveur is RhRequete ? serveur as RhRequete : null),
      appareil: appareilMobile,
      nomAppareil: () => JournalTerminal.instance.terminalNom.trim().isEmpty ? 'Prestige Mobile' : JournalTerminal.instance.terminalNom.trim(),
    );
  }

  /// Identifiant stable de l'appareil : celui du journal du terminal (créé une fois, gardé sur l'appareil).
  static String appareilMobile() {
    final id = JournalTerminal.instance.terminalId.trim();
    return id.isEmpty || id == 'terminal' ? 'prestige-mobile' : id;
  }

  EtatServeur? _etatPrecedent;

  /// Retour du serveur : demande de confirmation si des pointages attendent (écrans abonnés).
  void _onMonitor() {
    final e = _attache?.monitor.etat;
    final avant = _etatPrecedent;
    _etatPrecedent = e;
    if (e == EtatServeur.enLigne && avant != null && avant != EtatServeur.enLigne && enAttente > 0) {
      _confirmationDemandee = true;
      notifyListeners();
    }
  }

  bool _confirmationDemandee = false;

  /// Le serveur est revenu et des pointages attendent : l'écran ouvert propose l'envoi.
  bool get confirmationDemandee => _confirmationDemandee;
  void confirmationVue() => _confirmationDemandee = false;

  // ---------------------------------------------------------------------------
  // Accès (droit P_SM_RH), employés
  // ---------------------------------------------------------------------------

  AccesRh _acces = AccesRh.inconnu;

  /// 4.6.0 (demande 52) : `gerer` de GET v1/rh/droits (droit P_SM_RH) ; null : serveur qui ne l'envoie pas.
  bool? _gerer;
  bool? get gerer => _gerer;
  String _accesMessage = '';
  AccesRh get acces => _acces;
  String get accesMessage => _accesMessage;

  static const _prefAutorise = 'rh_terminal_autorise_v1';

  /// GET rh/droits. Hors ligne : dernier accès confirmé sur cet appareil (copie des employés requise).
  Future<AccesRh> verifierAcces() async {
    final s = serveur;
    if (s == null || horsLigne()) return _accesHorsLigne();
    try {
      final r = await s.get('/rh/droits');
      if (r.status == 404) {
        _poser(AccesRh.absent, 'Le pointage RH n\'existe pas sur cette version du serveur Prestige (routes RH absentes).');
      } else if (r.status == 401) {
        _poser(AccesRh.refuse, 'Session expirée : reconnectez-vous à l\'application.');
      } else if (r.body?['success'] == true) {
        // 4.6.0 (demande 52) : P_RH_POINTER ou P_SM_RH ouvrent le terminal ; « gerer » (P_SM_RH) pour la gestion.
        final g = r.body!['gerer'];
        _gerer = g is bool ? g : null;
        _poser(AccesRh.autorise, '');
        _memoriserAutorise(true);
      } else {
        _poser(AccesRh.refuse, messageRh(r.body, 'Vous n\'avez pas accès aux ressources humaines.'));
        _memoriserAutorise(false);
      }
    } on RhHorsLigne {
      return _accesHorsLigne();
    }
    return _acces;
  }

  Future<AccesRh> _accesHorsLigne() async {
    final autorise = await _autoriseMemorise();
    await chargerEmployes();
    if (autorise && _employes.isNotEmpty) {
      _poser(AccesRh.autorise, 'Hors ligne : copie des employés du ${_employesAt == null ? '?' : HorsLigne.formatDate(_employesAt!)}.');
    } else {
      _poser(AccesRh.inconnu, 'Hors ligne : le terminal de pointage n\'a encore jamais été ouvert en ligne sur cet appareil.');
    }
    return _acces;
  }

  void _poser(AccesRh a, String m) {
    _acces = a;
    _accesMessage = m;
    notifyListeners();
  }

  Future<void> _memoriserAutorise(bool v) async {
    if (v) _activerCopie();
    try {
      await (await SharedPreferences.getInstance()).setBool(_prefAutorise, v);
    } catch (_) {}
  }

  List<EmployeRh> _employes = [];
  DateTime? _employesAt;
  List<EmployeRh> get employes => List.unmodifiable(_employes);
  DateTime? get employesAt => _employesAt;

  Future<void> chargerEmployes() async {
    try {
      _employes = await store.employes();
      _employesAt = await store.employesAt();
    } catch (_) {}
  }

  /// GET rh/employes (actifs) → copie locale. Renvoie un message d'erreur, null si la copie est à jour.
  Future<String?> rafraichirEmployes() async {
    final s = serveur;
    if (s == null) return 'Serveur non configuré.';
    try {
      final r = await s.get('/rh/employes', const {'query': '', 'inactifs': 'false'});
      return _appliquerEmployes(r.status, r.body);
    } on RhHorsLigne catch (e) {
      return '${e.titre} : copie des employés inchangée.';
    }
  }

  Future<String?> _appliquerEmployes(int status, Map<String, dynamic>? b) async {
    if (status == 404) return 'Routes RH absentes sur ce serveur.';
    if (b == null || b['success'] != true || b['data'] is! List) return messageRh(b, 'Liste des employés refusée.');
    final l = [
      for (final x in b['data'] as List)
        if (x is Map) EmployeRh.fromJson(Map<String, dynamic>.from(x)),
    ].where((e) => e.id.isNotEmpty).toList();
    await store.remplacerEmployes(l, _clock());
    _memoriserAutorise(true);
    // Employé devenu inactif (absent de la liste des actifs) : ses empreintes sont supprimées du terminal.
    try {
      final n = await identification?.purgerInactifs(l) ?? 0;
      if (n > 0) {
        journal().noter(
            type: TypeJournal.pointageRh,
            action: 'Empreintes supprimées : $n employé(s) devenu(s) inactif(s)',
            resultat: ResultatJournal.info);
      }
    } catch (_) {}
    await chargerEmployes();
    notifyListeners();
    return null;
  }

  // CatalogueExtension : la copie des employés suit la mise à jour de la copie hors ligne.
  // Sans droit RH ou sans routes RH : rien n'est copié, SANS erreur (la copie du catalogue n'en souffre pas).

  @override
  String get label => 'Employés (pointage RH)';

  @override
  Future<void> sync(CatalogueFetch fetch, void Function(String etape, int done, int? total) progress) async {
    progress(label, 0, null);
    try {
      final b = await fetch('/rh/employes', const {'query': '', 'inactifs': 'false'});
      await _appliquerEmployes(200, b);
    } catch (_) {
      // Compte sans le droit RH, ancienne version du serveur, réseau : copie inchangée.
    }
  }

  @override
  Future<void> clear() async {
    await store.viderEmployes();
    await chargerEmployes();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Présence du jour (sens auto, écran responsable)
  // ---------------------------------------------------------------------------

  /// Dernier pointage connu par employé pour le jour courant (serveur + lectures du terminal).
  final Map<String, ({SensPointage? sens, DateTime at})> _derniers = {};
  String _jourDerniers = '';

  static String jourCle(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _nouveauJour() {
    final j = jourCle(_clock());
    if (j != _jourDerniers) {
      _jourDerniers = j;
      _derniers.clear();
    }
  }

  void _noterDernier(String employeId, SensPointage? sens, DateTime at) {
    final d = _derniers[employeId];
    if (d == null || !at.isBefore(d.at)) _derniers[employeId] = (sens: sens, at: at);
  }

  /// GET rh/presence?jour= (null si refus / réseau : message dans [erreur]).
  Future<({List<PresenceRh> presences, List<PointageJourRh> pointages, String? erreur})> presence(DateTime jour) async {
    final s = serveur;
    if (s == null) return (presences: const <PresenceRh>[], pointages: const <PointageJourRh>[], erreur: 'Serveur non configuré.');
    try {
      final r = await s.get('/rh/presence', {'jour': jourCle(jour)});
      if (r.status == 404) return (presences: const <PresenceRh>[], pointages: const <PointageJourRh>[], erreur: 'Routes RH absentes sur ce serveur.');
      final b = r.body;
      if (b == null || b['success'] != true) {
        return (presences: const <PresenceRh>[], pointages: const <PointageJourRh>[], erreur: messageRh(b, 'Présence refusée par le serveur.'));
      }
      final presences = [
        for (final x in (b['data'] is List ? b['data'] as List : const []))
          if (x is Map) PresenceRh.fromJson(Map<String, dynamic>.from(x)),
      ];
      final pointages = [
        for (final x in (b['pointages'] is List ? b['pointages'] as List : const []))
          if (x is Map) PointageJourRh.fromJson(Map<String, dynamic>.from(x)),
      ];
      if (jourCle(jour) == jourCle(_clock())) {
        _nouveauJour();
        final n = _clock();
        for (final p in pointages) {
          final at = p.at;
          if (at != null && !at.isAfter(n)) _noterDernier(p.employeId, p.sens, at);
        }
      }
      return (presences: presences, pointages: pointages, erreur: null);
    } on RhHorsLigne catch (e) {
      return (presences: const <PresenceRh>[], pointages: const <PointageJourRh>[], erreur: '${e.titre} : présence disponible en ligne uniquement.');
    }
  }

  // ---------------------------------------------------------------------------
  // Lecture du badge
  // ---------------------------------------------------------------------------

  /// Dernière lecture acceptée par employé (anti double lecture).
  final Map<String, DateTime> _lectures = {};

  /// Badge lu (clavier, scanner, caméra, NFC) → employé et sens proposé.
  LectureBadge lire(String brut, {MoyenIdentification moyen = MoyenIdentification.scan}) {
    final e = employePourBadge(_employes, moyen == MoyenIdentification.nfc ? normaliserUidNfc(brut) : brut) ??
        (moyen == MoyenIdentification.nfc ? employePourBadge(_employes, brut) : null);
    if (e == null) return BadgeInconnu(normaliserBadge(brut));
    return lireEmploye(e, moyen: moyen);
  }

  DateTime? _dernierRafraichissement;

  /// Comme [lire] ; badge inconnu EN LIGNE : la copie des employés est relue (au plus une fois par 30 s) puis le
  /// badge relu — un employé créé ou un badge ajouté dans Prestige depuis l'ouverture du terminal est reconnu.
  Future<LectureBadge> lireAvecRafraichissement(String brut, {MoyenIdentification moyen = MoyenIdentification.scan}) async {
    final l = lire(brut, moyen: moyen);
    if (l is! BadgeInconnu || serveur == null || horsLigne()) return l;
    final n = _clock();
    final d = _dernierRafraichissement;
    if (d != null && n.difference(d) < const Duration(seconds: 30)) return l;
    _dernierRafraichissement = n;
    if (await rafraichirEmployes() != null) return l;
    return lire(brut, moyen: moyen);
  }

  /// Employé identifié (empreinte, badge) → sens proposé, avec l'anti double lecture.
  LectureBadge lireEmploye(EmployeRh e, {MoyenIdentification moyen = MoyenIdentification.scan}) {
    final n = _clock();
    _nouveauJour();
    final avant = _lectures[e.id];
    if (avant != null && n.difference(avant) < antiDoubleLecture) {
      // Pointage déjà fait par cette lecture (sens et heure de lecture) ; sens inconnu s'il est encore en cours.
      final d = _derniers[e.id];
      final fait = d != null && !d.at.isBefore(avant) ? d : null;
      final at = fait?.at ?? avant;
      return BadgeIgnore(e, messageDejaPointe(e.prenomAffiche, fait?.sens, _hm(at)), sens: fait?.sens, at: at);
    }
    _lectures[e.id] = n;
    return BadgeAConfirmer(e, sensPropose(_derniers[e.id]?.sens), n, moyen);
  }

  /// Lecture annulée sur l'écran de confirmation : le badge peut être relu tout de suite.
  void annuler(BadgeAConfirmer l) {
    if (_lectures[l.employe.id] == l.lu) _lectures.remove(l.employe.id);
  }

  /// Prénom affiché de l'employé du pointage (copie locale), sinon le nom enregistré.
  String _prenom(PointageBadge p) {
    for (final e in _employes) {
      if (e.id == p.employeId) return e.prenomAffiche;
    }
    return p.employeNom;
  }

  static String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------------------
  // Enregistrement (en ligne) ou mise en file (hors ligne)
  // ---------------------------------------------------------------------------

  List<PointageBadge> _file = [];
  bool _fileChargee = false;
  bool _envoiEnCours = false;
  List<PointageBadge> get file => List.unmodifiable(_file);
  bool get envoiEnCours => _envoiEnCours;
  int get enAttente => _file.where((p) => p.statut == StatutPointageBadge.enAttente).length;
  List<PointageBadge> get aEnvoyer => _file.where((p) => p.statut == StatutPointageBadge.enAttente).toList();

  Future<void> chargerFile() async {
    if (_fileChargee) return;
    try {
      _file = await store.pointages();
      _fileChargee = true;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _sauver(PointageBadge p) async {
    final i = _file.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      _file[i] = p;
    } else {
      _file.add(p);
    }
    try {
      await store.enregistrer(p);
    } catch (_) {}
    notifyListeners();
  }

  /// Enregistre le pointage confirmé (sens éventuellement corrigé) avec l'heure de LECTURE. [controle] : contrôle
  /// de la photo (demande 31), envoyé avec le pointage.
  Future<ResultatBadge> enregistrer(BadgeAConfirmer l, SensPointage sens, {Map<String, dynamic>? controle}) async {
    await chargerFile();
    final p = PointageBadge(
      id: const Uuid().v4(),
      employeId: l.employe.id,
      employeNom: l.employe.nomComplet,
      lu: DateTime(l.lu.year, l.lu.month, l.lu.day, l.lu.hour, l.lu.minute),
      sens: sens,
      motif: l.moyen.motif(nomTerminal()),
      controle: controle,
    );
    _nouveauJour();
    final precedent = _derniers[l.employe.id];
    _noterDernier(l.employe.id, sens, l.lu);
    final s = serveur;
    if (s == null || horsLigne()) return _mettreEnFile(p);
    try {
      final r = await s.post('/rh/pointages', p.corps);
      if (r.status == 401) {
        // Session de l'application expirée : rien n'est perdu, le pointage attend la reconnexion.
        return _mettreEnFile(p, message: messageSessionExpireeFile(p.heure));
      }
      final res = await _issue(p, r, source: SourceJournal.enLigne);
      if (res.issue == IssueBadge.refuse) {
        // Refus en ligne : affiché tout de suite (pas d'anomalie), relecture possible.
        _lectures.remove(l.employe.id);
        if (precedent == null) {
          _derniers.remove(l.employe.id);
        } else {
          _derniers[l.employe.id] = precedent;
        }
      }
      return res;
    } on RhHorsLigne {
      _attache?.monitor.signalNetworkFailure();
      return _mettreEnFile(p);
    }
  }

  /// Comme [enregistrer], après la photo de contrôle [photo] (attendue, bornée) ; la photo — ou le marquage
  /// « sans photo (motif) » — est rangée dans le registre du terminal, liée au pointage. Jamais bloquant.
  Future<ResultatBadge> enregistrerAvecPhoto(BadgeAConfirmer l, SensPointage sens, {Future<ResultatPhoto>? photo}) async {
    ResultatPhoto? ph;
    if (photo != null) {
      try {
        ph = await photo.timeout(const Duration(seconds: 20));
      } catch (_) {
        ph = const PhotoAbsente(MotifSansPhoto.delaiDepasse);
      }
    }
    final r = await enregistrer(l, sens, controle: ph == null ? null : controlePhoto(ph));
    final reg = photos?.registre;
    if (ph != null && reg != null) {
      try {
        await reg.ajouter(
          id: r.pointage.id,
          employeId: l.employe.id,
          employeNom: l.employe.nomComplet,
          lu: r.pointage.lu,
          sens: sens.label,
          moyen: l.moyen.label,
          resultat: ph,
          envoi: r.pointage.statut.name,
        );
      } catch (_) {}
      // Pointage enregistré par le serveur : envoi de la photo, sans faire attendre l'employé.
      if (ph is PhotoPrise && (r.issue == IssueBadge.enregistre || r.issue == IssueBadge.dejaEnregistre)) {
        envoiPhotos = envoyerPhotos();
      }
    }
    return r;
  }

  // ---------------------------------------------------------------------------
  // Photos de contrôle envoyées au serveur (demande 31)
  // ---------------------------------------------------------------------------

  /// Dernier envoi de photos lancé (tests ; jamais attendu par l'écran de pointage).
  Future<int>? envoiPhotos;
  bool _envoiPhotosEnCours = false;

  /// Adresse du serveur sans la route photo (404 / 405) : plus d'essai pendant la session.
  String? _sansRoutePhoto;

  /// Envoie les photos des pointages enregistrés, pas encore envoyées (au plus [max]) ; renvoie le nombre envoyé.
  /// Jamais d'exception : réseau coupé → arrêt (réessai au prochain envoi), refus → photo marquée « refusée ».
  Future<int> envoyerPhotos({int max = 20}) async {
    final s = serveur, reg = photos?.registre;
    if (s is! RhPhotos || reg == null || _envoiPhotosEnCours || horsLigne()) return 0;
    final cle = _baseUrl.isEmpty ? 'serveur-${identityHashCode(s)}' : _baseUrl;
    if (_sansRoutePhoto == cle) return 0;
    _envoiPhotosEnCours = true;
    var n = 0;
    try {
      for (final p in reg.photosAEnvoyer.take(max)) {
        final jpeg = await reg.image(p.id);
        if (jpeg == null || jpeg.isEmpty) continue;
        final ReponseRh r;
        try {
          r = await (s as RhPhotos).envoyerPhoto(p.id, jpeg, p.lu);
        } on RhHorsLigne {
          break; // réessai au prochain envoi
        }
        if (r.status == 404 || r.status == 405) {
          _sansRoutePhoto = cle; // serveur sans la route : la photo reste sur le terminal, comme avant
          break;
        }
        if (r.status == 401) break; // session expirée : réessai après reconnexion
        if (r.status == 200 && r.body?['success'] == true) {
          await reg.majPhotoServeur(p.id, 'envoyee');
          n++;
          _noterPhoto(p.id, 'Photo de contrôle envoyée à Prestige', ResultatJournal.ok);
        } else if (r.status == 200 || r.status == 400 || r.status == 403 || r.status == 413) {
          // Refus du serveur (pointage inconnu, taille, format, droit) : pas de renvoi en boucle.
          await reg.majPhotoServeur(p.id, 'refusee');
          _noterPhoto(p.id, 'Photo de contrôle refusée par Prestige', ResultatJournal.refus, motif: messageRh(r.body, 'code ${r.status}'));
        } else {
          break; // erreur du serveur (5xx) : réessai au prochain envoi
        }
      }
    } catch (_) {
      // Jamais bloquant.
    } finally {
      _envoiPhotosEnCours = false;
    }
    return n;
  }

  void _noterPhoto(String id, String action, ResultatJournal r, {String motif = ''}) {
    try {
      journal().noter(
        type: TypeJournal.pointageRh,
        action: action,
        refLocale: id.length > 8 ? id.substring(0, 8) : id,
        resultat: r,
        motif: motif,
      );
    } catch (_) {}
  }

  void _majEnvoiPhoto(PointageBadge p) {
    try {
      photos?.registre.majEnvoi(p.id, p.statut.name);
    } catch (_) {}
  }

  Future<ResultatBadge> _mettreEnFile(PointageBadge p0, {String? message}) async {
    final p = PointageBadge.fromJson({...p0.toJson(), 'horsLigne': true});
    await _sauver(p);
    _noter(p, 'Pointage ${p.sens.majuscules} mis en file (${message == null ? 'hors ligne' : 'session expirée'})', ResultatJournal.info,
        source: SourceJournal.horsLigne);
    return ResultatBadge(
        IssueBadge.enFile, message ?? 'Hors ligne : pointage gardé sur le terminal (${p.heure}), envoyé à Prestige au retour du serveur.', p);
  }

  Future<ResultatBadge> _issue(PointageBadge p, ReponseRh r, {required String source}) async {
    final b = r.body;
    final m = messageRh(b, r.status == 401 ? 'Session expirée : reconnectez-vous.' : 'Pointage refusé (${r.status}).');
    // Demande 31 : même identifiant déjà reçu (renvoi après une coupure) → déjà enregistré, rien de créé.
    if (r.status == 200 && b?['success'] == true && b?['deja'] == true) {
      final ok = p.copie(statut: StatutPointageBadge.dejaApplique, message: m);
      if (p.horsLigne) await _sauver(ok);
      _majEnvoiPhoto(ok);
      _noter(ok, 'Pointage ${p.sens.majuscules} déjà enregistré sur le serveur', ResultatJournal.dejaApplique, motif: m, source: source);
      return ResultatBadge(IssueBadge.dejaEnregistre, messageDejaPointe(_prenom(p), p.sens, p.heure), ok);
    }
    if (r.status == 200 && b?['success'] == true) {
      final ok = p.copie(statut: StatutPointageBadge.envoye, message: m);
      if (p.horsLigne) await _sauver(ok);
      _majEnvoiPhoto(ok);
      _noter(ok, 'Pointage ${p.sens.majuscules} enregistré', ResultatJournal.ok, source: source);
      return ResultatBadge(IssueBadge.enregistre, '${p.sens.label} enregistrée à ${p.heure}.', ok);
    }
    if (estDoublonServeur(m)) {
      final ok = p.copie(statut: StatutPointageBadge.dejaApplique, message: m);
      if (p.horsLigne) await _sauver(ok);
      _majEnvoiPhoto(ok);
      _noter(ok, 'Pointage ${p.sens.majuscules} déjà enregistré sur le serveur', ResultatJournal.dejaApplique, motif: m, source: source);
      return ResultatBadge(IssueBadge.dejaEnregistre, messageDejaPointe(_prenom(p), p.sens, p.heure), ok);
    }
    final ko = p.copie(statut: StatutPointageBadge.refuse, message: m);
    if (p.horsLigne) await _sauver(ko);
    _majEnvoiPhoto(ko);
    _noter(ko, 'Pointage ${p.sens.majuscules} refusé', ResultatJournal.refus, motif: m, source: source);
    return ResultatBadge(IssueBadge.refuse, m, ko);
  }

  void _noter(PointageBadge p, String action, ResultatJournal r, {String motif = '', String? source}) {
    try {
      journal().noter(
        type: TypeJournal.pointageRh,
        action: '$action — ${p.employeNom} ${p.jour} ${p.heure}',
        refLocale: p.id.length > 8 ? p.id.substring(0, 8) : p.id,
        resultat: r,
        motif: motif,
        source: source,
      );
    } catch (_) {}
  }

  /// Pointages décochés à la confirmation : jamais envoyés (gardés dans l'historique).
  Future<void> exclure(Iterable<String> ids) async {
    final s = ids.toSet();
    for (final p in List.of(_file)) {
      if (s.contains(p.id) && p.statut == StatutPointageBadge.enAttente) {
        final x = p.copie(statut: StatutPointageBadge.exclu, message: 'Décoché à la confirmation d\'envoi.');
        await _sauver(x);
        _majEnvoiPhoto(x);
        _noter(x, 'Pointage ${p.sens.majuscules} non envoyé (décoché)', ResultatJournal.info, source: SourceJournal.fileHL);
      }
    }
  }

  /// Envoie les pointages en attente [ids] (tous si null), dans l'ordre de lecture.
  Future<BilanEnvoiRh> envoyer({Iterable<String>? ids}) async {
    await chargerFile();
    final s = serveur;
    if (_envoiEnCours || s == null) return const BilanEnvoiRh();
    _envoiEnCours = true;
    _confirmationDemandee = false;
    notifyListeners();
    var envoyes = 0, deja = 0, refus = 0;
    var interrompu = false, session = false;
    var panne = PanneServeur.injoignable;
    final choix = ids?.toSet();
    try {
      for (final p in aEnvoyer) {
        if (choix != null && !choix.contains(p.id)) continue;
        try {
          final r = await s.post('/rh/pointages', p.corps);
          if (r.status == 401) {
            // Session expirée : arrêt, ce pointage et les suivants restent en attente (jamais marqués refusés).
            interrompu = session = true;
            break;
          }
          final res = await _issue(p, r, source: SourceJournal.fileHL);
          switch (res.issue) {
            case IssueBadge.enregistre:
              envoyes++;
            case IssueBadge.dejaEnregistre:
              deja++;
            case IssueBadge.refuse:
              refus++;
            case IssueBadge.enFile:
              break;
          }
        } on RhHorsLigne catch (e) {
          interrompu = true;
          panne = e.panne;
          _attache?.monitor.signalNetworkFailure();
          break;
        }
      }
    } finally {
      _envoiEnCours = false;
      notifyListeners();
    }
    // Photos des pointages enregistrés (demande 31), sans retarder le bilan.
    if (!interrompu) envoiPhotos = envoyerPhotos();
    return BilanEnvoiRh(envoyes: envoyes, dejaAppliques: deja, refuses: refus, interrompu: interrompu, sessionExpiree: session, panne: panne);
  }

  /// Purge de l'historique au-delà de la durée de conservation.
  Future<void> purger(DateTime avant) async {
    try {
      await store.purger(avant);
      _fileChargee = false;
      await chargerFile();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Anomalies (rapport commun)
  // ---------------------------------------------------------------------------

  @override
  String get titreAnomalies => 'POINTAGES RH (BADGE)';

  @override
  List<Anomalie> get anomaliesList => [
        for (final p in _file.reversed)
          if (p.statut == StatutPointageBadge.refuse)
            Anomalie(
              id: 'rh-${p.id}',
              source: 'rh',
              date: p.lu,
              type: 'Pointage ${p.sens.label.toLowerCase()} (badge)',
              reference: '${p.employeNom} · ${p.jour} ${p.heure}',
              motif: p.message,
              traitee: p.traitee,
              operationId: p.id,
            ),
      ];

  @override
  int get anomaliesNonTraitees => _file.where((p) => p.statut == StatutPointageBadge.refuse && !p.traitee).length;

  @override
  Future<List<Anomalie>> anomalies() async {
    await chargerFile();
    return anomaliesList;
  }

  @override
  Future<void> setTraitee(String id, bool traitee) async {
    final pid = id.startsWith('rh-') ? id.substring(3) : id;
    final i = _file.indexWhere((p) => p.id == pid);
    if (i < 0) return;
    await _sauver(_file[i].copie(traitee: traitee));
  }

  @override
  void dispose() {
    _attache?.monitor.removeListener(_onMonitor);
    super.dispose();
  }
}

/// Contrôle envoyé avec un pointage par badge (demande 31) : `{photo: true}` ou `{photo: false, motif: CODE}`.
Map<String, dynamic> controlePhoto(ResultatPhoto ph) => switch (ph) {
      PhotoPrise() => const {'photo': true},
      PhotoAbsente(:final motif) => {'photo': false, 'motif': codeSansPhoto(motif)},
    };

/// Code du motif « sans photo » attendu par le serveur.
String codeSansPhoto(MotifSansPhoto m) => switch (m) {
      MotifSansPhoto.cameraAbsente => 'CAMERA_ABSENTE',
      MotifSansPhoto.permissionRefusee => 'PERMISSION_REFUSEE',
      MotifSansPhoto.erreurCamera => 'ERREUR_CAMERA',
      MotifSansPhoto.delaiDepasse => 'DELAI_DEPASSE',
      MotifSansPhoto.photoIllisible => 'PHOTO_ILLISIBLE',
    };
