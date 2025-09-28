// lib/main.dart
// 28/09/2025 21:05
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/product_search_provider.dart';
import 'package:prestige_vente_app/providers/product_stats_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/splash_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';

Future<void> main() async {
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

        // MODIFICATION : La logique 'update' est corrigée pour tous les providers.
        // On met à jour l'instance existante au lieu d'en créer une nouvelle.
        ChangeNotifierProxyProvider<ApiService, AuthProvider>(
          create: (context) => AuthProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, previousProvider) => previousProvider!..updateApiService(apiService),
        ),

        ChangeNotifierProxyProvider<ApiService, SaleProvider>(
          create: (context) => SaleProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, previousProvider) => previousProvider!..updateApiService(apiService),
        ),

        ChangeNotifierProxyProvider<ApiService, ProductStatsProvider>(
          create: (context) => ProductStatsProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, previousProvider) => previousProvider!..updateApiService(apiService),
        ),

        ChangeNotifierProxyProvider<ApiService, ProductSearchProvider>(
          create: (context) => ProductSearchProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, previousProvider) => previousProvider!..updateApiService(apiService),
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