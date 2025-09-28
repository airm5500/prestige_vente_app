// lib/providers/settings_provider.dart
// 28/09/2025 00:18
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

class SettingsProvider with ChangeNotifier {
  // Clés pour le stockage local
  static const String _localIpKey = 'local_ip';
  static const String _remoteIpKey = 'remote_ip';
  static const String _appNameKey = 'app_name';
  static const String _portKey = 'port';

  String _localIp = '';
  String _remoteIp = '';
  String _appName = 'prestige'; // Valeur par défaut
  String _port = '8080'; // Valeur par défaut

  // Getters pour accéder aux valeurs
  String get localIp => _localIp;
  String get remoteIp => _remoteIp;
  String get appName => _appName;
  String get port => _port;
  String get baseUrl => 'http://$_localIp:$_port/$_appName/api/v1';

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Charge les paramètres depuis SharedPreferences
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _localIp = prefs.getString(_localIpKey) ?? '';
    _remoteIp = prefs.getString(_remoteIpKey) ?? '';
    _appName = prefs.getString(_appNameKey) ?? 'prestige';
    _port = prefs.getString(_portKey) ?? '8080';
    notifyListeners();
  }

  // Sauvegarde les paramètres
  Future<bool> saveSettings({
    required String localIp,
    required String remoteIp,
    required String appName,
    required String port,
  }) async {
    _setLoading(true);
    // Ping automatique avant de sauvegarder
    final isPingSuccessful = await ping(localIp, port, appName);
    if (!isPingSuccessful) {
      _setLoading(false);
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localIpKey, localIp);
    await prefs.setString(_remoteIpKey, remoteIp);
    await prefs.setString(_appNameKey, appName);
    await prefs.setString(_portKey, port);

    _localIp = localIp;
    _remoteIp = remoteIp;
    _appName = appName;
    _port = port;

    _setLoading(false);
    return true;
  }

  // Fonction pour tester la connectivité au serveur
  Future<bool> ping(String ip, String port, String appName) async {
    if (ip.isEmpty) return false;
    final url = 'http://$ip:$port/$appName/api/v1/user/auth'; // On ping un endpoint connu
    try {
      final dio = Dio();
      // On envoie une requête qui échouera l'authentification mais confirmera la connexion
      await dio.post(url, data: {}, options: Options(receiveDataWhenStatusError: true));
      return true; // Si on arrive ici, le serveur a répondu
    } on DioException catch (e) {
      // Une réponse 400 ou 500 est OK, ça veut dire que le serveur est accessible
      if (e.response != null) {
        return true;
      }
      return false; // Erreur réseau
    } catch (_) {
      return false;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}