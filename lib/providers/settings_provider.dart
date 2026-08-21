// lib/providers/settings_provider.dart
// Mise à jour : Ajout du mode de comparaison de stock pour le contrôle BL
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

class SettingsProvider with ChangeNotifier {
  static const String _localIpKey = 'local_ip';
  static const String _remoteIpKey = 'remote_ip';
  static const String _appNameKey = 'app_name';
  static const String _portKey = 'port';
  static const String _isRemoteKey = 'is_remote';
  static const String _stayConnectedKey = 'stay_connected';
  static const String _savedLoginKey = 'saved_login';
  static const String _savedPasswordKey = 'saved_password';
  static const String _isTestPrintModeKey = 'is_test_print_mode';
  static const String _paperWidthKey = 'paper_width';
  static const String _showQrCodeOnSaleTicketKey = 'show_qr_code_on_sale_ticket';
  static const String _canEditDeliveryControlKey = 'can_edit_delivery_control';
  static const String _canEditBlControlKey = 'can_edit_bl_control';
  static const String _enabledPaymentMethodIdsKey = 'enabled_payment_method_ids';
  static const String _numberOfTicketsKey = 'number_of_tickets';
  static const String _ticketCodeTypeKey = 'ticket_code_type';
  static const String _numberOfTicketsAssuranceKey = 'number_of_tickets_assurance';
  static const String _maxTiersPayantsKey = 'max_tiers_payants';
  static const String _menuOrderKey = 'menuOrder';
  static const String _hiddenMenuIdsKey = 'hiddenMenuIds';

  // NOUVEAU PARAMÈTRE : Mode de comparaison Stock BL
  static const String _blStockComparisonModeKey = 'bl_stock_comparison_mode';

  String _localIp = '';
  String _remoteIp = '';
  String _appName = 'prestige';
  String _port = '8080';
  bool _isRemote = false;
  bool _stayConnected = false;
  String _savedLogin = '';
  bool _isTestPrintMode = true;
  int _paperWidth = 58;
  bool _showQrCodeOnSaleTicket = true;
  bool _canEditDeliveryControl = true;
  bool _canEditBlControl = true;
  List<String> _enabledPaymentMethodIds = [];
  int _numberOfTickets = 1;
  String _ticketCodeType = 'QR_CODE';
  int _numberOfTicketsAssurance = 1;
  int _maxTiersPayants = 2;
  List<String> _menuOrder = [];
  List<String> _hiddenMenuIds = [];

  // NOUVELLE VARIABLE
  String _blStockComparisonMode = 'theorique';

  // Getters
  String get localIp => _localIp;
  String get remoteIp => _remoteIp;
  String get appName => _appName;
  String get port => _port;
  bool get isRemote => _isRemote;
  bool get stayConnected => _stayConnected;
  String get savedLogin => _savedLogin;
  bool get isTestPrintMode => _isTestPrintMode;
  int get paperWidth => _paperWidth;
  bool get showQrCodeOnSaleTicket => _showQrCodeOnSaleTicket;
  bool get canEditDeliveryControl => _canEditDeliveryControl;
  bool get canEditBlControl => _canEditBlControl;
  List<String> get enabledPaymentMethodIds => _enabledPaymentMethodIds;
  int get numberOfTickets => _numberOfTickets;
  String get ticketCodeType => _ticketCodeType;
  int get numberOfTicketsAssurance => _numberOfTicketsAssurance;
  int get maxTiersPayants => _maxTiersPayants;
  List<String> get menuOrder => _menuOrder;
  List<String> get hiddenMenuIds => _hiddenMenuIds;

  // NOUVEAU GETTER
  String get blStockComparisonMode => _blStockComparisonMode;

  bool get isConfigured => _localIp.isNotEmpty || _remoteIp.isNotEmpty;

