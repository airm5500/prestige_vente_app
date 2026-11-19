// PERFORMANCE — 4.15.1 : réponse du serveur à la demande 63, données FICTIVES :
//  - conversion en 1 bit d'un long ticket gris (576 × 2 400 points, PNG du serveur) : moins de 1,5 s ; raster GS v 0
//    de la taille attendue (72 octets × hauteur + 8 octets par bande) ;
//  - remise d'une vente comptant sur la demande 63 : POST vente/remise puis le panier, SANS net/vno (net rendu dans
//    `data`) — une requête de moins ; serveur d'aujourd'hui : mêmes requêtes qu'en 4.15.0.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/services/ticket_1bit.dart';
import 'package:prestige_vente_app/ventes/common/remise_vente.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../outils/clients_vente_fictifs.dart';
import '../outils/demande63_fictive.dart';
import '../outils/faux_serveur_prestige.dart';
import '../outils/remises_fictives.dart';

const _remise = RemiseOption(id: 'REM-FICT-10', nom: 'REMISE FICTIVE 10 %');

void main() {
  test('ticket gris 576 × 2 400 converti en 1 bit en moins de 1,5 s', () {
    final morceau = img.decodePng(Demande63Fictive.ticketGris(576))!;
    final long = img.Image(width: 576, height: 2400, numChannels: 1);
    for (var y = 0; y < 2400; y += morceau.height) {
      img.compositeImage(long, morceau, dstY: y);
    }
    final png = Uint8List.fromList(img.encodePng(long));
    final sw = Stopwatch()..start();
    final r = Ticket1Bit.depuisPng(png, largeurMax: 576)!;
    final esc = r.gsV0();
    sw.stop();
    expect(esc.length, 72 * 2400 + 8 * (2400 / 256).ceil());
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });

  for (final nouveau in [true, false]) {
    test('remise comptant, ${nouveau ? 'demande 63 : pas de net/vno (data)' : 'serveur d\'aujourd\'hui : net/vno comme 4.15.0'}', () => avecVraiHttp(() async {
          SharedPreferences.setMockInitialValues({});
          DroitsVente.instance.oublier();
          DroitsVente.instance.oublierControles();
          final srv = FauxServeurPrestige();
          ClientsVenteFictifs(srv);
          final rf = RemisesFictives(srv);
          Demande63Fictive(srv, rf, d63: nouveau);
          srv.droitsComptes = {DonneesFictives.login: ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE', if (nouveau) droitRemise]};
          await srv.demarrer();
          try {
            await DioClient.cookieJar.deleteAll();
            final api = ApiService(baseUrl: srv.base);
            expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
            final gw = DioVenteGateway(api);
            final c = VenteController(gateway: gw);
            final p = (await gw.searchProducts('PRODUIT')).valueOrNull!.first;
            expect((await c.addProduct(p, 2)).isOk, isTrue);
            final avant = srv.recues.length;
            expect((await c.choisirRemise(_remise)).isOk, isTrue);
            final apres = srv.recues.sublist(avant).map((r) => '${r.methode} ${r.chemin.replaceAll(RegExp(r'^.*/api/v1'), '')}').toList();
            expect(apres.where((x) => x == 'POST /vente/remise'), hasLength(1));
            expect(apres.where((x) => x == 'POST /vente/net/vno'), hasLength(nouveau ? 0 : 1));
            expect(apres.length, nouveau ? 2 : 3, reason: '$apres');
            expect(c.montantRemise, greaterThan(0));
          } finally {
            await srv.arreter();
            await DioClient.cookieJar.deleteAll();
          }
        }));
  }
}
