# Prestige Pointage 1.1.0+2 — terminal sans reconnaissance d'empreinte Sunmi

Livrée avec Prestige Mobile V3 5.3.0+53 (même écran de pointage, `lib/rh`). Détail : `docs/NOTE_VERSION_5.3.0.md`.
Même identifiant (`com.dici.prestigepointage`), même nom, même icône, mêmes permissions.

- **Borne sur un SUNMI V3 (Android 13, sans le service `com.sunmi.fingerprintservice`)** : bandeau « Ce terminal ne
  permet pas la reconnaissance par empreinte. Pointez avec votre badge ou votre code personnel. », boutons « Scanner
  mon badge » et « Saisir mon code personnel » ; pas de lien technique en mode borne.
- **Administration** (code administrateur) :
  - « Confirmer le pointage par empreinte » (désactivé par défaut) : après le badge ou le code, empreinte Android
    demandée ; annulée ou refusée → pointage non enregistré, nouvel essai possible ; aucune empreinte enregistrée, pas
    de lecteur, lecteur en panne → pointage enregistré avec une mention. Android accepte toute empreinte enregistrée
    sur le terminal : cela décourage la fraude mais n'identifie pas la personne ;
  - « Lecteur d'empreinte : détails techniques » : diagnostic du lecteur.
- **Ancien terminal Sunmi** (service présent) : pointage par empreinte, enrôlement et empreintes partagées inchangés.
