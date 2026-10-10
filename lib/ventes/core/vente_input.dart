// lib/ventes/core/vente_input.dart
// Contrôles de saisie communs aux ventes : rien d'absurde ne part au serveur.
import 'package:flutter/services.dart';

class VenteInput {
  VenteInput._();

  static const int maxQuantity = 9999;
  static const int confirmQuantityAbove = 50;
  static const int maxPrice = 999999999;
  static const int maxQueryLength = 60;
  static const int maxBonLength = 30;
  static const int maxNameLength = 60;

  /// Recherche serveur à partir de 3 caractères (règle actuelle de la recherche produit).
  static const int minQueryLength = 3;

  static final RegExp _control = RegExp(r'[\x00-\x1F\x7F]');

  /// Quantité vendue : entier de 1 à 9 999 (null si invalide).
  static int? parseQuantity(String? text) {
    final v = int.tryParse((text ?? '').trim());
    if (v == null || v < 1 || v > maxQuantity) return null;
    return v;
  }

  static String? quantityError(String? text) {
    final t = (text ?? '').trim();
    if (t.isEmpty) return 'Quantité requise';
    return parseQuantity(t) == null ? 'Entre 1 et $maxQuantity' : null;
  }

  /// Prix unitaire (libre) : entier de 0 à 999 999 999 (null si invalide).
  static int? parsePrice(String? text) {
    final v = int.tryParse((text ?? '').trim());
    if (v == null || v < 0 || v > maxPrice) return null;
    return v;
  }

  static String? priceError(String? text) {
    final t = (text ?? '').trim();
    if (t.isEmpty) return 'Prix requis';
    return parsePrice(t) == null ? 'Prix invalide' : null;
  }

  /// Texte de recherche nettoyé (caractères parasites retirés, longueur limitée).
  static String cleanQuery(String? text) {
    final t = (text ?? '').replaceAll(_control, '').trim();
    return t.length > maxQueryLength ? t.substring(0, maxQueryLength) : t;
  }

  /// N° de bon : espaces et caractères parasites retirés, 30 caractères max.
  static String cleanBon(String? text) {
    final t = (text ?? '').replaceAll(_control, '').trim();
    return t.length > maxBonLength ? t.substring(0, maxBonLength) : t;
  }

  /// Nom / prénom / matricule : nettoyé, espaces multiples réduits.
  static String cleanName(String? text) {
    final t = (text ?? '').replaceAll(_control, '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > maxNameLength ? t.substring(0, maxNameLength) : t;
  }

  /// Taux de couverture 0..100 (min 1 à la création d'un client, comme aujourd'hui).
  static int? parseTaux(String? text, {int min = 0}) {
    final v = int.tryParse((text ?? '').trim());
    if (v == null || v < min || v > 100) return null;
    return v;
  }

  /// Numéros de bon en double dans la même vente (clé = compteTp).
  static bool hasDuplicateBons(Map<String, String> bons) {
    final values = bons.values.map(cleanBon).where((b) => b.isNotEmpty).map((b) => b.toUpperCase()).toList();
    return values.toSet().length != values.length;
  }

  static List<TextInputFormatter> get quantityFormatters =>
      [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)];
  static List<TextInputFormatter> get priceFormatters =>
      [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)];
  static List<TextInputFormatter> get tauxFormatters =>
      [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)];
  static List<TextInputFormatter> get bonFormatters =>
      [FilteringTextInputFormatter.deny(_control), LengthLimitingTextInputFormatter(maxBonLength)];
  static List<TextInputFormatter> get nameFormatters =>
      [FilteringTextInputFormatter.deny(_control), LengthLimitingTextInputFormatter(maxNameLength)];
  static List<TextInputFormatter> get queryFormatters =>
      [FilteringTextInputFormatter.deny(_control), LengthLimitingTextInputFormatter(maxQueryLength)];
}
