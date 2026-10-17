// lib/services/nfc_service.dart
// Lecture des badges NFC (cartes sans contact) : identifiant de la carte (UID) en hexadécimal.
import 'package:prestige_vente_app/plateforme/capacites.dart';
import 'package:flutter/services.dart';

enum NfcAvailability {
  /// Pas de puce NFC sur l'appareil.
  absent,

  /// NFC présent mais désactivé dans les réglages Android.
  disabled,
  ready,
}

/// Lecteur NFC remplaçable pour les tests.
abstract class NfcReader {
  Future<NfcAvailability> availability();

  /// UID des cartes approchées (tant que [start] est actif).
  Stream<String> get tags;

  /// Active la lecture. Renvoie false si le NFC n'est pas disponible.
  Future<bool> start();
  Future<void> stop();
  Future<void> openSettings();
}

class DeviceNfcReader implements NfcReader {
  static const _methods = MethodChannel('prestige/nfc');
  static const _events = EventChannel('prestige/nfc/tags');
  static final Stream<String> _tags = _events.receiveBroadcastStream().map((e) => '$e');

  const DeviceNfcReader();

  // 4.5.0 : sans pont NFC (iPhone / iPad) : absent, aucun appel natif.
  static bool get _pont => CapacitesPlateforme.courant.nfc;

  @override
  Future<NfcAvailability> availability() async {
    if (!_pont) return NfcAvailability.absent;
    try {
      final m = await _methods.invokeMapMethod<String, dynamic>('status');
      if (m?['supported'] != true) return NfcAvailability.absent;
      return m?['enabled'] == true ? NfcAvailability.ready : NfcAvailability.disabled;
    } on MissingPluginException {
      return NfcAvailability.absent;
    } on PlatformException {
      return NfcAvailability.absent;
    }
  }

  @override
  Stream<String> get tags => _pont ? _tags : const Stream<String>.empty();

  @override
  Future<bool> start() async {
    if (!_pont) return false;
    try {
      return await _methods.invokeMethod<bool>('start') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    if (!_pont) return;
    try {
      await _methods.invokeMethod('stop');
    } on MissingPluginException {
      // Rien à arrêter.
    } on PlatformException {
      // Idem.
    }
  }

  @override
  Future<void> openSettings() async {
    if (!_pont) return;
    try {
      await _methods.invokeMethod('openSettings');
    } on MissingPluginException {
      // Appareil sans pont NFC.
    }
  }
}
