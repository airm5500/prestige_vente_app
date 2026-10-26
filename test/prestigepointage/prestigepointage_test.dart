// Prestige Pointage — UNITAIRES (sans serveur) :
//  - identité de la borne : réponse d'enrôlement → identité (secret décodé) ; incomplète → null ; toString sans secret ;
//    coffre sécurisé : relu à l'identique, rien dans les préférences, effacé ;
//  - messages des états (textes demandés) ; écart d'horloge et heure du serveur ;
//  - corps multipart de la photo (format exact) ; en-têtes signés : date strictement croissante, signature recalculée ;
//  - pointages en attente depuis plus de 60 h signalés (refusés par le serveur après 72 h), bandeau de l'administrateur ;
//  - Prestige Mobile 4.10.0 : bouton « Pointer » et tuile de l'accueil seulement si Prestige Pointage est installée.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/prestigepointage/client_borne.dart';
import 'package:prestige_vente_app/prestigepointage/controleur_borne.dart';
import 'package:prestige_vente_app/prestigepointage/identite_borne.dart';
import 'package:prestige_vente_app/prestigepointage/lanceur_pointage.dart';
import 'package:prestige_vente_app/prestigepointage/pointage_app.dart';
import 'package:prestige_vente_app/prestigepointage/signature_borne.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/rh/rh_store.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _emp = 'AB' * 32;
final _secret = List<int>.generate(32, (i) => i * 5 + 1);

IdentiteBorne _identite() => IdentiteBorne(borneId: 'BORNE-0001-UNITE', secret: _secret, empreinte: _emp, nom: 'Borne entrée', serveur: 'http://192.0.2.10:8080/prestige/api/v1');

/// Aucun réseau : chaque appel échoue comme un serveur injoignable.
class _SansReseau implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async =>
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
  @override
  void close({bool force = false}) {}
}

ClientBorne _client(IdentiteBorne i) => ClientBorne(i, dio: Dio()..httpClientAdapter = _SansReseau());

