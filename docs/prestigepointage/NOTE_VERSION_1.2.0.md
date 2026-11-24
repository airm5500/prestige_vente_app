# Prestige Pointage 1.2.0+3 — heure du serveur fausse

Livrée avec Prestige Mobile V3 5.5.0+55 (même écran de pointage, `lib/rh`). Détail : `docs/NOTE_VERSION_5.5.0.md`.
Même identifiant (`com.dici.prestigepointage`), même nom, même icône, mêmes permissions.

- **Heure du serveur fausse** (serveur `plan/24112026`, HTTP 423 `horlogeBloquee`) : le pointage n'est ni refusé ni
  perdu ; la borne affiche « En attente d'envoi (heure du serveur à corriger) », le message du serveur tel quel, puis
  « Pointage gardé sur le terminal (HH:MM) : envoyé à Prestige quand l'heure du serveur sera corrigée. » L'heure de
  lecture est conservée ; la borne reste « en service » (pas « hors ligne », pas « heure du terminal incorrecte »).
- Aucune écriture relancée pendant le blocage : la borne lit seulement `GET v1/horloge/public` une fois par minute ;
  dès que l'heure est corrigée (OK / REGULARISATION, ou un pointage accepté), la file est envoyée seule, comme au
  retour en ligne (même identifiant : aucun doublon). Photos de contrôle : gardées, envoyées ensuite.
