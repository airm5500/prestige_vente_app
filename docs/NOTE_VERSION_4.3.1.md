# Prestige Mobile 4.3.1+17 — boîte déjà scannée refusée à la réception (D18)

Décision du pharmacien (15/10/2026) : une boîte dont le numéro de série a déjà été scanné est **refusée**.

## Réception BL (ajout de lot, `commande/add-lot`)

- Quand le code lu est un **DataMatrix GS1 avec numéro de série (AI 21) et GTIN (AI 01)**, l'application envoie
  `serie` et `gtin` avec le lot. Sans numéro de série (autre DataMatrix, saisie à la main, photo de l'étiquette) :
  rien de plus n'est envoyé, comme avant.
- Refus du serveur `code:"SERIE_DEJA_CONSOMMEE"` → fenêtre **« Boîte déjà scannée »** : aucune quantité ajoutée, la
  ligne repart à zéro, la boîte suivante peut être scannée aussitôt.
- **Hors ligne** : `serie` et `gtin` sont gardés dans la file (stockage privé de l'application) et envoyés à la
  synchronisation ; une boîte déjà scannée donne une ligne **refusée** lisible (« Boîte déjà scannée (lot …) :
  aucune quantité ajoutée ») dans le rapport, jamais renvoyée.
- **Ancien serveur** (`dev`, sans D18) : les champs inconnus sont ignorés (JSON-B, réglage par défaut de Payara ;
  `JaxRsConfig` n'enregistre aucun autre fournisseur JSON) ; par prudence, un refus 400 d'un serveur qui les
  refuserait renvoie **le même lot sans série** (une seule fois, jamais sans série au départ).
- **Aucun numéro de série dans les journaux** : ni journal du terminal, ni rapport, ni messages ; masqué (`***`)
  dans le journal HTTP de la console.

## Corrigé au passage

- **ANO-12** : texte de progression de la réception qui débordait sur 360 dp avec un texte agrandi (×1,3).

## Tests

`reception_bl_test` (D18 : série envoyée, boîte rescannée refusée, boîte suivante acceptée, sans série ; ergonomie
360×640 dp texte ×1,3), `reponse_serveur_test` (lecture AI 21, corps et journal masqué, serveur à jour, ancien
serveur et 400, délai dépassé, file hors ligne sans boucle).
