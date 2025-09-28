// lib/main.dart
// 28/09/2025 03:28
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/product_search_provider.dart';
import 'package:prestige_vente_app/providers/product_stats_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/splash_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 1. Le provider des paramètres (inchangé)
        ChangeNotifierProvider(create: (_) => SettingsProvider()),

        // 2. On crée UNE SEULE instance de ApiService pour toute l'app.
        // Elle dépend des paramètres, donc on utilise un ProxyProvider.
        ProxyProvider<SettingsProvider, ApiService>(
          update: (context, settings, previous) => ApiService(baseUrl: settings.baseUrl),
        ),

        // 3. Tous les autres providers reçoivent l'instance unique de ApiService.
        ChangeNotifierProxyProvider<ApiService, AuthProvider>(
          create: (context) => AuthProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, authProvider) => AuthProvider(apiService),
        ),

        ChangeNotifierProxyProvider<ApiService, SaleProvider>(
          create: (context) => SaleProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, saleProvider) => SaleProvider(apiService),
        ),

        ChangeNotifierProxyProvider<ApiService, ProductStatsProvider>(
          create: (context) => ProductStatsProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, productStatsProvider) => ProductStatsProvider(apiService),
        ),

        ChangeNotifierProxyProvider<ApiService, ProductSearchProvider>(
          create: (context) => ProductSearchProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, productSearchProvider) => ProductSearchProvider(apiService),
        ),
      ],
      child: MaterialApp(
        title: 'Prestige Vente',
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: SplashScreen(),
      ),
    );
  }
}