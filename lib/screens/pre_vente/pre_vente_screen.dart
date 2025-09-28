// lib/screens/pre_vente/pre_vente_screen.dart
// 28/09/2025 19:11
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/screens/pre_vente/tabs/prevente_list_tab.dart';
import 'package:prestige_vente_app/screens/pre_vente/tabs/vente_tab.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';

class PreVenteScreen extends StatefulWidget {
  const PreVenteScreen({super.key});

  @override
  State<PreVenteScreen> createState() => _PreVenteScreenState();
}

class _PreVenteScreenState extends State<PreVenteScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Color _activeTabColor = Colors.orange;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabSelection);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final saleProvider = Provider.of<SaleProvider>(context, listen: false);
      saleProvider.startNewSale();
      // On déclenche le chargement de la liste des préventes une seule fois
      saleProvider.fetchPreventes();
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) { return; }
    // Si on va sur l'onglet "Liste Preventes", on rafraîchit les données
    if (_tabController.index == 2) {
      Provider.of<SaleProvider>(context, listen: false).fetchPreventes();
    }
    setState(() {
      switch (_tabController.index) {
        case 0: _activeTabColor = Colors.orange; break;
        case 1: _activeTabColor = AppColors.success; break;
        case 2: _activeTabColor = AppColors.secondary; break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pre/Vente'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Provider.of<SaleProvider>(context, listen: false).startNewSale();
              _tabController.animateTo(0);
            },
            tooltip: 'Nouvelle Vente',
          )
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Container(
              height: 48,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: _activeTabColor,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white.withOpacity(0.8),
                tabs: [
                  // MODIFICATION : Utilisation d'un Row pour afficher icône et texte côte à côte
                  _buildTab(Icons.history_toggle_off, 'PREVENTE'),
                  _buildTab(Icons.point_of_sale, 'VENTE'),
                  _buildTab(Icons.list_alt, 'LISTE'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const VenteTab(isPrevente: true),
          const VenteTab(isPrevente: false),
          PreventeListTab(tabController: _tabController),
        ],
      ),
    );
  }

  // MODIFICATION : Widget pour créer un onglet horizontal
  Widget _buildTab(IconData icon, String text) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }
}