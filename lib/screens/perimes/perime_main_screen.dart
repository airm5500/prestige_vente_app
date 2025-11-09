// lib/screens/perimes/perime_main_screen.dart
// 09/11/2025 17:30
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/screens/perimes/tabs/recherche_perimes_tab.dart';
import 'package:prestige_vente_app/screens/perimes/tabs/saisie_perimes_screen.dart';

class PerimeMainScreen extends StatefulWidget {
  const PerimeMainScreen({super.key});

  @override
  State<PerimeMainScreen> createState() => _PerimeMainScreenState();
}

class _PerimeMainScreenState extends State<PerimeMainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        title: const Text('Gestion des Périmés'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.search), text: 'Recherche Périmés'),
            Tab(icon: Icon(Icons.edit_document), text: 'Saisie / Historique'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          RecherchePerimesTab(),
          SaisiePerimesScreen(), // Cet écran contient les 2 sous-onglets
        ],
      ),
    );
  }
}