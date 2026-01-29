// lib/main.dart
// 10/11/2025 09:30 (Ajout LicenceProvider)
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

import 'package:prestige_vente_app/providers/expiration_update_provider.dart';
import 'package:prestige_vente_app/providers/delivery_control_provider.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/product_update_provider.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:prestige_vente_app/providers/caisse_provider.dart';
import 'package:prestige_vente_app/providers/perime_provider.dart';
import 'package:prestige_vente_app/providers/carnet_sale_provider.dart';
import 'package:prestige_vente_app/providers/stock_report_provider.dart';
import 'package:prestige_vente_app/providers/reception_provider.dart';

// AJOUT : Import du provider de licence
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/depot_sale_provider.dart';
import 'package:prestige_vente_app/providers/proforma_provider.dart';

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

        // AJOUT : LicenceProvider (Placé haut pour être accessible partout)
        ChangeNotifierProxyProvider<ApiService, LicenceProvider>(
          create: (context) => LicenceProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, previousProvider) =>
          previousProvider!..updateApiService(apiService), // Note: updateApiService est optionnel si on recrée pas, mais bonne pratique ici
        ),

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

        ChangeNotifierProxyProvider<ApiService, ExpirationUpdateProvider>(
          create: (context) => ExpirationUpdateProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, previousProvider) => previousProvider!..updateApiService(apiService),
        ),

        ChangeNotifierProxyProvider<ApiService, DeliveryControlProvider>(
          create: (context) => DeliveryControlProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, previousProvider) => previousProvider!..updateApiService(apiService),
        ),

        ChangeNotifierProxyProvider<ApiService, BlControlProvider>(
          create: (context) => BlControlProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, previousProvider) => previousProvider!..updateApiService(apiService),
        ),

        ChangeNotifierProxyProvider<ApiService, ProductUpdateProvider>(
          create: (context) => ProductUpdateProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, previousProvider) => previousProvider!..updateApiService(apiService),
        ),

        ChangeNotifierProxyProvider2<ApiService, AuthProvider, AssuranceSaleProvider>(
          create: (context) => AssuranceSaleProvider(
            Provider.of<ApiService>(context, listen: false),
            Provider.of<AuthProvider>(context, listen: false).user?.userId ?? "",
          ),
          update: (context, apiService, auth, previousProvider) =>
              AssuranceSaleProvider(
                apiService,
                auth.user?.userId ?? "",
              ),
        ),

        ChangeNotifierProxyProvider2<ApiService, AuthProvider, CarnetSaleProvider>(
          create: (context) => CarnetSaleProvider(
            Provider.of<ApiService>(context, listen: false),
            Provider.of<AuthProvider>(context, listen: false).user?.userId ?? "",
          ),
          update: (context, apiService, auth, previousProvider) =>
              CarnetSaleProvider(
                apiService,
                auth.user?.userId ?? "",
              ),
        ),

        ChangeNotifierProxyProvider<ApiService, CaisseProvider>(
          create: (context) => CaisseProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, previousProvider) => previousProvider!..updateApiService(apiService),
        ),

        ChangeNotifierProxyProvider<ApiService, PerimeProvider>(
          create: (context) => PerimeProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, previousProvider) => previousProvider!..updateApiService(apiService),
        ),

        ChangeNotifierProxyProvider<ApiService, ReceptionProvider>(
          create: (context) => ReceptionProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, previousProvider) => previousProvider!..updateApiService(apiService),
        ),

        ChangeNotifierProxyProvider<ApiService, StockReportProvider>(
          create: (context) => StockReportProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, previousProvider) => previousProvider!..updateApiService(apiService),
        ),

        ChangeNotifierProxyProvider<ApiService, DepotSaleProvider>(
          create: (context) => DepotSaleProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, previous) => DepotSaleProvider(apiService),
        ),
        ChangeNotifierProvider(create: (context) => ProformaProvider(Provider.of<ApiService>(context, listen: false))),
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