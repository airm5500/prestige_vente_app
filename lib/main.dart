// lib/main.dart
// 28/09/2025 02:36
import 'package:flutter/material.dart';
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
        ChangeNotifierProvider(create: (_) => SettingsProvider()),

        ChangeNotifierProxyProvider<SettingsProvider, AuthProvider>(
          create: (context) => AuthProvider(
            Provider.of<SettingsProvider>(context, listen: false),
          ),
          update: (context, settingsProvider, authProvider) =>
              AuthProvider(settingsProvider),
        ),

        ChangeNotifierProxyProvider<SettingsProvider, SaleProvider>(
          create: (context) => SaleProvider(
            Provider.of<SettingsProvider>(context, listen: false),
          ),
          update: (context, settingsProvider, saleProvider) =>
              SaleProvider(settingsProvider),
        ),

        ChangeNotifierProxyProvider<SettingsProvider, ProductStatsProvider>(
          create: (context) => ProductStatsProvider(
            Provider.of<SettingsProvider>(context, listen: false),
          ),
          update: (context, settingsProvider, productStatsProvider) =>
              ProductStatsProvider(settingsProvider),
        ),

        ChangeNotifierProxyProvider<SettingsProvider, ProductSearchProvider>(
          create: (context) => ProductSearchProvider(
            Provider.of<SettingsProvider>(context, listen: false),
          ),
          update: (context, settingsProvider, productSearchProvider) =>
              ProductSearchProvider(settingsProvider),
        ),
      ],
      child: MaterialApp(
        title: 'Prestige Vente',
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: const SplashScreen(),
      ),
    );
  }
}