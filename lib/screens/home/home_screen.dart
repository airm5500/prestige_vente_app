// lib/screens/home/home_screen.dart
// 18/10/2025 22:10
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

  // On garde une référence aux providers
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

  // Navigation simple
  void navigate(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  // MODIFICATION : Logique de rafraîchissement au clic sur le bouton info
  Future<void> _showInfoPopup() async {
    // 1. Affiche un petit dialogue de chargement
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

    // 2. Rafraîchit les données en arrière-plan
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await Future.wait([
      _saleProvider.fetchPreventes(),
      _blProvider.fetchBonsLivraison(dtStart: today, dtEnd: today)
    ]);

    if (!mounted) return;
    Navigator.of(context).pop(); // Ferme le dialogue de chargement

    // 3. Affiche le dialogue avec les données à jour
    showDialog(
      context: context,
      builder: (ctx) {
        final preventesCount = _saleProvider.preventes.length;
        final blCount = _blProvider.bonsLivraison.length; // On compte tous les BL "is_Closed" du jour

        return AlertDialog(
          title: const Text('Tâches en attente'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (preventesCount > 0)
                Text(
                  '$preventesCount Prévente(s) en attente',
                  style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.bold, fontSize: 16),
                )
              else
                const Text("Aucune prévente en attente.", style: TextStyle(fontSize: 16)),

              const SizedBox(height: 16),

              if (blCount > 0)
                Text(
                  '$blCount BL(s) à pointer',
                  style: TextStyle(color: Colors.cyan.shade700, fontWeight: FontWeight.bold, fontSize: 16),
                )
              else
                const Text("Aucun BL à pointer.", style: TextStyle(fontSize: 16)),
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
      MenuItem( label: 'Évaluation Vente', icon: Icons.bar_chart, color: Colors.green.shade700, onTap: () => navigate(const ProductEvaluationScreen())),
      MenuItem( label: 'Recherche Article', icon: Icons.search, color: Colors.orange.shade700, onTap: () => navigate(const ProductSearchScreen())),
      MenuItem( label: 'Mise à jour Péremption', icon: Icons.date_range, color: Colors.purple.shade700, onTap: () => navigate(const ExpirationUpdateScreen())),
      MenuItem( label: 'Contrôle Livraison', icon: Icons.inventory_2, color: Colors.teal.shade700, onTap: () => navigate(const DeliveryListScreen())),
      MenuItem( label: 'Pointage BL Stock', icon: Icons.checklist, color: Colors.cyan.shade700, onTap: () => navigate(const BlListScreen())),
    ];
    _pages = [];
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
          // MODIFICATION : Bouton d'info réintégré
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