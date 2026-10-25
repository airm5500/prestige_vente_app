// Configuration commune des tests (lue par flutter test pour chaque fichier de test/ et de ses sous-dossiers).
// 4.7.1 : le nom de cet appareil est obligatoire ; sans nom enregistré, l'étape s'ouvre au lancement et les réglages
// ne se quittent pas. Chaque test part d'un appareil déjà nommé (en mémoire seulement), sauf ceux qui testent
// l'étape : ils repartent d'une instance neuve (NomAppareil.reinitialiser, AppE2E.preparer(nomAppareil: null)).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    NomAppareil.reinitialiser();
    NomAppareil.instance.enregistrerEnMemoire('Poste test');
  });
  await testMain();
}
