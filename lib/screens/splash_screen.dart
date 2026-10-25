// lib/screens/splash_screen.dart
// 30/12/2025 04:00 (Fix: Bug démarrage + Gestion erreur réseau)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:prestige_vente_app/parametres/nom_appareil_reglage.dart';
import 'package:prestige_vente_app/borne/borne_launcher.dart';
import 'package:prestige_vente_app/connexion/lancement_screen.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/interface_version.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/api/api_service.dart'; // IMPORTANT

import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/screens/auth/licence_registration_screen.dart';

/// Écran de lancement : nouvel écran (LancementScreen, proposition A) dans la nouvelle interface ;
/// écran d'origine ([AncienSplashScreen], inchangé) quand l'interrupteur InterfaceVersion est désactivé.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => InterfaceVersion.useNew.value ? const LancementScreen() : const AncienSplashScreen();
}

/// Écran de lancement d'origine (logique et présentation inchangées, attente visuelle de 2 s comprise).
class AncienSplashScreen extends StatefulWidget {
  const AncienSplashScreen({super.key});

  @override
  State<AncienSplashScreen> createState() => _AncienSplashScreenState();
}

class _AncienSplashScreenState extends State<AncienSplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkConfiguration();
  }

  Future<void> _checkConfiguration() async {
    // 1. Délai visuel initial
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);

    // 2. CHARGEMENT CRITIQUE DES PARAMÈTRES
    await settingsProvider.loadSettings();

    // ASTUCE ANTI-BUG : On laisse le temps au framework de propager l'IP au ApiService
    await Future.delayed(Duration.zero);

    // 3. Vérification si configuré
    if (settingsProvider.isConfigured) {
      // 4.7.1 : nom de cet appareil obligatoire (jamais sur une borne).
      if (!BorneLauncher.auDemarrage && mounted) {
        await exigerNomAppareil(context);
        if (!mounted) return;
      }

      // ANO-08 : l'ApiService fourni a été créé à la 1re image (réglages pas encore lus → http://localhost:8080) et
      // n'est recréé par le ProxyProvider qu'à l'image suivante ; « Future.delayed(Duration.zero) » n'en laisse
      // passer aucune. Si l'adresse n'est pas celle des réglages, on attend la fin de l'image suivante (ApiService recréé).
      if (mounted && Provider.of<ApiService>(context, listen: false).dio.options.baseUrl != settingsProvider.baseUrl) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }

      // ON FORCE LA MISE A JOUR DU PROVIDER LICENCE AVEC LE BON API SERVICE
      // C'est ici que se jouait le bug : on s'assure qu'il utilise la bonne IP
      final apiService = Provider.of<ApiService>(context, listen: false);
      final licenceProvider = Provider.of<LicenceProvider>(context, listen: false);
      licenceProvider.updateApiService(apiService);

      // 4. Vérification Licence
      LicenceStatus status = await licenceProvider.checkLicence();

      if (!mounted) return;

      // Borne libre-service (B1) active sur cet appareil : ouverture directe de la borne
      // (connexion de l'utilisateur borne ; serveur injoignable = « borne momentanément indisponible »).
      if (BorneLauncher.auDemarrage && (status == LicenceStatus.valid || status == LicenceStatus.error)) {
        Provider.of<AuthProvider>(context, listen: false).updateApiService(apiService);
        BorneLauncher.ouvrir(context);
        return;
      }

      if (status == LicenceStatus.valid) {
        // --- CAS 1 : LICENCE VALIDE ---
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        // On met aussi à jour l'auth provider par sécurité
        authProvider.updateApiService(apiService);

        bool isAuth = await authProvider.tryAutoLogin();
        if (!mounted) return;

        Widget nextScreen = isAuth ? InterfaceVersion.home() : const LoginScreen();
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => nextScreen),
                (route) => false
        );

      } else if (status == LicenceStatus.error) {
        // --- CAS 2 : ERREUR RÉSEAU (Le serveur ne répond pas) ---
        // On n'envoie PAS vers l'enregistrement, on affiche une erreur
        _showConnectionErrorDialog();

      } else {
        // --- CAS 3 : PAS DE LICENCE (Ou expirée) ---
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LicenceRegistrationScreen()),
              (route) => false,
        );
      }

    } else {
      // Pas configuré du tout
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => InterfaceVersion.settings()),
            (route) => false,
      );
    }
  }

  void _showConnectionErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(Provider.of<LicenceProvider>(context, listen: false).errorTitle),
        content: SingleChildScrollView(
          child: Text(
            "${Provider.of<LicenceProvider>(context, listen: false).errorMessage}\n\n"
            "(Problème de connexion : la licence n'a pas pu être vérifiée, elle n'est pas en cause.)\n\n"
            "Adresse utilisée : ${LicenceProvider.serverHost(Provider.of<SettingsProvider>(context, listen: false).baseUrl)}",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => InterfaceVersion.settings()),
              ).then((_) => _checkConfiguration());
            },
            child: const Text("Configuration"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _checkConfiguration(); // Réessayer
            },
            child: const Text("Réessayer"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
              child: Icon(Icons.storefront, size: 60, color: Colors.blue.shade800),
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text("Démarrage...", style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}