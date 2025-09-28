// lib/main.dart
// 28/09/2025 13:55
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:provider/provider.dart';
// Import nécessaire pour l'initialisation des locales
import 'package:intl/date_symbol_data_local.dart';

import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/product_search_provider.dart';
import 'package:prestige_vente_app/providers/product_stats_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/splash_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';

// La fonction main doit être asynchrone pour attendre l'initialisation
Future<void> main() async {
  // Ces deux lignes sont cruciales pour que l'application
  // et le formatage des dates fonctionnent correctement.
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ProxyProvider<SettingsProvider, ApiService>(
          update: (context, settings, previous) => ApiService(baseUrl: settings.baseUrl),
        ),
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