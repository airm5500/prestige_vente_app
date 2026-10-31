# PrestigePOS 1.8.1 (versionCode 23)

Version de PrestigePOS construite avec Prestige Mobile **4.10.1+37** (code partagé). Retours du pharmacien du 31/10
(détail : `docs/NOTE_VERSION_4.10.1.md`).

## Pour la borne PrestigePOS

- **Icônes coupées par le bas : corrigé.** Sur un Sunmi V2s dont la « Taille de l'affichage » d'Android est agrandie,
  ou avec un texte agrandi, le pictogramme et le libellé des tuiles « Catégories » de l'accueil étaient coupés. La
  tuile prend maintenant la hauteur de son contenu. À la taille d'usine, la grille est identique.
- **Mobile Money absent à la fin de la vente : diagnostic, rien de changé.** Le bouton n'apparaît que si quatre
  conditions sont réunies :
  - l'option est cochée ;
  - le serveur est en ligne ;
  - le serveur annonce au moins un opérateur, ce qui suppose un agrégateur configuré sur le serveur
    (`PRESTIGE_PAIEMENTS_FOURNISSEUR`, l'adresse publique HTTPS et les clés, puis un redémarrage). Les modes Wave /
    Orange de la caisse ne suffisent pas ;
  - l'utilisateur borne a un droit de clôture (P_SM_CLOTURER_CAISSE).

  « Tester la borne » signale déjà le droit manquant. Une explication sous l'option est proposée et attend une
  décision.
- Date de naissance de la fiche client (Prestige Mobile) : sans effet sur la borne.

## Non-régression

- Job `prestige-mobile-identique` : la référence est **4.10.1+37** (commit `9393a16`, avant la fusion).
- `test/prestigepos/pos_ergonomie_test.dart` : V2s à une densité de 2,25 à 2,75, texte ×1 et ×1,3. L'accueil de la
  borne ne déborde pas et les tuiles sont entières.
- `test/prestigepos/pos_version_test.dart` : version 1.8.1+23.
- Suites de PrestigePOS et de Prestige Mobile : complètes.
