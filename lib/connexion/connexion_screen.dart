// lib/connexion/connexion_screen.dart
// Nouvel écran de connexion (proposition A) — nouvelle interface seulement (InterfaceVersion) ;
// l'écran d'origine (AncienLoginScreen) reste inchangé derrière l'interrupteur.
//
// - En-tête bleu : logo, « Prestige Mobile », nom de l'officine gardé sur l'appareil (croix verte),
//   état du serveur (point + texte) avec réessai automatique toutes les 10 s, « Changer » sous code admin.
// - Formulaire : identifiant pré-rempli (dernier utilisateur), curseur dans le mot de passe, œil 48 px,
//   « Rester connecté — sur cet appareil uniquement » (masqué si « Terminal partagé »), bouton ambre 54 px,
//   anti double appui, chargements réels listés, erreurs compréhensibles (icône + texte).
// - Tablette (≥ 900 px) : deux colonnes (identité + serveur à gauche, formulaire à droite, 440 px max).
// - Pas de « Continuer hors ligne » (décision client).
// - Option C : après une connexion par mot de passe, création facultative d'un code PIN personnel.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/connexion/assistance.dart';
import 'package:prestige_vente_app/connexion/connexion_commun.dart';
import 'package:prestige_vente_app/connexion/connexion_reglages.dart';
import 'package:prestige_vente_app/connexion/pin_personnel.dart';
import 'package:prestige_vente_app/connexion/qui_etes_vous_screen.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';

/// Entrée de la connexion : « Qui êtes-vous ? » si la connexion rapide est activée et qu'au moins un
/// utilisateur s'est déjà connecté sur l'appareil ; sinon l'écran de connexion classique.
class ConnexionEntree extends StatefulWidget {
  final ConnexionServices? services;
  final String? message;
  const ConnexionEntree({super.key, this.services, this.message});

  @override
  State<ConnexionEntree> createState() => _ConnexionEntreeState();
}

class _ConnexionEntreeState extends State<ConnexionEntree> {
  List<DernierUtilisateur>? _derniers;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final l = ConnexionReglages.courant.value.connexionRapide ? await DerniersUtilisateurs.lire() : const <DernierUtilisateur>[];
    if (mounted) setState(() => _derniers = l);
  }

  @override
  Widget build(BuildContext context) {
    final l = _derniers;
    if (l == null) return const Scaffold(backgroundColor: Pal.navy, body: SizedBox.expand());
    if (l.isNotEmpty) return QuiEtesVousScreen(services: widget.services, message: widget.message);
    return ConnexionScreen(services: widget.services, message: widget.message);
  }
}

class ConnexionScreen extends StatefulWidget {
  final ConnexionServices? services;

  /// Information affichée au-dessus du formulaire (ex. « Votre mot de passe a changé… »).
  final String? message;

  /// Identifiant imposé (ex. utilisateur choisi dans « Qui êtes-vous ? »).
  final String? login;

  const ConnexionScreen({super.key, this.services, this.message, this.login});

  @override
  State<ConnexionScreen> createState() => _ConnexionScreenState();
}

class _ConnexionScreenState extends State<ConnexionScreen> {
  ConnexionServices get _sv => widget.services ?? ConnexionServices.instance;
  final _form = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _mdp = TextEditingController();
  final _focusLogin = FocusNode();
  final _focusMdp = FocusNode();
  late final SettingsProvider _settings = context.read<SettingsProvider>();
  late final ControleServeur _serveur = ControleServeur(() => _sv.sonderCourant(_settings), panneSonde: () => _settings.pingPanne);

  bool _voir = false;
  bool _rester = false;
  bool _occupe = false;
  IssueConnexion? _erreur;
  final Set<EtapeConnexion> _etapes = {};

  @override
  void initState() {
    super.initState();
    _rester = _settings.stayConnected;
    _serveur.verifier();
    _preremplir();
  }

  Future<void> _preremplir() async {
    var login = widget.login ?? '';
    if (login.isEmpty) {
      final derniers = await DerniersUtilisateurs.lire();
      login = derniers.isNotEmpty ? derniers.first.login : _settings.savedLogin;
    }
    if (!mounted) return;
    if (_login.text.isEmpty) _login.text = login;
    // Curseur directement dans le mot de passe quand l'identifiant est connu.
    (_login.text.isEmpty ? _focusLogin : _focusMdp).requestFocus();
  }

  @override
  void dispose() {
    _serveur.dispose();
    _login.dispose();
    _mdp.dispose();
    _focusLogin.dispose();
    _focusMdp.dispose();
    super.dispose();
  }

