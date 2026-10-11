// lib/rh/rh_models.dart
// Pointage RH (présence des employés) — modèles et règles pures, sans réseau ni écran.
//
// Deux voies, sur l'API EXISTANTE de Prestige (aucune modification du serveur) :
// - voie A : l'employé pointe avec SON téléphone (API `v1/mobile`, jeton Bearer, QR / GPS) ;
// - voie B : terminal commun avec lecture de badge (API `v1/rh`, session de l'appli, droit P_SM_RH).
// À ne pas confondre avec le « Pointage BL Stock » (contrôle des quantités) ni avec le pointage local
// par empreinte / PIN (lib/pointage) : ces modules restent inchangés.
import 'package:intl/intl.dart';

/// Sens d'un pointage, tel que Prestige l'écrit (`ENTREE` / `SORTIE`).
enum SensPointage { entree, sortie }

extension SensPointageInfo on SensPointage {
  String get code => this == SensPointage.entree ? 'ENTREE' : 'SORTIE';
  String get label => this == SensPointage.entree ? 'Entrée' : 'Sortie';
  String get majuscules => this == SensPointage.entree ? 'ENTRÉE' : 'SORTIE';
  SensPointage get inverse => this == SensPointage.entree ? SensPointage.sortie : SensPointage.entree;
}

/// `ENTREE` / `SORTIE` (casse indifférente) ; null sinon (sens inconnu).
SensPointage? sensDepuisCode(Object? v) => switch ('${v ?? ''}'.trim().toUpperCase()) {
      'ENTREE' || 'ENTRÉE' => SensPointage.entree,
      'SORTIE' => SensPointage.sortie,
      _ => null,
    };

/// Sens proposé : l'inverse du dernier pointage connu (entrée s'il n'y en a pas, ou s'il est de sens inconnu).
SensPointage sensPropose(SensPointage? dernier) => dernier == SensPointage.entree ? SensPointage.sortie : SensPointage.entree;

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

// ---------------------------------------------------------------------------
// Voie A : session du téléphone (POST v1/mobile/connexion, GET v1/mobile/moi)
// ---------------------------------------------------------------------------

/// Préfixe du contenu du QR affiché à l'officine (util.mobile.CodePointage.PREFIXE côté serveur).
const String prefixeQrPointage = 'PRESTIGE-POINTAGE:';

/// Le texte scanné est-il un QR de pointage Prestige ? (casse et espaces indifférents, comme le serveur.)
bool estQrPointage(String brut) => brut.trim().toUpperCase().startsWith(prefixeQrPointage);

/// Code saisi à la main (6 caractères affichés sous le QR) → contenu envoyé au serveur.
/// Le serveur accepte le code avec ou sans préfixe ; on envoie le texte brut tel quel s'il a le préfixe.
String codePointagePourEnvoi(String saisi) {
  final t = saisi.trim();
  if (estQrPointage(t)) return t;
  return t.toUpperCase().replaceAll(' ', '');
}

class SessionMobile {
  final String jeton;
  final DateTime? expiration;
  final String utilisateurId;
  final String login;
  final String nom;

  /// Employé rattaché au compte (null : pas de pointage possible).
  final String? employeId;
  final String employeMatricule;
  final String employeNom;
  final bool droitPointage;
  final bool droitPhotos;

  /// Ce que l'officine exige au pointage.
  final bool qr;
  final bool gps;

  const SessionMobile({
    required this.jeton,
    this.expiration,
    this.utilisateurId = '',
    this.login = '',
    this.nom = '',
    this.employeId,
    this.employeMatricule = '',
    this.employeNom = '',
    this.droitPointage = false,
    this.droitPhotos = false,
    this.qr = true,
    this.gps = false,
  });

  bool get aEmploye => employeId != null && employeId!.isNotEmpty;

  /// Pointage proposé : employé rattaché ET pointage autorisé par l'officine.
  bool get peutPointer => aEmploye && droitPointage;

  bool expireA(DateTime maintenant) => expiration != null && !maintenant.isBefore(expiration!);

