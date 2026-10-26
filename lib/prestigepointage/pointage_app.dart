// lib/prestigepointage/pointage_app.dart
// Prestige Pointage 1.0.0 (com.dici.prestigepointage, demande 57) : borne de pointage SANS compte, installée à côté de
// Prestige Mobile sur le même terminal. Un administrateur l'enrôle une fois ; ensuite plus aucune connexion.
//  - Premier lancement (assistant) : adresse du serveur → code administrateur de l'appareil → compte de
//    l'administrateur (P_SM_RH ou administrateur, connexion TEMPORAIRE) → nom de l'appareil (obligatoire, pré-rempli)
//    → enrôlement (POST v1/rh/bornes, empreinte de la demande 56) → déconnexion immédiate → borne.
//  - Borne : terminal de pointage de Prestige Mobile (badge QR / 1D / NFC, empreinte, photo de contrôle, file hors
//    ligne), plein écran, sur le client signé ; bandeau d'état (hors ligne, heure, retirée, réseau, serveur ancien).
//  - Administration (code administrateur) : état, envoi de la file, empreintes (connexion temporaire P_SM_RH), photo de
//    contrôle, nouvel enrôlement, retrait de l'appareil.
// Le secret de la borne n'est jamais affiché ; le contenu d'un badge QR non plus (masqué par le terminal).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/parametres/nom_appareil_reglage.dart';
import 'package:prestige_vente_app/prestigepointage/client_borne.dart';
import 'package:prestige_vente_app/prestigepointage/controleur_borne.dart';
import 'package:prestige_vente_app/prestigepointage/enrolement_borne.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/rh/empreintes_screen.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/rh/photo_controle_screen.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/rh/terminal_pointage_screen.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/serveur/nom_appareil_serveur.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

/// Points d'injection (tests).
class PointageApp {
  PointageApp._();
  static late ControleurBorne controleur;
  static Future<bool> Function(BuildContext) codeAdmin = PinCodeDialog.show;
  static EnrolementBorne enrolement = EnrolementBorne();

  /// Lecture du badge par la caméra (tests : remplacée).
  static Future<String?> Function(BuildContext)? camera;

  /// Délais de l'écran de confirmation (tests : raccourcis).
  static Duration delaiConfirmation = const Duration(seconds: 3);
  static Duration delaiResultat = const Duration(seconds: 4);
}

class PrestigePointageApp extends StatelessWidget {
  const PrestigePointageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Réglages du serveur lus au lancement (adresse reprise par l'assistant d'enrôlement).
        ChangeNotifierProvider(create: (_) => SettingsProvider()..loadSettings()),
        ChangeNotifierProvider.value(value: PointageApp.controleur),
      ],
      child: RacineTailleEcran(
        child: MaterialApp(
          title: 'Prestige Pointage',
          theme: AppTheme.lightTheme,
          debugShowCheckedModeBanner: false,
          home: const AccueilPointage(),
        ),
      ),
    );
  }
}

/// Assistant d'enrôlement tant que la borne n'a pas d'identité ; sinon la borne.
class AccueilPointage extends StatelessWidget {
  const AccueilPointage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ControleurBorne>();
    if (!c.charge) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final rh = c.rh;
    if (!c.enrolee || rh == null) return const AssistantEnrolement();
    return EcranBorne(key: ValueKey(c.identite!.borneId), rh: rh);
  }
}

// =====================================================================================================================
// Borne
// =====================================================================================================================

class EcranBorne extends StatelessWidget {
  final PointageRh rh;
  const EcranBorne({super.key, required this.rh});

