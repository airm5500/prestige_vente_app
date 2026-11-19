// lib/services/largeur_ticket.dart
// 4.14.0 — Largeur du ticket (58 ou 80 mm) selon l'appareil (demande du 19/11/2026, ticket 58 / 80 mm) :
//  - terminal à imprimante INTÉGRÉE (Sunmi) : la largeur est celle de l'imprimante, lue sur elle (58 mm sur les
//    terminaux V2s, P2…), imposée, sans choix. C'est ce qui a manqué le 19/11 : un terminal réglé sur 80 mm composait
//    des lignes de 48 caractères pour une imprimante de 32 ;
//  - appareil sans imprimante intégrée (tablette) : le réglage « Largeur du ticket » (58 ou 80 mm, gardé sur
//    l'appareil) ; le réglage s'applique au ticket suivant, sans redémarrer.
// La règle de largeur est celle du serveur (ModeleTicketService.largeurValide) : 58 mm ou moins → 58, sinon 80.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Largeur (58 / 80) de l'imprimante intégrée, ou null si l'appareil n'en a pas.
typedef DetecteurImprimanteIntegree = Future<int?> Function();

class LargeurTicket {
  LargeurTicket._();

  /// Canal du paquet sunmi_printer_plus (lecture directe : PAPER_SIZE renvoie 1 = 58 mm, 2 = 80 mm ; la méthode
  /// `paperSize()` du paquet échoue sur 2).
  static const MethodChannel _canal = MethodChannel('sunmi_printer_plus');

  /// Détection remplaçable dans les tests.
  static DetecteurImprimanteIntegree detecteur = _detecter;

  static int? _integree;
  static bool _lue = false;

  /// Règle du serveur : 58 mm ou moins → 58, tout le reste → 80.
  static int valide(int mm) => mm <= 58 ? 58 : 80;

  /// Points imprimables à 203 dpi : 384 en 58 mm, 576 en 80 mm.
  static int points(int mm) => valide(mm) == 58 ? 384 : 576;

  static Future<int?> _detecter() async {
    // Imprimante intégrée Sunmi : Android seulement (rien à lire ailleurs, ni dans les tests).
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final version = await _canal.invokeMethod<String>('PRINTER_VERSION').timeout(const Duration(seconds: 3));
      final v = (version ?? '').trim();
      if (v.isEmpty || v.toUpperCase() == 'NOT FOUND') return null;
      final papier = await _canal.invokeMethod<int>('PAPER_SIZE').timeout(const Duration(seconds: 3));
      return papier == 2 ? 80 : 58;
    } catch (_) {
      return null;
    }
  }

  /// Largeur de l'imprimante intégrée (lue une fois), null sans imprimante intégrée.
  static Future<int?> integree() async {
    if (_lue) return _integree;
    _integree = await detecteur();
    _lue = true;
    return _integree;
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
