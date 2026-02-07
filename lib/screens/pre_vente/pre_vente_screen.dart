// lib/screens/pre_vente/pre_vente_screen.dart
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/screens/pre_vente/tabs/prevente_list_tab.dart';
import 'package:prestige_vente_app/screens/pre_vente/tabs/vente_tab.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';

class PreVenteScreen extends StatefulWidget {
  final int initialTabIndex;
  const PreVenteScreen({super.key, this.initialTabIndex = 0});

  @override
  State<PreVenteScreen> createState() => _PreVenteScreenState();
}

class _PreVenteScreenState extends State<PreVenteScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Color _activeTabColor = Colors.orange;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTabIndex);
    _updateTabColor(_tabController.index);
    _tabController.addListener(_handleTabSelection);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final saleProvider = Provider.of<SaleProvider>(context, listen: false);
      if (saleProvider.currentVenteId == null) {
        saleProvider.startNewSale();
      }
      if (widget.initialTabIndex == 2) saleProvider.fetchPreventes();
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 2) {
      Provider.of<SaleProvider>(context, listen: false).fetchPreventes();
    }
    // Nettoyage recherche si changement d'onglet
    Provider.of<SaleProvider>(context, listen: false).clearSearchResults();
    _updateTabColor(_tabController.index);
    setState(() {});
  }

  void _updateTabColor(int index) {
    setState(() {
      switch (index) {
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
          Consumer<SaleProvider>(
            builder: (context, sale, child) {
              return IconButton(
                icon: Icon(sale.isQuickScanMode ? Icons.bolt : Icons.settings,
                    color: sale.isQuickScanMode ? Colors.greenAccent : null),
                onPressed: () => sale.toggleQuickScanMode(),
                tooltip: 'Mode Scan Rapide',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Provider.of<SaleProvider>(context, listen: false).startNewSale();
              _tabController.animateTo(0);
            },
          )
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Container(
              height: 48, padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: AppColors.primary.withAlpha(128), borderRadius: BorderRadius.circular(8)),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(borderRadius: BorderRadius.circular(8), color: _activeTabColor),
                tabs: [
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
          VenteTab(key: const ValueKey('prevente'), isPrevente: true),
          VenteTab(key: const ValueKey('vente'), isPrevente: false),
          // CORRECTION : On repasse le contrôleur ici
          PreventeListTab(tabController: _tabController),
        ],
      ),
    );
  }

  Widget _buildTab(IconData icon, String text) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}