  /// Taille du texte de la borne plafonnée (écran partagé, textes déjà grands) : au-delà, l'en-tête commun du
  /// terminal (lib/rh, inchangé pour Prestige Mobile) ne tient plus sur un petit écran. Assistant et administration
  /// suivent le réglage d'Android sans plafond.
  static const texteMax = 1.3;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: texteMax)),
      child: _terminal(context),
    );
  }

  Widget _terminal(BuildContext context) {
    return TerminalPointageScreen(
      rh: rh,
      titre: 'Prestige Pointage',
      gestion: false,
      confirmerEnvoi: false,
      borneAuDemarrage: true,
      codeAdmin: PointageApp.codeAdmin,
      camera: PointageApp.camera,
      delaiConfirmation: PointageApp.delaiConfirmation,
      delaiResultat: PointageApp.delaiResultat,
      bandeau: const BandeauBorne(),
      actionsEnPlus: (col) => [
        IconButton(
          key: const Key('pointage_admin'),
          tooltip: 'Administration',
          icon: Icon(Icons.admin_panel_settings_outlined, color: col),
          onPressed: () async {
            if (!await PointageApp.codeAdmin(context) || !context.mounted) return;
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranAdministrationBorne()));
          },
        ),
      ],
    );
  }
}

/// État de la borne (rien quand tout va bien) et pointages qui vont expirer.
class BandeauBorne extends StatelessWidget {
  const BandeauBorne({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ControleurBorne>();
    final cl = c.client;
    if (cl == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: cl,
      builder: (context, _) {
        final m = cl.message;
        final perimes = c.bientotPerimes.length;
        if (m.isEmpty && perimes == 0) return const SizedBox.shrink();
        final grave = cl.etat == EtatBorne.revoquee || cl.etat == EtatBorne.serveurAncien || cl.etat == EtatBorne.nonReconnue || cl.etat == EtatBorne.horloge;
        return Container(
          key: Key('pointage_bandeau_${cl.etat.name}'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: grave ? const Color(0xFFFDECEC) : const Color(0xFFFFF1D6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (m.isNotEmpty)
              Text(m, style: TextStyle(fontWeight: FontWeight.w600, color: grave ? const Color(0xFF8B1A1A) : const Color(0xFF8A5300))),
            if (perimes > 0) ...[
              if (m.isNotEmpty) const SizedBox(height: 6),
              Text(
                key: const Key('pointage_alerte_72h'),
                '$perimes pointage(s) en attente depuis plus de 60 h : Prestige les refusera après 72 h. '
                'Rétablissez la connexion de la borne au serveur (administrateur).',
                style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF8B1A1A)),
              ),
            ],
          ]),
        );
      },
    );
  }
}

// =====================================================================================================================
// Assistant d'enrôlement
// =====================================================================================================================

class AssistantEnrolement extends StatefulWidget {
  /// Nouvel enrôlement d'une borne déjà enrôlée (Administration) : retour possible.
  final bool nouvel;
  const AssistantEnrolement({super.key, this.nouvel = false});

  @override
  State<AssistantEnrolement> createState() => _AssistantEnrolementState();
}

