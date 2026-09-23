import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:prestige_vente_app/screens/common/camera_scan_screen.dart';
import 'package:prestige_vente_app/services/datamatrix_parser.dart';

void main() {
  const withGs = '0103400935955838172710311074452\u001d21SERIE99';
  const withoutGs = '010340093595583817271031107445221SERIE99';

  test('GS perdu dans le texte mais présent dans les octets : on reprend les octets', () {
    final b = Barcode(rawValue: withoutGs, rawBytes: Uint8List.fromList(withGs.codeUnits));
    final value = CameraScanScreen.valueOf(b)!;
    expect(value, withGs);
    expect(DataMatrixParser.parse(value)!.lot, '74452'); // lot non ambigu
    expect(DataMatrixParser.parse(withoutGs)!.lot, isNull); // sans GS : ambigu
  });

  test('texte déjà complet ou octets non textuels : texte conservé', () {
    expect(CameraScanScreen.valueOf(Barcode(rawValue: withGs, rawBytes: Uint8List.fromList(withGs.codeUnits))), withGs);
    expect(CameraScanScreen.valueOf(Barcode(rawValue: 'ABC', rawBytes: Uint8List.fromList([0xE8, 29, 0x01]))), 'ABC');
    expect(CameraScanScreen.valueOf(const Barcode(rawValue: '3400935955838')), '3400935955838');
  });
}
