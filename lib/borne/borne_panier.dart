// lib/borne/borne_panier.dart
// Panier de la borne : LOCAL (aucun appel serveur avant « Valider »), quantités bornées
// (1 à maxParProduit par produit, maxArticles au total), produits indisponibles refusés.
import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/borne/borne_produit.dart';

class BorneLigne {
  final BorneProduit produit;
  final int qte;
  const BorneLigne(this.produit, this.qte);
  int get total => produit.prix * qte;
  BorneLigne avec({BorneProduit? produit, int? qte}) => BorneLigne(produit ?? this.produit, qte ?? this.qte);
}

class BornePanier extends ChangeNotifier {
  int maxParProduit;
  int maxArticles;
  BornePanier({this.maxParProduit = 10, this.maxArticles = 15});

  final List<BorneLigne> _lignes = [];
  List<BorneLigne> get lignes => List.unmodifiable(_lignes);
  bool get vide => _lignes.isEmpty;
  int get articles => _lignes.fold(0, (s, l) => s + l.qte);
  int get total => _lignes.fold(0, (s, l) => s + l.total);
  int qteDe(String id) => _lignes.where((l) => l.produit.id == id).fold(0, (s, l) => s + l.qte);

  /// Quantité encore ajoutable pour ce produit.
  int restePour(String id) {
    final parProduit = maxParProduit - qteDe(id);
    final global = maxArticles - articles;
    return parProduit < global ? (parProduit < 0 ? 0 : parProduit) : (global < 0 ? 0 : global);
  }

  /// Ajoute ; renvoie un message si refusé (null = ajouté).
  String? ajouter(BorneProduit p, int qte) {
    if (!p.disponible) return 'Produit indisponible pour le moment.';
    if (qte < 1) return 'Quantité invalide.';
    if (qteDe(p.id) + qte > maxParProduit) return 'Au maximum $maxParProduit par produit à la borne.';
    if (articles + qte > maxArticles) return 'Panier limité à $maxArticles articles.';
    if (qteDe(p.id) + qte > p.stock) return 'Stock insuffisant (${p.stock} disponible${p.stock > 1 ? 's' : ''}).';
    final i = _lignes.indexWhere((l) => l.produit.id == p.id);
    if (i < 0) {
      _lignes.add(BorneLigne(p, qte));
    } else {
      _lignes[i] = BorneLigne(p, _lignes[i].qte + qte);
    }
    notifyListeners();
    return null;
  }

  /// Change la quantité d'une ligne (0 = retirer) ; message si refusé.
  String? changer(String id, int qte) {
    final i = _lignes.indexWhere((l) => l.produit.id == id);
    if (i < 0) return 'Produit absent du panier.';
    if (qte <= 0) {
      _lignes.removeAt(i);
      notifyListeners();
      return null;
    }
    final l = _lignes[i];
    if (qte > maxParProduit) return 'Au maximum $maxParProduit par produit à la borne.';
    if (articles - l.qte + qte > maxArticles) return 'Panier limité à $maxArticles articles.';
    if (qte > l.produit.stock) return 'Stock insuffisant (${l.produit.stock} disponible${l.produit.stock > 1 ? 's' : ''}).';
    _lignes[i] = l.avec(qte: qte);
    notifyListeners();
    return null;
  }

  void retirer(String id) => changer(id, 0);

  /// Remplace les lignes après vérification serveur (prix / stock à jour).
  void remplacer(List<BorneLigne> lignes) {
    _lignes
      ..clear()
      ..addAll(lignes.where((l) => l.qte > 0));
    notifyListeners();
  }

  /// Vide le panier (confidentialité : retour à l'accueil).
  void vider() {
    if (_lignes.isEmpty) return;
    _lignes.clear();
    notifyListeners();
  }
}
