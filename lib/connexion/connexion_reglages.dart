// lib/connexion/connexion_reglages.dart
// Réglages de l'écran de connexion (nouvelle interface, propres à cet appareil) :
//  - « Connexion rapide par utilisateur » (écran « Qui êtes-vous ? », option C) — désactivée par défaut ;
//  - « Terminal partagé » — désactivé par défaut ; activé : « Rester connecté » est interdit ;
//  - numéro d'assistance (défaut 0708080068), modifiable par l'administrateur.
// Mémoires de l'appareil : nom de l'officine (après une connexion réussie) et 6 derniers utilisateurs
// (identifiant, nom, rôle, date — AUCUN mot de passe ni code).
// Tout est sans effet dans l'ancienne interface (InterfaceVersion désactivée).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class ConnexionConfig {
  static const assistanceParDefaut = '0708080068';

  final bool connexionRapide;
  final bool terminalPartage;
  final String assistance;

  const ConnexionConfig({this.connexionRapide = false, this.terminalPartage = false, this.assistance = assistanceParDefaut});

  /// « Rester connecté » proposé sur cet appareil.
  bool get resterConnecteAutorise => !terminalPartage;

  ConnexionConfig copyWith({bool? connexionRapide, bool? terminalPartage, String? assistance}) => ConnexionConfig(
        connexionRapide: connexionRapide ?? this.connexionRapide,
        terminalPartage: terminalPartage ?? this.terminalPartage,
        assistance: assistance ?? this.assistance,
      );

  Map<String, Object?> toJson() => {'rapide': connexionRapide, 'partage': terminalPartage, 'assistance': assistance};

  factory ConnexionConfig.fromJson(Map<String, dynamic> j) => ConnexionConfig(
        connexionRapide: j['rapide'] == true,
        terminalPartage: j['partage'] == true,
        assistance: (j['assistance'] is String && (j['assistance'] as String).trim().isNotEmpty) ? (j['assistance'] as String).trim() : assistanceParDefaut,
      );
}

class ConnexionReglages {
  ConnexionReglages._();

  static const cle = 'connexion_reglages_v1';
  static const cleOfficine = 'connexion_officine_nom_v1';

  /// Réglages courants (chargés au démarrage).
  static final ValueNotifier<ConnexionConfig> courant = ValueNotifier(const ConnexionConfig());

  /// Nom de l'officine gardé sur l'appareil (vide si jamais connecté).
  static final ValueNotifier<String> officine = ValueNotifier('');

  static Future<ConnexionConfig> charger() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(cle);
      courant.value = s == null ? const ConnexionConfig() : ConnexionConfig.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
      officine.value = prefs.getString(cleOfficine) ?? '';
    } catch (_) {
      courant.value = const ConnexionConfig();
    }
    return courant.value;
  }

  static Future<void> enregistrer(ConnexionConfig c) async {
    courant.value = c;
    try {
      await (await SharedPreferences.getInstance()).setString(cle, jsonEncode(c.toJson()));
    } catch (_) {}
  }

  /// Garde le nom de l'officine reçu du serveur (après une connexion réussie).
  static Future<void> memoriserOfficine(String nom) async {
    final n = nom.trim();
    if (n.isEmpty || n == officine.value) return;
    officine.value = n;
    try {
      await (await SharedPreferences.getInstance()).setString(cleOfficine, n);
    } catch (_) {}
  }
}

/// Un utilisateur récent de l'appareil (aucun secret).
@immutable
class DernierUtilisateur {
  final String login;
  final String nom;
  final String role;
  final DateTime date;

  /// L'utilisateur a refusé la création d'un code PIN personnel (« Ne plus proposer »).
  final bool pinRefuse;

  const DernierUtilisateur({required this.login, required this.nom, required this.role, required this.date, this.pinRefuse = false});

  String get nomAffiche => nom.trim().isEmpty ? login : nom.trim();

