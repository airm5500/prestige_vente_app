// lib/rh/terminal_pointage_screen.dart
// Voie B — terminal de pointage commun (tablette / terminal à l'entrée de l'officine).
// Lecture du badge :
//   1. lecteur clavier USB / Bluetooth (ou scanner intégré Sunmi) : saisie rapide + Entrée dans un champ
//      toujours focalisé (clavier virtuel masqué) ;
//   2. code-barres / QR du badge par la caméra (scanner de l'appli) ;
//   3. badge NFC (pont NFC natif de l'appli, déjà utilisé par le pointage local) si l'appareil en a un.
// Écran de confirmation 3 s, en grand : « Bonjour <Prénom> — ENTRÉE 08:02 » ; le sens proposé (inverse du
// dernier pointage du jour) peut être corrigé ; son et vibration au résultat. Même badge relu < 2 min (ou doublon du serveur) : rien n'est renvoyé,
// « Awa, vous avez déjà pointé (ENTRÉE à 08:02) » en orange (information), son et vibration distincts.
// Hors ligne : pointages gardés en file avec l'heure de lecture, envoyés au retour après confirmation.
// Mode « borne » plein écran optionnel (barres système masquées, sortie par appui long + confirmation).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/rh/empreintes_screen.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/rh/rh_pointage_screen.dart';
import 'package:prestige_vente_app/screens/common/camera_scan_screen.dart';
import 'package:prestige_vente_app/services/nfc_service.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

class TerminalPointageScreen extends StatefulWidget {
  final PointageRh rh;
  final ListPresentation? presentation;

  /// Lecture du badge par la caméra (remplaçable pour les tests).
  final Future<String?> Function(BuildContext context)? camera;

  /// Empreinte (Sunmi), NFC et coffre des empreintes ; par défaut ceux du module.
  final IdentificationEmploye? identification;

  /// Durée de l'écran de confirmation avant enregistrement automatique.
  final Duration delaiConfirmation;

  /// Durée d'affichage du résultat.
  final Duration delaiResultat;

  /// Rafraîchir employés et présence à l'ouverture (désactivable pour les tests).
  final bool rafraichirAuDemarrage;

  const TerminalPointageScreen({
    super.key,
    required this.rh,
    this.presentation,
    this.camera,
    this.identification,
    this.delaiConfirmation = const Duration(seconds: 3),
    this.delaiResultat = const Duration(seconds: 4),
    this.rafraichirAuDemarrage = true,
  });

  @override
  State<TerminalPointageScreen> createState() => _TerminalPointageScreenState();
}

/// Résultat affiché en grand puis dans « Derniers pointages ».
class _Affiche {
  final String titre;
  final String detail;
  final bool ok;
  final DateTime at;

  /// Information (orange) : « vous avez déjà pointé » — ni succès ni erreur.
  final bool info;
  const _Affiche(this.titre, this.detail, this.ok, this.at, {this.info = false});
}

const _orangeFond = Color(0xFFFFF1D6);
const _orange = Color(0xFFE07B00);
const _orangeTexte = Color(0xFF8A5300);

class _TerminalPointageScreenState extends State<TerminalPointageScreen> with PresentationAware, WidgetsBindingObserver {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  PointageRh get _rh => widget.rh;

  final _champ = TextEditingController();
  final _focus = FocusNode(debugLabel: 'badge');
  Timer? _debounce;
  bool _saisieClavier = false;

  BadgeAConfirmer? _attente;
  SensPointage _sens = SensPointage.entree;
  Timer? _compteRebours;
  DateTime? _finConfirmation;
  bool _enregistrement = false;

  _Affiche? _resultat;
  Timer? _resultatTimer;
  Timer? _signalTimer;
  final List<_Affiche> _derniers = [];

  NfcAvailability? _nfcEtat;
  StreamSubscription<String>? _nfcSub;
  bool _borne = false;

