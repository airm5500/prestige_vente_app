// lib/connexion/lancement_screen.dart
// Nouvel écran de lancement (proposition A) — nouvelle interface seulement (InterfaceVersion) ;
// l'écran d'origine (AncienSplashScreen) reste inchangé derrière l'interrupteur.
//
// MÊME LOGIQUE que l'écran d'origine, dans le même ordre : réglages (et migrations silencieuses du mot de
// passe mémorisé et du code administrateur vers le stockage sécurisé) → appareil non configuré :
// Configuration → vérification de la licence (premier contact avec le serveur) → mode borne : borne
// ouverte directement → licence valide : connexion automatique si « Rester connecté », puis accueil,
// sinon écran de connexion → serveur injoignable / licence absente ou expirée : explications.
// Seule la présentation change : les VRAIES étapes sont affichées au fur et à mesure.
//
// Durée : plus d'attente fixe de 2 s (l'écran d'origine, lui, la garde : « délai visuel initial », purement
// visuel). Ici l'écran reste affiché AU MINIMUM 1,2 s (ConnexionServices.affichageMinimum) pour que le logo
// ne clignote pas quand tout est très rapide ; aucune attente en plus : si les étapes durent plus longtemps,
// l'écran suivant s'ouvre dès qu'elles sont finies. Les cas bloquants s'affichent immédiatement.
//
// Serveur injoignable : message clair, « Réessayer », réessai automatique toutes les 10 s,
// « Configuration » protégée par le code administrateur. Pas de « Continuer hors ligne » (décision client).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/licence_lookup.dart';
import 'package:prestige_vente_app/borne/borne_launcher.dart';
import 'package:prestige_vente_app/connexion/assistance.dart';
import 'package:prestige_vente_app/connexion/connexion_commun.dart';
import 'package:prestige_vente_app/connexion/connexion_reglages.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/licence_registration_screen.dart';
import 'package:prestige_vente_app/serveur/adresse_serveur.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

enum EtatEtape { attente, enCours, fait, echec, alerte }

class EtapeLancement {
  final String titre;
  String? detail;
  EtatEtape etat;
  EtapeLancement(this.titre, {this.etat = EtatEtape.attente});
}

enum _Panneau { aucun, premiereUtilisation, injoignable, licence, borne }

class LancementScreen extends StatefulWidget {
  final ConnexionServices? services;
  const LancementScreen({super.key, this.services});

  @override
  State<LancementScreen> createState() => _LancementScreenState();
}

class _LancementScreenState extends State<LancementScreen> {
  ConnexionServices get _sv => widget.services ?? ConnexionServices.instance;

  /// Fin de l'affichage minimal (minuterie lancée à l'ouverture de l'écran).
  late final Future<void> _minimum = Future<void>.delayed(ConnexionServices.affichageMinimum);
  late final CompteARebours _rebours = CompteARebours(duree: ConnexionServices.intervalleReessai, action: _demarrer)
    ..addListener(() {
      if (mounted) setState(() {});
    });

  List<EtapeLancement> _etapes = [];
  _Panneau _panneau = _Panneau.aucun;
  bool _enCours = false;
  LicenceStatus? _licence;

  @override
  void initState() {
    super.initState();
    _minimum.ignore();
    WidgetsBinding.instance.addPostFrameCallback((_) => _demarrer());
  }