  /// Réponse de `connexion` (avec le jeton) ou de `moi` (sans : on garde [jeton] et [expiration]).
  factory SessionMobile.fromJson(Map<String, dynamic> j, {String? jeton, DateTime? expiration}) {
    final u = j['utilisateur'] is Map ? Map<String, dynamic>.from(j['utilisateur'] as Map) : const <String, dynamic>{};
    final e = j['employe'] is Map ? Map<String, dynamic>.from(j['employe'] as Map) : null;
    final d = j['droits'] is Map ? Map<String, dynamic>.from(j['droits'] as Map) : const <String, dynamic>{};
    final p = j['pointage'] is Map ? Map<String, dynamic>.from(j['pointage'] as Map) : const <String, dynamic>{};
    return SessionMobile(
      jeton: jeton ?? _s(j['jeton']),
      expiration: expiration ?? DateTime.tryParse(_s(j['expiration'])),
      utilisateurId: _s(u['id']),
      login: _s(u['login']),
      nom: _s(u['nom']).trim(),
      employeId: e == null || _s(e['id']).isEmpty ? null : _s(e['id']),
      employeMatricule: _s(e?['matricule']),
      employeNom: _s(e?['nom']).trim(),
      droitPointage: d['pointage'] == true,
      droitPhotos: d['photos'] == true,
      qr: p['qr'] != false,
      gps: p['gps'] == true,
    );
  }

  /// Reprise depuis le stockage sûr (le jeton y est rangé avec le reste).
  Map<String, dynamic> toJson() => {
        'jeton': jeton,
        'expiration': expiration?.toUtc().toIso8601String(),
        'utilisateur': {'id': utilisateurId, 'login': login, 'nom': nom},
        'employe': employeId == null ? null : {'id': employeId, 'matricule': employeMatricule, 'nom': employeNom},
        'droits': {'pointage': droitPointage, 'photos': droitPhotos},
        'pointage': {'qr': qr, 'gps': gps},
      };

  /// Réglages et droits relus (`moi`) : le jeton et son échéance ne changent pas.
  SessionMobile avec(SessionMobile moi) => SessionMobile.fromJson(moi.toJson(), jeton: jeton, expiration: expiration);
}

/// Ligne de `GET v1/mobile/pointages` (16 dernières heures, toutes sources).
class PointageMobile {
  final String heure;
  final SensPointage? sens;
  final String source;
  const PointageMobile({required this.heure, this.sens, this.source = ''});

  factory PointageMobile.fromJson(Map<String, dynamic> j) =>
      PointageMobile(heure: _s(j['heure']), sens: sensDepuisCode(j['sens']), source: _s(j['source']));

  String get sourceLabel => switch (source.toUpperCase()) {
        'MOBILE' => 'téléphone',
        'POINTEUSE' => 'pointeuse',
        'MANUEL' => 'saisie manuelle',
        '' => '',
        _ => source.toLowerCase(),
      };
}

/// Position envoyée avec le pointage (degrés décimaux, précision en mètres).
class PositionPointage {
  final double latitude;
  final double longitude;
  final double? precision;
  const PositionPointage(this.latitude, this.longitude, [this.precision]);
}

// ---------------------------------------------------------------------------
// Voie B : employés (GET v1/rh/employes), présence (GET v1/rh/presence)
// ---------------------------------------------------------------------------

class EmployeRh {
  final String id;
  final String matricule;
  final String badge;
  final String nom;
  final String prenoms;
  final String poste;
  final String statut;

  const EmployeRh({
    required this.id,
    this.matricule = '',
    this.badge = '',
    this.nom = '',
    this.prenoms = '',
    this.poste = '',
    this.statut = 'ACTIF',
  });

  factory EmployeRh.fromJson(Map<String, dynamic> j) => EmployeRh(
        id: _s(j['id']),
        matricule: _s(j['matricule']),
        badge: _s(j['badge']),
        nom: _s(j['nom']),
        prenoms: _s(j['prenoms']),
        poste: _s(j['poste']),
        statut: _s(j['statut']).isEmpty ? 'ACTIF' : _s(j['statut']),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'matricule': matricule, 'badge': badge, 'nom': nom, 'prenoms': prenoms, 'poste': poste, 'statut': statut};

  bool get actif => statut.toUpperCase() == 'ACTIF';
  String get nomComplet => [nom, prenoms].where((s) => s.trim().isNotEmpty).join(' ').trim();

  /// « Bonjour <Prénom> » : premier prénom, sinon le nom.
  String get prenomAffiche {
    final p = prenoms.trim().split(RegExp(r'\s+')).first;
    return p.isNotEmpty ? p : nom.trim();
  }
}

/// Badge lu (clavier / scan / NFC) → clé de comparaison : comme le serveur (trim + majuscules),
/// sans caractères de contrôle (Entrée, tabulation du lecteur).
String normaliserBadge(String brut) => brut.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim().toUpperCase();

