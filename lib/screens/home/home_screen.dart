// lib/screens/home/home_screen.dart
// 28/09/2025 02:37
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/screens/pre_vente/pre_vente_screen.dart';
import 'package:prestige_vente_app/screens/product_evaluation/product_evaluation_screen.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_screen.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/utils/responsive.dart';
import 'package:prestige_vente_app/widgets/menu_button.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    final officine = authProvider.officine;

    return Scaffold(
      appBar: AppBar(
        title: Text(officine?.nomComplet ?? 'Prestige Vente'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              authProvider.logout();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
              );
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
              Card(
                color: AppColors.primary.withOpacity(0.1),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.person_pin_circle, size: 40, color: AppColors.primary),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bienvenue, ${user?.firstName ?? ''}',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (officine != null)
                              Text(
                                officine.fullName,
                                style: const TextStyle(fontSize: 16, color: Colors.black54),
                                overflow: TextOverflow.ellipsis,
                              )
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.count(
                  crossAxisCount: Responsive.isMobile(context) ? 2 : 4,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    MenuButton(
                      icon: Icons.point_of_sale,
                      label: 'Pre/Vente',
                      onTap: () {
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const PreVenteScreen())
                        );
                      },
                    ),
                    MenuButton(
                      icon: Icons.bar_chart,
                      label: 'Évaluation Vente',
                      onTap: () {
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ProductEvaluationScreen())
                        );
                      },
                    ),
                    MenuButton(
                      icon: Icons.search,
                      label: 'Recherche Article',
                      onTap: () {
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ProductSearchScreen())
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}