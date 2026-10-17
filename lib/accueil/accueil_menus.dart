// lib/accueil/accueil_menus.dart
// Catalogue des menus du nouvel accueil : les mêmes 22 menus, écrans et protections que
// l'accueil d'origine (lib/screens/home/home_screen.dart), rangés par familles.
// Ordre et menus masqués : SettingsProvider.menuOrder / hiddenMenuIds (mêmes clés que l'origine).
// Favoris (4 max) : clé propre au nouvel accueil.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/plateforme/capacites.dart';
import 'package:prestige_vente_app/images/photos_produits_screen.dart';
import 'package:prestige_vente_app/images/images_reglages.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prestige_vente_app/ventes/ventes_version.dart';
import 'package:prestige_vente_app/screens/retour_frs/retour_home_screen.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_home_screen.dart';
import 'package:prestige_vente_app/screens/depot_sale/depot_sale_list_screen.dart';
import 'package:prestige_vente_app/screens/caisse/caisse_screen.dart';
import 'package:prestige_vente_app/screens/perimes/perime_main_screen.dart';
import 'package:prestige_vente_app/screens/product_evaluation/product_evaluation_screen.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_screen.dart';
import 'package:prestige_vente_app/screens/expiration_update/expiration_update_screen.dart';
import 'package:prestige_vente_app/screens/delivery_control/delivery_list_screen.dart';
import 'package:prestige_vente_app/screens/bl_control/bl_list_screen.dart';
import 'package:prestige_vente_app/screens/product_update/ean_update_screen.dart';
import 'package:prestige_vente_app/screens/product_update/emplacement_update_screen.dart';
import 'package:prestige_vente_app/screens/stock_report/stock_report_screen.dart';
import 'package:prestige_vente_app/screens/reception_control/reception_list_screen.dart';
import 'package:prestige_vente_app/screens/proforma/proforma_list_screen.dart';
import 'package:prestige_vente_app/screens/analysis/article_analysis_screen.dart';
import 'package:prestige_vente_app/screens/ajustement/ajustement_screen.dart';
import 'package:prestige_vente_app/screens/prescription/prescription_check_screen.dart';
import 'package:prestige_vente_app/screens/pointage/pointage_home_screen.dart';
import 'package:prestige_vente_app/rh/rh_pointage_screen.dart';
import 'package:prestige_vente_app/borne/borne_reglages_page.dart';
import 'package:prestige_vente_app/droits/droits_modules.dart';
import 'package:prestige_vente_app/fiche_client/ordonnances_clients_screen.dart';
import 'package:prestige_vente_app/posos/posos_screen.dart';
import 'package:prestige_vente_app/reserve/reserve_screen.dart';

/// Familles de l'accueil, dans l'ordre d'affichage.
/// La Caisse est rangée dans « Ventes » (retour client) : les familles ne sont pas enregistrées
/// (ordre, menus masqués et favoris sont mémorisés par identifiant de menu) : rien à migrer.
enum MenuFamille { ventes, reception, stock, produits, equipe }

extension MenuFamilleLabel on MenuFamille {
  String get label => switch (this) {
        MenuFamille.ventes => 'Ventes',
        MenuFamille.reception => 'Réception & fournisseurs',
        MenuFamille.stock => 'Stock',
        MenuFamille.produits => 'Produits',
        MenuFamille.equipe => 'Équipe',
      };
}

class AccueilMenu {
  final String id;

  /// Libellé d'origine (recherche, listes).
  final String label;

  /// Libellé court des tuiles.
  final String short;
  final IconData icon;
  final Color color;
  final MenuFamille famille;

  /// Protégé par le code administrateur (PinCodeDialog), comme à l'origine.
  final bool protege;
  final Widget Function() screen;

  /// Droit d'accès (menu absent de l'accueil, de la recherche et de l'organisation s'il renvoie faux).
  /// Null : menu ouvert à tous (comme à l'origine).
  final bool Function()? autorise;

  const AccueilMenu({
    required this.id,
    required this.label,
    required this.short,
    required this.icon,
    required this.color,
    required this.famille,
    required this.screen,
    this.protege = false,
    this.autorise,
  });

  /// Le menu est accessible au compte connecté.
  bool get visible => autorise?.call() ?? true;
}

