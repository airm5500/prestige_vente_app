# Prestige Mobile V3 5.2.0+52 : présentation de l'accueil au choix

Même application (`com.dici.prestigemobile.v3`, « Prestige Mobile V3 »), même icône que la 5.1.0+51. Aucun
changement de contrat avec le serveur, aucune requête de plus : le choix est enregistré sur l'appareil.

## Demande du pharmacien

Dans les paramètres, pouvoir choisir et enregistrer la présentation de l'accueil parmi trois :

| Présentation | Description |
|---|---|
| **Actuelle** (par défaut) | l'accueil d'aujourd'hui, inchangé : favoris, cartes blanches ; suit la présentation A / B / C des menus |
| **Metro mosaïque** | fond bleu nuit, tuiles de couleur pleine, icône en haut à gauche, libellé en bas à gauche ; les 2 premiers favoris en grand (2×2) avec le libellé complet en sous-titre |
| **Metro bandes** | fond blanc, bandes de couleur pleine de 58 dp, largeur selon le libellé, rangées justifiées, ordre de l'accueil |

## Où le choisir

**Réglages › Apparence › Accueil › Présentation de l'accueil**, sous « Organiser l'accueil » : trois choix, chacun avec
un petit aperçu et une description. Comme la présentation des menus, le choix est réservé au compte administrateur ;
les autres comptes voient la présentation en place (« Modifiable par le compte administrateur »).

- Enregistré sur l'appareil (préférence `presentation_accueil_v1`), appliqué **tout de suite** (l'accueil change
  dès le retour, sans relancer), relu au lancement (conservé au redémarrage).
- Mise à jour depuis la 5.1.0 : aucune valeur enregistrée → « Actuelle » ; les autres préférences (présentation des
  menus, favoris, ordre, menus masqués) ne sont pas touchées. Valeur inconnue → « Actuelle ».
- « Actuelle » est identique au pixel près à l'accueil de la 5.1.0, en présentation A, B ou C.

## Metro mosaïque

- Grille de 4 colonnes sur le terminal, 6 sur une tablette en portrait ; en paysage, les familles se répartissent en
  deux groupes de 4 colonnes côte à côte.
- Tuile 1×1 si le libellé tient sur une ligne, sinon plus large (2 lignes au plus) ; petit écran ou grand texte : une
  rangée de plus plutôt qu'un libellé coupé. Les trous sont comblés (rangées justifiées, tuile voisine élargie).
- Les deux premiers favoris visibles en 2×2 (plus larges si le titre ou le libellé complet ne tiennent pas).

## Metro bandes

- Bandes de 58 dp de haut, largeur selon le libellé, rangées justifiées (la place libre est partagée), ordre strict de
  l'accueil ; fond blanc, titres de famille en petites capitales grises.

## Commun aux deux présentations Metro

- En-tête (état du serveur, utilisateur, recherche, scan, cloche, ⋮, déconnexion) et barre du bas conservés.
- Familles, cadenas des menus protégés (code administrateur demandé), pastilles des compteurs (préventes, BL).
- Couleurs des menus assombries automatiquement (même teinte) pour un contraste ≥ 4,5:1 avec le texte blanc.
- Mise en page calculée sur la largeur réelle de l'écran et le facteur de texte : libellés jamais tronqués, jamais
  coupés au milieu d'un mot, jamais sur 3 lignes (texte ×1,0 et ×1,3, de 320 dp à la tablette).
- Mêmes menus que l'accueil actuel : droits du compte, menus masqués par « Organiser l'accueil », « Borne » de
  l'administrateur. Appui long : favoris et « Organiser l'accueil… ».

## Fichiers

- `lib/accueil/accueil_metro.dart` (nouveau) : corps Metro (mosaïque, bandes), placement `MetroGrille`, couleurs
  `MetroCharte`.
- `lib/accueil/accueil_screen.dart` : présentation de l'accueil écoutée, en-tête A réutilisé ; `presentationAccueil`
  imposable (tests).
- `lib/widgets/presentation_style.dart` : `AccueilPresentation` et `PresentationPrefs.loadAccueil` / `saveAccueil`
  (à côté de la présentation des menus, qui ne change pas).
- `lib/parametres/rubriques_pages.dart` : `PresentationAccueilSetting`, `ApercuAccueil`.
- `lib/main.dart` : présentation lue au lancement (pas d'image de l'ancienne présentation avant la nouvelle).

## Tests

`accueil_metro` (écrans), `accueil_metro_e2e`, `accueil_metro_ergonomie`, `performance/accueil_metro_perf`,
`accueil_metro_garde` (non-régression) ; version : `v3_identite`, `v501_version_gradle`. Outil hors CI :
`test/outils/captures_metro_test.dart` (captures des 3 présentations et du réglage, terminal et tablette).
