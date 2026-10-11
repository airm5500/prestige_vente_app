// lib/support/signaler_probleme_screen.dart
// « Signaler un problème » (menu ⋮ de l'accueil, Réglages › Centre de support) : objet (obligatoire),
// description, module, gravité, contexte technique joint ou non. Envoi au centre de support
// (POST /support/events, type APPLICATION) ; gardé sur le terminal si le serveur ne répond pas.
// En option : demande de contact (e-mail au support, POST /prestige/support-contact) avec une capture d'écran.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prestige_vente_app/support/support_capture.dart';
import 'package:prestige_vente_app/support/support_centre.dart';
import 'package:prestige_vente_app/support/support_event.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Modules proposés (ceux du formulaire de contact web, plus ceux du mobile).
const modulesSupport = [
  'MOBILE',
  'VENTE',
  'CAISSE',
  'STOCK',
  'COMMANDES',
  'INVENTAIRE',
  'HORS_LIGNE',
  'POINTAGE',
  'IMPRESSION',
  'TIERS-PAYANT',
  'STATISTIQUES',
  'AUTRE',
];

const gravitesSupport = {
  NiveauSupport.info: 'Information',
  NiveauSupport.warn: 'Gênant',
  NiveauSupport.error: 'Bloquant',
};

/// Urgence de la demande de contact (liste du web : BASSE, MOYENNE, HAUTE, CRITIQUE).
String urgenceDe(String niveau) => switch (niveau) {
      NiveauSupport.error => 'HAUTE',
      NiveauSupport.warn => 'MOYENNE',
      _ => 'BASSE',
    };

/// Choix d'une capture d'écran (galerie) ; remplaçable dans les tests.
Future<SupportPieceJointe?> choisirCaptureGalerie() async {
  final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
  if (f == null) return null;
  return SupportPieceJointe(f.name, await f.readAsBytes());
}

/// Ouvre le formulaire depuis l'écran courant (gardé comme « écran concerné »).
Future<void> ouvrirSignalement(BuildContext context, {SupportCentre? centre}) {
  final c = centre ?? SupportCentre.instance;
  final ecran = c.ecran;
  return Navigator.of(context).push(MaterialPageRoute(
    settings: const RouteSettings(name: 'SignalerProblemeScreen'),
    builder: (_) => SignalerProblemeScreen(centre: c, ecranOrigine: ecran),
  ));
}

class SignalerProblemeScreen extends StatefulWidget {
  final SupportCentre? centre;

  /// Écran depuis lequel le problème est signalé.
  final String ecranOrigine;
  final Future<SupportPieceJointe?> Function()? choisirCapture;
  const SignalerProblemeScreen({super.key, this.centre, this.ecranOrigine = '', this.choisirCapture});

  @override
  State<SignalerProblemeScreen> createState() => _SignalerProblemeScreenState();
}

class _SignalerProblemeScreenState extends State<SignalerProblemeScreen> {
  final _form = GlobalKey<FormState>();
  final _objet = TextEditingController();
  final _description = TextEditingController();
  late String _module = modulesSupport.contains(moduleDeLEcran(widget.ecranOrigine)) ? moduleDeLEcran(widget.ecranOrigine) : 'MOBILE';
  String _gravite = NiveauSupport.warn;
  bool _contexte = true;
  bool _contact = false;
  SupportPieceJointe? _capture;
  bool _envoi = false;

  SupportCentre get _c => widget.centre ?? SupportCentre.instance;

  @override
  void dispose() {
    _objet.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _choisirCapture() async {
    try {
      final p = await (widget.choisirCapture ?? choisirCaptureGalerie)();
      if (p == null || !mounted) return;
      if (p.octets.length > SupportPieceJointe.maxOctets) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Capture trop lourde (10 Mo au plus).')));
        return;
      }
      setState(() => _capture = p);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Capture non jointe : $e')));
    }
  }

