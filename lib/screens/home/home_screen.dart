// lib/screens/home/home_screen.dart
// 30/12/2025 (Final: Watchdog Licence + Menu Dynamique + Bandeau Statut)

import 'dart:async'; // Pour le Timer de sécurité
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/screens/depot_sale/depot_sale_list_screen.dart';
import 'package:provider/provider.dart';

// Providers existants
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';

// AJOUT : Provider de Licence
import 'package:prestige_vente_app/providers/licence_provider.dart';

// Écrans d'authentification et Licence
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/screens/auth/settings_screen.dart';
import 'package:prestige_vente_app/screens/auth/licence_registration_screen.dart'; // Pour la redirection forcée

// Écrans Métiers
import 'package:prestige_vente_app/screens/pre_vente/pre_vente_screen.dart';
import 'package:prestige_vente_app/screens/assurance_sale/assurance_sale_screen.dart';
import 'package:prestige_vente_app/screens/carnet_sale/carnet_sale_screen.dart';
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

class MenuItem {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  MenuItem({required this.id, required this.label, required this.icon, required this.color, required this.onTap});
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// AJOUT : WidgetsBindingObserver pour détecter la mise en veille/réveil
class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  List<MenuItem> _displayMenuItems = [];

  late SaleProvider _saleProvider;
  late BlControlProvider _blProvider;

  // AJOUT : Timer pour la surveillance périodique
  Timer? _licenceWatchdogTimer;

