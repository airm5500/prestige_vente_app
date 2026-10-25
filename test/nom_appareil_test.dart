// 4.7.0 — nom de cet appareil (en-tête X-Poste, demande du serveur du 25/10/2026) :
//  - nettoyage identique au serveur (util.ContexteRequete.nettoyer) : accents, caractères retirés, espaces de bord,
//    60 caractères au plus (coupé après le retrait des espaces), vide = aucun nom ;
//  - encodage URL (UTF-8) relu tel quel par le serveur (URLDecoder) ;
//  - nom saisi gardé sur l'appareil, nom par défaut = marque et modèle, intercepteur Dio.
// Les attendus ont été recoupés avec le code Java du serveur (même expression, même coupure).
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cas recoupés avec le serveur : saisie → nom enregistré (null = aucun nom, le serveur garde le nom réseau).
final casServeur = <String, String?>{
  'Caisse mobile 1': 'Caisse mobile 1',
  'SUNMI V2s': 'SUNMI V2s',
  '  Caisse  2  ': 'Caisse  2',
  'Comptoir à l\'entrée': 'Comptoir à lentrée',
  'Poste n°3 — étage': 'Poste n3  étage',
  'Caisse/Accueil#1': 'CaisseAccueil1',
  'Réserve_B.2-bis': 'Réserve_B.2-bis',
  'Œuvre ÇÀÉÈÊËÎÏÔÛÙÜŸ': 'Œuvre ÇÀÉÈÊËÎÏÔÛÙÜŸ',
  'Caisse 😀 1': 'Caisse  1',
  'Tab\tulation\nligne': 'Tabulationligne',
  'Insécable espace': 'Insécableespace',
  'Décomposé é': 'Décomposé e',
  'Chiffres ²½٣': 'Chiffres ²½٣',
  'شباك 1': 'شباك 1',
  '%20+&=?': '20',
  '': null,
  '   ': null,
  '🙂🙂': null,
  'jeton=abc;x': 'jetonabcx',
  'A' * 61: 'A' * 60,
  '${'B' * 59} C': 'B' * 59,
  '  ${'D' * 70}  ': 'D' * 60,
  '${'é' * 59}é€': 'é' * 60,
  '${'x' * 59}𝔸': 'x' * 59,
};

