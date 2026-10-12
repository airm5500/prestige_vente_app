# Écran de lancement et écran de connexion : propositions

> Statut : **propositions à valider**. Aucun écran de l'application n'est modifié à ce stade.
> Maquettes visuelles : `docs/maquettes/lancement_connexion_maquettes.html` (s'ouvre dans un navigateur, sans Internet).
> Aperçus en images : `docs/maquettes/apercus/lancement_*.png` et `docs/maquettes/apercus/connexion_*.png`.
> Même charte que les écrans déjà refaits (accueil, réglages, ventes) : bleu Prestige `#003366`, ambre `#F59E0B` pour l'action principale, coins arrondis, présentations A / B / C.

---

## 1. Ce qui existe aujourd'hui

### 1.1 Écran de lancement (`lib/screens/splash_screen.dart`)

Fond blanc, icône de magasin dans un rond bleu, roue qui tourne et le mot « Démarrage… ». En coulisses, dans l'ordre :

1. **Attente fixe de 2 secondes** (uniquement visuelle).
2. **Chargement des réglages** de l'appareil (adresse du serveur local / distant, port, « Rester connecté », imprimante…). À cette occasion, l'ancien mot de passe enregistré en clair et l'ancien code administrateur en clair sont **déplacés dans le stockage sécurisé** (migration silencieuse, jamais bloquante).
3. Si l'appareil **n'est pas configuré** → ouverture de la Configuration.
4. **Vérification de la licence** auprès du serveur.
5. Si le **mode borne** est actif sur l'appareil → la borne libre-service s'ouvre directement (pas d'écran de connexion).
6. Licence **valide** → **connexion automatique** si « Rester connecté » était coché (identifiants lus dans le stockage sécurisé), puis accueil ; sinon écran de connexion.
7. **Serveur injoignable** → boîte de dialogue « Configuration / Réessayer » avec l'adresse utilisée (en précisant que la licence n'est pas en cause).
8. Licence **absente ou expirée** → écran « Clé de licence ».

Points faibles : 2 s d'attente imposées à chaque ouverture ; on ne sait pas ce que fait l'application ni où elle bloque ; les problèmes s'affichent dans une boîte de dialogue technique ; aucun nom d'officine ni numéro de version.

### 1.2 Écran de connexion (`lib/screens/auth/login_screen.dart`)

Barre bleue « Connexion » avec un **interrupteur Local / Distant** et une **roue dentée** (Configuration) accessibles à tous ; cadenas, champs Login et Mot de passe (avec œil), case « Rester connecté », bouton « Se connecter » remplacé par une roue pendant le chargement. Après la connexion : **nouvelle vérification de la licence**, enregistrement des identifiants (si « Rester connecté »), puis chargement des informations de l'officine, des préventes, des BL du jour et des modes de paiement avant d'ouvrir l'accueil.

Points faibles : aucune indication de l'état du serveur avant d'appuyer ; le changement de serveur et la Configuration sont ouverts à tout le personnel ; l'erreur « Erreur de connexion: DioException… » est technique ; pas de version de l'application ; pas de solution quand le serveur ne répond pas, alors que la **copie locale (hors ligne)** existe déjà sur l'appareil.

### 1.3 Éléments réutilisés

- Couleurs et boutons de `lib/widgets/presentation_style.dart` (`Pal.navy`, `Pal.amber`, pastilles d'initiales des grossistes réutilisées pour les avatars de la proposition C).
- Logo : icône actuelle de l'application (`assets/icon/icon.png`, chariot coché). Nom affiché sur le téléphone : « Prestige Mobile ».
- Nom de l'officine : reçu du serveur après la connexion (`nomComplet`). Pour l'afficher dès le lancement, il serait **gardé sur l'appareil** après la dernière connexion (« Pharmacie Les Palmiers » dans les maquettes, à titre d'exemple).
- Code PIN administrateur déjà existant (Paramètres › Sécurité), surveillance du serveur et copie locale du mode hors ligne.

---

## 2. Les trois propositions

Chaque proposition comprend un écran de **lancement** et un écran de **connexion** avec tous leurs états (prêt, chargement, mot de passe faux, serveur injoignable). Les cas particuliers du lancement (licence expirée, serveur injoignable, première utilisation, borne, mise à jour de la copie locale) suivent les **mêmes règles** dans les trois propositions ; ils sont dessinés dans le style A.

### A — « Sobre professionnel » (recommandée)

*Aperçus : `lancement_A.png`, `lancement_cas_A.png`, `connexion_A.png`, `connexion_A_serveur.png`, `connexion_A_tablette.png`, `lancement_A_tablette.png`.*

**Lancement** : fond bleu nuit Prestige, logo centré, « Prestige Mobile » et le nom de l'officine. En bas, une barre de progression ambre et la liste des **vraies étapes**, cochées au fur et à mesure :
« Chargement des réglages » → « Vérification de la licence » → « Connexion au serveur… (adresse) » → « Chargement du catalogue local ». Version de l'application en bas.

**Connexion** : en-tête bleu (logo, officine) avec un **indicateur du serveur** : point vert « Serveur local connecté · 192.168.1.50:8080 » ou point rouge « Serveur injoignable · nouvel essai dans 8 s », et un bouton **« Changer » protégé par le PIN administrateur**. Dessous, formulaire blanc : identifiant pré-rempli, mot de passe avec œil (curseur déjà dedans), « Rester connecté — sur cet appareil uniquement », gros bouton ambre « Se connecter ». Version et numéro d'assistance en bas.

Avantages :
- Continuité totale avec l'accueil et les réglages déjà refaits (même bleu, même ambre) : l'application paraît « d'un seul bloc ».
- On voit **où en est** le démarrage et **où il bloque** (Wifi ? licence ? serveur ?) : moins d'appels à l'assistance.
- L'état du serveur est visible **avant** de taper son mot de passe.
- Le changement de serveur n'est plus à la portée de tous.
- Sur tablette en paysage : deux colonnes (identité + serveur à gauche, formulaire à droite).

### B — « Pharmacie moderne »

*Aperçus : `lancement_B.png`, `connexion_B.png`.*

**Lancement** : dégradé doux vert d'eau → bleu clair, **croix verte de pharmacie** entourée d'un anneau de progression, une seule ligne d'étape (« Connexion au serveur… — étape 3 sur 4 »).
**Connexion** : carte blanche « flottante » avec ombre, pastille du serveur en haut de la carte (« Local · 192.168.1.50 — Changer »), bouton principal **vert**.

Avantages : image plus chaleureuse et plus « officine » ; très lisible ; agréable pour une première impression (clients qui voient l'écran, démonstrations).
Limites : s'éloigne de la charte bleu / ambre des autres écrans ; une seule étape visible à la fois (moins d'information en cas de blocage) ; la croix verte est un symbole réglementé dans certains pays (à vérifier pour la Côte d'Ivoire si elle doit apparaître sur l'icône de l'application).

### C — « Express comptoir »

*Aperçus : `lancement_C.png`, `connexion_C.png`.*

**Lancement** : très épuré, grand logo, une étape en gros caractères et un pourcentage ; boutons de 64 px en cas de problème (« Réessayer », « Vendre hors ligne »).
**Connexion** : « Qui êtes-vous ? » — tuiles des **5 derniers utilisateurs de l'appareil** (initiales en couleur, nom, dernière connexion) + « Autre ». On touche son nom, puis on tape un **code PIN personnel** de 4 chiffres sur un grand pavé, ou son mot de passe (onglet « Mot de passe »). Après 3 PIN faux, le mot de passe complet est exigé.

Avantages : connexion en **2 secondes** sur un terminal Sunmi partagé entre plusieurs vendeurs ; plus de saisie d'identifiant ; grosses touches utilisables avec des gants ou à bout de bras.
Limites : nécessite de **créer un PIN personnel** (nouveau réglage) et de garder sur l'appareil, chiffré, le mot de passe de chaque utilisateur qui l'active ; la liste des noms est visible par toute personne qui prend le terminal.

---

## 3. Recommandation

**Proposition A pour tous les appareils**, avec **en option l'écran « Qui êtes-vous ? » de C** activable par l'administrateur sur les terminaux de comptoir partagés (réglage « Connexion rapide par utilisateur » dans Paramètres, désactivé par défaut).

Raisons : A est cohérente avec tout ce qui a déjà été refait, montre les vraies étapes et les vraies pannes, et ne demande aucun changement côté serveur. L'option C répond au besoin de vitesse au comptoir sans l'imposer aux téléphones personnels.

---

## 4. Comportements proposés (communs aux trois)

### 4.1 Lancement

| Situation | Aujourd'hui | Proposition |
|---|---|---|
| Démarrage normal | 2 s d'attente imposées puis roue | **Plus d'attente forcée**. Si tout prend moins d'une demi-seconde, on passe directement ; sinon les étapes s'affichent. Objectif : moins de 2 s sur le Wifi de l'officine. |
| Appareil non configuré | Configuration | Message « Première utilisation » + bouton « Configurer le serveur » → **même page** de Configuration. |
| Serveur injoignable | Boîte de dialogue « Configuration / Réessayer » | Message clair sur l'écran (adresse, causes probables, « la licence n'est pas en cause »), **réessai automatique toutes les 10 s**, « Réessayer », **« Continuer hors ligne »** si une copie locale existe et qu'une session a déjà été ouverte sur l'appareil, « Configuration » protégée par le PIN administrateur. |
| Licence absente ou expirée | Écran « Clé de licence » | Même blocage, mais expliqué (date d'expiration), avec « Saisir la clé de licence » (écran actuel, inchangé), « Appeler l'assistance Prestige » et « Vérifier à nouveau ». |
| Licence qui expire bientôt | Rappel à 90 et 30 jours | Inchangé (rappel affiché sur l'accueil, comme validé pour le nouvel accueil). |
| Mode borne actif | Ouverture directe de la borne | Inchangé ; l'écran indique « Borne libre-service — ouverture de la borne… ». |
| Copie locale à mettre à jour | En arrière-plan après l'ouverture | Étape « Mise à jour du catalogue local · 1 240 / 4 312 » **jamais bloquante** : bouton « Continuer, mise à jour en arrière-plan ». |
| Connexion automatique (« Rester connecté ») | Silencieuse | Étape « Connexion au serveur » ; si elle échoue (mot de passe changé), l'écran de connexion s'ouvre avec l'identifiant pré-rempli et le message « Votre mot de passe a changé, saisissez-le à nouveau ». |

### 4.2 Connexion

- **Identifiant pré-rempli** avec le dernier utilisateur ; curseur directement dans le mot de passe.
- **Œil** pour afficher / masquer le mot de passe (cible de 48 × 48 px).
- **Rester connecté** : case de 48 px de haut, précision « Sur cet appareil uniquement ». Le mot de passe reste dans le stockage sécurisé (comme aujourd'hui depuis la migration).
- **Se connecter** : bouton de 54 px ; pendant la connexion il affiche une roue et « Connexion en cours… », les champs sont grisés (pas de double appui) et les chargements réels sont listés (identifiants, licence, préventes, BL du jour, modes de paiement).
- **Mot de passe faux** : message sous le champ, en rouge foncé **avec une icône et du texte** (pas seulement la couleur) : « Identifiant ou mot de passe incorrect. Vérifiez les majuscules et réessayez. » Le mot de passe est vidé, l'identifiant gardé.
- **Serveur injoignable** : point rouge dans l'indicateur, encadré « Le serveur ne répond pas — vos identifiants ne sont pas en cause », boutons « Réessayer » et « Continuer hors ligne » (avec la date de la copie locale).
- **Indicateur du serveur** : point vert / ambre (test en cours) / rouge + nom (« Serveur local », « Serveur distant ») + adresse. Remplace l'interrupteur Local / Distant de la barre du haut.
- **Changer de serveur** : demande le **code PIN administrateur** existant, puis propose les deux adresses enregistrées avec leur état (« Répond » / « Injoignable »), et un accès à la Configuration complète.
- **Version de l'application** (ex. « Version 1.2.0 ») et numéro d'assistance en bas de l'écran.
- Messages d'erreur techniques (« DioException… ») remplacés par des phrases compréhensibles ; le détail technique reste dans le journal du terminal pour l'assistance.

### 4.3 Accessibilité

- Contrastes vérifiés : texte blanc sur bleu `#003366` (≈ 12,6 : 1), texte foncé `#1F1300` sur ambre (≈ 9 : 1), rouge d'erreur `#B91C1C` sur blanc (≈ 6,5 : 1), texte gris `#5B6B82` sur blanc (≈ 5,3 : 1). Le vert vif n'est utilisé que pour les points d'état, jamais pour du texte.
- Toutes les zones à toucher font au moins **48 px** (boutons 54 px, touches du pavé 64 px, tuiles utilisateurs 118 px).
- Les états ne reposent jamais sur la seule couleur : chaque point de couleur est accompagné d'un texte (« connecté », « injoignable »).
- Les écrans suivent la taille de texte choisie dans Android ; sur tablette, le formulaire reste limité à 440 px de large.
- Le clavier ne cache jamais le bouton « Se connecter ».

---

## 5. Sécurité

1. **Changer de serveur** et **Configuration** depuis le lancement / la connexion : protégés par le code PIN administrateur (aujourd'hui : accessibles à tous). Sans code défini (première installation), l'accès reste libre.
2. **Continuer hors ligne** : n'est proposé que si (a) une copie locale existe, (b) l'utilisateur s'est déjà connecté **en ligne** sur cet appareil, et (c) le mot de passe saisi correspond à une **empreinte** gardée sur l'appareil lors de la dernière connexion réussie (jamais le mot de passe en clair). La licence connue doit être valide. Les ventes saisies partent au retour du serveur, comme dans le mode hors ligne actuel.
3. **PIN personnel (option C)** : il ne remplace pas le mot de passe du serveur ; il débloque le mot de passe gardé chiffré sur l'appareil. 3 erreurs → mot de passe complet obligatoire. Le PIN expire si le mot de passe change sur le serveur.
4. « Rester connecté » reste **par appareil** ; la déconnexion (Réglages › Se déconnecter) désactive la connexion automatique, comme aujourd'hui.
5. Aucune information sensible sur l'écran de lancement (pas de nom d'utilisateur, seulement l'officine et l'adresse du serveur).

---

## 6. Garantie : aucune régression

- **Même logique** : l'ordre des vérifications (réglages et migration des mots de passe, configuration, licence, borne, connexion automatique, licence revérifiée après la connexion, chargements avant l'accueil) est **repris tel quel** ; seule la présentation change. Les appels au serveur sont les mêmes.
- **Ancien écran gardé** : l'écran de lancement et l'écran de connexion actuels restent dans l'application, **inchangés**, derrière l'interrupteur de version déjà utilisé pour l'accueil et les réglages (Paramètres › « Nouvel accueil et nouveaux réglages »). Désactivé, l'application démarre exactement comme aujourd'hui, sans réinstallation.
- Le mode borne, l'écran « Clé de licence » et la page de Configuration ne sont pas modifiés.
- Ajouts seulement : nom de l'officine gardé sur l'appareil, empreinte pour le hors ligne, liste des derniers utilisateurs (option C) — chacun sans effet si l'interrupteur est désactivé.

---

## 7. Questions à valider

1. **Choix de la proposition** : A (recommandée), B ou C ? Ou A avec l'option « Qui êtes-vous ? » de C pour les terminaux de comptoir ?
2. **Continuer hors ligne depuis la connexion** : l'autorisez-vous (mot de passe vérifié sur l'appareil, uniquement pour un utilisateur déjà connecté en ligne sur ce téléphone) ? Pour tous les utilisateurs ou seulement certains rôles ?
3. **Changer de serveur** : d'accord pour le protéger par le code PIN administrateur ? Faut-il aussi protéger la case « Rester connecté » (ex. interdite sur les terminaux partagés) ?
4. **PIN personnel (option C)** : 4 ou 6 chiffres ? Chaque vendeur le choisit-il lui-même à la première connexion ?
5. **Liste des derniers utilisateurs (option C)** : combien de noms (5 proposés) ? Affichage du rôle (Caissière, Vendeur…) ?
6. **Nom de l'officine** au lancement : d'accord pour le garder sur l'appareil après la première connexion ? Faut-il afficher le **logo de l'officine** au lieu (ou à côté) du logo Prestige, s'il est disponible sur le serveur ?
7. **Numéro d'assistance** affiché en bas de l'écran : lequel (Prestige ou responsable de l'officine) ? Bouton « Appeler l'assistance » sur l'écran de licence expirée : d'accord ?
8. **Durée** : d'accord pour supprimer l'attente fixe de 2 secondes au démarrage ?
9. **Réessai automatique** quand le serveur ne répond pas : toutes les 10 s, est-ce adapté ?
10. **Proposition B** : la croix verte de pharmacie peut-elle être utilisée dans l'application (règles de l'Ordre des pharmaciens de Côte d'Ivoire) ?
11. Faut-il une version **tablette** dédiée pour la proposition retenue (deux colonnes, comme l'aperçu A), ou l'écran téléphone centré suffit-il ?

---

## 8. Mise en œuvre (réponses du client)

Statut : **réalisé** dans la nouvelle interface (`lib/connexion/`), branché par l'interrupteur `InterfaceVersion` ;
désactivé, l'écran de démarrage et l'écran de connexion d'origine (`AncienSplashScreen`, `AncienLoginScreen`) s'ouvrent, inchangés.

- **Proposition A** + **option C « Qui êtes-vous ? »** (Paramètres › Sécurité › « Connexion rapide par utilisateur », désactivée par défaut).
- **Pas de « Continuer hors ligne »** : serveur injoignable → message, « Réessayer », réessai automatique toutes les **10 s**.
- **« Changer de serveur »** et « Configuration » (depuis le lancement / la connexion) : **code PIN administrateur**.
- **Terminal partagé** (Paramètres › Sécurité, désactivé par défaut) : « Rester connecté » masqué, identifiants mémorisés effacés, pas de connexion automatique ; active la connexion rapide.
- **PIN personnel** : 4 chiffres, proposé (facultatif) après une connexion par mot de passe, empreinte PBKDF2 salée (stockage sécurisé), règles anti-PIN faibles, **3 erreurs → mot de passe**. Il débloque le mot de passe gardé chiffré **pour cet utilisateur** ; la connexion au serveur est toujours faite. Mot de passe refusé par le serveur → PIN effacé. Réinitialisation : Paramètres › Sécurité.
- **6 derniers utilisateurs** avec leur **rôle**, grille sans défilement (360 × 800 compris).
- **Nom de l'officine** gardé après une connexion réussie (croix verte d'accent) ; **logo** : aucune route du serveur ne fournit de logo d'officine → logo de l'application.
- **Assistance** : 0708080068 par défaut, modifiable (Paramètres › Sécurité), bouton « Appeler l'assistance » (composeur ; repli : numéro copié).
- **Attente de 2 s** de l'écran d'origine : purement visuelle (« Délai visuel initial », aucune vérification). Elle est **gardée** dans l'écran d'origine. Le nouveau lancement n'a **aucune attente fixe** : il affiche les vraies étapes et reste visible **au minimum 1,2 s** (pour que le logo ne clignote pas) ; au-delà, l'écran suivant s'ouvre dès que les étapes sont finies.
- **Tablette** : connexion en deux colonnes à partir de 900 px.
- Aperçus réels : `docs/maquettes/apercus/app_connexion_*.png` (`APERCUS=1 flutter test test/outils/apercus_connexion_test.dart --update-goldens`).
