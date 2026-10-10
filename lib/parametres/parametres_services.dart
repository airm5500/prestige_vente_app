// lib/parametres/parametres_services.dart
// Fonctions remplaçables des réglages (pour les tests) : code admin, ticket d'essai, appareil, pointage.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';

class ParametresServices {
  /// Code administrateur (par défaut : PinCodeDialog.show).
  final Future<bool> Function(BuildContext)? adminCheck;

  /// Ticket d'essai (par défaut : ReceiptService / imprimante Sunmi).
  final Future<void> Function(BuildContext)? printTestTicket;

  /// Infos de l'appareil (par défaut : FingerprintService.hardwareInfo).
  final Future<Map<String, Object?>> Function()? hardwareInfo;

  /// Données du pointage (par défaut : stockage local de l'appareil).
  final PointageRepository? pointageRepository;

  /// Après l'enregistrement du serveur (par défaut : redémarrage par l'écran de démarrage, comme l'original).
  final void Function(BuildContext)? afterServerSaved;

  /// Écran « Organiser l'accueil ».
  final Widget Function()? organiserAccueil;

  const ParametresServices({
    this.adminCheck,
    this.printTestTicket,
    this.hardwareInfo,
    this.pointageRepository,
    this.afterServerSaved,
    this.organiserAccueil,
  });
}
