// lib/rh/rh_pointage_screen.dart
// Entrée « Pointage présence » (menu Équipe, identifiant `pointage_rh`) : choix de la voie selon ce que le serveur et le compte permettent.
// - « Mon pointage » (voie A, téléphone de l'employé) : API v1/mobile présente et active ;
// - « Terminal de pointage » (voie B, badge, NFC, empreinte) : droit P_SM_RH du compte connecté ;
// - « Pointages en attente » : file hors ligne du terminal (confirmation avant envoi, liste décochable) ;
// - suivi (« Présences du jour ») : UNIQUEMENT pour le gestionnaire (administrateur de l'application ou compte
//   ayant le droit RH P_SM_RH) ; pour un employé, l'écran ne sert qu'à POINTER (capture), sans analyse.
// Ce qui n'est pas disponible reste visible mais désactivé, avec l'explication (route absente : 404,
// module désactivé, droit manquant, hors ligne). Présentations A / B / C et tablette comme les autres écrans.
// Réglages administrateur du terminal : « Mon pointage » (pointage par simple bouton) peut être désactivé sur un
// terminal partagé ; « Photos de contrôle » (pointages par badge, sans photo signalés) réservé au gestionnaire,
// après le code administrateur.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/rapports_hl_screen.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/rh/mobile_api.dart';
import 'package:prestige_vente_app/rh/mobile_pointage_screen.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/rh/photo_controle_screen.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/presences_screen.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/rh/terminal_pointage_screen.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';
import 'package:provider/provider.dart';

class RhPointageScreen extends StatefulWidget {
  /// Module (tests) ; sinon [PointageRh.instance].
  final PointageRh? rh;
  final ListPresentation? presentation;

  /// Gestionnaire (suivi, présences) : par défaut administrateur de l'application ou droit RH (P_SM_RH).
  final bool? gestion;

  /// Code administrateur (photos de contrôle) ; par défaut PinCodeDialog.show.
  final Future<bool> Function(BuildContext context)? codeAdmin;
  const RhPointageScreen({super.key, this.rh, this.presentation, this.gestion, this.codeAdmin});

  @override
  State<RhPointageScreen> createState() => _RhPointageScreenState();
}

/// État de la voie A vu du serveur.
enum EtatVoieA { verification, disponible, inactif, absent, horsLigne }

