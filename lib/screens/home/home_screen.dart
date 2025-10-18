// lib/screens/home/home_screen.dart
// 29/09/2025 23:55
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/screens/auth/settings_screen.dart';
import 'package:prestige_vente_app/screens/pre_vente/pre_vente_screen.dart';
import 'package:prestige_vente_app/screens/product_evaluation/product_evaluation_screen.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_screen.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/utils/responsive.dart';
import 'package:prestige_vente_app/widgets/menu_button.dart';
import 'package:prestige_vente_app/screens/expiration_update/expiration_update_screen.dart';
import 'package:prestige_vente_app/screens/delivery_control/delivery_list_screen.dart';
import 'package:prestige_vente_app/screens/bl_control/bl_list_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Consumer<AuthProvider>(
          builder: (context, auth, child) {
            return Text(auth.officine?.nomComplet ?? 'Prestige Vente');
          },
        ),
        // MODIFICATION : Ajout du bouton de configuration
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen())
              );
            },
            tooltip: 'Configuration',
          ),
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
              Consumer<AuthProvider>(
                builder: (context, auth, child) {
                  final officine = auth.officine;
                  return Card(
                    color: AppColors.primary.withAlpha(26),
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
                                  'Bienvenu(e) à ${officine?.nomComplet ?? ''}',
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
                  );
                },
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
                      color: Colors.blue.shade50,
                      onTap: () {
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const PreVenteScreen())
                        );
                      },
                    ),
                    MenuButton(
                      icon: Icons.bar_chart,
                      label: 'Évaluation Vente',
                      color: Colors.green.shade50,
                      onTap: () {
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ProductEvaluationScreen())
                        );
                      },
                    ),
                    MenuButton(
                      icon: Icons.search,
                      label: 'Recherche Article',
                      color: Colors.orange.shade50,
                      onTap: () {
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ProductSearchScreen())
                        );
                      },
                    ),

                    MenuButton(
                      icon: Icons.date_range,
                      label: 'Mise à jour Péremption',
                      color: Colors.purple.shade50,
                      onTap: () {
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ExpirationUpdateScreen())
                        );
                      },
                    ),

                    MenuButton(
                      icon: Icons.inventory_2,
                      label: 'Contrôle Livraison',
                      color: Colors.teal.shade50,
                      onTap: () {
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const DeliveryListScreen())
                        );
                      },
                    ),

                    // AJOUT
                    MenuButton(
                      icon: Icons.checklist,
                      label: 'Pointage BL Stock',
                      color: Colors.cyan.shade50,
                      onTap: () {
                        Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const BlListScreen())
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