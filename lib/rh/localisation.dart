// lib/rh/localisation.dart
// Position du téléphone pour la voie A, via geolocator.
// - Position EXIGÉE par l'officine (`pointage.gps`) : autorisation demandée si besoin, messages clairs.
// - Position NON exigée : envoyée seulement si l'autorisation est DÉJÀ accordée (jamais demandée), délai
//   court ; tout échec est silencieux et le pointage part sans position.
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
  /// [exigee] : l'officine exige la position (autorisation demandée si besoin). Sinon on ne la lit que si
  /// l'autorisation est DÉJÀ donnée, sans jamais la demander.
  Future<ResultatPosition> position({required bool exigee});
  Future<void> ouvrirReglages();
}

/// Délai maximal pour la position facultative (GPS non exigé) : au-delà, le pointage part sans position.
const Duration delaiPositionFacultative = Duration(seconds: 5);

/// Accès à la localisation du téléphone (remplaçable pour les tests).
abstract class PlateformeGeo {
  Future<bool> serviceActif();
  Future<LocationPermission> verifierPermission();
  Future<LocationPermission> demanderPermission();
  Future<PositionPointage> positionActuelle(Duration limite);
  Future<void> ouvrirReglages();
}

class GeolocatorPlateforme implements PlateformeGeo {
  const GeolocatorPlateforme();
  @override
  Future<bool> serviceActif() => Geolocator.isLocationServiceEnabled();
  @override
  Future<LocationPermission> verifierPermission() => Geolocator.checkPermission();
  @override
  Future<LocationPermission> demanderPermission() => Geolocator.requestPermission();
  @override
  Future<PositionPointage> positionActuelle(Duration limite) async {
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: limite),
    );
    return PositionPointage(pos.latitude, pos.longitude, pos.accuracy);
  }

  @override
  Future<void> ouvrirReglages() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}

/// Autorisation déjà accordée (pendant l'utilisation ou toujours).
bool permissionAccordee(LocationPermission p) => p == LocationPermission.whileInUse || p == LocationPermission.always;

class GeoLocalisateur implements Localisateur {
  final PlateformeGeo plateforme;
  const GeoLocalisateur([this.plateforme = const GeolocatorPlateforme()]);

  @override
  Future<ResultatPosition> position({required bool exigee}) => exigee ? _exigee() : _facultative();

  /// GPS exigé : comportement d'origine (demande d'autorisation, messages).
  Future<ResultatPosition> _exigee() async {
    try {
      if (!await plateforme.serviceActif()) {
        return const ResultatPosition.echec('La localisation du téléphone est coupée : activez-la pour pointer.', reglages: true);
      }
      var p = await plateforme.verifierPermission();
      if (p == LocationPermission.denied) p = await plateforme.demanderPermission();
      if (p == LocationPermission.deniedForever) {
        return const ResultatPosition.echec(
            'Localisation refusée pour Prestige Mobile : autorisez-la dans les réglages du téléphone pour pointer.',
            reglages: true);
      }
      if (p == LocationPermission.denied || p == LocationPermission.unableToDetermine) {
        return const ResultatPosition.echec('Localisation refusée : l\'officine exige la position du téléphone pour pointer.');
      }
      return ResultatPosition.ok(await plateforme.positionActuelle(const Duration(seconds: 20)));
    } catch (_) {
      return const ResultatPosition.echec('Position introuvable : réessayez à l\'extérieur ou près d\'une fenêtre.');
    }
  }

  /// GPS non exigé : autorisation VÉRIFIÉE (jamais demandée), délai court, échec silencieux.
  Future<ResultatPosition> _facultative() async {
    try {
      if (!permissionAccordee(await plateforme.verifierPermission())) {
        return const ResultatPosition.echec('Localisation non autorisée.');
      }
      if (!await plateforme.serviceActif()) return const ResultatPosition.echec('Localisation coupée.');
      return ResultatPosition.ok(await plateforme.positionActuelle(delaiPositionFacultative));
    } catch (_) {
      return const ResultatPosition.echec('Position introuvable.');
    }
  }

  @override
  Future<void> ouvrirReglages() async {
    try {
      await plateforme.ouvrirReglages();
    } catch (_) {}
  }
}

/// Précision au-delà de laquelle on prévient avant l'envoi (le serveur décide : 2 × rayon).
const double precisionDouteuseM = 100;