class _RhPointageScreenState extends State<RhPointageScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  PointageRh get _rh => widget.rh ?? PointageRh.instance;
  EtatVoieA _voieA = EtatVoieA.verification;
  bool _verifie = false;
  ReglagesPointageTerminal _reglages = const ReglagesPointageTerminal();
  RegistrePhotosPointage? _registre;

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _rh.addListener(_onRh);
    _registre = _rh.photos?.registre;
    _registre?.addListener(_onRh);
    _chargerReglages();
    _verifier();
  }

  Future<void> _chargerReglages() async {
    final r = await (_rh.photos?.reglages ?? ReglagesPointageTerminal.charger)();
    if (mounted) setState(() => _reglages = r);
    await _registre?.charger();
  }

  @override
  void dispose() {
    _rh.removeListener(_onRh);
    _registre?.removeListener(_onRh);
    super.dispose();
  }

  Future<void> _ouvrirPhotos() async {
    final reg = _registre;
    if (reg == null) return;
    if (!await (widget.codeAdmin ?? PinCodeDialog.show)(context) || !mounted) return;
    await _ouvrir(PhotosPointageScreen(registre: reg, retentionJours: _reglages.retentionJours));
  }

  void _onRh() {
    if (mounted) setState(() {});
    if (_rh.confirmationDemandee && mounted) {
      _rh.confirmationVue();
      confirmerEnvoiPointagesRh(context, _rh);
    }
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  Future<void> _verifier() async {
    setState(() => _verifie = false);
    await _rh.chargerFile();
    final m = _rh.mobile;
    EtatVoieA a;
    if (m == null || _rh.horsLigne()) {
      a = EtatVoieA.horsLigne;
    } else {
      final s = await m.sonder();
      a = s == null
          ? EtatVoieA.horsLigne
          : !s.existe
              ? EtatVoieA.absent
              : s.actif
                  ? EtatVoieA.disponible
                  : EtatVoieA.inactif;
    }
    await _rh.verifierAcces();
    if (!mounted) return;
    setState(() {
      _voieA = a;
      _verifie = true;
    });
    if (_rh.acces == AccesRh.autorise && !_rh.horsLigne() && _rh.enAttente > 0) {
      await confirmerEnvoiPointagesRh(context, _rh);
    }
  }

  bool get _adminAppli {
    try {
      return Provider.of<AuthProvider>(context, listen: false).isAdmin;
    } catch (_) {
      return false;
    }
  }

  /// Suivi et analyse réservés au gestionnaire : administrateur de l'application ou droit RH (P_SM_RH).
  bool get _gestionnaire => widget.gestion ?? estGestionnaireRh(admin: _adminAppli, acces: _rh.acces);

  String? get _loginConnecte {
    try {
      return Provider.of<AuthProvider>(context, listen: false).user?.login;
    } catch (_) {
      return null;
    }
  }

  String get _voieAExplication => switch (_voieA) {
        EtatVoieA.verification => 'Vérification du serveur…',
        EtatVoieA.disponible => 'Avec votre téléphone : QR code de l\'officine et position si elle est exigée.',
        EtatVoieA.inactif => messageModuleMobileInactif,
        EtatVoieA.absent => MobileIndisponible.message,
        EtatVoieA.horsLigne => 'Disponible en ligne uniquement (l\'heure est celle du serveur).',
      };

  String get _voieBExplication => switch (_rh.acces) {
        AccesRh.autorise => _rh.accesMessage.isNotEmpty
            ? _rh.accesMessage
            : 'Badge (lecteur, caméra), NFC ou empreinte sur un appareil commun. ${_rh.employes.length} employé(s) copiés.',
        AccesRh.refuse => '${_rh.accesMessage} Droit « P_SM_RH » nécessaire sur le compte connecté.',
        AccesRh.absent => _rh.accesMessage,
        AccesRh.inconnu => _verifie ? (_rh.accesMessage.isEmpty ? 'Accès RH non vérifié.' : _rh.accesMessage) : 'Vérification du droit RH…',
      };

  Future<void> _ouvrir(Widget w) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final voieB = _rh.acces == AccesRh.autorise;
    final presences = voieB && !_rh.horsLigne();
    final gestion = _gestionnaire;
    final tuiles = [
      _tuile(
        key: const Key('rh_voie_a'),
        icon: Icons.phone_android,
        titre: 'Mon pointage',
        detail: _reglages.simpleBouton ? _voieAExplication : messageSimpleBoutonDesactive,
        actif: _voieA == EtatVoieA.disponible && _reglages.simpleBouton,
        onTap: () => _ouvrir(MobilePointageScreen(rh: _rh, login: _loginConnecte, presentation: style)),
      ),
      _tuile(
        key: const Key('rh_voie_b'),
        icon: Icons.badge_outlined,
        titre: 'Terminal de pointage',
        detail: _voieBExplication,
        actif: voieB,
        onTap: () => _ouvrir(TerminalPointageScreen(rh: _rh, presentation: style, gestion: gestion)),
      ),
      // Suivi : jamais proposé à un employé (capture seule).
      if (gestion)
        _tuile(
          key: const Key('rh_presences'),
          icon: Icons.fact_check_outlined,
          titre: 'Présences du jour',
          detail: presences
              ? 'Suivi (pharmacien) : entrées, sorties, retards et anomalies de l\'équipe.'
              : voieB
                  ? 'Disponible en ligne uniquement.'
                  : 'Réservé aux comptes ayant le droit RH (P_SM_RH).',
          actif: presences,
          onTap: () => _ouvrir(PresencesScreen(rh: _rh, presentation: style)),
        ),
      // Photos de contrôle des pointages par badge : gestionnaire uniquement, après le code administrateur.
      if (gestion && _registre != null)
        _tuile(
          key: const Key('rh_photos'),
          icon: Icons.photo_camera_front,
          titre: 'Photos de contrôle (badge)',
          detail: !_reglages.photoBadge
              ? 'Photo de contrôle désactivée sur ce terminal (Paramètres › Équipe & pointage).'
              : _registre!.anomaliesNonTraitees > 0
                  ? '${_registre!.anomaliesNonTraitees} pointage(s) sans photo à vérifier · code administrateur.'
                  : 'Photo prise à chaque pointage par badge, gardée ${_reglages.retentionJours} jours sur ce terminal · code administrateur.',
          actif: true,
          onTap: _ouvrirPhotos,
        ),
      if (_rh.file.isNotEmpty)
        _tuile(
          key: const Key('rh_file'),
          icon: Icons.cloud_upload_outlined,
          titre: 'Pointages du terminal (${_rh.enAttente} en attente)',
          detail: _rh.anomaliesNonTraitees > 0
              ? '${_rh.anomaliesNonTraitees} refusé(s) par le serveur : voir les anomalies.'
              : 'Pointages saisis hors ligne, envoyés après confirmation.',
          actif: true,
          onTap: () => _ouvrir(FilePointagesRhScreen(rh: _rh)),
        ),
    ];
    final enAttente = _rh.enAttente;
    return PresentationScaffold(
      style: style,
      title: 'Pointage présence',
      subtitle: style == ListPresentation.dashboard ? 'Présence des employés (Prestige)' : null,
      actions: (col) => [
        IconButton(key: const Key('rh_verifier'), tooltip: 'Vérifier à nouveau', onPressed: _verifier, icon: Icon(Icons.refresh, color: col)),
        PresentationMenuButton(value: style, onChanged: _setStyle, color: col),
      ],
      steps: StepsBar(active: 1, steps: [
        (title: 'Choisir', detail: 'téléphone ou badge', onTap: null),
        (title: 'Pointer', detail: 'envoi à Prestige', onTap: null),
        if (gestion) (title: 'Suivre', detail: 'présences', onTap: null),
      ]),
      header: [
        if (style == ListPresentation.dashboard)
          Row(children: [
            Expanded(child: KpiTile('${_rh.employes.length}', 'employé(s) copiés')),
            const SizedBox(width: 8),
            Expanded(child: KpiTile('$enAttente', 'en attente d\'envoi', highlight: enAttente > 0)),
          ]),
      ],
      compactHeader: [
        LightFigures([
          ('${_rh.employes.length}', 'Employés copiés', Pal.navy),
          ('$enAttente', 'En attente', enAttente > 0 ? const Color(0xFFB45309) : Pal.navy),
        ]),
      ],
      body: ListView(
        key: const Key('rh_hub'),
        padding: const EdgeInsets.all(16),
        children: [
          if (!_verifie) const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator()),
          if (style == ListPresentation.compact)
            Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.line)),
              child: Column(children: tuiles),
            )
          else
            ...cardColumn(tuiles, Responsive.isCompact(context) ? 1 : 2, spacing: 10),
          const SizedBox(height: 12),
          const Text(
            'Les pointages faits ici sont envoyés à Prestige (RH › Présence du jour). Le menu « Pointage local » '
            '(empreinte / PIN sur cet appareil) n\'envoie rien à Prestige ; le « Pointage BL Stock » contrôle les quantités.',
            key: Key('rh_note_envoi'),
            style: TextStyle(fontSize: 12, color: Pal.muted),
          ),
        ],
      ),
    );
  }

  Widget _tuile({required Key key, required IconData icon, required String titre, required String detail, required bool actif, required VoidCallback onTap}) {
    final row = Row(children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: actif ? const Color(0xFFE3ECF7) : const Color(0xFFEFF1F4), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: actif ? Pal.navy : Pal.muted),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: actif ? Pal.ink : Pal.muted)),
          Text(detail, style: const TextStyle(fontSize: 13, color: Pal.muted)),
        ]),
      ),
      Icon(actif ? Icons.chevron_right : Icons.block, size: 18, color: Pal.muted),
    ]);
    final tap = actif ? onTap : null;
    if (style == ListPresentation.compact) {
      return InkWell(
        key: key,
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
          child: row,
        ),
      );
    }
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(16),
      onTap: tap,
      child: SoftCard(
          band: style == ListPresentation.guided && actif ? Pal.navy : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: row),
    );
  }
}