  Future<void> _changerServeur() => changerServeur(context, services: _sv, apres: _serveur.verifier);

  Future<void> _connecter() async {
    if (_occupe) return; // anti double appui
    setState(() => _erreur = null);
    if (!(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final login = _login.text.trim();
    final mdp = _mdp.text;
    setState(() {
      _occupe = true;
      _etapes.clear();
    });
    final issue = await ConnexionFlux.connecter(
      context,
      login: login,
      motDePasse: mdp,
      resterConnecte: _rester,
      services: _sv,
      etape: (e) {
        if (mounted) setState(() => _etapes.add(e));
      },
    );
    if (!mounted) return;
    switch (issue) {
      case IssueConnexion.reussie:
        await proposerPinPersonnel(context, login: login, motDePasse: mdp);
        if (mounted) ConnexionFlux.allerAccueil(context, services: _sv);
        return;
      case IssueConnexion.licence:
        return; // écran « Clé de licence » ouvert
      case IssueConnexion.identifiants:
        _mdp.clear();
        _focusMdp.requestFocus();
      case IssueConnexion.serveur:
        // 4.3.3 : panne constatée par la connexion (injoignable ≠ Prestige indisponible), sinon par la sonde.
        _serveur.signalerInjoignable(context.read<AuthProvider>().dernierePanne ?? _settings.pingPanne);
      case IssueConnexion.erreur:
        break;
    }
    setState(() {
      _occupe = false;
      _erreur = issue;
    });
  }

  InputDecoration _deco(Teintes t, {required IconData icone, Widget? suffixe, bool erreur = false}) => InputDecoration(
        prefixIcon: Icon(icone, color: erreur ? t.erreur : t.attenue),
        suffixIcon: suffixe,
        filled: true,
        fillColor: _occupe ? t.champ.withValues(alpha: 0.6) : t.champ,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.bordure)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: erreur ? t.erreur : t.bordure)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: erreur ? t.erreur : (t == Teintes.sombre ? texteSurBleu : Pal.navy), width: 2)),
        errorStyle: TextStyle(color: t.erreur),
      );

  Widget _libelle(String texte, Teintes t, {bool erreur = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4),
        child: Text(texte, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: erreur ? t.erreur : t.attenue)),
      );

  Widget _etapeLigne(String texte, bool fait, Teintes t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Semantics(
          label: '$texte, ${fait ? 'terminé' : 'en cours'}',
          excludeSemantics: true,
          child: Row(children: [
            fait
                ? const Icon(Icons.check, size: 18, color: Pal.green)
                : const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Pal.amber)),
            const SizedBox(width: 8),
            Expanded(child: Text(texte, style: TextStyle(fontSize: 13.5, color: t.texte, fontWeight: fait ? FontWeight.w400 : FontWeight.w700))),
          ]),
        ),
      );

  Widget _formulaire(Teintes t, ConnexionConfig cfg) {
    final erreurMdp = _erreur == IssueConnexion.identifiants;
    final infoTexte = widget.message;
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(header: true, child: Text('Connexion', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: t.texte))),
        const SizedBox(height: 2),
        Text('Saisissez vos identifiants Prestige.', style: TextStyle(fontSize: 14.5, color: t.attenue)),
        if (infoTexte != null) ...[
          const SizedBox(height: 12),
          Container(
            key: const Key('connexion_info'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF7E0), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.info_outline, color: Color(0xFF9A3412)),
              const SizedBox(width: 8),
              Expanded(child: Text(infoTexte, style: const TextStyle(color: Color(0xFF3B2A06), fontSize: 13.5))),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        _libelle('Identifiant', t),
        TextFormField(
          key: const Key('connexion_login'),
          controller: _login,
          focusNode: _focusLogin,
          enabled: !_occupe && widget.login == null,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          inputFormatters: [LengthLimitingTextInputFormatter(60)],
          style: TextStyle(fontSize: 16, color: t.texte),
          decoration: _deco(t, icone: Icons.person_outline),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Saisissez votre identifiant' : null,
          onFieldSubmitted: (_) => _focusMdp.requestFocus(),
        ),
        const SizedBox(height: 10),
        _libelle('Mot de passe', t, erreur: erreurMdp),
        TextFormField(
          key: const Key('connexion_mdp'),
          controller: _mdp,
          focusNode: _focusMdp,
          enabled: !_occupe,
          obscureText: !_voir,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          inputFormatters: [LengthLimitingTextInputFormatter(128)],
          style: TextStyle(fontSize: 16, color: t.texte),
          decoration: _deco(
            t,
            icone: Icons.lock_outline,
            erreur: erreurMdp,
            suffixe: IconButton(
              key: const Key('voir_mdp'),
              tooltip: _voir ? 'Masquer le mot de passe' : 'Afficher le mot de passe',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(_voir ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: t.attenue),
              onPressed: () => setState(() => _voir = !_voir),
            ),
          ),
          validator: (v) => (v ?? '').isEmpty ? 'Saisissez votre mot de passe' : null,
          onFieldSubmitted: (_) => _connecter(),
        ),
        if (erreurMdp) ...[
          const SizedBox(height: 8),
          MessageErreur(ConnexionFlux.message(IssueConnexion.identifiants), icone: Icons.warning_amber_rounded),
        ],
        const SizedBox(height: 6),
        if (cfg.resterConnecteAutorise)
          MergeSemantics(
            child: InkWell(
              key: const Key('rester_connecte'),
              borderRadius: BorderRadius.circular(10),
              onTap: _occupe ? null : () => setState(() => _rester = !_rester),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Row(children: [
                  Checkbox(value: _rester, activeColor: Pal.navy, onChanged: _occupe ? null : (v) => setState(() => _rester = v ?? false)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text('Rester connecté', style: TextStyle(fontSize: 15, color: t.texte)),
                      Text('Sur cet appareil uniquement', style: TextStyle(fontSize: 12.5, color: t.attenue)),
                    ]),
                  ),
                ]),
              ),
            ),
          )
        else
          Padding(
            key: const Key('terminal_partage_info'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Icon(Icons.devices_other, size: 18, color: t.attenue),
              const SizedBox(width: 8),
              Expanded(child: Text('Terminal partagé : reconnectez-vous à chaque ouverture.', style: TextStyle(fontSize: 12.5, color: t.attenue))),
            ]),
          ),
        const SizedBox(height: 10),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            key: const Key('se_connecter'),
            style: boutonAmbre(context).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? Pal.amber.withValues(alpha: 0.75) : Pal.amber),
              foregroundColor: const WidgetStatePropertyAll(Pal.onAmber),
            ),
            onPressed: _occupe ? null : _connecter,
            child: _occupe
                ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Pal.onAmber)),
                    SizedBox(width: 12),
                    Flexible(child: Text('Connexion en cours…', overflow: TextOverflow.ellipsis)),
                  ])
                : const Text('Se connecter', style: TextStyle(fontSize: 16.5)),
          ),
        ),
        if (_occupe) ...[
          const SizedBox(height: 10),
          _etapeLigne('Identifiants vérifiés', _etapes.contains(EtapeConnexion.identifiants), t),
          if (_etapes.contains(EtapeConnexion.identifiants)) _etapeLigne('Licence vérifiée', _etapes.contains(EtapeConnexion.licence), t),
          if (_etapes.contains(EtapeConnexion.chargements)) _etapeLigne('Préventes, BL du jour et modes de paiement…', false, t),
        ],
        if (_erreur == IssueConnexion.erreur) ...[
          const SizedBox(height: 10),
          MessageErreur(ConnexionFlux.message(IssueConnexion.erreur)),
        ],
        ListenableBuilder(
          listenable: _serveur,
          builder: (context, _) => _serveur.etat == EtatServeur.injoignable && !_occupe
              ? Padding(padding: const EdgeInsets.only(top: 14), child: EncadreServeurInjoignable(controle: _serveur))
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  Widget _identite({required bool grande}) => Row(children: [
        LogoOfficine(taille: grande ? 72 : 52),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Prestige Mobile',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: grande ? 30 : 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            NomOfficine(taille: grande ? 18 : 14, align: TextAlign.start),
          ]),
        ),
      ]);

  Widget _pied(Color couleur) => Column(mainAxisSize: MainAxisSize.min, children: [
        PiedConnexion(couleur: couleur),
        TextButton.icon(
          key: const Key('appeler_assistance'),
          style: TextButton.styleFrom(foregroundColor: couleur, minimumSize: const Size(48, 48)),
          onPressed: () => Assistance.appeler(context),
          icon: const Icon(Icons.call_outlined, size: 18),
          label: const Text('Appeler l\'assistance', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final t = Teintes.of(context);
    final canPop = Navigator.of(context).canPop();
    final retour = canPop
        ? IconButton(
            tooltip: 'Retour',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          )
        : null;
    return ValueListenableBuilder<ConnexionConfig>(
      valueListenable: ConnexionReglages.courant,
      builder: (context, cfg, _) {
        final tablette = Responsive.isExpanded(context);
        if (tablette) {
          return Scaffold(
            backgroundColor: t.fond,
            body: Row(children: [
              Expanded(
                child: Container(
                  decoration: fondBleuNuit,
                  child: SafeArea(
                    right: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(48, 16, 48, 16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (retour != null) retour,
                        const Spacer(),
                        _identite(grande: true),
                        const SizedBox(height: 28),
                        IndicateurServeur(controle: _serveur, onChanger: _changerServeur),
                        const Spacer(),
                        Align(alignment: Alignment.centerLeft, child: _pied(texteSurBleu)),
                      ]),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SafeArea(
                  left: false,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: _formulaire(t, cfg)),
                    ),
                  ),
                ),
              ),
            ]),
          );
        }
        return Scaffold(
          backgroundColor: t.fond,
          body: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle.light,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Pal.navy,
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Row(children: [if (retour != null) retour, Expanded(child: _identite(grande: false))]),
                            const SizedBox(height: 14),
                            IndicateurServeur(controle: _serveur, onChanger: _changerServeur),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8), child: _formulaire(t, cfg)),
                ),
              ),
              SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: _pied(t.attenue))),
            ]),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Code PIN personnel : proposition après une connexion par mot de passe