void main() {
  group('identité de la borne', () {
    test('réponse d\'enrôlement → identité ; secret décodé (32 octets, « = » toléré) ; incomplète → null', () {
      final b64 = base64Url.encode(_secret);
      for (final s in [b64, b64.replaceAll('=', '')]) {
        final i = IdentiteBorne.depuisEnrolement({'success': true, 'borneId': 'B-1', 'secret': s, 'creeLe': '2026-10-26T08:00:00'},
            empreinte: _emp, nom: 'Borne', serveur: 'http://x')!;
        expect(i.secret, _secret);
        expect(i.empreinte, _emp.toLowerCase(), reason: 'empreinte en minuscules (le serveur compare sans la casse)');
        expect(i.creeLe, DateTime(2026, 10, 26, 8));
      }
      expect(IdentiteBorne.depuisEnrolement({'success': true, 'borneId': 'B-1', 'secret': 'court'}, empreinte: _emp, nom: 'B', serveur: 'x'), isNull);
      expect(IdentiteBorne.depuisEnrolement({'success': true, 'secret': b64}, empreinte: _emp, nom: 'B', serveur: 'x'), isNull);
      expect(IdentiteBorne.depuisEnrolement({'success': false}, empreinte: _emp, nom: 'B', serveur: 'x'), isNull);
      expect(IdentiteBorne.depuisEnrolement(null, empreinte: _emp, nom: 'B', serveur: 'x'), isNull);
    });

    test('toString : ni le secret ni l\'empreinte', () {
      final s = _identite().toString();
      expect(s, isNot(contains(base64Url.encode(_secret).substring(0, 12))));
      expect(s, isNot(contains(_emp.toLowerCase())));
      expect(s, contains('Borne entrée'));
    });

    test('coffre sécurisé : relu à l\'identique, rien dans les préférences ; effacé', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      const c = CoffreBorneSecurise();
      expect(await c.lire(), isNull);
      await c.ecrire(_identite());
      final i = (await c.lire())!;
      expect([i.borneId, i.secret, i.empreinte, i.nom, i.serveur], [_identite().borneId, _secret, _emp.toLowerCase(), 'Borne entrée', _identite().serveur]);
      final p = await SharedPreferences.getInstance();
      expect([for (final k in p.getKeys()) '$k=${p.get(k)}'].join(), isNot(contains(base64Url.encode(_secret).substring(0, 12))));
      await c.effacer();
      expect(await c.lire(), isNull);
      await const FlutterSecureStorage().write(key: CoffreBorneSecurise.cle, value: '{illisible');
      expect(await c.lire(), isNull, reason: 'contenu illisible : enrôlement demandé, pas de plantage');
    });
  });

  group('messages', () {
    test('textes demandés pour chaque état ; en ligne : rien', () {
      expect(messageEtatBorne(EtatBorne.ok), isEmpty);
      expect(messageEtatBorne(EtatBorne.inconnu), isEmpty);
      expect(messageEtatBorne(EtatBorne.revoquee), startsWith('Appareil retiré : faites-le enrôler à nouveau'));
      expect(messageEtatBorne(EtatBorne.reseau), startsWith('Borne utilisable seulement sur le réseau de l\'officine'));
      expect(messageEtatBorne(EtatBorne.serveurAncien), startsWith('Serveur à mettre à jour'));
      expect(messageEtatBorne(EtatBorne.horloge), startsWith('Heure du terminal incorrecte'));
      final h = messageEtatBorne(EtatBorne.horloge, ecart: const Duration(minutes: -9), heureServeur: DateTime(2026, 10, 26, 8, 5));
      expect(h, contains('écart de 9 min'));
      expect(h, contains('08:05'));
      expect(messageEtatBorne(EtatBorne.horloge, ecart: const Duration(hours: 3)), contains('3 h'));
      for (final e in EtatBorne.values.where((e) => e != EtatBorne.ok && e != EtatBorne.inconnu)) {
        expect(messageEtatBorne(e), isNotEmpty, reason: '$e');
      }
    });
  });

  group('requête signée', () {
    test('photo : multipart exact (champ photo JPEG puis prise), Content-Type avec la frontière', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]);
      final (type, octets) = ClientBorne.multipartPhoto(jpeg, '2026-10-26T08:02:00', frontiere: 'XYZ');
      expect(type, 'multipart/form-data; boundary=XYZ');
      final attendu = [
        ...utf8.encode('--XYZ\r\nContent-Disposition: form-data; name="photo"; filename="controle.jpg"\r\nContent-Type: image/jpeg\r\n\r\n'),
        ...jpeg,
        ...utf8.encode('\r\n--XYZ\r\nContent-Disposition: form-data; name="prise"\r\n\r\n2026-10-26T08:02:00\r\n--XYZ--\r\n'),
      ];
      expect(octets, attendu);
      final (t2, _) = ClientBorne.multipartPhoto(jpeg, 'x');
      expect(t2, matches(RegExp(r'^multipart/form-data; boundary=PrestigePointage[0-9a-f]{16}$')));
    });

    test('en-têtes : date UTC strictement croissante (même milliseconde), signature = chaîne du serveur', () {
      final t = DateTime.utc(2026, 10, 26, 7, 30, 0, 123);
      final c = ClientBorne(_identite(), maintenant: () => t);
      final u = Uri.parse('http://192.0.2.10:8080/prestige/api/v1/borne-pointage/empreintes?format=SUNMI_A400_RAW&depuis=2026-10-26T08%3A00%3A00');
      final a = c.entetes('GET', u, const []);
      final b = c.entetes('GET', u, const []);
      expect(a['X-Borne-Date'], '2026-10-26T07:30:00.123Z');
      expect(b['X-Borne-Date'], '2026-10-26T07:30:00.124Z', reason: 'jamais deux fois la même signature (rejeu)');
      expect(a['X-Borne'], 'BORNE-0001-UNITE');
      expect(a['X-Borne-Empreinte'], _emp.toLowerCase());
      final chaine = SignatureBorne.chaine('GET', '/prestige/api/v1/borne-pointage/empreintes?format=SUNMI_A400_RAW&depuis=2026-10-26T08%3A00%3A00',
          '2026-10-26T07:30:00.123Z', _emp.toLowerCase(), const []);
      expect(a['X-Borne-Signature'], SignatureBorne.signer(_secret, chaine));
      expect(a.values.join(), isNot(contains(base64Url.encode(_secret).replaceAll('=', ''))));
    });

    test('sans réseau : hors ligne (le pointage reste en file) ; routes de gestion : 404 sans appel', () async {
      final c = _client(_identite());
      expect(await c.moi(), isNull);
      expect(c.etat, EtatBorne.horsLigne);
      expect(c.horsLigne, isTrue);
      expect((await c.get('/rh/presence')).status, 404);
      expect((await c.post('/rh/employes', const {})).status, 404);
    });
  });

  group('72 h', () {
    PointageBadge p(String id, DateTime lu, {StatutPointageBadge s = StatutPointageBadge.enAttente}) =>
        PointageBadge(id: id, employeId: 'E1', employeNom: 'Awa', lu: lu, sens: SensPointage.entree, motif: 'Badge terminal', statut: s);

    Future<ControleurBorne> controleur(DateTime maintenant, List<PointageBadge> file) async {
      final store = MemoryRhStore();
      for (final x in file) {
        await store.enregistrer(x);
      }
      final coffre = CoffreBorneMemoire();
      await coffre.ecrire(_identite());
      final c = ControleurBorne(coffre: coffre, store: store, client: _client, maintenant: () => maintenant);
      await c.charger();
      await c.rh!.chargerFile();
      return c;
    }

    test('en attente depuis plus de 60 h : signalés ; envoyés ou récents : non', () async {
      final n = DateTime(2026, 10, 26, 9);
      final c = await controleur(n, [
        p('aaaaaaaa-1', n.subtract(const Duration(hours: 61))),
        p('aaaaaaaa-2', n.subtract(const Duration(hours: 10))),
        p('aaaaaaaa-3', n.subtract(const Duration(hours: 70)), s: StatutPointageBadge.envoye),
      ]);
      expect([for (final x in c.bientotPerimes) x.id], ['aaaaaaaa-1']);
      expect(ControleurBorne.ageMaximal, const Duration(hours: 72));
      c.dispose();
    });

    testWidgets('bandeau de la borne : avertissement avant l\'expiration', (t) async {
      final n = DateTime(2026, 10, 26, 9);
      late ControleurBorne c;
      await t.runAsync(() async => c = await controleur(n, [p('aaaaaaaa-1', n.subtract(const Duration(hours: 62)))]));
      await t.pumpWidget(ChangeNotifierProvider.value(
          value: c, child: const MaterialApp(home: Scaffold(body: BandeauBorne()))));
      await t.pump();
      expect(find.byKey(const Key('pointage_alerte_72h')), findsOneWidget);
      expect(find.textContaining('1 pointage(s) en attente depuis plus de 60 h'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  group('Prestige Mobile 4.10.0 : « Pointer »', () {
    setUp(LanceurPointage.reinitialiser);
    tearDown(LanceurPointage.reinitialiser);

    testWidgets('bouton masqué tant que Prestige Pointage n\'est pas installée ; visible sinon ; ouvre l\'application', (t) async {
      var ouvertures = 0;
      LanceurPointage.detecteur = () async => false;
      LanceurPointage.ouvreur = () async {
        ouvertures++;
        return true;
      };
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: BoutonPointer(couleur: Colors.teal))));
      await t.pump();
      expect(find.byKey(const Key('bouton_pointer')), findsNothing);
      LanceurPointage.detecteur = () async => true;
      await LanceurPointage.detecter();
      await t.pump();
      expect(find.byKey(const Key('bouton_pointer')), findsOneWidget);
      await t.tap(find.byKey(const Key('bouton_pointer')));
      await t.pump();
      expect(ouvertures, 1);
    });

    testWidgets('canal absent : masqué ; désinstallée entre-temps : ouverture impossible : message, bouton masqué', (t) async {
      LanceurPointage.detecteur = () async => throw MissingPluginException('prestige/pointage');
      expect(await LanceurPointage.detecter(), isFalse, reason: 'canal natif absent : masqué');
      LanceurPointage.detecteur = () async => true;
      LanceurPointage.ouvreur = () async => false;
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: BoutonPointer(couleur: Colors.teal))));
      LanceurPointage.installee.value = true;
      await t.pump();
      expect(find.byKey(const Key('bouton_pointer')), findsOneWidget);
      LanceurPointage.detecteur = () async => false; // désinstallée entre-temps
      await t.tap(find.byKey(const Key('bouton_pointer')));
      await t.pump();
      await t.pump();
      expect(find.textContaining('Prestige Pointage n\'a pas pu être ouverte'), findsOneWidget);
      expect(find.byKey(const Key('bouton_pointer')), findsNothing);
    });

    test('tuile de l\'accueil : ajoutée au groupe Équipe seulement si installée ; hors des 23 menus', () {
      final f = {MenuFamille.equipe: <AccueilMenu>[], MenuFamille.ventes: <AccueilMenu>[]};
      expect(avecMenuPointage(f, installee: false), same(f));
      expect(avecMenuPointage(f, installee: true)[MenuFamille.equipe]!.single.id, 'prestige_pointage');
      expect(avecMenuPointage({MenuFamille.ventes: <AccueilMenu>[]}, installee: true)[MenuFamille.equipe]!.single, same(menuPrestigePointage));
      expect(LanceurPointage.paquet, 'com.dici.prestigepointage');
    });
  });
}