  @override
  void dispose() {
    _rebours.dispose();
    super.dispose();
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  Future<void> _attendreMinimum() => _minimum;

  void _remplacer(Widget ecran) {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => ecran), (_) => false);
  }

  Future<void> _demarrer() async {
    if (_enCours || !mounted) return;
    _enCours = true;
    _rebours.arreter();
    final reglages = EtapeLancement('Chargement des réglages', etat: EtatEtape.enCours);
    final serveur = EtapeLancement('Connexion au serveur');
    final licence = EtapeLancement('Vérification de la licence');
    setState(() {
      _panneau = _Panneau.aucun;
      _etapes = [reglages, serveur, licence];
    });
    try {
      await _sequence(reglages, serveur, licence);
    } finally {
      _enCours = false;
    }
  }

  Future<void> _sequence(EtapeLancement reglages, EtapeLancement serveur, EtapeLancement licenceEtape) async {
    final settings = context.read<SettingsProvider>();
    // 1. Réglages (+ migrations silencieuses vers le stockage sécurisé, dans loadSettings).
    await settings.loadSettings();
    await ConnexionReglages.charger();
    // Comme l'écran d'origine : on laisse le framework propager l'adresse à l'ApiService.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    reglages.etat = EtatEtape.fait;

    // 2. Appareil non configuré : Configuration.
    if (!settings.isConfigured) {
      setState(() => _panneau = _Panneau.premiereUtilisation);
      return;
    }

    // 3. Licence (premier contact avec le serveur).
    serveur
      ..etat = EtatEtape.enCours
      ..detail = 'Serveur ${settings.isRemote ? 'distant' : 'local'} · ${settings.adresseAffichee(settings.isRemote)}';
    licenceEtape.etat = EtatEtape.enCours;
    _maj();
    final apiService = Provider.of<ApiService>(context, listen: false);
    final licenceProvider = Provider.of<LicenceProvider>(context, listen: false);
    licenceProvider.updateApiService(apiService);
    final status = await licenceProvider.checkLicence();
    if (!mounted) return;
    _licence = status;

    // 4. Borne libre-service active sur cet appareil : ouverture directe (comme l'écran d'origine).
    if (BorneLauncher.auDemarrage && (status == LicenceStatus.valid || status == LicenceStatus.error)) {
      Provider.of<AuthProvider>(context, listen: false).updateApiService(apiService);
      setState(() => _panneau = _Panneau.borne);
      await _attendreMinimum();
      if (!mounted) return;
      (_sv.ouvrirBorne ?? BorneLauncher.ouvrir)(context);
      return;
    }

    if (status == LicenceStatus.error) {
      // Serveur injoignable : la licence n'est pas en cause.
      serveur.etat = EtatEtape.echec;
      licenceEtape.etat = EtatEtape.attente;
      setState(() => _panneau = _Panneau.injoignable);
      _rebours.demarrer();
      return;
    }
    serveur.etat = EtatEtape.fait;

    if (status != LicenceStatus.valid) {
      // Licence absente ou expirée : même blocage, expliqué.
      licenceEtape.etat = EtatEtape.alerte;
      setState(() => _panneau = _Panneau.licence);
      return;
    }
    licenceEtape.etat = EtatEtape.fait;

    // 5. Connexion automatique (« Rester connecté »), interdite sur un terminal partagé.
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.updateApiService(apiService);
    final partage = ConnexionReglages.courant.value.terminalPartage;
    final memorise = settings.stayConnected && settings.savedLogin.isNotEmpty && !partage;
    EtapeLancement? auto;
    if (memorise) {
      auto = EtapeLancement('Connexion automatique', etat: EtatEtape.enCours);
      setState(() => _etapes = [..._etapes, auto!]);
    }
    final isAuth = partage ? false : await authProvider.tryAutoLogin();
    if (!mounted) return;
    auto?.etat = isAuth ? EtatEtape.fait : EtatEtape.echec;
    _maj();
    await _attendreMinimum();
    if (!mounted) return;
    _remplacer(isAuth
        ? _sv.ecranAccueil()
        : ConnexionEntree(
            services: widget.services,
            message: memorise ? 'Votre mot de passe a changé, saisissez-le à nouveau.' : null,
          ));
  }

  Future<void> _configuration({required bool protege}) async {
    if (protege && !await _sv.verifierAdmin(context)) return;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _sv.ecranConfiguration()));
    // Après l'enregistrement, la Configuration relance elle-même le démarrage : on ne relance ici que
    // si cet écran est de nouveau au premier plan.
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) _demarrer();
  }

  // -------------------------------------------------------------------------
  // Affichage
  // -------------------------------------------------------------------------

  Widget _iconeEtape(EtatEtape e) => switch (e) {
        EtatEtape.fait => Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
            child: const Icon(Icons.check, size: 16, color: Colors.white)),
        EtatEtape.enCours => const SizedBox(
            width: 24, height: 24, child: Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2.6, color: Pal.amber))),
        EtatEtape.attente => Container(
            width: 24, height: 24, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: texteSurBleu.withValues(alpha: 0.6), width: 2))),
        EtatEtape.echec => Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
            child: const Icon(Icons.close, size: 16, color: Colors.white)),
        EtatEtape.alerte => const Icon(Icons.warning_amber_rounded, size: 24, color: Pal.amber),
      };

  static String _etatTexte(EtatEtape e) => switch (e) {
        EtatEtape.fait => 'terminé',
        EtatEtape.enCours => 'en cours',
        EtatEtape.attente => 'en attente',
        EtatEtape.echec => 'échec',
        EtatEtape.alerte => 'à traiter',
      };

  Widget _etape(EtapeLancement e) {
    final actif = e.etat == EtatEtape.enCours || e.etat == EtatEtape.echec || e.etat == EtatEtape.alerte;
    final titre = switch ((e.titre, e.etat)) {
      ('Connexion au serveur', EtatEtape.echec) => 'Connexion au serveur impossible',
      ('Vérification de la licence', EtatEtape.alerte) => _licence == LicenceStatus.expired ? 'Licence expirée' : 'Aucune licence',
      (_, EtatEtape.enCours) => '${e.titre}…',
      _ => e.titre,
    };
    return Semantics(
      label: '$titre, ${_etatTexte(e.etat)}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          _iconeEtape(e.etat),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titre,
                  style: TextStyle(
                      color: e.etat == EtatEtape.attente ? texteSurBleu.withValues(alpha: 0.85) : Colors.white,
                      fontSize: 15.5,
                      fontWeight: actif ? FontWeight.w700 : FontWeight.w400)),
              if (e.detail != null && e.etat == EtatEtape.enCours) Text(e.detail!, style: const TextStyle(color: texteSurBleu, fontSize: 13)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _boutonPlein(String texte, IconData icone, VoidCallback? onPressed, {Key? key}) => SizedBox(
        height: 54,
        width: double.infinity,
        child: ElevatedButton.icon(key: key, style: boutonAmbre(context), onPressed: onPressed, icon: Icon(icone), label: Text(texte)),
      );

  Widget _boutonContour(String texte, IconData icone, VoidCallback? onPressed, {Key? key}) => SizedBox(
        height: 52,
        width: double.infinity,
        child: OutlinedButton.icon(
          key: key,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: policeBouton(context, FontWeight.w700),
          ),
          onPressed: onPressed,
          icon: Icon(icone),
          label: Text(texte),
        ),
      );

  Widget _encadre({required IconData icone, required String titre, required String texte, bool clair = false, Key? key}) => Semantics(
        liveRegion: true,
        child: Container(
          key: key,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: clair ? const Color(0xFFFFF7E0) : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: clair ? const Color(0xFFF5D48A) : Colors.white.withValues(alpha: 0.18)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icone, color: clair ? const Color(0xFF9A3412) : const Color(0xFFFCA5A5)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titre, style: TextStyle(color: clair ? Pal.onAmber : Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5)),
                const SizedBox(height: 3),
                Text(texte, style: TextStyle(color: clair ? const Color(0xFF3B2A06) : texteSurBleu, fontSize: 13.5, height: 1.35)),
              ]),
            ),
          ]),
        ),
      );

  List<Widget> _panneauWidgets(SettingsProvider s) {
    switch (_panneau) {
      case _Panneau.aucun:
        return const [];
      case _Panneau.borne:
        return [
          const SizedBox(height: 8),
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.6, color: Pal.amber)),
            SizedBox(width: 12),
            Flexible(
                child: Text('Borne libre-service — ouverture de la borne…',
                    key: Key('lancement_borne'), style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600))),
          ]),
        ];
      case _Panneau.premiereUtilisation:
        return [
          _encadre(
            key: const Key('lancement_premiere'),
            icone: Icons.settings_suggest_outlined,
            titre: 'Première utilisation',
            texte: 'Cet appareil n\'est relié à aucun serveur. Indiquez l\'adresse du serveur de l\'officine pour commencer.',
          ),
          const SizedBox(height: 12),
          _boutonPlein('Configurer le serveur', Icons.dns_outlined, () => _configuration(protege: false), key: const Key('configurer_serveur')),
          const SizedBox(height: 10),
          const BoutonAssistance(couleur: Colors.white, libelle: 'Besoin d\'aide ? Appeler'),
        ];
      case _Panneau.injoignable:
        final type = s.isRemote ? 'Serveur distant' : 'Serveur local';
        // HTTPS (4.1.0) : certificat refusé / port non HTTPS ≠ serveur injoignable ≠ licence.
        final tls = switch (context.read<LicenceProvider>().issue) {
          LicenceIssue.certificate => ErreurTls.certificat,
          LicenceIssue.notHttps => ErreurTls.protocole,
          _ => null,
        };
        return [
          _encadre(
            key: Key(tls == null ? 'lancement_injoignable' : 'lancement_certificat'),
            icone: tls == null ? Icons.wifi_off : Icons.gpp_bad_outlined,
            titre: tls == null ? 'Le serveur ne répond pas' : tls.titre,
            texte: tls == null
                ? '$type · ${s.adresseAffichee(s.isRemote)}\n'
                    'Vérifiez le Wifi et que le serveur de l\'officine est allumé. La licence n\'est pas en cause.'
                : '$type · ${s.adresseAffichee(s.isRemote)}\n${tls.explication} La licence n\'est pas en cause.',
          ),
          const SizedBox(height: 12),
          _boutonPlein('Réessayer', Icons.refresh, _enCours ? null : _demarrer, key: const Key('lancement_reessayer')),
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              _rebours.reste > 0 ? 'Nouvel essai automatique dans ${_rebours.reste} s' : 'Nouvel essai…',
              key: const Key('lancement_decompte'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: texteSurBleu, fontSize: 13.5),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('lancement_configuration'),
              style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(48, 48)),
              onPressed: () => _configuration(protege: true),
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Configuration', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ];
      case _Panneau.licence:
        final lic = context.read<LicenceProvider>().licence;
        final fin = DateTime.tryParse(lic?.dateEnd ?? '');
        final expiree = _licence == LicenceStatus.expired;
        return [
          _encadre(
            key: const Key('lancement_licence'),
            clair: true,
            icone: Icons.key_outlined,
            titre: expiree ? 'Licence expirée${fin == null ? '' : ' le ${DateFormat('dd/MM/yyyy').format(fin)}'}' : 'Aucune licence enregistrée',
            texte: 'Les ventes ne sont plus possibles sur cet appareil. Contactez Prestige pour '
                '${expiree ? 'la renouveler' : 'en obtenir une'}, puis saisissez la clé de licence.',
          ),
          const SizedBox(height: 12),
          _boutonPlein('Saisir la clé de licence', Icons.vpn_key_outlined, () => _remplacer(const LicenceRegistrationScreen()),
              key: const Key('saisir_licence')),
          const SizedBox(height: 10),
          const BoutonAssistance(couleur: Colors.white, libelle: 'Appeler l\'assistance Prestige'),
          const SizedBox(height: 10),
          _boutonContour('Vérifier à nouveau', Icons.refresh, _enCours ? null : _demarrer, key: const Key('verifier_licence')),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final faits = _etapes.where((e) => e.etat == EtatEtape.fait).length;
    final progression = _etapes.isEmpty ? 0.0 : faits / _etapes.length;
    final borne = _panneau == _Panneau.borne;
    final premiere = _panneau == _Panneau.premiereUtilisation;
    return Scaffold(
      backgroundColor: Pal.navy,
      body: Container(
        decoration: fondBleuNuit,
        child: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            final tablette = c.maxWidth >= 600;
            final largeur = tablette ? 480.0 : 440.0;
            return SingleChildScrollView(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight, minWidth: c.maxWidth < largeur ? c.maxWidth : largeur, maxWidth: largeur),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const Spacer(flex: 3),
                        Center(
                          child: borne
                              ? Container(
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(color: Pal.amber, borderRadius: BorderRadius.circular(24)),
                                  child: const Icon(Icons.storefront, size: 52, color: Pal.onAmber))
                              : LogoOfficine(taille: tablette ? 112 : 92),
                        ),
                        const SizedBox(height: 18),
                        Semantics(
                          header: true,
                          child: Text(borne ? 'Borne libre-service' : 'Prestige Mobile',
                              textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: tablette ? 34 : 30, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(height: 8),
                        Center(child: NomOfficine(siVide: premiere ? 'Bienvenue !' : '')),
                        const Spacer(flex: 2),
                        if (!borne && !premiere) ...[
                          Semantics(
                            label: 'Démarrage : $faits étapes sur ${_etapes.length}',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                key: const Key('lancement_progression'),
                                value: progression,
                                minHeight: 6,
                                color: Pal.amber,
                                backgroundColor: Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (final e in _etapes) _etape(e),
                          const SizedBox(height: 10),
                        ],
                        ..._panneauWidgets(s),
                        const SizedBox(height: 14),
                        PiedConnexion(
                          couleur: texteSurBleu,
                          assistance: false,
                          extra: borne
                              ? 'Mode borne actif sur cet appareil'
                              : (_panneau == _Panneau.licence ? 'Serveur : ${s.adresseAffichee(s.isRemote)}' : 'Prestige'),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
