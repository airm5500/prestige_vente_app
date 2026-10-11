// lib/main.dart
// 10/11/2025 09:30 (Ajout LicenceProvider)
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/ventes/ventes_version.dart';
import 'package:prestige_vente_app/interface_version.dart';
import 'package:prestige_vente_app/providers/article_analysis_provider.dart';
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
import 'package:prestige_vente_app/providers/ajustement_provider.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/images/images_reglages.dart';
import 'package:prestige_vente_app/images/produit_images.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';
import 'package:prestige_vente_app/horsligne/connexion_toasts.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/horsligne_ui.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/services/fingerprint_service.dart';
import 'package:prestige_vente_app/support/support_capture.dart';
import 'package:prestige_vente_app/support/support_centre.dart';
import 'package:prestige_vente_app/support/support_file.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);
  await VentesVersion.load();
  await InterfaceVersion.load();
  await SearchModePrefs.load();
  // Borne libre-service (désactivée par défaut) : réglages de cet appareil.
  await BorneReglages.charger();
  // Images des produits (B2) : réglages et cache disque (affichage hors ligne).
  await ImagesReglages.charger();
  ProduitImages.instance.dossier = () async => Directory('${(await getApplicationSupportDirectory()).path}/images_produits');
  unawaited(ProduitImages.instance.init());
  // Journal du terminal (SQLite, fichier du catalogue) : durée de conservation et identité du terminal.
  JournalTerminal.instance = JournalTerminal.app(HorsLigne.instance.store);
  await JournalTerminal.chargerReglages();
  await JournalTerminal.instance.chargerIdentite(materiel: FingerprintService.hardwareInfo);
  // Centre de support : file locale des anomalies, réglage d'envoi automatique, capture des erreurs Flutter.
  SupportCentre.instance = SupportCentre(file: PrefsSupportFileStore());
  await SupportCentre.instance.chargerReglage();
  installerCaptureErreurs();
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
        ChangeNotifierProxyProvider<ApiService, AjustementProvider>(
          create: (context) => AjustementProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, previous) => AjustementProvider(apiService),
        ),

        ChangeNotifierProxyProvider<ApiService, DepotSaleProvider>(
          create: (context) => DepotSaleProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, apiService, previous) => DepotSaleProvider(apiService),
        ),
        ChangeNotifierProvider(create: (context) => ProformaProvider(Provider.of<ApiService>(context, listen: false))),
        // dans main.dart, liste des providers :
        ChangeNotifierProvider(create: (ctx) => ArticleAnalysisProvider(ctx.read<ApiService>())),
      ],
      child: MaterialApp(
        title: 'Prestige Vente',
        // Navigateur global : le bandeau hors ligne ouvre « Ventes hors ligne ».
        navigatorKey: HorsLigne.navigatorKey,
        // Centre de support : écran courant et fil d'Ariane des écrans.
        navigatorObservers: [SupportNavigatorObserver()],
        theme: AppTheme.lightTheme,
        // Tablette : fenêtres de dialogue à largeur raisonnable (téléphone inchangé).
        debugShowCheckedModeBanner: false,
        // Thème des dialogues adapté aux tablettes + bandeau hors ligne (rien tant que le serveur répond)
        // + messages « Connexion au serveur perdue » / « De nouveau en ligne » (le retour n'est pas répété dans le bandeau).
        builder: (context, child) => HorsLigneScope(
            bandeauRetour: false, child: ConnexionToasts(child: ResponsiveTheme(child: child ?? const SizedBox.shrink()))),
        home: const SplashScreen(),
      ),
    );
  }
}