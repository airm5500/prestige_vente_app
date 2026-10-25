// lib/connexion/connexion_commun.dart
// Éléments communs du nouveau lancement et de la nouvelle connexion (proposition A, charte bleu / ambre) :
// services remplaçables (tests), teintes clair / sombre, logo et nom de l'officine (croix verte d'accent),
// surveillance du serveur avec réessai automatique toutes les 10 s, « Changer de serveur » sous code
// administrateur, connexion au serveur (même logique que l'écran d'origine), pied de page.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/parametres/nom_appareil_reglage.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/connexion/assistance.dart';
import 'package:prestige_vente_app/connexion/connexion_reglages.dart';
import 'package:prestige_vente_app/connexion/pin_personnel.dart';
import 'package:prestige_vente_app/interface_version.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/licence_registration_screen.dart';
import 'package:prestige_vente_app/version_app.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';

// ---------------------------------------------------------------------------
// Services remplaçables
// ---------------------------------------------------------------------------

class ConnexionServices {
  /// Code administrateur (défaut : PinCodeDialog.show, comme les rubriques à cadenas des Paramètres).
  final Future<bool> Function(BuildContext)? adminCheck;

  /// Le serveur Prestige répond-il à [ip] (port et application des réglages) ? Défaut : SettingsProvider.ping.
  final Future<bool> Function(SettingsProvider settings, String ip)? sonde;

  /// Chargements après la connexion (défaut : officine, modes de paiement ; préventes et BL du jour si l'accueil
  /// qui suit ne les lit pas lui-même — ANO-09).
  final Future<void> Function(BuildContext)? chargements;

  /// Écran d'accueil (défaut : InterfaceVersion.home()).
  final Widget Function()? accueil;

  /// Ouverture de la borne (défaut : BorneLauncher.ouvrir).
  final void Function(BuildContext)? ouvrirBorne;

  /// Page de configuration (défaut : InterfaceVersion.settings()).
  final Widget Function()? configuration;

  const ConnexionServices({this.adminCheck, this.sonde, this.chargements, this.accueil, this.ouvrirBorne, this.configuration});

  /// Services de l'appli (remplaçables dans les tests).
  static ConnexionServices instance = const ConnexionServices();

  /// Affichage minimal du nouvel écran de lancement (le logo ne « clignote » pas) — aucune attente fixe
  /// en plus : si le démarrage dure plus longtemps, l'écran suivant s'ouvre dès qu'il est prêt.
  static Duration affichageMinimum = const Duration(milliseconds: 1200);

  /// Réessai automatique quand le serveur ne répond pas.
  static Duration intervalleReessai = const Duration(seconds: 10);

  Future<bool> verifierAdmin(BuildContext context) => (adminCheck ?? PinCodeDialog.show)(context);

  Future<bool> sonder(SettingsProvider s, String ip) async {
    try {
      // Adresse avec « https:// » éventuel ; port effectif de cette adresse (4.1.0).
      return await (sonde ?? (s, ip) => s.ping(ip, s.portPour(ip), s.appName))(s, ip);
    } catch (_) {
      return false;
    }
  }

  /// Adresse utilisée actuellement.
  static String ipCourante(SettingsProvider s) => s.isRemote ? s.remoteIp : s.localIp;

  Future<bool> sonderCourant(SettingsProvider s) => sonder(s, ipCourante(s));

  Widget ecranAccueil() => (accueil ?? InterfaceVersion.home)();

  /// ANO-09 (4.3.0) : l'écran ouvert après la connexion est le nouvel accueil (AccueilScreen), qui lit lui-même
  /// les préventes et les BL du jour dès son ouverture : la connexion ne les lit donc pas une 1re fois. Accueil
  /// d'origine ou accueil remplacé (tests) : chargements inchangés.
  bool get accueilLitLesTaches => accueil == null && InterfaceVersion.useNew.value;

  Widget ecranConfiguration() => (configuration ?? InterfaceVersion.settings)();
}

// ---------------------------------------------------------------------------
// Teintes (clair / sombre)
// ---------------------------------------------------------------------------

class Teintes {
  final Color fond, texte, attenue, champ, bordure, erreur, erreurFond;
  const Teintes._(this.fond, this.texte, this.attenue, this.champ, this.bordure, this.erreur, this.erreurFond);

