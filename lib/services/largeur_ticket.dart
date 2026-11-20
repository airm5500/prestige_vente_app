// lib/services/largeur_ticket.dart
// 4.14.0 — Largeur du ticket (58 ou 80 mm) selon l'appareil (demande du 19/11/2026, ticket 58 / 80 mm) :
//  - terminal à imprimante INTÉGRÉE (Sunmi) : la largeur est celle de l'imprimante, lue sur elle (58 mm sur les
//    terminaux V2s, P2…), imposée, sans choix. C'est ce qui a manqué le 19/11 : un terminal réglé sur 80 mm composait
//    des lignes de 48 caractères pour une imprimante de 32 ;
//  - appareil sans imprimante intégrée (tablette) : le réglage « Largeur du ticket » (58 ou 80 mm, gardé sur
//    l'appareil) ; le réglage s'applique au ticket suivant, sans redémarrer.
// La règle de largeur est celle du serveur (ModeleTicketService.largeurValide) : 58 mm ou moins → 58, sinon 80.
//
// 5.1.0 : la largeur n'est lue qu'une fois le service d'impression Sunmi réellement connecté
// (ImprimanteSunmi.attendreConnexion) ; une lecture faite sans connexion n'est jamais mémorisée (avant : « aucune
// imprimante intégrée » gardé pour toute la session si le premier ticket partait avant la connexion).
import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/services/imprimante_sunmi.dart';

/// Largeur (58 / 80) de l'imprimante intégrée, ou null si l'appareil n'en a pas.
typedef DetecteurImprimanteIntegree = Future<int?> Function();

class LargeurTicket {
  LargeurTicket._();

  /// Détection remplaçable dans les tests.
  static DetecteurImprimanteIntegree detecteur = _detecter;

  static int? _integree;
  static bool _lue = false;

  /// Règle du serveur : 58 mm ou moins → 58, tout le reste → 80.
  static int valide(int mm) => mm <= 58 ? 58 : 80;

  /// Points imprimables à 203 dpi : 384 en 58 mm, 576 en 80 mm.
  static int points(int mm) => valide(mm) == 58 ? 384 : 576;

  static Future<int?> _detecter() async {
    // Imprimante intégrée Sunmi seulement (rien à lire ailleurs, ni dans les tests), service réellement connecté.
    if (!await ImprimanteSunmi.attendreConnexion()) return null;
    try {
      // Lecture directe : PAPER_SIZE renvoie 1 = 58 mm, 2 = 80 mm (la méthode `paperSize()` du paquet échoue sur 2).
      final papier = await ImprimanteSunmi.canal.invokeMethod<int>('PAPER_SIZE').timeout(const Duration(seconds: 3));
      return papier == 2 ? 80 : 58;
    } catch (_) {
      return null;
    }
  }

  /// Largeur de l'imprimante intégrée (lue une fois), null sans imprimante intégrée. 5.1.0 : sur un terminal Sunmi
  /// dont le service n'est pas (encore) connecté, rien n'est mémorisé : la lecture est refaite au ticket suivant.
  static Future<int?> integree() async {
    if (_lue) return _integree;
    final mm = await detecteur();
    if (mm != null || !await ImprimanteSunmi.estSunmi()) {
      _integree = mm;
      _lue = true;
    }
    return mm;
  }

  /// Largeur connue sans attendre (null : pas encore lue ou pas d'imprimante intégrée).
  static int? get integreeConnue => _integree;

  /// Largeur à utiliser pour imprimer : celle de l'imprimante intégrée si elle existe, sinon le réglage.
  static Future<int> pourImpression(int reglage) async => valide(await integree() ?? reglage);

  @visibleForTesting
  static void reinitialiser({DetecteurImprimanteIntegree? avec}) {
    detecteur = avec ?? _detecter;
    _integree = null;
    _lue = false;
  }
}
