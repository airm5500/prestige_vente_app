// lib/parametres/nom_appareil_reglage.dart
// « Nom de cet appareil » (en-tête X-Poste, voir lib/serveur/nom_appareil.dart).
//  - 4.7.0 : champ des réglages (Licence & appareil), aperçu du nom tel que Prestige l'enregistrera.
//  - 4.7.1 (décision du pharmacien) : nom OBLIGATOIRE. Sans nom enregistré, l'étape « Nom de cet appareil » est
//    imposée au lancement (après la configuration du serveur) et les réglages ne se quittent pas ; le champ est
//    pré-rempli avec la marque et le modèle : un appui sur « Enregistrer » suffit. Plus de « Plus tard ».
//    Jamais montré aux clients : pas d'étape au lancement d'une borne (réglée par l'administrateur).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// 4.7.1 : où le nom est gardé (préférences de l'application) : il reste après une mise à jour ; une désinstallation
/// l'efface (sauf restauration par la sauvegarde Android, qui demande les services Google) : il est alors redemandé.
const String mentionConservationNomAppareil = 'Gardé sur cet appareil : conservé lors des mises à jour de l\'application. '
    'Après une désinstallation, il faut le saisir de nouveau.';

/// Message quand on veut quitter sans nom enregistré.
const String messageNomAppareilObligatoire = 'Saisissez le nom de cet appareil avant de quitter les réglages.';

/// Message d'un nom vide (ou sans caractère permis).
const String messageNomAppareilVide = 'Saisissez le nom de cet appareil (lettres, chiffres, espace, point, tiret, souligné).';

/// Aperçu du nom enregistré par Prestige pour une saisie.
String apercuNomAppareil(String saisie) {
  final propre = nettoyerNomPoste(saisie);
  if (propre != null) return 'Enregistré dans Prestige : « $propre »';
  return saisie.trim().isEmpty ? 'Nom obligatoire.' : 'Aucun caractère permis : saisissez un autre nom.';
}

/// Champ « Nom de cet appareil » : pré-rempli (nom enregistré, sinon marque et modèle), aperçu, Enregistrer.
class ChampNomAppareil extends StatefulWidget {
  final NomAppareil? nom;

  /// Appelé après l'enregistrement (nom envoyé désormais).
  final ValueChanged<String>? enregistre;
  const ChampNomAppareil({super.key, this.nom, this.enregistre});

  @override
  State<ChampNomAppareil> createState() => ChampNomAppareilState();
}

class ChampNomAppareilState extends State<ChampNomAppareil> {
  late final NomAppareil _n = widget.nom ?? NomAppareil.instance;
  late final _champ = TextEditingController(text: _n.nomEnregistre ? _n.saisi : (_n.parDefaut ?? ''));
  bool _envoi = false;
  String? _erreur;

  @override
  void dispose() {
    _champ.dispose();
    super.dispose();
  }

  /// Enregistre la saisie (nettoyée) ; null si rien de permis n'a été saisi (rien n'est changé).
  Future<String?> enregistrer() async {
    if (_envoi) return null;
    setState(() => _envoi = true);
    final e = await _n.enregistrer(_champ.text);
    if (!mounted) return e;
    setState(() {
      _envoi = false;
      _erreur = e == null ? messageNomAppareilVide : null;
      if (e != null) _champ.text = e;
    });
    if (e != null) widget.enregistre?.call(e);
    return e;
  }