  static const clair = Teintes._(Colors.white, Pal.ink, Pal.muted, Colors.white, Color(0xFFC5D0DE), Color(0xFFB91C1C), Color(0xFFFDECEC));
  static const sombre =
      Teintes._(Color(0xFF0E1726), Color(0xFFE8EEF7), Color(0xFFA9B6C9), Color(0xFF17233A), Color(0xFF3A4C68), Color(0xFFFCA5A5), Color(0xFF3B1218));

  static Teintes of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? sombre : clair;
}

/// Police des boutons : celle du thème (les styles de boutons partagés n'en précisent pas).
TextStyle policeBouton(BuildContext context, FontWeight poids, [double taille = 15]) =>
    (Theme.of(context).textTheme.labelLarge ?? const TextStyle()).copyWith(fontWeight: poids, fontSize: taille);

/// Bouton ambre (action principale) avec la police du thème.
ButtonStyle boutonAmbre(BuildContext context) => amberButton.copyWith(textStyle: WidgetStatePropertyAll(policeBouton(context, FontWeight.bold)));

/// Fond bleu nuit Prestige (lancement, en-tête, colonne gauche tablette).
const fondBleuNuit = BoxDecoration(
  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0B4A7F), Pal.navy, Color(0xFF00264D)]),
);

/// Texte clair sur bleu nuit (≈ 9 : 1 sur #003366).
const texteSurBleu = Color(0xFFC9D6E8);

// ---------------------------------------------------------------------------
// Identité : logo, nom de l'officine, croix verte
// ---------------------------------------------------------------------------

/// Logo : aucune route du serveur ne fournit de logo d'officine → logo de l'application.
class LogoOfficine extends StatelessWidget {
  final double taille;
  const LogoOfficine({super.key, this.taille = 84});

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: 'Logo Prestige Mobile',
        child: Container(
          width: taille,
          height: taille,
          padding: EdgeInsets.all(taille * 0.12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(taille * 0.24),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Image.asset(
            'assets/icon/icon.png',
            fit: BoxFit.contain,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => Icon(Icons.shopping_cart_checkout, color: Pal.navy, size: taille * 0.6),
          ),
        ),
      );
}

/// Petite croix verte de pharmacie (accent visuel, décoratif).
class CroixVerte extends StatelessWidget {
  final double taille;
  const CroixVerte({super.key, this.taille = 14});

  @override
  Widget build(BuildContext context) {
    final b = taille / 3;
    return ExcludeSemantics(
      child: SizedBox(
        key: const Key('croix_verte'),
        width: taille,
        height: taille,
        child: Stack(alignment: Alignment.center, children: [
          Container(width: b, height: taille, decoration: BoxDecoration(color: Pal.green, borderRadius: BorderRadius.circular(1.5))),
          Container(width: taille, height: b, decoration: BoxDecoration(color: Pal.green, borderRadius: BorderRadius.circular(1.5))),
        ]),
      ),
    );
  }
}

/// Nom de l'officine gardé sur l'appareil, précédé de la croix verte (rien si jamais connecté).
class NomOfficine extends StatelessWidget {
  final double taille;
  final TextAlign align;
  final Color couleur;
  final String siVide;
  const NomOfficine({super.key, this.taille = 16, this.align = TextAlign.center, this.couleur = texteSurBleu, this.siVide = ''});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: ConnexionReglages.officine,
        builder: (context, nom, _) {
          final t = nom.isEmpty ? siVide : nom;
          if (t.isEmpty) return const SizedBox.shrink();
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (nom.isNotEmpty) ...[CroixVerte(taille: taille * 0.8), SizedBox(width: taille * 0.45)],
              Flexible(
                child: Text(t,
                    key: const Key('nom_officine'),
                    textAlign: align,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: couleur, fontSize: taille)),
              ),
            ],
          );
        },
      );
}

/// Rôle affiché pour un utilisateur (champ du serveur s'il existe, sinon déduit du compte).
String roleDe(User? u, String login) {
  final r = u?.role.trim() ?? '';
  if (r.isNotEmpty) return r;
  return login.trim().toLowerCase() == 'admin' ? 'Administrateur' : 'Utilisateur';
}

// ---------------------------------------------------------------------------
// Compte à rebours / surveillance du serveur
// ---------------------------------------------------------------------------

