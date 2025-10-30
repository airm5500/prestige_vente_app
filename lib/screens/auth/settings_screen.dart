// lib/screens/auth/settings_screen.dart
// 30/10/2025 00:45
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/screens/auth/qr_code_preview_screen.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';


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

  bool _isLoadingPaymentMethods = false;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    _localIpController = TextEditingController(text: settings.localIp);
    _remoteIpController = TextEditingController(text: settings.remoteIp);
    _appNameController = TextEditingController(text: settings.appName);
    _portController = TextEditingController(text: settings.port);

    _loadPaymentMethods();
  }

  Future<void> _loadPaymentMethods() async {
    if (Provider.of<SettingsProvider>(context, listen: false).localIp.isEmpty) {
      return;
    }
    setState(() => _isLoadingPaymentMethods = true);
    await Provider.of<SaleProvider>(context, listen: false).fetchPaymentMethodsWithQr();
    if(mounted) {
      setState(() => _isLoadingPaymentMethods = false);
    }
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

  // MODIFICATION (Point 1) : Fonction qui ouvre le Pop-up
  void _showPaymentMethodDialog() {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);

    // On récupère tous les modes de paiement chargés
    final allMethods = saleProvider.paymentMethodsWithQr;

    showDialog(
      context: context,
      builder: (ctx) {
        // StatefulBuilder est nécessaire pour que les Checkbox se mettent à jour
        // à l'intérieur du pop-up (qui est un widget "stateless" à la base)
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Gérer les modes de paiement'),
              content: SizedBox(
                width: double.maxFinite,
                // Utilise SingleChildScrollView si la liste est longue
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: allMethods.map((PaymentMethodQr method) {
                      return CheckboxListTile(
                        title: Text(method.name),
                        // On lit l'état actuel depuis le provider
                        value: settings.enabledPaymentMethodIds.contains(method.id),
                        onChanged: (bool? value) {
                          if (value != null) {
                            // 1. On met à jour le provider (sauvegarde)
                            settings.togglePaymentMethod(method.id, value);
                            // 2. On rafraîchit l'UI du pop-up
                            setDialogState(() {});
                          }
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Fermer'),
                  onPressed: () => Navigator.of(ctx).pop(),
                )
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuration')),
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
                      Text('Serveur', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 10),
                      _buildIpField(controller: _localIpController, label: 'Adresse IP Locale', isRequired: true),
                      const SizedBox(height: 20),
                      _buildIpField(controller: _remoteIpController, label: 'Adresse IP Distante (Optionnel)', isRequired: false),
                      const SizedBox(height: 20),
                      TextFormField(controller: _appNameController, decoration: const InputDecoration(labelText: 'Nom Application Serveur'), validator: (value) => value!.isEmpty ? 'Ce champ est requis' : null),
                      const SizedBox(height: 20),
                      TextFormField(controller: _portController, decoration: const InputDecoration(labelText: 'Port'), keyboardType: TextInputType.number, validator: (value) => value!.isEmpty ? 'Ce champ est requis' : null),

                      const Divider(height: 40),

                      Text('Impression', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 10),
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Text("Largeur du ticket", style: TextStyle(fontSize: 16)), ToggleButtons( isSelected: [ settings.paperWidth == 58, settings.paperWidth == 80 ], onPressed: (index) { settings.setPaperWidth(index == 0 ? 58 : 80); }, borderRadius: BorderRadius.circular(8), children: const [ Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('58mm')), Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('80mm')) ], ), ], ),
                      const SizedBox(height: 10),
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Text("Mode test d'impression", style: TextStyle(fontSize: 16)), Switch( value: settings.isTestPrintMode, onChanged: (value) { settings.setTestPrintMode(value); } ), ], ),
                      const SizedBox(height: 10),
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Flexible(child: Text("Afficher QR/Code-barres (Vente)", style: TextStyle(fontSize: 16))), Switch( value: settings.showQrCodeOnSaleTicket, onChanged: (value) { settings.setShowQrCodeOnSaleTicket(value); } ), ], ),
                      const SizedBox(height: 10),
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Flexible(child: Text("Nombre de tickets (Vente)", style: TextStyle(fontSize: 16))), SizedBox( width: 80, child: DropdownButtonFormField<int>( value: settings.numberOfTickets, items: [1, 2, 3].map((int value) => DropdownMenuItem<int>(value: value, child: Text(value.toString()))).toList(), onChanged: (value) { if(value != null) settings.setNumberOfTickets(value); }, decoration: const InputDecoration(isDense: true), ), ) ], ),
                      const SizedBox(height: 10),
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Text("Type de code ticket", style: TextStyle(fontSize: 16)), ToggleButtons( isSelected: [ settings.ticketCodeType == 'QR_CODE', settings.ticketCodeType == 'BARCODE' ], onPressed: (index) { settings.setTicketCodeType(index == 0 ? 'QR_CODE' : 'BARCODE'); }, borderRadius: BorderRadius.circular(8), children: const [ Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('QR Code')), Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Code-barres')) ], ), ], ),

                      const Divider(height: 30),

                      Text('Droits', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 10),
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Flexible(child: Text("Modifier Contrôle Livraison", style: TextStyle(fontSize: 16))), Switch( value: settings.canEditDeliveryControl, onChanged: (value) { settings.setCanEditDeliveryControl(value); } ), ], ),
                      const SizedBox(height: 10),
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Flexible(child: Text("Modifier Pointage BL", style: TextStyle(fontSize: 16))), Switch( value: settings.canEditBlControl, onChanged: (value) { settings.setCanEditBlControl(value); } ), ], ),

                      const Divider(height: 30),

                      Text('Modes de Paiement', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 10),

                      // MODIFICATION (Point 1) : Remplacement de la liste par des boutons
                      _buildPaymentSettingsButtons(settings),

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

  // MODIFICATION (Point 1) : Nouveau widget pour les boutons
  Widget _buildPaymentSettingsButtons(SettingsProvider settings) {
    if (_isLoadingPaymentMethods) {
      return const Center(child: CircularProgressIndicator());
    }

    if (settings.localIp.isEmpty) {
      return const Center(child: Text("Veuillez d'abord configurer l'IP du serveur."));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Bouton pour ouvrir le Pop-up
        OutlinedButton.icon(
          icon: const Icon(Icons.credit_card),
          label: const Text("Gérer les modes de paiement"),
          onPressed: _showPaymentMethodDialog,
        ),
        const SizedBox(height: 8),
        // 2. Bouton pour l'aperçu (gardé)
        OutlinedButton.icon(
          icon: const Icon(Icons.qr_code_2),
          label: const Text("Aperçu des QR Codes de Paiement"),
          onPressed: () {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const QrCodePreviewScreen())
            );
          },
        ),
      ],
    );
  }
}