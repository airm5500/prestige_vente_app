// lib/services/contraste_impression.dart
// 5.4.0 — Réglage « Contraste d'impression » (Réglages › Impression), gardé sur l'appareil :
//  - Renforcé (par défaut) : ticket du serveur (vente, prévente, borne, réimpression) converti au seuil 160 et traits
//    verticaux d'un seul point doublés (lib/services/ticket_1bit.dart) ; gabarit local (police de l'imprimante) :
//    tout le texte en caractères accentués (gras de l'imprimante, même largeur de colonnes) ;
//  - Normal : rendu de la 5.3.0 (seuil 128, texte normal sauf les lignes en gras).
// Lu sans contexte au moment d'imprimer (ImpressionTicket.rasters, ReceiptService), chargé au démarrage.
import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/services/ticket_1bit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReglageContraste {
  ReglageContraste._();

  /// Clé des préférences (valeurs : « renforce », « normal »).
  static const String cle = 'contraste_impression_v1';

  /// Valeur par défaut : renforcé (retour du pharmacien du 20/11 : libellés pâles sur le SUNMI V3).
  static const ContrasteImpression parDefaut = ContrasteImpression.renforce;

  /// Valeur courante (écoutée par la rubrique Impression).
  static final ValueNotifier<ContrasteImpression> courant = ValueNotifier(parDefaut);

  static ContrasteImpression lire(String? v) => v == 'normal' ? ContrasteImpression.normal : parDefaut;

  static String ecrire(ContrasteImpression c) => c == ContrasteImpression.normal ? 'normal' : 'renforce';

  /// Texte du gabarit local en gras de l'imprimante.
  static bool get texteRenforce => courant.value == ContrasteImpression.renforce;

  /// Au démarrage : valeur gardée sur l'appareil (renforcé si aucune).
  static Future<void> charger() async {
    try {
      courant.value = lire((await SharedPreferences.getInstance()).getString(cle));
    } catch (_) {
      courant.value = parDefaut;
    }
  }

  static Future<void> choisir(ContrasteImpression c) async {
    courant.value = c;
    try {
      await (await SharedPreferences.getInstance()).setString(cle, ecrire(c));
    } catch (_) {}
  }

  @visibleForTesting
  static void reinitialiser([ContrasteImpression c = parDefaut]) => courant.value = c;
}
