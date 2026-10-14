# Accès HTTPS au serveur Prestige depuis Internet (serveur Windows)

| | |
|---|---|
| **Date** | 14/10/2026 |
| **Pour** | la personne qui administre le serveur Prestige de l'officine (Windows, Payara, port 8080, contexte `/prestige`) |
| **But** | que les téléphones et terminaux joignent le serveur **par Internet en HTTPS** (connexion chiffrée), **sans rien changer sur le réseau local** de la pharmacie |
| **Durée** | environ 1 à 2 heures, plus le délai de mise à jour du nom de domaine (quelques minutes à quelques heures) |

## En bref

- Aujourd'hui, l'accès « distant » se fait en **HTTP en clair** : mots de passe, cookies de session et données de
  vente circulent sans chiffrement sur Internet.
- La solution recommandée : installer **Caddy**, un petit serveur gratuit, **devant** Payara. Caddy reçoit les
  connexions HTTPS d'Internet, obtient et renouvelle **tout seul** un certificat **Let's Encrypt** (gratuit, reconnu
  par Android), puis transmet les requêtes à Payara sur la même machine (`127.0.0.1:8080`). C'est ce qu'on appelle
  un **proxy inverse**.
- **Payara ne change pas.** Sur le réseau local, les applications continuent de joindre `http://<IP locale>:8080`
  directement, comme aujourd'hui.

```
Internet ── https:// (443) ──► Box ──► Caddy (serveur Windows, 443) ──► Payara 127.0.0.1:8080 /prestige
Réseau local ── http://192.168.x.x:8080 ─────────────────────────────► Payara (inchangé)
```

## 0. Ce que font les applications (à lire avant de commencer)

| Application | Mode local | Mode distant en HTTPS | Point d'attention |
|---|---|---|---|
| **Prestige Pharmacien** | `http` sur l'adresse IP locale, inchangé | **accepté** : saisir `https://<nom>` dans l'adresse distante (`prestige_app/docs/HTTPS_ET_TRAFIC_EN_CLAIR.md`) | **un seul champ « Port du Serveur » pour les deux modes** : il doit rester `8080` pour le local. D'où la règle « port externe 8080 → 443 » de l'étape 3 |
| **Prestige Inventaire** | inchangé | **accepté** : `https://<nom>` dans l'adresse distante, avec son **propre port distant** (`443`) | aucun |
| **Prestige Mobile** (comptoir) | `http` sur l'adresse IP locale, inchangé | **accepté depuis la 4.1.0** : choisir **https** sous l'adresse distante (ou saisir `https://<nom>`), port **443** par défaut (`docs/NOTE_VERSION_4.1.0.md`) | aucun : le champ « Port » reste `8080` pour le local, le distant en https prend 443 tout seul |

Autres règles des applications :

- un certificat **auto-signé est refusé** (« Connexion sécurisée (HTTPS) impossible : certificat du serveur refusé ») :
  il faut un certificat reconnu, d'où Let's Encrypt ;
- le HTTP en clair reste autorisé dans les applications, **pour ne pas casser le mode local** (Android ne sait pas
  limiter le clair aux adresses IP locales).

## 1. Prérequis

### 1.1 Une adresse IP publique joignable

