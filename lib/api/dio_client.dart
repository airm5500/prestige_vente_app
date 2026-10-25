// lib/api/dio_client.dart
// Mise à jour avec Timeout de sécurité
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:prestige_vente_app/utils/journal_debug.dart';
import 'package:prestige_vente_app/api/session_expiree.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';

class DioClient {
  // On crée une seule instance de CookieJar
  static final CookieJar _cookieJar = CookieJar();

  // On crée une seule instance de Dio
  static final Dio _dio = _createDio();

  static Dio _createDio() {
    // 1. On configure les options de base avec les délais (timeouts)
    final options = BaseOptions(
      connectTimeout: const Duration(seconds: 10), // Temps max pour trouver le serveur
      receiveTimeout: const Duration(seconds: 10), // Temps max pour recevoir les données
    );

    // 2. On instancie Dio avec ces options
    final dio = Dio(options);

    // On attache le CookieJar unique
    dio.interceptors.add(CookieManager(_cookieJar));
    // 4.5.1 : en-tête X-Prestige-Utilisateur et 409 « session changée » (lib/api/utilisateur_session.dart).
    IntercepteurUtilisateur.brancher(dio);
    // 4.3.3 : 404 de Payara pendant un redéploiement → 503 « Prestige indisponible » (lib/serveur/panne_serveur.dart).
    avecDeploiement(dio);
    // Session expirée (401 « Veuillez vous connecter ») : reconnexion silencieuse et requête rejouée, sinon
    // retour à l'écran de connexion (lib/api/session_expiree.dart).
    dio.interceptors.add(IntercepteurSession(dio));
    // 4.3.1 (D18) : le numéro de série d'une boîte n'apparaît jamais dans le journal de la console.
    // 4.3.2 : journal des requêtes en mode DÉBOGAGE seulement. Dans l'APK livré, il recopiait chaque corps de
    // réponse (listes de produits, ventes, clients) dans le journal du téléphone : travail inutile à chaque
    // requête et données de l'officine hors de l'application.
    // 4.7.1 : méthode, chemin (sans valeur), statut et durée seulement : jamais de corps (mot de passe de la
    // connexion, ventes, clients), d'en-têtes (cookies, jetons, X-Client-Ref) ni de paramètres (lib/utils/journal_debug.dart).
    if (kDebugMode) {
      dio.interceptors.add(JournalHttpDebug());
    }

    return dio;
  }

  /// 4.8.0 : client de la session, à l'adresse du serveur courant (nom de l'appareil enregistré sur le serveur).
  static Dio get session => _dio;

  /// Session partagée (synchro hors ligne : même connexion, sans le journal).
  static CookieJar get cookieJar => _cookieJar;

  // Méthode pour obtenir le client Dio configuré
  static Dio getClient(String baseUrl) {
    _dio.options.baseUrl = baseUrl;
    return _dio;
  }
}

/// Masque la valeur du champ `serie` (numéro de série d'une boîte, D18) dans une ligne de journal : forme Map
/// (`serie: X`) et forme JSON (`"serie":"X"`).
String masquerSerie(String ligne) {
  if (!ligne.contains('serie')) return ligne;
  return ligne
      .replaceAllMapped(RegExp(r'("serie"\s*:\s*")[^"]*(")'), (m) => '${m[1]}***${m[2]}')
      .replaceAllMapped(RegExp(r'(\bserie:\s*)[^,}\s]+'), (m) => '${m[1]}***');
}