/// Les 23 menus, dans l'ordre par défaut (par famille).
final List<AccueilMenu> accueilMenus = [
  // Ventes
  // Pré-vente : panier préparé pour l'encaissement (shopping_cart_checkout), distinct de la Caisse (calculate)
  // et du bouton « Encaisser » des ventes (point_of_sale) ; tuiles, favoris et recherche des menus.
  AccueilMenu(id: 'prevente', label: 'Pre/Vente', short: 'Pré-vente', icon: Icons.shopping_cart_checkout, color: Colors.blue.shade700, famille: MenuFamille.ventes, screen: () => VentesVersion.preVente()),
  AccueilMenu(id: 'assurance', label: 'Pre/Vente Assurance', short: 'Assurance', icon: Icons.health_and_safety, color: Colors.red.shade700, famille: MenuFamille.ventes, screen: () => VentesVersion.assurance()),
  AccueilMenu(id: 'carnet', label: 'Vente Carnet', short: 'Carnet', icon: Icons.book, color: Colors.green.shade800, famille: MenuFamille.ventes, screen: () => VentesVersion.carnet()),
  AccueilMenu(id: 'depot', label: 'Vente Dépôt', short: 'Dépôt', icon: Icons.store_mall_directory, color: Colors.brown.shade600, famille: MenuFamille.ventes, screen: () => const DepotSaleListScreen()),
  AccueilMenu(id: 'proforma', label: 'Proforma / Devis', short: 'Proforma', icon: Icons.description, color: Colors.purple.shade600, famille: MenuFamille.ventes, screen: () => const ProformaListScreen()),
  AccueilMenu(id: 'ordonnance', label: 'Vérification Ordonnance', short: 'Ordonnance', icon: Icons.receipt_long, color: Colors.teal.shade600, famille: MenuFamille.ventes, screen: () => const PrescriptionCheckScreen()),
  // Caisse (famille Ventes)
  AccueilMenu(id: 'caisse', label: 'Gestion Caisse', short: 'Caisse', icon: Icons.calculate, color: Colors.lime.shade700, famille: MenuFamille.ventes, screen: () => const CaisseScreen()),
  // Réception & fournisseurs
  AccueilMenu(id: 'reception_bl', label: 'Réception BL', short: 'Réception BL', icon: Icons.local_shipping, color: Colors.teal.shade700, famille: MenuFamille.reception, screen: () => const ReceptionHomeScreen()),
  AccueilMenu(id: 'retour_frs', label: 'Retour Fournisseur', short: 'Retour frs', icon: Icons.assignment_return, color: Colors.red.shade400, famille: MenuFamille.reception, screen: () => const RetourHomeScreen()),
  AccueilMenu(id: 'delivery', label: 'Contrôle Livraison', short: 'Livraison', icon: Icons.inventory_2, color: Colors.teal.shade700, famille: MenuFamille.reception, screen: () => const DeliveryListScreen()),
  AccueilMenu(id: 'reception', label: 'Contrôle Réception', short: 'Réception', icon: Icons.inventory_2_outlined, color: Colors.indigo.shade700, famille: MenuFamille.reception, screen: () => const ReceptionListScreen()),
  AccueilMenu(id: 'bl_control', label: 'Pointage BL Stock', short: 'Pointage BL', icon: Icons.checklist, color: Colors.cyan.shade700, famille: MenuFamille.reception, screen: () => const BlListScreen()),
  // Stock
  AccueilMenu(id: 'stock', label: 'État de Stock', short: 'État stock', icon: Icons.inventory, color: Colors.blueGrey.shade600, famille: MenuFamille.stock, screen: () => const StockReportScreen()),
  AccueilMenu(id: 'ajustement', label: 'Ajustement Stock', short: 'Ajustement', icon: Icons.inventory_2, color: Colors.orange.shade700, famille: MenuFamille.stock, protege: true, screen: () => const AjustementScreen()),
  AccueilMenu(id: 'perimes', label: 'Gestion Périmés', short: 'Périmés', icon: Icons.dangerous, color: Colors.deepOrange.shade600, famille: MenuFamille.stock, screen: () => const PerimeMainScreen()),
  AccueilMenu(id: 'update_perim', label: 'Mise à jour Péremption', short: 'Péremption', icon: Icons.date_range, color: Colors.purple.shade700, famille: MenuFamille.stock, screen: () => const ExpirationUpdateScreen()),
  // Produits
  AccueilMenu(id: 'search', label: 'Recherche Article', short: 'Recherche', icon: Icons.search, color: Colors.orange.shade700, famille: MenuFamille.produits, screen: () => const ProductSearchScreen()),
  AccueilMenu(id: 'analyse_article', label: 'Analyse Article', short: 'Analyse', icon: Icons.analytics, color: Colors.blueGrey.shade700, famille: MenuFamille.produits, screen: () => const ArticleAnalysisScreen()),
  AccueilMenu(id: 'evaluation', label: 'Évaluation Vente', short: 'Évaluation', icon: Icons.bar_chart, color: Colors.green.shade700, famille: MenuFamille.produits, screen: () => const ProductEvaluationScreen()),
  AccueilMenu(id: 'update_ean', label: 'Mise à jour EAN', short: 'EAN', icon: Icons.qr_code_scanner, color: Colors.indigo.shade400, famille: MenuFamille.produits, screen: () => const EanUpdateScreen()),
  AccueilMenu(id: 'update_emplacement', label: 'Mise à jour Emplacement', short: 'Emplacement', icon: Icons.location_on, color: Colors.brown.shade400, famille: MenuFamille.produits, screen: () => const EmplacementUpdateScreen()),
  // Équipe
  // Pointage LOCAL (empreinte / PIN, lib/pointage) : rien n'est envoyé à Prestige. Libellé explicite et menu masqué
  // par défaut (SettingsProvider.menusMasques ; réaffichable par un administrateur : Paramètres › Équipe).
  // 4.5.0 : absent sur iPhone / iPad (empreinte et NFC du terminal : ponts Android).
  AccueilMenu(id: 'empreinte', label: 'Pointage local (non envoyé à Prestige)', short: 'Pointage local', icon: Icons.fingerprint, color: Colors.deepPurple.shade400, famille: MenuFamille.equipe, autorise: _pointageLocalPossible, screen: () => const PointageHomeScreen()),
  // Pointage présence sur le serveur Prestige (« Mon pointage » au téléphone, « Terminal de pointage » :
  // badge, NFC, empreinte ; présences) : voies proposées selon les routes du serveur et le droit RH du compte
  // (désactivées et expliquées sinon). Identifiant `pointage_rh` conservé (favoris, ordre, menus masqués).
  AccueilMenu(id: 'pointage_rh', label: 'Pointage présence', short: 'Pointage présence', icon: Icons.how_to_reg, color: Colors.indigo.shade500, famille: MenuFamille.equipe, screen: () => const RhPointageScreen()),
];