  @override
  Widget build(BuildContext context) {
    final defaut = _n.parDefaut;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      TextField(
        key: const Key('nom_appareil_champ'),
        controller: _champ,
        enabled: !_envoi,
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => setState(() => _erreur = null),
        onSubmitted: (_) => enregistrer(),
        decoration: InputDecoration(
          labelText: 'Nom de cet appareil',
          hintText: defaut ?? 'Ex. Caisse mobile 1',
          helperText: 'Lettres, chiffres, espace, point, tiret, souligné ; $longueurMaxPoste caractères au plus.',
          helperMaxLines: 3,
          errorText: _erreur,
          errorMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 6),
      Text(apercuNomAppareil(_champ.text), key: const Key('nom_appareil_apercu'), style: const TextStyle(fontSize: 13, color: Pal.ink)),
      const SizedBox(height: 4),
      const Text(mentionConservationNomAppareil, key: Key('nom_appareil_conservation'), style: TextStyle(fontSize: 12, color: Pal.muted)),
      const SizedBox(height: 6),
      Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 4, children: [
        if (defaut != null && _champ.text != defaut)
          TextButton(
            key: const Key('nom_appareil_defaut'),
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
            onPressed: _envoi ? null : () => setState(() => _champ.text = defaut),
            child: Text('Reprendre « $defaut »'),
          ),
        FilledButton(
          key: const Key('nom_appareil_enregistrer'),
          style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
          onPressed: _envoi ? null : enregistrer,
          child: const Text('Enregistrer'),
        ),
      ]),
    ]);
  }
}

/// Carte « Nom de cet appareil » OBLIGATOIRE, en tête des réglages tant qu'aucun nom n'est enregistré.
class CarteNomAppareilObligatoire extends StatelessWidget {
  final NomAppareil? nom;
  const CarteNomAppareilObligatoire({super.key, this.nom});

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('nom_appareil_obligatoire'),
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4E0),
          border: Border.all(color: const Color(0xFFF2B45A)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Text('Nom de cet appareil (obligatoire)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Pal.ink)),
          const SizedBox(height: 4),
          const Text('Il apparaît dans Prestige (« Ventes terminées ») pour les ventes faites ici. Vérifiez-le, puis Enregistrer.',
              style: TextStyle(fontSize: 13, color: Pal.ink)),
          const SizedBox(height: 10),
          ChampNomAppareil(nom: nom),
        ]),
      );
}

/// Bloque la sortie d'un écran tant qu'aucun nom n'est enregistré (retour Android, geste, bouton de l'en-tête).
class GardeNomAppareil extends StatelessWidget {
  final Widget child;
  final NomAppareil? nom;
  final String message;
  const GardeNomAppareil({super.key, required this.child, this.nom, this.message = messageNomAppareilObligatoire});

  @override
  Widget build(BuildContext context) {
    final n = nom ?? NomAppareil.instance;
    return ListenableBuilder(
      listenable: n,
      builder: (context, _) => PopScope(
        canPop: n.nomEnregistre,
        onPopInvokedWithResult: (aQuitte, _) {
          if (!aQuitte && !n.nomEnregistre) signalerNomAppareilObligatoire(context, message: message);
        },
        child: child,
      ),
    );
  }
}

void signalerNomAppareilObligatoire(BuildContext context, {String message = messageNomAppareilObligatoire}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(key: const Key('nom_appareil_message'), content: Text(message)));
}

/// Étape « Nom de cet appareil » imposée (lancement) : rien d'autre tant qu'un nom n'est pas enregistré.
class NomAppareilObligatoireScreen extends StatelessWidget {
  final NomAppareil? nom;
  const NomAppareilObligatoireScreen({super.key, this.nom});

  @override
  Widget build(BuildContext context) => GardeNomAppareil(
        nom: nom,
        message: 'Saisissez le nom de cet appareil pour continuer.',
        child: Scaffold(
          key: const Key('nom_appareil_etape'),
          backgroundColor: Pal.page,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: Pal.navy,
            foregroundColor: Colors.white,
            title: const Text('Nom de cet appareil'),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  const Text('Donnez un nom à cet appareil, par exemple « Caisse mobile 1 ». Il apparaît dans Prestige '
                      '(« Ventes terminées ») pour les ventes faites ici et distingue deux terminaux du même modèle.'),
                  const SizedBox(height: 16),
                  ChampNomAppareil(nom: nom, enregistre: (_) => Navigator.of(context).pop(true)),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Lancement : impose l'étape tant qu'aucun nom n'est enregistré ; renvoie tout de suite sinon.
Future<void> exigerNomAppareil(BuildContext context, {NomAppareil? nom}) async {
  final n = nom ?? NomAppareil.instance;
  if (n.nomEnregistre || !context.mounted) return;
  await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => NomAppareilObligatoireScreen(nom: n)));
}
