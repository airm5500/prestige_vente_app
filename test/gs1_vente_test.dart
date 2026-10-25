// 4.9.0 — lecture GS1 à la vente (alignée sur le web) : reconnaissance, verdicts du serveur (GET v1/vente/gs1), lot
// en attente (mode B), contrôle hors ligne, et SURTOUT aucune régression : lecture inactive, serveur ancien, panne,
// délai → exactement la recherche d'avant (mêmes codes essayés, même produit). Données FICTIVES.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/ventes/core/gs1_recherche.dart';
import 'package:prestige_vente_app/ventes/core/gs1_vente.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

ProductSearchResult _p(String id, String name, String cip) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: name, intCIP: cip, intPRICE: 1000, intNUMBERAVAILABLE: 5, strLIBELLEE: '', intPAF: 800);

/// DataMatrix GS1 d'une boîte de DOLIPRANE (fictif) : GTIN, péremption, lot.
const _dm = '0103400935955838\u001d17281031\u001d10LOTA1';
const _dmPerime = '0103400935955838\u001d17200131\u001d10LOTX';

/// Faux serveur des réponses de vente/gs1 : (statut, corps) ou exception ; requêtes notées.
class _Srv extends Interceptor {
  final List<String> chemins = [];
  FutureOr<(int, Object?)> Function(RequestOptions o)? reponse;
  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    chemins.add(o.path);
    final f = reponse;
    if (f == null) return h.reject(DioException(requestOptions: o, type: DioExceptionType.connectionError));
    try {
      final (s, b) = await f(o);
      h.resolve(Response(requestOptions: o, statusCode: s, data: b is String ? b : jsonEncode(b)));
    } catch (e) {
      h.reject(DioException(requestOptions: o, type: DioExceptionType.connectionError, error: e));
    }
  }
}

Map<String, dynamic> _ok({String controle = 'CONFORME', String mode = 'A', bool lotEnStock = false, bool perime = false}) => {
      'success': true,
      'actif': true,
      'gs1': true,
      'lot': 'LOTA1',
      'peremption': '31/10/2028',
      'perime': perime,
      'cip': '3595583',
      'gtin': '03400935955838',
      'lotPrevu': 'LOTB2',
      'peremptionPrevue': '30/06/2028',
      'controle': controle,
      'modeControle': mode,
      'lotEnStock': lotEnStock,
      'data': {'lgFAMILLEID': 'P83', 'intCIP': '3595583', 'strNAME': 'DOLI PRODUIT 083'},
    };