/// Employé ACTIF du badge (prioritaire) ou du matricule lu ; null si inconnu.
EmployeRh? employePourBadge(Iterable<EmployeRh> employes, String lu) {
  final c = normaliserBadge(lu);
  if (c.isEmpty) return null;
  for (final e in employes) {
    if (e.actif && e.badge.trim().isNotEmpty && normaliserBadge(e.badge) == c) return e;
  }
  for (final e in employes) {
    if (e.actif && e.matricule.trim().isNotEmpty && normaliserBadge(e.matricule) == c) return e;
  }
  return null;
}

/// Pointage du jour (`pointages` de GET v1/rh/presence).
class PointageJourRh {
  final String id;
  final String employeId;

  /// « yyyy-MM-dd HH:mm » (heure du serveur).
  final String horodatage;
  final SensPointage? sens;
  final String source;
  final String motif;
  const PointageJourRh({this.id = '', required this.employeId, required this.horodatage, this.sens, this.source = '', this.motif = ''});

  factory PointageJourRh.fromJson(Map<String, dynamic> j) => PointageJourRh(
        id: _s(j['id']),
        employeId: _s(j['employeId']),
        horodatage: _s(j['horodatage']),
        sens: sensDepuisCode(j['sens']),
        source: _s(j['source']),
        motif: _s(j['motif']),
      );

  DateTime? get at => DateTime.tryParse(horodatage.replaceFirst(' ', 'T'));
  String get heure => horodatage.length >= 16 ? horodatage.substring(11, 16) : horodatage;
}

/// Ligne de présence (commonTasks.dto.RhPresenceDTO).
class PresenceRh {
  final String employeId;
  final String employe;
  final String matricule;
  final String jour;
  final String prevu;
  final String entree;
  final String sortie;
  final int minutesPrevues;
  final int minutesPresence;
  final int retard;
  final int departAnticipe;
  final int heuresSup;
  final String absence;
  final String anomalies;
  final String pointages;

  const PresenceRh({
    required this.employeId,
    this.employe = '',
    this.matricule = '',
    this.jour = '',
    this.prevu = '',
    this.entree = '',
    this.sortie = '',
    this.minutesPrevues = 0,
    this.minutesPresence = 0,
    this.retard = 0,
    this.departAnticipe = 0,
    this.heuresSup = 0,
    this.absence = '',
    this.anomalies = '',
    this.pointages = '',
  });

  factory PresenceRh.fromJson(Map<String, dynamic> j) => PresenceRh(
        employeId: _s(j['employeId']),
        employe: _s(j['employe']).trim(),
        matricule: _s(j['matricule']),
        jour: _s(j['jour']),
        prevu: _s(j['prevu'] ?? j['prevuTexte']),
        entree: _s(j['entree']),
        sortie: _s(j['sortie']),
        minutesPrevues: _i(j['minutesPrevues']),
        minutesPresence: _i(j['minutesPresence']),
        retard: _i(j['retard']),
        departAnticipe: _i(j['departAnticipe']),
        heuresSup: _i(j['heuresSup']),
        absence: _s(j['absence']),
        anomalies: _s(j['anomalies']),
        pointages: _s(j['pointages']),
      );

  bool get present => entree.isNotEmpty;
  bool get enRetard => retard > 0;
  bool get absent => anomalies.toUpperCase().contains('ABSENT');

  /// Anomalies en clair (codes du serveur séparés par des virgules ou des espaces).
  List<String> get anomaliesLisibles => [
        for (final a in anomalies.split(RegExp(r'[,;]+')).where((a) => a.trim().isNotEmpty)) anomalieLisible(a),
      ];
}

String anomalieLisible(String code) => switch (code.trim().toUpperCase()) {
      'ABSENT' => 'absent (non justifié)',
      'DOUBLON' => 'doublon',
      'DEUX_ENTREES' => 'deux entrées de suite',
      'SORTIE_SANS_ENTREE' => 'sortie sans entrée',
      'ENTREE_SANS_SORTIE' => 'entrée sans sortie',
      'POINTAGE_EN_CONGE' => 'pointage pendant une absence',
      'HORS_PLANNING' => 'pointé hors planning',
      'JOURNEE_LONGUE' => 'journée anormalement longue',
      final c => c.toLowerCase().replaceAll('_', ' '),
    };

