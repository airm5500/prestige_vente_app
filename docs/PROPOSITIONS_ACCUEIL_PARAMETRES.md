# Écran d'accueil et Paramétrage : propositions

> Statut : **validé en partie** — à réaliser **après la refonte des ventes**. Aperçus en images : `docs/maquettes/apercus/`.
> Maquettes visuelles : `docs/maquettes/accueil_parametres_maquettes.html`.
> Même charte que les menus déjà refaits (bleu Prestige, ambre pour l'action principale, présentations A / B / C).

## 1. Écran d'accueil

### 1.1 Constat (écran actuel)

| Élément actuel | Problème |
|---|---|
| Grille 2 × 3 en pages à faire défiler (4 pages pour 22 menus) | Il faut se souvenir de la page où se trouve un menu ; les menus du bas de liste sont « cachés » (ex. État de stock, Emplacement en page 3). |
| Carte « Bienvenu(e) à … » | Prend de la place sans information utile au travail. |
| Bandeau de licence vert permanent | Toujours affiché, même à 300 jours : attire l'œil pour rien. |
| Tâches en attente dans une icône ⓘ | Information importante (préventes à encaisser, BL à pointer) cachée derrière un dialogue. |
| Icônes de la barre (ⓘ, ⚙, ⏻) sans libellé | Peu compréhensibles pour un nouvel employé ; la déconnexion est à côté des réglages. |
| Aucun état du serveur | On découvre une panne seulement en ouvrant un menu. |

### 1.2 Proposition

**En-tête (bleu)**
- Nom de l'officine, nom de l'utilisateur et rôle, date du jour.
- **Pastille d'état du serveur** : « Serveur connecté » (vert) / « Hors ligne » (rouge, avec Réessayer). Vérifiée à l'ouverture et au retour sur l'accueil.
- La licence n'apparaît **que si elle expire dans moins de 30 jours** (ambre, puis rouge à 7 jours).
- **Recherche rapide** : « Rechercher un menu ou un produit ». Taper « stock » propose « État de Stock » ; scanner un code ouvre la fiche produit.

**« À faire maintenant »** (cartes cliquables, remplace l'icône ⓘ)
- Préventes à encaisser (nombre) → liste des préventes.
- BL à pointer / BL à entrer en stock (nombre) → menu correspondant.
- Caisse : ouverte / fermée → Gestion caisse.
- Ventes interrompues à reprendre (si la refonte des ventes en mémorise une).
- Chaque carte disparaît quand il n'y a rien à faire ; « Tout est à jour ✓ » sinon.

**Favoris** : 4 grandes tuiles en haut (par défaut : Pré-vente, Vente assurance, Recherche article, Réception BL), choisies par l'utilisateur.

**Tous les menus, rangés par familles** (une seule page qui défile, plus de pages cachées) :

| Famille | Menus |
|---|---|
| Ventes | Pré-vente, Pré-vente assurance, Vente carnet, Vente dépôt, Proforma / devis, Vérification ordonnance |
| Caisse | Gestion caisse |
| Réception & fournisseurs | Réception BL, Retour fournisseur, Contrôle livraison, Contrôle réception, Pointage BL stock |
| Stock | État de stock, Ajustement stock, Gestion périmés, Mise à jour péremption |
| Produits | Recherche article, Analyse article, Évaluation vente, Mise à jour EAN, Mise à jour emplacement |
| Équipe | Pointage |

- Pastilles de nombre sur les tuiles concernées (ex. « 3 » sur Pré-vente = 3 préventes à encaisser).
- Menus protégés par code (Ajustement…) marqués d'un petit cadenas.
- Tirer vers le bas pour actualiser les compteurs.

**Barre du bas** (4 boutons libellés, toujours visibles) : **Accueil** · **Scanner** (scan global : fiche produit) · **Tâches** · **Réglages**. La déconnexion passe dans Réglages → « Se déconnecter » (avec confirmation), pour ne plus la toucher par erreur.

### 1.3 Les trois présentations de l'accueil

| | A — Tableau de bord (défaut) | B — Compact | C — Guidé |
|---|---|---|---|
| Idée | Tâches + favoris + familles en tuiles | Liste dense de tous les menus par famille, recherche en haut | « Que voulez-vous faire ? » : grosses actions par métier |
| Pour qui | Pharmacien, gérant | Utilisateur expérimenté, petit écran | Nouveaux employés, caissiers |

### 1.4 Organiser l'accueil (remplace « Organiser le menu d'accueil »)
- Glisser-déposer l'ordre **dans chaque famille**, étoile pour mettre en favori (4 max), œil pour masquer.
- Aperçu en direct, bouton « Rétablir l'ordre par défaut ».
- Réglage par appareil, protégé par le code administrateur (comme aujourd'hui).

## 2. Paramétrage (Configuration)

### 2.1 Constat (écran actuel)
- Un seul long formulaire : Serveur, Personnalisation, Sécurité, Impression, Droits & limites, Modes de paiement, puis « Enregistrer » tout en bas.
- Mélange de réglages techniques (IP, port) et de réglages métier (tickets, droits), sans recherche.
- Les réglages d'autres menus sont éparpillés (Pointage, Réception BL, présentation A/B/C dans chaque menu).
- Le test de connexion n'apparaît qu'en bas, après « Enregistrer ».
- Pas de version de l'application ni d'identifiant de l'appareil visibles (utile pour le support).

### 2.2 Proposition : une page d'accueil des réglages par rubriques

| Rubrique | Contenu | Protection |
|---|---|---|
| **Connexion au serveur** | IP locale, IP distante, port, nom de l'application ; **« Tester la connexion »** avec le détail (serveur joignable, application Prestige trouvée, licence) ; enregistrement seulement si le test passe (ou confirmation explicite). | Code admin |
| **Ventes** | Version des ventes (nouvelle / ancienne), modes de paiement activés + aperçu des QR, nombre max. de tiers payants, masquer les produits RV, scan rapide par défaut. | Code admin |
| **Impression** | Largeur du ticket (58 / 80 mm), mode test, QR / code-barres sur le ticket, type de code, nombre de tickets (vente, assurance), **« Imprimer un ticket d'essai »**. | — |
| **Stock & contrôles** | Droits « modifier contrôle livraison / pointage BL », comparaison stock BL (théorique / machine), réglages de Réception BL (péremption obligatoire…). | Code admin |
| **Apparence** | Présentation par défaut A / B / C (appliquée à tous les menus), organiser l'accueil, taille du texte (normal / grand). | — |
| **Équipe & pointage** | Accès aux réglages du pointage (méthode, badge, NFC). | Code admin |
| **Sécurité** | Code PIN administrateur, menus protégés par code (cases à cocher), délai de verrouillage. | Code admin |
| **Licence & appareil** | État de la licence, jours restants, identifiant de l'appareil, modèle, version de l'application, **journal des erreurs** (consultable / à envoyer au support). | — |
| **Se déconnecter** | Avec confirmation. | — |

- **Recherche** en haut : « Rechercher un réglage » (ex. « ticket » → Impression).
- Chaque rubrique affiche un **résumé** sous son titre (ex. Impression : « 80 mm · 1 ticket · QR activé ») : on voit l'essentiel sans ouvrir.
- **Enregistrement** : les interrupteurs s'appliquent tout de suite ; les champs texte (IP, port…) ont une barre fixe « Enregistrer / Annuler » qui n'apparaît que s'il y a une modification.
- **Contrôles de saisie** : IP au bon format, port de 1 à 65535, nom d'application sans espace ; message clair sous le champ.
- **Rétablir les valeurs par défaut** par rubrique (avec confirmation).
- Cadenas sur les rubriques protégées ; le code n'est demandé qu'une fois par visite des réglages.

## 3. Questions pour valider

1. Accueil : **une seule page par familles** (plus de pages à faire défiler) — d'accord ?
2. Favoris : 4 tuiles en haut — combien ? lesquelles par défaut ?
3. Barre du bas (Accueil / Scanner / Tâches / Réglages) — d'accord ? La **déconnexion dans Réglages** — d'accord ?
4. Recherche / scan global depuis l'accueil (scanner un produit ouvre sa fiche) — d'accord ?
5. Pastille d'état du serveur sur l'accueil — d'accord ?
6. Licence affichée seulement à moins de 30 jours — d'accord ?
7. Réglages par rubriques avec recherche et résumé — d'accord ? Quelles rubriques protéger par le code admin ?
8. « Présentation par défaut A / B / C » commune à tous les menus dans Apparence — d'accord ?
9. Ordre : on fait l'accueil et le paramétrage **après** la refonte des ventes, ou en parallèle ?

### Réponses du client
| # | Décision |
|---|---|
| 1 | Oui : une seule page par familles. |
| 2 | 4 favoris (par défaut : Pré-vente, Vente assurance, Recherche article, Réception BL). |
| 3 | Oui : barre du bas ; déconnexion dans Réglages. |
| 4 | Oui : recherche / scan global. |
| 5 | Oui : pastille d'état du serveur. |
| 6 | Oui : licence affichée à moins de 30 jours. |
| 7 | À préciser (proposition : Connexion, Ventes, Stock & contrôles, Équipe, Sécurité protégés). |
| 8 | À préciser (proposition : oui). |
| 9 | Après les ventes. |

## 4. Plan proposé (après validation)

| Étape | Contenu |
|---|---|
| 1 | Accueil : familles, favoris, tâches, pastille serveur, recherche, barre du bas ; organiser l'accueil (ordre par famille, favoris, masqués) — l'ordre et les menus masqués actuels sont repris. |
| 2 | Paramétrage : rubriques, recherche, résumés, test de connexion, ticket d'essai, journal des erreurs. |

Même filet de sécurité que pour les ventes : point de retour noté avant chaque étape, aucun réglage existant perdu (mêmes clés de stockage), tests automatiques.