// ---------------------------------------------------------------------------

/// Propose (facultatif) de créer un code PIN personnel si la connexion rapide est activée, que
/// l'utilisateur n'a pas de PIN sur cet appareil et n'a pas refusé définitivement.
Future<void> proposerPinPersonnel(BuildContext context, {required String login, required String motDePasse}) async {
  if (!ConnexionReglages.courant.value.connexionRapide) return;
  if (await PinPersonnel.instance.actif(login)) return;
  final n = DerniersUtilisateurs.normaliser(login);
  final u = (await DerniersUtilisateurs.lire()).where((e) => DerniersUtilisateurs.normaliser(e.login) == n).firstOrNull;
  if (u == null || u.pinRefuse || !context.mounted) return;
  await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CreationPinDialog(login: login, motDePasse: motDePasse),
  );
}

class CreationPinDialog extends StatefulWidget {
  final String login;
  final String motDePasse;
  const CreationPinDialog({super.key, required this.login, required this.motDePasse});

  @override
  State<CreationPinDialog> createState() => _CreationPinDialogState();
}

class _CreationPinDialogState extends State<CreationPinDialog> {
  final _pin = TextEditingController();
  final _confirmation = TextEditingController();
  String? _erreur;
  bool _occupe = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (_occupe) return;
    final motif = PinPersonnel.refus(_pin.text);
    if (motif != null) return setState(() => _erreur = motif);
    if (_pin.text != _confirmation.text) return setState(() => _erreur = 'Les deux codes sont différents.');
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    final r = await PinPersonnel.instance.definir(widget.login, _pin.text, widget.motDePasse);
    if (!mounted) return;
    if (r != null) {
      return setState(() {
        _occupe = false;
        _erreur = r;
      });
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _nePlusProposer() async {
    if (_occupe) return;
    _occupe = true;
    await DerniersUtilisateurs.refuserPin(widget.login);
    if (mounted) Navigator.of(context).pop(false);
  }

  Widget _champ(TextEditingController c, String label, Key key) => TextField(
        key: key,
        controller: c,
        enabled: !_occupe,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(PinPersonnel.longueur)],
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
        decoration: InputDecoration(labelText: label, counterText: '', border: const OutlineInputBorder()),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Code PIN personnel'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Facultatif : choisissez 4 chiffres pour vous connecter plus vite sur cet appareil. '
                'Votre mot de passe reste exigé après 3 codes faux.'),
            const SizedBox(height: 12),
            _champ(_pin, 'Nouveau code (4 chiffres)', const Key('pin_perso_nouveau')),
            const SizedBox(height: 10),
            _champ(_confirmation, 'Confirmer le code', const Key('pin_perso_confirmation')),
            if (_erreur != null) ...[const SizedBox(height: 8), MessageErreur(_erreur!)],
          ]),
        ),
        actions: [
          TextButton(key: const Key('pin_perso_jamais'), onPressed: _occupe ? null : _nePlusProposer, child: const Text('Ne plus proposer')),
          TextButton(key: const Key('pin_perso_plus_tard'), onPressed: _occupe ? null : () => Navigator.of(context).pop(false), child: const Text('Plus tard')),
          ElevatedButton(key: const Key('pin_perso_enregistrer'), onPressed: _occupe ? null : _enregistrer, child: const Text('Enregistrer')),
        ],
      );
}
