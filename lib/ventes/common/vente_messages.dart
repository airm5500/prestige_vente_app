// lib/ventes/common/vente_messages.dart
// Messages communs des ventes : message du serveur lisible, panne ≠ refus, caisse fermée.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

/// Message du serveur sans balises HTML ni espaces superflus.
String venteMessage(String? raw, {String fallback = 'Opération impossible.'}) {
  final t = (raw ?? '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return t.isEmpty ? fallback : t;
}

/// Bandeau bas : erreur (rouge), panne avec « Réessayer », ou information.
void showVenteSnack(BuildContext context, String message, {bool error = false, VoidCallback? onRetry, Color? color, Duration? duree}) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: color ?? (error ? Colors.red.shade700 : null),
    duration: duree ?? Duration(seconds: onRetry != null ? 6 : (error ? 4 : 2)),
    action: onRetry == null ? null : SnackBarAction(label: 'Réessayer', textColor: Colors.white, onPressed: onRetry),
  ));
}

/// Affiche l'échec d'un résultat : message du serveur (refus) ou panne (avec « Réessayer » si fourni).
void showVenteFailure(BuildContext context, VenteResult<dynamic> r, {VoidCallback? onRetry}) {
  final msg = venteMessage(r.message);
  // 4.15.2 (demande 64) : panier verrouillé par un paiement mobile money : message du serveur tel quel, laissé 8 s
  // (deux phrases à lire : ne pas modifier, terminer avec ce paiement).
  final verrou = r is VenteRefused && r.panierVerrouille;
  showVenteSnack(context, msg, error: true, onRetry: r is VenteFailed ? onRetry : null, duree: verrou ? dureeMessageVerrou : null);
}

/// 4.15.2 : durée d'affichage d'un refus « panier verrouillé » (demande 64).
const dureeMessageVerrou = Duration(seconds: 8);

/// Caisse fermée : même proposition qu'aujourd'hui (ouvrir la caisse). Renvoie true si traité.
Future<bool> handleCaisseFermee(BuildContext context, VenteResult<dynamic> r) async {
  if (r is! VenteRefused || !r.caisseFermee) return false;
  return Constants.checkAndOpenCaisse(context, {'success': false, 'msg': 'Votre caisse est fermée. ${venteMessage(r.message)}'});
}