class _AssistantEnrolementState extends State<AssistantEnrolement> {
  int _etape = 0; // 0 serveur, 1 compte de l'administrateur
  late final SettingsProvider _s = context.read<SettingsProvider>();
  late final _adresse = TextEditingController(text: _s.localIp == '192.168.1.50' ? '' : _s.localIp);
  late final _port = TextEditingController(text: _s.port);
  late final _appli = TextEditingController(text: _s.appName);
  final _login = TextEditingController();
  final _mdp = TextEditingController();
  bool _occupe = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    // Réglages lus après la première image : adresse déjà enregistrée reprise dans les champs restés vides.
    _s.addListener(_reprendreReglages);
  }

  void _reprendreReglages() {
    if (_etape != 0) return;
    if (_adresse.text.isEmpty && _s.localIp != '192.168.1.50') _adresse.text = _s.localIp;
    if (_port.text.isEmpty) _port.text = _s.port;
    if (_appli.text.isEmpty) _appli.text = _s.appName;
  }

  @override
  void dispose() {
    _s.removeListener(_reprendreReglages);
    for (final c in [_adresse, _port, _appli, _login, _mdp]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _serveur() async {
    if (_occupe) return;
    final a = _adresse.text.trim();
    if (a.isEmpty) {
      setState(() => _erreur = 'Saisissez l\'adresse du serveur Prestige (ex. 192.168.1.50).');
      return;
    }
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    final ok = await _s.saveSettings(
        localIp: a,
        remoteIp: _s.remoteIp,
        appName: _appli.text.trim().isEmpty ? 'prestige' : _appli.text.trim(),
        port: _port.text.trim().isEmpty ? '8080' : _port.text.trim());
    if (ok) await _s.setConnectionMode(false);
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _erreur = ok ? null : (_s.pingError.isEmpty ? 'Serveur injoignable : vérifiez l\'adresse et le Wi-Fi.' : _s.pingError);
    });
    if (!ok) return;
    // Code administrateur de l'appareil avant de demander le compte de l'administrateur.
    if (!await PointageApp.codeAdmin(context) || !mounted) return;
    setState(() => _etape = 1);
  }

  Future<void> _enroler() async {
    if (_occupe) return;
    if (_login.text.trim().isEmpty || _mdp.text.isEmpty) {
      setState(() => _erreur = 'Saisissez le login et le mot de passe de l\'administrateur.');
      return;
    }
    // Nom de cet appareil : obligatoire (pré-rempli avec la marque et le modèle), le même que X-Poste.
    await exigerNomAppareil(context, racine: _s.baseUrl);
    if (!mounted || !NomAppareil.instance.nomEnregistre) return;
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    String? emp;
    try {
      emp = await NomAppareilServeur.instance.empreinte();
    } catch (_) {}
    if (emp == null || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(emp)) {
      if (mounted) {
        setState(() {
          _occupe = false;
          _erreur = 'Empreinte de l\'appareil illisible : enrôlement impossible sur cet appareil.';
        });
      }
      return;
    }
    final r = await PointageApp.enrolement.enroler(
      baseUrl: _s.baseUrl,
      login: _login.text,
      motDePasse: _mdp.text,
      nom: NomAppareil.instance.saisi,
      empreinte: emp.toLowerCase(),
    );
    _mdp.clear(); // jamais gardé
    if (!mounted) return;
    if (!r.reussi) {
      setState(() {
        _occupe = false;
        _erreur = r.message;
      });
      return;
    }
    final c = context.read<ControleurBorne>();
    await c.enroler(r.identite!);
    // Photo de contrôle : autorisation de la caméra expliquée maintenant (l'administrateur est là).
    final ph = c.photos;
    if (ph != null && mounted && (await ph.reglages()).photoBadge && !await PhotoControle.permissionExpliquee()) {
      if (mounted) await expliquerEtAutoriserCamera(context, ph);
    }
    if (!mounted) return;
    setState(() => _occupe = false);
    if (widget.nouvel) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final etapes = ['1. Serveur Prestige', '2. Enrôlement par l\'administrateur'];
    return Scaffold(
      key: const Key('pointage_assistant'),
      appBar: AppBar(
        title: const Text('Prestige Pointage'),
        automaticallyImplyLeading: widget.nouvel,
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(etapes[_etape], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Pal.navy)),
          const SizedBox(height: 8),
          Text(
            _etape == 0
                ? 'Cette borne permet aux employés de pointer sans compte. Un administrateur l\'enrôle une seule fois ; '
                    'ensuite, plus aucune connexion n\'est demandée.'
                : 'Compte d\'un administrateur (droit Ressources humaines ou profil administrateur). Il sert UNE fois, '
                    'à enrôler la borne, puis il est déconnecté aussitôt. Le mot de passe n\'est pas gardé.',
            style: const TextStyle(color: Pal.muted),
          ),
          const SizedBox(height: 16),
          if (_etape == 0) ...[
            TextField(
                key: const Key('pointage_serveur_adresse'),
                controller: _adresse,
                decoration: const InputDecoration(labelText: 'Adresse du serveur', hintText: '192.168.1.50', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: TextField(
                      key: const Key('pointage_serveur_port'),
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()))),
              const SizedBox(width: 12),
              Expanded(
                  child: TextField(
                      controller: _appli, decoration: const InputDecoration(labelText: 'Application', border: OutlineInputBorder()))),
            ]),
          ] else ...[
            TextField(
                key: const Key('pointage_admin_login'),
                controller: _login,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Login de l\'administrateur', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                key: const Key('pointage_admin_mdp'),
                controller: _mdp,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Mot de passe', border: OutlineInputBorder())),
          ],
          if (_erreur != null) ...[
            const SizedBox(height: 12),
            Text(_erreur!, key: const Key('pointage_assistant_erreur'), style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              key: Key(_etape == 0 ? 'pointage_serveur_suivant' : 'pointage_enroler'),
              style: navyButton,
              onPressed: _occupe ? null : (_etape == 0 ? _serveur : _enroler),
              child: _occupe
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_etape == 0 ? 'Vérifier et continuer' : 'Enrôler cette borne'),
            ),
          ),
          if (_etape == 1)
            TextButton(onPressed: _occupe ? null : () => setState(() => _etape = 0), child: const Text('Changer de serveur')),
        ]),
      ),
    );
  }
}

