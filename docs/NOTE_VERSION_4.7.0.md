# Prestige Mobile 4.7.0+28 — nom de cet appareil dans Prestige (« Ventes terminées »)

Demande du serveur du 25/10/2026 (`docs/notices/DEMANDE_SESSION_MOBILE_NOM_APPAREIL.md` du serveur, commit
43c4acf8). Dans « Ventes terminées », les ventes faites sur un Sunmi montraient l'adresse IP comme poste, parce que
l'application n'envoyait pas d'en-tête `X-Poste`.

## Vérifié dans le code du serveur (lecture seule, branche claude/new-session-xm8ptu, 582a72bc)

- `filter.AuthenticationFilter` (filtre JAX-RS global) appelle `util.ContexteRequete.poser` en tête de CHAQUE
  requête de l'API, routes mobiles et connexion comprises.
- `ContexteRequete` : `URLDecoder.decode(X-Poste, "UTF-8")` (en cas d'erreur, la valeur brute), puis
  `nettoyer` : `replaceAll("[^\p{L}\p{N} ._\-]", "")`, `trim()`, vide → aucun nom, plus de 60 caractères →
  `substring(0, 60)` (unités UTF-16, coupé après le `trim`).
- Poste de saisie : `TPreenregistrement.completerPosteSaisie` (`@PrePersist`, création de la vente). Poste
  d'encaissement et adresse IP : `marquerPosteEncaissement`, appelé à la clôture comptant (`vente/cloturer/vno`),
  assurance (`vente/cloturer/assurance`) et dépôt (`clotureVenteDepot`, `clotureVenteDepotAgree`). Paiement mobile
  money : la clôture comptant est faite par la requête qui confirme le paiement. Si c'est l'application qui relit le
  statut, le poste d'encaissement est son nom. Si c'est la notification du fournisseur (webhook), c'est le nom
  réseau de l'appelant. Le poste de saisie reste celui de l'appareil dans les deux cas.
- Journal des actions (`TEventLog`) : même nom.
- Sans en-tête : nom réseau (résolution bornée) ou adresse IP, comme avant.
- **Écart avec la notice** : la ligne de journal de la **connexion** (« Authentification … nom poste … ») et le
  journal RH des connexions prennent toujours le nom réseau (`UserServiceImpl.getHostName`), pas `X-Poste`. Les
  ventes et les autres actions ont bien le nom de l'appareil.

## Ce qui change

| Sujet | Dans l'application |
|---|---|
| Nom par défaut | Marque et modèle de l'appareil (« SUNMI V2s »), déjà lus au démarrage par le journal du terminal (canal natif existant, `Build.MANUFACTURER` et `Build.MODEL`). Aucun paquet ajouté : `device_info_plus` n'est pas nécessaire. |
| Réglage | Réglages → « Licence & appareil » → « Nom de cet appareil » (par exemple « Caisse mobile 1 »). Il est gardé sur l'appareil, dans les préférences : ce n'est pas un secret. Un aperçu montre le nom tel que Prestige l'enregistrera ; le nom est nettoyé à l'enregistrement. « Nom par défaut » revient à la marque et au modèle. |
| Première connexion | Une fenêtre propose de nommer l'appareil, une seule fois, si aucun nom n'a été saisi. « Plus tard » est possible : le nom par défaut part alors. |
| En-tête | `X-Poste: Uri.encodeComponent(nom nettoyé)` sur **toutes** les requêtes vers Prestige : tous les clients Dio (session, JSON, RH, mobile, hors ligne, stock, images, ordonnances, support, sondes, test de connexion, diagnostic de la borne). Sans nom (marque et modèle inconnus, rien de saisi) : pas d'en-tête, le serveur garde le nom réseau. |
| Nettoyage | Mêmes règles que le serveur ; une espace laissée en fin par la coupure à 60 caractères, ou une demi-lettre hors du plan de base, est retirée, comme le ferait le serveur. Les résultats ont été recoupés sur 24 cas avec le code Java du serveur : accents, arabe, chiffres ²½٣, émoji, tabulations, espace insécable, accent décomposé, 60 caractères. |
| Rien d'autre | Routes, corps des requêtes et connexion inchangés. Le nom ne contient ni jeton ni identifiant : jamais l'identifiant du terminal. |

## Tests

- `test/nom_appareil_test.dart` (unitaires) : nettoyage, longueur, encodage, nom par défaut et saisi, intercepteur.
- `test/nom_appareil_e2e_test.dart` (application entière) :
  - sans nom : « SUNMI V2s » sur toutes les requêtes ;
  - première connexion : « Caisse mobile 1 » saisi, vente faite et terminée, en-tête sur la création (`vente/add/vno`)
    et la clôture (`vente/cloturer/vno`), nom absent des corps et des routes ;
  - « Plus tard ».
- `test/reseau/nom_appareil_reseau_test.dart` (vrai HTTP) : connexion, client JSON, vérification du déploiement,
  coupure et reprise, aucun en-tête sans nom.
- `test/parametres_test.dart` (ergonomie) : champ des réglages sur téléphone 360 dp et Sunmi V2s, texte ×1,3 et ×2.
- `test/nom_appareil_garde_test.dart` (non-régression) : tout Dio créé dans `lib/` reçoit l'intercepteur ; aucun
  autre client HTTP.
- `test/performance/nom_appareil_perf_test.dart` : 20 000 requêtes en moins de 400 ms ; valeur de l'en-tête gardée.

## Vérification à l'officine

1. Réglages → « Licence & appareil » → « Nom de cet appareil » : saisir « Caisse mobile 1 », puis Enregistrer.
2. Faire et terminer une vente. Dans Prestige, « Ventes terminées » : colonne P = « Caisse mobile 1 », et le filtre
   par poste retrouve la vente.
3. Sans nom saisi : la marque et le modèle de l'appareil.
