// lib/borne/borne_kiosque.dart
// Mode kiosque Android (épinglage d'écran) via le canal « prestige/kiosque » (KiosqueBridge.kt).
// Sans Device Owner, Android demande une confirmation à l'utilisateur (épinglage standard).
// Hors Android (tests) : aucun effet ; [BorneKiosque.simule] permet de vérifier les appels.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract class BorneKiosque {
  /// Épingle l'écran ; renvoie l'état (« aucun », « epingle », « verrouille »).
  Future<String> demarrer();
  Future<void> arreter();

  /// Kiosque de l'appli (canal Android) ; remplacé dans les tests.
  static BorneKiosque instance = CanalKiosque();
}

class CanalKiosque implements BorneKiosque {
  static const MethodChannel canal = MethodChannel('prestige/kiosque');

  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<String> demarrer() async {
    if (!_android) return 'aucun';
    try {
      return await canal.invokeMethod<String>('demarrer') ?? 'aucun';
    } catch (_) {
      return 'aucun';
    }
  }

  @override
  Future<void> arreter() async {
    if (!_android) return;
    try {
      await canal.invokeMethod<bool>('arreter');
    } catch (_) {}
  }
}

/// Kiosque simulé (tests) : compte les appels.
class KiosqueSimule implements BorneKiosque {
  int demarrages = 0;
  int arrets = 0;
  bool epingle = false;

  @override
  Future<String> demarrer() async {
    demarrages++;
    epingle = true;
    return 'epingle';
  }

  @override
  Future<void> arreter() async {
    arrets++;
    epingle = false;
  }
}
