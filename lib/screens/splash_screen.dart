// lib/screens/splash_screen.dart
// 30/12/2025 04:00 (Fix: Bug démarrage + Gestion erreur réseau)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/interface_version.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/api/api_service.dart'; // IMPORTANT

import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/screens/auth/licence_registration_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
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

      // ON FORCE LA MISE A JOUR DU PROVIDER LICENCE AVEC LE BON API SERVICE
      // C'est ici que se jouait le bug : on s'assure qu'il utilise la bonne IP
      final apiService = Provider.of<ApiService>(context, listen: false);
      final licenceProvider = Provider.of<LicenceProvider>(context, listen: false);
      licenceProvider.updateApiService(apiService);

      // 4. Vérification Licence
      LicenceStatus status = await licenceProvider.checkLicence();

      if (!mounted) return;

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