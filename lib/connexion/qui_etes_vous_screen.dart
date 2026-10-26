// lib/connexion/qui_etes_vous_screen.dart
// Option C « Qui êtes-vous ? » (activée par l'administrateur, désactivée par défaut) : on touche son nom
// parmi les 6 derniers utilisateurs de l'appareil, puis on tape son code PIN personnel (4 chiffres, grand
// pavé de 64 px) ou son mot de passe. Après 3 codes faux, le mot de passe complet est exigé.
// Le PIN débloque le mot de passe gardé chiffré pour CET utilisateur sur l'appareil ; la connexion au
// serveur est toujours faite (ConnexionFlux, même logique que la connexion classique).
import 'package:prestige_vente_app/prestigepointage/lanceur_pointage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/connexion/connexion_commun.dart';
import 'package:prestige_vente_app/connexion/connexion_reglages.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/connexion/derniers_utilisateurs.dart';
import 'package:prestige_vente_app/connexion/pin_personnel.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';

/// Point + texte d'état du serveur (en-tête compact).
class _EtatServeurCompact extends StatelessWidget {
  final ControleServeur controle;
  const _EtatServeurCompact(this.controle);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    return ListenableBuilder(
      listenable: controle,
      builder: (context, _) {
        final type = s.isRemote ? 'distant' : 'local';
        final (couleur, texte) = switch (controle.etat) {
          EtatServeur.test => (Pal.amber, 'Test du serveur $type…'),
          EtatServeur.connecte => (const Color(0xFF22C55E), 'Serveur $type connecté'),
          EtatServeur.injoignable => (
              const Color(0xFFEF4444),
              '${MessagesServeur.titre(controle.panne)}${controle.rebours.reste > 0 ? ' · nouvel essai dans ${controle.rebours.reste} s' : ''}'
            ),
        };
        return Semantics(
          liveRegion: true,
          label: texte,
          excludeSemantics: true,
          child: Row(children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: couleur, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(
                child: Text(texte,
                    key: const Key('etat_serveur'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: texteSurBleu, fontSize: 12.5))),
          ]),
        );
      },
    );
  }
}

class QuiEtesVousScreen extends StatefulWidget {
  final ConnexionServices? services;
  final String? message;

  /// Heure de référence (tests).
  final DateTime? maintenant;
  const QuiEtesVousScreen({super.key, this.services, this.message, this.maintenant});

  @override
  State<QuiEtesVousScreen> createState() => _QuiEtesVousScreenState();
}

