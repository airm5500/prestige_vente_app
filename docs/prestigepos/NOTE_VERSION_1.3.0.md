# PrestigePOS 1.3.0 (versionCode 9)

Version de PrestigePOS construite avec Prestige Mobile **4.5.0+23** (code partagé) : **Google Play, piste « Test
interne »**. Guide pour le pharmacien : `docs/android/README.md` (deux applications dans la Play Console pour ce
dépôt, Prestige Mobile et PrestigePOS, **mêmes secrets**).

## Ce qui change

- **Deuxième application Play** : `com.dici.prestigepos`. Workflow `.github/workflows/play.yml` (le même que sur la
  branche Prestige Mobile, application choisie par la branche) : sur `prestigepos`, version Play construite avec
  `--flavor pos -t lib/main_pos.dart`, contrôlée à chaque envoi (paquet, version 1.3.0+9, targetSdk 36, pages de
  16 Ko) ; App Bundle signé en artefact **`prestigepos-aab`** quand les 4 secrets de la clé d'envoi existent ; envoi
  en Test interne quand `android/DEMANDE_PLAY` de cette branche contient `1.3.0+9` et que `PLAY_SERVICE_ACCOUNT_JSON`
  existe. Une demande de Prestige Mobile arrivée par fusion est ignorée avec un message : deux envois distincts.
- **Signature** : clé d'envoi (secrets / `android/key.properties`) ; sans elle, **clé debug comme avant** : l'APK des
  bornes construit sur le PC du pharmacien ne change pas de signature.
- **targetSdk 36 pour la version Play seulement** (propriété `playStore`) : l'APK des bornes Sunmi garde targetSdk 35,
  donc aucun changement de comportement d'Android 16 (orientation sur grand écran, retour prédictif) pour la borne,
  le kiosque, l'épinglage, le démarrage automatique, les imprimantes. Le manifeste commun désactive en plus le retour
  prédictif et garde l'orientation sur grand écran pour la version Play (neutre en targetSdk 35).
- **Règles de Google Play** vérifiées (guide, section 11) : administrateur de l'appareil sans politique (propriétaire
  seulement par `adb`), tâche verrouillée, alias HOME désactivé par défaut, `RECEIVE_BOOT_COMPLETED`, Bluetooth
  (`neverForLocation`, `BLUETOOTH` / `BLUETOOTH_ADMIN` jusqu'à Android 11), USB hôte facultatif : **aucune déclaration**
  nécessaire pour le test interne ; caméra, micro (module caméra) et position au premier plan à indiquer dans
  « Sécurité des données » avant une piste fermée.
- **Non-régression de Prestige Mobile** : job `prestige-mobile-identique`, référence **4.5.0+23** (commit 872770e,
  avant la fusion). Par rapport à la 4.4.1+22, l'identité de l'APK Prestige Mobile ne change que par le **numéro de
  version** (changement voulu) ; permissions identiques.

## Tests

- `test/prestigepos/pos_play_test.dart` : saveur pos dans le workflow Play, targetSdk non fixé par la saveur, APK
  des bornes sans `playStore`, règles Play ci-dessus (administrateur sans politique, alias HOME désactivé, tâche
  verrouillée, démarrage, Bluetooth, USB).
- `test/android_play_test.dart` (commun aux deux branches) ; suites complètes vertes en local avant l'envoi.
