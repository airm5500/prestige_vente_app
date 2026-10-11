// lib/borne/borne_config.dart
// B1 — Borne de vente libre-service : réglages propres à CET appareil (désactivée par défaut).
// Les réglages sont dans SharedPreferences (aucun secret) ; le mot de passe de l'utilisateur borne
// est dans le stockage sécurisé d'Android (flutter_secure_storage, chiffré par le Keystore),
// jamais en clair dans SharedPreferences.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Présentation de la borne (maquettes §3.4).
enum BornePresentation { vitrine, listeRapide, guidee }

extension BornePresentationInfo on BornePresentation {
  String get label => switch (this) {
        BornePresentation.vitrine => 'Vitrine',
        BornePresentation.listeRapide => 'Liste rapide',
        BornePresentation.guidee => 'Guidée',
      };

  String get detail => switch (this) {
        BornePresentation.vitrine => 'Grandes cartes, style boutique (tablette, borne)',
        BornePresentation.listeRapide => 'Liste dense : nom, prix, code (terminal Sunmi)',
        BornePresentation.guidee => 'Étapes 1-2-3, gros boutons (tous publics)',
      };
}

/// Catégorie mise en avant : libellé affiché + mot-clé recherché (recherche « contient »).
/// Le serveur expose les rayons (/common/rayons) mais la recherche de vente ne filtre pas par rayon :
/// les catégories sont donc des mots-clés configurables.
class BorneCategorie {
  final String libelle;
  final String motCle;
  const BorneCategorie(this.libelle, this.motCle);

  @override
  bool operator ==(Object other) => other is BorneCategorie && other.libelle == libelle && other.motCle == motCle;
  @override
  int get hashCode => Object.hash(libelle, motCle);

  /// Lecture d'une ligne « Libellé = mot-clé » (ou « mot-clé » seul).
  static BorneCategorie? parse(String line) {
    final t = line.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    if (t.isEmpty) return null;
    final i = t.indexOf('=');
    final lib = (i < 0 ? t : t.substring(0, i)).trim();
    final mot = (i < 0 ? t : t.substring(i + 1)).trim();
    if (lib.isEmpty || mot.length < BorneConfig.minRecherche) return null;
    String cut(String s, int n) => s.length > n ? s.substring(0, n) : s;
    return BorneCategorie(cut(lib, 24), cut(mot.toUpperCase(), 30));
  }

  String get ligne => '$libelle = $motCle';
}

@immutable
class BorneConfig {
  /// Mode borne actif sur cet appareil (désactivé par défaut).
  final bool actif;
  final BornePresentation presentation;

  /// Retour à l'accueil après [inactivite] secondes sans action (avertissement 10 s avant).
  final int inactivite;

  /// Quantité maximale par produit (1 à 10).
  final int maxParProduit;

  /// Nombre maximal d'articles dans le panier (somme des quantités).
  final int maxArticles;

  /// Login Prestige de l'utilisateur borne (vendeur des préventes de la borne). Mot de passe : stockage sécurisé.
  final String login;
  final String accueil;
  final List<BorneCategorie> categories;

  /// Codes produits (CIP) mis en avant sur l'accueil.
  final List<String> vedettes;

  /// Ticket « discret » : sans nom des produits (désactivé par défaut : le client veut les produits sur le ticket).
  final bool ticketDiscret;

  static const int minRecherche = 3;
  static const int inactiviteDefaut = 60;
  static const int inactiviteMin = 20;
  static const int inactiviteMax = 600;
  static const int maxParProduitPlafond = 10;
  static const int maxArticlesDefaut = 15;
  static const int maxArticlesPlafond = 50;
  static const String accueilDefaut = 'Trouvez vos produits en toute discrétion';

  static const List<BorneCategorie> categoriesDefaut = [
    BorneCategorie('Douleur', 'DOLI'),
    BorneCategorie('Rhume', 'RHUM'),
    BorneCategorie('Hygiène', 'SAVON'),
    BorneCategorie('Bébé', 'LAIT'),
    BorneCategorie('Vitamines', 'VITAM'),
    BorneCategorie('Intime', 'INTIM'),
  ];

  const BorneConfig({
    this.actif = false,
    this.presentation = BornePresentation.vitrine,
    this.inactivite = inactiviteDefaut,
    this.maxParProduit = maxParProduitPlafond,
    this.maxArticles = maxArticlesDefaut,
    this.login = '',
    this.accueil = accueilDefaut,
    this.categories = categoriesDefaut,
    this.vedettes = const [],
    this.ticketDiscret = false,
  });

  /// Valeurs bornées (une valeur absurde enregistrée ne casse jamais la borne).
  BorneConfig normalisee() => copyWith(
        inactivite: inactivite.clamp(inactiviteMin, inactiviteMax),
        maxParProduit: maxParProduit.clamp(1, maxParProduitPlafond),
        maxArticles: maxArticles.clamp(1, maxArticlesPlafond),
        accueil: accueil.trim().isEmpty ? accueilDefaut : (accueil.trim().length > 80 ? accueil.trim().substring(0, 80) : accueil.trim()),
        login: login.trim(),
        vedettes: vedettes.map((v) => v.replaceAll(RegExp(r'[^0-9A-Za-z]'), '')).where((v) => v.length >= 3).take(12).toList(),
        categories: categories.take(12).toList(),
      );

