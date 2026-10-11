// lib/borne/borne_widgets.dart
// Éléments visuels de la borne : pictogramme (ou image B2), cartes produit des 3 présentations,
// gros boutons (≥ 56 px), sélecteur de quantité. Contraste élevé (encre foncée sur fond clair).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_produit.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

const double borneToucheMin = 56;

String prixF(int v) => '${Constants.formatNumber(v)} F';

/// Constructeur d'image produit (B2) : image du serveur, ou [picto] tant qu'elle n'est pas connue.
typedef BorneImageBuilder = Widget Function(BorneProduit p, double taille, Widget picto);

/// Image du produit si disponible (B2), sinon pictogramme de la forme sur fond coloré.
class BornePicto extends StatelessWidget {
  final BorneProduit produit;
  final double taille;
  final BorneImageBuilder? image;
  const BornePicto(this.produit, {super.key, this.taille = 56, this.image});

  @override
  Widget build(BuildContext context) {
    final f = produit.forme;
    final (bg, fg) = f.couleurs;
    final picto = Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(taille * 0.18)),
      alignment: Alignment.center,
      child: Icon(f.icon, color: fg, size: taille * 0.52, semanticLabel: f.label),
    );
    if (image == null) return picto;
    return SizedBox(
      width: taille,
      height: taille,
      child: ClipRRect(borderRadius: BorderRadius.circular(taille * 0.18), child: image!(produit, taille, picto)),
    );
  }
}

class BorneBouton extends StatelessWidget {
  final String texte;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool principal;
  final bool contour;
  final bool occupe;
  const BorneBouton(this.texte, {super.key, this.icon, this.onPressed, this.principal = true, this.contour = false, this.occupe = false});

  @override
  Widget build(BuildContext context) {
    final child = occupe
        ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3, color: Pal.onAmber))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 24), const SizedBox(width: 10)],
            Flexible(child: Text(texte, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          ]);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    const min = Size(borneToucheMin * 2, borneToucheMin + 4);
    if (contour) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
            minimumSize: min, foregroundColor: Pal.navy, side: const BorderSide(color: Pal.navy, width: 2), shape: shape),
        child: child,
      );
    }
    return ElevatedButton(
      onPressed: occupe ? null : onPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: min,
        backgroundColor: principal ? Pal.amber : Pal.navy,
        foregroundColor: principal ? Pal.onAmber : Colors.white,
        disabledBackgroundColor: const Color(0xFFDDE3EA),
        disabledForegroundColor: const Color(0xFF5B6B82),
        shape: shape,
        elevation: 0,
      ),
      child: child,
    );
  }
}

/// − quantité + (boutons ≥ 56 px).
class BorneQte extends StatelessWidget {
  final int qte;
  final int max;
  final ValueChanged<int> onChanged;
  final int min;
  final String cle;
  const BorneQte({super.key, required this.qte, required this.max, required this.onChanged, this.min = 1, this.cle = 'qte'});

  @override
  Widget build(BuildContext context) {
    Widget b(IconData i, String tip, VoidCallback? f, String k) => SizedBox(
          width: borneToucheMin,
          height: borneToucheMin,
          child: OutlinedButton(
            key: ValueKey('$cle-$k'),
            onPressed: f,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: Pal.navy,
              side: const BorderSide(color: Pal.navy, width: 1.6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Icon(i, size: 28, semanticLabel: tip),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      b(Icons.remove, 'Moins', qte > min ? () => onChanged(qte - 1) : null, 'moins'),
      SizedBox(
          width: 56,
          child: Text('$qte',
              key: ValueKey('$cle-valeur'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Pal.ink))),
      b(Icons.add, 'Plus', qte < max ? () => onChanged(qte + 1) : null, 'plus'),
    ]);
  }
}

/// Badge « Indisponible ».
class BorneIndispo extends StatelessWidget {
  const BorneIndispo({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(20)),
        child: const Text('Indisponible', style: TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.w700, fontSize: 12.5)),
      );
}

/// Carte produit selon la présentation.
class BorneCarteProduit extends StatelessWidget {
  final BorneProduit produit;
  final BornePresentation presentation;

  /// Grille (cartes verticales) ou ligne (1 colonne).
  final bool grille;
  final VoidCallback onTap;
  final VoidCallback? onAjouter;
  final BorneImageBuilder? image;
  const BorneCarteProduit({
    super.key,
    required this.produit,
    required this.presentation,
    required this.grille,
    required this.onTap,
    this.onAjouter,
    this.image,
  });

  @override
  Widget build(BuildContext context) {
    final p = produit;
    final dispo = p.disponible;
    final nom = Text(p.nom,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: grille ? TextAlign.center : TextAlign.start,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: presentation == BornePresentation.guidee ? 17 : 15, color: Pal.ink));
    final prix = Text(prixF(p.prix), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Pal.navy));
    final ajouter = dispo && onAjouter != null
        ? SizedBox(
            width: borneToucheMin,
            height: borneToucheMin,
            child: IconButton.filled(
              key: ValueKey('borne-ajouter-${p.id}'),
              onPressed: onAjouter,
              style: IconButton.styleFrom(backgroundColor: Pal.amber, foregroundColor: Pal.onAmber),
              icon: const Icon(Icons.add_shopping_cart, semanticLabel: 'Ajouter au panier'),
            ),
          )
        : (dispo ? const SizedBox.shrink() : const BorneIndispo());

    Widget contenu;
    if (grille) {
      contenu = Padding(
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          BornePicto(p, taille: 74, image: image),
          const SizedBox(height: 6),
          Expanded(child: Center(child: nom)),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Flexible(child: prix), ajouter]),
        ]),
      );
    } else if (presentation == BornePresentation.listeRapide) {
      contenu = Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(children: [
          BornePicto(p, taille: 44, image: image),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              nom,
              Text(p.code, style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
            ]),
          ),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [prix, if (!dispo) const BorneIndispo()]),
          if (dispo && onAjouter != null) ...[const SizedBox(width: 6), ajouter],
        ]),
      );
    } else {
      contenu = Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          BornePicto(p, taille: 60, image: image),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [nom, const SizedBox(height: 4), prix])),
          ajouter,
        ]),
      );
    }
    final carte = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(presentation == BornePresentation.listeRapide ? 0 : 16),
      elevation: presentation == BornePresentation.listeRapide ? 0 : 0.8,
      shadowColor: const Color(0x3314213D),
      clipBehavior: Clip.antiAlias,
      child: InkWell(key: ValueKey('borne-produit-${p.id}'), onTap: onTap, child: ConstrainedBox(constraints: const BoxConstraints(minHeight: borneToucheMin + 8), child: contenu)),
    );
    return Opacity(opacity: dispo ? 1 : 0.78, child: carte);
  }
}
