// lib/ventes/core/gs1_recherche.dart
// 4.9.0 — recherche d'un produit à partir d'une étiquette GS1 scannée, commune aux écrans de vente (nouvelle et
// ancienne interface) : verdict de Gs1Vente (périmé, lot, mode — ou « comme avant »), puis le produit par le chemin
// d'avant (ProductLookup.byCode : GTIN → EAN-13 / CIP7 / UPC, ou le CIP rendu par le serveur).
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/ventes/core/gs1_vente.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

class RechercheGs1 {
  /// Produit exact (une seule ligne) ou candidats ; vide si refusé ou introuvable.
  final List<ProductSearchResult> produits;

  /// Boîte refusée (rien à ajouter) : message à afficher.
  final Gs1Refus? refus;

  /// Lot différent (avertissement au vendeur, jamais au client).
  final String? avertissement;

  /// Recherche impossible (panne) : message.
  final String? erreur;

  /// Codes essayés (message « introuvable »).
  final List<String> essayes;
  const RechercheGs1({this.produits = const [], this.refus, this.avertissement, this.erreur, this.essayes = const []});
  bool get exact => produits.length == 1 && refus == null;
}

/// null si [brut] n'est pas une étiquette GS1 (code-barres, CIP, nom : chemin d'avant, inchangé).
Future<RechercheGs1?> rechercherEtiquetteGs1(String brut, ProductPageSearch search, {Gs1Vente? gs1}) async {
  if (!Gs1Vente.ressembleGs1(brut) && !Gs1Vente.estEtiquetteEtendue(brut)) return null;
  final v = await (gs1 ?? Gs1Vente.instance).verdict(brut);
  String code = brut;
  String? avert;
  switch (v) {
    case Gs1Refus():
      return RechercheGs1(refus: v);
    case Gs1Accepte(code: final c, avertissement: final a):
      code = c;
      avert = a;
    case Gs1CommeAvant():
      break;
  }
  final r = await ProductLookup.byCode(code, search);
  if (r is! VenteOk<CodeLookup>) return RechercheGs1(erreur: r.message ?? 'Recherche impossible');
  final f = r.value;
  if (f.exact != null) return RechercheGs1(produits: [f.exact!], avertissement: avert, essayes: f.tried);
  return RechercheGs1(produits: f.candidates, avertissement: f.candidates.isEmpty ? null : avert, essayes: f.tried);
}
