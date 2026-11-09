# Prestige Mobile 4.12.0+41 : demandes 59 et 60 livrées par le serveur

Le pharmacien a validé le 08/11 :
- **demande 59** : clôture « entrer le reçu » d'un BL, puis retour en attente des manquants **sans sortie de stock**
  (option a) ;
- **demande 60** : droit `P_RESERVE_SUGGESTION` (« Voir les suggestions de réserve ») ; la création d'une suggestion
  reste permise sans ce droit.

Le serveur a livré les deux demandes (notices `REPONSE_SERVEUR_2026-11-08.md` et
`REPONSE_SERVEUR_2026-11-08_demande60.md`), sur des branches pas encore fusionnées dans sa branche principale. Cette
version confronte chaque appel de 4.11.0 au **code** du serveur (`CommandeRessource`, `ReceptionMobileRessource`,
`ManquantsReceptionService`, `CommandeServiceImpl`, `MobileClientRefService`, `SuggestionReserveRessource`,
`ReserveRessource`, `Droits`) et ajoute ce qui manquait.

**Repli complet** : sur un serveur sans ces capacités, l'application se comporte exactement comme 4.11.0.

## 1. Écarts entre 4.11.0 et le contrat réel (corrigés)

| Point | 4.11.0 | Contrat réel | 4.12.0 |
|---|---|---|---|
| `X-Client-Ref` sur `validerbl?mode=RECU` | absent | facultatif, même clé = même réponse (type `CLOTURE_BL_RECU`) ; un refus n'est pas gardé | clé `BLR-…` créée à l'ouverture du bilan, la même à chaque essai |
| Refus `AUCUN_RECU` (aucune ligne n'a de lot) | message brut, fenêtre « refusée » | HTTP **200**, `{success:false, code:"AUCUN_RECU", msg}` ; rien n'entre, le BL reste ouvert | message clair « Rien n'est entré… le BL reste ouvert », on reste sur le bilan |
| Autre refus de la clôture au reçu | même fenêtre que le résultat | `{success:false, msg}` (BL déjà clos), 403 `interdit` (`P_ENTREE_EN_STOCK`) | fenêtre de refus, on reste sur le bilan |
| Réponse de la clôture | `ecarts:[{cip, nom, commande, recu, manquant}]` lus | en plus : `mode`, `detailId`, `ug`, `totalManquant`, `reserve` | tout lu ; `totalManquant` affiché ; `reserve` ignoré (voir 3) |
| Capacité `retourManquants` | non lue | `GET v1/reception/parametres` | lue dans la **même** requête que `clotureRecu` |

Formats confirmés tels quels : `clotureRecu: true`, `PUT v1/commande/validerbl/{id}?mode=RECU`, écarts
`manquant = max(0, commande − reçu)`, seules les lignes en écart listées.

## 2. Retour en attente des manquants (demande 59)

Seulement si le serveur annonce `retourManquants` (sinon : aucun bouton, aucune requête de plus, fenêtre de 4.11.0).

- **Avant la clôture** : la confirmation « Entrer ce qui a été reçu ? » donne les écarts **calculés par Prestige** sur
  les lots enregistrés (`GET v1/reception/{blId}/ecarts`, mode `PROVISOIRE`). Lecture en échec : le calcul de l'écran,
  comme en 4.11.0.
- **Après la clôture** : le bilan est **relu** (`GET …/ecarts`, mode `RECU`, quantités écrites à la clôture), avec le
  total manquant. Si un retour des manquants existe déjà (`retourManquants` non nul), sa référence et son état sont
  affichés : « Retour RF-… (en attente de validation) : à valider dans « Retour fournisseur » sur Prestige ; rien ne
  sort du stock. » Aucun bouton.
- **« Créer un retour en attente des manquants »** (s'il y a des manquants et aucun retour) : `POST
  v1/reception/{blId}/retour-manquants` avec `X-Client-Ref` (`BLM-…`, la **même** pour chaque essai de la fenêtre :
  un délai dépassé puis un nouvel essai ne créent jamais deux retours).
  - créé : « Retour RF-… créé, en attente de validation sur Prestige : rien ne sort du stock (n ligne(s), m
    boîte(s)) » ;
  - `deja:true` : « Retour RF-… déjà créé (en attente de validation) » ;
  - 403 `interdit` (ni `P_SM_RETOUR_FRS` ni `P_VALIDER_RETOUR_FRS`) : message du serveur, le bouton disparaît, **jamais
    de déconnexion** ;
  - 409 `BL_NON_ENTRE_AU_RECU`, 409 `AUCUN_MANQUANT`, 404 `BL_INCONNU` : message clair, le bouton disparaît ;
  - serveur injoignable : message, le bouton reste (même clé au nouvel essai).
- La validation du retour reste sur Prestige (écran « Retour fournisseur ») : elle ne sort rien du stock.

## 3. Fenêtre « réserve après entrée »

Prestige Mobile **n'a pas** cette fenêtre : le champ `reserve` de la clôture n'a jamais été lu par l'application.
Rien n'est donc proposé après l'entrée, avec ou sans `voirSuggestions` (garde-fou `manquants_bl_garde_test`).

## 4. Droit « Voir les suggestions de réserve » (demande 60)

- 4.11.0 lisait déjà `voirSuggestions` (`GET v1/reserve/droits`) : contrat confirmé (présence du droit dans la
  session ; champ absent = serveur plus ancien = comportement d'avant).
- **Nouveau** : un 403 `{interdit:true, msg:"Droit manquant : Voir les suggestions de réserve"}` sur une route des
  suggestions (en attente, ouvrir, quantité, retirer une ligne, traiter, réessayer) est :
  - affiché comme **droit manquant** (« Droit manquant : … »), sans « Réessayer » (inutile) et **sans
    déconnexion** (ce n'est pas un 401) ;
  - **constaté** : les suggestions ne sont plus proposées, comme avec `voirSuggestions:false`, jusqu'à la prochaine
    lecture des droits (cas d'un droit retiré pendant la session).
  - Le refus « Droit manquant : Traiter la réserve » (contrôlé avant sur les actions) ne retire pas les suggestions.
- `POST creer` et `GET motifs` restent permis : inchangé (« Demande … créée : elle sera traitée par une personne
  habilitée »).

## 5. Hors ligne

La clôture d'un BL et le retour des manquants sont **en ligne seulement** : jamais mis dans la file d'envoi
(`stock_sender`). Hors ligne : capacités absentes (aucun bouton), message « Disponible en ligne uniquement ».
L'idempotence est assurée par `X-Client-Ref` sur les appels en ligne.

## Points remontés au serveur (pour le pharmacien)

Voir le rapport de cette version. En bref :
- un BL dont le retour des manquants a été **abandonné** (`is_Abandoned`) ne peut plus recevoir de nouveau retour des
  manquants : `retourExistant` ne filtre que `delete` ; `deja:true` renvoie le retour abandonné ;
- la réponse `deja:true` ne porte ni `lignes` ni `totalManquant` (la notice laisse entendre la même forme) ;
- sur les **actions** des suggestions, le refus `P_RESERVE_SUGGESTION` passe **avant** le contrôle de session ; et
  tant que la migration `V7.2.70` n'est pas passée, les routes des suggestions refusent tout le monde (la clôture,
  elle, tolère l'absence du droit en base) ;
- la notice de la demande 60 dit que la fenêtre « Réserve après entrée » n'est pas traitée, alors que la branche de
  la demande 59 renvoie déjà `reserve: []` sans le droit (comportement retenu par l'application : aucun effet).

## Tests (catégories de la CI)

- **Unitaires** — `test/manquants_bl_regles_test.dart` : écarts (RECU, PROVISOIRE, COMPLET, BL_INCONNU), retour
  (création, `deja`, 409, 404), `AUCUN_RECU`, clés `X-Client-Ref`, refus du droit des suggestions.
- **Écrans** — `test/manquants_bl_test.dart` : `AUCUN_RECU` (bilan gardé, même clé), autre refus, capacité :
  écarts provisoires, relecture, retour créé, `deja`, retour existant, 403, délai dépassé (même clé), aucun manquant ;
  sans capacité et passerelle 4.11.0 : inchangé ; écran Réserve sur 403.
- **Intégration** — `test/manquants_bl_integration_test.dart` : passerelle hors ligne autour du client HTTP, en
  ligne (tout passe, `X-Client-Ref`) et hors ligne (aucune requête, file vide).
- **E2E** — `test/manquants_bl_e2e_test.dart` : application entière (Sunmi V2s) : serveur complet, `AUCUN_RECU`,
  profil sans droit retours (403), serveur 4.11.0.
- **Réseau** — `test/reseau/manquants_bl_reseau_test.dart` (vrai HTTP) : capacités (une requête), `X-Client-Ref`,
  `AUCUN_RECU` en 200, 403 sans reconnexion, écarts 404, retour 409/404/403/coupé, suggestions 403 (« Voir » et
  « Traiter »), `creer` et `motifs` permis.
- **Ergonomie** — `test/manquants_bl_ergonomie_test.dart` : V2s, V3, 360 × 800 dp, tablette, texte ×1 et ×1,3.
- **Performance** — `test/performance/manquants_bl_perf_test.dart` : 100 000 lignes d'écarts lues < 1 s, nombre de
  requêtes (avec / sans capacité), fenêtre de 500 lignes < 2 s.
- **Non-régression** — `test/manquants_bl_garde_test.dart` : clôture classique inchangée, `X-Client-Ref`, jamais
  dans la file d'envoi, `reserve` jamais lu, routes des suggestions contrôlées sauf `creer` et `motifs`.
