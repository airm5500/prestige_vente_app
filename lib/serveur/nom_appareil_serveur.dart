// lib/serveur/nom_appareil_serveur.dart
// 4.8.0 — demande 56 du serveur (25/10/2026) : le serveur garde le nom de l'appareil, rattaché à son EMPREINTE, pour le
// retrouver après une désinstallation de l'application. Vérifié dans le code du serveur (rest.AppareilRessource) :
//  - GET v1/appareil/nom?empreinte=<64 hex> SANS session : 200 {success:true, nom:"…"|null} ; 400 {code:INVALIDE} ;
//    429 {code:TROP_DE_DEMANDES} (30 lectures par minute et par adresse) ;
//  - PUT v1/appareil/nom {empreinte, nom} avec la session : 200 {success:true, nom: tel qu'enregistré (nettoyé comme
//    X-Poste)} ; 401 {code:SESSION} ; 400 (nom vide, empreinte invalide) ; remplace le nom existant.
// Empreinte = SHA-256(ANDROID_ID + ":" + nom du paquet), calculée par le code natif (FingerprintService) : ANDROID_ID
// n'arrive jamais dans Flutter ; l'empreinte n'est ni journalisée ni gardée, elle part seulement dans le champ
// « empreinte » de ces deux routes. Ni secret ni droit.
//
// Application :
//  - premier lancement sans nom sur l'appareil : lecture (délai court, [delaiLecture]) ; nom trouvé → gardé sur
//    l'appareil, l'étape obligatoire est sautée ; sinon (null, 404/405, 429, réseau, délai) : étape comme avant ;
//  - envoi (PUT) quand l'utilisateur enregistre un nom, et après chaque connexion tant que CE serveur ne l'a pas
//    confirmé ; échec : nouvel essai à la connexion suivante ; 404/405 : serveur ancien, plus d'essai pour lui.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/services/fingerprint_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Issue d'une lecture du nom gardé par le serveur.
enum LectureNomServeur { trouve, inconnu, indisponible }

class NomAppareilServeur {
  NomAppareilServeur._();
  static NomAppareilServeur instance = NomAppareilServeur._();

  @visibleForTesting
  static void reinitialiser() => instance = NomAppareilServeur._();

  /// Préférence : nom confirmé par chaque serveur (racine de l'API → nom envoyé, ou [_ancien]).
  static const prefSynchro = 'nom_appareil_serveur_v1';
  static const _ancien = '#ancien';

  /// Délai maximal de la lecture au premier lancement (puis étape obligatoire comme avant).
  static Duration delaiLecture = const Duration(seconds: 3);

  /// Empreinte de l'appareil (64 hexadécimaux) ou null ; remplaçable pour les tests.
  Future<String?> Function() empreinte = FingerprintService.empreinteAppareil;

  /// Client de la session (PUT) ; remplaçable pour les tests.
  Dio Function() session = () => DioClient.session;

  /// Une connexion est ouverte (sinon le PUT attend la prochaine connexion).
  bool Function() connecte = () => UtilisateurSession.id != null;

  String? _empreinte;
  Future<String?> _lireEmpreinte() async {
    if (_empreinte != null) return _empreinte;
    try {
      final e = await empreinte();
      if (e != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(e)) _empreinte = e;
    } catch (_) {}
    return _empreinte;
  }

  /// Lecture au premier lancement ([racine] = adresse de l'API) ; nom trouvé → enregistré sur l'appareil et confirmé
  /// pour ce serveur. Jamais d'exception, jamais plus de [delaiLecture].
  Future<LectureNomServeur> retrouver(String racine) async {
    try {
      return await _retrouver(racine).timeout(delaiLecture, onTimeout: () => LectureNomServeur.indisponible);
    } catch (_) {
      return LectureNomServeur.indisponible;
    }
  }

  Future<LectureNomServeur> _retrouver(String racine) async {
    final e = await _lireEmpreinte();
    if (e == null || racine.isEmpty) return LectureNomServeur.indisponible;
    final d = IntercepteurPoste.brancher(Dio(BaseOptions(
      baseUrl: racine,
      connectTimeout: delaiLecture,
      sendTimeout: delaiLecture,
      receiveTimeout: delaiLecture,
      validateStatus: (_) => true,
      responseType: ResponseType.plain,
    )));
    try {
      final r = await d.get<String>('/appareil/nom', queryParameters: {'empreinte': e});
      if (r.statusCode != 200) return LectureNomServeur.indisponible;
      final j = jsonDecode(r.data ?? '');
      if (j is! Map || j['success'] != true) return LectureNomServeur.indisponible;
      final nom = nettoyerNomPoste(j['nom'] is String ? j['nom'] as String : null);
      if (nom == null) return LectureNomServeur.inconnu;
      await NomAppareil.instance.enregistrer(nom);
      await _noter(racine, nom);
      return LectureNomServeur.trouve;
    } catch (_) {
      return LectureNomServeur.indisponible;
    } finally {
      d.close(force: true);
    }
  }

  Future<Map<String, String>> _etat() async {
    try {
      final p = await SharedPreferences.getInstance();
      final j = jsonDecode(p.getString(prefSynchro) ?? '{}');
      return j is Map ? {for (final e in j.entries) '${e.key}': '${e.value}'} : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _noter(String racine, String valeur) async {
    try {
      final m = await _etat();
      m[racine] = valeur;
      final p = await SharedPreferences.getInstance();
      await p.setString(prefSynchro, jsonEncode(m));
    } catch (_) {}
  }

  Future<void>? _envoi;

  /// Envoie le nom enregistré au serveur de la session s'il ne l'a pas encore confirmé (après une connexion, ou quand
  /// l'utilisateur enregistre un nom). Jamais d'exception ; un seul envoi à la fois.
  Future<void> synchroniser() => _envoi ??= _synchroniser().whenComplete(() => _envoi = null);

  Future<void> _synchroniser() async {
    try {
      final n = NomAppareil.instance;
      if (!n.nomEnregistre || !connecte()) return;
      final d = session();
      final racine = d.options.baseUrl;
      if (racine.isEmpty) return;
      final deja = (await _etat())[racine];
      if (deja == _ancien || deja == n.saisi) return;
      final e = await _lireEmpreinte();
      if (e == null) return;
      final nom = n.saisi;
      final r = await d.put<dynamic>('/appareil/nom',
          data: {'empreinte': e, 'nom': nom}, options: Options(validateStatus: (_) => true, receiveTimeout: const Duration(seconds: 10)));
      final s = r.statusCode ?? 0;
      if (s == 404 || s == 405) {
        await _noter(racine, _ancien); // serveur sans la demande 56 : plus d'essai pour lui
        return;
      }
      final j = r.data is String ? jsonDecode(r.data as String) : r.data;
      if (s != 200 || j is! Map || j['success'] != true) return; // nouvel essai à la prochaine connexion
      // Nom tel que le serveur l'a enregistré (nettoyé comme X-Poste) : c'est celui qu'on garde.
      final garde = nettoyerNomPoste(j['nom'] is String ? j['nom'] as String : null) ?? nom;
      if (garde != n.saisi) await n.enregistrer(garde);
      await _noter(racine, garde);
    } catch (_) {
      // Réseau, session : nouvel essai à la prochaine connexion.
    }
  }
}