void main() {
  final catalog = [for (var i = 0; i < 120; i++) _p('P$i', 'DOLI PRODUIT ${i.toString().padLeft(3, '0')}', '35955${i.toString().padLeft(2, '0')}')];
  final appels = <String>[];
  Future<VenteResult<ProductPage>> recherche(String q, int start, int limit) async {
    appels.add(q);
    final all = catalog.where((p) => p.strNAME.startsWith(q) || p.intCIP.startsWith(q)).toList();
    return VenteOk(ProductPage(all.skip(start).take(limit).toList(), all.length));
  }

  late _Srv srv;
  late Gs1Vente g;
  setUp(() {
    appels.clear();
    srv = _Srv();
    g = Gs1Vente.instance;
    final d = Dio(BaseOptions(baseUrl: 'http://serveur.test/prestige/api/v1'))..interceptors.add(srv);
    g.dio = () => d;
    g.horsLigne = () => false;
    g.maintenant = () => DateTime(2026, 10, 25);
    g.actifPourTests = true;
  });

  group('reconnaissance (sans réseau)', () {
    test('étiquettes GS1 reconnues comme le web (préfixes ]d2 ]Q3 ]C1, forme lisible, 01+17/10/240, lien)', () {
      for (final v in [
        _dm,
        ']d2$_dm',
        ']Q3$_dm',
        ']C1$_dm',
        '(01)03400935955838(17)281031(10)LOTA1',
        '1728103110LOT\u001d2403595583',
        '10LOT\u001d2403595583',
        'https://id.gs1.org/01/03400935955838/10/LOTA1?17=281031',
      ]) {
        expect(Gs1Vente.ressembleGs1(v), isTrue, reason: v);
        expect(ProductLookup.looksLikeCode(v), isTrue, reason: v);
      }
    });

    test('codes-barres, CIP tapés, noms : jamais pris pour une étiquette GS1', () {
      for (final v in ['3400935955838', '3595583', '03400935955838', '0103400935955838', 'DOLIPRANE 1000', '1000', '(abc)', 'http://exemple.ci/produit/12']) {
        expect(Gs1Vente.ressembleGs1(v), isFalse, reason: v);
      }
    });

    test('lien GS1 Digital Link : traduit seulement s\'il est univoque', () {
      expect(Gs1Vente.depuisLienNumerique('https://id.gs1.org/01/03400935955838/10/LOTA1?17=281031'), '(01)03400935955838(17)281031(10)LOTA1');
      expect(Gs1Vente.depuisLienNumerique('https://id.gs1.org/01/03400935955838'), '(01)03400935955838');
      expect(Gs1Vente.depuisLienNumerique('https://id.gs1.org/01/03400935955839'), isNull, reason: 'clé de contrôle fausse');
      expect(Gs1Vente.depuisLienNumerique('https://id.gs1.org/01/03400935955838/10'), isNull, reason: 'segment orphelin');
      expect(Gs1Vente.depuisLienNumerique('https://id.gs1.org/01/03400935955838?17=2810'), isNull, reason: 'date illisible');
      expect(ProductLookup.codeCandidates('https://id.gs1.org/01/03400935955838/10/LOTA1').contains('3595583'), isTrue);
    });
  });

  group('verdicts du serveur (lecture active)', () {
    test('code-barres classique : aucun appel à vente/gs1', () async {
      expect(await g.verdict('3400935955838'), isA<Gs1CommeAvant>());
      expect(srv.chemins, isEmpty);
    });

    test('périmée : refusée « Boîte périmée (jj/mm/aaaa) : non ajoutée »', () async {
      srv.reponse = (_) => (200, _ok(perime: true));
      final v = await g.verdict(_dm) as Gs1Refus;
      expect(v.message, 'Boîte périmée (31/10/2028) : non ajoutée');
      expect(srv.chemins, ['/vente/gs1']);
    });

    test('mode C + lot différent : refusée « Prenez une boîte du lot Y (péremption …) »', () async {
      srv.reponse = (_) => (200, _ok(controle: 'DIFFERENT', mode: 'C'));
      final v = await g.verdict(_dm) as Gs1Refus;
      expect(v.message, startsWith('Prenez une boîte du lot LOTB2, péremption 30/06/2028'));
    });

    test('mode A + lot différent : accepté avec un avertissement, aucun lot envoyé', () async {
      srv.reponse = (_) => (200, _ok(controle: 'DIFFERENT'));
      final v = await g.verdict(_dm) as Gs1Accepte;
      expect((v.code, v.lotScanne), ('3595583', null));
      expect(v.avertissement, contains('Prestige sort le lot LOTB2'));
      expect(LotScanneEnAttente.prendre('P83'), isNull);
    });

    test('mode B + lot en stock : lot scanné en attente pour CE produit, pris une seule fois', () async {
      srv.reponse = (_) => (200, _ok(controle: 'DIFFERENT', mode: 'B', lotEnStock: true));
      final v = await g.verdict(_dm) as Gs1Accepte;
      expect(v.lotScanne, 'LOTA1');
      expect(v.avertissement, contains('la vente sortira ce lot'));
      expect(LotScanneEnAttente.champ('AUTRE'), isEmpty, reason: 'autre produit : rien, et l\'attente est vidée (comme le web)');
      expect(LotScanneEnAttente.champ('P83'), isEmpty);
      srv.reponse = (_) => (200, _ok(controle: 'DIFFERENT', mode: 'B', lotEnStock: true));
      await g.verdict(_dm);
      expect(LotScanneEnAttente.champ('P83'), {'lotScanne': 'LOTA1'});
      expect(LotScanneEnAttente.champ('P83'), isEmpty, reason: 'pris une seule fois');
    });

    test('mode B sans lot en stock : avertissement, aucun lot envoyé', () async {
      srv.reponse = (_) => (200, _ok(controle: 'DIFFERENT', mode: 'B'));
      final v = await g.verdict(_dm) as Gs1Accepte;
      expect(v.lotScanne, isNull);
      expect(LotScanneEnAttente.prendre('P83'), isNull);
    });

    test('conforme : accepté sans avertissement', () async {
      srv.reponse = (_) => (200, _ok());
      final v = await g.verdict(_dm) as Gs1Accepte;
      expect(v.avertissement, isNull);
    });

    test('étiquette étendue : refusée avec le message du serveur ; sans produit : message du serveur', () async {
      srv.reponse = (_) => (200, {'success': false, 'actif': true, 'etendu': true, 'msg': 'Étiquette étendue (DataMatrix+ ou QR+) : réservée…'});
      expect((await g.verdict(_dm) as Gs1Refus).message, startsWith('Étiquette étendue'));
      srv.reponse = (_) => (200, {'success': false, 'actif': true, 'gs1': false, 'sansProduit': true, 'msg': 'Étiquette sans produit : lot LOTA1.'});
      expect((await g.verdict(_dm) as Gs1Refus).message, 'Étiquette sans produit : lot LOTA1.');
    });
  });

  group('aucune régression : comportement d\'avant', () {
    // Recherche de référence : ProductLookup.byCode seul (4.8.0).
    Future<(List<String>, String?)> reference(String brut) async {
      appels.clear();
      final r = await ProductLookup.byCode(brut, recherche);
      return ([...appels], r.valueOrNull?.exact?.lgFAMILLEID);
    }

    final replis = <String, void Function(_Srv s, Gs1Vente g)>{
      'lecture inactive (0, vide, absente)': (s, g) => g.actifPourTests = false,
      'serveur ancien : 404': (s, g) => s.reponse = (_) => (404, '<html>404</html>'),
      'serveur ancien : 405': (s, g) => s.reponse = (_) => (405, ''),
      'panne réseau': (s, g) => s.reponse = null,
      'erreur 500': (s, g) => s.reponse = (_) => (500, '{}'),
      'réponse illisible': (s, g) => s.reponse = (_) => (200, '<html>'),
      'lecture désactivée entre-temps (actif:false)': (s, g) => s.reponse = (_) => (200, {'success': false, 'actif': false, 'msg': 'Lecture des étiquettes GS1 désactivée.'}),
      'aucun produit côté serveur': (s, g) => s.reponse = (_) => (200, {'success': false, 'actif': true, 'gs1': true, 'msg': 'Aucun produit…'}),
      'délai dépassé': (s, g) => s.reponse = (_) async {
            await Future<void>.delayed(const Duration(seconds: 5));
            return (200, _ok(perime: true));
          },
    };
    for (final MapEntry(key: nom, value: preparer) in replis.entries) {
      test('$nom : mêmes codes essayés, même produit, rien de refusé', () async {
        for (final brut in [_dm, ']d2$_dm', '(01)03400935955838(17)281031(10)LOTA1', _dmPerime]) {
          final (codesAvant, produitAvant) = await reference(brut);
          preparer(srv, g);
          Gs1Vente.delai = const Duration(milliseconds: 300);
          appels.clear();
          final r = await rechercherEtiquetteGs1(brut, recherche);
          expect(r!.refus, isNull, reason: '$nom : $brut');
          expect(appels, codesAvant, reason: '$nom : $brut');
          expect(r.produits.length == 1 ? r.produits.single.lgFAMILLEID : null, produitAvant, reason: '$nom : $brut');
          Gs1Vente.delai = const Duration(milliseconds: 2500);
        }
        expect(produitIdOuNull(await ProductLookup.byCode(_dm, recherche)), 'P83');
      });
    }
  });

  group('hors ligne (décision 1)', () {
    test('lecture active : boîte périmée refusée (date de l\'étiquette), lot non contrôlé ; sinon comme avant', () async {
      g.horsLigne = () => true;
      expect((await g.verdict(_dmPerime) as Gs1Refus).message, 'Boîte périmée (31/01/2020) : non ajoutée');
      expect(await g.verdict(_dm), isA<Gs1CommeAvant>());
      expect(srv.chemins, isEmpty, reason: 'aucun appel hors ligne');
      g.actifPourTests = false;
      expect(await g.verdict(_dmPerime), isA<Gs1CommeAvant>(), reason: 'lecture inactive : rien ne change');
    });
  });
}

String? produitIdOuNull(VenteResult<CodeLookup> r) => r.valueOrNull?.exact?.lgFAMILLEID;
