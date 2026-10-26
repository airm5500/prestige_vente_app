// RÉSEAU — Prestige Pointage (demande 57) en VRAI HTTP (dart:io, port local) contre le faux serveur Prestige, qui
// recalcule la signature à partir de ce qu'il RELIT sur le fil (chemin et paramètres bruts, octets du corps) :
//  - enrôlement puis appels signés : paramètres à encoder (espace, accents, « + », « & »), corps JSON UTF-8 accentué,
//    photo multipart binaire ; Content-Length = octets signés ; aucune signature refusée ;
//  - le secret n'est jamais sur le fil ; aucune session ni cookie ;
//  - serveur coupé → hors ligne, puis retour → en ligne ;
//  - 401 REVOQUEE, 403 RESEAU, 429 Retry-After reçus tels quels par le vrai client HTTP.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/prestigepointage/client_borne.dart';
import 'package:prestige_vente_app/prestigepointage/enrolement_borne.dart';
import 'package:prestige_vente_app/prestigepointage/identite_borne.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';

import '../outils/faux_serveur_borne.dart';
import '../outils/faux_serveur_prestige.dart';

final _emp = '5eed' * 16;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FauxServeurPrestige srv;
  late FauxBornes bornes;

  setUp(() => avecVraiHttp(() async {
        srv = FauxServeurPrestige();
        bornes = FauxBornes(srv);
        await srv.demarrer();
        SondeDeploiement.vider();
        await DioClient.cookieJar.deleteAll();
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
      }));

  Future<IdentiteBorne> enroler() async {
    final r = await EnrolementBorne().enroler(
        baseUrl: srv.base, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin, nom: 'Borne réseau', empreinte: _emp);
    expect(r.reussi, isTrue, reason: r.message);
    return r.identite!;
  }

  test('fil réel : paramètres encodés, JSON accentué, multipart binaire — signature juste, Content-Length exact', () => avecVraiHttp(() async {
        final i = await enroler();
        final c = ClientBorne(i);
        expect(await c.moi(), isNotNull);
        await c.get('/rh/empreintes', const {'format': 'SUNMI_A400_RAW', 'depuis': '2026-10-26T08:00:00', 'note': 'é + & ='});
        final q = srv.recues.last;
        expect(q.cible, contains('?'), reason: 'paramètres sur le fil');
        expect(q.cible, isNot(contains(' ')), reason: 'encodés');
        final n = DateTime.now();
        String d2(int v) => v.toString().padLeft(2, '0');
        final corps = {
          'id': 'a1b2c3d4-0000-4000-8000-00000000abcd',
          'employeId': 'E1',
          'jour': '${n.year}-${d2(n.month)}-${d2(n.day)}',
          'heure': '${d2(n.hour)}:${d2(n.minute)}',
          'sens': 'ENTREE',
          'motif': 'Badge terminal Borne réseau — accentué',
        };
        expect((await c.post('/rh/pointages', corps)).body?['success'], isTrue);
        final p = srv.recues.last;
        expect(int.parse(p.entete('content-length')!), p.octets.length);
        expect(utf8.decode(p.octets), jsonEncode(corps), reason: 'octets reçus = octets signés');
        final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, for (var k = 0; k < 4000; k++) (k * 7) & 0xff, 0xFF, 0xD9]);
        expect((await c.envoyerPhoto(corps['id'] as String, jpeg, n)).body?['success'], isTrue);
        final ph = srv.recues.last;
        expect(ph.entete('content-type'), startsWith('multipart/form-data; boundary='));
        expect(int.parse(ph.entete('content-length')!), ph.octets.length);
        expect(bornes.photos.values.single, containsAllInOrder(jpeg.sublist(0, 32)));
        expect(bornes.refusSignature, 0, reason: 'le serveur a vérifié chaque signature sur les octets reçus');
        final s64 = base64Url.encode(i.secret).replaceAll('=', '');
        for (final r in srv.recues.where((r) => r.chemin.contains('/borne-pointage/'))) {
          expect(r.entetes.values.join('|'), isNot(contains(s64)));
          expect(r.corps, isNot(contains(s64)));
          expect(r.cookie, isEmpty);
        }
      }));

  test('serveur coupé → hors ligne ; retour → en ligne', () => avecVraiHttp(() async {
        final i = await enroler();
        final c = ClientBorne(i);
        expect(await c.moi(), isNotNull);
        await srv.couper();
        await expectLater(c.get('/rh/employes'), throwsA(isA<RhHorsLigne>()));
        expect(c.horsLigne, isTrue);
        await srv.retablir();
        expect(await c.moi(), isNotNull);
        expect(c.etat, EtatBorne.ok);
      }));

  test('refus reçus par le vrai client : REVOQUEE, RESEAU, 429 + Retry-After', () => avecVraiHttp(() async {
        final i = await enroler();
        final c = ClientBorne(i);
        bornes.horsReseau = true;
        expect(await c.moi(), isNull);
        expect(c.etat, EtatBorne.reseau);
        bornes.horsReseau = false;
        bornes.retirer(i.borneId);
        expect(await c.moi(), isNull);
        expect(c.etat, EtatBorne.revoquee);
        final j = await enroler();
        var t = DateTime.now();
        bornes.horloge = () => t;
        final d = ClientBorne(j, maintenant: () => t);
        for (var k = 0; k < 120; k++) {
          await d.moi();
        }
        expect(await d.moi(), isNull);
        expect(d.etat, EtatBorne.tropDeDemandes);
        expect(d.bloqueJusqua!.difference(t).inSeconds, 60);
      }));
}
