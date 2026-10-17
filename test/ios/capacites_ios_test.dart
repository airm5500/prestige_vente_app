// 4.5.0 — iPhone / iPad : fonctions natives Android / Sunmi MASQUÉES ou « indisponibles », sans aucun appel natif
// (couche de capacités lib/plateforme/capacites.dart). Android (et les postes de test) : inchangé.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/plateforme/capacites.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/services/fingerprint_service.dart';
import 'package:prestige_vente_app/services/nfc_service.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/borne/borne_kiosque.dart';

/// Canaux natifs écoutés : tout appel est compté (il ne doit y en avoir aucun sur iOS).
final _appels = <String>[];
void _ecouter(String canal) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(canal), (c) async {
    _appels.add('$canal.${c.method}');
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canaux = ['prestige/fingerprint', 'prestige/nfc', 'prestige/kiosque', 'sunmi_printer_plus'];

  setUp(() {
    _appels.clear();
    for (final c in canaux) {
      _ecouter(c);
    }
  });
  tearDown(() {
    CapacitesPlateforme.forcee = null;
    debugDefaultTargetPlatformOverride = null;
  });

  test('plateforme : iOS déduit de defaultTargetPlatform ; Android et postes de test : tout disponible', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final i = CapacitesPlateforme.courant;
    expect([i.ios, i.android, i.imprimanteSunmi, i.empreinte, i.nfc, i.borne, i.pointageLocal, i.pontsAndroid], [true, false, false, false, false, false, false, false]);
    expect(i.camera, isTrue, reason: 'appareil photo disponible sur iOS');
    expect(i.indisponible('Imprimante'), 'Imprimante : indisponible sur iPhone / iPad.');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final a = CapacitesPlateforme.courant;
    expect([a.imprimanteSunmi, a.empreinte, a.nfc, a.borne, a.pointageLocal], everyElement(isTrue));
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(CapacitesPlateforme.courant.imprimanteSunmi, isTrue, reason: 'postes de test : comme Android');
    CapacitesPlateforme.forcee = CapacitesPlateforme.iphoneIpad;
    expect(CapacitesPlateforme.courant.ios, isTrue);
  });

  test('empreinte (iOS) : « indisponible » sans appel natif ; identité générique', () async {
    CapacitesPlateforme.forcee = CapacitesPlateforme.iphoneIpad;
    expect(await FingerprintService.isServiceInstalled(), isFalse);
    await expectLater(FingerprintService.connect(), throwsA(isA<FingerprintException>().having((e) => e.code, 'code', 'PLATEFORME')));
    await expectLater(FingerprintService.enroll(), throwsA(isA<FingerprintException>()));
    expect(await FingerprintService.hardwareInfo(), {'manufacturer': 'Apple', 'model': 'iPhone / iPad'});
    expect(await FingerprintService.hints.isEmpty, isTrue);
    expect(await const SunmiEmpreinte().disponible(), isFalse);
    expect(_appels, isEmpty);
  });

  test('NFC (iOS) : absent, aucun appel ; borne : aucun épinglage', () async {
    CapacitesPlateforme.forcee = CapacitesPlateforme.iphoneIpad;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const nfc = DeviceNfcReader();
    expect(await nfc.availability(), NfcAvailability.absent);
    expect(await nfc.start(), isFalse);
    await nfc.stop();
    await nfc.openSettings();
    expect(await nfc.tags.isEmpty, isTrue);
    expect(await CanalKiosque().demarrer(), 'aucun');
    await CanalKiosque().arreter();
    expect(_appels, isEmpty);
  });

  test('imprimante Sunmi (iOS) : ticket de la borne non imprimé, aucun appel au plugin', () async {
    CapacitesPlateforme.forcee = CapacitesPlateforme.iphoneIpad;
    final ok = await ReceiptService().printBorneTicket(officine: 'PHARMACIE TEST', numero: '12', reference: 'REF-1', lignes: const ['A'], pied: const ['Merci'], codeType: 'QR_CODE');
    expect(ok, isFalse);
    expect(_appels, isEmpty);
  });

  test('Android : les canaux sont bien appelés (comportement inchangé)', () async {
    CapacitesPlateforme.forcee = CapacitesPlateforme.androidSunmi;
    await const DeviceNfcReader().availability();
    expect(await FingerprintService.isServiceInstalled(), isFalse);
    expect(_appels, containsAll(['prestige/nfc.status', 'prestige/fingerprint.isServiceInstalled']));
  });

  test('menus (iOS) : « Pointage local » et « Borne » masqués ; Android : présents', () {
    final local = accueilMenus.firstWhere((m) => m.id == 'empreinte');
    final familles = {for (final f in MenuFamille.values) f: <AccueilMenu>[]};
    CapacitesPlateforme.forcee = CapacitesPlateforme.iphoneIpad;
    expect(local.visible, isFalse);
    expect(orderedMenus(const []).map((m) => m.id), isNot(contains('empreinte')));
    expect(avecMenusAdmin(familles, admin: true)[MenuFamille.ventes]!.map((m) => m.id), isNot(contains('borne_admin')));
    CapacitesPlateforme.forcee = CapacitesPlateforme.androidSunmi;
    expect(local.visible, isTrue);
    expect(avecMenusAdmin(familles, admin: true)[MenuFamille.ventes]!.map((m) => m.id), contains('borne_admin'));
  });
}
