// lib/prestigepos/demarrage_auto.dart
// PrestigePOS 1.1.0 — démarrage automatique de la borne avec l'appareil (coupure de courant, redémarrage).
//
// Pourquoi pas seulement « au démarrage » : depuis Android 10, une application ne peut plus ouvrir son écran depuis
// l'arrière-plan (un récepteur BOOT_COMPLETED est bloqué), sauf exceptions. Deux moyens fiables, combinés :
//   1. PrestigePOS APPLICATION D'ACCUEIL : réglage activé → l'écran d'accueil « PrestigePOS » est proposé à Android
//      (alias d'activité HOME, désactivé par défaut) ; on le choisit « Toujours » : au démarrage, Android ouvre
//      lui-même PrestigePOS (Android 7 à 14, Sunmi compris), et la touche Accueil ramène à la borne ;
//   2. PROPRIÉTAIRE DE L'APPAREIL (facultatif, `adb shell dpm set-device-owner com.dici.prestigepos/.PosAdminReceiver`) :
//      PrestigePOS est autorisé en tâche verrouillée → la borne se verrouille SANS confirmation ; le récepteur de
//      démarrage peut aussi rouvrir la borne (exception d'Android pour le propriétaire de l'appareil).
//   Le récepteur de démarrage (BOOT_COMPLETED) rouvre la borne sur Android 9 et moins, et en propriétaire de l'appareil.
// Réglage désactivé par défaut, dans l'Administration (code administrateur). « Revenir à Android » le désactive,
// arrête le verrouillage et ouvre l'accueil d'Android : sortie toujours possible, même si PrestigePOS est l'accueil.
// Licence : sans licence valide, PrestigePOS s'ouvre sur « Licence Prestige absente » (la borne ne travaille pas).
// Canal « prestigepos/demarrage » (DemarrageBridge.kt, saveur pos seulement). Hors Android (tests) : simulé.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// État du démarrage automatique sur l'appareil.
@immutable
class EtatDemarrage {
  /// Réglage « Démarrer automatiquement avec l'appareil ».
  final bool actif;

  /// L'accueil « PrestigePOS » est proposé à Android (alias HOME activé).
  final bool accueilPropose;

  /// PrestigePOS est l'application d'accueil choisie par défaut (« Toujours »).
  final bool accueilParDefaut;

  /// PrestigePOS est propriétaire de l'appareil (verrouillage sans confirmation).
  final bool proprietaire;

  /// Version d'Android (API) ; 0 si inconnue.
  final int api;

  const EtatDemarrage({this.actif = false, this.accueilPropose = false, this.accueilParDefaut = false, this.proprietaire = false, this.api = 0});

  factory EtatDemarrage.depuis(Object? m, {required bool actif}) {
    final j = m is Map ? m : const {};
    bool b(String k) => j[k] == true;
    return EtatDemarrage(
      actif: actif,
      accueilPropose: b('accueilPropose'),
      accueilParDefaut: b('accueilParDefaut'),
      proprietaire: b('proprietaire'),
      api: j['api'] is int ? j['api'] as int : 0,
    );
  }

  /// La borne se rouvrira seule au prochain démarrage de l'appareil.
  bool get fiable => actif && (accueilParDefaut || proprietaire || (api > 0 && api < 29));

  /// Ce qu'il reste à faire (texte affiché dans l'Administration) ; vide si tout est prêt.
  String get conseil {
    if (!actif) return '';
    if (accueilParDefaut || proprietaire) return '';
    if (api > 0 && api < 29) return 'Android ${_version(api)} : la borne se rouvrira seule au démarrage. Choisir PrestigePOS comme application d\'accueil reste recommandé.';
    return 'Dernière étape : choisissez PrestigePOS comme application d\'accueil et touchez « Toujours ».';
  }

  static String _version(int api) => switch (api) {
        24 => '7.0',
        25 => '7.1',
        26 => '8.0',
        27 => '8.1',
        28 => '9',
        _ => 'API $api',
      };
}

/// Accès à Android (remplacé dans les tests).
abstract class PlateformeDemarrage {
  Future<Map<Object?, Object?>?> etat();
  Future<void> activer(bool actif);
  Future<void> ouvrirChoixAccueil();
  Future<void> revenirAndroid();
  Future<void> retirerProprietaire();
}

