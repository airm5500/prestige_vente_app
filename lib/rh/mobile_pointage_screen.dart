// lib/rh/mobile_pointage_screen.dart
// Voie A — « Mon pointage » : l'employé pointe son entrée / sa sortie avec SON téléphone.
// 1. Connexion (si pas de jeton valable) : identifiant (pré-rempli avec le compte de l'appli) et mot de
//    passe, utilisé pour cet appel seulement (jamais conservé). Jeton gardé dans le stockage sécurisé.
// 2. Écran de pointage (en-tête : nom et matricule de l'employé) : deux gros boutons « Arrivée » (vert, ENTREE)
//    et « Départ » (rouge doux, SORTIE) ; celui qui correspond à l'inverse du dernier pointage est mis en
//    évidence (« suggéré »), sans être imposé. Un appui = scan du QR (si exigé) puis envoi : deux gestes,
//    aucune confirmation. Position : exigée → demandée ; sinon envoyée seulement si l'autorisation est déjà
//    accordée (jamais demandée, délai court, jamais bloquante). Résultat du serveur en grand (heure = serveur),
//    historique des 16 dernières heures. Refus du serveur affiché tel quel. Code saisi à la main en secours.
//    Rien n'est journalisé (ni QR, ni position, ni réponse du serveur).
// Hors ligne : « Disponible en ligne uniquement » (l'heure du serveur et le QR l'imposent).
// Sous le résultat, l'état de l'envoi : « Envoyé à Prestige ✓ » ou « Refusé par Prestige ».
// 4.4.0 (décision du pharmacien, proposition a) : le téléphone pointe TOUJOURS pour le compte connecté à
// l'application. Jeton d'un autre compte → effacé automatiquement (information affichée) ; pas de jeton → connexion
// v1/mobile automatique si le mot de passe de CE compte est mémorisé (« Rester connecté »), sinon mot de passe
// seul, identifiant pré-rempli NON modifiable.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/rh/localisation.dart';
import 'package:prestige_vente_app/rh/mobile_api.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/screens/common/camera_scan_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

class MobilePointageScreen extends StatefulWidget {
  final PointageRh rh;

  /// Identifiant du compte connecté à l'appli (pré-rempli ; le mot de passe est toujours demandé).
  final String? login;
  final ListPresentation? presentation;

  /// Lecture du QR (remplaçable pour les tests).
  final Future<String?> Function(BuildContext context)? scanner;
  final Localisateur localisateur;

  /// Mot de passe mémorisé de [login] (« Rester connecté »), ou null : connexion automatique (4.4.0).
  final Future<String?> Function()? motDePasseMemorise;

  const MobilePointageScreen({
    super.key,
    required this.rh,
    this.login,
    this.presentation,
    this.scanner,
    this.localisateur = const GeoLocalisateur(),
    this.motDePasseMemorise,
  });

  @override
  State<MobilePointageScreen> createState() => _MobilePointageScreenState();
}

