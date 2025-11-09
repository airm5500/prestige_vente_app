// lib/screens/home/home_screen.dart
// 09/11/2025 19:00 (Ajout Vente Carnet)
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/screens/auth/settings_screen.dart';
import 'package:prestige_vente_app/screens/bl_control/bl_list_screen.dart';
import 'package:prestige_vente_app/screens/delivery_control/delivery_list_screen.dart';
import 'package:prestige_vente_app/screens/expiration_update/expiration_update_screen.dart';
import 'package:prestige_vente_app/screens/pre_vente/pre_vente_screen.dart';
import 'package:prestige_vente_app/screens/product_evaluation/product_evaluation_screen.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_screen.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/utils/responsive.dart';
import 'package:prestige_vente_app/widgets/menu_button.dart';
import 'package:prestige_vente_app/screens/product_update/ean_update_screen.dart';
import 'package:prestige_vente_app/screens/product_update/emplacement_update_screen.dart';
import 'package:prestige_vente_app/screens/assurance_sale/assurance_sale_screen.dart';
import 'package:prestige_vente_app/screens/caisse/caisse_screen.dart';
import 'package:prestige_vente_app/screens/perimes/perime_main_screen.dart';

// AJOUT : Import pour le nouvel écran
import 'package:prestige_vente_app/screens/carnet_sale/carnet_sale_screen.dart';


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
  List<MenuItem> _menuItems = [];
  List<List<MenuItem>> _pages = [];

  late SaleProvider _saleProvider;
  late BlControlProvider _blProvider;

  @override
  void initState() {
    super.initState();
    _saleProvider = Provider.of<SaleProvider>(context, listen: false);
    _blProvider = Provider.of<BlControlProvider>(context, listen: false);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void navigate(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
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
    Navigator.of(context).pop(); // Ferme le dialogue de chargement

    showDialog(
      context: context,
      builder: (ctx) {
        final preventesCount = _saleProvider.preventes.length;
        final blCount = _blProvider.bonsLivraison
            .where((b) => b.statutTraitement != "TERMINE")
            .length;

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
                onTap: () {
                  Navigator.of(ctx).pop();
                  navigate(const PreVenteScreen(initialTabIndex: 2));
                },
              ),
              ListTile(
                leading: Icon(Icons.checklist, color: Colors.cyan.shade700),
                title: Text('$blCount BL(s) à pointer'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  navigate(const BlListScreen(initialFilter: 'A_TRAITER'));
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Fermer'),
            )
          ],
        );
      },
    );
  }

  void _buildMenuItems(BuildContext context) {
    _menuItems = [
      MenuItem( label: 'Pre/Vente', icon: Icons.point_of_sale, color: Colors.blue.shade700, onTap: () => navigate(const PreVenteScreen())),
      MenuItem(
        label: 'Pre/Vente Assurance',
        icon: Icons.health_and_safety,
        color: Colors.red.shade700,
        onTap: () => navigate(const AssuranceSaleScreen()),
      ),

      // AJOUT : Le nouveau menu pour le Carnet
      MenuItem(
        label: 'Vente Carnet',
        icon: Icons.book, // Icône pour le carnet
        color: Colors.green.shade800, // Une nouvelle couleur
        onTap: () => navigate(const CarnetSaleScreen()), // Vers le nouvel écran
      ),

      MenuItem(
        label: 'Gestion Caisse',
        icon: Icons.calculate,
        color: Colors.lime.shade700,
        onTap: () => navigate(const CaisseScreen()),
      ),
      MenuItem(
        label: 'Gestion Périmés',
        icon: Icons.dangerous,
        color: Colors.deepOrange.shade600,
        onTap: () => navigate(const PerimeMainScreen()),
      ),
      MenuItem( label: 'Évaluation Vente', icon: Icons.bar_chart, color: Colors.green.shade700, onTap: () => navigate(const ProductEvaluationScreen())),
      MenuItem( label: 'Recherche Article', icon: Icons.search, color: Colors.orange.shade700, onTap: () => navigate(const ProductSearchScreen())),
      MenuItem( label: 'Mise à jour Péremption', icon: Icons.date_range, color: Colors.purple.shade700, onTap: () => navigate(const ExpirationUpdateScreen())),
      MenuItem( label: 'Contrôle Livraison', icon: Icons.inventory_2, color: Colors.teal.shade700, onTap: () => navigate(const DeliveryListScreen())),
      MenuItem( label: 'Pointage BL Stock', icon: Icons.checklist, color: Colors.cyan.shade700, onTap: () => navigate(const BlListScreen())),
      MenuItem(
        label: 'Mise à jour EAN',
        icon: Icons.qr_code_scanner,
        color: Colors.indigo.shade400,
        onTap: () => navigate(const EanUpdateScreen()),
      ),
      MenuItem(
        label: 'Mise à jour Emplacement',
        icon: Icons.location_on,
        color: Colors.brown.shade400,
        onTap: () => navigate(const EmplacementUpdateScreen()),
      ),
    ];

    _pages = [];
    // Gère la pagination (6 par page)
    for (var i = 0; i < _menuItems.length; i += 6) {
      _pages.add(_menuItems.sublist(i, i + 6 > _menuItems.length ? _menuItems.length : i + 6));
    }
  }

  @override
  Widget build(BuildContext context) {
    _buildMenuItems(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prestige Mobile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showInfoPopup,
            tooltip: 'Tâches en attente',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => navigate(const SettingsScreen()),
            tooltip: 'Configuration',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              authProvider.logout();
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
            },
            tooltip: 'Déconnexion',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeCard(),
              const SizedBox(height: 24),

              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                  },
                  itemBuilder: (context, pageIndex) {
                    final pageItems = _pages[pageIndex];
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: Responsive.isMobile(context) ? 2 : 3,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1.2,
                      ),
                      itemCount: pageItems.length,
                      itemBuilder: (context, itemIndex) {
                        final item = pageItems[itemIndex];
                        return MenuButton(
                          label: item.label,
                          icon: item.icon,
                          color: item.color,
                          onTap: item.onTap,
                        );
                      },
                    );
                  },
                ),
              ),

              if (_pages.length > 1)
                _buildPageIndicator(),
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

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_pages.length, (index) {
        return Container(
          width: 8.0,
          height: 8.0,
          margin: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 4.0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _currentPage == index
                ? AppColors.primary
                : AppColors.primary.withAlpha(77),
          ),
        );
      }),
    );
  }
}