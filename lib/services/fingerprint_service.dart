// lib/services/fingerprint_service.dart
// Accès au lecteur d'empreinte Sunmi (service com.sunmi.fingerprintservice) via le pont natif
// SunmiFingerprintBridge. Les gabarits d'empreinte sont conservés par l'application.
import 'package:flutter/services.dart';

class FingerprintException implements Exception {
  final String code;
  final String message;
  const FingerprintException(this.code, this.message);

  @override
  String toString() => message;
}

class FingerprintMatch {
  /// Position du gabarit reconnu dans la liste fournie, -1 si aucun.
  final int index;
  final int score;
  const FingerprintMatch(this.index, this.score);
  bool get found => index >= 0;
}

class FingerprintService {
  FingerprintService._();

  static const _methods = MethodChannel('prestige/fingerprint');
  static const _events = EventChannel('prestige/fingerprint/events');

  /// Consignes du capteur : "press" (posez le doigt), "raise" (retirez le doigt), "disconnected".
  static Stream<String> get hints => _events.receiveBroadcastStream().map((e) => e.toString());

  static Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _methods.invokeMethod<T>(method, args);
    } on MissingPluginException {
      throw const FingerprintException('NO_PLUGIN', 'Lecteur d\'empreinte non disponible sur cet appareil.');
    } on PlatformException catch (e) {
      throw FingerprintException(e.code, e.message ?? e.code);
    }
  }

  static Future<bool> isServiceInstalled() async {
    try {
      return await _call<bool>('isServiceInstalled') ?? false;
    } on FingerprintException {
      return false;
    }
  }

  static Future<void> connect() => _call<bool>('connect');
  static Future<void> engage() => _call<bool>('engage');
  static Future<void> release() => _call<int>('release');
  static Future<void> cancel() => _call<int>('cancel');

  static Future<Map<String, String>> deviceInfo() async {
    final m = await _call<Map<Object?, Object?>>('deviceInfo') ?? const {};
    return {for (final e in m.entries) '${e.key}': '${e.value}'};
  }

  static Future<({int capacity, int enrolled})> capacity() async {
    final m = await _call<Map<Object?, Object?>>('capacity') ?? const {};
    return (capacity: (m['capacity'] as int?) ?? -1, enrolled: (m['enrolled'] as int?) ?? -1);
  }

  /// Enregistre le doigt posé et renvoie son gabarit.
  static Future<Uint8List> enroll({int timeoutSeconds = 15}) async {
    final t = await _call<Uint8List>('enroll', {'timeout': timeoutSeconds});
    if (t == null || t.isEmpty) throw const FingerprintException('ENROLL_FAILED', 'Empreinte non enregistrée');
    return t;
  }

  /// Compare le doigt posé aux gabarits fournis.
  static Future<FingerprintMatch> identify(List<Uint8List> templates, {int timeoutSeconds = 10}) async {
    final m = await _call<Map<Object?, Object?>>('identify', {'templates': templates, 'timeout': timeoutSeconds}) ?? const {};
    return FingerprintMatch((m['index'] as int?) ?? -1, (m['score'] as int?) ?? 0);
  }
}