/// Compte à rebours (1 s) qui appelle [action] à zéro. Arrêté par [arreter] / [dispose].
class CompteARebours extends ChangeNotifier {
  final Duration duree;
  final FutureOr<void> Function() action;
  Timer? _t;
  int reste = 0;
  bool _fini = false;

  CompteARebours({required this.duree, required this.action});

  bool get actif => _t?.isActive ?? false;

  void demarrer() {
    _t?.cancel();
    reste = duree.inSeconds;
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      reste--;
      if (reste <= 0) {
        t.cancel();
        if (!_fini) action();
      }
      if (!_fini) notifyListeners();
    });
    notifyListeners();
  }

  void arreter() {
    _t?.cancel();
    reste = 0;
  }

  @override
  void dispose() {
    _fini = true;
    _t?.cancel();
    super.dispose();
  }
}

enum EtatServeur { test, connecte, injoignable }

/// État du serveur affiché sur l'écran de connexion : test au démarrage, réessai automatique toutes les
/// 10 s tant qu'il ne répond pas.
class ControleServeur extends ChangeNotifier {
  final Future<bool> Function() sonde;
  EtatServeur etat = EtatServeur.test;
  late final CompteARebours rebours = CompteARebours(duree: ConnexionServices.intervalleReessai, action: verifier)..addListener(_relayer);
  Future<void>? _enCours;
  bool _fini = false;

  /// 4.3.3 : panne constatée par la sonde (null : non précisée → injoignable).
  final PanneServeur? Function()? panneSonde;

  /// Panne affichée quand [etat] est injoignable : aucune réponse ≠ Prestige en démarrage / redéploiement.
  PanneServeur panne = PanneServeur.injoignable;

  ControleServeur(this.sonde, {this.panneSonde});

  void _relayer() {
    if (!_fini) notifyListeners();
  }

  Future<void> verifier() => _enCours ??= _verifier().whenComplete(() => _enCours = null);

  Future<void> _verifier() async {
    rebours.arreter();
    etat = EtatServeur.test;
    _relayer();
    bool ok;
    try {
      ok = await sonde();
    } catch (_) {
      ok = false;
    }
    if (_fini) return;
    if (!ok) panne = panneSonde?.call() ?? PanneServeur.injoignable;
    etat = ok ? EtatServeur.connecte : EtatServeur.injoignable;
    if (!ok) rebours.demarrer();
    _relayer();
  }

  /// Après une tentative de connexion : le serveur ne répond pas.
  void signalerInjoignable([PanneServeur? constatee]) {
    if (_fini) return;
    panne = constatee ?? panne;
    etat = EtatServeur.injoignable;
    if (!rebours.actif) rebours.demarrer();
    _relayer();
  }

  @override
  void dispose() {
    _fini = true;
    rebours.dispose();
    super.dispose();
  }
}

/// Bandeau d'état du serveur (point + texte, jamais la couleur seule) et bouton « Changer » (code admin).
class IndicateurServeur extends StatelessWidget {
  final ControleServeur controle;
  final VoidCallback? onChanger;
  const IndicateurServeur({super.key, required this.controle, this.onChanger});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    return ListenableBuilder(
      listenable: controle,
      builder: (context, _) {
        final type = s.isRemote ? 'distant' : 'local';
        final adresse = '${s.adresseAffichee(s.isRemote)} · ${s.appName}';
        final (couleur, titre, detail) = switch (controle.etat) {
          EtatServeur.test => (Pal.amber, 'Test du serveur $type…', adresse),
          EtatServeur.connecte => (const Color(0xFF22C55E), 'Serveur $type connecté', adresse),
          EtatServeur.injoignable => (
              const Color(0xFFEF4444),
              // HTTPS (4.1.0) : certificat refusé ≠ serveur injoignable.
              s.pingTls?.titre ?? MessagesServeur.titre(controle.panne),
              controle.rebours.reste > 0 ? 'Nouvel essai dans ${controle.rebours.reste} s' : adresse
            ),
        };
        return Container(
          key: const Key('indicateur_serveur'),
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                label: '$titre. $detail',
                excludeSemantics: true,
                child: Row(children: [
                  Container(width: 11, height: 11, decoration: BoxDecoration(color: couleur, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(titre,
                          key: const Key('etat_serveur'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                      Text(detail,
                          key: const Key('detail_serveur'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: texteSurBleu, fontSize: 12.5)),
                    ]),
                  ),
                ]),
              ),
            ),
            if (onChanger != null)
              Semantics(
                button: true,
                label: 'Changer de serveur, code administrateur demandé',
                excludeSemantics: true,
                child: TextButton.icon(
                  key: const Key('changer_serveur'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    minimumSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: policeBouton(context, FontWeight.w700, 14),
                  ),
                  onPressed: onChanger,
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: const Text('Changer'),
                ),
              ),
          ]),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Changer de serveur (code administrateur)
// ---------------------------------------------------------------------------

/// Demande le code administrateur, puis propose les adresses enregistrées avec leur état et l'accès à
/// la Configuration complète. [apres] est appelé si l'adresse a pu changer.
Future<void> changerServeur(BuildContext context, {ConnexionServices? services, required VoidCallback apres}) async {
  final sv = services ?? ConnexionServices.instance;
  if (!await sv.verifierAdmin(context) || !context.mounted) return;
  final choix = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ChoixServeur(services: sv),
  );
  if (!context.mounted) return;
  if (choix == 'configuration') {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => sv.ecranConfiguration()));
  }
  if (choix != null) apres();
}

