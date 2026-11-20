// lib/services/imprimante_sunmi.dart
// 5.1.0 — Connexion au service d'impression intégré Sunmi (premier ticket non imprimé, retour du 20/11/2026).
//
// Cause : le paquet sunmi_printer_plus répond `true` à BIND_PRINTER_SERVICE dès que la liaison est DEMANDÉE, avant que
// le service soit réellement connecté (onServiceConnected, toast « Sunmi Printer Service Connected »). Rien ne liait
// l'imprimante au démarrage : au premier ticket, la largeur était lue (PRINTER_VERSION → « NOT FOUND ») avant la
// connexion et mémorisée « aucune imprimante intégrée » pour toute la session (Réimprimer échouait aussi), et les
// commandes du gabarit local partaient vers un service pas encore connecté (perdues sans erreur).
//
// Correctif :
//  - liaison demandée une fois au démarrage sur un terminal Sunmi, sans attendre ([lierAuDemarrage]) ;
//  - avant toute impression ([pret]) : sur un terminal Sunmi, attente de la connexion RÉELLE (version de
//    l'imprimante lisible, ni vide ni « NOT FOUND »), 3 s au plus ; la liaison est redemandée si besoin ;
//  - sur un autre appareil (tablette, téléphone) : rien ne change (aucune attente, même appel qu'avant).
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/services/fingerprint_service.dart';

/// L'appareil est-il un terminal Sunmi (imprimante intégrée attendue) ?
typedef DetecteurSunmi = Future<bool> Function();

class ImprimanteSunmi {
  ImprimanteSunmi._();

  /// Canal du paquet sunmi_printer_plus.
  static const MethodChannel canal = MethodChannel('sunmi_printer_plus');

  /// Détection de l'appareil, remplaçable dans les tests.
  static DetecteurSunmi detecteur = _detecter;

  /// Attente maximale de la connexion du service avant d'abandonner l'impression.
  static Duration delaiConnexion = const Duration(seconds: 3);

  /// Intervalle entre deux lectures de la version de l'imprimante pendant l'attente.
  static Duration intervalle = const Duration(milliseconds: 150);

  static bool? _sunmi;
  static bool _liaisonDemandee = false;

  /// Motif affiché quand le service ne s'est pas connecté à temps (« Réimprimer » réessaie).
  static const String motifNonConnectee = 'imprimante intégrée pas encore prête (service d\'impression non connecté). '
      'Réessayez dans quelques secondes.';

  static Future<bool> _detecter() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final hw = await FingerprintService.hardwareInfo();
      return '${hw['manufacturer'] ?? ''}'.toUpperCase().contains('SUNMI');
    } catch (_) {
      return false;
    }
  }

  /// Terminal Sunmi ? (lu une fois). La réponse est gardée, jamais le Future (un Future créé dans une autre zone,
  /// celle d'un test précédent par exemple, peut ne jamais se terminer dans la suivante).
  static Future<bool> estSunmi() async => _sunmi ??= await detecteur();

  /// Au démarrage de l'application : liaison demandée sur un terminal Sunmi, sans bloquer le démarrage.
  static void lierAuDemarrage() {
    unawaited(() async {
      try {
        if (await estSunmi()) await _lier();
      } catch (_) {}
    }());
  }

  static Future<void> _lier() async {
    _liaisonDemandee = true;
    try {
      await canal.invokeMethod<bool>('BIND_PRINTER_SERVICE');
    } catch (_) {}
  }

  /// Version de l'imprimante si le service est connecté, sinon null (« NOT FOUND » : pas encore lié ; vide : erreur).
  static Future<String?> version() async {
    try {
      final v = (await canal.invokeMethod<String>('PRINTER_VERSION').timeout(const Duration(seconds: 2)) ?? '').trim();
      return v.isEmpty || v.toUpperCase() == 'NOT FOUND' ? null : v;
    } catch (_) {
      return null;
    }
  }

  /// Terminal Sunmi : attend que le service d'impression soit réellement connecté ([delaiConnexion] au plus).
  /// true : connecté ; false : autre appareil, ou service toujours absent après le délai.
  static Future<bool> attendreConnexion({Duration? delai}) async {
    if (!await estSunmi()) return false;
    if (await version() != null) return true;
    // Pas encore connecté : liaison demandée si elle ne l'a jamais été (sinon celle du démarrage est en cours), puis
    // lecture répétée de la version jusqu'au délai.
    if (!_liaisonDemandee) await _lier();
    // Nombre d'essais (et non l'heure) : même comportement sous le temps simulé des tests.
    final essais = ((delai ?? delaiConnexion).inMilliseconds / intervalle.inMilliseconds).ceil();
    for (var i = 0; i < essais; i++) {
      await Future<void>.delayed(intervalle);
      if (await version() != null) return true;
    }
    // Toujours pas connecté (service arrêté ?) : nouvelle demande de liaison, pour l'essai suivant (« Réimprimer »).
    await _lier();
    return false;
  }

  /// Imprimante prête à recevoir des commandes : terminal Sunmi → service réellement connecté ; autre appareil →
  /// réponse de BIND_PRINTER_SERVICE (comportement d'avant la 5.1.0).
  static Future<bool> pret() async {
    if (await estSunmi()) return attendreConnexion();
    try {
      return await canal.invokeMethod<bool>('BIND_PRINTER_SERVICE') == true;
    } catch (_) {
      return false;
    }
  }

  /// Liaison demandée au moins une fois (diagnostic, tests).
  static bool get liaisonDemandee => _liaisonDemandee;

  @visibleForTesting
  static void reinitialiser({DetecteurSunmi? avec, Duration? delai, Duration? pas}) {
    detecteur = avec ?? _detecter;
    _sunmi = null;
    _liaisonDemandee = false;
    delaiConnexion = delai ?? const Duration(seconds: 3);
    intervalle = pas ?? const Duration(milliseconds: 150);
  }
}