  Map<String, Object?> toJson() => {'login': login, 'nom': nom, 'role': role, 'date': date.millisecondsSinceEpoch, 'pinRefuse': pinRefuse};

  static DernierUtilisateur? fromJson(Object? o) {
    if (o is! Map) return null;
    final login = o['login'];
    final date = o['date'];
    if (login is! String || login.trim().isEmpty || date is! int) return null;
    return DernierUtilisateur(
      login: login,
      nom: o['nom'] is String ? o['nom'] as String : '',
      role: o['role'] is String ? o['role'] as String : '',
      date: DateTime.fromMillisecondsSinceEpoch(date),
      pinRefuse: o['pinRefuse'] == true,
    );
  }

  DernierUtilisateur copyWith({bool? pinRefuse}) => DernierUtilisateur(login: login, nom: nom, role: role, date: date, pinRefuse: pinRefuse ?? this.pinRefuse);
}

/// Les 6 derniers utilisateurs de l'appareil, du plus récent au plus ancien.
class DerniersUtilisateurs {
  DerniersUtilisateurs._();

  static const cle = 'connexion_derniers_utilisateurs_v1';
  static const maximum = 6;

  static String normaliser(String login) => login.trim().toLowerCase();

  static Future<List<DernierUtilisateur>> lire() async {
    try {
      final s = (await SharedPreferences.getInstance()).getString(cle);
      if (s == null) return const [];
      final l = (jsonDecode(s) as List).map(DernierUtilisateur.fromJson).whereType<DernierUtilisateur>().toList()..sort((a, b) => b.date.compareTo(a.date));
      return l.take(maximum).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _ecrire(List<DernierUtilisateur> l) async {
    try {
      await (await SharedPreferences.getInstance()).setString(cle, jsonEncode(l.take(maximum).map((u) => u.toJson()).toList()));
    } catch (_) {}
  }

  /// Ajoute (ou remonte en tête) l'utilisateur qui vient de se connecter. Renvoie l'utilisateur retiré
  /// de la liste s'il y en a un (7e) : ses données de connexion rapide doivent être effacées.
  static Future<String?> noter({required String login, required String nom, required String role, DateTime? date}) async {
    final l = (await lire()).toList();
    final n = normaliser(login);
    final ancien = l.where((u) => normaliser(u.login) == n).firstOrNull;
    l.removeWhere((u) => normaliser(u.login) == n);
    l.insert(0, DernierUtilisateur(login: login.trim(), nom: nom, role: role, date: date ?? DateTime.now(), pinRefuse: ancien?.pinRefuse ?? false));
    String? sorti;
    if (l.length > maximum) sorti = l.removeLast().login;
    await _ecrire(l);
    return sorti;
  }

  static Future<void> retirer(String login) async {
    final n = normaliser(login);
    await _ecrire((await lire()).where((u) => normaliser(u.login) != n).toList());
  }

  static Future<void> refuserPin(String login) async {
    final n = normaliser(login);
    await _ecrire([for (final u in await lire()) normaliser(u.login) == n ? u.copyWith(pinRefuse: true) : u]);
  }

  static Future<void> vider() async {
    try {
      await (await SharedPreferences.getInstance()).remove(cle);
    } catch (_) {}
  }
}

/// « il y a 5 min », « il y a 2 h », « hier », « 08/10 ».
String quandConnecte(DateTime d, {DateTime? maintenant}) {
  final now = maintenant ?? DateTime.now();
  final ecart = now.difference(d);
  final jour = DateTime(now.year, now.month, now.day);
  final jourD = DateTime(d.year, d.month, d.day);
  if (jourD == jour) {
    if (ecart.inMinutes < 1) return 'à l\'instant';
    if (ecart.inMinutes < 60) return 'il y a ${ecart.inMinutes} min';
    return 'il y a ${ecart.inHours} h';
  }
  if (jour.difference(jourD).inDays == 1) return 'hier';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}
