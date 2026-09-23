import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/services/datamatrix_parser.dart';

void main() {
  const gs = '\u001d';
  final now = DateTime(2026, 9, 23);
  // CIP13 3400935955838 -> GTIN 03400935955838
  const gtin = '03400935955838';

  DataMatrixData? parse(String s) => DataMatrixParser.parse(s, now: now);

  group('Clé GS1', () {
    test('GTIN valide / invalide', () {
      expect(DataMatrixParser.isValidGs1CheckDigit(gtin), isTrue);
      expect(DataMatrixParser.isValidGs1CheckDigit('03400935955839'), isFalse);
    });
  });

  group('GS1 brut', () {
    test('01 + 17 + 10 (lot en dernier, sans séparateur)', () {
      final d = parse('01${gtin}17271031101234AB')!;
      expect(d.format, DataMatrixFormat.gs1);
      expect(d.gtin, gtin);
      expect(d.expiry, DateTime(2027, 10, 31));
      expect(d.lot, '1234AB');
      expect(d.productSearchQueries, ['3400935955838', '3595583']);
    });

    test('préfixe de symbologie ]d2 et GS initial', () {
      final d = parse(']d2${gs}01${gtin}10LOT42${gs}17271231')!;
      expect(d.lot, 'LOT42');
      expect(d.expiry, DateTime(2027, 12, 31));
    });

    test('séparateur GS : lot puis numéro de série', () {
      final d = parse('01${gtin}21SERIAL123${gs}10LOT7445${gs}17261002')!;
      expect(d.lot, 'LOT7445');
      expect(d.expiry, DateTime(2026, 10, 2));
    });

    test('séparateur GS textuel <GS>', () {
      final d = parse('01${gtin}10AB12<GS>21XYZ')!;
      expect(d.lot, 'AB12');
    });

    test('jour 00 = dernier jour du mois', () {
      final d = parse('01${gtin}17270200')!;
      expect(d.expiry, DateTime(2027, 2, 28));
    });

    test('lot suivi d\'un numéro de série sans GS : ambigu, rien n\'est inventé', () {
      final d = parse('01${gtin}17271031107445213456789')!;
      expect(d.gtin, gtin);
      expect(d.expiry, DateTime(2027, 10, 31));
      expect(d.lot, isNull);
      expect(d.isLotAmbiguous, isTrue);
      expect(d.lotCandidates, containsAll(['7445', '7445213456789']));
    });

    test('date impossible : GTIN conservé, date signalée invalide', () {
      final d = parse('01${gtin}17271340')!;
      expect(d.gtin, gtin);
      expect(d.expiry, isNull);
      expect(d.invalidExpiry, isTrue);
    });

    test('GTIN avec clé fausse sans autre indice : pas un DataMatrix', () {
      expect(parse('0103400935955839172710311012'), isNull);
    });

    test('siècle GS1', () {
      expect(DataMatrixParser.gs1Date('990101', now: now), DateTime(1999, 1, 1));
      expect(DataMatrixParser.gs1Date('300101', now: now), DateTime(2030, 1, 1));
    });
  });

  group('Boîte réelle (GTIN 08901296107140, lot XKB0136, série XKB0136QZ8URD5)', () {
    test('avec séparateur GS', () {
      final d = parse('010890129610714017260800${'10'}XKB0136${gs}21XKB0136QZ8URD5')!;
      expect(d.gtin, '08901296107140');
      expect(d.lot, 'XKB0136');
      expect(d.expiry, DateTime(2026, 8, 31));
    });
    test('sans séparateur : le lot reste déterminé (un lot de 23 caractères est impossible)', () {
      final d = parse('01089012961071401726083110XKB013621XKB0136QZ8URD5')!;
      expect(d.lot, 'XKB0136');
      expect(d.expiry, DateTime(2026, 8, 31));
    });
  });

  group('GS1 lisible', () {
    test('avec AI supplémentaires', () {
      final d = parse('(01)$gtin(21)SERIE-99(17)271231(10)LOT42(30)12')!;
      expect(d.gtin, gtin);
      expect(d.lot, 'LOT42');
      expect(d.expiry, DateTime(2027, 12, 31));
    });
  });

  group('Formats non GS1', () {
    test('champs nommés', () {
      final d = parse('EAN=3400935955838;LOT=ABC-42;EXP=2027-12-31')!;
      expect(d.format, DataMatrixFormat.namedFields);
      expect(d.gtin, gtin);
      expect(d.lot, 'ABC-42');
      expect(d.expiry, DateTime(2027, 12, 31));
    });

    test('champs nommés : date 2-2-2 ambiguë proposée sans être imposée', () {
      final d = parse('LOT=ABC|EXP=27/10/31')!;
      expect(d.expiry, isNull);
      expect(d.expiryCandidates, containsAll([DateTime(2027, 10, 31), DateTime(2031, 10, 27)]));
    });

    test('ASC MH10.8.2 (PPN)', () {
      final d = parse('[)>\u001e06${gs}9N110375286414${gs}1TABC123${gs}D270600${gs}S12345\u001e\u0004')!;
      expect(d.format, DataMatrixFormat.asc);
      expect(d.lot, 'ABC123');
      expect(d.expiry, DateTime(2027, 6, 30));
    });
  });

  group('Saisies ordinaires non détectées', () {
    for (final s in ['doliprane', '3595583', '3400935955838', '311027', 'AB123', '5', '', '   ', 'Doliprane: 1000']) {
      test('"$s"', () => expect(parse(s), isNull));
    }
  });
}