1. Sur l'interface de la box, notez l'**adresse IP WAN** (adresse Internet de la box).
2. Depuis un poste de la pharmacie, ouvrez un site comme `https://ifconfig.me` : il affiche l'**adresse IP publique**.
3. Si les deux sont **identiques** : c'est bon.
   Si elles **diffèrent** (ou si l'adresse WAN commence par `100.64` à `100.127`) : votre fournisseur partage une
   adresse entre plusieurs clients (« CGNAT ») et **aucune redirection de port ne fonctionnera**. Demandez à votre
   fournisseur une adresse IP publique (souvent une option, parfois fixe). À défaut, il faut un tunnel (par exemple
   Cloudflare Tunnel) : hors du cadre de cette notice.
4. Notez si l'adresse est **fixe** (elle ne change jamais) ou **dynamique** (elle change au redémarrage de la box).

### 1.2 Un nom de domaine qui pointe vers cette adresse

Let's Encrypt ne délivre pas de certificat pour une adresse IP : il faut un **nom**.

- **Vous avez un domaine** (ex. `ma-pharmacie.ci`) et une **IP fixe** : chez le registraire du domaine, créez un
  enregistrement **A** `prestige` → `<IP publique>`. Le nom sera `prestige.ma-pharmacie.ci`.
- **IP dynamique ou pas de domaine** : utilisez **DuckDNS** (gratuit, `https://www.duckdns.org`) :
  1. connectez-vous, choisissez un sous-domaine, par exemple `ma-pharmacie` → nom `ma-pharmacie.duckdns.org` ;
  2. notez le **jeton** (token) affiché : il est **secret** (il permet de changer l'adresse de votre nom) ;
  3. créez le fichier `C:\caddy\duckdns.ps1` (dossier créé à l'étape 4) :

     ```powershell
     # Met à jour l'adresse de ma-pharmacie.duckdns.org avec l'IP publique actuelle.
     # Le paramètre ip= vide laisse DuckDNS détecter l'adresse. Réponse attendue : OK
     Invoke-WebRequest -UseBasicParsing -OutFile C:\caddy\duckdns.txt `
       "https://www.duckdns.org/update?domains=ma-pharmacie&token=VOTRE_JETON&ip="
     ```

  4. planifiez-le toutes les 5 minutes, dans une invite de commandes **administrateur** :

     ```bat
     schtasks /Create /TN "DuckDNS Prestige" /SC MINUTE /MO 5 /RU SYSTEM ^
       /TR "powershell -NoProfile -ExecutionPolicy Bypass -File C:\caddy\duckdns.ps1"
     ```

     (`-ExecutionPolicy Bypass` ne s'applique qu'à ce script, le temps de son exécution.) Vérifiez que
     `C:\caddy\duckdns.txt` contient `OK`.

Dans la suite, remplacez `prestige.ma-pharmacie.ci` par votre nom.

**Vérification** : `nslookup prestige.ma-pharmacie.ci` (invite de commandes) renvoie votre IP publique.

### 1.3 Une adresse IP locale fixe pour le serveur

Dans la box, réservez l'adresse IP locale du serveur (« bail DHCP statique » ou « réservation »), par exemple
`192.168.1.100`. Sinon les redirections de port pointeront un jour vers une autre machine.

### 1.4 Les ports 80 et 443 libres sur le serveur

Caddy a besoin des ports **80** (obtention du certificat, redirection vers HTTPS) et **443** (HTTPS). Dans une
invite de commandes :

```bat
netstat -ano | findstr ":80 :443"
```

Si une ligne `LISTENING` apparaît sur `0.0.0.0:80` ou `0.0.0.0:443`, un autre programme les utilise : notez son
numéro (dernière colonne) et cherchez-le avec `tasklist /FI "PID eq <numéro>"`. Le numéro `4` (« System ») désigne
souvent IIS ou un service web Windows : à arrêter ou à déplacer avant d'aller plus loin.

## 2. Pare-feu Windows

Dans **PowerShell administrateur** :

```powershell
# Autoriser HTTP et HTTPS entrants (pour Caddy)
New-NetFirewallRule -DisplayName "Caddy HTTP/HTTPS (Prestige)" -Direction Inbound -Protocol TCP `
  -LocalPort 80,443 -Action Allow

# Payara 8080 : réservé au réseau local de la pharmacie
New-NetFirewallRule -DisplayName "Prestige Payara 8080 (réseau local seulement)" -Direction Inbound `
  -Protocol TCP -LocalPort 8080 -RemoteAddress LocalSubnet -Action Allow
```

Puis repérez les **anciennes règles** qui ouvraient 8080 à tout le monde :

```powershell
Get-NetFirewallPortFilter | Where-Object LocalPort -eq 8080 | Get-NetFirewallRule |
  Format-Table DisplayName, Enabled, Profile, Action
```

Désactivez celles qui ne sont pas la nouvelle règle « réseau local seulement » (clic droit → Désactiver dans
« Pare-feu Windows Defender avec fonctions avancées de sécurité », ou
`Disable-NetFirewallRule -DisplayName "<nom exact>"`). Vérifiez aussi qu'aucune règle **par programme** n'autorise
`java.exe` sur tous les ports pour tout le monde : une telle règle contournerait la restriction.

**Si les postes ou terminaux sont sur un autre sous-réseau** que le serveur (plusieurs réseaux Wi-Fi, VLAN), remplacez
`LocalSubnet` par les plages concernées, par exemple `-RemoteAddress 192.168.1.0/24,192.168.2.0/24`. Testez un poste
local juste après (étape 6).

**Ne jamais ouvrir sur Internet** : 4848 (console d'administration Payara), 8181 (HTTPS interne de Payara), 3306
(base de données), 3389 (bureau à distance).

## 3. Redirections de port sur la box

Dans l'interface de la box (menu « NAT », « Redirection de ports » ou « Serveur virtuel »), vers l'IP locale du
serveur (ex. `192.168.1.100`) :

| Port externe (Internet) | Port interne (serveur) | Rôle |
|---|---|---|
| 80 | 80 | obtention et renouvellement du certificat, redirection vers HTTPS |
| 443 | 443 | HTTPS (Inventaire, Prestige Mobile, navigateurs, notifications de paiement) |
| 8080 | **443** | HTTPS pour **Prestige Pharmacien** (son champ « Port » reste 8080 pour le local) |

- **Supprimez l'ancienne redirection 8080 → 8080** si elle existe : c'est elle qui exposait Payara en clair. Faites-le
  **à l'étape 8**, une fois HTTPS vérifié, si vous voulez une transition sans coupure.
- Si la box ne sait pas rediriger un port externe vers un **autre** port interne (8080 → 443), voir « Dépannage ».
- Aucune règle 4848, 8181 ou 3306.

## 4. Installer Caddy

1. Créez le dossier `C:\caddy`, avec les sous-dossiers `C:\caddy\data` et `C:\caddy\logs`.
2. Téléchargez Caddy depuis le **site officiel** : `https://caddyserver.com/download`, plateforme **Windows amd64**
   (ou la page des versions `https://github.com/caddyserver/caddy/releases`, fichier `caddy_<version>_windows_amd64.zip`).
3. Placez l'exécutable dans `C:\caddy` et renommez-le **`caddy.exe`**.
4. Vérifiez : `C:\caddy\caddy.exe version` affiche un numéro de version 2.x.

## 5. Le fichier de configuration `C:\caddy\Caddyfile`

Créez le fichier `C:\caddy\Caddyfile` (sans extension) avec le Bloc-notes :

```caddyfile
{
	# Adresse pour les avis de Let's Encrypt (certificat bientôt expiré, problème de renouvellement)
	email informatique@ma-pharmacie.ci
	# Certificats et compte Let's Encrypt rangés dans un dossier connu (sauvegarde, dépannage)
	storage file_system {
		root C:/caddy/data
	}
}

prestige.ma-pharmacie.ci {
	# Seule l'application Prestige est publiée sur Internet.
	handle /prestige/* {
		# Caddy ajoute lui-même X-Forwarded-For, X-Forwarded-Proto et X-Forwarded-Host.
		reverse_proxy 127.0.0.1:8080
	}
	# Tout le reste : rien à voir.
	handle {
		respond "Not found" 404
	}

	# Journal d'accès (facultatif). Il contient les adresses demandées : à garder privé.
	log {
		output file C:/caddy/logs/acces.log {
			roll_size 10MiB
			roll_keep 10
		}
	}
}
```

Explications :

- **Version minimale**, si vous préférez : `prestige.ma-pharmacie.ci { reverse_proxy 127.0.0.1:8080 }`. Elle
  fonctionne aussi ; la version ci-dessus évite seulement de publier autre chose que `/prestige`.
- Les **en-têtes `X-Forwarded-*`** (adresse réelle du client, protocole `https`, nom demandé) sont ajoutés
  automatiquement par `reverse_proxy` : rien à écrire.
- Caddy redirige tout seul `http://prestige.ma-pharmacie.ci` vers `https://…`.
- **Plus strict (facultatif)** : remplacez `handle /prestige/*` par `handle /prestige/api/*` pour ne publier que
  l'API des applications (l'écran web de Prestige ne sera alors plus accessible depuis Internet).
- Les chemins Windows s'écrivent avec `/` dans ce fichier (`C:/caddy/...`).

Vérifiez la syntaxe :

```bat
C:\caddy\caddy.exe validate --config C:\caddy\Caddyfile
```

## 6. Premier démarrage, à la main

Dans une invite de commandes **administrateur** :

```bat
cd /d C:\caddy
caddy.exe run --config C:\caddy\Caddyfile
```

Attendez dans les messages une ligne du type `certificate obtained successfully` pour votre nom (quelques secondes
à une minute). En cas d'erreur, voir « Dépannage ». Gardez la fenêtre ouverte et faites les vérifications :

1. **Depuis un téléphone en 4G** (Wi-Fi coupé), ouvrez
   `https://prestige.ma-pharmacie.ci/prestige/api/v1/officine` : le navigateur affiche un **cadenas** et une
   réponse JSON avec le nom de l'officine.
2. Toujours en 4G : `https://prestige.ma-pharmacie.ci:8080/prestige/api/v1/officine` donne la même chose (règle
   8080 → 443 de la box).
3. **Sur le réseau local**, un poste ou un terminal : `http://192.168.1.100:8080/prestige/api/v1/officine` répond
   **comme avant**.
4. Depuis un ordinateur extérieur (ou un téléphone en 4G avec une application de terminal) :

   ```bash
   curl -i https://prestige.ma-pharmacie.ci/prestige/api/v1/officine        # 200 + JSON
   curl -i https://prestige.ma-pharmacie.ci/prestige/api/v1/licence/find    # 200 (lisible sans session)
   curl -i https://prestige.ma-pharmacie.ci/prestige/api/v1/ws/inventaires  # 401 (reste fermé sans session)
   curl -i http://prestige.ma-pharmacie.ci/                                  # 308 vers https://
   ```

Arrêtez ensuite Caddy avec **Ctrl+C**.

## 7. Installer Caddy comme service Windows

Pour que Caddy démarre avec Windows, même sans session ouverte. Invite de commandes **administrateur** (attention :
l'espace **après** chaque `=` est obligatoire avec `sc.exe`) :

```bat
sc.exe create caddy start= auto binPath= "C:\caddy\caddy.exe run --config C:\caddy\Caddyfile"
sc.exe description caddy "Proxy HTTPS devant Prestige (Payara)"
sc.exe failure caddy reset= 86400 actions= restart/5000/restart/5000/restart/60000
sc.exe start caddy
sc.exe query caddy
```

- `start= auto` : démarrage automatique ; `failure` : redémarrage automatique en cas d'arrêt anormal.
- `sc.exe query caddy` doit indiquer `RUNNING`. Refaites les vérifications 1 à 4 de l'étape 6.
- **Après une modification du Caddyfile** : `C:\caddy\caddy.exe validate --config C:\caddy\Caddyfile`, puis
  `sc.exe stop caddy` et `sc.exe start caddy` (ou `Restart-Service caddy` dans PowerShell).

**Alternative : NSSM** (outil gratuit `https://nssm.cc`, utile si vous l'employez déjà pour d'autres services) :

```bat
nssm install caddy C:\caddy\caddy.exe run --config C:\caddy\Caddyfile
nssm set caddy AppDirectory C:\caddy
nssm start caddy
```

N'utilisez qu'**une** des deux méthodes.

## 8. Régler les applications, puis fermer l'accès en clair

Sur chaque appareil, dans la Configuration (protégée par le code administrateur) :

| Application | Adresse locale | Adresse distante | Port |
|---|---|---|---|
| **Prestige Pharmacien** | inchangée (ex. `192.168.1.100`) | `https://prestige.ma-pharmacie.ci` | **8080** (champ unique, inchangé) |
| **Prestige Inventaire** | inchangée, port local `8080` | `https://prestige.ma-pharmacie.ci` | port distant **443** |
| **Prestige Mobile** (4.1.0 et suivantes) | inchangée, **http** | `prestige.ma-pharmacie.ci` avec **https** (ou `https://prestige.ma-pharmacie.ci`) | **8080** (champ « Port », pour le local) ; le distant en https utilise **443** |

1. Utilisez « Tester la connexion », passez en mode **Distant**, connectez-vous **en 4G** et faites une lecture
   simple (accueil, recherche d'un produit).
2. Testez **chaque modèle** de terminal (Sunmi V2s, V3, téléphones). Les appareils Android récents reconnaissent
   Let's Encrypt ; un appareil **très ancien** peut refuser le certificat (message « certificat du serveur refusé ») :
   à repérer avant l'étape suivante.
3. Quand tout fonctionne : **supprimez sur la box l'ancienne redirection 8080 → serveur 8080** (si elle existait et
   n'a pas déjà été remplacée par 8080 → 443). Vérifiez depuis l'extérieur que `http://<IP publique>:8080` **ne
   répond plus** en clair.

**Prestige Mobile** (version **4.1.0** ou suivante ; une version antérieure ne connaît que le HTTP) :

1. Configuration du serveur, protégée par le code administrateur :
   - nouvelle interface : **Réglages › Connexion au serveur** ;
   - interface d'origine : écran **Configuration**, rubrique « Serveur ».
2. **Adresse IP locale** : inchangée, protocole **http**, **Port** `8080`.
3. **Adresse IP distante** : `prestige.ma-pharmacie.ci`, puis **https** (nouvelle interface : appuyer sur le bouton
   `http://` au début du champ, il devient `https://` ; interface d'origine : choix « Protocole du serveur distant »)
   — ou saisir directement `https://prestige.ma-pharmacie.ci` : le choix passe tout seul sur https). Le port **443** est
   pris par défaut ; pour un autre port HTTPS, l'écrire dans l'adresse (`prestige.ma-pharmacie.ci:8443`).
4. **Tester la connexion** : « IP distante joignable (https://prestige.ma-pharmacie.ci) ». Un certificat non
   reconnu donne « Connexion sécurisée (HTTPS) impossible : certificat du serveur refusé » ; https vers le port
   8080 de Payara donne « le serveur ne répond pas en HTTPS sur ce port ».
5. Enregistrer, puis passer en **serveur distant** (« Changer de serveur » sur l'écran de connexion) pour l'essai
   en 4G.

Les réglages déjà en place restent en http, à l'identique : rien à refaire sur les appareils qui n'utilisent que
le réseau local. Une fois tous les appareils en 4.1.0 et réglés en https, l'ancien accès en clair (8080 → 8080) peut
être fermé comme pour les deux autres applications.

Rappel : **dans la pharmacie, utilisez le mode Local**. Certaines box ne savent pas renvoyer vers le serveur une
connexion faite depuis le réseau local vers l'adresse publique (« hairpin NAT ») : le mode Distant en Wi-Fi local
peut alors échouer, c'est normal.

Pour les **paiements Mobile Money par agrégateur** (patch B3, quand il sera appliqué), l'adresse publique à
déclarer sera `PRESTIGE_PAIEMENTS_URL_PUBLIQUE=https://prestige.ma-pharmacie.ci/prestige/api/v1`, et l'URL de
notification `https://prestige.ma-pharmacie.ci/prestige/api/v1/paiements-mobile/notification/<cinetpay|wave>`.

## 9. Sécurité et entretien

- **Ce qui est exposé** : seulement Caddy (80 et 443) et, via lui, `/prestige`. Payara 8080 n'est plus joignable
  depuis Internet (box et pare-feu). La console Payara (4848) et la base de données ne le sont jamais.
- **Comptes** : avec un accès Internet, les mots de passe faibles deviennent un risque réel. Imposez des mots de
  passe solides aux comptes Prestige, en particulier administrateur et pharmacien.
- **Renouvellement** : Caddy renouvelle le certificat tout seul (environ tous les 60 jours). Il faut que les ports
  80 et 443 restent ouverts et que le nom pointe toujours vers la bonne adresse (tâche DuckDNS active).
- **Mises à jour** : de temps en temps, téléchargez la nouvelle version de Caddy, `sc.exe stop caddy`, remplacez
  `caddy.exe`, `sc.exe start caddy`. Gardez Windows à jour.
- **Sauvegardes** : sauvegardez `C:\caddy\Caddyfile` et `C:\caddy\duckdns.ps1`. Le dossier `C:\caddy\data`
  (certificats) peut être sauvegardé mais n'est pas indispensable : Caddy redemande un certificat s'il manque. Ces
  fichiers contiennent des secrets (clé du certificat, jeton DuckDNS) : sauvegarde **non partagée**.
- **Journaux** : `C:\caddy\logs\acces.log` note les adresses demandées. Certaines peuvent contenir une information
  sensible (par exemple une clé de licence dans `licence/save/<clé>`) : accès réservé à l'administrateur.
- **Adresse des clients vue par Prestige** : derrière Caddy, Payara voit toutes les connexions Internet comme
  venant de `127.0.0.1` (la vraie adresse est dans l'en-tête `X-Forwarded-For`). Le Fichier Journal de Prestige et
  toute limite « par adresse IP » côté serveur verront donc `127.0.0.1` pour les accès distants. À signaler à la
  session serveur si une traçabilité par adresse est souhaitée (lire `X-Forwarded-For` seulement quand la requête
  vient de `127.0.0.1`).

## 10. Dépannage courant

| Symptôme | Cause probable | Que faire |
|---|---|---|
| Caddy ne démarre pas : `bind: address already in use` / `Only one usage of each socket address` | un autre programme utilise 80 ou 443 | étape 1.4 (`netstat`, `tasklist`) ; arrêter ou déplacer ce programme |
| Pas de certificat : erreur `challenge failed`, `timeout`, `connection refused` | le nom ne pointe pas vers la bonne IP, ou les ports 80 / 443 ne sont pas redirigés | `nslookup` du nom ; vérifier les redirections de la box et le pare-feu (étapes 2 et 3) ; vérifier l'absence de CGNAT (1.1) |
| Pas de certificat : `too many certificates` / `rate limit` | trop d'essais en peu de temps | attendre (les limites de Let's Encrypt se lèvent après quelques heures) ; corriger la cause avant de réessayer |
| Le fournisseur d'accès bloque le port 80 | fréquent sur certaines offres | Caddy peut obtenir le certificat par le port 443 seul ; si 443 est aussi bloqué, il faut la validation par DNS (version de Caddy avec le module DuckDNS, à choisir sur la page de téléchargement) |
| La box ne permet pas « externe 8080 → interne 443 » | box limitée | Prestige Pharmacien : en attendant, garder l'accès distant par Inventaire ou le navigateur ; ou ajouter à Caddy un second port HTTPS (par exemple `prestige.ma-pharmacie.ci:8443`) et rediriger 8080 → 8443 si la box l'accepte ; ou demander à la session Pharmacien un port distant séparé (comme Inventaire) |
| Navigateur : cadenas OK, mais l'application dit « certificat du serveur refusé » | appareil Android trop ancien, ou date et heure fausses sur l'appareil | vérifier la date et l'heure ; tester un autre appareil ; noter le modèle et la version d'Android |
| `https://…/prestige/api/v1/officine` → **502 Bad Gateway** | Payara arrêté ou n'écoute pas sur 8080 | démarrer le domaine Payara ; tester `http://127.0.0.1:8080/prestige/api/v1/officine` sur le serveur |
| L'écran web de Prestige redirige vers `http://…:8080` | Payara construit une adresse en `http` | sur un serveur de test d'abord, faire lire `X-Forwarded-Proto` par Payara : `asadmin set configs.config.server-config.network-config.protocols.protocol.http-listener-1.http.scheme-mapping=X-Forwarded-Proto` puis redémarrer le domaine. Sans effet sur les applications mobiles (API JSON) |
| Les postes locaux ne joignent plus Payara | règle de pare-feu `LocalSubnet` trop stricte (autre sous-réseau) | élargir `-RemoteAddress` (étape 2) |
| Tout marchait, plus rien depuis ce matin | l'IP publique a changé et DuckDNS n'est pas à jour | contenu de `C:\caddy\duckdns.txt` (`OK` attendu), tâche planifiée active |

Pour voir les messages de Caddy installé en service : arrêtez le service (`sc.exe stop caddy`) et lancez-le à la
main (étape 6) le temps de lire les erreurs.

## 11. Retour arrière

Le réseau local n'est jamais touché : on peut revenir en arrière à tout moment, sans effet sur le comptoir.

1. Arrêter Caddy : `sc.exe stop caddy`, puis `sc.exe config caddy start= disabled` (ou `sc.exe delete caddy` pour le
   retirer ; avec NSSM : `nssm remove caddy confirm`).
2. Sur la box : supprimer les redirections 80, 443 et 8080 → 443.
3. Sur les appareils : remettre l'ancienne adresse distante (ou utiliser le mode Local).
4. Rouvrir l'ancien accès en clair (redirection 8080 → 8080 et règle de pare-feu 8080 pour tous) **n'est pas
   recommandé** : ne le faire que temporairement et en connaissance de cause.
5. Le dossier `C:\caddy` peut être supprimé.

## 12. Alternative : le certificat directement dans Payara (déconseillé ici)

Payara a son propre écouteur HTTPS (port 8181 par défaut, avec un certificat auto-signé, **refusé** par les
applications). On peut y installer un certificat Let's Encrypt : obtenir le certificat avec un outil ACME, le
convertir (PKCS12), l'importer dans le magasin de clés du domaine Payara (`keystore.jks`, alias `s1as`, avec
`keytool`), adapter le mot de passe du magasin, puis redémarrer le domaine. **Et refaire tout cela tous les 60 à
90 jours**, à la main ou par un script. C'est plus long, plus fragile (une erreur bloque tout le domaine Payara, y
compris le local) et sans les avantages de Caddy (renouvellement automatique, redirection HTTP → HTTPS, seul
`/prestige` publié). À réserver au cas où aucun programme supplémentaire ne peut être installé sur le serveur.

## Références

- `prestige_app/docs/HTTPS_ET_TRAFIC_EN_CLAIR.md` : comportement de Prestige Pharmacien (HTTPS en distant, certificat
  reconnu exigé, clair conservé pour le local).
- `prestinv/docs/NOTE_VERSION_FIABILITE.md` : « Adresse https:// acceptée (si le serveur la propose) ; http:// reste
  le défaut ».
- `prestige_vente_app/docs/NOTE_VERSION_4.1.0.md` : Prestige Mobile accepte `https://` depuis la 4.1.0 (choix
  http / https par adresse, 443 par défaut en https, certificat reconnu exigé, clair conservé pour le local) ;
  `prestige_vente_app/lib/serveur/adresse_serveur.dart` : construction de l'adresse.
- `prestige_vente_app/docs/serveur/B3_PAIEMENTS.md` : adresse publique HTTPS requise pour les notifications de
  paiement ; `prestige_vente_app/docs/serveur/DEMANDE_PHOTO_POINTAGE.md` § 3.5 : « HTTPS en production ».
