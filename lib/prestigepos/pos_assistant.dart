// lib/prestigepos/pos_assistant.dart
// PrestigePOS — premier lancement : écran d'accueil puis ASSISTANT DE CONFIGURATION, protégé par le code
// administrateur de l'appareil (code par défaut à changer à la première utilisation, comme Prestige Mobile) :
//   1. Serveur Prestige (adresse http:// ou https://, port, application) — vérifié avant de continuer ;
//   2. Utilisateur borne (compte Prestige dédié, droits de prévente) — mot de passe en stockage sécurisé,
//      « Tester la borne » (connexion + produits, cause précise en cas d'échec) ;
//   3. Présentation (Vitrine / Liste rapide / Guidée), taille de l'écran, mobile money ;
//   4. Imprimante de ticket (Sunmi, Bluetooth, USB, réseau ; 58 / 80 mm ; test) ;
//   5. Récapitulatif → « Démarrer la borne ».
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/parametres/nom_appareil_reglage.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_diagnostic.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_page.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_reglages.dart';
import 'package:prestige_vente_app/prestigepos/pos_app.dart';
import 'package:prestige_vente_app/prestigepos/pos_reglages.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/serveur/adresse_serveur.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart';
import 'package:prestige_vente_app/prestigepos/pos_styles.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';

/// Premier lancement : présentation et accès à l'assistant (code administrateur).
class PosBienvenue extends StatelessWidget {
  const PosBienvenue({super.key});