  String get baseUrl {
    String ip = _isRemote ? _remoteIp : _localIp;
    if (ip.isEmpty) {
      ip = "localhost";
    }
    return 'http://$ip:$_port/$_appName/api/v1';
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _localIp = prefs.getString(_localIpKey) ?? '192.168.1.50';
    _remoteIp = prefs.getString(_remoteIpKey) ?? '';
    _appName = prefs.getString(_appNameKey) ?? 'prestige';
    _port = prefs.getString(_portKey) ?? '8080';
    _isRemote = prefs.getBool(_isRemoteKey) ?? false;
    _stayConnected = prefs.getBool(_stayConnectedKey) ?? false;
    _savedLogin = prefs.getString(_savedLoginKey) ?? '';
    _isTestPrintMode = prefs.getBool(_isTestPrintModeKey) ?? false;
    _paperWidth = prefs.getInt(_paperWidthKey) ?? 58;
    _showQrCodeOnSaleTicket = prefs.getBool(_showQrCodeOnSaleTicketKey) ?? false;
    _canEditDeliveryControl = prefs.getBool(_canEditDeliveryControlKey) ?? true;
    _canEditBlControl = prefs.getBool(_canEditBlControlKey) ?? true;
    _enabledPaymentMethodIds = prefs.getStringList(_enabledPaymentMethodIdsKey) ?? [];
    _numberOfTickets = prefs.getInt(_numberOfTicketsKey) ?? 1;
    _ticketCodeType = prefs.getString(_ticketCodeTypeKey) ?? 'QR_CODE';
    _numberOfTicketsAssurance = prefs.getInt(_numberOfTicketsAssuranceKey) ?? 2;
    _maxTiersPayants = prefs.getInt(_maxTiersPayantsKey) ?? 2;
    _menuOrder = prefs.getStringList(_menuOrderKey) ?? [];
    _hiddenMenuIds = prefs.getStringList(_hiddenMenuIdsKey) ?? [];
    _hideRvProducts = prefs.getBool('hide_rv_products') ?? true;

    // CHARGEMENT DU NOUVEAU PARAMÈTRE
    _blStockComparisonMode = prefs.getString(_blStockComparisonModeKey) ?? 'theorique';

    if (prefs.containsKey('hiddenMenuIds')) {
      _hiddenMenuIds = prefs.getStringList('hiddenMenuIds') ?? [];
    } else {
      _hiddenMenuIds = [
        'evaluation',
        'search',
        'ajustement',
        'depot'
      ];
    }

    if (prefs.containsKey(_enabledPaymentMethodIdsKey)) {
      _enabledPaymentMethodIds = List<String>.from(prefs.getStringList(_enabledPaymentMethodIdsKey) ?? []);
    } else {
      _enabledPaymentMethodIds = [
        '10', // WAVE
        '7',  // ORANGE
        '9',  // MTN
        '8',  // MOOV
        '3'   // CARTE BANCAIRE
      ];
    }
    notifyListeners();
  }

  // --- NOUVEAU SETTER POUR LE BL ---
  Future<void> setBlStockComparisonMode(String mode) async {
    _blStockComparisonMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_blStockComparisonModeKey, mode);
    notifyListeners();
  }

  Future<void> togglePaymentMethod(String methodId, bool isEnabled) async {
    if (isEnabled) {
      if (!_enabledPaymentMethodIds.contains(methodId)) {
        _enabledPaymentMethodIds.add(methodId);
      }
    } else {
      _enabledPaymentMethodIds.remove(methodId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_enabledPaymentMethodIdsKey, _enabledPaymentMethodIds);
    notifyListeners();
  }

  Future<void> setNumberOfTickets(int count) async {
    _numberOfTickets = count;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_numberOfTicketsKey, _numberOfTickets);
    notifyListeners();
  }

  Future<void> setNumberOfTicketsAssurance(int count) async {
    _numberOfTicketsAssurance = count;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_numberOfTicketsAssuranceKey, _numberOfTicketsAssurance);
    notifyListeners();
  }

  Future<void> setMaxTiersPayants(int count) async {
    _maxTiersPayants = count;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxTiersPayantsKey, _maxTiersPayants);
    notifyListeners();
  }

  Future<void> setTicketCodeType(String codeType) async {
    _ticketCodeType = codeType;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ticketCodeTypeKey, _ticketCodeType);
    notifyListeners();
  }

  Future<void> setCanEditDeliveryControl(bool canEdit) async {
    _canEditDeliveryControl = canEdit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_canEditDeliveryControlKey, canEdit);
    notifyListeners();
  }

  Future<void> setCanEditBlControl(bool canEdit) async {
    _canEditBlControl = canEdit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_canEditBlControlKey, canEdit);
    notifyListeners();
  }

  Future<void> setShowQrCodeOnSaleTicket(bool show) async {
    _showQrCodeOnSaleTicket = show;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showQrCodeOnSaleTicketKey, show);
    notifyListeners();
  }

  Future<void> setPaperWidth(int width) async {
    _paperWidth = width;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_paperWidthKey, _paperWidth);
    notifyListeners();
  }

  Future<void> setTestPrintMode(bool isTestMode) async {
    _isTestPrintMode = isTestMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isTestPrintModeKey, isTestMode);
    notifyListeners();
  }

  Future<void> saveMenuConfig(List<String> newOrder, List<String> newHiddenIds) async {
    _menuOrder = newOrder;
    _hiddenMenuIds = newHiddenIds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_menuOrderKey, newOrder);
    await prefs.setStringList(_hiddenMenuIdsKey, newHiddenIds);
    notifyListeners();
  }

  Future<void> resetMenuConfig() async {
    _menuOrder = [];
    _hiddenMenuIds = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_menuOrderKey);
    await prefs.remove(_hiddenMenuIdsKey);
    notifyListeners();
  }

  Future<String> getSavedPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savedPasswordKey) ?? '';
  }

  Future<void> saveCredentials(String login, String password, bool stayConnected) async {
    _stayConnected = stayConnected;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_stayConnectedKey, _stayConnected);

    if (_stayConnected) {
      await prefs.setString(_savedLoginKey, login);
      await prefs.setString(_savedPasswordKey, password);
      _savedLogin = login;
    } else {
      await prefs.remove(_savedLoginKey);
      await prefs.remove(_savedPasswordKey);
      _savedLogin = '';
    }
    notifyListeners();
  }

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
    final url = 'http://$ip:$port/$_appName/api/v1/user/auth';
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

  bool _hideRvProducts = true;
  bool get hideRvProducts => _hideRvProducts;

  Future<void> setHideRvProducts(bool value) async {
    _hideRvProducts = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hide_rv_products', value);
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}