/// Suivi et analyse (présences, empreintes) : administrateur de l'application, ou compte ayant le droit RH
/// (P_SM_RH, vérifié par `GET rh/droits`). Les autres comptes ne font que pointer.
bool estGestionnaireRh({required bool admin, required AccesRh acces}) => admin || acces == AccesRh.autorise;

// -----------------------------------------------------------------------------
// File des pointages du terminal (hors ligne) et confirmation d'envoi
// -----------------------------------------------------------------------------

bool _confirmationRhOuverte = false;

/// Confirmation AVANT tout envoi (comme les ventes H2 / le stock H3) : liste des pointages, à décocher
/// s'ils ont déjà été saisis autrement (ils ne seront jamais envoyés). Une seule fenêtre à la fois.
Future<BilanEnvoiRh?> confirmerEnvoiPointagesRh(BuildContext context, PointageRh rh) async {
  if (_confirmationRhOuverte || rh.envoiEnCours) return null;
  _confirmationRhOuverte = true;
  try {
    await rh.chargerFile();
    final liste = rh.aEnvoyer;
    if (liste.isEmpty || !context.mounted) return null;
    final choix = await showDialog<Set<String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConfirmationEnvoiRh(pointages: liste),
    );
    if (choix == null) return null; // Plus tard
    await rh.exclure([for (final p in liste) if (!choix.contains(p.id)) p.id]);
    if (choix.isEmpty) return null;
    final bilan = await rh.envoyer(ids: choix);
    if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(bilan.message)));
    return bilan;
  } finally {
    _confirmationRhOuverte = false;
  }
}

class _ConfirmationEnvoiRh extends StatefulWidget {
  final List<PointageBadge> pointages;
  const _ConfirmationEnvoiRh({required this.pointages});

  @override
  State<_ConfirmationEnvoiRh> createState() => _ConfirmationEnvoiRhState();
}

