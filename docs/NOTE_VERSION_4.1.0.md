# Prestige Mobile — note de version 4.1.0 (versionCode 12)

Suite de la 4.0.3+11 (pas encore publiée sur le magasin Sunmi, dernière version publiée : 3.3.1 / 7).
Numérotation : `docs/VERSIONS_SUNMI.md` (nouveauté → 4.**1**.0, +N augmenté de 1 : **4.1.0+12**).

## HTTPS pour l'accès au serveur par Internet

Jusqu'en 4.0.3, l'adresse du serveur était toujours construite en `http://` (`SettingsProvider.baseUrl`) : le mode
distant passait en clair sur Internet. Prestige Mobile accepte désormais `https://`, **sur le même principe que
Prestige Pharmacien et Prestige Inventaire**, pour un serveur placé derrière un proxy HTTPS (Caddy, voir
`docs/serveur/HTTPS_SERVEUR_WINDOWS.md`). **Rien ne change en local.**

### Où se règle le HTTPS

Configuration du serveur (protégée par le code administrateur) :

- **Nouvelle interface** : Réglages › **Connexion au serveur**.
- **Interface d'origine** : écran **Configuration**, rubrique « Serveur ».

Pour chaque adresse (IP locale, IP distante), le protocole se choisit :

- **nouvelle interface** : bouton **`http://` / `https://`** au début du champ (un appui bascule ; cadenas vert en
  https) ;
- **interface d'origine** : choix **http / https** sous le champ (« Protocole du serveur local », « Protocole du
  serveur distant »).

On peut aussi **saisir ou coller** `https://nom` dans le champ : le protocole est retiré du champ et reporté sur le
choix. En https, le clavier passe en mode adresse (lettres) pour saisir un nom.

| Cas | Adresse | Port utilisé |
|---|---|---|
| Local, comme avant | `192.168.1.100` (http) | champ « Port » (8080) — **identique à 4.0.3** |
| Distant par Internet | `prestige.ma-pharmacie.ci` + **https** | **443** par défaut (le champ « Port » reste celui du local) |
| Port HTTPS particulier | `prestige.ma-pharmacie.ci:8443` + https | **8443** (port écrit dans l'adresse : prioritaire) |
| Serveur principal en https | adresse locale en https | champ « Port », qui passe tout seul de 8080 à 443 (un autre port saisi est gardé) |

Règle exacte (`lib/serveur/adresse_serveur.dart`) : un port écrit dans l'adresse (`nom:port`) est prioritaire ;
sinon le champ « Port » s'applique au serveur local et au serveur distant **s'il a le même protocole** ; sinon le
port par défaut du protocole (443 en https, 8080 en http).

### Réglages existants : inchangés

- Mêmes clés (`local_ip`, `remote_ip`, `port`). Une adresse **sans protocole** est en **http** : les appareils déjà
  configurés construisent **exactement la même adresse** qu'avant (`http://ip:port/prestige/api/v1`). Valeur par
  défaut d'un appareil neuf inchangée (http, 8080).
- Forme enregistrée : http sans protocole (comme avant), https avec `https://` (`https://nom` ou `https://nom:8443`).
  Une adresse enregistrée avec `http://` est relue sans le préfixe (même adresse).

### Une seule adresse pour tous les clients HTTP

Tous les clients partent de `SettingsProvider.baseUrl` (directement, ou par l'adresse du Dio principal) : Dio
principal (`DioClient`, intercepteur de session 401 compris), hors ligne / synchro / surveillance du serveur
(`lib/horsligne`), stock hors ligne, ventes (`DioVenteGateway`), réception BL / retours fournisseur,
`ClientPrestige` (Réserve, Analyse posologie, Fiche client, droits), RH / pointage (`DioRhServeur`, transport
`/mobile/`), support, images des produits, paiements mobile, ordonnances O4 / O5, borne, licence. Aucune autre
adresse `http://` n'était construite à la main ; l'affichage des adresses (écran de lancement, connexion, choix du
serveur, résumé des Réglages) montre `https://nom` en https et `ip:port` en http, comme avant.

Les **cookies de session** (pot à cookies unique, par hôte) suivent l'adresse https : la session **renouvelée** à
la connexion est bien celle envoyée ensuite, et la reconnexion silencieuse après une session expirée fonctionne en
https (tests).

### Sécurité

- La vérification des certificats n'est **jamais** désactivée (aucun `badCertificateCallback`) : seuls les
  certificats reconnus par l'appareil sont acceptés (Let's Encrypt, par exemple). Un certificat auto-signé est
  refusé.
- Messages distincts : « **Connexion sécurisée (HTTPS) impossible : certificat du serveur refusé.** » (avec le
  conseil : certificat reconnu, date et heure de l'appareil) ≠ « Serveur injoignable » ≠ licence absente / expirée.
  Https choisi vers un port qui ne parle pas HTTPS (par exemple 8080 de Payara) : « le serveur ne répond pas en
  HTTPS sur ce port ». Ces messages apparaissent au test de connexion de la Configuration, au lancement (« La licence
  n'est pas en cause »), sur l'écran de connexion, dans les modules (titre « Certificat du serveur refusé ») et les
  chargements de listes. Un certificat refusé ne bloque pas l'accès comme une licence absente.
- `network_security_config.xml` : le HTTP en clair **reste autorisé** (réseau local : Android ne sait pas le limiter
  à des plages d'adresses IP) ; ancres de confiance = autorités du **système** (comportement par défaut, rendu
  explicite).

## Tests

- `test/https_adresse_test.dart` (nouveau, unitaires) : construction de l'adresse http / https, ports par défaut,
  port écrit prioritaire, adresse saisie avec protocole, distant / local, contrôles de saisie ; **anciens réglages =
  même adresse qu'en 4.0.3** ; classement des échecs TLS.
- `test/https_integration_test.dart` (nouveau, intégration) : faux serveur Prestige en **HTTPS**
  (`HttpServer.bindSecure`, certificat de test auto-signé créé à la volée, approuvé **dans le test seulement**) :
  tous les clients (Dio principal, ClientPrestige, RH, transport `/mobile/`, support, images) joignent la même
  adresse https avec le cookie de la **dernière** connexion ; session expirée → reconnexion silencieuse en https ;
  certificat non approuvé → « certificat du serveur refusé » (Configuration, licence, modules, listes) sans qu'aucune
  requête ne parte ; https vers un port HTTP ; serveur arrêté = injoignable ; http inchangé.
- `test/https_configuration_test.dart` (nouveau, écrans + e2e) : choix http / https dans la **nouvelle interface**
  (port 8080 ↔ 443, port saisi gardé, `https://` collé, test et enregistrement, certificat refusé) et dans
  l'**interface d'origine** (enregistrement réel puis relance en https) ; application entière configurée en https :
  toutes les requêtes vers la même adresse https, aucune refusée faute de session.
- Outils : `test/outils/certificat_tls.dart` (certificat de test, confiance limitée au test),
  `ServeurJsonLocal.contexteTls` (faux serveur en HTTPS).
- Non-régression : toute la suite de la CI verte ; `flutter analyze` sans nouvelle remarque.
