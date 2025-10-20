// lib/screens/auth/settings_screen.dart
// 20/10/2025 03:45
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/screens/auth/qr_code_preview_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _localIpController;
  late TextEditingController _remoteIpController;
  late TextEditingController _appNameController;
  late TextEditingController _portController;
  final _formKey = GlobalKey<FormState>();
  String? _pingResult;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    _localIpController = TextEditingController(text: settings.localIp);
    _remoteIpController = TextEditingController(text: settings.remoteIp);
    _appNameController = TextEditingController(text: settings.appName);
    _portController = TextEditingController(text: settings.port);
  }

  @override
  void dispose() {
    _localIpController.dispose();
    _remoteIpController.dispose();
    _appNameController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _onPing(String ip, String port, String appName) async {
    setState(() => _pingResult = 'Test en cours...');
    final success = await Provider.of<SettingsProvider>(context, listen: false).ping(ip, port, appName);
    setState(() => _pingResult = success ? 'Connexion réussie !' : 'Échec de la connexion.');
  }

  Future<void> _onSave() async {
    if (_formKey.currentState!.validate()) {
      final provider = Provider.of<SettingsProvider>(context, listen: false);
      final success = await provider.saveSettings(
        localIp: _localIpController.text, remoteIp: _remoteIpController.text,
        appName: _appNameController.text, port: _portController.text,
      );
      if (mounted) {
        if (success) {
          Constants.showSnackBar(context, 'Paramètres enregistrés avec succès.');
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
        } else {
          Constants.showSnackBar(context, 'Impossible de joindre le serveur.', isError: true);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuration du Serveur')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Consumer<SettingsProvider>(
              builder: (context, settings, child) {
                return Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildIpField(controller: _localIpController, label: 'Adresse IP Locale', isRequired: true),
                      const SizedBox(height: 20),
                      _buildIpField(controller: _remoteIpController, label: 'Adresse IP Distante (Optionnel)', isRequired: false),
                      const SizedBox(height: 20),
                      TextFormField(controller: _appNameController, decoration: const InputDecoration(labelText: 'Nom Application Serveur'), validator: (value) => value!.isEmpty ? 'Ce champ est requis' : null),
                      const SizedBox(height: 20),
                      TextFormField(controller: _portController, decoration: const InputDecoration(labelText: 'Port'), keyboardType: TextInputType.number, validator: (value) => value!.isEmpty ? 'Ce champ est requis' : null),
                      const Divider(height: 40),

                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Text("Largeur du ticket", style: TextStyle(fontSize: 16)), ToggleButtons( isSelected: [ settings.paperWidth == 58, settings.paperWidth == 80 ], onPressed: (index) { settings.setPaperWidth(index == 0 ? 58 : 80); }, borderRadius: BorderRadius.circular(8), children: const [ Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('58mm')), Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('80mm')) ], ), ], ),
                      const SizedBox(height: 10),
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Text("Mode test d'impression", style: TextStyle(fontSize: 16)), Switch( value: settings.isTestPrintMode, onChanged: (value) { settings.setTestPrintMode(value); } ), ], ),
                      const SizedBox(height: 10),
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Flexible(child: Text("Afficher QR code (Vente)", style: TextStyle(fontSize: 16))), Switch( value: settings.showQrCodeOnSaleTicket, onChanged: (value) { settings.setShowQrCodeOnSaleTicket(value); } ), ], ),
                      const SizedBox(height: 10),
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Flexible(child: Text("Modifier Contrôle Livraison", style: TextStyle(fontSize: 16))), Switch( value: settings.canEditDeliveryControl, onChanged: (value) { settings.setCanEditDeliveryControl(value); } ), ], ),
                      const SizedBox(height: 10),
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Flexible(child: Text("Modifier Pointage BL", style: TextStyle(fontSize: 16))), Switch( value: settings.canEditBlControl, onChanged: (value) { settings.setCanEditBlControl(value); } ), ], ),

                      const Divider(height: 30),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text("Aperçu des QR Codes de Paiement"),
                        onPressed: () {
                          // MODIFICATION : On vérifie si l'IP est configurée avant de naviguer
                          if (settings.localIp.isEmpty) {
                            Constants.showSnackBar(
                              context,
                              "Veuillez renseigner l'adresse ip svp",
                              isError: true,
                            );
                          } else {
                            Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const QrCodePreviewScreen())
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 20),

                      if (_pingResult != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 15.0),
                          child: Text(_pingResult!, textAlign: TextAlign.center, style: TextStyle(color: _pingResult!.contains('réussie') ? AppColors.success : AppColors.error, fontWeight: FontWeight.bold)),
                        ),
                      settings.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : ElevatedButton(onPressed: _onSave, child: const Text('Enregistrer')),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIpField({ required TextEditingController controller, required String label, required bool isRequired}) { return Row( children: [ Expanded( child: TextFormField( controller: controller, decoration: InputDecoration(labelText: label), keyboardType: TextInputType.phone, validator: (value) { if (isRequired && value!.isEmpty) { return 'Ce champ est requis'; } return null; }, ), ), const SizedBox(width: 10), IconButton( icon: const Icon(Icons.network_ping, color: AppColors.secondary), onPressed: () => _onPing( controller.text, _portController.text, _appNameController.text), tooltip: 'Tester la connexion', ), ], ); }
}