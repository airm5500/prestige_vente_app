// PERFORMANCE — Prestige Pointage (demande 57) :
//  - signature : 2 000 requêtes signées (GET avec paramètres, POST d'un corps de 1 Ko, photo de 60 Ko) ;
//  - copie des employés : 2 000 employés reçus par la route signée, puis 2 000 badges lus (numéro, QR ; recherche linéaire de la 4.6.2 dans la copie) ;
//  - une lecture de badge ne déclenche AUCUNE requête (copie locale).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/prestigepointage/client_borne.dart';
import 'package:prestige_vente_app/prestigepointage/identite_borne.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_store.dart';
import 'package:prestige_vente_app/rh/identification.dart';

import '../outils/faux_serveur_borne.dart';
import '../outils/faux_serveur_prestige.dart';
import '../outils/performance.dart';

final _emp = '0a1b' * 16;

void main() {
  test('2 000 requêtes signées (GET, POST 1 Ko, photo 60 Ko)', () async {
    final i = IdentiteBorne(borneId: 'BORNE-PERF', secret: List.generate(32, (k) => k), empreinte: _emp, nom: 'Borne', serveur: 'http://192.0.2.1:8080/prestige/api/v1');
    final c = ClientBorne(i);
    final get = Uri.parse('http://192.0.2.1:8080/prestige/api/v1/borne-pointage/empreintes?format=SUNMI_A400_RAW&depuis=2026-10-26T08%3A00%3A00');
    final post = Uri.parse('http://192.0.2.1:8080/prestige/api/v1/borne-pointage/pointages');
    final corps = utf8.encode(jsonEncode({'id': 'x' * 36, 'motif': 'é' * 480}));
    final photo = Uint8List(60 * 1024);
    final ms = await meilleurDe(3, () async {
      final sw = Stopwatch()..start();
      for (var k = 0; k < 1000; k++) {
        c.entetes('GET', get, const []);
        c.entetes('POST', post, corps);
      }
      for (var k = 0; k < 20; k++) {
        c.entetes('POST', post, photo);
      }
      return sw.elapsedMicroseconds / 1000;
    });
    mesurer('Prestige Pointage : 2 000 requêtes signées + 20 photos', ms, seuil: 1500, unite: 'ms');
  });

  test('2 000 employés reçus puis 2 000 badges lus ; aucune requête par lecture', () async {
    final srv = FauxServeurPrestige()..installerEnMemoire();
    addTearDown(srv.desinstaller);
    await DioClient.cookieJar.deleteAll();
    final bornes = FauxBornes(srv);
    srv.employesRh = [
      for (var k = 0; k < 2000; k++)
        {'id': 'E$k', 'matricule': '$k', 'nom': 'NOM$k', 'prenoms': 'Prenom$k', 'badge': 'B${k.toString().padLeft(5, '0')}', 'statut': 'ACTIF'},
    ];
    final secret = List.generate(32, (k) => 255 - k);
    bornes.bornes['BORNE-PERF'] = BorneServeur('BORNE-PERF', 'Borne', _emp, secret, DonneesFictives.admin);
    final c = ClientBorne(IdentiteBorne(borneId: 'BORNE-PERF', secret: secret, empreinte: _emp, nom: 'Borne', serveur: srv.base));
    final rh = PointageRh(store: MemoryRhStore(), serveur: c, identification: IdentificationEmploye(coffre: CoffreEmpreintesMemoire()), horsLigne: () => c.horsLigne, nomTerminal: () => 'Borne');
    final sw = Stopwatch()..start();
    await rh.rafraichirEmployes();
    final copie = sw.elapsedMicroseconds / 1000;
    expect(rh.employes, hasLength(2000));
    mesurer('Prestige Pointage : copie de 2 000 employés (route signée)', copie, seuil: 1500, unite: 'ms');
    final avant = srv.recues.length;
    final lus = Stopwatch()..start();
    var reconnus = 0;
    for (var k = 0; k < 2000; k++) {
      final n = 'B${k.toString().padLeft(5, '0')}';
      final brut = k.isEven ? n : 'PRESTIGE-BADGE|1|$n|login.fictif|SecretFictif$k';
      if (rh.lire(brut) is! BadgeInconnu) reconnus++;
    }
    lus.stop();
    expect(reconnus, 2000);
    expect(srv.recues.length, avant, reason: 'lecture locale : aucune requête');
    mesurer('Prestige Pointage : 2 000 badges lus (numéro et QR)', lus.elapsedMicroseconds / 1000, seuil: 2000, unite: 'ms');
    expect(bornes.refusSignature, 0);
  });
}
