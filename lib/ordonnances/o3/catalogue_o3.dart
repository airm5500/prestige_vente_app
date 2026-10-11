// lib/ordonnances/o3/catalogue_o3.dart
// Étape O3 : sources de la correspondance catalogue (copie locale hors ligne, sinon recherche serveur)
// et compteur local des produits validés sur ordonnance (bonus « réellement vendu »).
import 'dart:convert';

import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/ordonnances/o3/correspondance_o3.dart';
import 'package:prestige_vente_app/ordonnances/o4/apprentissage_o4.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CatalogueO3 {
  CatalogueO3._();

  /// Tous les produits de la copie locale (vide si la copie n'a pas été téléchargée).
  static Future<List<ProductSearchResult>> copieLocale([LocalStore? store]) async {
    final s = store ?? HorsLigne.instance.store;
    final stats = await s.stats();
    if (stats.count(CatalogueCategorie.produits) == 0) return const [];
    final out = <ProductSearchResult>[];
    const paquet = 500;
    while (true) {
      final page = await s.searchProducts('', out.length, paquet);
      out.addAll(page.items);
      if (page.items.length < paquet || out.length >= page.total) break;
    }
    return out;
  }

  /// Correspondance O3 : copie locale complète si disponible, sinon recherche serveur [recherche].
  /// O4 : [apprentissages] (apprentissages par correction) prioritaires ; leurs validations reçues des autres
  /// terminaux nourrissent aussi le bonus « produits vendus ».
  static Future<CorrespondanceO3> creer(ProductPageSearch recherche,
      {LocalStore? store, SourceApprentissages? apprentissages, bool fragments = false}) async {
    final pop = await PopulariteLocale.charger();
    return CorrespondanceO3.auto(
      recherche,
      chargerTout: () => copieLocale(store),
      popularite: apprentissages == null ? pop : PopulariteAvecApprentissages(pop, apprentissages),
      apprentissages: apprentissages,
      fragments: fragments,
    );
  }
}

/// Compteur local (sur l'appareil) des produits validés par le pharmacien sur une ordonnance.
/// Point d'accroche pour un historique de ventes du serveur (même interface [PopulariteProduits]).
class PopulariteLocale implements PopulariteProduits {
  static const _cle = 'ordonnance_o3_produits_valides_v1';
  final Map<String, int> _compteurs;
  PopulariteLocale._(this._compteurs);

  static Future<PopulariteLocale> charger() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_cle);
      if (raw == null) return PopulariteLocale._({});
      return PopulariteLocale._((jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())));
    } catch (_) {
      return PopulariteLocale._({});
    }
  }

  @override
  int ventes(String produitId) => _compteurs[produitId] ?? 0;

  /// Ajoute les produits validés (création de la pré-vente depuis l'ordonnance).
  static Future<void> enregistrer(Iterable<String> produitIds) async {
    try {
      final p = await charger();
      for (final id in produitIds) {
        p._compteurs[id] = (p._compteurs[id] ?? 0) + 1;
      }
      await (await SharedPreferences.getInstance()).setString(_cle, jsonEncode(p._compteurs));
    } catch (_) {}
  }
}
