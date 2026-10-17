// lib/plateforme/capacites.dart
// 4.5.0 — Capacités de la plateforme (Android / iOS) : ce que l'appareil sait faire NATIVEMENT.
//
// Prestige Mobile est conçu pour les terminaux Sunmi (Android). Sur iPhone et iPad (TestFlight, 4.5.0), les
// fonctions qui reposent sur un pont natif Android ou sur un service Sunmi n'existent pas : elles sont MASQUÉES
// (menu, bouton, rubrique absents) ou répondent « indisponible » SANS aucun appel natif :
//   - imprimante thermique Sunmi (sunmi_printer_plus : sur iOS, le plugin n'est qu'une coquille vide) ;
//   - lecteur d'empreinte Sunmi (canal prestige/fingerprint) ;
//   - NFC (canal prestige/nfc) ;
//   - borne libre-service (épinglage de l'écran, canal prestige/kiosque, et ticket sur l'imprimante Sunmi) ;
//   - pointage local (empreinte / PIN du terminal) ;
//   - scanner intégré : la douchette Sunmi « tape » au clavier ; sur iOS, un lecteur Bluetooth en mode clavier
//     fonctionne de la même façon (rien à masquer) — l'appareil photo reste disponible.
// Disponibles sur iOS : tout ce qui passe par le réseau (ventes, stock, ordonnances, pointage « Mon pointage » et
// terminal par badge / caméra), l'appareil photo (mobile_scanner, capture guidée et photo de contrôle via
// camera_avfoundation), l'OCR ML Kit, les PDF (impression AirPrint / partage), le stockage sécurisé (trousseau).
//
// Point d'entrée unique : [CapacitesPlateforme.courant] (remplaçable dans les tests ; sinon déduit de
// defaultTargetPlatform, que les tests peuvent fixer avec debugDefaultTargetPlatformOverride).
import 'package:flutter/foundation.dart';

class CapacitesPlateforme {
  /// Android (terminal Sunmi ou téléphone Android).
  final bool android;

  /// iPhone / iPad.
  final bool ios;

  const CapacitesPlateforme({required this.android, required this.ios});

  static const CapacitesPlateforme androidSunmi = CapacitesPlateforme(android: true, ios: false);
  static const CapacitesPlateforme iphoneIpad = CapacitesPlateforme(android: false, ios: true);

  /// Remplacement explicite (tests) ; null : déduit de la plateforme.
  static CapacitesPlateforme? forcee;

  static CapacitesPlateforme get courant {
    final f = forcee;
    if (f != null) return f;
    if (kIsWeb) return const CapacitesPlateforme(android: false, ios: false);
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => iphoneIpad,
      TargetPlatform.android => androidSunmi,
      // Postes de test (Linux, macOS, Windows) : comme Android, où toute l'application a été conçue et testée.
      _ => androidSunmi,
    };
  }

  /// Ponts natifs Android de l'application (empreinte, NFC, kiosque) et services Sunmi.
  bool get pontsAndroid => !ios;

  /// Imprimante thermique Sunmi (tickets de vente, prévente, borne, rapports).
  bool get imprimanteSunmi => !ios;

  /// Lecteur d'empreinte (service Sunmi, BiometricPrompt Android).
  bool get empreinte => !ios;

  /// Lecture NFC des badges (pont natif Android).
  bool get nfc => !ios;

  /// Borne libre-service : épinglage de l'écran (Android) et ticket imprimé sur la Sunmi.
  bool get borne => !ios;

  /// Pointage LOCAL (empreinte / PIN du terminal, menu masqué par défaut).
  bool get pointageLocal => !ios;

  /// Appareil photo : scan des codes, capture guidée, photo de contrôle (Android et iOS).
  bool get camera => true;

  /// Nom de l'appareil pour les messages (« sur iPhone / iPad »).
  String get nomAppareil => ios ? 'iPhone / iPad' : 'ce terminal';

  /// Motif affiché quand une fonction n'existe pas sur cet appareil.
  String indisponible(String fonction) => '$fonction : indisponible sur iPhone / iPad.';
}
