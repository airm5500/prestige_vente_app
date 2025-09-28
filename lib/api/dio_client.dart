// lib/api/dio_client.dart
// 28/09/2025 20:30
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';

class DioClient {
  // On crée une seule instance de CookieJar
  static final CookieJar _cookieJar = CookieJar();

  // On crée une seule instance de Dio
  static final Dio _dio = _createDio();

  static Dio _createDio() {
    final dio = Dio();
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