  Future<void> _configurer(BuildContext context) async {
    if (!await PosApp.codeAdmin(context) || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PosAssistant()));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('pos-bienvenue'),
        backgroundColor: Pal.page,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const PosLogo(taille: 110),
                  const SizedBox(height: 18),
                  const Text('Bienvenue dans PrestigePOS',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Pal.ink)),
                  const SizedBox(height: 10),
                  const Text(
                    'Borne de vente libre-service reliée à votre serveur Prestige : le client choisit ses produits, '
                    'reçoit un ticket de prévente et paie à la caisse.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Pal.muted),
                  ),
                  const SizedBox(height: 10),
                  const Text('La configuration est réservée à l\'administrateur (code administrateur demandé).',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Pal.ink, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      key: const ValueKey('pos-configurer'),
                      style: posBoutonBleu,
                      onPressed: () => _configurer(context),
                      icon: const Icon(Icons.settings),
                      label: const Text('Configurer PrestigePOS', style: TextStyle(fontSize: 17)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Assistant de configuration (5 étapes).
class PosAssistant extends StatefulWidget {
  /// Test de la borne (tests) ; sinon TesteurBorne sur l'adresse du serveur.
  final TesteurBorne Function(String baseUrl)? testeur;
  const PosAssistant({super.key, this.testeur});

  static const etapes = ['Serveur', 'Utilisateur borne', 'Présentation', 'Imprimante', 'Terminé'];

  @override
  State<PosAssistant> createState() => _PosAssistantState();
}

class _PosAssistantState extends State<PosAssistant> {
  int _etape = 0;
  late final SettingsProvider _s = context.read<SettingsProvider>();

  // 1. Serveur
  late final _adresse = TextEditingController(text: _s.localIp == '192.168.1.50' && !PosReglages.courant.value.configure ? '' : _s.localIp);
  late final _port = TextEditingController(text: _s.port);
  late final _appli = TextEditingController(text: _s.appName);
  bool _verification = false;
  String? _erreurServeur;

  // 2. Utilisateur borne
  late BorneConfig _borne = BorneReglages.courant.value;
  late final _login = TextEditingController(text: _borne.login);
  final _mdp = TextEditingController();
  bool _mdpEnregistre = false;
  String? _erreurBorne;
  bool _test = false;
  DiagnosticBorne? _diagnostic;

  // 3. Présentation
  late TailleEcran _taille = TailleEcranReglage.enregistree;
  late bool _mobileMoney = PosReglages.courant.value.mobileMoney;

  @override
  void initState() {
    super.initState();
    BorneReglages.secrets.lire().then((v) {
      if (mounted) setState(() => _mdpEnregistre = v != null && v.isNotEmpty);
    });
  }

  @override
  void dispose() {
    for (final c in [_adresse, _port, _appli, _login, _mdp]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Étapes
  // ---------------------------------------------------------------------------

  Future<void> _verifierServeur() async {
    if (_verification) return;
    final adresse = _adresse.text.trim();
    if (adresse.isEmpty) {
      setState(() => _erreurServeur = 'Saisissez l\'adresse du serveur Prestige (ex. 192.168.1.50 ou https://pharmacie.exemple.com).');
      return;
    }
    setState(() {
      _verification = true;
      _erreurServeur = null;
    });
    final ok = await _s.saveSettings(
      localIp: adresse,
      remoteIp: _s.remoteIp,
      appName: _appli.text.trim().isEmpty ? 'prestige' : _appli.text.trim(),
      port: _port.text.trim().isEmpty ? '8080' : _port.text.trim(),
    );
    if (ok) await _s.setConnectionMode(false);
    if (!mounted) return;
    setState(() {
      _verification = false;
      // 1.1.3 : « Serveur injoignable… » ou « Serveur indisponible… » (Prestige en démarrage / redéploiement).
      _erreurServeur = ok ? null : (_s.pingError.isEmpty ? MessagesServeur.injoignable : _s.pingError);
    });
    if (ok) _suivant();
  }

  Future<bool> _enregistrerBorne() async {
    final login = _login.text.trim();
    if (login.isEmpty) {
      setState(() => _erreurBorne = 'Saisissez le login Prestige de la borne.');
      return false;
    }
    if (_mdp.text.isEmpty && !_mdpEnregistre) {
      setState(() => _erreurBorne = 'Saisissez le mot de passe de l\'utilisateur borne.');
      return false;
    }
    if (_mdp.text.isNotEmpty) {
      try {
        await BorneReglages.secrets.ecrire(_mdp.text);
        _mdpEnregistre = true;
        _mdp.clear();
      } catch (e) {
        setState(() => _erreurBorne = 'Mot de passe non enregistré (stockage sécurisé indisponible : $e).');
        return false;
      }
    }
    await BorneReglages.enregistrer(_borne.copyWith(login: login, actif: true));
    _borne = BorneReglages.courant.value;
    if (mounted) setState(() => _erreurBorne = null);
    return true;
  }

  Future<void> _tester() async {
    if (_test || !await _enregistrerBorne()) return;
    setState(() {
      _test = true;
      _diagnostic = null;
    });
    DiagnosticBorne d;
    try {
      d = await (widget.testeur?.call(_s.baseUrl) ?? TesteurBorne(baseUrl: _s.baseUrl)).tester(_borne);
    } catch (e) {
      d = DiagnosticBorne([EtapeBorne('Test', EtatEtapeBorne.echec, 'Test impossible : $e')]);
    }
    if (mounted) {
      setState(() {
        _test = false;
        _diagnostic = d;
      });
    }
  }

  Future<void> _terminer() async {
    await PosReglages.enregistrer(PosReglages.courant.value.copyWith(configure: true, mobileMoney: _mobileMoney));
    PaiementsMobileReglages.actif.value = _mobileMoney;
    await BorneReglages.enregistrer(BorneReglages.courant.value.copyWith(actif: true));
    if (_taille != TailleEcranReglage.enregistree) {
      await TailleEcranReglage.enregistrer(_taille);
      TailleEcranReglage.appliquerMaintenant();
    }
    if (!mounted) return;
    // 1.5.1 : nom de cet appareil obligatoire avant d'ouvrir la borne (l'assistant est fait par l'administrateur).
    // 1.6.0 (demande 56) : nom d'abord cherché sur le serveur (réinstallation) ; trouvé, l'étape est sautée.
    await exigerNomAppareil(context, racine: _s.baseUrl);
    if (!mounted) return;
    await PosApp.ouvrirBorne(context);
  }

  Future<void> _suivant() async {
    if (_etape == 1 && !await _enregistrerBorne()) return;
    if (_etape == 2) {
      await BorneReglages.enregistrer(_borne);
      await PosReglages.enregistrer(PosReglages.courant.value.copyWith(mobileMoney: _mobileMoney));
    }
    if (!mounted) return;
    setState(() => _etape = (_etape + 1).clamp(0, PosAssistant.etapes.length - 1));
  }

  void _precedent() {
    if (_etape == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _etape--);
    }
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------

  Widget _aide(String t) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(t, style: const TextStyle(fontSize: 13.5, color: Pal.muted)),
      );

  Widget _erreur(String t, Key key) => Container(
        key: key,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(12)),
        child: Text(t, style: const TextStyle(color: Color(0xFF7C2D12), fontSize: 14.5)),
      );

  Widget _serveur() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Adresse du serveur Prestige de la pharmacie (le même que Prestige Mobile).', style: TextStyle(fontSize: 15, color: Pal.ink)),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('pos-serveur-adresse'),
          controller: _adresse,
          onChanged: (_) => setState(() {}),
          keyboardType: TextInputType.url,
          autocorrect: false,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s')), LengthLimitingTextInputFormatter(200)],
          decoration: const InputDecoration(
              labelText: 'Adresse (IP ou nom)', hintText: '192.168.1.50 ou https://pharmacie.exemple.com', border: OutlineInputBorder()),
        ),
        _aide('« https:// » devant l\'adresse pour une connexion chiffrée ; sinon HTTP. Un port écrit dans l\'adresse '
            '(« :8443 ») est prioritaire.'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('pos-serveur-port'),
              controller: _port,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
              decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              key: const ValueKey('pos-serveur-appli'),
              controller: _appli,
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\s/]')), LengthLimitingTextInputFormatter(40)],
              decoration: const InputDecoration(labelText: 'Application', border: OutlineInputBorder()),
            ),
          ),
        ]),
        if (_adresse.text.trim().isNotEmpty)
          _aide('Adresse utilisée : ${AdresseServeur.affichage(AdresseServeur.normaliser(_adresse.text), AdresseServeur.portEffectif(AdresseServeur.normaliser(_adresse.text), portChamp: _port.text, protocolePrincipal: AdresseServeur.protocole(AdresseServeur.normaliser(_adresse.text))))}'),
        if (_erreurServeur != null) _erreur(_erreurServeur!, const ValueKey('pos-serveur-erreur')),
      ]);

  Widget _utilisateur() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Compte Prestige DÉDIÉ à la borne : il est le vendeur des préventes de la borne. Donnez-lui seulement le '
            'droit de créer des préventes (pas d\'encaissement, pas d\'administration).', style: TextStyle(fontSize: 15, color: Pal.ink)),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('pos-borne-login'),
          controller: _login,
          autocorrect: false,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]')), LengthLimitingTextInputFormatter(40)],
          decoration: const InputDecoration(labelText: 'Login de l\'utilisateur borne', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('pos-borne-mdp'),
          controller: _mdp,
          obscureText: true,
          inputFormatters: [LengthLimitingTextInputFormatter(64)],
          decoration: InputDecoration(
            labelText: 'Mot de passe',
            helperText: _mdpEnregistre ? 'Enregistré : laisser vide pour le garder.' : null,
            border: const OutlineInputBorder(),
          ),
        ),
        _aide('Mot de passe chiffré dans le stockage sécurisé d\'Android, jamais en clair.'),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('pos-borne-tester'),
            style: posBoutonContour,
            onPressed: _test ? null : _tester,
            icon: _test ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.fact_check_outlined),
            label: const Text('Tester la borne'),
          ),
        ),
        if (_erreurBorne != null) _erreur(_erreurBorne!, const ValueKey('pos-borne-erreur')),
        if (_diagnostic != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.line)),
            child: DiagnosticBorneVue(_diagnostic!),
          ),
      ]);

  Widget _presentation() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Présentation de la borne', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Pal.ink)),
        for (final p in BornePresentation.values)
          RadioListTile<BornePresentation>(
            key: ValueKey('pos-presentation-${p.name}'),
            contentPadding: EdgeInsets.zero,
            value: p,
            groupValue: _borne.presentation,
            title: Text(p.label),
            subtitle: Text(p.detail),
            onChanged: (v) => setState(() => _borne = _borne.copyWith(presentation: v)),
          ),
        const SizedBox(height: 10),
        const Text('Taille de l\'écran', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Pal.ink)),
        for (final t in TailleEcran.values)
          RadioListTile<TailleEcran>(
            key: ValueKey('pos-taille-${t.name}'),
            contentPadding: EdgeInsets.zero,
            value: t,
            groupValue: _taille,
            title: Text(t.libelle),
            subtitle: Text(switch (t) {
              TailleEcran.automatique => 'Selon l\'écran (Compact d\'office sur un petit terminal)',
              TailleEcran.compact => 'Interface réduite de 10 %',
              TailleEcran.tresCompact => 'Interface réduite de 20 %',
            }),
            onChanged: (v) => setState(() => _taille = v ?? TailleEcran.automatique),
          ),
        const SizedBox(height: 10),
        SwitchListTile(
          key: const ValueKey('pos-mobile-money'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Proposer le paiement mobile money'),
          subtitle: const Text('Seulement si le serveur Prestige l\'annonce (module paiements mobile). Sinon, le client paie '
              'à la caisse avec son ticket de prévente.'),
          value: _mobileMoney,
          onChanged: (v) => setState(() => _mobileMoney = v),
        ),
      ]);

  Widget _termine() {
    final imp = ImprimanteReglages.courant.value;
    Widget ligne(IconData i, String t, String v) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(i, color: Pal.navy),
          title: Text(t, style: const TextStyle(color: Pal.muted, fontSize: 13.5)),
          subtitle: Text(v, style: const TextStyle(color: Pal.ink, fontSize: 16, fontWeight: FontWeight.w700)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('PrestigePOS est prêt.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Pal.ink)),
      const SizedBox(height: 6),
      ligne(Icons.dns_outlined, 'Serveur', _s.adresseAffichee(false)),
      ligne(Icons.person_outline, 'Utilisateur borne', BorneReglages.courant.value.login),
      ligne(Icons.dashboard_outlined, 'Présentation', BorneReglages.courant.value.presentation.label),
      ligne(Icons.print_outlined, 'Imprimante', imp.resume),
      const SizedBox(height: 8),
      const Text(
        'La borne s\'ouvre en plein écran et reste épinglée (Android peut demander « Épingler l\'application ? » : '
        'acceptez). Pour en sortir : maintenez 2 s le cadenas en haut à droite, confirmez, puis saisissez le code '
        'administrateur.',
        style: TextStyle(fontSize: 14.5, color: Pal.muted),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final contenu = switch (_etape) {
      0 => _serveur(),
      1 => _utilisateur(),
      2 => _presentation(),
      3 => const ImprimanteReglagesVue(),
      _ => _termine(),
    };
    final dernier = _etape == PosAssistant.etapes.length - 1;
    return Scaffold(
      key: const ValueKey('pos-assistant'),
      backgroundColor: Pal.page,
      body: Column(children: [
        Container(
          width: double.infinity,
          color: Pal.navy,
          padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Configuration de PrestigePOS', style: TextStyle(color: Pal.headerMuted, fontSize: 14)),
            const SizedBox(height: 4),
            Text('${_etape + 1}. ${PosAssistant.etapes[_etape]}',
                key: const ValueKey('pos-etape-titre'), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Row(children: [
              for (var i = 0; i < PosAssistant.etapes.length; i++)
                Expanded(
                  child: Container(
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(color: i <= _etape ? Pal.amber : const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(3)),
                  ),
                ),
            ]),
          ]),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [contenu]),
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Pal.line))),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SafeArea(
            top: false,
            child: Row(children: [
              TextButton.icon(
                key: const ValueKey('pos-precedent'),
                style: TextButton.styleFrom(minimumSize: const Size(88, 48), foregroundColor: Pal.navy),
                onPressed: _precedent,
                icon: const Icon(Icons.arrow_back),
                label: Text(_etape == 0 ? 'Annuler' : 'Retour'),
              ),
              const SizedBox(width: 12),
              // Bouton principal : prend la place restante, texte réduit si l'écran est étroit (Sunmi, texte ×1,3).
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    key: ValueKey(dernier ? 'pos-demarrer' : (_etape == 0 ? 'pos-serveur-verifier' : 'pos-suivant')),
                    style: (dernier ? posBoutonAmbre : posBoutonBleu).copyWith(minimumSize: const WidgetStatePropertyAll(Size(64, 52))),
                    onPressed: _verification
                        ? null
                        : dernier
                            ? _terminer
                            : (_etape == 0 ? _verifierServeur : _suivant),
                    icon: _verification
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(dernier ? Icons.storefront : Icons.arrow_forward),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(dernier ? 'Démarrer la borne' : (_etape == 0 ? 'Vérifier et continuer' : 'Continuer')),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