  late final IdentificationEmploye _id = widget.identification ?? _rh.identification ?? IdentificationEmploye();
  NfcReader get _nfc => _id.nfc;
  CapacitesTerminal _capacites = const CapacitesTerminal();
  int _enroles = 0;
  bool _empreinteEnCours = false;

  @override
  void initState() {
    super.initState();
    loadPresentation();
    WidgetsBinding.instance.addObserver(this);
    _rh.addListener(_onRh);
    _demarrer();
    _initCapacites();
  }

  /// Capacités du terminal : empreinte (service Sunmi), NFC ; le scan et le clavier sont toujours possibles.
  Future<void> _initCapacites() async {
    final c = await _id.detecter();
    var n = 0;
    try {
      n = (await _id.enroles()).length;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _capacites = c;
      _enroles = n;
    });
    await _initNfc();
  }

  bool get _empreintePossible => _capacites.empreinte && _enroles > 0;

  Future<void> _identifierEmpreinte() async {
    if (_empreinteEnCours || _attente != null || _enregistrement) return;
    setState(() => _empreinteEnCours = true);
    try {
      final e = await _id.parEmpreinte(_rh.employes);
      if (!mounted) return;
      if (e == null) {
        _afficher(_Affiche('Empreinte non reconnue', 'Réessayez, ou utilisez votre badge.', false, _rh.now), garder: false);
        _signal(false);
      } else {
        _traiter(_rh.lireEmploye(e, moyen: MoyenIdentification.empreinte));
      }
    } on EmpreinteIndisponible catch (x) {
      if (mounted) _afficher(_Affiche('Empreinte indisponible', '${x.message} Utilisez votre badge.', false, _rh.now), garder: false);
    } finally {
      if (mounted) setState(() => _empreinteEnCours = false);
      _refocus();
    }
  }

  Future<void> _ouvrirEmpreintes() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EmpreintesScreen(rh: _rh, identification: _id)));
    await _initCapacites();
    _refocus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rh.removeListener(_onRh);
    _debounce?.cancel();
    _compteRebours?.cancel();
    _resultatTimer?.cancel();
    _signalTimer?.cancel();
    _nfcSub?.cancel();
    _nfc.stop();
    if (_borne) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _champ.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_nfcEtat != NfcAvailability.ready) _initNfc();
      if (_borne) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _refocus();
    }
  }

  void _onRh() {
    if (!mounted) return;
    setState(() {});
    if (_rh.confirmationDemandee && _attente == null) {
      _rh.confirmationVue();
      confirmerEnvoiPointagesRh(context, _rh).then((_) => _refocus());
    }
  }

  Future<void> _demarrer() async {
    await _rh.chargerEmployes();
    await _rh.chargerFile();
    if (mounted) setState(() {});
    if (widget.rafraichirAuDemarrage && !_rh.horsLigne()) {
      await _rh.rafraichirEmployes();
      await _rh.presence(_rh.now);
      if (mounted) setState(() {});
      if (mounted && _rh.enAttente > 0) await confirmerEnvoiPointagesRh(context, _rh);
    }
    _refocus();
  }

  Future<void> _initNfc() async {
    final e = await _nfc.availability();
    if (!mounted) return;
    setState(() => _nfcEtat = e);
    if (e != NfcAvailability.ready) return;
    _nfcSub ??= _nfc.tags.listen((uid) => _lu(uid, moyen: MoyenIdentification.nfc));
    await _nfc.start();
  }

  void _refocus() {
    if (!mounted) return;
    if (!_focus.hasFocus) _focus.requestFocus();
  }

  // ---------------------------------------------------------------------------
  // Lecture
  // ---------------------------------------------------------------------------

  void _onChange(String v) {
    _debounce?.cancel();
    // Scanner intégré sans touche Entrée : le code arrive d'un bloc, on attend la fin de la rafale.
    if (_saisieClavier || v.trim().isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 300), () => _lu(_champ.text));
  }

  Future<void> _camera() async {
    final v = await (widget.camera ?? (ctx) => CameraScanScreen.open(ctx, title: 'Scannez votre badge'))(context);
    if (v != null && mounted) _lu(v);
    _refocus();
  }

  void _lu(String brut, {MoyenIdentification moyen = MoyenIdentification.scan}) {
    _debounce?.cancel();
    _champ.clear();
    if (!mounted || brut.trim().isEmpty) return;
    // Une confirmation est à l'écran : les lectures suivantes sont ignorées.
    if (_attente != null || _enregistrement) {
      _refocus();
      return;
    }
    _traiter(_rh.lire(brut, moyen: moyen));
  }

  void _traiter(LectureBadge l) {
    switch (l) {
      case BadgeInconnu(:final code):
        _afficher(_Affiche('Badge non reconnu', 'Badge « $code » inconnu : faites-le associer à votre fiche (menu RH de Prestige).', false, _rh.now));
        _signal(false);
      case BadgeIgnore(:final message):
        // Aucun nouveau pointage : information claire (orange), son et vibration distincts.
        _afficher(_Affiche('Déjà pointé', message, true, _rh.now, info: true), garder: false);
        _signalInfo();
      case BadgeAConfirmer():
        _resultatTimer?.cancel();
        setState(() {
          _resultat = null;
          _attente = l;
          _sens = l.sens;
        });
        _lancerCompteRebours();
    }
    _refocus();
  }

  void _lancerCompteRebours() {
    _compteRebours?.cancel();
    _finConfirmation = DateTime.now().add(widget.delaiConfirmation);
    _compteRebours = Timer(widget.delaiConfirmation, _valider);
    setState(() {});
  }

  void _corriger(SensPointage s) {
    if (_attente == null || _enregistrement) return;
    setState(() => _sens = s);
    _lancerCompteRebours(); // le temps de vérifier la correction
  }

  void _annuler() {
    final a = _attente;
    if (a == null || _enregistrement) return;
    _compteRebours?.cancel();
    _rh.annuler(a);
    setState(() => _attente = null);
    _refocus();
  }

  Future<void> _valider() async {
    final a = _attente;
    if (a == null || _enregistrement) return;
    _compteRebours?.cancel();
    setState(() => _enregistrement = true);
    final r = await _rh.enregistrer(a, _sens);
    if (!mounted) return;
    setState(() {
      _attente = null;
      _enregistrement = false;
    });
    final hm = r.pointage.heure;
    switch (r.issue) {
      case IssueBadge.enregistre:
        _afficher(_Affiche('Bonjour ${a.employe.prenomAffiche} — ${_sens.majuscules} $hm ✓', 'Pointage enregistré.', true, _rh.now));
      case IssueBadge.dejaEnregistre:
        // Doublon du serveur (« Un pointage existe déjà à cette heure ») : même message que la relecture.
        _afficher(_Affiche('Déjà pointé', r.message, true, _rh.now, info: true));
        _signalInfo();
        _refocus();
        return;
      case IssueBadge.enFile:
        _afficher(_Affiche('Bonjour ${a.employe.prenomAffiche} — ${_sens.majuscules} $hm ✓', r.message, true, _rh.now));
      case IssueBadge.refuse:
        _afficher(_Affiche('${a.employe.prenomAffiche} : pointage refusé', r.message, false, _rh.now));
    }
    _signal(r.accepte);
    _refocus();
  }

  void _signal(bool ok) {
    try {
      SystemSound.play(ok ? SystemSoundType.click : SystemSoundType.alert);
      ok ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// « Déjà pointé » : double clic léger (distinct du succès et du refus).
  void _signalInfo() {
    void un() {
      try {
        SystemSound.play(SystemSoundType.click);
        HapticFeedback.lightImpact();
      } catch (_) {}
    }

    un();
    _signalTimer?.cancel();
    _signalTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) un();
    });
  }

  void _afficher(_Affiche a, {bool garder = true}) {
    _resultatTimer?.cancel();
    setState(() {
      _resultat = a;
      if (garder) {
        _derniers.insert(0, a);
        if (_derniers.length > 20) _derniers.removeLast();
      }
    });
    _resultatTimer = Timer(widget.delaiResultat, () {
      if (mounted) setState(() => _resultat = null);
    });
  }

  // ---------------------------------------------------------------------------
  // Mode borne
  // ---------------------------------------------------------------------------

  Future<void> _basculerBorne() async {
    if (_borne) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Quitter le mode borne ?'),
          content: const Text('Les barres du système et le bouton Retour seront de nouveau disponibles.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Rester')),
            ElevatedButton(key: const Key('rh_quitter_borne'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Quitter')),
          ],
        ),
      );
      if (ok != true) return _refocus();
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      setState(() => _borne = false);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      setState(() => _borne = true);
    }
    _refocus();
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  // ---------------------------------------------------------------------------
  // Écran
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final horsLigne = _rh.horsLigne();
    final at = _rh.employesAt;
    final etat = horsLigne
        ? 'Hors ligne · ${_rh.employes.length} employé(s) (copie ${at == null ? '—' : HorsLigne.formatDate(at)})'
        : 'En ligne · ${_rh.employes.length} employé(s)';
    final contenu = Stack(children: [
      ListView(
        key: const Key('rh_terminal'),
        padding: const EdgeInsets.all(16),
        children: [
          if (_empreintePossible) ...[
            SizedBox(
              height: 84,
              child: ElevatedButton.icon(
                key: const Key('rh_empreinte'),
                style: navyButton.copyWith(shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)))),
                onPressed: _empreinteEnCours ? null : _identifierEmpreinte,
                icon: _empreinteEnCours
                    ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                    : const Icon(Icons.fingerprint, size: 40),
                label: Text(_empreinteEnCours ? 'Posez votre doigt sur le lecteur…' : 'Pointer avec mon empreinte',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _zoneBadge(),
          const SizedBox(height: 12),
          _ligneEtat(etat, horsLigne),
          const SizedBox(height: 16),
          if (_derniers.isNotEmpty) ...[
            const Text('DERNIERS POINTAGES DU TERMINAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Pal.muted)),
            const SizedBox(height: 6),
            SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(children: [
                for (final d in _derniers.take(8))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(d.info ? Icons.info_outline : (d.ok ? Icons.check_circle : Icons.error_outline),
                        color: d.info ? _orange : (d.ok ? Pal.green : const Color(0xFFB91C1C))),
                    title: Text(d.titre, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${DateFormat('HH:mm').format(d.at)} · ${d.detail}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
              ]),
            ),
          ],
        ],
      ),
      if (_attente != null) Positioned.fill(child: _confirmation(_attente!)),
      if (_attente == null && _resultat != null) Positioned.fill(child: _panneauResultat(_resultat!)),
    ]);
    final ecran = PresentationScaffold(
      style: style,
      title: 'Terminal de pointage',
      subtitle: style == ListPresentation.dashboard ? 'Présentez votre badge' : null,
      actions: (col) => [
        if (_rh.file.isNotEmpty)
          IconButton(
            key: const Key('rh_terminal_file'),
            tooltip: 'Pointages en attente (${_rh.enAttente})',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => FilePointagesRhScreen(rh: _rh)));
              _refocus();
            },
            icon: Badge(
              isLabelVisible: _rh.enAttente > 0,
              label: Text('${_rh.enAttente}'),
              child: Icon(Icons.cloud_upload_outlined, color: col),
            ),
          ),
        if (_capacites.empreinte && !_borne)
          IconButton(
            key: const Key('rh_gerer_empreintes'),
            tooltip: 'Empreintes des employés',
            onPressed: _ouvrirEmpreintes,
            icon: Icon(Icons.fingerprint, color: col),
          ),
        GestureDetector(
          onLongPress: _borne ? _basculerBorne : null,
          child: IconButton(
            key: const Key('rh_mode_borne'),
            tooltip: _borne ? 'Mode borne (appui long pour quitter)' : 'Mode borne plein écran',
            onPressed: _borne ? null : _basculerBorne,
            icon: Icon(_borne ? Icons.lock : Icons.fullscreen, color: col),
          ),
        ),
        if (!_borne) PresentationMenuButton(value: style, onChanged: _setStyle, color: col),
      ],
      steps: StepsBar(active: _attente == null ? 0 : 1, steps: const [
        (title: 'Badge', detail: 'lecteur, caméra, NFC', onTap: null),
        (title: 'Confirmer', detail: 'entrée / sortie', onTap: null),
      ]),
      body: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _refocus, child: contenu),
    );
    return PopScope(
      canPop: !_borne,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _borne) {
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(const SnackBar(content: Text('Mode borne : appui long sur le cadenas pour quitter.')));
        }
      },
      child: ecran,
    );
  }

  Widget _zoneBadge() {
    final champ = TextField(
      key: const Key('rh_badge_champ'),
      controller: _champ,
      focusNode: _focus,
      autofocus: true,
      keyboardType: _saisieClavier ? TextInputType.text : TextInputType.none,
      textInputAction: TextInputAction.done,
      onChanged: _onChange,
      onSubmitted: (v) => _lu(v),
      decoration: InputDecoration(
        hintText: 'Scannez votre badge',
        prefixIcon: const Icon(Icons.badge),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(key: const Key('rh_badge_camera'), tooltip: 'Scanner le badge (caméra)', icon: const Icon(Icons.photo_camera), onPressed: _camera),
          IconButton(
            tooltip: 'Saisir le code du badge',
            icon: Icon(_saisieClavier ? Icons.keyboard_hide : Icons.keyboard),
            onPressed: () {
              setState(() => _saisieClavier = !_saisieClavier);
              _focus.unfocus();
              Future.microtask(() => _focus.requestFocus());
            },
          ),
        ]),
      ),
    );
    final grand = !Responsive.isCompact(context);
    return SoftCard(
      band: style == ListPresentation.guided ? Pal.navy : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Icon(Icons.contactless_outlined, size: grand ? 96 : 64, color: Pal.navy),
        const SizedBox(height: 8),
        Text('Présentez votre badge',
            textAlign: TextAlign.center, style: TextStyle(fontSize: grand ? 28 : 22, fontWeight: FontWeight.bold, color: Pal.ink)),
        const SizedBox(height: 4),
        const Text('Lecteur de badge, appareil photo ou NFC. Le sens (entrée / sortie) est proposé automatiquement.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Pal.muted)),
        const SizedBox(height: 12),
        champ,
        if (_nfcEtat == NfcAvailability.ready || _nfcEtat == NfcAvailability.disabled)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(Icons.nfc, size: 18, color: _nfcEtat == NfcAvailability.ready ? Pal.green : Pal.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_nfcEtat == NfcAvailability.ready ? 'Badge NFC : approchez-le du dos de l\'appareil' : 'NFC désactivé dans les réglages',
                    style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
              ),
              if (_nfcEtat == NfcAvailability.disabled) TextButton(onPressed: _nfc.openSettings, child: const Text('Activer')),
            ]),
          ),
      ]),
    );
  }

  Widget _ligneEtat(String etat, bool horsLigne) => Row(children: [
        Icon(horsLigne ? Icons.cloud_off : Icons.cloud_done_outlined, size: 18, color: horsLigne ? const Color(0xFF8A5300) : Pal.green),
        const SizedBox(width: 6),
        Expanded(child: Text(etat, key: const Key('rh_terminal_etat'), style: const TextStyle(fontSize: 13, color: Pal.muted))),
        if (_rh.enAttente > 0) Text('${_rh.enAttente} en attente', style: const TextStyle(fontSize: 13, color: Color(0xFF8A5300), fontWeight: FontWeight.w600)),
      ]);

  Widget _confirmation(BadgeAConfirmer a) {
    final entree = _sens == SensPointage.entree;
    final couleur = entree ? Pal.green : const Color(0xFFDC5A5A);
    final grand = !Responsive.isCompact(context);
    return Container(
      key: const Key('rh_confirmation'),
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Bonjour ${a.employe.prenomAffiche}',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: grand ? 40 : 30, fontWeight: FontWeight.bold, color: Pal.ink)),
              const SizedBox(height: 6),
              Text(a.employe.nomComplet, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: Pal.muted)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(20)),
                child: Text('${_sens.majuscules} ${DateFormat('HH:mm').format(a.lu)}',
                    key: const Key('rh_confirmation_sens'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: grand ? 44 : 34, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              const SizedBox(height: 12),
              if (_enregistrement)
                const LinearProgressIndicator()
              else
                _Decompte(fin: _finConfirmation, duree: widget.delaiConfirmation),
              const SizedBox(height: 16),
              Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
                OutlinedButton.icon(
                  key: const Key('rh_corriger'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(160, 52)),
                  onPressed: _enregistrement ? null : () => _corriger(_sens.inverse),
                  icon: const Icon(Icons.swap_horiz),
                  label: Text('Corriger : ${_sens.inverse.majuscules}'),
                ),
                TextButton(
                  key: const Key('rh_annuler'),
                  style: TextButton.styleFrom(minimumSize: const Size(100, 52)),
                  onPressed: _enregistrement ? null : _annuler,
                  child: const Text('Annuler'),
                ),
                ElevatedButton.icon(
                  key: const Key('rh_valider'),
                  style: navyButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(160, 52))),
                  onPressed: _enregistrement ? null : _valider,
                  icon: const Icon(Icons.check),
                  label: const Text('Valider'),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _panneauResultat(_Affiche r) => GestureDetector(
        onTap: () => setState(() => _resultat = null),
        child: Container(
          key: const Key('rh_resultat'),
          color: r.info ? _orangeFond : (r.ok ? const Color(0xFFDCF5E7) : const Color(0xFFFDECEC)),
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(r.info ? Icons.info_outline : (r.ok ? Icons.check_circle : Icons.error_outline),
                  size: 96, color: r.info ? _orange : (r.ok ? Pal.green : const Color(0xFFB91C1C))),
              const SizedBox(height: 12),
              Text(r.titre,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: r.info ? 22 : 30,
                      fontWeight: FontWeight.bold,
                      color: r.info ? _orangeTexte : (r.ok ? const Color(0xFF0B6B45) : const Color(0xFFB91C1C)))),
              const SizedBox(height: 8),
              Text(r.detail,
                  textAlign: TextAlign.center,
                  style: r.info
                      ? const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _orangeTexte)
                      : const TextStyle(fontSize: 16, color: Pal.ink)),
            ]),
          ),
        ),
      );
}

/// Barre du décompte avant enregistrement automatique.
class _Decompte extends StatefulWidget {
  final DateTime? fin;
  final Duration duree;
  const _Decompte({required this.fin, required this.duree});

  @override
  State<_Decompte> createState() => _DecompteState();
}

class _DecompteState extends State<_Decompte> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duree)..forward();

  @override
  void didUpdateWidget(covariant _Decompte old) {
    super.didUpdateWidget(old);
    if (old.fin != widget.fin) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        AnimatedBuilder(
          animation: _c,
          builder: (_, __) => LinearProgressIndicator(value: 1 - _c.value, minHeight: 6, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(height: 6),
        const Text('Enregistrement automatique dans un instant…', style: TextStyle(fontSize: 13, color: Pal.muted)),
      ]);
}
