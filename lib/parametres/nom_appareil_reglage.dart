// lib/parametres/nom_appareil_reglage.dart
// 4.7.0 — « Nom de cet appareil » (en-tête X-Poste, voir lib/serveur/nom_appareil.dart) : champ des réglages
// (Licence & appareil) et proposition, une seule fois, après la première connexion (« Plus tard » possible : le nom
// par défaut, marque et modèle, est alors envoyé). Le nom est montré tel que Prestige l'enregistrera.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Aperçu du nom enregistré par Prestige pour une saisie ([saisie] vide : nom par défaut).
String apercuNomAppareil(String saisie, NomAppareil n) {
  final propre = nettoyerNomPoste(saisie);
  if (propre != null) return 'Enregistré dans Prestige : « $propre »';
  final d = n.parDefaut;
  if (saisie.trim().isNotEmpty) {
    return d == null ? 'Aucun caractère permis : Prestige gardera le nom réseau.' : 'Aucun caractère permis : nom par défaut « $d ».';
  }
  return d == null ? 'Sans nom : Prestige gardera le nom réseau de l\'appareil.' : 'Nom par défaut : « $d » (marque et modèle).';
}

/// Champ « Nom de cet appareil » avec l'aperçu du nom enregistré et le bouton Enregistrer.
class ChampNomAppareil extends StatefulWidget {
  final NomAppareil? nom;

  /// Appelé après l'enregistrement (nom envoyé désormais).
  final ValueChanged<String?>? enregistre;
  final bool boutons;
  const ChampNomAppareil({super.key, this.nom, this.enregistre, this.boutons = true});

  @override
  State<ChampNomAppareil> createState() => ChampNomAppareilState();
}

class ChampNomAppareilState extends State<ChampNomAppareil> {
  late final NomAppareil _n = widget.nom ?? NomAppareil.instance;
  late final _champ = TextEditingController(text: _n.saisi);
  bool _envoi = false;

  @override
  void dispose() {
    _champ.dispose();
    super.dispose();
  }

  /// Enregistre la saisie (nettoyée) ; renvoie le nom désormais envoyé.
  Future<String?> enregistrer() async {
    if (_envoi) return _n.effectif;
    setState(() => _envoi = true);
    final e = await _n.enregistrer(_champ.text);
    if (!mounted) return e;
    setState(() {
      _envoi = false;
      _champ.text = _n.saisi;
    });
    widget.enregistre?.call(e);
    return e;
  }

  @override
  Widget build(BuildContext context) {
    final apercu = apercuNomAppareil(_champ.text, _n);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      TextField(
        key: const Key('nom_appareil_champ'),
        controller: _champ,
        enabled: !_envoi,
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) => setState(() {}),
        onSubmitted: widget.boutons ? (_) => enregistrer() : null,
        decoration: InputDecoration(
          labelText: 'Nom de cet appareil',
          hintText: _n.parDefaut ?? 'Ex. Caisse mobile 1',
          helperText: 'Lettres, chiffres, espace, point, tiret, souligné ; $longueurMaxPoste caractères au plus.',
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 6),
      Text(apercu, key: const Key('nom_appareil_apercu'), style: const TextStyle(fontSize: 13, color: Pal.ink)),
      if (widget.boutons) ...[
        const SizedBox(height: 6),
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 4, children: [
          if (_n.saisi.isNotEmpty)
            TextButton(
              key: const Key('nom_appareil_defaut'),
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: _envoi
                  ? null
                  : () {
                      _champ.clear();
                      enregistrer();
                    },
              child: const Text('Nom par défaut'),
            ),
          FilledButton(
            key: const Key('nom_appareil_enregistrer'),
            style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
            onPressed: _envoi ? null : enregistrer,
            child: const Text('Enregistrer'),
          ),
        ]),
      ],
    ]);
  }
}

/// Après la première connexion : propose de nommer l'appareil s'il n'a jamais été nommé ni proposé. Non bloquant.
Future<void> proposerNomAppareil(BuildContext context, {NomAppareil? nom}) async {
  final n = nom ?? NomAppareil.instance;
  if (n.dejaPropose || !context.mounted) return;
  await n.marquerPropose();
  if (!context.mounted) return;
  final cle = GlobalKey<ChampNomAppareilState>();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('nom_appareil_proposition'),
      title: const Text('Nom de cet appareil'),
      scrollable: true,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Ce nom apparaît dans Prestige (« Ventes terminées ») pour les ventes faites ici. '
            'Donnez un nom à chaque terminal, par exemple « Caisse mobile 1 ».'),
        const SizedBox(height: 12),
        ChampNomAppareil(key: cle, nom: n, boutons: false),
      ]),
      actions: [
        TextButton(key: const Key('nom_appareil_plus_tard'), onPressed: () => Navigator.of(ctx).pop(), child: const Text('Plus tard')),
        FilledButton(
          key: const Key('nom_appareil_valider'),
          onPressed: () async {
            await cle.currentState?.enregistrer();
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
}
