// lib/prestigepos/pos_app.dart
// PrestigePOS — application de vente libre-service, construite depuis le MÊME projet que Prestige Mobile
// (saveur Android `pos`, point d'entrée lib/main_pos.dart). Elle ne contient que la borne de Prestige Mobile
// (lib/borne/ : recherche, catégories, fiche, panier, vérification prix/stock, prévente, ticket QR, kiosque,
// sortie par code administrateur) et ce qui lui est propre (lib/prestigepos/ : assistant, administration,
// imprimantes Bluetooth / USB / réseau). Même serveur, mêmes routes, même session (cookie JSESSIONID).
//
// Démarrage : réglages lus → assistant de configuration au premier lancement (code administrateur) →
// licence vérifiée → borne plein écran (kiosque). Sortie de la borne (cadenas, appui long 2 s, confirmation,
// code administrateur) → écran d'administration (reprendre, assistant, imprimante, réglages, test).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_launcher.dart';
import 'package:prestige_vente_app/connexion/session_expiree_app.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/prestigepointage/lanceur_pointage.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_pos.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_reglages.dart';
import 'package:prestige_vente_app/prestigepos/pos_admin.dart';
import 'package:prestige_vente_app/prestigepos/pos_assistant.dart';
import 'package:prestige_vente_app/prestigepos/pos_reglages.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/connexion/changement_utilisateur.dart';

/// Points de personnalisation de PrestigePOS (remplacés dans les tests).
class PosApp {
  PosApp._();

  static const nom = 'PrestigePOS';

  /// Code administrateur (assistant, administration). Par défaut : code administrateur de l'appareil.
  static Future<bool> Function(BuildContext) codeAdmin = PinCodeDialog.show;

  /// Imprimante du ticket.
  static ImprimantePos Function() imprimante = () => ImprimantePos();

  /// Branche la borne de PrestigePOS sur le code partagé de la borne (BorneLauncher).
  static void installer() {
    BorneLauncher.hote = () => const PosBorne();
    BorneLauncher.apresSortie = () => const PosAdminScreen();
    // 1.8.0 : aucun bouton « Pointer » (Prestige Pointage) dans PrestigePOS — borne tournée vers les clients, aucun
    // écran de Prestige Mobile affiché ; même si l'un d'eux l'était, Prestige Pointage est tenue pour absente.
    LanceurPointage.detecteur = () async => false;
    LanceurPointage.installee.value = false;
  }

  /// Ouvre la borne (mode borne actif : la borne se rouvre aussi au prochain démarrage).
  static Future<void> ouvrirBorne(BuildContext context) async {
    final nav = Navigator.of(context);
    await BorneReglages.enregistrer(BorneReglages.courant.value.copyWith(actif: true));
    if (!nav.mounted) return;
    nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => BorneLauncher.hote()), (_) => false);
  }

  /// Configuration complète : assistant terminé, serveur et utilisateur borne renseignés.
  static bool configure(SettingsProvider s) => PosReglages.courant.value.configure && s.isConfigured && BorneReglages.courant.value.login.isNotEmpty;
}

/// Borne de PrestigePOS : borne partagée (BorneHote) avec l'imprimante de PrestigePOS, plein écran immersif.
class PosBorne extends StatefulWidget {
  const PosBorne({super.key});

  @override
  State<PosBorne> createState() => _PosBorneState();
}

class _PosBorneState extends State<PosBorne> {
  late final ImprimantePos _imprimante = PosApp.imprimante();

  @override
  void initState() {
    super.initState();
    // Plein écran : barres système masquées (elles réapparaissent un instant sur un glissement du bord).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ImprimanteConfig>(
        valueListenable: ImprimanteReglages.courant,
        builder: (_, c, __) => BorneHote(imprimante: _imprimante, largeurTicket: c.papier),
      );
}

/// Application PrestigePOS.
class PrestigePosApp extends StatelessWidget {
  const PrestigePosApp({super.key});