  Future<void> _envoyer() async {
    if (_envoi || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _envoi = true);
    final objet = _objet.text.trim();
    final description = SupportFiltre.texte(_description.text.trim());
    final issue = await _c.signaler(SupportEvent(
      type: TypeSupport.application,
      niveau: _gravite,
      module: _module,
      messageCourt: objet,
      urlOuEcran: widget.ecranOrigine.isEmpty ? 'Signalement mobile' : widget.ecranOrigine,
      stack: description.isEmpty ? null : description,
      donnees: {'signalement': 'manuel', 'objet': tronquer(objet, 300)},
      auto: false,
      contexte: _contexte,
    ));

    String? contactMsg;
    if (_contact) {
      final f = _c.contact;
      if (f == null) {
        contactMsg = 'Demande de contact impossible : connectez-vous au serveur.';
      } else {
        final ctx = _c.contexteTechnique();
        final terminal = ctx['terminal'] is Map ? (ctx['terminal'] as Map)['id'] : '';
        final message = [
          description.isEmpty ? objet : description,
          if (_contexte) '— Envoyé depuis ${SupportCentre.application} ${SupportCentre.version}, terminal $terminal'
              '${widget.ecranOrigine.isEmpty ? '' : ', écran ${widget.ecranOrigine}'}.',
        ].join('\n\n');
        final (r, msg) = await f(
          objet: tronquer(objet, 250),
          message: message,
          moduleConcerne: _module,
          urgence: urgenceDe(_gravite),
          pieces: [if (_capture != null) _capture!],
        );
        contactMsg = switch (r) {
          SupportReponse.ok => msg.isNotEmpty ? msg : 'Demande de contact transmise au support.',
          SupportReponse.routeAbsente => 'Demande de contact indisponible sur ce serveur.',
          SupportReponse.session => 'Demande de contact non envoyée : reconnectez-vous.',
          SupportReponse.rejete => msg.isNotEmpty ? msg : 'Demande de contact refusée par le serveur.',
          SupportReponse.echec => 'Demande de contact non envoyée : serveur injoignable. Réessayez plus tard.',
        };
      }
    }
    if (!mounted) return;
    setState(() => _envoi = false);
    final texte = switch (issue) {
      SupportIssue.envoye => 'Merci : votre signalement a été transmis au centre de support.',
      SupportIssue.rejete => 'Le serveur a refusé le signalement. Contactez le support par téléphone.',
      _ => _c.routeAbsente
          ? 'Ce serveur n\'a pas encore le centre de support : le signalement est gardé sur le terminal '
              'et sera envoyé dès que possible.'
          : 'Le serveur ne répond pas : le signalement est gardé sur le terminal et sera envoyé '
              'automatiquement au retour de la connexion.',
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('support_confirmation'),
        icon: Icon(issue == SupportIssue.envoye ? Icons.check_circle : Icons.schedule,
            color: issue == SupportIssue.envoye ? Pal.green : Pal.amber, size: 40),
        title: Text(issue == SupportIssue.envoye ? 'Signalement envoyé' : 'Signalement enregistré'),
        content: Text([texte, if (contactMsg != null) contactMsg].join('\n\n')),
        actions: [ElevatedButton(style: navyButton, onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );
    if (mounted) Navigator.of(context).pop(issue);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signaler un problème'), backgroundColor: Pal.navy, foregroundColor: Colors.white),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                key: const Key('support_objet'),
                controller: _objet,
                maxLength: 200,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Objet *', hintText: 'Ex. : le ticket ne s\'imprime pas', border: OutlineInputBorder()),
                validator: (v) => (v ?? '').trim().isEmpty ? 'L\'objet est obligatoire' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('support_description'),
                controller: _description,
                minLines: 3,
                maxLines: 8,
                maxLength: 3000,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Ce que vous faisiez, ce qui s\'est passé. Pas de nom de patient ni de mot de passe.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const Key('support_module'),
                value: _module,
                decoration: const InputDecoration(labelText: 'Module concerné', border: OutlineInputBorder()),
                items: [for (final m in modulesSupport) DropdownMenuItem(value: m, child: Text(m))],
                onChanged: (v) => setState(() => _module = v ?? 'MOBILE'),
              ),
              const SizedBox(height: 12),
              const Text('Gravité', style: TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                key: const Key('support_gravite'),
                segments: [
                  for (final e in gravitesSupport.entries) ButtonSegment(value: e.key, label: Text(e.value)),
                ],
                selected: {_gravite},
                onSelectionChanged: (s) => setState(() => _gravite = s.first),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const Key('support_contexte'),
                contentPadding: EdgeInsets.zero,
                value: _contexte,
                onChanged: (v) => setState(() => _contexte = v ?? true),
                title: const Text('Joindre le contexte technique'),
                subtitle: const Text('Version, terminal, utilisateur, écran et dernières actions (sans paramètres ni données patient).'),
              ),
              SwitchListTile(
                key: const Key('support_contact'),
                contentPadding: EdgeInsets.zero,
                value: _contact,
                onChanged: (v) => setState(() => _contact = v),
                title: const Text('Être recontacté par le support'),
                subtitle: const Text('Envoie aussi une demande de contact (e-mail au support), avec une capture si besoin.'),
              ),
              if (_contact)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('support_capture'),
                    onPressed: _choisirCapture,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(_capture == null ? 'Joindre une capture d\'écran' : 'Capture : ${_capture!.nom}'),
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                key: const Key('support_envoyer'),
                style: navyButton,
                onPressed: _envoi ? null : _envoyer,
                icon: _envoi
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: const Text('Envoyer au centre de support'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
