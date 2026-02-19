// lib/api/dio_client.dart
// Mise à jour avec Timeout de sécurité
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';

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
    dio.interceptors.add(LogInterceptor(responseBody: true, requestBody: true));

    return dio;
  }

  // Méthode pour obtenir le client Dio configuré
  static Dio getClient(String baseUrl) {
    _dio.options.baseUrl = baseUrl;
    return _dio;
  }
}