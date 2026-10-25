// 4.7.0 — nom de cet appareil (en-tête X-Poste, demande du serveur du 25/10/2026) :
//  - nettoyage identique au serveur (util.ContexteRequete.nettoyer) : accents, caractères retirés, espaces de bord,
//    60 caractères au plus (coupé après le retrait des espaces), vide = aucun nom ;
//  - encodage URL (UTF-8) relu tel quel par le serveur (URLDecoder) ;
//  - nom saisi gardé sur l'appareil, nom par défaut = marque et modèle, intercepteur Dio.
// Les attendus ont été recoupés avec le code Java du serveur (même expression, même coupure).
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

    test('sans saisie : marque et modèle ; marque inconnue : aucun en-tête', () async {
      final n = NomAppareil.instance..modele = () => 'SUNMI V2s';
      await n.charger();
      expect(n.effectif, 'SUNMI V2s');
      expect(n.entete, 'SUNMI%20V2s');
      expect(n.dejaPropose, isFalse);
      n.modele = () => '';
      expect(n.effectif, isNull);
      expect(n.entete, isNull);
    });

    test('saisie nettoyée et gardée sur l\'appareil ; vide = retour au nom par défaut', () async {
      final n = NomAppareil.instance..modele = () => 'SUNMI V2s';
      await n.charger();
      expect(await n.enregistrer('  Caisse/mobile 1 '), 'Caissemobile 1');
      final p = await SharedPreferences.getInstance();
      expect(p.getString(NomAppareil.prefNom), 'Caissemobile 1');
      expect(n.dejaPropose, isTrue);
      NomAppareil.reinitialiser();
      final relu = NomAppareil.instance..modele = () => 'SUNMI V2s';
      await relu.charger();
      expect(relu.effectif, 'Caissemobile 1', reason: 'relu après redémarrage');
      expect(await relu.enregistrer('  '), 'SUNMI V2s');
      expect(p.getString(NomAppareil.prefNom), isNull);
      expect(relu.dejaPropose, isTrue, reason: 'déjà proposé : plus de proposition');
    });

    test('« Plus tard » : proposé une seule fois', () async {
      final n = NomAppareil.instance;
      await n.charger();
      await n.marquerPropose();
      NomAppareil.reinitialiser();
      await NomAppareil.instance.charger();
      expect(NomAppareil.instance.dejaPropose, isTrue);
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
