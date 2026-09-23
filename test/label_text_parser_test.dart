import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/services/label_text_parser.dart';

void main() {
  final now = DateTime(2026, 9, 23);
  LabelData parse(List<String> l) => LabelTextParser.parse(l, now: now);

  test('Lot/Batch + Exp mois en lettres, fabrication ignorée', () {
    final d = parse(['Lot/Batch : TRL24011', 'Fab./Mfg. date : MAR 2024', 'Per./Exp. date : FEB 2027']);
    expect(d.lotCandidates.first, 'TRL24011');
    expect(d.lotFromLabel, isTrue);
    expect(d.expiryCandidates.first, DateTime(2027, 2, 28));
    expect(d.expiryFromLabel, isTrue);
  });

  test('Batch No. / N° de lot + mois.année numérique', () {
    final d = parse(['Batch No./ N° de lot : DWSH0069', 'Mfg. Date/ Date Fab. : 11.2024', 'Expiry Date/ Date Exp. : 10.2027']);
    expect(d.lotCandidates.first, 'DWSH0069');
    expect(d.expiryCandidates.first, DateTime(2027, 10, 31));
  });

  test('format boîte française : LOT et EXP sur la même ligne, JJ/MM/AAAA', () {
    final d = parse(['LOT: A1234B  EXP: 31/10/2027']);
    expect(d.lotCandidates.first, 'A1234B');
    expect(d.expiryCandidates.first, DateTime(2027, 10, 31));
  });

  test('valeur sur la ligne suivante', () {
    final d = parse(['LOT', 'X77AB', 'EXP', '2028-03']);
    expect(d.lotCandidates.first, 'X77AB');
    expect(d.expiryCandidates.first, DateTime(2028, 3, 31));
  });

  test('mentions GS1 imprimées en clair', () {
    final d = parse(['(01) 03400935955838', '(17) 271031 (10) LOT42']);
    expect(d.gtin, '03400935955838');
    expect(d.lotCandidates.first, 'LOT42');
    expect(d.expiryCandidates.first, DateTime(2027, 10, 31));
  });

  test('EAN-13 espacé sous le code-barres (clé vérifiée)', () {
    expect(parse(['3 400935 955838']).gtin, '03400935955838');
    expect(parse(['3 400935 955839']).gtin, isNull);
  });

  test('date sans libellé : proposée mais non marquée fiable', () {
    final d = parse(['PARACETAMOL 500 mg', '03/2025', '03/2028']);
    expect(d.expiryFromLabel, isFalse);
    expect(d.expiryCandidates.first, DateTime(2028, 3, 31));
  });

  test('mot contenant LOT (PILOTE) ignoré', () {
    expect(parse(['PILOTE 123']).lotCandidates, isEmpty);
  });

  test('boîte format indien : GTIN, B.No., Mfd., Exp., S.N. (photo réelle)', () {
    final d = parse([
      '8 901296 107140',
      'GTIN :08901296107140',
      'B.No..:XKB0136',
      'Mfd. :09/2024',
      'Exp. :08/2026',
      'S.N. :XKB0136QZ8URD5',
    ]);
    expect(d.gtin, '08901296107140');
    expect(d.lotCandidates, ['XKB0136']); // pas le numéro de série
    expect(d.lotFromLabel, isTrue);
    expect(d.expiryCandidates.first, DateTime(2026, 8, 31)); // pas la date de fabrication
    expect(d.expiryFromLabel, isTrue);
  });

  test('ligne fusionnée (tableau) : fabrication et péremption sur la même ligne', () {
    final d = parse(['B.No.: XKB0136  Mfd.: 09/2024  Exp.: 08/2026']);
    expect(d.lotCandidates.first, 'XKB0136');
    expect(d.expiryCandidates.first, DateTime(2026, 8, 31));
    expect(d.expiryFromLabel, isTrue);
  });
}
