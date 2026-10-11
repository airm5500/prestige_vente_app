// lib/rh/mobile_pointage_screen.dart
// Voie A — « Mon pointage » : l'employé pointe son entrée / sa sortie avec SON téléphone.
// 1. Connexion (si pas de jeton valable) : identifiant (pré-rempli avec le compte de l'appli) et mot de
//    passe, utilisé pour cet appel seulement (jamais conservé). Jeton gardé dans le stockage sécurisé.
// 2. Écran de pointage : gros bouton « Pointer mon entrée / ma sortie » (sens proposé = inverse du dernier
//    pointage), scan du QR affiché à l'officine si exigé, position si exigée, résultat du serveur en grand
//    (heure = serveur), historique des 16 dernières heures. Refus du serveur affiché tel quel.
// Hors ligne : « Disponible en ligne uniquement » (l'heure du serveur et le QR l'imposent).
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

  const MobilePointageScreen({
    super.key,
    required this.rh,
    this.login,
    this.presentation,
    this.scanner,
    this.localisateur = const GeoLocalisateur(),
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
  bool _reglagesPosition = false;

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

  void _dire(String? m, {bool ok = false, bool reglages = false}) {
    if (!mounted) return;
    setState(() {
      _message = m;
      _messageOk = ok;
      _reglagesPosition = reglages;
    });
  }

  Future<void> _demarrer() async {
    final api = _api;
    if (api == null) {
      setState(() => _chargement = false);
      return;
    }
    final s = await api.reprendre();
    if (!mounted) return;
    setState(() {
      _session = s;
      _chargement = false;
    });
    if (s != null) await _actualiser();
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
    } on MobileHorsLigne {
      _dire(MobileHorsLigne.message);
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
    } on MobileHorsLigne {
      _dire(MobileHorsLigne.message);
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
    if (_login.text.trim().isEmpty || _mdp.text.isEmpty) {
      _dire('Identifiant et mot de passe obligatoires.');
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
    } on MobileHorsLigne {
      _dire(MobileHorsLigne.message);
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

  /// Sens proposé : l'inverse du dernier pointage des 16 dernières heures.
  SensPointage get _sensPropose => sensPropose(_historique.isEmpty ? null : _historique.last.sens);

  Future<String?> _scanner() =>
      (widget.scanner ?? (ctx) => CameraScanScreen.open(ctx, title: 'Scannez le QR code affiché à l\'officine'))(context);

  Future<String?> _saisirCode() => showDialog<String>(
        context: context,
        builder: (ctx) {
          final c = TextEditingController();
          return AlertDialog(
            title: const Text('Code de pointage'),
            content: TextField(
              key: const Key('rh_code_saisi'),
              controller: c,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'Code affiché sous le QR (6 caractères)'),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(c.text), child: const Text('Valider')),
            ],
          );
        },
      );

  /// Un pointage en deux gestes : bouton, puis scan (si exigé).
  Future<void> _pointer(SensPointage sens, {bool saisieManuelle = false}) async {
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
        final lu = saisieManuelle ? await _saisirCode() : await _scanner();
        if (!mounted || lu == null || lu.trim().isEmpty) return;
        if (!saisieManuelle && !estQrPointage(lu)) {
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
      }
      final r = await api.pointer(sens: sens, code: code, position: position);
      if (!mounted) return;
      if (r.ok) {
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
        _dire(r.valeur!.message, ok: true);
        await _chargerHistorique();
      } else {
        HapticFeedback.heavyImpact();
        _dire(r.refus);
      }
    } on MobileSessionExpiree catch (e) {
      _expire(e.message);
    } on MobileHorsLigne {
      _dire(MobileHorsLigne.message);
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
            color: _messageOk ? const Color(0xFFDCF5E7) : const Color(0xFFFDECEC),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(_messageOk ? Icons.check_circle : Icons.error_outline, color: _messageOk ? Pal.green : const Color(0xFFB91C1C), size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_message!,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: _messageOk ? const Color(0xFF0B6B45) : const Color(0xFFB91C1C))),
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
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(labelText: 'Identifiant', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline)),
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

  List<Widget> _pointage(SessionMobile s) {
    if (!s.aEmploye) {
      return [_bandeau('Votre compte n\'est rattaché à aucun employé actif : voyez le responsable RH.', false)];
    }
    if (!s.droitPointage) {
      return [_bandeau('Le pointage par téléphone est désactivé par l\'officine.', false)];
    }
    final sens = _sensPropose;
    final entree = sens == SensPointage.entree;
    return [
      Wrap(spacing: 8, runSpacing: 6, children: [
        _puce(s.qr ? Icons.qr_code_2 : Icons.qr_code_2_outlined, s.qr ? 'QR code de l\'officine exigé' : 'QR code non exigé', s.qr),
        _puce(s.gps ? Icons.location_on : Icons.location_off_outlined, s.gps ? 'Position exigée' : 'Position non exigée', s.gps),
      ]),
      const SizedBox(height: 14),
      SizedBox(
        height: 88,
        child: ElevatedButton.icon(
          key: const Key('rh_pointer'),
          style: ElevatedButton.styleFrom(
            backgroundColor: entree ? Pal.green : const Color(0xFFDC5A5A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          onPressed: _occupe || _horsLigne ? null : () => _pointer(sens),
          icon: Icon(entree ? Icons.login : Icons.logout, size: 34),
          label: Text(entree ? 'Pointer mon entrée' : 'Pointer ma sortie', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
      ),
      const SizedBox(height: 6),
      Wrap(alignment: WrapAlignment.spaceBetween, children: [
        TextButton.icon(
          key: const Key('rh_pointer_autre'),
          onPressed: _occupe || _horsLigne ? null : () => _pointer(sens.inverse),
          icon: Icon(sens.inverse == SensPointage.entree ? Icons.login : Icons.logout, size: 18),
          label: Text(sens.inverse == SensPointage.entree ? 'Pointer plutôt mon entrée' : 'Pointer plutôt ma sortie'),
        ),
        if (s.qr)
          TextButton.icon(
            key: const Key('rh_saisir_code'),
            onPressed: _occupe || _horsLigne ? null : () => _pointer(sens, saisieManuelle: true),
            icon: const Icon(Icons.keyboard, size: 18),
            label: const Text('Saisir le code affiché'),
          ),
      ]),
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

  Widget _puce(IconData i, String t, bool actif) => Chip(
        avatar: Icon(i, size: 18, color: actif ? Pal.navy : Pal.muted),
        label: Text(t, style: TextStyle(fontSize: 12.5, color: actif ? Pal.ink : Pal.muted)),
        backgroundColor: actif ? const Color(0xFFE3ECF7) : const Color(0xFFF1F3F6),
        side: BorderSide.none,
      );
}
