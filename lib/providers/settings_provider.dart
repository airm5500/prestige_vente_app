// lib/providers/settings_provider.dart
// 28/09/2025 20:20
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

class SettingsProvider with ChangeNotifier {
  static const String _localIpKey = 'local_ip';
  static const String _remoteIpKey = 'remote_ip';
  static const String _appNameKey = 'app_name';
  static const String _portKey = 'port';
  // MODIFICATION : Nouvelles clés pour les préférences
  static const String _isRemoteKey = 'is_remote';
  static const String _stayConnectedKey = 'stay_connected';
  static const String _savedLoginKey = 'saved_login';
  static const String _savedPasswordKey = 'saved_password';


  String _localIp = '';
  String _remoteIp = '';
  String _appName = 'prestige';
  String _port = '8080';
  // MODIFICATION : Nouveaux états
  bool _isRemote = false;
  bool _stayConnected = false;
  String _savedLogin = '';

  String get localIp => _localIp;
  String get remoteIp => _remoteIp;
  String get appName => _appName;
  String get port => _port;
  bool get isRemote => _isRemote;
  bool get stayConnected => _stayConnected;
  String get savedLogin => _savedLogin;

  // Le baseUrl s'adapte maintenant au mode de connexion choisi
  String get baseUrl {
    final ip = _isRemote ? _remoteIp : _localIp;
    return 'http://$ip:$_port/$_appName/api/v1';
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Charge tous les paramètres au démarrage
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _localIp = prefs.getString(_localIpKey) ?? '';
    _remoteIp = prefs.getString(_remoteIpKey) ?? '';
    _appName = prefs.getString(_appNameKey) ?? 'prestige';
    _port = prefs.getString(_portKey) ?? '8080';
    _isRemote = prefs.getBool(_isRemoteKey) ?? false;
    _stayConnected = prefs.getBool(_stayConnectedKey) ?? false;
    _savedLogin = prefs.getString(_savedLoginKey) ?? '';
    notifyListeners();
  }

  // Récupère le mot de passe sauvegardé (uniquement quand c'est nécessaire)
  Future<String> getSavedPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savedPasswordKey) ?? '';
  }

  // Sauvegarde les identifiants si "Rester connecté" est coché
  Future<void> saveCredentials(String login, String password, bool stayConnected) async {
    _stayConnected = stayConnected;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_stayConnectedKey, _stayConnected);

    if (_stayConnected) {
      await prefs.setString(_savedLoginKey, login);
      await prefs.setString(_savedPasswordKey, password);
      _savedLogin = login;
    } else {
      // Si décoché, on supprime les identifiants sauvegardés
      await prefs.remove(_savedLoginKey);
      await prefs.remove(_savedPasswordKey);
      _savedLogin = '';
    }
    notifyListeners();
  }

  // Change le mode de connexion et le sauvegarde
  Future<void> setConnectionMode(bool isRemote) async {
    _isRemote = isRemote;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isRemoteKey, isRemote);
    notifyListeners();
  }

  Future<bool> saveSettings({
    required String localIp,
    required String remoteIp,
    required String appName,
    required String port,
  }) async {
    _setLoading(true);
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

  Future<bool> ping(String ip, String port, String appName) async {
    if (ip.isEmpty) return false;
    final url = 'http://$ip:$port/$appName/api/v1/user/auth';
    try {
      final dio = Dio();
      await dio.post(url, data: {}, options: Options(receiveDataWhenStatusError: true));
      return true;
    } on DioException catch (e) {
      if (e.response != null) { return true; }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}