bool _pointageLocalPossible() => CapacitesPlateforme.courant.pointageLocal;

final Map<String, AccueilMenu> accueilMenuById = {for (final m in accueilMenus) m.id: m};

/// « Borne / vente discrète » (B1/B2) : entrée du groupe Ventes réservée au compte administrateur, qui ouvre
/// la configuration de la borne (Réglages › Borne libre-service : activation sur CET appareil, désactivée par
/// défaut — rien n'est activé automatiquement). Protégée par le code administrateur, comme la rubrique des
/// réglages. Hors de [accueilMenus] : pas d'ordre, de masquage ni de favori (menus d'origine inchangés).
final AccueilMenu menuBorneAdmin = AccueilMenu(
  id: 'borne_admin',
  label: 'Borne / vente discrète',
  short: 'Borne',
  icon: Icons.storefront,
  color: Colors.indigo.shade700,
  famille: MenuFamille.ventes,
  protege: true,
  screen: () => const BornePage(),
);

/// Familles affichées : [menuBorneAdmin] ajouté en fin du groupe Ventes pour l'administrateur.
Map<MenuFamille, List<AccueilMenu>> avecMenusAdmin(Map<MenuFamille, List<AccueilMenu>> familles, {required bool admin}) {
  // 4.5.0 : pas de borne sur iPhone / iPad (épinglage Android, ticket sur l'imprimante Sunmi).
  if (!admin || !CapacitesPlateforme.courant.borne) return familles;
  return {for (final e in familles.entries) e.key: e.key == MenuFamille.ventes ? [...e.value, menuBorneAdmin] : e.value};
}
/// Menus soumis à un droit, ajoutés après les 23 menus d'origine (catalogue d'origine inchangé). Ils ne figurent
/// que si le compte connecté y a droit ([AccueilMenu.visible]) ; ils ne sont ni organisables ni proposés en favoris.
final List<AccueilMenu> menusSousDroits = [
  // Analyse posologie (Posos via Prestige) : interactions, contre-indications, posologies. Compte connecté.
  AccueilMenu(id: 'posos', label: 'Analyse posologie', short: 'Posologie', icon: Icons.health_and_safety_outlined, color: Colors.pink.shade600, famille: MenuFamille.ventes, autorise: () => DroitsModules.instance.posos, screen: () => const PososScreen()),
  // Ordonnances des clients (onglet « Fiche client ») : droit Prestige P_ORDONNANCE_CLIENT.
  AccueilMenu(id: 'ordonnances_clients', label: 'Ordonnances des clients', short: 'Fiche client', icon: Icons.assignment_ind, color: Colors.teal.shade800, famille: MenuFamille.ventes, autorise: () => DroitsModules.instance.ordonnancesConsulter, screen: () => const OrdonnancesClientsScreen()),
  // Réserve : réappros rayon ↔ réserve (suggestion puis traitement). Administrateur (+ droit dédié quand le serveur l'exposera).
  AccueilMenu(id: 'reserve', label: 'Réserve', short: 'Réserve', icon: Icons.warehouse_outlined, color: Colors.deepPurple.shade600, famille: MenuFamille.stock, autorise: () => DroitsModules.instance.reserve, screen: () => const ReserveScreen()),
  // 4.4.0 — Photos produits : scanner, photographier, OK → produit suivant. Mêmes droits que l'ajout de photo
  // de la fiche produit (réglage « photo terminal », ou administrateur avec « photoAdmin » ; droit du serveur).
  AccueilMenu(
      id: 'photos_produits',
      label: 'Photos produits',
      short: 'Photos',
      icon: Icons.add_photo_alternate_outlined,
      color: Colors.indigo.shade500,
      famille: MenuFamille.stock,
      autorise: () => menuPhotosProduitsVisible(config: ImagesReglages.courant.value, admin: DroitsModules.instance.adminLocal),
      screen: () => const PhotosProduitsScreen()),
];