void main() {
  group('nettoyage (comme le serveur)', () {
    test('cas recoupés avec util.ContexteRequete.nettoyer', () {
      casServeur.forEach((brut, attendu) => expect(nettoyerNomPoste(brut), attendu, reason: brut));
      expect(nettoyerNomPoste(null), isNull);
    });

    test('jamais plus de 60 caractères (unités UTF-16, comme Java)', () {
      for (final brut in casServeur.keys) {
        expect((nettoyerNomPoste(brut) ?? '').length, lessThanOrEqualTo(longueurMaxPoste));
      }
    });

    test('encodage URL : relu à l\'identique, ASCII seulement, rien pour un nom vide', () {
      for (final brut in casServeur.keys) {
        final v = valeurEntetePoste(brut);
        final n = nettoyerNomPoste(brut);
        if (n == null) {
          expect(v, isNull, reason: brut);
          continue;
        }
        expect(RegExp(r'^[\x21-\x7E]+$').hasMatch(v!), isTrue, reason: 'en-tête HTTP ASCII : $v');
        expect(Uri.decodeComponent(v), n);
        expect(v.contains('+'), isFalse, reason: 'URLDecoder lirait « + » comme une espace');
      }
      expect(valeurEntetePoste('Caisse mobile 1'), 'Caisse%20mobile%201');
      expect(valeurEntetePoste('Comptoir é'), 'Comptoir%20%C3%A9');
    });
  });

  group('nom de cet appareil', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      NomAppareil.reinitialiser();
    });

    test('aucun nom enregistré : marque et modèle envoyés en attendant ; nom à enregistrer (obligatoire)', () async {
      final n = NomAppareil.instance..modele = () => 'SUNMI V2s';
      await n.charger();
      expect(n.nomEnregistre, isFalse);
      expect(n.effectif, 'SUNMI V2s');
      expect(n.entete, 'SUNMI%20V2s');
      n.modele = () => '';
      expect(n.effectif, isNull);
      expect(n.entete, isNull);
    });

    test('4.7.1 : nom nettoyé et gardé sur l\'appareil ; vide ou sans caractère permis : refusé, rien ne change', () async {
      final n = NomAppareil.instance..modele = () => 'SUNMI V2s';
      await n.charger();
      expect(await n.enregistrer('  '), isNull);
      expect(await n.enregistrer('#/!'), isNull);
      expect(n.nomEnregistre, isFalse);
      expect(await n.enregistrer('  Caisse/mobile 1 '), 'Caissemobile 1');
      final p = await SharedPreferences.getInstance();
      expect(p.getString(NomAppareil.prefNom), 'Caissemobile 1');
      expect(n.nomEnregistre, isTrue);
      expect(await n.enregistrer(''), isNull);
      expect(n.saisi, 'Caissemobile 1', reason: 'un nom enregistré ne s\'efface pas');
      NomAppareil.reinitialiser();
      final relu = NomAppareil.instance..modele = () => 'SUNMI V2s';
      await relu.charger();
      expect((relu.nomEnregistre, relu.effectif), (true, 'Caissemobile 1'), reason: 'relu après redémarrage');
    });

    test('nom par défaut enregistré tel quel (un appui sur Enregistrer)', () async {
      final n = NomAppareil.instance..modele = () => 'SUNMI V2s';
      await n.charger();
      expect(await n.enregistrer(n.parDefaut!), 'SUNMI V2s');
      expect(n.nomEnregistre, isTrue);
    });
  });

  // 4.7.1 (demande du pharmacien) : le nom n'est pas à ressaisir après une mise à jour.
  group('conservation', () {
    test('mise à jour : le nom saisi en 4.7.0 (préférences de l\'appareil) est relu tel quel, plus demandé', () async {
      // Préférences laissées par la 4.7.0 : une mise à jour Android garde les données de l'application.
      SharedPreferences.setMockInitialValues({'nom_appareil_v1': 'Caisse mobile 1', 'nom_appareil_propose_v1': true});
      NomAppareil.reinitialiser();
      final n = NomAppareil.instance..modele = () => 'SUNMI V2s';
      await n.charger();
      expect(n.effectif, 'Caisse mobile 1');
      expect(n.entete, 'Caisse%20mobile%201');
      expect(n.nomEnregistre, isTrue);
      expect(NomAppareil.prefNom, 'nom_appareil_v1', reason: 'clé figée : la changer ferait perdre le nom à la mise à jour');
    });

    test('mise à jour d\'une 4.7.0 sans nom (« Plus tard ») : nom à enregistrer', () async {
      SharedPreferences.setMockInitialValues({'nom_appareil_propose_v1': true});
      NomAppareil.reinitialiser();
      await NomAppareil.instance.charger();
      expect(NomAppareil.instance.nomEnregistre, isFalse);
    });

    test('sauvegarde Android : préférences de l\'application jamais exclues (seul le stockage sécurisé l\'est)', () {
      for (final f in ['android/app/src/main/res/xml/regles_sauvegarde.xml', 'android/app/src/main/res/xml/regles_extraction.xml']) {
        final x = File(f).readAsStringSync();
        expect(x, isNot(contains('FlutterSharedPreferences')), reason: f);
        expect(RegExp(r'<exclude domain="sharedpref" path="([^"]+)"').allMatches(x).map((m) => m.group(1)).toSet(), {'FlutterSecureStorage.xml'},
            reason: f);
      }
      expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(), isNot(contains('android:allowBackup="false"')));
    });
  });

  group('intercepteur', () {
    Future<RequestOptions> envoyer(Interceptor i, [Map<String, dynamic> entetes = const {}]) async {
      late RequestOptions vu;
      final d = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1/prestige/api/v1', headers: {...entetes}));
      d.interceptors.add(i);
      d.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        vu = o;
        h.resolve(Response(requestOptions: o, statusCode: 200, data: '{}'));
      }));
      await d.post('/vente/cloturer/vno', data: {'x': 1});
      return vu;
    }

    test('X-Poste posé ; corps, route et autres en-têtes inchangés ; aucun nom → aucun en-tête', () async {
      final o = await envoyer(IntercepteurPoste(entete: () => 'Caisse%20mobile%201'), {'X-Client-Ref': 'K1'});
      expect(o.headers[entetePoste], 'Caisse%20mobile%201');
      expect(o.headers['X-Client-Ref'], 'K1');
      expect(o.path, '/vente/cloturer/vno');
      expect(o.data, {'x': 1});
      final sans = await envoyer(IntercepteurPoste(entete: () => null));
      expect(sans.headers.containsKey(entetePoste), isFalse);
    });

    test('branché une seule fois', () {
      final d = Dio();
      IntercepteurPoste.brancher(d);
      IntercepteurPoste.brancher(d);
      expect(d.interceptors.whereType<IntercepteurPoste>(), hasLength(1));
    });
  });
}