  @override
  Widget build(BuildContext context) {
    PosApp.installer();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ProxyProvider<SettingsProvider, ApiService>(update: (_, settings, __) => ApiService(baseUrl: settings.baseUrl)),
        ChangeNotifierProxyProvider<ApiService, LicenceProvider>(
          create: (ctx) => LicenceProvider(ctx.read<ApiService>()),
          update: (_, api, previous) => previous!..updateApiService(api),
        ),
        ChangeNotifierProxyProvider<ApiService, AuthProvider>(
          // Session expirée : la borne reconnecte SON utilisateur (BorneHote) ; ailleurs, retour à l'administration.
          create: (ctx) {
            final auth = AuthProvider(ctx.read<ApiService>());
            // Hors de la borne (jamais l'écran de connexion de Prestige Mobile) : redémarrage de PrestigePOS.
            brancherSessionExpiree(auth, ecranConnexion: (_) => const PosDemarrage());
            // 4.5.1 (Prestige Mobile) : 409 « session changée » → redémarrage de PrestigePOS (la borne reconnecte son
            // utilisateur) ; droits de vente relus au retour au premier plan.
            brancherChangementUtilisateur(auth, accueil: () => const PosDemarrage());
            return auth;
          },
          update: (_, api, previous) => previous!..updateApiService(api),
        ),
      ],
      child: RacineTailleEcran(
        child: MaterialApp(
          title: PosApp.nom,
          navigatorKey: HorsLigne.navigatorKey,
          theme: AppTheme.lightTheme,
          debugShowCheckedModeBanner: false,
          builder: (context, child) => PosServeurScope(child: child ?? const SizedBox.shrink()),
          home: const PosDemarrage(),
        ),
      ),
    );
  }
}

/// Surveillance du serveur (borne « momentanément indisponible » si injoignable) et branchement des services de
/// la borne (paiements mobile money, images) sur l'ApiService courant. Version allégée de HorsLigneScope :
/// PrestigePOS ne télécharge pas de copie du catalogue et ne vend pas hors ligne.
class PosServeurScope extends StatefulWidget {
  final Widget child;
  const PosServeurScope({super.key, required this.child});

  @override
  State<PosServeurScope> createState() => _PosServeurScopeState();
}

class _PosServeurScopeState extends State<PosServeurScope> {
  late final HorsLigne _hl = HorsLigne.instance;

  @override
  void initState() {
    super.initState();
    _hl.monitor.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = Provider.of<ApiService?>(context);
    if (api != null) _hl.bind(api);
  }

  @override
  void dispose() {
    _hl.monitor.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Démarrage : réglages, assistant (premier lancement), licence, borne.
class PosDemarrage extends StatefulWidget {
  const PosDemarrage({super.key});

  @override
  State<PosDemarrage> createState() => _PosDemarrageState();
}

class _PosDemarrageState extends State<PosDemarrage> {
  String? _erreur;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _demarrer());
  }

  Future<void> _demarrer() async {
    setState(() => _erreur = null);
    final settings = context.read<SettingsProvider>();
    await settings.loadSettings();
    if (!mounted) return;
    // L'ApiService est recréé à l'image suivante avec l'adresse lue (ANO-08 de Prestige Mobile).
    if (context.read<ApiService>().dio.options.baseUrl != settings.baseUrl) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    final nav = Navigator.of(context);
    if (!PosApp.configure(settings)) {
      nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const PosBienvenue()), (_) => false);
      return;
    }
    final api = context.read<ApiService>();
    final licence = context.read<LicenceProvider>()..updateApiService(api);
    context.read<AuthProvider>().updateApiService(api);
    final statut = await licence.checkLicence();
    if (!mounted) return;
    if (statut == LicenceStatus.none || statut == LicenceStatus.expired) {
      nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => PosLicenceScreen(expiree: statut == LicenceStatus.expired)), (_) => false);
      return;
    }
    // Licence valide, ou serveur injoignable : la borne s'ouvre (« momentanément indisponible » et reprise
    // automatique dès que le serveur répond).
    await PosApp.ouvrirBorne(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('pos-demarrage'),
        backgroundColor: Colors.white,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const PosLogo(taille: 96),
            const SizedBox(height: 20),
            const Text(PosApp.nom, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Pal.navy)),
            const SizedBox(height: 18),
            if (_erreur == null) const CircularProgressIndicator() else Text(_erreur!),
          ]),
        ),
      );
}

/// Logo de PrestigePOS (chariot + coche), dessiné : aucune image à embarquer.
class PosLogo extends StatelessWidget {
  final double taille;
  const PosLogo({super.key, this.taille = 72});

  @override
  Widget build(BuildContext context) => Container(
        width: taille,
        height: taille,
        decoration: BoxDecoration(color: const Color(0xFFE3ECF7), borderRadius: BorderRadius.circular(taille * .24)),
        child: Stack(alignment: Alignment.center, children: [
          Icon(Icons.shopping_cart_outlined, size: taille * .62, color: Pal.navy),
          Positioned(
            right: taille * .08,
            top: taille * .08,
            child: Container(
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(Icons.check_circle, size: taille * .34, color: Pal.green),
            ),
          ),
        ]),
      );
}