  @override
  void initState() {
    super.initState();

    // 1. Abonnement au cycle de vie de l'application
    WidgetsBinding.instance.addObserver(this);

    _saleProvider = Provider.of<SaleProvider>(context, listen: false);
    _blProvider = Provider.of<BlControlProvider>(context, listen: false);

    // 2. Actions au chargement de la page (après le build)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AuthProvider>(context, listen: false).loadOfficineInfo();

      // Lancement des alertes (popups) si l'échéance est proche
      Provider.of<LicenceProvider>(context, listen: false).checkReminders(context);
    });

    // 3. Lancement du "Chien de Garde" (Vérification toutes les heures)
    _licenceWatchdogTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      _performSecurityCheck();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _buildDynamicMenu();
  }

  @override
  void dispose() {
    // Nettoyage impératif pour éviter les fuites de mémoire
    WidgetsBinding.instance.removeObserver(this);
    _licenceWatchdogTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // AJOUT : Détecte quand l'application revient au premier plan (sortie de veille)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // L'utilisateur a rallumé la tablette ou réouvert l'app
      _performSecurityCheck();
    }
  }

  // AJOUT : Logique de sécurité pour bloquer l'app si la licence expire en cours de route
  void _performSecurityCheck() async {
    final licenceProvider = Provider.of<LicenceProvider>(context, listen: false);

    // Vérification locale rapide (Date tablette vs Date fin licence)
    bool isExpired = licenceProvider.checkLocalExpiration();

    if (isExpired) {
      // Si la date est dépassée, on redirige de force vers l'écran d'enregistrement
      // On vide la pile de navigation pour empêcher le retour
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LicenceRegistrationScreen()),
              (route) => false,
        );
      }
    }
  }

  void navigate(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _buildDynamicMenu() {
    final Map<String, MenuItem> allAvailableMenus = {
      'prevente': MenuItem(id: 'prevente', label: 'Pre/Vente', icon: Icons.point_of_sale, color: Colors.blue.shade700, onTap: () => navigate(const PreVenteScreen())),
      'assurance': MenuItem(id: 'assurance', label: 'Pre/Vente Assurance', icon: Icons.health_and_safety, color: Colors.red.shade700, onTap: () => navigate(const AssuranceSaleScreen())),
      'carnet': MenuItem(id: 'carnet', label: 'Vente Carnet', icon: Icons.book, color: Colors.green.shade800, onTap: () => navigate(const CarnetSaleScreen())),
      'caisse': MenuItem(id: 'caisse', label: 'Gestion Caisse', icon: Icons.calculate, color: Colors.lime.shade700, onTap: () => navigate(const CaisseScreen())),
      'perimes': MenuItem(id: 'perimes', label: 'Gestion Périmés', icon: Icons.dangerous, color: Colors.deepOrange.shade600, onTap: () => navigate(const PerimeMainScreen())),
      'evaluation': MenuItem(id: 'evaluation', label: 'Évaluation Vente', icon: Icons.bar_chart, color: Colors.green.shade700, onTap: () => navigate(const ProductEvaluationScreen())),
      'search': MenuItem(id: 'search', label: 'Recherche Article', icon: Icons.search, color: Colors.orange.shade700, onTap: () => navigate(const ProductSearchScreen())),
      'update_perim': MenuItem(id: 'update_perim', label: 'Mise à jour Péremption', icon: Icons.date_range, color: Colors.purple.shade700, onTap: () => navigate(const ExpirationUpdateScreen())),
      'delivery': MenuItem(id: 'delivery', label: 'Contrôle Livraison', icon: Icons.inventory_2, color: Colors.teal.shade700, onTap: () => navigate(const DeliveryListScreen())),
      'bl_control': MenuItem(id: 'bl_control', label: 'Pointage BL Stock', icon: Icons.checklist, color: Colors.cyan.shade700, onTap: () => navigate(const BlListScreen())),
      'reception': MenuItem(id: 'reception', label: 'Contrôle Réception', icon: Icons.inventory_2_outlined, color: Colors.indigo.shade700, onTap: () => navigate(const ReceptionListScreen())),
      'update_ean': MenuItem(id: 'update_ean', label: 'Mise à jour EAN', icon: Icons.qr_code_scanner, color: Colors.indigo.shade400, onTap: () => navigate(const EanUpdateScreen())),
      'update_emplacement': MenuItem(id: 'update_emplacement', label: 'Mise à jour Emplacement', icon: Icons.location_on, color: Colors.brown.shade400, onTap: () => navigate(const EmplacementUpdateScreen())),
      'stock': MenuItem(id: 'stock', label: 'État de Stock', icon: Icons.inventory, color: Colors.blueGrey.shade600, onTap: () => navigate(const StockReportScreen())),
      'depot': MenuItem(
          id: 'depot',
          label: 'Vente Dépôt',
          icon: Icons.store_mall_directory, // Ou une autre icône appropriée
          color: Colors.brown.shade600,
          onTap: () => navigate(const DepotSaleListScreen()) // Importez l'écran d'abord
      ),
      'proforma': MenuItem(
          id: 'proforma',
          label: 'Proforma / Devis',
          icon: Icons.description,
          color: Colors.purple.shade600,
          onTap: () => navigate(const ProformaListScreen())
      ),
      'analyse_article': MenuItem(
          id: 'analyse_article',
          label: 'Analyse Article',
          icon: Icons.analytics, // Icône suggérée
          color: Colors.blueGrey.shade700,
          onTap: () => navigate(const ArticleAnalysisScreen())
      ),
      'ajustement': MenuItem(
          id: 'ajustement',
          label: 'Ajustement Stock',
          icon: Icons.inventory_2, // Icône de stock/inventaire
          color: Colors.orange.shade700, // Orange pour distinguer des ventes
          onTap: () => navigate(const AjustementScreen())
      )
    };

    final settings = Provider.of<SettingsProvider>(context);
    List<String> order = settings.menuOrder;
    List<String> hidden = settings.hiddenMenuIds;

    List<MenuItem> newList = [];

    for (String id in order) {
      if (allAvailableMenus.containsKey(id) && !hidden.contains(id)) {
        newList.add(allAvailableMenus[id]!);
        allAvailableMenus.remove(id);
      }
    }

    allAvailableMenus.forEach((id, item) {
      if (!hidden.contains(id)) {
        newList.add(item);
      }
    });

    bool changed = false;
    if (_displayMenuItems.length != newList.length) {
      changed = true;
    } else {
      for (int i = 0; i < newList.length; i++) {
        if (_displayMenuItems[i].id != newList[i].id) {
          changed = true;
          break;
        }
      }
    }

    if (changed) {
      _displayMenuItems = newList;
    }
  }

  Future<void> _showInfoPopup() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 24),
            Text("Mise à jour..."),
          ],
        ),
      ),
    );

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await Future.wait([
      _saleProvider.fetchPreventes(),
      _blProvider.fetchBonsLivraison(dtStart: today, dtEnd: today, query: '')
    ]);

    if (!mounted) return;
    Navigator.of(context).pop();

    showDialog(
      context: context,
      builder: (ctx) {
        final preventesCount = _saleProvider.preventes.length;
        final blCount = _blProvider.bonsLivraison.where((b) => b.statutTraitement != "TERMINE").length;

        return AlertDialog(
          title: const Text('Tâches en attente'),
          contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: Icon(Icons.history_toggle_off, color: Colors.orange.shade700),
                title: Text('$preventesCount Prévente(s) en attente'),
                onTap: () { Navigator.of(ctx).pop(); navigate(const PreVenteScreen(initialTabIndex: 2)); },
              ),
              ListTile(
                leading: Icon(Icons.checklist, color: Colors.cyan.shade700),
                title: Text('$blCount BL(s) à pointer'),
                onTap: () { Navigator.of(ctx).pop(); navigate(const BlListScreen(initialFilter: 'A_TRAITER')); },
              ),
            ],
          ),
          actions: [ TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer')) ],
        );
      },
    );
  }

  // AJOUT : Widget Bandeau de statut Licence
  Widget _buildLicenceStatusBanner() {
    return Consumer<LicenceProvider>(
      builder: (context, provider, child) {
        if (provider.status != LicenceStatus.valid || provider.licence == null) {
          return const SizedBox.shrink();
        }

        final days = provider.remainingDays;

        Color bgColor;
        Color textColor = Colors.white;
        String text;

        if (days <= 7) {
          bgColor = Colors.redAccent;
          text = "URGENT : Licence expire dans $days jour(s)";
        } else if (days <= 30) {
          bgColor = Colors.orange;
          text = "Attention : Licence expire dans $days jours";
        } else {
          bgColor = Colors.green.shade600;
          text = "Licence valide : $days jours restants";
        }

        return Container(
          width: double.infinity,
          color: bgColor,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final size = MediaQuery.of(context).size;
    final bool isTablet = size.width > 600;

    // CONFIGURATION GRILLE
    final int cols = isTablet ? 4 : 2;
    final int rows = 3;
    final int itemsPerPage = cols * rows;

    List<List<MenuItem>> pages = [];
    for (var i = 0; i < _displayMenuItems.length; i += itemsPerPage) {
      pages.add(_displayMenuItems.sublist(
          i, i + itemsPerPage > _displayMenuItems.length ? _displayMenuItems.length : i + itemsPerPage));
    }
    if (pages.isEmpty) pages.add([]);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Prestige Mobile'),
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: _showInfoPopup, tooltip: 'Tâches en attente'),
          IconButton(icon: const Icon(Icons.settings), onPressed: () => navigate(const SettingsScreen()), tooltip: 'Configuration'),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              authProvider.logout();
              Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
            },
            tooltip: 'Déconnexion',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Bandeau de licence toujours visible en haut
            _buildLicenceStatusBanner(),

            // 2. Contenu principal (Menus)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildWelcomeCard(),
                    const SizedBox(height: 12),

                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: pages.length,
                        onPageChanged: (index) => setState(() => _currentPage = index),
                        itemBuilder: (context, pageIndex) {
                          final pageItems = pages[pageIndex];

                          if (pageItems.isEmpty) return const Center(child: Text("Aucun menu disponible"));

                          return Column(
                            children: List.generate(rows, (rowIndex) {
                              return Expanded(
                                child: Row(
                                  children: List.generate(cols, (colIndex) {
                                    final itemIndex = rowIndex * cols + colIndex;

                                    if (itemIndex < pageItems.length) {
                                      return Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.all(6.0),
                                          child: _buildMenuCard(pageItems[itemIndex], isTablet),
                                        ),
                                      );
                                    } else {
                                      return const Expanded(child: SizedBox());
                                    }
                                  }),
                                ),
                              );
                            }),
                          );
                        },
                      ),
                    ),

                    if (pages.length > 1)
                      _buildPageIndicator(pages.length),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Card(
      color: AppColors.primary,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Consumer<AuthProvider>(
          builder: (context, auth, child) {
            final officine = auth.officine;
            return Row(
              children: [
                Icon(Icons.storefront, size: 40, color: Colors.white.withAlpha(204)),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bienvenu(e) à ${officine?.nomComplet ?? ''}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        officine?.fullName ?? '',
                        style: TextStyle(fontSize: 16, color: Colors.white.withAlpha(204)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMenuCard(MenuItem item, bool isTablet) {
    // Tailles originales conservées
    final double iconSize = 48;
    final double fontSize = 15;
    final double containerPadding = 12;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(containerPadding),
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, size: iconSize, color: item.color),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: Text(
                  item.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageIndicator(int pageCount) {
    return Container(
      height: 30,
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(pageCount, (index) {
          return Container(
            width: 8.0,
            height: 8.0,
            margin: const EdgeInsets.symmetric(horizontal: 4.0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _currentPage == index
                  ? AppColors.primary
                  : AppColors.primary.withAlpha(77),
            ),
          );
        }),
      ),
    );
  }
}