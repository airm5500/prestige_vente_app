// lib/screens/auth/licence_registration_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/screens/auth/settings_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/utils/responsive.dart';

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
                        const SizedBox(height: 30),

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
                              MaterialPageRoute(builder: (_) => const SettingsScreen()),
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