class _ChoixServeur extends StatefulWidget {
  final ConnexionServices services;
  const _ChoixServeur({required this.services});

  @override
  State<_ChoixServeur> createState() => _ChoixServeurState();
}

class _ChoixServeurState extends State<_ChoixServeur> {
  final Map<bool, bool?> _etat = {}; // distant ? → répond (null = test)
  bool _occupe = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>();
    _tester(false, s.localIp);
    if (s.remoteIp.isNotEmpty) _tester(true, s.remoteIp);
  }

  Future<void> _tester(bool distant, String ip) async {
    final s = context.read<SettingsProvider>();
    final ok = await widget.services.sonder(s, ip);
    if (mounted) setState(() => _etat[distant] = ok);
  }

  Future<void> _choisir(bool distant) async {
    if (_occupe) return;
    _occupe = true;
    await context.read<SettingsProvider>().setConnectionMode(distant);
    if (mounted) Navigator.of(context).pop('serveur');
  }

  Widget _ligne(bool distant, String ip, SettingsProvider s) {
    final t = Teintes.of(context);
    final r = _etat[distant];
    final utilise = s.isRemote == distant;
    final etat = r == null ? 'Test…' : (r ? 'Répond' : 'Injoignable');
    return Semantics(
      button: true,
      selected: utilise,
      label: 'Serveur ${distant ? 'distant' : 'local'}, $ip, $etat${utilise ? ', utilisé' : ''}',
      excludeSemantics: true,
      child: Material(
        color: utilise ? const Color(0xFFE3ECF7) : t.champ,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: Key('serveur_${distant ? 'distant' : 'local'}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => _choisir(distant),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(children: [
                Icon(distant ? Icons.public : Icons.lan_outlined, color: utilise ? Pal.navy : t.texte),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Serveur ${distant ? 'distant' : 'local'}${utilise ? ' · utilisé' : ''}',
                        style: TextStyle(fontWeight: FontWeight.w700, color: utilise ? Pal.ink : t.texte)),
                    Text('${s.adresseAffichee(distant)} · ${s.appName}', style: TextStyle(fontSize: 12.5, color: utilise ? Pal.muted : t.attenue)),
                  ]),
                ),
                Icon(r == null ? Icons.hourglass_empty : (r ? Icons.check_circle : Icons.cancel),
                    size: 18, color: r == null ? Pal.muted : (r ? Pal.green : const Color(0xFFDC2626))),
                const SizedBox(width: 4),
                Text(etat, style: TextStyle(fontSize: 12.5, color: utilise ? Pal.ink : t.texte)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final t = Teintes.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Changer de serveur', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: t.texte)),
          const SizedBox(height: 4),
          Text('Choisissez l\'adresse utilisée par cet appareil.', style: TextStyle(color: t.attenue)),
          const SizedBox(height: 12),
          _ligne(false, s.localIp, s),
          if (s.remoteIp.isNotEmpty) ...[const SizedBox(height: 8), _ligne(true, s.remoteIp, s)],
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              key: const Key('configuration_complete'),
              style: outlineButton.copyWith(textStyle: WidgetStatePropertyAll(policeBouton(context, FontWeight.w600))),
              onPressed: () => Navigator.of(context).pop('configuration'),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Configuration complète'),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connexion au serveur (même logique que l'écran d'origine)
// ---------------------------------------------------------------------------

enum IssueConnexion { reussie, identifiants, serveur, licence, erreur }

enum EtapeConnexion { identifiants, licence, chargements }

class ConnexionFlux {
  ConnexionFlux._();

  /// Connexion : identifiants vérifiés par le serveur, licence revérifiée (absente / expirée → écran
  /// « Clé de licence »), identifiants mémorisés si « Rester connecté » (stockage sécurisé), puis
  /// chargements (officine, préventes, BL du jour, modes de paiement). Ne navigue pas vers l'accueil.
  static Future<IssueConnexion> connecter(
    BuildContext context, {
    required String login,
    required String motDePasse,
    required bool resterConnecte,
    ValueChanged<EtapeConnexion>? etape,
    ConnexionServices? services,
  }) async {
    final sv = services ?? ConnexionServices.instance;
    final auth = context.read<AuthProvider>();
    final settings = context.read<SettingsProvider>();
    final licence = context.read<LicenceProvider>();
    try {
      final ok = await auth.login(login, motDePasse);
      if (!ok) {
        // 4.3.3 : serveur injoignable / Prestige indisponible (démarrage, redéploiement) → message du serveur, jamais
        // « mot de passe incorrect ». Sinon : le serveur a-t-il répondu (identifiants refusés) ?
        if (auth.dernierEchecServeur) return IssueConnexion.serveur;
        return await sv.sonderCourant(settings) ? IssueConnexion.identifiants : IssueConnexion.serveur;
      }
      etape?.call(EtapeConnexion.identifiants);
      if (await licence.mustBlockAccess()) {
        // Demande 11 (option A) : un administrateur garde sa session pour activer la licence ; sinon déconnexion.
        if (context.mounted) await ouvrirActivationLicence(context);
        return IssueConnexion.licence;
      }
      etape?.call(EtapeConnexion.licence);
      final rester = resterConnecte && ConnexionReglages.courant.value.resterConnecteAutorise;
      await settings.saveCredentials(login, motDePasse, rester);
      await PinPersonnel.instance.apresConnexionMotDePasse(login, motDePasse);
      final sorti = await DerniersUtilisateurs.noter(login: login, nom: auth.user?.fullName.trim() ?? '', role: roleDe(auth.user, login));
      if (sorti != null) await PinPersonnel.instance.effacer(sorti);
      if (!context.mounted) return IssueConnexion.erreur;
      etape?.call(EtapeConnexion.chargements);
      await (sv.chargements ?? (c) => _chargements(c, accueilLitLesTaches: sv.accueilLitLesTaches))(context);
      await ConnexionReglages.memoriserOfficine(auth.officine?.nomComplet ?? '');
      return IssueConnexion.reussie;
    } catch (e) {
      // Détail technique dans le journal de la console seulement, jamais à l'écran.
      debugPrint('Connexion : erreur ${e.runtimeType}');
      return IssueConnexion.erreur;
    }
  }

  /// [accueilLitLesTaches] (ANO-09) : préventes et BL du jour lus par le nouvel accueil à son ouverture, pas ici.
  /// L'officine est toujours lue (nom mémorisé juste après) et marquée pour l'accueil qui suit (pas de 2e lecture).
  /// Modes de paiement avec QR : toujours lus (cache de la session, utilisé ensuite sans réseau).
  static Future<void> _chargements(BuildContext context, {bool accueilLitLesTaches = false}) async {
    final auth = context.read<AuthProvider>();
    final sale = context.read<SaleProvider>();
    final bl = context.read<BlControlProvider>();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await Future.wait([
      auth.loadOfficineInfo().then((_) => auth.marquerOfficineDeLaConnexion()),
      if (!accueilLitLesTaches) sale.fetchPreventes(),
      if (!accueilLitLesTaches) bl.fetchBonsLivraison(dtStart: today, dtEnd: today, query: ''),
      sale.fetchPaymentMethodsWithQr(),
    ]);
  }

  /// Ouvre l'accueil (pile vidée).
  /// 4.7.0 : à la première connexion, propose de nommer l'appareil (X-Poste) si ce n'est jamais fait ; non bloquant.
  static void allerAccueil(BuildContext context, {ConnexionServices? services}) {
    final sv = services ?? ConnexionServices.instance;
    final nav = Navigator.of(context);
    nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => sv.ecranAccueil()), (_) => false);
    if (!NomAppareil.instance.dejaPropose) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (nav.mounted) proposerNomAppareil(nav.context);
      });
    }
  }

  /// Message affiché (jamais d'exception technique).
  static String message(IssueConnexion i, {PanneServeur panne = PanneServeur.injoignable}) => switch (i) {
        IssueConnexion.identifiants => 'Identifiant ou mot de passe incorrect. Vérifiez les majuscules et réessayez.',
        IssueConnexion.serveur => '${MessagesServeur.message(panne)} Vos identifiants ne sont pas en cause.',
        IssueConnexion.erreur => 'La connexion n\'a pas abouti. Réessayez ; si le problème continue, appelez l\'assistance.',
        IssueConnexion.licence || IssueConnexion.reussie => '',
      };
}

