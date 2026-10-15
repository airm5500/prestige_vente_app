// lib/screens/auth/licence_registration_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/interface_version.dart';
import 'package:prestige_vente_app/serveur/client_contexte.dart';
import 'package:prestige_vente_app/serveur/json_tolerant.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/utils/responsive.dart';

/// Licence absente ou expirée constatée à la CONNEXION (nouvelle et ancienne interface). 4.3.0, demande 11
/// (option A du pharmacien : la licence s'active après la connexion d'un administrateur, jamais sans session) :
/// administrateur (compte « admin » de l'application ou profil administrateur du serveur, GET v1/roles/est-admin)
/// → sa session est gardée pour la seule activation ; autre compte → déconnexion, comme avant. Puis l'écran
/// « Clé de licence » (pile vidée).
Future<void> ouvrirActivationLicence(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  final licence = context.read<LicenceProvider>();
  var admin = auth.isAdmin;
  if (!admin) {
    try {
      admin = booleen((await clientPrestige(context).get('/roles/est-admin'))['authorize']);
    } catch (_) {
      admin = false;
    }
  }
  licence.activationParAdministrateur = admin;
  if (!admin) await auth.logout();
  if (context.mounted) {
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LicenceRegistrationScreen()), (_) => false);
  }
}

class LicenceRegistrationScreen extends StatefulWidget {
  const LicenceRegistrationScreen({Key? key}) : super(key: key);

  @override
  State<LicenceRegistrationScreen> createState() => _LicenceRegistrationScreenState();
}

class _LicenceRegistrationScreenState extends State<LicenceRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _licenceController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _licenceController.dispose();
    super.dispose();
  }

  Future<void> _submitLicence() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final provider = Provider.of<LicenceProvider>(context, listen: false);
    // On nettoie la saisie (trim)
    final success = await provider.registerLicence(_licenceController.text.trim());

    setState(() => _isLoading = false);

    if (success && mounted) {
      // Activation faite avec la session d'un administrateur : session fermée, connexion normale ensuite.
      if (provider.activationParAdministrateur) {
        provider.activationParAdministrateur = false;
        await Provider.of<AuthProvider>(context, listen: false).logout();
        if (!mounted) return;
      }
      // Licence validée -> Direction Login
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Licence activée avec succès !"),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage.isNotEmpty
                ? provider.errorMessage
                : "Licence invalide ou impossible à vérifier."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Gestion Responsive pour centrer la carte
    final isDesktop = Responsive.isDesktop(context);
    final isTablet = Responsive.isTablet(context);
    final width = MediaQuery.of(context).size.width;

    double cardWidth;
    if (isDesktop) {
      cardWidth = width * 0.35;
    } else if (isTablet) {
      cardWidth = width * 0.6;
    } else {
      cardWidth = width * 0.9;
    }

    // Récupération du statut pour afficher un message spécifique si expiré
    final status = context.watch<LicenceProvider>().status;
    String titleText = "Activation de Licence";
    if (status == LicenceStatus.expired) {
      titleText = "Licence Expirée";
    }

    return Scaffold(
      backgroundColor: AppColors.primary, // CORRECTION : AppColors.primary
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                margin: const EdgeInsets.only(bottom: 30),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon( // CORRECTION : const ajouté pour optimisation
                  Icons.verified_user_outlined, // Icône cadenas/licence
                  size: 60,
                  color: AppColors.primary, // CORRECTION : AppColors.primary
                ),
              ),

              // Carte de saisie
              Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Container(
                  width: cardWidth,
                  padding: const EdgeInsets.all(30),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        Text(
                          titleText,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: status == LicenceStatus.expired
                                ? Colors.red
                                : AppColors.primary, // CORRECTION : AppColors.primary
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Veuillez saisir votre clé de licence pour utiliser l'application Prestige Vente.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 12),
                        // Problème de connexion : ce n'est pas la licence qui est en cause
                        if (status == LicenceStatus.error && context.watch<LicenceProvider>().issue != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              border: Border.all(color: Colors.orange.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "${context.watch<LicenceProvider>().errorTitle} : vérifiez la configuration serveur "
                              "avant de saisir une clé.",
                              style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w600),
                            ),
                          ),
                        // Demande 11 (option A) : le serveur exige une session → connexion d'un administrateur.
                        if (context.watch<LicenceProvider>().sessionRequise && !context.watch<LicenceProvider>().activationParAdministrateur) ...[
                          Container(
                            key: const Key('licence_session_requise'),
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              border: Border.all(color: Colors.orange.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              LicenceProvider.messageActivationAdministrateur,
                              style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton.icon(
                              key: const Key('licence_connexion_admin'),
                              onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen())),
                              icon: const Icon(Icons.admin_panel_settings_outlined),
                              label: const Text('Connexion administrateur'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          "Serveur : ${LicenceProvider.serverHost(context.watch<SettingsProvider>().baseUrl)}",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        const SizedBox(height: 18),

                        // Champ de saisie
                        TextFormField(
                          controller: _licenceController,
                          decoration: InputDecoration(
                            labelText: "Clé de Licence",
                            hintText: "Entrez la clé fournie",
                            prefixIcon: const Icon(Icons.vpn_key),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return "La clé est obligatoire";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 25),

                        // Bouton Valider
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _submitLicence,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary, // CORRECTION : AppColors.primary
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text(
                              "ACTIVER LA LICENCE",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Bouton Configuration (Lien discret)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => InterfaceVersion.settings()),
                            );
                          },
                          icon: const Icon(Icons.settings, size: 18),
                          label: const Text("Configuration Serveur"),
                          style: TextButton.styleFrom(foregroundColor: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Copyright
              const SizedBox(height: 30),
              const Text(
                "© Prestige Vente",
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}