// lib/screens/perimes/tabs/saisie_perimes_screen.dart
// 09/11/2025 17:30
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/screens/perimes/tabs/historique_saisies_tab.dart';
import 'package:prestige_vente_app/screens/perimes/tabs/saisie_en_cours_tab.dart';

import '../../../utils/constants.dart';

class SaisiePerimesScreen extends StatefulWidget {
  const SaisiePerimesScreen({super.key});

  @override
  State<SaisiePerimesScreen> createState() => _SaisiePerimesScreenState();
}

class _SaisiePerimesScreenState extends State<SaisiePerimesScreen> with SingleTickerProviderStateMixin {
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
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Saisie en Cours'),
            Tab(text: 'Historique des Saisies'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              SaisieEnCoursTab(),
              HistoriqueSaisiesTab(),
            ],
          ),
        ),
      ],
    );
  }
}