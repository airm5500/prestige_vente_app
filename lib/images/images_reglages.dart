// lib/images/images_reglages.dart
// B2 — Réglages des images produits (sur cet appareil).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class ImagesConfig {
  /// Afficher les images du serveur (sans l'API côté serveur : pictogrammes, aucune requête).
  final bool actif;

  /// Vignettes dans les listes de vente (désactivé par défaut : ne pas ralentir la saisie).
  final bool vignettesVentes;

  /// Taille maximale du cache disque (Mo).
  final int cacheMo;

  /// Préchargement en tâche de fond à partir de la copie locale du catalogue (affichage hors ligne).
  final bool prechargement;

  /// Bouton « Photo du produit » dans la fiche produit (réglage administrateur, désactivé par défaut).
  final bool photoTerminal;

  static const int cacheMoDefaut = 500;
  static const int cacheMoMin = 50;
  static const int cacheMoMax = 4000;

  const ImagesConfig({
    this.actif = true,
    this.vignettesVentes = false,
    this.cacheMo = cacheMoDefaut,
    this.prechargement = false,
    this.photoTerminal = false,
  });

  ImagesConfig copyWith({bool? actif, bool? vignettesVentes, int? cacheMo, bool? prechargement, bool? photoTerminal}) => ImagesConfig(
        actif: actif ?? this.actif,
        vignettesVentes: vignettesVentes ?? this.vignettesVentes,
        cacheMo: (cacheMo ?? this.cacheMo).clamp(cacheMoMin, cacheMoMax),
        prechargement: prechargement ?? this.prechargement,
        photoTerminal: photoTerminal ?? this.photoTerminal,
      );

  Map<String, dynamic> toJson() =>
      {'actif': actif, 'vignettesVentes': vignettesVentes, 'cacheMo': cacheMo, 'prechargement': prechargement, 'photoTerminal': photoTerminal};

  static ImagesConfig fromJson(Map<String, dynamic> j) => ImagesConfig(
        actif: j['actif'] != false,
        vignettesVentes: j['vignettesVentes'] == true,
        cacheMo: ((j['cacheMo'] as num?)?.toInt() ?? cacheMoDefaut).clamp(cacheMoMin, cacheMoMax),
        prechargement: j['prechargement'] == true,
        photoTerminal: j['photoTerminal'] == true,
      );
}

class ImagesReglages {
  ImagesReglages._();
  static const _cle = 'images_produits_v1';
  static final ValueNotifier<ImagesConfig> courant = ValueNotifier(const ImagesConfig());

  static Future<ImagesConfig> charger() async {
    try {
      final s = (await SharedPreferences.getInstance()).getString(_cle);
      courant.value = s == null ? const ImagesConfig() : ImagesConfig.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
    } catch (_) {
      courant.value = const ImagesConfig();
    }
    return courant.value;
  }

  static Future<void> enregistrer(ImagesConfig c) async {
    courant.value = c;
    try {
      await (await SharedPreferences.getInstance()).setString(_cle, jsonEncode(c.toJson()));
    } catch (_) {}
  }
}