class _QuiEtesVousScreenState extends State<QuiEtesVousScreen> {
  ConnexionServices get _sv => widget.services ?? ConnexionServices.instance;
  late final SettingsProvider _settings = context.read<SettingsProvider>();
  late final ControleServeur _serveur = ControleServeur(() => _sv.sonderCourant(_settings), panneSonde: () => _settings.pingPanne);
  List<DernierUtilisateur> _utilisateurs = const [];
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    _serveur.verifier();
    _charger();
  }

  @override
  void dispose() {
    _serveur.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final l = await DerniersUtilisateurs.lire();
    if (mounted) {
      setState(() {
        _utilisateurs = l;
        _charge = true;
      });
    }
  }

  void _ouvrir(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w)).then((_) {
        if (mounted) {
          _charger();
          _serveur.verifier();
        }
      });

  Future<void> _retirer(DernierUtilisateur u) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Retirer ${u.nomAffiche} ?'),
            content: const Text('Le nom ne sera plus proposé sur cet appareil et son code PIN personnel y sera effacé.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              ElevatedButton(key: const Key('confirmer_retrait'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Retirer')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await PinPersonnel.instance.effacer(u.login);
    await DerniersUtilisateurs.retirer(u.login);
    await _charger();
  }

  @override
  Widget build(BuildContext context) {
    final t = Teintes.of(context);
    if (_charge && _utilisateurs.isEmpty) return ConnexionScreen(services: widget.services, message: widget.message);
    return Scaffold(
      backgroundColor: t.fond,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Container(
            color: Pal.navy,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 10),
                child: Row(children: [
                  const LogoOfficine(taille: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      const NomOfficine(taille: 16, align: TextAlign.start, couleur: Colors.white, siVide: 'Prestige Mobile'),
                      const SizedBox(height: 2),
                      _EtatServeurCompact(_serveur),
                    ]),
                  ),
                  IconButton(
                    key: const Key('changer_serveur'),
                    tooltip: 'Changer de serveur (code administrateur)',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const Icon(Icons.settings_outlined, color: Colors.white),
                    onPressed: () => changerServeur(context, services: _sv, apres: _serveur.verifier),
                  ),
                ]),
              ),
            ),
          ),
        ),
        Expanded(
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Semantics(header: true, child: Text('Qui êtes-vous ?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: t.texte))),
                    if (widget.message != null) ...[
                      const SizedBox(height: 6),
                      Text(widget.message!, style: TextStyle(color: t.attenue)),
                    ],
                    const SizedBox(height: 12),
                    Expanded(
                      child: !_charge
                          ? const SizedBox.shrink()
                          : GrilleUtilisateurs(
                              key: const Key('grille_utilisateurs'),
                              utilisateurs: _utilisateurs,
                              maintenant: widget.maintenant,
                              onChoisir: (u) => _ouvrir(UtilisateurConnexionScreen(utilisateur: u, services: widget.services)),
                              onRetirer: _retirer,
                              onAutre: () => _ouvrir(ConnexionScreen(services: widget.services)),
                            ),
                    ),
                    const SizedBox(height: 6),
                    // 4.10.0 : Prestige Pointage installée → « Pointer » sans se connecter (masqué sinon).
                    BoutonPointer(couleur: t.attenue),
                    PiedConnexion(couleur: t.attenue, extra: 'Appui long sur un nom : le retirer'),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Connexion d'un utilisateur choisi : code PIN ou mot de passe
// ---------------------------------------------------------------------------

class UtilisateurConnexionScreen extends StatefulWidget {
  final DernierUtilisateur utilisateur;
  final ConnexionServices? services;
  const UtilisateurConnexionScreen({super.key, required this.utilisateur, this.services});

  @override
  State<UtilisateurConnexionScreen> createState() => _UtilisateurConnexionScreenState();
}

class _UtilisateurConnexionScreenState extends State<UtilisateurConnexionScreen> {
  ConnexionServices get _sv => widget.services ?? ConnexionServices.instance;
  late final SettingsProvider _settings = context.read<SettingsProvider>();
  late final ControleServeur _serveur = ControleServeur(() => _sv.sonderCourant(_settings), panneSonde: () => _settings.pingPanne);
  final _mdp = TextEditingController();
  final _focusMdp = FocusNode();

  String get _login => widget.utilisateur.login;

  /// null = en cours de lecture ; true = PIN utilisable.
  bool? _pinDisponible;
  bool _modePin = true;
  String _saisie = '';
  bool _pinFaux = false;
  bool _occupe = false;
  bool _voir = false;
  bool _rester = false;
  String? _erreur;
  String? _info;

  @override
  void initState() {
    super.initState();
    _rester = _settings.stayConnected;
    _serveur.verifier();
    _lirePin();
  }

  Future<void> _lirePin() async {
    final actif = await PinPersonnel.instance.actif(_login);
    final verrou = actif && await PinPersonnel.instance.verrouille(_login);
    if (!mounted) return;
    setState(() {
      _pinDisponible = actif && !verrou;
      _modePin = _pinDisponible!;
      if (verrou) _info = '3 codes incorrects : saisissez votre mot de passe.';
    });
    if (!_modePin) _focusMdp.requestFocus();
  }

  @override
  void dispose() {
    _serveur.dispose();
    _mdp.dispose();
    _focusMdp.dispose();
    super.dispose();
  }

  void _passerAuMotDePasse(String info) {
    setState(() {
      _modePin = false;
      _pinDisponible = false;
      _saisie = '';
      _info = info;
      _erreur = null;
    });
    _focusMdp.requestFocus();
  }

  void _touche(String c) {
    if (_occupe) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pinFaux = false;
      _erreur = null;
      if (c == '<') {
        if (_saisie.isNotEmpty) _saisie = _saisie.substring(0, _saisie.length - 1);
      } else if (_saisie.length < PinPersonnel.longueur) {
        _saisie += c;
      }
    });
    if (c != '<' && _saisie.length == PinPersonnel.longueur) _validerPin();
  }

  Future<void> _validerPin() async {
    if (_occupe || _saisie.length != PinPersonnel.longueur) return;
    setState(() => _occupe = true);
    final (r, mdp) = await PinPersonnel.instance.verifier(_login, _saisie);
    if (!mounted) return;
    switch (r) {
      case ResultatPin.accepte:
        await _connecter(mdp!, parPin: true);
        return;
      case ResultatPin.refuse:
        final reste = await PinPersonnel.instance.essaisRestants(_login);
        if (!mounted) return;
        setState(() {
          _occupe = false;
          _pinFaux = true;
          _saisie = '';
          _erreur = 'Code incorrect · $reste essai${reste > 1 ? 's' : ''} restant${reste > 1 ? 's' : ''}';
        });
      case ResultatPin.verrouille:
        setState(() => _occupe = false);
        _passerAuMotDePasse('3 codes incorrects : saisissez votre mot de passe.');
      case ResultatPin.absent:
        setState(() => _occupe = false);
        _passerAuMotDePasse('Code PIN non disponible sur cet appareil : saisissez votre mot de passe.');
      case ResultatPin.indisponible:
        setState(() => _occupe = false);
        _passerAuMotDePasse('Stockage sécurisé indisponible : saisissez votre mot de passe.');
    }
  }

  Future<void> _validerMotDePasse() async {
    if (_occupe) return;
    if (_mdp.text.isEmpty) return setState(() => _erreur = 'Saisissez votre mot de passe');
    setState(() => _occupe = true);
    await _connecter(_mdp.text, parPin: false);
  }

  Future<void> _connecter(String motDePasse, {required bool parPin}) async {
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    final issue = await ConnexionFlux.connecter(context, login: _login, motDePasse: motDePasse, resterConnecte: _rester, services: _sv);
    if (!mounted) return;
    switch (issue) {
      case IssueConnexion.reussie:
        if (!parPin) await proposerPinPersonnel(context, login: _login, motDePasse: motDePasse);
        if (mounted) ConnexionFlux.allerAccueil(context, services: _sv);
        return;
      case IssueConnexion.licence:
        return;
      case IssueConnexion.identifiants:
        if (parPin) {
          // Le mot de passe gardé n'est plus valable (changé sur le serveur) : PIN et mot de passe effacés.
          await PinPersonnel.instance.effacer(_login);
          if (!mounted) return;
          setState(() => _occupe = false);
          _passerAuMotDePasse('Votre mot de passe a changé : saisissez-le. Le code PIN sera à recréer.');
          return;
        }
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
      _saisie = '';
      _erreur = ConnexionFlux.message(issue, panne: _serveur.panne);
    });
  }

  // -------------------------------------------------------------------------

  Widget _onglets(Teintes t) {
    Widget onglet(String texte, bool actif, VoidCallback? onTap, Key key) => Expanded(
          child: Semantics(
            selected: actif,
            button: true,
            child: Material(
              color: actif ? t.champ : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: key,
                borderRadius: BorderRadius.circular(10),
                onTap: _occupe ? null : onTap,
                child: SizedBox(
                  height: 48,
                  child: Center(
                      child: Text(texte,
                          style: TextStyle(fontWeight: FontWeight.w700, color: actif ? (identical(t, Teintes.sombre) ? Colors.white : Pal.navy) : t.attenue))),
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration:
          BoxDecoration(color: identical(t, Teintes.sombre) ? const Color(0xFF0A111C) : const Color(0xFFE6EBF2), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        onglet('Code PIN', _modePin, _pinDisponible == true ? () => setState(() => _modePin = true) : null, const Key('onglet_pin')),
        onglet('Mot de passe', !_modePin, () {
          setState(() => _modePin = false);
          _focusMdp.requestFocus();
        }, const Key('onglet_mdp')),
      ]),
    );
  }

  Widget _points(Teintes t) => Semantics(
        label: '${_saisie.length} chiffres saisis sur ${PinPersonnel.longueur}',
        excludeSemantics: true,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < PinPersonnel.longueur; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _pinFaux ? t.erreur : (i < _saisie.length ? (identical(t, Teintes.sombre) ? Colors.white : Pal.navy) : Colors.transparent),
                border: Border.all(color: _pinFaux ? t.erreur : t.attenue, width: 2),
              ),
            ),
        ]),
      );

  Widget _pave(Teintes t) {
    Widget touche(String c) {
      final ok = c == 'ok';
      final eff = c == '<';
      final label = ok ? 'Valider' : (eff ? 'Effacer' : c);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Semantics(
            button: true,
            label: ok || eff ? label : 'Chiffre $c',
            excludeSemantics: true,
            child: Material(
              color: ok ? Pal.amber : t.champ,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14), side: ok ? BorderSide.none : BorderSide(color: t.bordure.withValues(alpha: 0.6))),
              child: InkWell(
                key: Key('touche_$c'),
                borderRadius: BorderRadius.circular(14),
                onTap: _occupe ? null : () => ok ? _validerPin() : _touche(c),
                child: SizedBox(
                  height: 64,
                  child: Center(
                    child: ok
                        ? (_occupe
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Pal.onAmber))
                            : const Icon(Icons.check, color: Pal.onAmber, size: 28))
                        : eff
                            ? Icon(Icons.backspace_outlined, color: t.texte)
                            : Text(c, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: t.texte)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(children: [
      for (final ligne in const [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
        ['<', '0', 'ok'],
      ])
        Row(children: [for (final c in ligne) touche(c)]),
    ]);
  }

  Widget _caseRester(Teintes t) => !ConnexionReglages.courant.value.resterConnecteAutorise
      ? const SizedBox.shrink()
      : MergeSemantics(
          child: InkWell(
            key: const Key('rester_connecte'),
            onTap: _occupe ? null : () => setState(() => _rester = !_rester),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Checkbox(value: _rester, activeColor: Pal.navy, onChanged: _occupe ? null : (v) => setState(() => _rester = v ?? false)),
                Text('Rester connecté', style: TextStyle(color: t.texte, fontSize: 15)),
              ]),
            ),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final t = Teintes.of(context);
    final u = widget.utilisateur;
    final role = u.role.isEmpty ? 'Utilisateur' : u.role;
    return Scaffold(
      backgroundColor: t.fond,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Container(
            color: Pal.navy,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 12, 10),
                child: Row(children: [
                  IconButton(
                    tooltip: 'Retour',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: _occupe ? null : () => Navigator.of(context).maybePop(),
                  ),
                  AvatarUtilisateur(u.nomAffiche, taille: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(u.nomAffiche,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                      Text('${u.login} · $role', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: texteSurBleu, fontSize: 13)),
                      _EtatServeurCompact(_serveur),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
        Expanded(
          child: SafeArea(
            top: false,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _pinDisponible == null
                      ? const SizedBox(height: 120)
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _onglets(t),
                          const SizedBox(height: 16),
                          if (_info != null) ...[
                            Container(
                              key: const Key('utilisateur_info'),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFFFFF7E0), borderRadius: BorderRadius.circular(12)),
                              child: Row(children: [
                                const Icon(Icons.info_outline, color: Color(0xFF9A3412)),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_info!, style: const TextStyle(color: Color(0xFF3B2A06), fontSize: 13.5))),
                              ]),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_modePin) ...[
                            _points(t),
                            const SizedBox(height: 10),
                            if (_erreur != null) Center(child: MessageErreur(_erreur!, icone: Icons.warning_amber_rounded)),
                            const SizedBox(height: 10),
                            _pave(t),
                            const SizedBox(height: 6),
                            Text('Après 3 erreurs, le mot de passe complet est demandé.',
                                textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: t.attenue)),
                          ] else ...[
                            TextField(
                              key: const Key('utilisateur_mdp'),
                              controller: _mdp,
                              focusNode: _focusMdp,
                              enabled: !_occupe,
                              obscureText: !_voir,
                              autocorrect: false,
                              enableSuggestions: false,
                              inputFormatters: [LengthLimitingTextInputFormatter(128)],
                              style: TextStyle(fontSize: 16, color: t.texte),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _validerMotDePasse(),
                              decoration: InputDecoration(
                                labelText: 'Mot de passe',
                                filled: true,
                                fillColor: t.champ,
                                prefixIcon: Icon(Icons.lock_outline, color: t.attenue),
                                suffixIcon: IconButton(
                                  tooltip: _voir ? 'Masquer le mot de passe' : 'Afficher le mot de passe',
                                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                  icon: Icon(_voir ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: t.attenue),
                                  onPressed: () => setState(() => _voir = !_voir),
                                ),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            if (_erreur != null) ...[const SizedBox(height: 8), MessageErreur(_erreur!, icone: Icons.warning_amber_rounded)],
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 54,
                              child: ElevatedButton(
                                key: const Key('utilisateur_se_connecter'),
                                style: boutonAmbre(context),
                                onPressed: _occupe ? null : _validerMotDePasse,
                                child: _occupe
                                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Pal.onAmber))
                                    : const Text('Se connecter', style: TextStyle(fontSize: 16.5)),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          _caseRester(t),
                          ListenableBuilder(
                            listenable: _serveur,
                            builder: (context, _) => _serveur.etat == EtatServeur.injoignable && !_occupe
                                ? Padding(padding: const EdgeInsets.only(top: 12), child: EncadreServeurInjoignable(controle: _serveur))
                                : const SizedBox.shrink(),
                          ),
                        ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
