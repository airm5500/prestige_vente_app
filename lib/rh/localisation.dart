// lib/rh/localisation.dart
// Position du téléphone pour la voie A (si l'officine l'exige : `pointage.gps`), via geolocator.
// La position n'est jamais journalisée ; elle part seulement avec le pointage.
import 'package:geolocator/geolocator.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';

/// Position obtenue, ou raison claire de l'échec.
class ResultatPosition {
  final PositionPointage? position;
  final String? erreur;

  /// L'utilisateur peut corriger dans les réglages (localisation coupée, autorisation refusée définitivement).
  final bool reglages;
  const ResultatPosition.ok(PositionPointage this.position)
      : erreur = null,
        reglages = false;
  const ResultatPosition.echec(String this.erreur, {this.reglages = false}) : position = null;
  bool get ok => position != null;
}

abstract class Localisateur {
  /// [exigee] : l'officine exige la position (sinon on ne la demande que si l'autorisation est déjà donnée).
  Future<ResultatPosition> position({required bool exigee});
  Future<void> ouvrirReglages();
}

class GeoLocalisateur implements Localisateur {
  const GeoLocalisateur();

  @override
  Future<ResultatPosition> position({required bool exigee}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const ResultatPosition.echec('La localisation du téléphone est coupée : activez-la pour pointer.', reglages: true);
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied && exigee) p = await Geolocator.requestPermission();
      if (p == LocationPermission.deniedForever) {
        return const ResultatPosition.echec(
            'Localisation refusée pour Prestige Mobile : autorisez-la dans les réglages du téléphone pour pointer.',
            reglages: true);
      }
      if (p == LocationPermission.denied || p == LocationPermission.unableToDetermine) {
        return const ResultatPosition.echec('Localisation refusée : l\'officine exige la position du téléphone pour pointer.');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      return ResultatPosition.ok(PositionPointage(pos.latitude, pos.longitude, pos.accuracy));
    } catch (_) {
      return const ResultatPosition.echec('Position introuvable : réessayez à l\'extérieur ou près d\'une fenêtre.');
    }
  }

  @override
  Future<void> ouvrirReglages() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {}
  }
}

/// Précision au-delà de laquelle on prévient avant l'envoi (le serveur décide : 2 × rayon).
const double precisionDouteuseM = 100;
