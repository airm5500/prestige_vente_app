// lib/screens/home/home_screen.dart
// 12/11/2025 20:30 (Version Finale : Zero Scroll - Flex Layout)
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';

// Écrans
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/screens/auth/settings_screen.dart';
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

class MenuItem {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  MenuItem({required this.label, required this.icon, required this.color, required this.onTap});
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  List<MenuItem> _allMenuItems = [];

  late SaleProvider _saleProvider;
  late BlControlProvider _blProvider;

  @override
  void initState() {
    super.initState();
    _saleProvider = Provider.of<SaleProvider>(context, listen: false);
    _blProvider = Provider.of<BlControlProvider>(context, listen: false);
    _initMenuItems();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void navigate(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _initMenuItems() {
    _allMenuItems = [
      MenuItem(label: 'Pre/Vente', icon: Icons.point_of_sale, color: Colors.blue.shade700, onTap: () => navigate(const PreVenteScreen())),
      MenuItem(label: 'Pre/Vente Assurance', icon: Icons.health_and_safety, color: Colors.red.shade700, onTap: () => navigate(const AssuranceSaleScreen())),
      MenuItem(label: 'Vente Carnet', icon: Icons.book, color: Colors.green.shade800, onTap: () => navigate(const CarnetSaleScreen())),
      MenuItem(label: 'Gestion Caisse', icon: Icons.calculate, color: Colors.lime.shade700, onTap: () => navigate(const CaisseScreen())),
      MenuItem(label: 'Gestion Périmés', icon: Icons.dangerous, color: Colors.deepOrange.shade600, onTap: () => navigate(const PerimeMainScreen())),
      MenuItem(label: 'Évaluation Vente', icon: Icons.bar_chart, color: Colors.green.shade700, onTap: () => navigate(const ProductEvaluationScreen())),
      MenuItem(label: 'Recherche Article', icon: Icons.search, color: Colors.orange.shade700, onTap: () => navigate(const ProductSearchScreen())),
      MenuItem(label: 'Mise à jour Péremption', icon: Icons.date_range, color: Colors.purple.shade700, onTap: () => navigate(const ExpirationUpdateScreen())),
      MenuItem(label: 'Contrôle Livraison', icon: Icons.inventory_2, color: Colors.teal.shade700, onTap: () => navigate(const DeliveryListScreen())),
      MenuItem(label: 'Pointage BL Stock', icon: Icons.checklist, color: Colors.cyan.shade700, onTap: () => navigate(const BlListScreen())),
      MenuItem(label: 'Mise à jour EAN', icon: Icons.qr_code_scanner, color: Colors.indigo.shade400, onTap: () => navigate(const EanUpdateScreen())),
      MenuItem(label: 'Mise à jour Emplacement', icon: Icons.location_on, color: Colors.brown.shade400, onTap: () => navigate(const EmplacementUpdateScreen())),
      MenuItem(label: 'État de Stock', icon: Icons.inventory, color: Colors.blueGrey.shade600, onTap: () => navigate(const StockReportScreen())),
    ];
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

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final size = MediaQuery.of(context).size;
    final bool isTablet = size.width > 600;

    // --- CONFIGURATION GRILLE ---
    // Tablette : 4 colonnes x 3 lignes = 12 items (Standard pour 10")
    // Mobile : 2 colonnes x 3 lignes = 6 items
    final int cols = isTablet ? 4 : 2;
    final int rows = 3;
    final int itemsPerPage = cols * rows;

    // Découpage en pages
    List<List<MenuItem>> pages = [];
    for (var i = 0; i < _allMenuItems.length; i += itemsPerPage) {
      pages.add(_allMenuItems.sublist(
          i, i + itemsPerPage > _allMenuItems.length ? _allMenuItems.length : i + itemsPerPage));
    }

    return Scaffold(
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
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // HEADER (FIXE)
              _buildWelcomeCard(),
              const SizedBox(height: 16),

              // ZONE DES MENUS (FLEXIBLE)
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: pages.length,
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  itemBuilder: (context, pageIndex) {
                    final pageItems = pages[pageIndex];

                    // Construction de la grille "Flexible" (Column > Rows > Expanded)
                    // Cela garantit qu'il n'y a JAMAIS de scroll
                    return Column(
                      children: List.generate(rows, (rowIndex) {
                        return Expanded( // Chaque ligne prend 1/3 de la hauteur dispo
                          child: Row(
                            children: List.generate(cols, (colIndex) {
                              final itemIndex = rowIndex * cols + colIndex;

                              if (itemIndex < pageItems.length) {
                                return Expanded( // Chaque item prend 1/4 de la largeur
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: _buildMenuCard(pageItems[itemIndex], isTablet),
                                  ),
                                );
                              } else {
                                return const Expanded(child: SizedBox()); // Espace vide
                              }
                            }),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),

              // INDICATEUR DE PAGE (FIXE)
              if (pages.length > 1)
                _buildPageIndicator(pages.length),
            ],
          ),
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
    // Tailles dynamiques
    final double iconSize = isTablet ? 42 : 48;
    final double fontSize = isTablet ? 13 : 15;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: item.color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(item.icon, size: iconSize, color: item.color),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
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
    );
  }

  Widget _buildPageIndicator(int pageCount) {
    return Container(
      height: 30, // Hauteur fixe pour éviter le saut
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