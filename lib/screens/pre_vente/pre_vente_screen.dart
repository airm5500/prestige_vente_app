// lib/screens/pre_vente/pre_vente_screen.dart
// 28/09/2025 01:46
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/screens/pre_vente/tabs/prevente_list_tab.dart';
import 'package:prestige_vente_app/screens/pre_vente/tabs/vente_tab.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';

class PreVenteScreen extends StatefulWidget {
  const PreVenteScreen({super.key});

  @override
  State<PreVenteScreen> createState() => _PreVenteScreenState();
}

class _PreVenteScreenState extends State<PreVenteScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Initialise une nouvelle vente à l'ouverture de l'écran
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SaleProvider>(context, listen: false).startNewSale();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pre/Vente'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'PREVENTE'),
            Tab(text: 'VENTE'),
            Tab(text: 'LISTE PREVENTES'),
          ],
        ),
        actions: [
          // Bouton pour démarrer une nouvelle vente
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Provider.of<SaleProvider>(context, listen: false).startNewSale();
              _tabController.animateTo(0); // Revient au premier onglet
            },
            tooltip: 'Nouvelle Vente',
          )
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Onglet 1: Prevente (isPrevente = true)
          const VenteTab(isPrevente: true),
          // Onglet 2: Vente (isPrevente = false)
          const VenteTab(isPrevente: false),
          // Onglet 3: Liste des préventes
          PreventeListTab(tabController: _tabController),
        ],
      ),
    );
  }
}