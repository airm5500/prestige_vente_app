# Prestige Mobile — note de version 4.1.1 (versionCode 13)

Suite de la 4.1.0+12 (pas encore publiée sur le magasin Sunmi, dernière version publiée : 3.3.1 / 7).
Numérotation : `docs/VERSIONS_SUNMI.md` (correction / petit réglage → 4.1.**1**, +N augmenté de 1 : **4.1.1+13**).

## Demande du pharmacien

> « Sur le ticket de prévente, l'affichage des produits doit être lié à un paramètre afficher ou pas. »

## Tickets de prévente imprimés par l'application

| Ticket | Où | Code | Produits avant 4.1.1 |
|---|---|---|---|
| Prévente comptant (comptoir) | Vente (nouvelle version) : « Prévente » ; ancienne version : onglet Vente ; réimpression depuis « Préventes à encaisser » (les deux versions) | `ReceiptService.printPreventeTicket` | **non** (ticket minimaliste : en-tête, PRE-VENTE + date, NET A PAYER, QR / code-barres, référence, vendeur) |
| Prévente assurance / carnet (comptoir) | Vente assurance, Vente carnet (nouvelle et ancienne version) ; réimpression (historique carnet, liste des préventes assurance de l'ancienne version) | `ReceiptService.printAssurancePreventeTicket` | **non** (client, patient, matricule, total brut, part assurance, part client, code, référence) |
| Prévente provisoire (hors ligne) | mêmes écrans, serveur injoignable | mêmes fonctions (`provisoire`) | non |
| Prévente de la borne | Borne libre-service | `BorneTicket` → `ReceiptService.printBorneTicket` | **oui**, sauf « Ticket discret » (réglage de la borne) |

Chaque ticket existe en impression Sunmi et en **aperçu à l'écran** (mode test d'impression), qui suivent le même
réglage. L'application ne produit **aucun PDF** de ticket de prévente (les PDF existants sont les rapports hors
ligne, le journal, les proformas, les ajustements). Les tickets de **vente encaissée** (comptant, assurance, carnet)
ont leur propre code et ne changent pas.

## Nouveau réglage : « Afficher les produits sur le ticket de prévente »

- **Nouvelle interface** : Réglages › **Impression** (interrupteur sous « Afficher le QR / code-barres (vente) »).
- **Interface d'origine** : écran **Configuration**, rubrique « Impression » (interrupteur sous « Afficher
  QR/Code-barres (Vente) »).
- Même protection que les autres réglages d'impression (rubrique Impression : sans code administrateur, comme
  avant ; Configuration d'origine : même écran que les autres réglages). « Rétablir les valeurs par défaut »
  (Impression) le désactive. Résumé de la rubrique : « · produits sur la prévente » quand il est activé.
- Clé : `afficher_produits_ticket_prevente_v1` (SharedPreferences).

**Valeur par défaut : désactivé**, c'est-à-dire le comportement actuel. Les tickets de prévente du comptoir
n'avaient pas de produits : un réglage activé par défaut aurait changé tous les tickets de prévente imprimés dès la
mise à jour. Désactivé, chaque ticket est **identique, appel par appel à l'imprimante**, à celui de la 4.1.0 (test
de non-régression).

**Activé**, les tickets de prévente du comptoir (comptant, assurance, carnet, provisoires compris, impression et
aperçu) impriment, après l'en-tête (comptant) ou après client / patient / matricule (assurance, carnet) :

```
EFFERALGAN 500MG
  2 x 1 200                2 400
PARACETAMOL BIOGARAN 1G CPR EFFV
B/20
  1 x 950                    950
--------------------------------
3 articles
```

puis le reste du ticket **sans changement** : totaux (NET A PAYER / Total brut / Part assurance / PART CLIENT),
QR ou code-barres, référence, vendeur, mentions « PROVISOIRE ».

Réimpression depuis une liste (« Préventes à encaisser », historique carnet, liste assurance de l'ancienne version) :
si le réglage est activé, les lignes de la prévente sont relues au serveur (`/vente/deatails`, déjà utilisée pour
reprendre une prévente) ; en cas d'échec, le ticket est imprimé sans produits, comme avant. Réglage désactivé :
aucune requête supplémentaire.

### Borne : réglage propre, inchangé

La borne garde **son** réglage « **Ticket discret** » (Réglages › Borne libre-service), **indépendant** : le
nouveau réglage ne concerne que le comptoir. Une phrase d'aide l'indique dans les deux écrans (Impression et Borne).
Ticket discret : « N articles » au lieu des produits, comme avant.

## Correction : nom de produit long sur deux lignes

Sur les captures de la borne, un nom plus long que la largeur du papier (32 caractères en 58 mm, 48 en 80 mm) était
**coupé sans signe** : « PARACETAMOL BIOGARAN 1G CPR EFFV B/20 » perdait « B/20 ». Désormais (ticket de la borne et
lignes produits de la prévente du comptoir) :

- un nom qui tient reste sur **une** ligne, **à l'identique** ;
- sinon il passe sur **deux** lignes, coupé **à un espace** (un mot n'est coupé que s'il est plus long qu'une
  ligne entière) ;
- au-delà de deux lignes, la fin de la 2e ligne est remplacée par « .. » (le ticket montre que le nom est raccourci).

Code commun : `lib/services/ticket_prevente.dart` (`TicketPrevente`). Les tickets de vente encaissée gardent leur
mise en page (non concernés par la demande).

## Tests

`test/ticket_prevente_test.dart` (dans la liste de la CI) :

- **unitaires** : coupure des noms (une ligne, deux lignes, mot trop long, « .. »), lignes produits, nombre
  d'articles, lignes sans nom ignorées, aucune requête si le réglage est désactivé, réglage enregistré et relu ;
- **contenu du ticket** (imprimante Sunmi simulée sur le canal `sunmi_printer_plus`, aperçu du mode test) :
  produits présents / absents selon le réglage pour la prévente comptant (58 et 80 mm), assurance et carnet,
  provisoire ; totaux, QR / code-barres et référence identiques ; nom long sur deux lignes ;
- **borne** : nom de la capture sur deux lignes, ticket discret inchangé ;
- **non-régression** : avec les réglages par défaut, **tous** les tickets (préventes, ventes, ventes assurance,
  borne ; 58 / 80 mm ; QR / code-barres ; provisoire ou non ; Sunmi et aperçu : 80 cas) sont identiques à ceux de
  la 4.1.0, enregistrés dans `test/ticket_prevente_reference.json` avant toute modification ;
- **écrans** : interrupteur de Réglages › Impression (désactivé par défaut, appliqué et enregistré, phrase d'aide
  sur la borne, « Rétablir les valeurs par défaut ») et de la Configuration d'origine (application entière, Sunmi
  V2s).

Outil commun : `test/outils/ticket_capture.dart` (voir `test/README.md`).

Les captures PNG de la borne (`docs/maquettes/captures_borne/`, outil manuel `APERCUS=1`) ne sont pas régénérées
par la CI.
