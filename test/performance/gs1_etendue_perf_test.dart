// PERFORMANCE — 4.9.2 : la reconnaissance des étiquettes étendues (DataMatrix+, QR+) ne ralentit pas le scan :
// 50 000 contenus (étendus, GS1 normaux, codes-barres, CIP, noms, contenus longs) en moins de 500 ms, sans réseau.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/ventes/core/gs1_vente.dart';

void main() {
  test('50 000 reconnaissances en moins de 500 ms', () {
    final codes = [
      '0103400935955838\u001d17281031\u001d10LOTA1\u001d91EPLUS1\u001d92DOLI_FICTIF',
      'EP1|CIP:3400935955838|NOM:DOLI FICTIF|LOT:LOTA1',
      '0103400935955838\u001d17281031\u001d10LOTA1',
      '3400935955838',
      '3595583',
      'DOLIPRANE 1000',
      'X' * 500,
    ];
    var n = 0;
    final sw = Stopwatch()..start();
    for (var k = 0; k < 50000; k++) {
      if (Gs1Vente.estEtiquetteEtendue(codes[k % codes.length])) n++;
    }
    sw.stop();
    expect(n, (50000 ~/ 7) * 2 + (50000 % 7 >= 2 ? 2 : 50000 % 7));
    expect(sw.elapsedMilliseconds, lessThan(500), reason: '${sw.elapsedMilliseconds} ms');
  });
}
