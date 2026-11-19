// Captures PNG — 4.15.1, demande 63 : ticket FICTIF dessiné « comme le serveur » (PNG en niveaux de gris, texte lissé,
// QR à modules de 2,8 points) puis tel qu'il part à l'imprimante après la conversion en 1 bit de l'application
// (lib/services/ticket_1bit.dart), en 58 mm (384 points) et 80 mm (576 points), plus un agrandissement ×4 du QR.
// Hors de la suite de la CI. Pour régénérer :
//   APERCUS=1 CAPTURES=/chemin flutter test test/outils/captures_demande63_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prestige_vente_app/services/ticket_1bit.dart';

import 'demande63_fictive.dart';

final _actif = Platform.environment.containsKey('APERCUS');
final _dossier = Platform.environment['CAPTURES'] ?? '/tmp/captures_d63';

void main() {
  test('tickets 58 / 80 mm : gris du serveur → 1 bit imprimé', () {
    Directory(_dossier).createSync(recursive: true);
    for (final (mm, points) in [(58, 384), (80, 576)]) {
      for (final (nom, qr) in [('vente', null), ('prevente', 'REF-FICT-000123')]) {
        final gris = Demande63Fictive.ticketGris(points, qr: qr);
        final r = Ticket1Bit.depuisPng(gris, largeurMax: points)!;
        File('$_dossier/ticket_${nom}_${mm}mm_1_serveur_gris.png').writeAsBytesSync(gris);
        File('$_dossier/ticket_${nom}_${mm}mm_2_imprime_1bit.png').writeAsBytesSync(r.png());
        if (qr != null) {
          final i = img.decodePng(r.png())!;
          final g = img.decodePng(gris)!;
          final h = i.height - 250;
          final zoomGris = img.copyResize(img.copyCrop(g, x: 0, y: h, width: points, height: 250), width: points * 4, interpolation: img.Interpolation.nearest);
          final zoom1 = img.copyResize(img.copyCrop(i, x: 0, y: h, width: points, height: 250), width: points * 4, interpolation: img.Interpolation.nearest);
          File('$_dossier/ticket_${nom}_${mm}mm_3_qr_x4_gris.png').writeAsBytesSync(img.encodePng(zoomGris));
          File('$_dossier/ticket_${nom}_${mm}mm_4_qr_x4_1bit.png').writeAsBytesSync(img.encodePng(zoom1));
        }
      }
    }
  }, skip: !_actif);
}