/// « 1 h 18 » / « 12 min ».
String dureeLisible(int minutes) {
  if (minutes <= 0) return '0 min';
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

/// Dernier sens connu de l'employé ce jour-là (pointages du serveur, dans l'ordre).
SensPointage? dernierSensDuJour(Iterable<PointageJourRh> pointages, String employeId) {
  PointageJourRh? dernier;
  for (final p in pointages) {
    if (p.employeId != employeId) continue;
    if (dernier == null || p.horodatage.compareTo(dernier.horodatage) >= 0) dernier = p;
  }
  return dernier?.sens;
}

// ---------------------------------------------------------------------------
// Voie B : pointage par badge (enregistré en ligne ou mis en file hors ligne)
// ---------------------------------------------------------------------------

enum StatutPointageBadge { enAttente, envoye, dejaApplique, refuse, exclu }

extension StatutPointageBadgeInfo on StatutPointageBadge {
  String get label => switch (this) {
        StatutPointageBadge.enAttente => 'En attente d\'envoi',
        StatutPointageBadge.envoye => 'Enregistré',
        StatutPointageBadge.dejaApplique => 'Déjà enregistré',
        StatutPointageBadge.refuse => 'Refusé par le serveur',
        StatutPointageBadge.exclu => 'Non envoyé (décoché)',
      };
  bool get termine => this != StatutPointageBadge.enAttente;
}

final DateFormat _jourFmt = DateFormat('yyyy-MM-dd');
final DateFormat _heureFmt = DateFormat('HH:mm');

class PointageBadge {
  /// Identifiant local (file hors ligne, anomalies).
  final String id;
  final String employeId;
  final String employeNom;

  /// Heure de LECTURE du badge sur le terminal (envoyée telle quelle, même des heures plus tard).
  final DateTime lu;
  final SensPointage sens;
  final String motif;
  final StatutPointageBadge statut;
  final String message;
  final bool traitee;

  /// Saisi hors ligne (mis en file) plutôt qu'enregistré tout de suite.
  final bool horsLigne;

  const PointageBadge({
    required this.id,
    required this.employeId,
    this.employeNom = '',
    required this.lu,
    required this.sens,
    required this.motif,
    this.statut = StatutPointageBadge.enAttente,
    this.message = '',
    this.traitee = false,
    this.horsLigne = false,
  });

  String get jour => _jourFmt.format(lu);
  String get heure => _heureFmt.format(lu);

  /// Corps de POST v1/rh/pointages.
  Map<String, dynamic> get corps => {'employeId': employeId, 'jour': jour, 'heure': heure, 'sens': sens.code, 'motif': motif};

  PointageBadge copie({StatutPointageBadge? statut, String? message, bool? traitee, SensPointage? sens}) => PointageBadge(
        id: id,
        employeId: employeId,
        employeNom: employeNom,
        lu: lu,
        sens: sens ?? this.sens,
        motif: motif,
        statut: statut ?? this.statut,
        message: message ?? this.message,
        traitee: traitee ?? this.traitee,
        horsLigne: horsLigne,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeId': employeId,
        'employeNom': employeNom,
        'lu': lu.toIso8601String(),
        'sens': sens.code,
        'motif': motif,
        'statut': statut.name,
        'message': message,
        'traitee': traitee,
        'horsLigne': horsLigne,
      };

  factory PointageBadge.fromJson(Map<String, dynamic> j) => PointageBadge(
        id: _s(j['id']),
        employeId: _s(j['employeId']),
        employeNom: _s(j['employeNom']),
        lu: DateTime.tryParse(_s(j['lu'])) ?? DateTime.fromMillisecondsSinceEpoch(0),
        sens: sensDepuisCode(j['sens']) ?? SensPointage.entree,
        motif: _s(j['motif']),
        statut: StatutPointageBadge.values.asNameMap()[_s(j['statut'])] ?? StatutPointageBadge.enAttente,
        message: _s(j['message']),
        traitee: j['traitee'] == true,
        horsLigne: j['horsLigne'] == true,
      );
}

/// Motif imposé par le serveur pour un pointage hors pointeuse : « Badge terminal <nom du terminal> ».
String motifTerminal(String nomTerminal) {
  final n = nomTerminal.trim();
  final m = 'Badge terminal ${n.isEmpty ? 'Prestige Mobile' : n}';
  return m.length > 250 ? m.substring(0, 250) : m;
}

/// Refus « un pointage existe déjà à cette heure » (INSERT IGNORE du serveur, même minute) : déjà appliqué.
bool estDoublonServeur(String message) {
  final m = message.toLowerCase();
  return m.contains('existe déjà') || m.contains('existe deja');
}
