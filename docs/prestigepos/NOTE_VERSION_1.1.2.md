# PrestigePOS 1.1.2 (versionCode 4)

Version de PrestigePOS construite avec Prestige Mobile **4.3.2+18** (code partagé de la borne).

## Venu de Prestige Mobile 4.3.2

- **Redéploiement du serveur Prestige** (Payara répond 404 / 502 / 503 ou refuse la connexion) : la borne affiche
  **« Serveur indisponible, veuillez réessayer »** au lieu de « Connexion refusée … HTTP 404 », et reprend seule dès
  que le serveur répond. Un vrai mot de passe faux de l'utilisateur borne reste signalé comme tel.
- Analyse article et fiche produit plus rapides : écrans de Prestige Mobile, absents de PrestigePOS.

Inchangé depuis la 1.1.0 : démarrage automatique avec l'appareil, « Revenir à Android », message « Ajouté » en haut
de l'écran de la borne. Prestige Mobile reste identique à sa version de référence (job `prestige-mobile-identique`,
référence 4.3.2+18, commit 6b5902f).