class _ConfirmationEnvoiRhState extends State<_ConfirmationEnvoiRh> {
  late final Set<String> _coches = {for (final p in widget.pointages) p.id};
  bool _repondu = false;

  void _fermer([Set<String>? choix]) {
    if (_repondu) return;
    _repondu = true;
    Navigator.of(context).pop(choix);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.pointages.length;
    final exclus = n - _coches.length;
    return AlertDialog(
      key: const Key('rh_confirmation_envoi'),
      scrollable: true,
      title: Text('Envoyer $n pointage(s) du terminal ?'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(
              'Pointages lus hors ligne, envoyés avec l\'heure de lecture. Décochez ceux déjà saisis autrement '
              '(pointeuse, saisie manuelle) : ils restent dans l\'historique, jamais envoyés.',
              style: TextStyle(fontSize: 13.5)),
          const SizedBox(height: 8),
          for (final p in widget.pointages)
            CheckboxListTile(
              key: Key('rh_coche_${p.id}'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _coches.contains(p.id),
              onChanged: (c) => setState(() => c == true ? _coches.add(p.id) : _coches.remove(p.id)),
              title: Text('${p.employeNom} · ${p.sens.majuscules}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text('${DateFormat('dd/MM').format(p.lu)} à ${p.heure}', style: const TextStyle(fontSize: 12.5)),
            ),
          if (exclus > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('$exclus pointage(s) décoché(s) : non envoyé(s).', style: const TextStyle(fontSize: 12.5, color: Color(0xFF9A3412))),
            ),
        ]),
      ),
      actions: [
        TextButton(
          key: const Key('rh_envoi_plus_tard'),
          style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
          onPressed: () => _fermer(),
          child: const Text('Plus tard'),
        ),
        ElevatedButton(
          key: const Key('rh_envoyer_selection'),
          style: ElevatedButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => _fermer(Set<String>.of(_coches)),
          child: const Text('Envoyer la sélection'),
        ),
      ],
    );
  }
}

/// Historique des pointages du terminal (file hors ligne) : état, envoi, anomalies.
class FilePointagesRhScreen extends StatefulWidget {
  final PointageRh rh;
  const FilePointagesRhScreen({super.key, required this.rh});

  @override
  State<FilePointagesRhScreen> createState() => _FilePointagesRhScreenState();
}

class _FilePointagesRhScreenState extends State<FilePointagesRhScreen> {
  @override
  void initState() {
    super.initState();
    widget.rh.chargerFile();
  }

  ({Color fg, Color bg}) _couleurs(StatutPointageBadge s) => switch (s) {
        StatutPointageBadge.enAttente => (fg: const Color(0xFF8A5300), bg: const Color(0xFFFFF1D6)),
        StatutPointageBadge.envoye || StatutPointageBadge.dejaApplique => (fg: const Color(0xFF0B6B45), bg: const Color(0xFFDCF5E7)),
        StatutPointageBadge.refuse => (fg: const Color(0xFFB91C1C), bg: const Color(0xFFFDECEC)),
        StatutPointageBadge.exclu => (fg: const Color(0xFF3D4B60), bg: const Color(0xFFE6EBF2)),
      };

  @override
  Widget build(BuildContext context) {
    final rh = widget.rh;
    return ListenableBuilder(
      listenable: rh,
      builder: (context, _) {
        final l = rh.file.reversed.toList();
        return Scaffold(
          backgroundColor: Pal.page,
          appBar: AppBar(
            title: const Text('Pointages du terminal'),
            actions: [
              IconButton(
                tooltip: 'Anomalies',
                icon: const Icon(Icons.report_problem_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnomaliesHorsLigneScreen())),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: ElevatedButton.icon(
                key: const Key('rh_envoyer'),
                style: navyButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48))),
                icon: rh.envoiEnCours
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text('Envoyer (${rh.enAttente})'),
                onPressed: rh.envoiEnCours || rh.enAttente == 0 || rh.horsLigne() ? null : () => confirmerEnvoiPointagesRh(context, rh),
              ),
            ),
          ),
          body: ContentWidth(
            child: ListView(
              key: const Key('rh_liste_file'),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                if (rh.horsLigne())
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Hors ligne : envoi au retour du serveur (confirmation demandée).', style: TextStyle(color: Color(0xFF8A5300))),
                  ),
                if (l.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucun pointage gardé sur ce terminal.'))),
                for (final p in l)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SoftCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${p.employeNom} · ${p.sens.majuscules}', style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
                            Text('Lu le ${DateFormat('dd/MM').format(p.lu)} à ${p.heure}', style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
                            if (p.message.isNotEmpty && p.statut != StatutPointageBadge.envoye)
                              Text(p.message, style: const TextStyle(fontSize: 12.5, color: Pal.ink)),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        StatusBadge(p.statut.label, fg: _couleurs(p.statut).fg, bg: _couleurs(p.statut).bg),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
