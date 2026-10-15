// lib/prestigepos/impression/transports.dart
// PrestigePOS — envoi des octets ESC/POS à l'imprimante :
//  - réseau (Wi-Fi / Ethernet) : socket TCP Dart vers IP:9100 (« RAW »), aucun code natif ;
//  - Bluetooth classique (SPP) et USB (OTG) : petit pont Kotlin propre à la saveur `pos`
//    (android/app/src/pos/kotlin/com/dici/prestigepos/ImprimantesPlugin.kt), canal « prestigepos/imprimantes ».
//    Le pont n'existe pas dans Prestige Mobile (saveur `mobile`) : aucune permission Bluetooth / USB n'y est ajoutée.
// Chaque échec est traduit en un message clair pour le personnel (EchecImpression.message).
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_reglages.dart';

/// Échec d'impression, avec un message en clair.
class EchecImpression implements Exception {
  final String code;
  final String message;
  const EchecImpression(this.code, this.message);

  @override
  String toString() => message;

  /// Message clair d'un code d'erreur du pont Android.
  static String messagePour(String code, {String detail = ''}) => switch (code) {
        'PERMISSION' => 'Autorisation Bluetooth refusée : autorisez « Appareils à proximité » pour PrestigePOS '
            '(Paramètres Android › Applications › PrestigePOS › Autorisations).',
        'BT_ABSENT' => 'Cet appareil n\'a pas de Bluetooth.',
        'BT_INACTIF' => 'Le Bluetooth est désactivé : activez-le, puis réessayez.',
        'LOCALISATION' => 'Recherche Bluetooth impossible : activez la localisation d\'Android (nécessaire pour '
            'découvrir les appareils sur Android 11 et moins), ou appairez l\'imprimante dans les réglages Bluetooth.',
        'CONNEXION' => 'Imprimante Bluetooth injoignable : vérifiez qu\'elle est allumée, chargée et à portée '
            '(moins de 10 m), puis réessayez.',
        'USB_ABSENT' => 'Imprimante USB non branchée (câble OTG) ou éteinte.',
        'USB_REFUS' => 'Accès à l\'imprimante USB refusé : rebranchez-la et acceptez la demande d\'Android.',
        'USB_INTERFACE' => 'Ce périphérique USB n\'est pas une imprimante reconnue.',
        'RESEAU' => 'Imprimante réseau injoignable${detail.isEmpty ? '' : ' ($detail)'} : vérifiez son adresse IP, '
            'son port (9100) et qu\'elle est sur le même réseau Wi-Fi.',
        'INDISPONIBLE' => 'Impression Bluetooth / USB indisponible sur cet appareil.',
        _ => 'Impression impossible${detail.isEmpty ? '' : ' : $detail'}.',
      };
}

/// Envoi d'octets à une imprimante.
abstract class TransportImpression {
  Future<void> envoyer(Uint8List octets);
}

/// Imprimante réseau : socket TCP brute (port 9100), délai de connexion borné.
class TransportReseau implements TransportImpression {
  final String hote;
  final int port;
  final Duration delai;
  const TransportReseau(this.hote, {this.port = ImprimanteConfig.portDefaut, this.delai = const Duration(seconds: 5)});

  @override
  Future<void> envoyer(Uint8List octets) async {
    Socket? s;
    try {
      s = await Socket.connect(hote, port, timeout: delai);
      s.add(octets);
      await s.flush().timeout(delai);
      await s.close().timeout(delai);
    } on SocketException {
      throw EchecImpression('RESEAU', EchecImpression.messagePour('RESEAU', detail: '$hote:$port'));
    } on TimeoutException {
      throw EchecImpression('RESEAU', EchecImpression.messagePour('RESEAU', detail: '$hote:$port, délai dépassé'));
    } finally {
      s?.destroy();
    }
  }
}

/// Pont Android (Bluetooth SPP et USB) de la saveur `pos`. Remplaçable dans les tests ([PontImprimantes.instance]).
abstract class PontImprimantes {
  /// Demande les autorisations Bluetooth (Android 12+ : « Appareils à proximité » ; ≤ 11 : localisation pour la
  /// découverte). true si accordées.
  Future<bool> autorisations();

  /// Appareils Bluetooth appairés.
  Future<List<AppareilImprimante>> appaires();

  /// Recherche (appairés + découverte de [duree]).
  Future<List<AppareilImprimante>> rechercher({Duration duree = const Duration(seconds: 12)});

  /// Demande à Android d'activer le Bluetooth.
  Future<void> activerBluetooth();

  Future<void> envoyerBluetooth(String adresse, Uint8List octets);

  /// Périphériques USB branchés (adresse « vendorId:productId »).
  Future<List<AppareilImprimante>> usb();

  Future<void> envoyerUsb(int vendorId, int productId, Uint8List octets);

  static PontImprimantes instance = CanalImprimantes();
}

class CanalImprimantes implements PontImprimantes {
  static const MethodChannel canal = MethodChannel('prestigepos/imprimantes');

  Future<T?> _appel<T>(String methode, [Object? args]) async {
    try {
      return await canal.invokeMethod<T>(methode, args);
    } on PlatformException catch (e) {
      throw EchecImpression(e.code, EchecImpression.messagePour(e.code, detail: e.message ?? ''));
    } on MissingPluginException {
      throw EchecImpression('INDISPONIBLE', EchecImpression.messagePour('INDISPONIBLE'));
    }
  }

  static List<AppareilImprimante> _liste(Object? v) => [
        if (v is List)
          for (final e in v)
            if (AppareilImprimante.fromJson(e) case final a?) a
      ];

  @override
  Future<bool> autorisations() async => await _appel<bool>('autorisations') ?? false;

  @override
  Future<List<AppareilImprimante>> appaires() async => _liste(await _appel<List<Object?>>('bluetoothAppaires'));

  @override
  Future<List<AppareilImprimante>> rechercher({Duration duree = const Duration(seconds: 12)}) async =>
      _liste(await _appel<List<Object?>>('bluetoothRechercher', {'duree': duree.inMilliseconds}));

  @override
  Future<void> activerBluetooth() => _appel<bool>('bluetoothActiver');

  @override
  Future<void> envoyerBluetooth(String adresse, Uint8List octets) =>
      _appel<bool>('bluetoothEnvoyer', {'adresse': adresse, 'octets': octets});

  @override
  Future<List<AppareilImprimante>> usb() async => _liste(await _appel<List<Object?>>('usbListe'));

  @override
  Future<void> envoyerUsb(int vendorId, int productId, Uint8List octets) =>
      _appel<bool>('usbEnvoyer', {'vendorId': vendorId, 'productId': productId, 'octets': octets});
}

class TransportBluetooth implements TransportImpression {
  final String adresse;
  final PontImprimantes pont;
  TransportBluetooth(this.adresse, {PontImprimantes? pont}) : pont = pont ?? PontImprimantes.instance;

  @override
  Future<void> envoyer(Uint8List octets) => pont.envoyerBluetooth(adresse, octets);
}

class TransportUsb implements TransportImpression {
  final int vendorId;
  final int productId;
  final PontImprimantes pont;
  TransportUsb(this.vendorId, this.productId, {PontImprimantes? pont}) : pont = pont ?? PontImprimantes.instance;

  @override
  Future<void> envoyer(Uint8List octets) => pont.envoyerUsb(vendorId, productId, octets);
}
