// lib/connexion/derniers_utilisateurs.dart
// Grille des 6 derniers utilisateurs de l'appareil (option C « Qui êtes-vous ? ») + tuile « Autre ».
// SANS DÉFILEMENT : la hauteur des tuiles est calculée pour que toute la grille tienne dans la place
// disponible (360 × 800 compris : 2 colonnes × 4 rangées) ; 3 colonnes à partir de 600 px, 4 à partir de 900 px.
// Chaque tuile : initiales en couleur, nom, RÔLE, dernière connexion ; appui long = retirer de la liste.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/connexion/connexion_commun.dart';
import 'package:prestige_vente_app/connexion/connexion_reglages.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

class GrilleUtilisateurs extends StatelessWidget {
  final List<DernierUtilisateur> utilisateurs;
  final ValueChanged<DernierUtilisateur> onChoisir;
  final ValueChanged<DernierUtilisateur>? onRetirer;
  final VoidCallback onAutre;
  final DateTime? maintenant;

  const GrilleUtilisateurs({
    super.key,
    required this.utilisateurs,
    required this.onChoisir,
    required this.onAutre,
    this.onRetirer,
    this.maintenant,
  });

  static const ecart = 10.0;

  static int colonnes(double largeur) => largeur >= 900 ? 4 : (largeur >= 600 ? 3 : 2);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final liste = utilisateurs.take(DerniersUtilisateurs.maximum).toList();
        final n = liste.length + 1;
        final cols = colonnes(c.maxWidth);
        final rangees = (n / cols).ceil();
        final dispo = c.maxHeight.isFinite ? c.maxHeight : 4 * 132.0;
        final hauteur = ((dispo - ecart * (rangees - 1)) / rangees).clamp(56.0, 132.0);
        final tuiles = <Widget>[
          for (final u in liste)
            _Tuile(
                utilisateur: u,
                hauteur: hauteur,
                maintenant: maintenant,
                onTap: () => onChoisir(u),
                onLongPress: onRetirer == null ? null : () => onRetirer!(u)),
          _TuileAutre(hauteur: hauteur, onTap: onAutre),
        ];
        final grille = Column(mainAxisSize: MainAxisSize.min, children: [
          for (var r = 0; r < rangees; r++) ...[
            if (r > 0) const SizedBox(height: ecart),
            Row(children: [
              for (var k = 0; k < cols; k++) ...[
                if (k > 0) const SizedBox(width: ecart),
                Expanded(child: r * cols + k < tuiles.length ? tuiles[r * cols + k] : SizedBox(height: hauteur)),
              ],
            ]),
          ],
        ]);
        // Repli seulement si la place manque vraiment (très grand texte, écran minuscule).
        final total = rangees * hauteur + ecart * (rangees - 1);
        return total <= dispo + 0.5 ? Align(alignment: Alignment.topCenter, child: grille) : SingleChildScrollView(child: grille);
      });
}

/// Initiales en couleur (mêmes pastilles que les grossistes).
class AvatarUtilisateur extends StatelessWidget {
  final String nom;
  final double taille;
  const AvatarUtilisateur(this.nom, {super.key, this.taille = 48});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = GrossisteAvatar.colorsFor(nom);
    return Container(
      width: taille,
      height: taille,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(taille * 0.28)),
      child: Text(GrossisteAvatar.initials(nom), style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: taille * 0.4)),
    );
  }
}

class _Tuile extends StatelessWidget {
  final DernierUtilisateur utilisateur;
  final double hauteur;
  final DateTime? maintenant;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _Tuile({required this.utilisateur, required this.hauteur, required this.onTap, this.onLongPress, this.maintenant});

  @override
  Widget build(BuildContext context) {
    final t = Teintes.of(context);
    final quand = quandConnecte(utilisateur.date, maintenant: maintenant);
    final role = utilisateur.role.isEmpty ? 'Utilisateur' : utilisateur.role;
    final avatar = hauteur >= 108 ? 46.0 : (hauteur >= 84 ? 36.0 : 28.0);
    return Semantics(
      button: true,
      label: '${utilisateur.nomAffiche}, $role, dernière connexion $quand',
      hint: onLongPress == null ? null : 'Appui long pour retirer de la liste',
      excludeSemantics: true,
      child: Material(
        color: t.champ,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: t.bordure.withValues(alpha: 0.7))),
        child: InkWell(
          key: Key('utilisateur_${utilisateur.login}'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox(
            height: hauteur,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AvatarUtilisateur(utilisateur.nomAffiche, taille: avatar),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(utilisateur.nomAffiche,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: t.texte)),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(role,
                        key: Key('role_${utilisateur.login}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: identical(t, Teintes.sombre) ? const Color(0xFFFCD34D) : const Color(0xFF8A5300))),
                  ),
                  Text(quand, style: TextStyle(fontSize: 12, color: t.attenue)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TuileAutre extends StatelessWidget {
  final double hauteur;
  final VoidCallback onTap;
  const _TuileAutre({required this.hauteur, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Teintes.of(context);
    final avatar = hauteur >= 108 ? 46.0 : (hauteur >= 84 ? 36.0 : 28.0);
    return Semantics(
      button: true,
      label: 'Autre utilisateur : saisir l\'identifiant',
      excludeSemantics: true,
      child: Material(
        color: t.champ,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: t.bordure.withValues(alpha: 0.7))),
        child: InkWell(
          key: const Key('utilisateur_autre'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            height: hauteur,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: avatar,
                    height: avatar,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(avatar * 0.28), border: Border.all(color: t.attenue, width: 1.5)),
                    child: Icon(Icons.add, color: t.attenue),
                  ),
                  const SizedBox(height: 6),
                  Text('Autre', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: t.texte)),
                  Text('saisir l\'identifiant', style: TextStyle(fontSize: 12, color: t.attenue)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