// =====================================================================================================================
// Administration
// =====================================================================================================================

class EcranAdministrationBorne extends StatefulWidget {
  const EcranAdministrationBorne({super.key});

  @override
  State<EcranAdministrationBorne> createState() => _EcranAdministrationBorneState();
}

class _EcranAdministrationBorneState extends State<EcranAdministrationBorne> {
  bool _verif = false;
  ReglagesPointageTerminal? _reglages;

  @override
  void initState() {
    super.initState();
    ReglagesPointageTerminal.charger().then((r) {
      if (mounted) setState(() => _reglages = r);
    });
  }

  Future<void> _verifier(ControleurBorne c) async {
    setState(() => _verif = true);
    final ok = await c.verifier();
    if (ok) await c.envoyerFile();
    if (mounted) setState(() => _verif = false);
  }

  /// Empreintes : enrôlement soumis au droit P_SM_RH → connexion TEMPORAIRE de l'administrateur, fermée au retour.
  Future<void> _empreintes(ControleurBorne c) async {
    // Serveur de CETTE borne (celui de l'enrôlement), pas un autre réglage.
    final base = c.identite?.serveur ?? context.read<SettingsProvider>().baseUrl;
    final id = await showDialog<({String login, String mdp})>(context: context, builder: (_) => const _DialogueCompte());
    if (id == null || !mounted) return;
    final api = ApiService(baseUrl: base);
    final u = await api.login(id.login, id.mdp);
    if (!mounted) return;
    if (u == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(api.dernierEchecConnexion?.message ?? 'Connexion refusée.')));
      return;
    }
    final serveur = DioRhServeur(() => base);
    final temp = PointageRh(store: c.store, serveur: serveur, identification: c.identification, nomTerminal: () => c.identite?.nom ?? '');
    try {
      final acces = await temp.verifierAcces();
      if (acces != AccesRh.autorise || temp.gerer == false) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Ce compte ne peut pas enrôler d\'empreintes : droit Ressources humaines (P_SM_RH) requis.')));
        }
        return;
      }
      await temp.rafraichirEmployes();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => EmpreintesScreen(rh: temp, identification: c.identification, codeAdmin: (_) async => true)));
    } finally {
      await api.logout();
      try {
        await DioClient.cookieJar.deleteAll();
      } catch (_) {}
      // Copie des employés de la borne (champs réduits) relue avec la clé de la borne.
      unawaited(c.rh?.rafraichirEmployes());
    }
  }

  Future<void> _retirer(ControleurBorne c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer cette borne de l\'appareil ?'),
        content: const Text('La borne ne pourra plus pointer jusqu\'à un nouvel enrôlement. Les pointages en attente restent '
            'sur l\'appareil. Pour l\'interdire aussi côté serveur : Prestige web › RH › Bornes de pointage › Retirer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(key: const Key('pointage_retirer_confirmer'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await c.oublier();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ControleurBorne>();
    final i = c.identite;
    final cl = c.client;
    final rh = c.rh;
    final r = _reglages;
    return Scaffold(
      key: const Key('pointage_administration'),
      appBar: AppBar(title: const Text('Administration de la borne')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i?.nom ?? '—', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Borne ${i == null ? '—' : (i.borneId.length > 8 ? '${i.borneId.substring(0, 8)}…' : i.borneId)} · ${i?.serveur ?? ''}',
                style: const TextStyle(color: Pal.muted)),
            const SizedBox(height: 8),
            if (cl != null)
              ListenableBuilder(
                listenable: cl,
                builder: (_, __) => Text(cl.etat == EtatBorne.ok ? 'En ligne ✓' : (cl.message.isEmpty ? 'État non vérifié' : cl.message),
                    key: const Key('pointage_admin_etat')),
              ),
            const SizedBox(height: 8),
            Text('${rh?.enAttente ?? 0} pointage(s) en attente d\'envoi'
                '${c.bientotPerimes.isEmpty ? '' : ' (dont ${c.bientotPerimes.length} depuis plus de 60 h)'}'),
          ]),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          key: const Key('pointage_admin_verifier'),
          style: navyButton,
          onPressed: _verif ? null : () => _verifier(c),
          icon: const Icon(Icons.sync),
          label: const Text('Vérifier le serveur et envoyer les pointages'),
        ),
        const SizedBox(height: 16),
        if (r != null)
          SwitchListTile(
            key: const Key('pointage_admin_photo'),
            title: const Text('Photo de contrôle au pointage par badge'),
            subtitle: const Text('Caméra frontale, photo gardée sur la borne et envoyée à Prestige.'),
            value: r.photoBadge,
            onChanged: (v) async {
              final n = r.copie(photoBadge: v);
              await n.enregistrer();
              setState(() => _reglages = n);
            },
          ),
        ListTile(
          key: const Key('pointage_admin_empreintes'),
          leading: const Icon(Icons.fingerprint),
          title: const Text('Empreintes des employés'),
          subtitle: const Text('Enrôlement par un compte Ressources humaines (connexion temporaire, fermée ensuite).'),
          onTap: () => _empreintes(c),
        ),
        ListTile(
          key: const Key('pointage_admin_reenroler'),
          leading: const Icon(Icons.app_registration),
          title: const Text('Enrôler à nouveau'),
          subtitle: const Text('Appareil retiré, autre serveur, ou nouveau nom : l\'ancienne borne est retirée par le serveur.'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AssistantEnrolement(nouvel: true))),
        ),
        ListTile(
          key: const Key('pointage_admin_retirer'),
          leading: const Icon(Icons.delete_outline, color: Color(0xFFB91C1C)),
          title: const Text('Retirer la borne de cet appareil'),
          onTap: () => _retirer(c),
        ),
        ListTile(
          leading: const Icon(Icons.exit_to_app),
          title: const Text('Fermer Prestige Pointage'),
          onTap: () => SystemNavigator.pop(),
        ),
      ]),
    );
  }
}

class _DialogueCompte extends StatefulWidget {
  const _DialogueCompte();
  @override
  State<_DialogueCompte> createState() => _DialogueCompteState();
}

class _DialogueCompteState extends State<_DialogueCompte> {
  final _l = TextEditingController();
  final _m = TextEditingController();
  @override
  void dispose() {
    _l.dispose();
    _m.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Compte Ressources humaines'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const Key('pointage_rh_login'), controller: _l, decoration: const InputDecoration(labelText: 'Login')),
          TextField(key: const Key('pointage_rh_mdp'), controller: _m, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          TextButton(
              key: const Key('pointage_rh_valider'),
              onPressed: () => Navigator.pop(context, (login: _l.text.trim(), mdp: _m.text)),
              child: const Text('Se connecter')),
        ],
      );
}
