// lib/images/images_reglages_page.dart
// Réglages › Images des produits (code administrateur) : affichage, vignettes dans les ventes,
// taille du cache, préchargement, « Photo du produit » (désactivé par défaut).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/horsligne/activite_app.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/images/images_reglages.dart';
import 'package:prestige_vente_app/images/produit_images.dart';
import 'package:prestige_vente_app/parametres/parametres_widgets.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

String imagesSummary(ImagesConfig c) {
  if (!c.actif) return 'Désactivées (pictogrammes)';
  final cap = switch (ProduitImages.instance.capacite) {
    CapaciteImages.non => ' · serveur sans images',
    _ => '',
  };
  return 'Du serveur · cache ${c.cacheMo} Mo${c.vignettesVentes ? ' · vignettes en vente' : ''}$cap';
}

class ImagesPage extends StatefulWidget {
  final ProduitImages? images;
  const ImagesPage({super.key, this.images});

  @override
  State<ImagesPage> createState() => _ImagesPageState();
}

class _ImagesPageState extends State<ImagesPage> {
  ProduitImages get _s => widget.images ?? ProduitImages.instance;
  ImagesConfig get _c => ImagesReglages.courant.value;

  Future<void> _set(ImagesConfig c) async {
    await ImagesReglages.enregistrer(c);
    if (mounted) setState(() {});
  }

  String _mo(int octets) => '${(octets / (1024 * 1024)).toStringAsFixed(octets < 10 * 1024 * 1024 ? 1 : 0)} Mo';

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final card = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Les images viennent du serveur Prestige (fiche produit). Sans images sur le serveur, la borne et les listes '
            'gardent leurs pictogrammes. Les images vues sont gardées sur l\'appareil pour l\'affichage hors ligne.',
            style: TextStyle(color: Pal.muted, fontSize: 13.5),
          ),
        ),
        SwitchListTile(
          key: const ValueKey('images-actif'),
          title: const Text('Afficher les images des produits'),
          value: c.actif,
          onChanged: (v) => _set(c.copyWith(actif: v)),
        ),
        SwitchListTile(
          key: const ValueKey('images-vignettes-ventes'),
          title: const Text('Vignettes dans les listes de vente'),
          subtitle: const Text('Désactivé par défaut pour ne pas ralentir la saisie.'),
          value: c.vignettesVentes,
          onChanged: c.actif ? (v) => _set(c.copyWith(vignettesVentes: v)) : null,
        ),
        ListTile(
          title: const Text('Taille maximale du cache'),
          subtitle: Text('Utilisé : ${_mo(_s.tailleCache)} · ${_s.nbImages} image${_s.nbImages > 1 ? 's' : ''}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                key: const ValueKey('images-cache-moins'),
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: c.cacheMo > ImagesConfig.cacheMoMin ? () => _set(c.copyWith(cacheMo: c.cacheMo - 100)) : null),
            Text('${c.cacheMo} Mo', key: const ValueKey('images-cache-valeur'), style: const TextStyle(fontWeight: FontWeight.w700)),
            IconButton(
                key: const ValueKey('images-cache-plus'),
                icon: const Icon(Icons.add_circle_outline),
                onPressed: c.cacheMo < ImagesConfig.cacheMoMax ? () => _set(c.copyWith(cacheMo: c.cacheMo + 100)) : null),
          ]),
        ),
        SwitchListTile(
          key: const ValueKey('images-prechargement'),
          title: const Text('Précharger les images après la connexion'),
          subtitle: const Text('Parcourt la copie locale du catalogue, en pause quand l\'appli est utilisée.'),
          value: c.prechargement,
          onChanged: c.actif ? (v) => _set(c.copyWith(prechargement: v)) : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(spacing: 10, runSpacing: 8, children: [
            OutlinedButton.icon(
              key: const ValueKey('images-precharger'),
              onPressed: !c.actif || _s.prechargeEnCours
                  ? null
                  : () async {
                      setState(() {});
                      await _s.prechargerCatalogue(HorsLigne.instance.store, occupe: () => ActiviteApp.occupee);
                      if (mounted) setState(() {});
                    },
              icon: const Icon(Icons.download),
              label: Text(_s.prechargeEnCours ? 'Préchargement…' : 'Précharger maintenant'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('images-vider'),
              onPressed: () async {
                await _s.vider();
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Vider le cache'),
            ),
          ]),
        ),
        const Divider(height: 1),
        SwitchListTile(
          key: const ValueKey('images-photo-terminal'),
          title: const Text('« Photo du produit » depuis le terminal'),
          subtitle: const Text('Bouton dans la fiche produit, pour les utilisateurs ayant le droit de modifier les images. '
              'Désactivé en attendant les précisions de la pharmacie.'),
          value: c.photoTerminal,
          onChanged: (v) => _set(c.copyWith(photoTerminal: v)),
        ),
      ]),
    );
    return RubriquePage(title: 'Images des produits', subtitle: imagesSummary(c), children: [card]);
  }
}
