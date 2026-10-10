# Balises de retour arrière — refonte des ventes

Chaque étape de la refonte des ventes (Pré-vente, Assurance, Carnet) a un point de retour.
Les identifiants ci-dessous sont des commits de la branche `pres-/tender-thompson-ang0ls`
(les étiquettes git ne peuvent pas être poussées depuis l'environnement de travail ; le commit suffit).

| Balise | Commit | Contenu |
|---|---|---|
| `ventes-v0-avant-refonte` | `19760fe30a97241a9b7964c28ca7ff7625cc458a` | Ventes d'origine (avant toute modification des ventes). |

## Revenir en arrière

1. **Sans réinstaller** : Configuration → désactiver « Ventes : nouvelle version ».
   Les écrans d'origine (dossiers `lib/screens/pre_vente`, `assurance_sale`, `carnet_sale`)
   ne sont pas modifiés par la refonte.
2. **Version précise** : reconstruire l'APK depuis le commit de la balise voulue
   (`git checkout <commit>` puis la CI ou `flutter build apk`), ou réinstaller l'APK conservée de l'étape.
