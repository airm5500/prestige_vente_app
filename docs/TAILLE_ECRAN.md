# Taille de l'écran — `lib/ui/taille_ecran.dart`

*Prestige Mobile 4.0.1. Module repris **tel quel** de Prestige Inventaire 4.13.1 (même fichier, même logique,
mêmes facteurs, même seuil, même clé enregistrée) : un seul fichier Dart, sans dépendance autre que `flutter` et
`shared_preferences`. Toute évolution doit être reportée dans les deux applications.*

## 1. Le besoin

Sur les petits terminaux (Sunmi V2s 5,45″ : 720 × 1440 px, densité 2 → **360 × 720 dp** ; Sunmi V3 / V3H / V3mix :
1080 × 1920 px, densité 3 → **360 × 640 dp**), les écrans conçus pour un téléphone de 390 × 844 dp manquent de place,
surtout en hauteur (vente avec le clavier ouvert, fiche produit, réserve…). Un **réglage unique** réduit toute
l'interface, sans retoucher aucun écran :

| Taille | Facteur | Surface vue par l'application sur un V2s | Effet |
|---|---|---|---|
| **Automatique** (défaut) | 1,0, ou 0,9 sur un petit écran | 400 × 800 dp (Compact appliqué) | taille définie par Android ; **Compact sur un petit écran** |
| **Compact** | 0,9 | 400 × 800 dp | tout est 10 % plus petit |
| **Très compact** | 0,8 | 450 × 900 dp | tout est 20 % plus petit |

### Automatique sur les petits écrans

`TailleEcranReglage.petitEcran(taille)` : écran **petit** si son **côté long < 740 dp** ou son **côté court
< 340 dp**, mesuré sur l'écran réel (avant réduction), quelle que soit l'orientation.
`TailleEcranReglage.effective(choix, taille)` : Automatique → Compact sur un petit écran ; **Compact et Très compact
(choix manuels) restent prioritaires**.

| Appareil | Taille logique | Résultat |
|---|---|---|
| Sunmi V2s 720 × 1440, ×2 | 360 × 720 dp | Compact (400 dp vus) |
| Sunmi V3 / V3H / V3mix 1080 × 1920, ×3 ; téléphone 720 × 1280, ×2 | 360 × 640 dp | Compact |
| Téléphone 1080 × 2400, ×2,625 / ×2,75 | 411 × 914 / 393 × 873 dp | **normale** (rien ne change) |
| Téléphone 1080 × 2400, ×3 (Samsung) | 360 × 800 dp | **normale** |
| Tablettes | 1280 × 800 dp… | **normale** |

Les réglages affichent alors « **Automatique (Compact appliqué sur cet écran)** ».

## 2. Dans Prestige Mobile

- **Branchement** (`lib/main.dart`) : `await TailleEcranReglage.charger()` avant `runApp` ; `RacineTailleEcran`
  enveloppe la **seule** `MaterialApp` de l'application, **sous** le `MultiProvider` (session, ventes, file d'envoi
  hors ligne gardées lors de « Relancer maintenant »). Le bandeau hors ligne, les messages de connexion, le thème
  tablette (`builder` de `MaterialApp`), toutes les fenêtres, feuilles et messages sont réduits avec l'interface.
- **Réglage** (`lib/parametres/taille_ecran_reglage.dart`, `TailleEcranSetting`), dans les **deux interfaces** :
  - nouvelle : **Réglages › Apparence › Affichage** (code administrateur des Réglages, gardé une fois saisi pendant la
    visite) ;
  - d'origine : **Configuration › Personnalisation** (code administrateur, `PinCodeDialog`).
  Choix enregistré pour le **prochain lancement** ; la fenêtre qui suit propose « **Plus tard** » ou « **Relancer
  maintenant** » (retour au premier écran, interface reconstruite ; la session reste ouverte).

## 3. Compatibilité vérifiée

| Élément | Effet de la réduction | Vérifié par |
|---|---|---|
| **Impression Sunmi** (ticket de vente, prévente, assurance, borne) | **Aucun** : le ticket est envoyé en commandes de l'imprimante (`printText`, `printQRCode`, `printBarCode`, `lineWrap`), mis en page selon la largeur du papier (58 / 80 mm). Aucun code d'impression ni de PDF ne lit `MediaQuery`, la densité ou une capture d'écran. Seul l'**aperçu** du mode test (fenêtre à l'écran) est réduit. | `taille_ecran_test` (garde-fou sur les sources) |
| **Douchette Sunmi** | Aucun : événements du clavier matériel (et saisie directe dans le champ), indépendants de l'affichage. | `ergonomie_taille_ecran_test` (douchette sur l'accueil réduit → fiche produit) |
| **Clavier système, vente** | `viewInsets` ramenés à l'échelle : le pied « clavier ouvert » (total, Prévente, Encaisser) reste posé exactement sur le clavier réel. | `taille_ecran_test`, `ergonomie_taille_ecran_test` (vente V2s clavier ouvert) |
| **Caméra** (scan DataMatrix / code-barres, photo d'ordonnance, photo de pointage) | Aperçu réduit comme le reste (widget `Texture`, pas de vue native). Le cadre de capture est calculé en **proportions** de l'aperçu : la zone découpée dans la photo est la même à toutes les tailles ; la photo garde la résolution du capteur. | `taille_ecran_test` (géométrie), écrans photo de pointage dans l'ergonomie |
| **Lecteur d'empreinte** | Aucun : fenêtre native Android, hors interface Flutter. | — |
| **Borne libre-service** | Dans la même `MaterialApp` : suit le réglage du terminal (en général une tablette : taille normale en Automatique). | `ergonomie_taille_ecran_test` (tablette inchangée) |
| **Images des produits** | Taille de décodage = dp × densité effective = pixels réels (ni flou, ni surdimensionné). | `taille_ecran_test` |
| **Captures d'écran du support** | Choisies dans la galerie (captures système) : résolution réelle de l'écran, non concernées. | — |
| **Disposition tablette** (`Responsive`, seuils 600 / 900 dp) | Un V2s en Compact voit 400 dp : reste « téléphone ». | ergonomie |

## 4. Tests

- `test/taille_ecran_test.dart` : facteurs, seuil (V2s, V3, téléphones 1080 × 2400, Samsung 360 × 800 dp, tablettes,
  limites exactes), choix manuel prioritaire, persistance et valeur abîmée, données d'écran (taille, marges, clavier,
  densité), touchers justes, clavier, impression / PDF / caméra / vues natives / `MaterialApp` unique.
- `test/ergonomie_taille_ecran_test.dart` : écrans principaux sur V2s en Automatique, Compact et Très compact (texte
  1,0 et 1,3) — interface qui remplit l'écran, aucun débordement, cibles, contraste, charte, champ au-dessus du
  clavier ; vente clavier ouvert ; douchette ; autres appareils en Automatique ; réglage dans les deux interfaces
  (code, Plus tard, Relancer maintenant).
- `test/ergonomie_test.dart` : la matrice existante tourne désormais avec le réglage par défaut (Automatique) : les
  deux Sunmi et le téléphone 360 × 640 dp y sont en Compact. Cibles tactiles exigées : 48 dp **de l'interface**
  (43,2 dp réels en Compact, 38,4 en Très compact : réduction voulue par l'administrateur).

## 5. Limites connues

- Une vue native Android ne serait pas réduite (il n'y en a aucune ; un test le vérifie).
- En Très compact, les textes de 12 dp deviennent 9,6 dp réels : à réserver aux petits terminaux.
