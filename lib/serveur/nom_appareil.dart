// lib/serveur/nom_appareil.dart
// 4.7.0 — demande du serveur du 25/10/2026 (docs/notices/DEMANDE_SESSION_MOBILE_NOM_APPAREIL.md) : nom de cet
// appareil envoyé à Prestige dans l'en-tête `X-Poste` de CHAQUE requête. « Ventes terminées » l'affiche ensuite comme
// poste de saisie (création de la vente) et poste d'encaissement (clôture) au lieu de l'adresse IP.
//
// Serveur (vérifié dans son code, branche claude/new-session-xm8ptu) : filter.AuthenticationFilter pose
// util.ContexteRequete pour toute requête de l'API ; ContexteRequete décode l'en-tête (URLDecoder, UTF-8) puis le
// nettoie (`nettoyer`) : caractères hors [\p{L}\p{N} ._-] retirés, espaces de bord retirés, vide = pas de nom, 60
// caractères au plus (unités UTF-16, coupé APRÈS le retrait des espaces). Sans en-tête : nom réseau ou adresse IP.
// [nettoyerNomPoste] rend le nom tel qu'il sera ENREGISTRÉ à partir de l'en-tête envoyé : après la coupure, une
// espace finale ou une demi-paire de substitution est retirée (le serveur ne les garderait pas).
//
// Ici : mêmes règles ([nettoyerNomPoste]) pour montrer le nom tel qu'il sera enregistré. Nom par défaut : marque et
// modèle de l'appareil (« SUNMI V2s »), lus au démarrage par le journal du terminal (aucun paquet ajouté). Le nom
// saisi est gardé sur l'appareil (préférences, ce n'est pas un secret) ; jamais de jeton ni d'identifiant dedans.
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// En-tête lu par le serveur.
const String entetePoste = 'X-Poste';

/// Longueur maximale gardée par le serveur.
const int longueurMaxPoste = 60;

final RegExp _horsPermis = RegExp(r'[^\p{L}\p{N} ._\-]', unicode: true);

/// Nom tel que le serveur l'enregistrera (util.ContexteRequete.nettoyer) ; null s'il ne reste rien.
String? nettoyerNomPoste(String? brut) {
  if (brut == null) return null;
  var s = brut.replaceAll(_horsPermis, '').trim();
  if (s.isEmpty) return null;
  if (s.length > longueurMaxPoste) {
    s = s.substring(0, longueurMaxPoste);
    // Coupure au milieu d'une lettre hors du plan de base (paire de substitution) : demi-caractère retiré.
    final u = s.codeUnitAt(s.length - 1);
    if (u >= 0xD800 && u <= 0xDBFF) s = s.substring(0, s.length - 1);
    // Le serveur nettoie ce qu'il reçoit : une espace laissée en fin par la coupure y est retirée.
    s = s.trimRight();
  }
  return s;
}

/// Valeur de l'en-tête : nom nettoyé, encodé en URL (UTF-8) ; null = pas d'en-tête.
String? valeurEntetePoste(String? brut) {
  final n = nettoyerNomPoste(brut);
  return n == null ? null : Uri.encodeComponent(n);
}

/// Nom de cet appareil (saisi, sinon marque et modèle).
class NomAppareil extends ChangeNotifier {
  NomAppareil._();
  static NomAppareil instance = NomAppareil._();

  /// Pour les tests : instance neuve.
  @visibleForTesting
  static void reinitialiser() => instance = NomAppareil._();

  static const prefNom = 'nom_appareil_v1';
  static const prefPropose = 'nom_appareil_propose_v1';

  String _saisi = '';
  bool _propose = false;

  /// Marque et modèle (journal du terminal, lus au démarrage) ; remplaçable pour les tests.
  String Function() modele = () => JournalTerminal.instance.terminalNom;

  /// Nom saisi par l'utilisateur ('' = aucun).
  String get saisi => _saisi;

  /// Nom par défaut, tel qu'enregistré (null si la marque et le modèle sont inconnus).
  String? get parDefaut => nettoyerNomPoste(modele());

  /// Nom envoyé (saisi, sinon par défaut) ; null = aucun en-tête (le serveur garde le nom réseau).
  String? get effectif => nettoyerNomPoste(_saisi) ?? parDefaut;

  // Valeur de l'en-tête gardée tant que le nom saisi et le modèle ne changent pas (lue à chaque requête).
  String? _cleCache;
  String? _enteteCache;

  /// Valeur de l'en-tête X-Poste.
  String? get entete {
    final cle = '$_saisi\u0000${modele()}';
    if (cle != _cleCache) {
      final e = effectif;
      _enteteCache = e == null ? null : Uri.encodeComponent(e);
      _cleCache = cle;
    }
    return _enteteCache;
  }

  /// Le nom a déjà été proposé (ou saisi) sur cet appareil.
  bool get dejaPropose => _propose || _saisi.isNotEmpty;

  Future<void> charger() async {
    try {
      final p = await SharedPreferences.getInstance();
      _saisi = p.getString(prefNom) ?? '';
      _propose = p.getBool(prefPropose) ?? false;
    } catch (_) {}
    notifyListeners();
  }

  /// Enregistre le nom NETTOYÉ (celui que le serveur gardera) ; '' = revenir au nom par défaut.
  Future<String?> enregistrer(String brut) async {
    final n = nettoyerNomPoste(brut) ?? '';
    _saisi = n;
    _propose = true;
    try {
      final p = await SharedPreferences.getInstance();
      if (n.isEmpty) {
        await p.remove(prefNom);
      } else {
        await p.setString(prefNom, n);
      }
      await p.setBool(prefPropose, true);
    } catch (_) {}
    notifyListeners();
    return effectif;
  }

  /// La proposition de la première connexion a été vue (« Plus tard » compris).
  Future<void> marquerPropose() async {
    _propose = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(prefPropose, true);
    } catch (_) {}
  }
}

/// Ajoute `X-Poste` à chaque requête vers Prestige (nom de cet appareil). Rien d'autre n'est modifié.
class IntercepteurPoste extends Interceptor {
  IntercepteurPoste({String? Function()? entete}) : _entete = entete ?? (() => NomAppareil.instance.entete);
  final String? Function() _entete;

  /// Ajoute l'intercepteur s'il n'y est pas déjà ; renvoie [d].
  static Dio brancher(Dio d) {
    if (!d.interceptors.any((i) => i is IntercepteurPoste)) d.interceptors.add(IntercepteurPoste());
    return d;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      final v = _entete();
      if (v != null && v.isNotEmpty) options.headers[entetePoste] = v;
    } catch (_) {}
    handler.next(options);
  }
}
