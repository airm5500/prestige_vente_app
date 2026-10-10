// lib/accueil/accueil_menus.dart
// Catalogue des menus du nouvel accueil : les mêmes 22 menus, écrans et protections que
// l'accueil d'origine (lib/screens/home/home_screen.dart), rangés par familles.
// Ordre et menus masqués : SettingsProvider.menuOrder / hiddenMenuIds (mêmes clés que l'origine).
// Favoris (4 max) : clé propre au nouvel accueil.
import 'package:flutter/material.dart';
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

/// Familles de l'accueil, dans l'ordre d'affichage.
enum MenuFamille { ventes, caisse, reception, stock, produits, equipe }

extension MenuFamilleLabel on MenuFamille {
  String get label => switch (this) {
        MenuFamille.ventes => 'Ventes',
        MenuFamille.caisse => 'Caisse',
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

  const AccueilMenu({
    required this.id,
    required this.label,
    required this.short,
    required this.icon,
    required this.color,
    required this.famille,
    required this.screen,
    this.protege = false,
  });
}

/// Les 22 menus, dans l'ordre par défaut (par famille).
final List<AccueilMenu> accueilMenus = [
  // Ventes
  AccueilMenu(id: 'prevente', label: 'Pre/Vente', short: 'Pré-vente', icon: Icons.point_of_sale, color: Colors.blue.shade700, famille: MenuFamille.ventes, screen: () => VentesVersion.preVente()),
  AccueilMenu(id: 'assurance', label: 'Pre/Vente Assurance', short: 'Assurance', icon: Icons.health_and_safety, color: Colors.red.shade700, famille: MenuFamille.ventes, screen: () => VentesVersion.assurance()),
  AccueilMenu(id: 'carnet', label: 'Vente Carnet', short: 'Carnet', icon: Icons.book, color: Colors.green.shade800, famille: MenuFamille.ventes, screen: () => VentesVersion.carnet()),
  AccueilMenu(id: 'depot', label: 'Vente Dépôt', short: 'Dépôt', icon: Icons.store_mall_directory, color: Colors.brown.shade600, famille: MenuFamille.ventes, screen: () => const DepotSaleListScreen()),
  AccueilMenu(id: 'proforma', label: 'Proforma / Devis', short: 'Proforma', icon: Icons.description, color: Colors.purple.shade600, famille: MenuFamille.ventes, screen: () => const ProformaListScreen()),
  AccueilMenu(id: 'ordonnance', label: 'Vérification Ordonnance', short: 'Ordonnance', icon: Icons.receipt_long, color: Colors.teal.shade600, famille: MenuFamille.ventes, screen: () => const PrescriptionCheckScreen()),
  // Caisse
  AccueilMenu(id: 'caisse', label: 'Gestion Caisse', short: 'Caisse', icon: Icons.calculate, color: Colors.lime.shade700, famille: MenuFamille.caisse, screen: () => const CaisseScreen()),
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
  AccueilMenu(id: 'empreinte', label: 'Pointage', short: 'Pointage', icon: Icons.fingerprint, color: Colors.deepPurple.shade400, famille: MenuFamille.equipe, screen: () => const PointageHomeScreen()),
];

final Map<String, AccueilMenu> accueilMenuById = {for (final m in accueilMenus) m.id: m};

/// Ordre complet des menus : d'abord l'ordre enregistré, puis les menus absents (ordre par défaut).
List<AccueilMenu> orderedMenus(List<String> savedOrder) {
  final out = <AccueilMenu>[];
  final seen = <String>{};
  for (final id in savedOrder) {
    final m = accueilMenuById[id];
    if (m != null && seen.add(id)) out.add(m);
  }
  for (final m in accueilMenus) {
    if (seen.add(m.id)) out.add(m);
  }
  return out;
}

/// Menus par famille, dans l'ordre enregistré ; [hidden] exclus si [withHidden] est faux.
Map<MenuFamille, List<AccueilMenu>> menusByFamille(List<String> savedOrder, Iterable<String> hidden, {bool withHidden = false}) {
  final h = hidden.toSet();
  final map = {for (final f in MenuFamille.values) f: <AccueilMenu>[]};
  for (final m in orderedMenus(savedOrder)) {
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
