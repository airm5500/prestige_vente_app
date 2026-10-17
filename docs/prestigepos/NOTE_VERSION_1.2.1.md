# PrestigePOS 1.2.1 (versionCode 7)

Version de PrestigePOS construite avec Prestige Mobile **4.5.0+21** (code partagé).

## Venu de Prestige Mobile 4.5.0

Prestige Mobile 4.5.0 ajoute la construction pour iPhone et iPad (TestFlight) : voir `docs/NOTE_VERSION_4.5.0.md`
et `docs/ios/README.md`. Le code partagé reçoit une **couche de capacités de la plateforme**
(`lib/plateforme/capacites.dart`) qui masque sur iOS l'imprimante Sunmi, l'empreinte, le NFC, la borne et le
pointage local.

Pour PrestigePOS (Android) : **rien ne change**. Sur Android toutes les capacités restent actives : même borne,
même imprimante Sunmi, mêmes menus et réglages, mêmes canaux natifs. Le dossier `android/` de Prestige Mobile est
identique à celui de la 4.4.0 ; le paquet ajouté (`camera_avfoundation`) n'existe que sur iOS.

Prestige Mobile reste identique à sa version de référence (job `prestige-mobile-identique`, référence 4.5.0+21,
commit 30f1a99, qui ne diffère de la 4.4.0+20 (commit 2e59cd0) que par le numéro de version).
