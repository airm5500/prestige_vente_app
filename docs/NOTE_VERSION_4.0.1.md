# Prestige Mobile — note de version 4.0.1 (versionCode 9)

Suite de la 4.0.0+8 (pas encore publiée sur le magasin Sunmi, dernière version publiée : 3.3.1 / 7).
Numérotation : `docs/VERSIONS_SUNMI.md` (+N augmenté de 1 : **4.0.1+9**).

## Nouveauté : taille de l'écran

- Nouveau réglage **« Taille de l'écran »** : *Automatique* (défaut), *Compact* (tout 10 % plus petit), *Très
  compact* (20 %). Repris tel quel de Prestige Inventaire, pour un comportement identique dans les applications
  Prestige.
- **Sur les petits terminaux, Automatique applique Compact d'office** : Sunmi V2s (5,45″), Sunmi V3 / V3H / V3mix
  et téléphones 360 × 640 dp. L'interface y gagne environ 10 % de place (400 dp de large au lieu de 360) : la
  vente avec le clavier ouvert, la fiche produit ou la réserve tiennent mieux à l'écran. Les réglages indiquent
  « Automatique (Compact appliqué sur cet écran) ».
- **Téléphones courants et tablettes : rien ne change** en Automatique.
- Où : **Réglages › Apparence › Affichage** (nouvelle interface) et **Configuration › Personnalisation**
  (interface d'origine). Protégé par le **code administrateur**. Le choix s'applique au prochain lancement, ou
  tout de suite avec « **Relancer maintenant** » (retour à l'accueil, la session reste ouverte).
- **Non concernés** : le ticket imprimé (commandes de l'imprimante Sunmi, mise en page selon le papier 58 / 80 mm),
  la douchette, les photos (scan DataMatrix, ordonnance, pointage : résolution et cadrage inchangés), le lecteur
  d'empreinte.

Détails techniques : `docs/TAILLE_ECRAN.md`.

## Tests

- Nouveaux : `test/taille_ecran_test.dart` (unitaires et compatibilité : seuil, choix manuel, persistance,
  impression, caméra) et `test/ergonomie_taille_ecran_test.dart` (écrans principaux sur Sunmi V2s aux trois tailles,
  vente clavier ouvert, douchette, autres appareils, réglage dans les deux interfaces) ; ajoutés à la CI.
- Adaptés (justification) : `test/ergonomie_test.dart` démarre l'application entière avec le réglage par défaut ;
  sur les petits écrans de la matrice (deux Sunmi, 360 × 640 dp) l'interface est donc en Compact :
  - cibles tactiles exigées à 48 dp **de l'interface** (43,2 dp réels), comme dans Prestige Inventaire ;
  - ANO-06 (pied de vente) et ANO-07 (pastille du sens de la réserve), qui ne se produisaient qu'à 360 dp de large
    avec un texte à 130 %, **n'apparaissent plus sur ces terminaux** ; elles restent sur les téléphones de 360 dp
    à la taille normale : un téléphone 1080 × 2400 densité 3 (360 × 800 dp) a été ajouté à la matrice, et les
    contrôles y sont sautés avec leur identifiant ;
  - la liste des écrans contrôlés est partagée (`test/outils/ecrans_ergonomie.dart`).