  BorneConfig copyWith({
    bool? actif,
    BornePresentation? presentation,
    int? inactivite,
    int? maxParProduit,
    int? maxArticles,
    String? login,
    String? accueil,
    List<BorneCategorie>? categories,
    List<String>? vedettes,
    bool? ticketDiscret,
  }) =>
      BorneConfig(
        actif: actif ?? this.actif,
        presentation: presentation ?? this.presentation,
        inactivite: inactivite ?? this.inactivite,
        maxParProduit: maxParProduit ?? this.maxParProduit,
        maxArticles: maxArticles ?? this.maxArticles,
        login: login ?? this.login,
        accueil: accueil ?? this.accueil,
        categories: categories ?? this.categories,
        vedettes: vedettes ?? this.vedettes,
        ticketDiscret: ticketDiscret ?? this.ticketDiscret,
      );

  Map<String, dynamic> toJson() => {
        'actif': actif,
        'presentation': presentation.name,
        'inactivite': inactivite,
        'maxParProduit': maxParProduit,
        'maxArticles': maxArticles,
        'login': login,
        'accueil': accueil,
        'categories': [for (final c in categories) {'l': c.libelle, 'm': c.motCle}],
        'vedettes': vedettes,
        'ticketDiscret': ticketDiscret,
      };

  static BorneConfig fromJson(Map<String, dynamic> j) {
    int i(Object? v, int d) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;
    final cats = j['categories'];
    return BorneConfig(
      actif: j['actif'] == true,
      presentation: BornePresentation.values.asNameMap()['${j['presentation']}'] ?? BornePresentation.vitrine,
      inactivite: i(j['inactivite'], inactiviteDefaut),
      maxParProduit: i(j['maxParProduit'], maxParProduitPlafond),
      maxArticles: i(j['maxArticles'], maxArticlesDefaut),
      login: '${j['login'] ?? ''}',
      accueil: '${j['accueil'] ?? accueilDefaut}',
      categories: cats is List
          ? [
              for (final c in cats)
                if (c is Map && '${c['l'] ?? ''}'.isNotEmpty && '${c['m'] ?? ''}'.isNotEmpty) BorneCategorie('${c['l']}', '${c['m']}')
            ]
          : categoriesDefaut,
      vedettes: j['vedettes'] is List ? [for (final v in j['vedettes'] as List) '$v'] : const [],
      ticketDiscret: j['ticketDiscret'] == true,
    ).normalisee();
  }
}

/// Stockage du mot de passe de l'utilisateur borne (remplaçable dans les tests).
abstract class BorneSecrets {
  Future<String?> lire();
  Future<void> ecrire(String? motDePasse);
}

/// Stockage sécurisé Android (Keystore) via flutter_secure_storage.
class SecureBorneSecrets implements BorneSecrets {
  static const _cle = 'borne_mot_de_passe_v1';
  final FlutterSecureStorage _s;
  const SecureBorneSecrets([this._s = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true))]);

  @override
  Future<String?> lire() async {
    try {
      return await _s.read(key: _cle);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> ecrire(String? motDePasse) async {
    if (motDePasse == null || motDePasse.isEmpty) {
      await _s.delete(key: _cle);
    } else {
      await _s.write(key: _cle, value: motDePasse);
    }
  }
}

/// Mémoire (tests).
class MemoireBorneSecrets implements BorneSecrets {
  String? valeur;
  MemoireBorneSecrets([this.valeur]);
  @override
  Future<String?> lire() async => valeur;
  @override
  Future<void> ecrire(String? motDePasse) async => valeur = (motDePasse == null || motDePasse.isEmpty) ? null : motDePasse;
}

/// Réglages de la borne de cet appareil.
class BorneReglages {
  BorneReglages._();
  static const _cle = 'borne_config_v1';

  /// Réglages courants (chargés au démarrage par [charger]).
  static final ValueNotifier<BorneConfig> courant = ValueNotifier(const BorneConfig());

  /// Stockage du mot de passe (remplacé par [MemoireBorneSecrets] dans les tests).
  static BorneSecrets secrets = const SecureBorneSecrets();

  static Future<BorneConfig> charger() async {
    try {
      final s = (await SharedPreferences.getInstance()).getString(_cle);
      courant.value = s == null ? const BorneConfig() : BorneConfig.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
    } catch (_) {
      courant.value = const BorneConfig();
    }
    return courant.value;
  }

  static Future<void> enregistrer(BorneConfig c) async {
    final n = c.normalisee();
    courant.value = n;
    try {
      await (await SharedPreferences.getInstance()).setString(_cle, jsonEncode(n.toJson()));
    } catch (_) {}
  }
}