// ---------------------------------------------------------------------------
// Messages et pied de page
// ---------------------------------------------------------------------------

/// Message d'erreur : icône + texte (pas seulement la couleur).
class MessageErreur extends StatelessWidget {
  final String texte;
  final IconData icone;
  const MessageErreur(this.texte, {super.key, this.icone = Icons.error_outline});

  @override
  Widget build(BuildContext context) {
    final t = Teintes.of(context);
    return Semantics(
      liveRegion: true,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icone, size: 18, color: t.erreur),
        const SizedBox(width: 6),
        Expanded(child: Text(texte, key: const Key('message_erreur'), style: TextStyle(color: t.erreur, fontWeight: FontWeight.w600, fontSize: 13.5))),
      ]),
    );
  }
}

/// Encadré « Le serveur ne répond pas » avec Réessayer (réessai automatique en cours).
class EncadreServeurInjoignable extends StatelessWidget {
  final ControleServeur controle;
  const EncadreServeurInjoignable({super.key, required this.controle});

  @override
  Widget build(BuildContext context) {
    final t = Teintes.of(context);
    return ListenableBuilder(
      listenable: controle,
      builder: (context, _) {
        // HTTPS (4.1.0) : échec TLS du dernier test du serveur (certificat refusé, port non HTTPS).
        final tls = context.read<SettingsProvider?>()?.pingTls;
        final p = controle.panne;
        return Container(
        key: const Key('encadre_injoignable'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: t.erreurFond, borderRadius: BorderRadius.circular(14), border: Border.all(color: t.erreur.withValues(alpha: 0.35))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(p == PanneServeur.indisponible && tls == null ? Icons.hourglass_top : Icons.wifi_off, color: t.erreur),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tls?.titre ?? MessagesServeur.titre(p),
                    key: const Key('encadre_injoignable_titre'), style: TextStyle(color: t.erreur, fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                    '${tls != null ? tls.explication : MessagesServeur.detail(p)} Vos identifiants ne sont pas en cause.'
                    '${controle.rebours.reste > 0 ? '\nNouvel essai automatique dans ${controle.rebours.reste} s.' : ''}',
                    style: TextStyle(color: t.texte, fontSize: 13.5)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              key: const Key('reessayer_serveur'),
              style: boutonAmbre(context),
              onPressed: controle.etat == EtatServeur.test ? null : controle.verifier,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ),
        ]),
      );
      },
    );
  }
}

/// « Version 4.0.0+8 · Assistance : 07 08 08 00 68 » (version lue à l'exécution, voir [VersionApp]).
class PiedConnexion extends StatelessWidget {
  final Color couleur;
  final bool assistance;
  final String? extra;
  const PiedConnexion({super.key, required this.couleur, this.assistance = true, this.extra});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ConnexionConfig>(
        valueListenable: ConnexionReglages.courant,
        builder: (context, c, _) => KeyedSubtree(
          key: const Key('pied_connexion'),
          child: VersionAffichee(
            couleur: couleur,
            taille: 12.5,
            format: (version) => [
              version,
              if (extra != null) extra!,
              if (assistance) 'Assistance : ${Assistance.formater(c.assistance)}',
            ].join(' · '),
          ),
        ),
      );
}
