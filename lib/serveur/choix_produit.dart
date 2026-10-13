// lib/serveur/choix_produit.dart
// Choix d'un produit pour les modules Réserve et Analyse posologie : réutilise la recherche produit de
// l'application (ProductSearchModal : code scanné → produit exact, texte → liste par pages) et son scanner
// (CameraScanScreen, tous les codes des boîtes ; la douchette Sunmi saisit dans le champ de recherche).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/screens/common/camera_scan_screen.dart';
import 'package:prestige_vente_app/screens/common/product_search_modal.dart';

/// Choisit un produit ([code] : code scanné à chercher d'emblée). Null si abandon.
typedef ChoixProduit = Future<ProductSearchResult?> Function(BuildContext context, {String? code});

/// Scanne un code avec l'appareil photo. Null si abandon.
typedef ScanCode = Future<String?> Function(BuildContext context);

Future<ProductSearchResult?> choisirProduitParDefaut(BuildContext context, {String? code}) async {
  ProductSearchResult? choisi;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ProductSearchModal(initialQuery: code ?? '', onProductSelected: (p) => choisi = p),
  );
  return choisi;
}

Future<String?> scannerCodeParDefaut(BuildContext context) =>
    CameraScanScreen.open(context, title: 'Scanner un produit', produit: true, aide: 'Code-barres ou DataMatrix de la boîte');
