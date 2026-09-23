import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/services/ocr_service.dart';

void main() {
  test('les colonnes d\'une même ligne de tableau sont regroupées de gauche à droite', () {
    final rows = OcrService.groupIntoRows([
      (box: const Rect.fromLTWH(520, 302, 60, 20), text: '3257001'),
      (box: const Rect.fromLTWH(10, 300, 300, 22), text: 'EFFERALGAN 500MG CPR EFFV B/16'),
      (box: const Rect.fromLTWH(700, 301, 90, 20), text: '1CP par jour'),
      (box: const Rect.fromLTWH(610, 303, 10, 18), text: '1'),
      (box: const Rect.fromLTWH(10, 250, 80, 20), text: 'Produit'),
      (box: const Rect.fromLTWH(520, 251, 40, 20), text: 'CIP'),
      (box: const Rect.fromLTWH(10, 350, 300, 20), text: 'TOTAL : 1 produit(s) prescrit(s)'),
    ]);
    expect(rows, [
      'Produit  CIP',
      'EFFERALGAN 500MG CPR EFFV B/16  3257001  1  1CP par jour',
      'TOTAL : 1 produit(s) prescrit(s)',
    ]);
  });
}
