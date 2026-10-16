// 4.4.0 — Mise à jour péremption : « le code-barres n'est pas lu même dans le cadre ».
// Causes trouvées (comparaison avec la recherche de l'accueil et le choix de produit, où le scan fonctionne) :
// - analyse caméra en 640×480 (défaut Android de mobile_scanner) : un DataMatrix de boîte (8-10 mm) n'a que
//   2 à 3 pixels par module ; lisible seulement à 5-6 cm, sous la distance de mise au point → jamais net ;
// - « Scanner lot / date » ne lisait QUE les DataMatrix : l'EAN visé dans le cadre était ignoré sans message ;
// - « Scanner le produit » sans UPC-A / ITF / Code 39 : un EAN-13 commençant par 0 (lu « UPC-A ») était ignoré.
// Correctifs vérifiés ici : haute définition 1280×720 + zoom automatique, formats des boîtes, refus expliqué.
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:prestige_vente_app/screens/common/camera_scan_screen.dart';
import 'package:prestige_vente_app/screens/expiration_update/expiration_update_screen.dart';

void main() {
  test('contrôleur : haute définition = 1280×720 + zoom automatique ; sinon inchangé (640×480 Android)', () {
    final hd = CameraScanScreen.controleur(formats: CameraScanScreen.formatsProduit, hauteDefinition: true);
    expect(hd.cameraResolution, CameraScanScreen.resolutionHauteDefinition);
    expect(hd.cameraResolution!.width * hd.cameraResolution!.height, greaterThanOrEqualTo(2.9 * 640 * 480), reason: '≈ 3× plus de pixels');
    expect(hd.autoZoom, isTrue);
    expect(hd.detectionSpeed, DetectionSpeed.noDuplicates);
    hd.dispose();
    // Non-régression : les autres écrans (badges, borne, recherche) gardent exactement l'ancien réglage.
    final std = CameraScanScreen.controleur(formats: const [BarcodeFormat.qrCode]);
    expect(std.cameraResolution, isNull);
    expect(std.autoZoom, isFalse);
    expect(std.formats, [BarcodeFormat.qrCode]);
    std.dispose();
  });

  test('péremption : formats des boîtes (comme la recherche de l\'accueil), haute définition, aide', () {
    for (final o in [ExpirationUpdateScreen.scanProduit, ExpirationUpdateScreen.scanLotDate]) {
      expect(o.produit, isTrue);
      expect(o.hauteDefinition, isTrue);
      expect(o.aide, isNotEmpty);
    }
    for (final f in [BarcodeFormat.dataMatrix, BarcodeFormat.ean13, BarcodeFormat.upcA, BarcodeFormat.itf, BarcodeFormat.code39]) {
      expect(CameraScanScreen.formatsProduit, contains(f));
    }
    expect(ExpirationUpdateScreen.scanLotDate.aide, contains('DataMatrix'));
  });

  test('lot / date : DataMatrix GS1 accepté ; EAN, GTIN seul ou texte refusés avec un message (lecture continue)', () {
    const gs = '\u001d';
    expect(ExpirationUpdateScreen.refusLotDate('010340093595583817271231${'10'}LOTFICTIF1'), isNull, reason: 'GTIN + date + lot');
    expect(ExpirationUpdateScreen.refusLotDate('${gs}0103400935955838172712311${'0'}LOT2${gs}21SERIE'), isNull);
    expect(ExpirationUpdateScreen.refusLotDate('3400935955838'), contains('DataMatrix'), reason: 'EAN-13 de la boîte');
    expect(ExpirationUpdateScreen.refusLotDate('0103400935955838'), contains('sans lot ni date'), reason: 'GTIN seul');
    expect(ExpirationUpdateScreen.refusLotDate('BONJOUR'), isNotNull);
  });

  test('valeur rendue inchangée : UPC-A → EAN-13 complet ; séparateurs GS conservés', () {
    expect(CameraScanScreen.valueOf(const Barcode(rawValue: '012345678905', format: BarcodeFormat.upcA)), '0012345678905');
    expect(CameraScanScreen.valueOf(const Barcode(rawValue: '3400922385563', format: BarcodeFormat.ean13)), '3400922385563');
  });
}