class _MobilePointageScreenState extends State<MobilePointageScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  MobileApi? get _api => widget.rh.mobile;
  SessionMobile? _session;
  bool _chargement = true;
  bool _occupe = false;
  List<PointageMobile> _historique = [];

  /// Message principal (résultat du pointage, refus, erreur) et sa couleur.
  String? _message;
  bool _messageOk = false;

  /// Message d'information (orange) : « Vous avez déjà pointé à 08:02 ».
  bool _messageInfo = false;
  bool _reglagesPosition = false;

  /// État de l'envoi du dernier pointage (sous le message) : envoyé à Prestige, ou refusé par Prestige.
  String? _etatEnvoi;

  late final TextEditingController _login = TextEditingController(text: widget.login ?? '');
  final TextEditingController _mdp = TextEditingController();
  bool _voirMdp = false;

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _demarrer();
  }

  @override
  void dispose() {
    _login.dispose();
    _mdp.dispose();
    super.dispose();
  }

  bool get _horsLigne => widget.rh.horsLigne();

  void _dire(String? m, {bool ok = false, bool reglages = false, bool info = false, String? envoi}) {
    if (!mounted) return;
    setState(() {
      _message = m;
      _messageOk = ok;
      _messageInfo = info;
      _reglagesPosition = reglages;
      _etatEnvoi = envoi;
    });
  }

  Future<void> _demarrer() async {
    final api = _api;
    if (api == null) {
      setState(() => _chargement = false);
      return;
    }
    // Lien au compte de l'application : un jeton d'un autre compte est effacé tout de suite.
    final efface = await api.lier(widget.login);
    var s = await api.reprendre();
    if (!mounted) return;
    if (efface) {
      _dire('Ce téléphone était connecté au compte « ${api.jetonEfface} » : déconnecté. Il pointe désormais pour « ${_loginApp!} ».', info: true);
    }
    if (s == null && _loginApp != null && !_horsLigne) s = await _connexionAutomatique();
    if (!mounted) return;
    setState(() {
      _session = s;
      _chargement = false;
    });
    if (s != null) await _actualiser();
  }

  /// Compte de l'application (null : pas de compte connu, identifiant saisi librement comme avant).
  String? get _loginApp {
    final l = (widget.login ?? '').trim();
    return l.isEmpty ? null : l;
  }

  /// Connexion v1/mobile sans geste si le mot de passe de CE compte est mémorisé ; sinon null (formulaire).
  Future<SessionMobile?> _connexionAutomatique() async {
    final api = _api, login = _loginApp;
    if (api == null || login == null) return null;
    String? mdp;
    try {
      mdp = await widget.motDePasseMemorise?.call();
    } catch (_) {}
    if (mdp == null || mdp.isEmpty) return null;
    try {
      final r = await api.connexion(login, mdp);
      if (r.ok) return r.valeur;
      _dire(r.refus);
    } on MobileHorsLigne catch (e) {
      _dire(e.texte);
    } on MobileIndisponible {
      _dire(MobileIndisponible.message);
    }
    return null;
  }

  /// Droits et réglages relus (`moi`), puis historique.
  Future<void> _actualiser() async {
    final api = _api;
    if (api == null || _horsLigne) {
      _dire(MobileHorsLigne.message);
      return;
    }
    try {
      final s = await api.moi();
      if (!mounted) return;
      setState(() => _session = s);
      if (s.peutPointer) await _chargerHistorique();
    } on MobileSessionExpiree catch (e) {
      _expire(e.message);
    } on MobileHorsLigne catch (e) {
      _dire(e.texte);
    } on MobileIndisponible {
      _dire(MobileIndisponible.message);
    }
  }

  Future<void> _chargerHistorique() async {
    try {
      final h = await _api!.mesPointages();
      if (mounted) setState(() => _historique = h);
    } on MobileSessionExpiree catch (e) {
      _expire(e.message);
    } on MobileHorsLigne catch (e) {
      _dire(e.texte);
    } on MobileIndisponible {
      _dire(MobileIndisponible.message);
    }
  }

  void _expire(String m) {
    if (!mounted) return;
    setState(() {
      _session = null;
      _historique = [];
    });
    _dire(m);
  }

  Future<void> _connecter() async {
    final api = _api;
    if (api == null || _occupe) return;
    if (_loginApp != null) _login.text = _loginApp!; // jamais un autre compte que celui de l'application
    if (_login.text.trim().isEmpty || _mdp.text.isEmpty) {
      _dire(_loginApp != null ? 'Mot de passe obligatoire.' : 'Identifiant et mot de passe obligatoires.');
      return;
    }
    if (_horsLigne) {
      _dire(MobileHorsLigne.message);
      return;
    }
    setState(() => _occupe = true);
    try {
      final r = await api.connexion(_login.text, _mdp.text);
      _mdp.clear(); // jamais conservé
      if (!mounted) return;
      if (!r.ok) {
        _dire(r.refus);
        return;
      }
      setState(() => _session = r.valeur);
      _dire(null);
      if (r.valeur!.peutPointer) await _chargerHistorique();
    } on MobileHorsLigne catch (e) {
      _dire(e.texte);
    } on MobileIndisponible {
      _dire(MobileIndisponible.message);
    } finally {
      _mdp.clear();
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _deconnecter() async {
    await _api?.deconnecter();
    if (!mounted) return;
    setState(() {
      _session = null;
      _historique = [];
    });
    _dire('Téléphone déconnecté : le jeton a été effacé.', ok: true);
  }

  /// Sens suggéré : l'inverse du dernier pointage des 16 dernières heures (mis en évidence, jamais imposé).
  SensPointage get _sensSuggere => sensPropose(_historique.isEmpty ? null : _historique.last.sens);

  Future<String?> _scanner() =>
      (widget.scanner ?? (ctx) => CameraScanScreen.open(ctx, title: 'Scannez le QR code affiché à l\'officine'))(context);

  /// Secours : code affiché sous le QR saisi à la main, puis « Arrivée » ou « Départ ».
  Future<({String code, SensPointage sens})?> _saisirCode() => showDialog<({String code, SensPointage sens})>(
        context: context,
        builder: (ctx) {
          final c = TextEditingController();
          final suggere = _sensSuggere;
          void valider(SensPointage sens) => Navigator.of(ctx).pop((code: c.text, sens: sens));
          ButtonStyle style(SensPointage sens) => sens == suggere
              ? ElevatedButton.styleFrom(backgroundColor: _couleurSens(sens), foregroundColor: Colors.white)
              : ElevatedButton.styleFrom(foregroundColor: _couleurSens(sens));
          return AlertDialog(
            title: const Text('Code de pointage'),
            content: TextField(
              key: const Key('rh_code_saisi'),
              controller: c,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'Code affiché sous le QR (6 caractères)'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
              ElevatedButton(
                  key: const Key('rh_code_arrivee'), style: style(SensPointage.entree), onPressed: () => valider(SensPointage.entree), child: const Text('Arrivée')),
              ElevatedButton(
                  key: const Key('rh_code_depart'), style: style(SensPointage.sortie), onPressed: () => valider(SensPointage.sortie), child: const Text('Départ')),
            ],
          );
        },
      );

  Future<void> _pointerAvecCodeSaisi() async {
    if (_occupe || _horsLigne) return;
    final r = await _saisirCode();
    if (!mounted || r == null || r.code.trim().isEmpty) return;
    await _pointer(r.sens, codeSaisi: r.code);
  }

  /// Position facultative (GPS non exigé) : seulement si l'autorisation est déjà accordée, délai court ;
  /// tout échec → pointage sans position (jamais bloquant).
  Future<PositionPointage?> _positionFacultative() async {
    try {
      final p = await widget.localisateur
          .position(exigee: false)
          .timeout(delaiPositionFacultative, onTimeout: () => const ResultatPosition.echec('Délai dépassé.'));
      return p.ok ? p.position : null;
    } catch (_) {
      return null;
    }
  }

  /// Un pointage en deux gestes : bouton « Arrivée » / « Départ », puis scan (si exigé). Pas de confirmation.
  Future<void> _pointer(SensPointage sens, {String? codeSaisi}) async {
    final api = _api;
    final s = _session;
    if (api == null || s == null || _occupe) return;
    if (_horsLigne) {
      _dire(MobileHorsLigne.message);
      return;
    }
    setState(() => _occupe = true);
    try {
      String? code;
      if (s.qr) {
        final lu = codeSaisi ?? await _scanner();
        if (!mounted || lu == null || lu.trim().isEmpty) return;
        if (codeSaisi == null && !estQrPointage(lu)) {
          _dire('Ce n\'est pas le QR code de pointage de l\'officine (il commence par « $prefixeQrPointage »).');
          return;
        }
        code = codePointagePourEnvoi(lu);
      }
      PositionPointage? position;
      if (s.gps) {
        _dire('Recherche de la position…', ok: true);
        final p = await widget.localisateur.position(exigee: true);
        if (!mounted) return;
        if (!p.ok) {
          _dire(p.erreur, reglages: p.reglages);
          return;
        }
        position = p.position;
      } else {
        position = await _positionFacultative();
        if (!mounted) return;
      }
      final r = await api.pointer(sens: sens, code: code, position: position);
      if (!mounted) return;
      if (r.ok) {
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
        _dire(r.valeur!.message, ok: true, envoi: etatEnvoyePrestige);
        await _chargerHistorique();
      } else if (estRefusDeuxMinutes(r.refus!)) {
        // Refus « moins de deux minutes » : l'employé a déjà pointé — heure du dernier pointage connu.
        await _chargerHistorique();
        if (!mounted) return;
        final hm = _historique.isEmpty ? '' : heureMinute(_historique.last.heure);
        HapticFeedback.lightImpact();
        SystemSound.play(SystemSoundType.click);
        _dire(messageDejaPointeMobile(hm), info: true, envoi: 'Déjà enregistré dans Prestige : rien de nouveau envoyé.');
      } else {
        HapticFeedback.heavyImpact();
        _dire(r.refus, envoi: '$etatRefusPrestige : ce pointage n\'est pas enregistré.');
      }
    } on MobileSessionExpiree catch (e) {
      _expire(e.message);
    } on MobileHorsLigne catch (e) {
      _dire(e.texte);
    } on MobileIndisponible {
      _dire(MobileIndisponible.message);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return PresentationScaffold(
      style: style,
      title: 'Mon pointage',
      subtitle: s?.aEmploye == true ? '${s!.employeNom}${s.employeMatricule.isEmpty ? '' : ' · ${s.employeMatricule}'}' : 'Pointage avec mon téléphone',
      actions: (col) => [
        if (s != null)
          IconButton(key: const Key('rh_mobile_deconnexion'), tooltip: 'Déconnecter ce téléphone', onPressed: _deconnecter, icon: Icon(Icons.logout, color: col)),
        PresentationMenuButton(value: style, onChanged: _setStyle, color: col),
      ],
      steps: StepsBar(active: s == null ? 0 : 1, steps: const [
        (title: 'Se connecter', detail: 'une fois', onTap: null),
        (title: 'Pointer', detail: 'bouton, scan', onTap: null),
      ]),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              key: const Key('rh_mobile'),
              padding: const EdgeInsets.all(16),
              children: [
                if (_horsLigne) _bandeau('Disponible en ligne uniquement : le pointage utilise l\'heure du serveur et le QR code du moment.', false),
                if (_message != null) _bandeauMessage(),
                if (_api == null)
                  _bandeau('Serveur non configuré.', false)
                else if (s == null)
                  _formulaire()
                else
                  ..._pointage(s),
              ],
            ),
    );
  }

  Widget _bandeau(String t, bool ok) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: ok ? const Color(0xFFDCF5E7) : const Color(0xFFFFF1D6), borderRadius: BorderRadius.circular(12)),
          child: Text(t, style: TextStyle(color: ok ? const Color(0xFF0B6B45) : const Color(0xFF8A5300), fontWeight: FontWeight.w600)),
        ),
      );

  Widget _bandeauMessage() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          key: const Key('rh_mobile_message'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _messageInfo ? const Color(0xFFFFF1D6) : (_messageOk ? const Color(0xFFDCF5E7) : const Color(0xFFFDECEC)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(_messageInfo ? Icons.info_outline : (_messageOk ? Icons.check_circle : Icons.error_outline),
                color: _messageInfo ? const Color(0xFFE07B00) : (_messageOk ? Pal.green : const Color(0xFFB91C1C)), size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(_message!,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _messageInfo ? const Color(0xFF8A5300) : (_messageOk ? const Color(0xFF0B6B45) : const Color(0xFFB91C1C)))),
                if (_etatEnvoi != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_etatEnvoi!, key: const Key('rh_mobile_etat_envoi'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Pal.ink)),
                  ),
              ]),
            ),
            if (_reglagesPosition)
              TextButton(onPressed: widget.localisateur.ouvrirReglages, child: const Text('Réglages')),
          ]),
        ),
      );

  Widget _formulaire() => SoftCard(
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Connectez ce téléphone avec vos identifiants Prestige.',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
            const SizedBox(height: 4),
            const Text('Le mot de passe sert seulement à obtenir l\'accès du téléphone (12 h) ; il n\'est jamais gardé.',
                style: TextStyle(fontSize: 12.5, color: Pal.muted)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('rh_mobile_login'),
              controller: _login,
              // 4.4.0 : le compte de l'application, non modifiable (le téléphone pointe pour lui seul).
              readOnly: _loginApp != null,
              enableInteractiveSelection: _loginApp == null,
              autofillHints: const [AutofillHints.username],
              decoration: InputDecoration(
                labelText: 'Identifiant',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person_outline),
                suffixIcon: _loginApp != null ? const Tooltip(message: 'Compte connecté à l\'application', child: Icon(Icons.lock_outline)) : null,
                helperText: _loginApp != null ? 'Compte connecté à l\'application' : null,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('rh_mobile_mdp'),
              controller: _mdp,
              obscureText: !_voirMdp,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _connecter(),
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _voirMdp ? 'Masquer' : 'Afficher',
                  icon: Icon(_voirMdp ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _voirMdp = !_voirMdp),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                key: const Key('rh_mobile_connecter'),
                style: navyButton,
                onPressed: _occupe ? null : _connecter,
                icon: _occupe
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.login),
                label: const Text('Se connecter', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      );

  List<Widget> _pointage(SessionMobile s) => _pointageCompte(s);

  List<Widget> _pointageCompte(SessionMobile s) {
    if (!s.aEmploye) {
      return [_bandeau('Votre compte n\'est rattaché à aucun employé actif : voyez le responsable RH.', false)];
    }
    if (!s.droitPointage) {
      return [_bandeau('Le pointage par téléphone est désactivé par l\'officine.', false)];
    }
    final suggere = _sensSuggere;
    final arrivee = _boutonSens(SensPointage.entree, suggere == SensPointage.entree);
    final depart = _boutonSens(SensPointage.sortie, suggere == SensPointage.sortie);
    return [
      Wrap(spacing: 8, runSpacing: 6, children: [
        _puce(s.qr ? Icons.qr_code_2 : Icons.qr_code_2_outlined, s.qr ? 'QR code de l\'officine exigé' : 'QR code non exigé', s.qr),
        _puce(s.gps ? Icons.location_on : Icons.location_off_outlined, s.gps ? 'Position exigée' : 'Position non exigée', s.gps),
      ]),
      const SizedBox(height: 14),
      // Deux gros boutons côte à côte (empilés si l'écran est trop étroit).
      LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 280
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: arrivee),
                const SizedBox(width: 12),
                Expanded(child: depart),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [arrivee, const SizedBox(height: 12), depart]),
      ),
      if (s.qr) ...[
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('rh_saisir_code'),
            onPressed: _occupe || _horsLigne ? null : _pointerAvecCodeSaisi,
            icon: const Icon(Icons.keyboard, size: 18),
            label: const Text('Saisir le code affiché'),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Row(children: [
        const Expanded(child: Text('MES POINTAGES (16 DERNIÈRES HEURES)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Pal.muted))),
        IconButton(tooltip: 'Actualiser', onPressed: _occupe ? null : _actualiser, icon: const Icon(Icons.refresh, size: 20)),
      ]),
      SoftCard(
        key: const Key('rh_historique'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: _historique.isEmpty
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Aucun pointage.', style: TextStyle(color: Pal.muted)))
            : Column(children: [
                for (final p in _historique.reversed)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(p.sens == SensPointage.sortie ? Icons.logout : Icons.login,
                        color: p.sens == SensPointage.sortie ? const Color(0xFFB91C1C) : Pal.green),
                    title: Text('${p.heure} · ${p.sens?.label ?? '?'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: p.sourceLabel.isEmpty ? null : Text(p.sourceLabel),
                  ),
              ]),
      ),
    ];
  }

  static Color _couleurSens(SensPointage sens) => sens == SensPointage.entree ? Pal.green : const Color(0xFFDC5A5A);

  /// « Arrivée » (vert, ENTREE) ou « Départ » (rouge doux, SORTIE). Le bouton suggéré (inverse du dernier
  /// pointage) porte une bordure et un badge discret « suggéré » ; l'autre reste pleinement utilisable.
  Widget _boutonSens(SensPointage sens, bool suggere) {
    final entree = sens == SensPointage.entree;
    return SizedBox(
      height: 104,
      child: ElevatedButton(
        key: Key(entree ? 'rh_arrivee' : 'rh_depart'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _couleurSens(sens),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          elevation: suggere ? 4 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: suggere ? BorderSide(color: entree ? const Color(0xFF0B6B45) : const Color(0xFF9B1C1C), width: 3) : BorderSide.none,
          ),
        ),
        onPressed: _occupe || _horsLigne ? null : () => _pointer(sens),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(entree ? Icons.login : Icons.logout, size: 30),
              const SizedBox(width: 8),
              Text(entree ? 'Arrivée' : 'Départ', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 6),
            // Place réservée même sans badge : les deux boutons gardent la même mise en page.
            SizedBox(
              height: 20,
              child: suggere
                  ? Container(
                      key: Key(entree ? 'rh_suggere_arrivee' : 'rh_suggere_depart'),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0x40FFFFFF), borderRadius: BorderRadius.circular(10)),
                      child: const Text('suggéré', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    )
                  : null,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _puce(IconData i, String t, bool actif) => Chip(
        avatar: Icon(i, size: 18, color: actif ? Pal.navy : Pal.muted),
        label: Text(t, style: TextStyle(fontSize: 12.5, color: actif ? Pal.ink : Pal.muted)),
        backgroundColor: actif ? const Color(0xFFE3ECF7) : const Color(0xFFF1F3F6),
        side: BorderSide.none,
      );
}
