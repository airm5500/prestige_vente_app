# PrestigePOS 1.5.0 (versionCode 14)

Version de PrestigePOS construite avec Prestige Mobile **4.7.0+28** (code partagé) : nom de cet appareil envoyé à
Prestige dans l'en-tête `X-Poste` (détail dans `docs/NOTE_VERSION_4.7.0.md`).

## Pour la borne PrestigePOS

- **Administration → « Nom de cet appareil »** (nouvelle entrée), par exemple « Borne entrée ». Le nom est gardé sur
  l'appareil. Un aperçu montre le nom tel que Prestige l'enregistrera. Ce nom devient le poste de saisie des préventes
  de la borne dans « Ventes terminées », au lieu de l'adresse IP.
- **Nom par défaut** : marque et modèle de l'appareil, lus au lancement par le canal natif existant. S'ils sont
  inconnus et qu'aucun nom n'est saisi, aucun en-tête ne part et Prestige garde le nom réseau.
- **Pas de fenêtre à la première connexion** sur la borne : le client ne doit jamais la voir. Le nom se règle depuis
  l'administration.
- **En-tête sur toutes les requêtes** de la borne : connexion de l'utilisateur borne, recherche, prévente, paiement,
  diagnostic « Tester la borne ».
- Rien d'autre ne change : écran, mobile money, imprimantes, démarrage automatique, « Revenir à Android ».

## Tests

`test/prestigepos/pos_e2e_test.dart` :
- « Borne entrée » envoyé sur toutes les requêtes de la borne ;
- changé en « Borne #2 » dans l'administration : l'aperçu affiche « Borne 2 » ;
- prévente suivante : `X-Poste: Borne%202` sur toutes ses requêtes, création comprise.

## Non-régression

Job `prestige-mobile-identique` : la référence est **4.7.0+28** (commit d3cb268, avant la fusion). Sur l'APK
Prestige Mobile, l'identité ne change que par le numéro de version ; les permissions sont identiques.
