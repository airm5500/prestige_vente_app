// lib/screens/auth/settings_screen.dart
// 13/11/2025 10:00 (Complet : Assurance + Menu Organizer + Sécurité PIN + Stock BL Mode)
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/parametres/nom_appareil_reglage.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/services/ticket_prevente.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/interface_version.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart'; // Pour isAdmin
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/screens/auth/qr_code_preview_screen.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/screens/home/menu_organizer_screen.dart';
import 'package:prestige_vente_app/screens/splash_screen.dart';
import 'package:prestige_vente_app/parametres/taille_ecran_reglage.dart';
import 'package:prestige_vente_app/parametres/protocole_choix.dart';
import 'package:prestige_vente_app/serveur/adresse_serveur.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart'; // Pour la sécurité
import 'package:prestige_vente_app/ventes/ventes_version.dart';
import 'package:prestige_vente_app/version_app.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Adresse sans protocole + choix http / https (4.1.0 ; « https://… » saisi dans le champ règle le choix).
  late AdresseAvecProtocole _localA;
  late AdresseAvecProtocole _remoteA;
  late TextEditingController _appNameController;
  late TextEditingController _portController;
  final _formKey = GlobalKey<FormState>();
  String? _pingResult;

  bool _isLoadingPaymentMethods = false;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    _localA = AdresseAvecProtocole(settings.localIp, surChangement: _majProtocole);
    _remoteA = AdresseAvecProtocole(settings.remoteIp, surChangement: _majProtocole);
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
    _localA.dispose();
    _remoteA.dispose();
    _appNameController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _majProtocole() {
    if (mounted) setState(() {});
  }

  /// Protocole du serveur local changé : le port par défaut suit (8080 ↔ 443) ; un autre port est gardé.
  void _protocoleLocal(String p) {
    final ancien = _localA.protocole;
    if (p == ancien) return;
    setState(() {
      _localA.protocole = p;
      final port = _portController.text.trim();
      if (port.isEmpty || port == AdresseServeur.portParDefaut(ancien)) _portController.text = AdresseServeur.portParDefaut(p);
    });
  }

  Future<void> _onPing(AdresseAvecProtocole a, String port, String appName) async {
    final ip = a.adresse;
    // Port effectif : écrit dans l'adresse, sinon champ « Port » (protocole du serveur local), sinon 443 / 8080.
    port = AdresseServeur.portEffectif(ip, portChamp: port.trim(), protocolePrincipal: _localA.protocole);
    setState(() => _pingResult = 'Test en cours...');
    final success = await Provider.of<SettingsProvider>(context, listen: false).ping(ip, port, appName);
    if (!mounted) return;
    final reason = Provider.of<SettingsProvider>(context, listen: false).pingError;
    setState(() => _pingResult = success ? 'Connexion réussie !' : 'Échec de la connexion. $reason');
  }

  Future<void> _onSave() async {
    if (_formKey.currentState!.validate()) {
      final provider = Provider.of<SettingsProvider>(context, listen: false);
      final success = await provider.saveSettings(
        localIp: _localA.adresse, remoteIp: _remoteA.adresse,
        appName: _appNameController.text, port: _portController.text,
      );
      if (mounted) {
        if (success) {
          Constants.showSnackBar(context, 'Paramètres enregistrés avec succès.');
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const SplashScreen()));
        } else {
          final reason = provider.pingError;
          Constants.showSnackBar(context, reason.isEmpty ? 'Impossible de joindre le serveur.' : reason, isError: true);
        }
      }
    }
  }

  void _showPaymentMethodDialog() {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);

    final allMethods = saleProvider.paymentMethodsWithQr;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Gérer les modes de paiement'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: allMethods.map((PaymentMethodQr method) {
                      return CheckboxListTile(
                        title: Text(method.name),
                        value: settings.enabledPaymentMethodIds.contains(method.id),
                        onChanged: (bool? value) {
                          if (value != null) {
                            settings.togglePaymentMethod(method.id, value);
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
    // Récupération du rôle pour afficher/masquer le bouton de modif PIN
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final bool isAdmin = authProvider.isAdmin;

    // 4.7.1 : nom de cet appareil obligatoire (réglages non quittables tant qu'il n'est pas enregistré).
    return GardeNomAppareil(
        child: Scaffold(
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
                      // 4.7.1 : toujours visible ici (interface d'origine) ; obligatoire tant qu'il n'est pas enregistré.
                      ListenableBuilder(
                        listenable: NomAppareil.instance,
                        builder: (_, __) => NomAppareil.instance.nomEnregistre
                            ? ListTile(
                                key: const Key('nom_appareil_ligne'),
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Nom de cet appareil'),
                                subtitle: Text('${NomAppareil.instance.saisi}\n$mentionConservationNomAppareil'),
                                isThreeLine: true,
                                trailing: TextButton(
                                  key: const Key('nom_appareil_modifier'),
                                  onPressed: () => Navigator.of(context)
                                      .push(MaterialPageRoute(builder: (_) => const NomAppareilObligatoireScreen())),
                                  child: const Text('Modifier'),
                                ),
                              )
                            : const Padding(padding: EdgeInsets.only(bottom: 16), child: CarteNomAppareilObligatoire()),
                      ),
                      Text('Serveur', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 10),
                      _buildIpField(adresse: _localA, label: 'Adresse IP Locale', isRequired: true),
                      ProtocoleChoix(
                        key: const Key('protocole_local'),
                        libelle: 'Protocole du serveur local',
                        valeur: _localA.protocole,
                        onChanged: _protocoleLocal,
                      ),
                      const SizedBox(height: 20),
                      _buildIpField(adresse: _remoteA, label: 'Adresse IP Distante (Optionnel)', isRequired: false),
                      ProtocoleChoix(
                        key: const Key('protocole_distant'),
                        libelle: 'Protocole du serveur distant',
                        valeur: _remoteA.protocole,
                        onChanged: (p) => setState(() => _remoteA.protocole = p),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(controller: _appNameController, decoration: const InputDecoration(labelText: 'Nom Application Serveur'), validator: (value) => value!.isEmpty ? 'Ce champ est requis' : null),
                      const SizedBox(height: 20),
                      TextFormField(controller: _portController, decoration: const InputDecoration(labelText: 'Port'), keyboardType: TextInputType.number, validator: (value) => value!.isEmpty ? 'Ce champ est requis' : null),

                      const Divider(height: 40),

                      // SECTION PERSONNALISATION (SÉCURISÉE)
                      Text('Personnalisation', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 10),
                      ListTile(
                        leading: const Icon(Icons.dashboard_customize, color: Colors.blue),
                        title: const Text("Organiser le menu d'accueil"),
                        subtitle: const Text("Changer l'ordre et la visibilité des icônes"),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () async {
                          // AJOUT SÉCURITÉ : Demande PIN
                          bool authorized = await PinCodeDialog.show(context);
                          if (authorized && context.mounted) {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (context) => const MenuOrganizerScreen()),
                            );
                          }
                        },
                      ),

                      // Taille de l'écran (4.0.1) : code administrateur, appliquée au prochain lancement.
                      const TailleEcranSetting(),

                      // SECTION SÉCURITÉ ADMIN (Visible uniquement si Admin)
                      if (isAdmin) ...[
                        const Divider(height: 20),
                        Text('Sécurité Admin', style: Theme.of(context).textTheme.titleLarge),
                        ListTile(
                          leading: const Icon(Icons.lock_reset, color: Colors.red),
                          title: const Text("Modifier le Code PIN Administrateur"),
                          subtitle: const Text("Définir le code pour les menus sensibles"),
                          trailing: const Icon(Icons.edit, size: 16),
                          onTap: () {
                            // Pas de demande de PIN, on est déjà Admin
                            PinCodeDialog.changePin(context);
                          },
                        ),
                      ],

                      const Divider(height: 40),

                      Text('Impression', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 10),
                      _LigneReglage( libelle: "Largeur du ticket", choix: ToggleButtons( isSelected: [ settings.paperWidth == 58, settings.paperWidth == 80 ], onPressed: (index) { settings.setPaperWidth(index == 0 ? 58 : 80); }, borderRadius: BorderRadius.circular(8), children: const [ Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('58mm')), Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('80mm')) ], ), ),
                      const SizedBox(height: 10),
                      _LigneReglage( libelle: "Mode test d'impression", choix: Switch( value: settings.isTestPrintMode, onChanged: (value) { settings.setTestPrintMode(value); } ), ),
                      const SizedBox(height: 10),
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Flexible(child: Text("Afficher QR/Code-barres (Vente)", style: TextStyle(fontSize: 16))), Switch( value: settings.showQrCodeOnSaleTicket, onChanged: (value) { settings.setShowQrCodeOnSaleTicket(value); } ), ], ),
                      // 4.1.1 : produits sur le ticket de prévente du comptoir (désactivé par défaut : ticket d'origine).
                      const SizedBox(height: 10),
                      Row( key: const Key('origine_afficher_produits_prevente'), mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Flexible(child: Text(TicketPrevente.libelleReglage, style: TextStyle(fontSize: 16))), Switch( value: settings.afficherProduitsPrevente, onChanged: (value) { settings.setAfficherProduitsPrevente(value); } ), ], ),
                      Text(TicketPrevente.aideReglage, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                      const SizedBox(height: 10),
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Flexible(child: Text("Nombre de tickets (Vente)", style: TextStyle(fontSize: 16))), SizedBox( width: 80, child: DropdownButtonFormField<int>( value: settings.numberOfTickets, items: [1, 2, 3].map((int value) => DropdownMenuItem<int>(value: value, child: Text(value.toString()))).toList(), onChanged: (value) { if(value != null) settings.setNumberOfTickets(value); }, decoration: const InputDecoration(isDense: true), ), ) ], ),
                      const SizedBox(height: 10),

                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Flexible(child: Text("Nombre de tickets (Assurance)", style: TextStyle(fontSize: 16))), SizedBox( width: 80, child: DropdownButtonFormField<int>( value: settings.numberOfTicketsAssurance, items: [1, 2, 3].map((int value) => DropdownMenuItem<int>(value: value, child: Text(value.toString()))).toList(), onChanged: (value) { if(value != null) settings.setNumberOfTicketsAssurance(value); }, decoration: const InputDecoration(isDense: true), ), ) ], ),
                      const SizedBox(height: 10),

                      // F1 (4.0.3) : libellé et choix côte à côte s'ils tiennent, sinon le choix passe sous le libellé (débordait de
                      // ~132 px, même sur tablette : largeur bornée à 500 dp). Mêmes choix, mêmes valeurs.
                      _LigneReglage( libelle: "Type de code ticket", choix: ToggleButtons( isSelected: [ settings.ticketCodeType == 'QR_CODE', settings.ticketCodeType == 'BARCODE' ], onPressed: (index) { settings.setTicketCodeType(index == 0 ? 'QR_CODE' : 'BARCODE'); }, borderRadius: BorderRadius.circular(8), children: const [ Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('QR Code')), Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Code-barres')) ], ), ),

                      const Divider(height: 30),

                      Text('Droits & Limites', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 10),
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Flexible(child: Text("Modifier Contrôle Livraison", style: TextStyle(fontSize: 16))), Switch( value: settings.canEditDeliveryControl, onChanged: (value) { settings.setCanEditDeliveryControl(value); } ), ], ),
                      const SizedBox(height: 10),
                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Flexible(child: Text("Modifier Pointage BL", style: TextStyle(fontSize: 16))), Switch( value: settings.canEditBlControl, onChanged: (value) { settings.setCanEditBlControl(value); } ), ], ),

                      // NOUVEAU PARAMÈTRE : COMPARAISON STOCK
                      const SizedBox(height: 10),
                      _LigneReglage(
                        libelle: "Comparaison Stock BL",
                        choix: ToggleButtons(
                          isSelected: [
                            settings.blStockComparisonMode == 'theorique',
                            settings.blStockComparisonMode == 'machine'
                          ],
                          onPressed: (index) {
                            settings.setBlStockComparisonMode(index == 0 ? 'theorique' : 'machine');
                          },
                          borderRadius: BorderRadius.circular(8),
                          children: const [
                            Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Théorique')),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Machine'))
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),
                      const VentesVersionTile(),
                      const InterfaceVersionTile(),
                      SwitchListTile(
                        title: const Text("Masquer les produits 'RV'"),
                        value: settings.hideRvProducts,
                        activeColor: AppColors.primary,
                        onChanged: (bool value) {
                          settings.setHideRvProducts(value);
                        },
                      ),

                      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ const Flexible(child: Text("Max Tiers Payants (Assurance)", style: TextStyle(fontSize: 16))), SizedBox( width: 80, child: DropdownButtonFormField<int>( value: settings.maxTiersPayants, items: [1, 2, 3].map((int value) => DropdownMenuItem<int>(value: value, child: Text(value.toString()))).toList(), onChanged: (value) { if(value != null) settings.setMaxTiersPayants(value); }, decoration: const InputDecoration(isDense: true), ), ) ], ),


                      const Divider(height: 30),

                      Text('Modes de Paiement', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 10),

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
                      // Version installée (pubspec.yaml → Gradle), lue à l'exécution.
                      const Padding(
                        padding: EdgeInsets.only(top: 16, bottom: 8),
                        child: VersionAffichee(key: Key('reglages_version')),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ));
  }

  // 4.1.0 : nom de serveur et « https:// » acceptés (clavier adapté en https) ; port explicite « nom:8443 » accepté.
  Widget _buildIpField({ required AdresseAvecProtocole adresse, required String label, required bool isRequired}) { final controller = adresse.champ; return Row( children: [ Expanded( child: TextFormField( controller: controller, decoration: InputDecoration(labelText: label, errorMaxLines: 2), keyboardType: adresse.protocole == AdresseServeur.https ? TextInputType.url : TextInputType.phone, validator: (value) { if (isRequired && value!.isEmpty) { return 'Ce champ est requis'; } if ((value ?? '').trim().isEmpty) return null; return AdresseServeur.erreur(value, requis: isRequired); }, ), ), const SizedBox(width: 10), IconButton( icon: const Icon(Icons.network_ping, color: AppColors.secondary), onPressed: () => _onPing( adresse, _portController.text, _appNameController.text), tooltip: 'Tester la connexion', ), ], ); }

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
        OutlinedButton.icon(
          icon: const Icon(Icons.credit_card),
          label: const Text("Gérer les modes de paiement"),
          onPressed: _showPaymentMethodDialog,
        ),
        const SizedBox(height: 8),
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

/// Ligne « libellé + choix » de la Configuration (4.0.3, F1) : libellé à gauche et choix à droite quand les deux
/// tiennent sur la largeur (aspect d'origine), sinon le choix passe sous le libellé (retour à la ligne) au lieu de
/// déborder ; un choix plus large que l'écran entier (texte très agrandi) se réduit au lieu d'être coupé.
/// Le choix lui-même (boutons, valeurs, enregistrement) est inchangé.
class _LigneReglage extends StatelessWidget {
  final String libelle;
  final Widget choix;
  const _LigneReglage({required this.libelle, required this.choix});

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          Text(libelle, style: const TextStyle(fontSize: 16)),
          FittedBox(fit: BoxFit.scaleDown, child: choix),
        ],
      );
}
