// PrestigePOS 1.14.0 — Prestige Mobile V3 5.1.0 (premier ticket non imprimé sur Sunmi) appliquée aux chemins propres
// à PrestigePOS : détection de l'imprimante intégrée de la borne (ImprimantePos), liaison au démarrage (main_pos),
// ticket de la borne imprimé seulement une fois le service réellement connecté (canal simulé, connexion en retard).
// Données FICTIVES.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_pos.dart';
import 'package:prestige_vente_app/services/imprimante_sunmi.dart';
import 'package:prestige_vente_app/services/largeur_ticket.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messager = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  DateTime? lieA;
  final appels = <String>[];
  final perdues = <String>[];
  bool connecte() => lieA != null && DateTime.now().difference(lieA!) >= const Duration(milliseconds: 300);

  setUp(() {
    lieA = null;
    appels.clear();
    perdues.clear();
    ImprimanteSunmi.reinitialiser(avec: () async => true, pas: const Duration(milliseconds: 30));
    LargeurTicket.reinitialiser();
    messager.setMockMethodCallHandler(ImprimanteSunmi.canal, (call) async {
      appels.add(call.method);
      switch (call.method) {
        case 'BIND_PRINTER_SERVICE':
          lieA ??= DateTime.now();
          return true;
        case 'PRINTER_VERSION':
          return connecte() ? '2.4.1' : 'NOT FOUND';
        case 'PAPER_SIZE':
          return 1;
        case 'GET_UPDATE_PRINTER':
          return connecte() ? 'NORMAL' : 'ERROR';
        default:
          if (!connecte()) perdues.add(call.method);
          return null;
      }
    });
  });
  tearDown(() {
    messager.setMockMethodCallHandler(ImprimanteSunmi.canal, null);
    ImprimanteSunmi.reinitialiser();
    LargeurTicket.reinitialiser();
  });

  test('terminal Sunmi : imprimante intégrée détectée par le fabricant, sans attendre la liaison', () async {
    expect(await detecterSunmi(), isTrue);
    expect(appels, isEmpty, reason: 'aucune liaison nécessaire pour la détection');
  });

  test('ticket de la borne juste après le lancement : commandes envoyées seulement après la connexion réelle', () async {
    ImprimanteSunmi.lierAuDemarrage();
    final ok = await ReceiptService().printBorneTicket(
        officine: 'Pharmacie Fictive', numero: '7', reference: 'REF-FICT-7', lignes: const ['PRODUIT FICTIF x1'], pied: const ['Merci'], codeType: 'QR_CODE');
    expect(ok, isTrue);
    expect(perdues, isEmpty);
    expect(appels, contains('PRINT_TEXT'));
  });

  test('autre appareil : détection comme avant (réponse de la liaison), aucune attente', () async {
    ImprimanteSunmi.reinitialiser(avec: () async => false);
    expect(await detecterSunmi(), isTrue, reason: 'réponse du paquet, comportement d\'avant');
    expect(appels, ['BIND_PRINTER_SERVICE']);
  });

  test('main_pos lie le service d\'impression au démarrage', () {
    expect(File('lib/main_pos.dart').readAsStringSync(), contains('ImprimanteSunmi.lierAuDemarrage();'));
  });
}
