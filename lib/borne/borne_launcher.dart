// lib/borne/borne_launcher.dart
// Ouverture de la borne dans l'appli : connexion de l'utilisateur borne (mot de passe lu dans le
// stockage sécurisé), passerelle des ventes, imprimante Sunmi, kiosque Android, sortie par code admin.
// Démarrage : si le mode borne est actif sur cet appareil, l'écran de démarrage ouvre directement la borne.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_kiosque.dart';
import 'package:prestige_vente_app/borne/borne_screen.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/images/produit_image_widget.dart';
import 'package:prestige_vente_app/images/produit_images.dart';
import 'package:prestige_vente_app/interface_version.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/common/camera_scan_screen.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:provider/provider.dart';

class BorneLauncher {
  BorneLauncher._();

  /// La borne doit s'ouvrir au démarrage (mode actif et utilisateur borne renseigné).
  static bool get auDemarrage {
    final c = BorneReglages.courant.value;
    return c.actif && c.login.isNotEmpty;
  }

  /// Remplace toute la pile par la borne.
  static Future<void> ouvrir(BuildContext context) =>
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const BorneHote()), (_) => false);
}

/// Hôte de la borne : services stables, nom de l'officine suivi (chargé après la connexion).
class BorneHote extends StatefulWidget {
  const BorneHote({super.key});

  @override
  State<BorneHote> createState() => _BorneHoteState();
}

class _BorneHoteState extends State<BorneHote> {
  late final ApiService _api = context.read<ApiService>();
  late final AuthProvider _auth = context.read<AuthProvider>();
  late final BorneService _service = BorneService(DioVenteGateway(_api));
  final BorneConfig _config = BorneReglages.courant.value;

  /// Connexion avec l'utilisateur borne (identifiants enregistrés de façon sûre).
  Future<bool> _connexion() async {
    if (_auth.user != null && _auth.user!.login.toLowerCase() == _config.login.toLowerCase()) {
      if (_auth.officine == null) await _auth.loadOfficineInfo();
      return true;
    }
    final mdp = await BorneReglages.secrets.lire();
    if (mdp == null || _config.login.isEmpty) return false;
    final ok = await _auth.login(_config.login, mdp);
    if (ok) await _auth.loadOfficineInfo();
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final auth = context.watch<AuthProvider>();
    return BorneScreen(
      service: _service,
      config: _config,
      monitor: HorsLigne.instance.monitor,
      imprimante: SunmiBorneImprimante(modeTest: settings.isTestPrintMode),
      kiosque: BorneKiosque.instance,
      adminCheck: PinCodeDialog.show,
      connexion: _connexion,
      scanner: (ctx) => CameraScanScreen.open(ctx, title: 'Scanner un produit'),
      officine: auth.officine?.nomComplet ?? '',
      // B2 : images du serveur (cache disque), produits avec image mis en avant.
      image: (p, taille, picto) => ProduitImage(familleId: p.id, taille: taille, placeholder: picto),
      imageConnue: ProduitImages.instance.aImage,
      codeType: settings.ticketCodeType,
      largeurTicket: settings.paperWidth,
      onSortie: (ctx) => Navigator.of(ctx).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => InterfaceVersion.home()), (_) => false),
    );
  }
}