class CanalDemarrage implements PlateformeDemarrage {
  static const MethodChannel canal = MethodChannel('prestigepos/demarrage');

  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<Map<Object?, Object?>?> etat() async {
    if (!_android) return null;
    return canal.invokeMethod<Map<Object?, Object?>>('etat');
  }

  @override
  Future<void> activer(bool actif) async {
    if (_android) await canal.invokeMethod<bool>('activer', {'actif': actif});
  }

  @override
  Future<void> ouvrirChoixAccueil() async {
    if (_android) await canal.invokeMethod<bool>('ouvrirChoixAccueil');
  }

  @override
  Future<void> revenirAndroid() async {
    if (_android) await canal.invokeMethod<bool>('revenirAndroid');
  }

  @override
  Future<void> retirerProprietaire() async {
    if (_android) await canal.invokeMethod<bool>('retirerProprietaire');
  }
}

class DemarrageAuto {
  DemarrageAuto._();

  /// Réglage (SharedPreferences de PrestigePOS) ; désactivé par défaut.
  static const cle = 'prestigepos_demarrage_auto_v1';

  static PlateformeDemarrage plateforme = CanalDemarrage();

  static final ValueNotifier<EtatDemarrage> courant = ValueNotifier(const EtatDemarrage());

  static Future<bool> _reglage() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(cle) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Relit le réglage et l'état d'Android. Jamais d'exception.
  static Future<EtatDemarrage> lire() async {
    final actif = await _reglage();
    Map<Object?, Object?>? m;
    try {
      m = await plateforme.etat();
    } catch (_) {
      m = null;
    }
    return courant.value = EtatDemarrage.depuis(m, actif: actif);
  }

  /// Au lancement : Android remis d'accord avec le réglage (après une mise à jour de l'application, par exemple).
  static Future<void> synchroniser() async {
    final actif = await _reglage();
    try {
      await plateforme.activer(actif);
    } catch (_) {}
    await lire();
  }

  /// Active ou désactive le démarrage automatique (Administration, après le code administrateur).
  static Future<EtatDemarrage> activer(bool actif) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(cle, actif);
    } catch (_) {}
    try {
      await plateforme.activer(actif);
    } catch (_) {}
    return lire();
  }

  /// Écran d'Android « Application d'accueil » (choisir PrestigePOS, « Toujours »).
  static Future<void> ouvrirChoixAccueil() async {
    try {
      await plateforme.ouvrirChoixAccueil();
    } catch (_) {}
  }

  /// Annule « propriétaire de l'appareil » (étape adb du mode d'emploi).
  static Future<EtatDemarrage> retirerProprietaire() async {
    try {
      await plateforme.retirerProprietaire();
    } catch (_) {}
    return lire();
  }

  /// Sortie vers Android : réglage désactivé, verrouillage arrêté, accueil d'Android ouvert.
  static Future<void> revenirAndroid() async {
    await activer(false);
    try {
      await plateforme.revenirAndroid();
    } catch (_) {}
  }
}

/// Plate-forme simulée (tests) : enregistre les appels.
class DemarrageSimule implements PlateformeDemarrage {
  final appels = <String>[];
  bool accueilPropose = false;
  bool accueilParDefaut = false;
  bool proprietaire = false;
  int api = 33;

  @override
  Future<Map<Object?, Object?>?> etat() async =>
      {'accueilPropose': accueilPropose, 'accueilParDefaut': accueilPropose && accueilParDefaut, 'proprietaire': proprietaire, 'api': api};

  @override
  Future<void> activer(bool actif) async {
    appels.add('activer:$actif');
    accueilPropose = actif;
  }

  @override
  Future<void> ouvrirChoixAccueil() async {
    appels.add('ouvrirChoixAccueil');
    accueilParDefaut = true;
  }

  @override
  Future<void> revenirAndroid() async => appels.add('revenirAndroid');

  @override
  Future<void> retirerProprietaire() async {
    appels.add('retirerProprietaire');
    proprietaire = false;
  }
}
