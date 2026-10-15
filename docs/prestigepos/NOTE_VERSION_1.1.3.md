# PrestigePOS 1.1.3 (versionCode 5)

Version de PrestigePOS construite avec Prestige Mobile **4.3.3+19** (code partagé de la borne).

## Venu de Prestige Mobile 4.3.3

Deux pannes du serveur, deux messages (borne, assistant de premier lancement, « Tester la borne ») :

- le serveur ne répond pas (PC serveur éteint, Payara arrêté, Wi-Fi coupé, délai dépassé) :
  **« Serveur injoignable. Vérifiez le Wi-Fi et que le PC serveur est allumé. »** ;
- le serveur répond mais Prestige n'est pas déployé (404 de Payara, 502 / 503 / 504) :
  **« Serveur indisponible : Prestige est en cours de démarrage ou de redéploiement. Veuillez réessayer dans un
  instant. »**

L'écran « Borne momentanément indisponible » (client) garde son texte et ajoute, pour le personnel, la ligne qui
correspond à la panne ; la borne reprend seule dès que le serveur répond. Un mot de passe faux de l'utilisateur
borne reste « Connexion refusée ». Un 404 de Payara n'est plus pris pour une « route absente » d'un serveur ancien
(vérification par `/officine`), rien n'est mémorisé à tort pendant un redéploiement.

Inchangé depuis la 1.1.0 : démarrage automatique avec l'appareil, « Revenir à Android », message « Ajouté » en haut
de l'écran de la borne. Prestige Mobile reste identique à sa version de référence (job `prestige-mobile-identique`,
référence 4.3.3+19, commit 6c86174).
