// Images AVANT / APRÈS du contraste d'impression 5.4.0 (données FICTIVES) : chaque PNG gris du dossier SOURCE (par
// défaut les références test/references/tickets/image_serveur_fictive_*.png, dessinées par le code du serveur) est
// converti en 1 bit comme en 5.3.0 (seuil 128) et comme en 5.4.0 (contraste renforcé), à la largeur exacte de la tête.
// Outil hors CI, comme les autres test/outils/captures_* :
//   CAPTURES=/dossier [SOURCE=/dossier_png_gris] flutter test test/outils/captures_contraste_540_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/services/ticket_1bit.dart';

final _sortie = Platform.environment['CAPTURES'];
final _source = Platform.environment['SOURCE'] ?? 'test/references/tickets';

void main() {
  test('tickets du serveur : 1 bit 5.3.0 (seuil 128) et 5.4.0 (renforcé)', () {
    final dossier = _sortie;
    if (dossier == null) {
      markTestSkipped('CAPTURES non défini');
      return;
    }
    Directory(dossier).createSync(recursive: true);
    final pngs = Directory(_source).listSync().whereType<File>().where((f) => f.path.endsWith('.png') && f.path.contains('gris') || f.path.contains('image_serveur_fictive_'));
    var n = 0;
    for (final f in pngs) {
      final nom = f.uri.pathSegments.last.replaceAll('.png', '');
      final png = f.readAsBytesSync();
      final avant = Ticket1Bit.depuisPng(png)!;
      final apres = Ticket1Bit.depuisPng(png, contraste: ContrasteImpression.renforce)!;
      File('$dossier/${nom}_1_avant_5.3.0.png').writeAsBytesSync(avant.png());
      File('$dossier/${nom}_2_apres_5.4.0.png').writeAsBytesSync(apres.png());
      n++;
    }
    expect(n, greaterThan(0));
  });
}
