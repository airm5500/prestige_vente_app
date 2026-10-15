// lib/borne/borne_launcher.dart
// Ouverture de la borne dans l'appli : connexion de l'utilisateur borne (mot de passe lu dans le
// stockage sécurisé), passerelle des ventes, imprimante Sunmi, kiosque Android, sortie par code admin.
// Démarrage : si le mode borne est actif sur cet appareil, l'écran de démarrage ouvre directement la borne.
// 4.1.2 (retours du pharmacien) :
// - « Quitter le mode borne » (cadenas, appui long 2 s, confirmation, code administrateur) : désépinglage,
//   mode borne DÉSACTIVÉ sur cet appareil (sinon l'appli rouvrait la borne au démarrage suivant), déconnexion de
//   l'utilisateur borne, retour à l'écran de connexion (avant : accueil ouvert avec la session de l'utilisateur
//   borne, mode borne toujours actif) ;
// - borne sans données : cause affichée (utilisateur non configuré, mot de passe absent, connexion refusée,
//   serveur injoignable) au lieu d'un « indisponible » muet ;
// - session de l'utilisateur borne expirée sur le serveur : la borne reconnecte SON utilisateur (avant :
//   l'intercepteur ne savait reconnecter que le compte « Rester connecté » et renvoyait la borne épinglée sur
//   l'écran de connexion de l'appli).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/session_expiree.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_kiosque.dart';
import 'package:prestige_vente_app/borne/borne_screen.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/images/produit_image_widget.dart';
import 'package:prestige_vente_app/images/produit_images.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
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

  /// Écran affiché après « Quitter le mode borne » (remplaçable dans les tests).
  static Widget Function() apresSortie = () => const LoginScreen();

  /// Sortie du mode borne (code administrateur déjà vérifié, kiosque déjà arrêté) : mode borne désactivé sur
  /// CET appareil (les autres réglages de la borne sont gardés), déconnexion de l'utilisateur borne, écran de
  /// connexion de l'appli.
  static Future<void> quitter(BuildContext context, {ApiService? api, AuthProvider? auth}) async {
    final nav = Navigator.of(context);
    await BorneReglages.enregistrer(BorneReglages.courant.value.copyWith(actif: false));
    try {
      await api?.logout();
    } catch (_) {}
    // Déconnexion LOCALE (sans toucher « Rester connecté » du compte de la pharmacie).
    auth?.sessionExpiree();
    nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => apresSortie()), (_) => false);
  }
}

/// Cause d'un échec de connexion de la borne, en clair pour le personnel (null : aucune).
String? motifConnexionBorne({required String login, required bool motDePasse, EchecConnexion? echec}) {
  if (login.trim().isEmpty) return 'Utilisateur borne non configuré : renseignez-le dans Réglages › Borne libre-service.';
  if (!motDePasse) {
    return 'Mot de passe de l\'utilisateur borne « $login » absent sur cet appareil : ressaisissez-le dans Réglages › Borne libre-service.';
  }
  if (echec == null) return null;
  if (echec.estRefus) {
    return 'Connexion refusée pour l\'utilisateur borne « $login » (${echec.message}) : vérifiez le login et le mot de passe '
        'dans Réglages › Borne libre-service.';
  }
  return echec.message;
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
  final GlobalKey<BorneScreenState> _cle = GlobalKey();

  /// Cause du dernier échec de connexion (affichée sur l'écran « indisponible »).
  String? _motif;

  // Intercepteur de session de l'appli, remis en place à la sortie de la borne.
  late final SessionExpiree _session = SessionExpiree.instance;
  late final Future<bool> Function() _reconnecterAppli = _session.reconnecter;
  late final void Function(String) _versConnexionAppli = _session.versConnexion;

  @override
  void initState() {
    super.initState();
    // Session de l'utilisateur borne expirée : reconnexion de CET utilisateur (identifiants de la borne), puis
    // requête rejouée ; si impossible : borne indisponible avec la cause, nouvel essai — jamais l'écran de
    // connexion de l'appli sur une borne épinglée.
    _session.reconnecter = () => _connexion(force: true);
    _session.versConnexion = (_) => _cle.currentState?.connexionPerdue();
  }

  @override
  void dispose() {
    _session.reconnecter = _reconnecterAppli;
    _session.versConnexion = _versConnexionAppli;
    super.dispose();
  }

  /// Connexion avec l'utilisateur borne (identifiants enregistrés de façon sûre). [force] : nouvelle connexion
  /// même si l'utilisateur borne paraît connecté (session expirée sur le serveur).
  Future<bool> _connexion({bool force = false}) async {
    if (!force && _auth.user != null && _auth.user!.login.toLowerCase() == _config.login.toLowerCase()) {
      if (_auth.officine == null) await _auth.loadOfficineInfo();
      _motif = null;
      return true;
    }
    final mdp = await BorneReglages.secrets.lire();
    final present = mdp != null && mdp.isNotEmpty;
    if (!present || _config.login.isEmpty) {
      _motif = motifConnexionBorne(login: _config.login, motDePasse: present);
      return false;
    }
    final ok = await _auth.login(_config.login, mdp);
    _motif = ok ? null : (motifConnexionBorne(login: _config.login, motDePasse: true, echec: _api.dernierEchecConnexion) ??
        'Connexion de l\'utilisateur borne « ${_config.login} » impossible.');
    if (ok) await _auth.loadOfficineInfo();
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final auth = context.watch<AuthProvider>();
    return BorneScreen(
      key: _cle,
      service: _service,
      config: _config,
      monitor: HorsLigne.instance.monitor,
      imprimante: SunmiBorneImprimante(modeTest: settings.isTestPrintMode),
      kiosque: BorneKiosque.instance,
      adminCheck: PinCodeDialog.show,
      connexion: _connexion,
      motifConnexion: () => _motif,
      scanner: (ctx) => CameraScanScreen.open(ctx, title: 'Scanner un produit'),
      officine: auth.officine?.nomComplet ?? '',
      // B2 : images du serveur (cache disque), produits avec image mis en avant.
      image: (p, taille, picto) => ProduitImage(familleId: p.id, taille: taille, placeholder: picto),
      imageConnue: ProduitImages.instance.aImage,
      // B3 : mobile money (réglage Paiements mobile money + module serveur) ; sinon « Payer en caisse » seul.
      paiementsMobile: PaiementsMobile.instance,
      codeType: settings.ticketCodeType,
      largeurTicket: settings.paperWidth,
      onSortie: (ctx) => BorneLauncher.quitter(ctx, api: _api, auth: _auth),
    );
  }
}
