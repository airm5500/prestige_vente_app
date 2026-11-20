# PrestigePOS 1.17.0 (versionCode 40)

Version de PrestigePOS construite avec **Prestige Mobile V3 5.4.0+54** (code partagé ; détail :
`docs/NOTE_VERSION_5.4.0.md`).

## Ce qui change (code partagé avec Prestige Mobile V3 5.4.0)

- Ventes à crédit du comptoir (saveur `mobile`) : 2e ticket rétabli (« Ticket suivant (2/2) » après le 1er ticket quand
  le serveur dessine le ticket) ; « Réédition des ventes » ; réglage « Contraste d'impression » (Renforcé par défaut).
- Borne (PrestigePOS) : le ticket de prévente dessiné par le serveur et imprimé sur la Sunmi intégrée passe par la même
  conversion renforcée (seuil 160, traits verticaux d'un point doublés, QR inchangé).

## Propre à PrestigePOS

- Imprimantes externes (Bluetooth, USB, réseau) : le ticket du serveur est converti avec le même contraste
  (`TicketEscPos.matricePng`) ; le ticket ESC/POS composé par la borne imprime ses lignes produits et le total en gras
  si le contraste est renforcé (même largeur de colonnes) ; « Normal » : octets identiques à la 1.16.0.
- Page Imprimante (administration) : interrupteur « Contraste renforcé » (toutes les imprimantes, Sunmi comprise).
- Réglage chargé au démarrage (`main_pos.dart`).
- PrestigePOS n'a pas de vente au comptoir à plusieurs tickets ni de liste des ventes : la réédition reste dans la
  saveur `mobile`. Identité inchangée : `com.dici.prestigepos`, « PrestigePOS », `PosActivity`, icône de `src/pos`,
  version 1.17.0+40 (`android/app/prestigepos-version.properties`), APK `PrestigePOS-release-1.17.0.apk`.

## Contrôles

- `test/prestigepos/pos_contraste_test.dart` : contraste des images du serveur (imprimantes externes), ticket ESC/POS
  en gras si renforcé et identique à la référence 1.16.0 en « Normal », interrupteur de la page Imprimante.
- `test/prestigepos/pos_identite_v3_test.dart` : identité et icône inchangées, référence de Prestige Mobile 5.4.0+54.
- CI (job `prestige-mobile-identique`) : Prestige Mobile V3 construite sur cette branche identique à la référence
  5.4.0+54 (`REFERENCE_MOBILE`).
- `pos_version_test.dart` : 1.17.0+40.