final Map<String, AccueilMenu> _tousMenusById = {for (final m in [...accueilMenus, ...menusSousDroits]) m.id: m};

/// Ordre complet des menus : d'abord l'ordre enregistré, puis les menus absents (ordre par défaut).
/// Les menus non autorisés au compte connecté ([AccueilMenu.visible]) n'y figurent pas.
List<AccueilMenu> orderedMenus(List<String> savedOrder) {
  final out = <AccueilMenu>[];
  final seen = <String>{};
  for (final id in savedOrder) {
    final m = _tousMenusById[id];
    if (m != null && m.visible && seen.add(id)) out.add(m);
  }
  for (final m in [...accueilMenus, ...menusSousDroits]) {
    if (m.visible && seen.add(m.id)) out.add(m);
  }
  return out;
}

/// Menus par famille, dans l'ordre enregistré ; [hidden] exclus si [withHidden] est faux.
Map<MenuFamille, List<AccueilMenu>> menusByFamille(List<String> savedOrder, Iterable<String> hidden, {bool withHidden = false}) {
  final h = hidden.toSet();
  final map = {for (final f in MenuFamille.values) f: <AccueilMenu>[]};
  for (final m in orderedMenus(savedOrder)) {
    // Organisation de l'accueil ([withHidden]) : les menus soumis à un droit n'y sont pas proposés (ni ordre, ni
    // masquage, ni favoris) ; ils s'affichent à la fin de leur famille quand le compte y a droit.
    if (withHidden && menusSousDroits.contains(m)) continue;
    if (withHidden || !h.contains(m.id)) map[m.famille]!.add(m);
  }
  return map;
}

/// Texte simplifié pour la recherche : minuscules, sans accents ni ponctuation.
String normaliser(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyo';
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// Menus dont le nom (ou la famille) contient tous les mots de [query].
List<AccueilMenu> chercherMenus(String query, Iterable<AccueilMenu> menus) {
  final mots = normaliser(query).split(' ').where((w) => w.isNotEmpty).toList();
  if (mots.isEmpty) return const [];
  return menus.where((m) {
    final t = normaliser('${m.label} ${m.short} ${m.famille.label}');
    return mots.every(t.contains);
  }).toList();
}

/// Favoris de l'accueil (4 au plus), mémorisés sur l'appareil.
class AccueilFavoris {
  AccueilFavoris._();
  static const key = 'accueil_favoris_v1';
  static const int max = 4;
  static const List<String> parDefaut = ['prevente', 'assurance', 'search', 'reception_bl'];

  /// Ne garde que des menus connus, sans doublon, 4 au plus.
  static List<String> nettoyer(Iterable<String> ids) {
    final out = <String>[];
    for (final id in ids) {
      if (accueilMenuById.containsKey(id) && !out.contains(id)) out.add(id);
      if (out.length >= max) break;
    }
    return out;
  }

  static Future<List<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getStringList(key);
      return v == null ? List.of(parDefaut) : nettoyer(v);
    } catch (_) {
      return List.of(parDefaut);
    }
  }

  static Future<void> save(List<String> ids) async {
    try {
      await (await SharedPreferences.getInstance()).setStringList(key, nettoyer(ids));
    } catch (_) {}
  }
}
