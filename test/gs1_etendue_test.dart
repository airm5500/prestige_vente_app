// 4.9.2 — étiquettes étendues d'Étiquetage Pro (DataMatrix+, QR+) refusées à la vente comme le web, MÊME lecture GS1
// inactive ou absente, sans requête :
//  - reconnaissance : portage exact de VenteCtr / DevisCtr.estEtiquetteEtendue (préfixes ]d2 ]Q3 ]Q1 ]C1 ]e0, « EP1| »,
//    champ 91 EPLUS1 après GS / <GS> / ^] / ~1 / |, entre parenthèses ou en tête) ; jamais une étiquette GS1 normale,
//    un code-barres, un CIP, un nom ;
//  - verdict : refus local (lecture active, inactive, hors ligne), aucune requête ; Dépôt (etendueLocale: false) :
//    comme avant ;
//  - recherche Proforma (etendueRefusee) : refus ; Dépôt : comme avant ; autres menus : inchangés.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/services/product_finder.dart';
import 'package:prestige_vente_app/ventes/core/gs1_recherche.dart';
import 'package:prestige_vente_app/ventes/core/gs1_vente.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

ProductSearchResult _p(String id, String name, String cip) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: name, intCIP: cip, intPRICE: 1000, intNUMBERAVAILABLE: 5, strLIBELLEE: '', intPAF: 800);

/// Étiquettes FICTIVES.
const _gs1 = '0103400935955838\u001d17281031\u001d10LOTA1';
const _dmPlus = '$_gs1\u001d91EPLUS1\u001d92DOLI_FICTIF\u001d931250';
const _qrPlus = 'EP1|CIP:3400935955838|NOM:DOLI FICTIF|PRIX:1250|LOT:LOTA1|PER:31/10/2028';

class _Api extends ApiService {
  _Api() : super(baseUrl: 'http://localhost');
  final appels = <String>[];
  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    appels.add(query);
    final p = _p('P83', 'DOLI FICTIF', '3595583');
    final ok = '3595583'.startsWith(query) || query == '3400935955838';
    return ProductPage(ok ? [p] : const [], ok ? 1 : 0);
  }
}

class _Srv extends Interceptor {
  int appels = 0;
  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) {
    appels++;
    h.resolve(Response(requestOptions: o, statusCode: 200, data: jsonEncode({'success': true, 'actif': true, 'cip': '3595583', 'controle': 'CONFORME'})));
  }
}

void main() {
  late _Srv srv;
  setUp(() {
    srv = _Srv();
    final d = Dio()..interceptors.add(srv);
    final g = Gs1Vente.instance;
    g.dio = () => d;
    g.horsLigne = () => false;
    g.maintenant = () => DateTime(2026, 10, 25);
  });

  group('reconnaissance (comme le web)', () {
    test('étendues reconnues sous toutes les formes des douchettes', () {
      for (final e in [
        _dmPlus,
        ']d2$_dmPlus',
        ']Q3$_qrPlus',
        ']Q1$_qrPlus',
        ']C1$_dmPlus',
        ']e0$_dmPlus',
        _qrPlus,
        'ep1|cip:3400935955838',
        '${_gs1.replaceAll('\u001d', '<GS>')}<GS>91EPLUS1<GS>92DOLI',
        '${_gs1.replaceAll('\u001d', '^]')}^]91EPLUS1',
        '${_gs1.replaceAll('\u001d', '~1')}~191EPLUS1',
        '${_gs1.replaceAll('\u001d', '|')}|91EPLUS1|92DOLI',
        '(01)03400935955838(17)281031(10)LOTA1(91)EPLUS1(92)DOLI_FICTIF',
        '91EPLUS1\u001d92DOLI',
        '  $_qrPlus  ',
      ]) {
        expect(Gs1Vente.estEtiquetteEtendue(e), isTrue, reason: e.replaceAll('\u001d', '<GS>'));
      }
    });

    test('jamais une étiquette normale, un code-barres, un CIP, un nom, ni un champ 91 d\'un fabricant', () {
      for (final n in [
        _gs1,
        ']d2$_gs1',
        '(01)03400935955838(17)281031(10)LOTA1',
        'https://id.gs1.org/01/03400935955838/10/LOTA1',
        '3400935955838',
        '3595583',
        'DOLIPRANE 1000',
        'EP1 sans barre',
        'XEP1|CIP:1',
        '$_gs1\u001d91ABC123',
        // GS perdu (champ qui retire les caractères de contrôle) : sans séparateur, le web ne la reconnaît pas non plus.
        _dmPlus.replaceAll('\u001d', ''),
        'EPLUS1',
        '(91)EPLUS',
      ]) {
        expect(Gs1Vente.estEtiquetteEtendue(n), isFalse, reason: n.replaceAll('\u001d', '<GS>'));
      }
    });
  });

  group('verdict : refus local, sans requête', () {
    for (final (cas, actif, horsLigne) in [
      ('lecture active', true, false),
      ('lecture inactive', false, false),
      ('hors ligne, lecture inactive', false, true),
      ('hors ligne, lecture active', true, true),
    ]) {
      test(cas, () async {
        Gs1Vente.instance.actifPourTests = actif;
        Gs1Vente.instance.horsLigne = () => horsLigne;
        for (final e in [_dmPlus, _qrPlus]) {
          final v = await Gs1Vente.instance.verdict(e);
          expect(v, isA<Gs1Refus>());
          expect((v as Gs1Refus).message, Gs1Refus.messageEtendue);
          expect(v.raison, 'etendu');
        }
        expect(srv.appels, 0);
      });
    }

    test('message exact du web', () {
      expect(Gs1Refus.messageEtendue,
          'Cette étiquette (DataMatrix+ ou QR+) est réservée à la commande, à la réception et à l\'inventaire : elle ne passe pas '
          'à la vente. Scannez le code de la boîte ou l\'étiquette standard du produit.');
    });

    test('Dépôt (etendueLocale: false), lecture inactive : comme avant', () async {
      Gs1Vente.instance.actifPourTests = false;
      expect(await Gs1Vente.instance.verdict(_dmPlus, etendueLocale: false), isA<Gs1CommeAvant>());
      expect(await Gs1Vente.instance.verdict(_qrPlus, etendueLocale: false), isA<Gs1CommeAvant>());
    });

    test('étiquette normale, lecture inactive : comme avant (inchangé)', () async {
      Gs1Vente.instance.actifPourTests = false;
      expect(await Gs1Vente.instance.verdict(_gs1), isA<Gs1CommeAvant>());
      expect(srv.appels, 0);
    });
  });

  group('recherches', () {
    Future<VenteResult<ProductPage>> recherche(String q, int s, int l) async =>
        VenteOk(ProductPage(q == '3400935955838' || q == '3595583' ? [_p('P83', 'DOLI FICTIF', '3595583')] : const [], 1));

    test('vente (nouvelle et ancienne interface) : refus, aucune recherche de produit', () async {
      Gs1Vente.instance.actifPourTests = false;
      for (final e in [_dmPlus, _qrPlus]) {
        final r = (await rechercherEtiquetteGs1(e, recherche))!;
        expect(r.refus?.message, Gs1Refus.messageEtendue);
        expect(r.produits, isEmpty);
      }
      expect(await rechercherEtiquetteGs1('DOLIPRANE', recherche), isNull);
      expect(await rechercherEtiquetteGs1('3400935955838', recherche), isNull);
    });

    test('Proforma : refus ; Dépôt et autres menus : comme avant', () async {
      Gs1Vente.instance.actifPourTests = false;
      final api = _Api();
      final proforma = PagedProductSearch(() => api, gs1Vente: true, etendueRefusee: true);
      await proforma.run(_qrPlus);
      expect(proforma.refusGs1, Gs1Refus.messageEtendue);
      await proforma.run(_dmPlus);
      expect(proforma.refusGs1, Gs1Refus.messageEtendue);
      expect(api.appels, isEmpty);
      for (final s in [PagedProductSearch(() => api, gs1Vente: true), PagedProductSearch(() => api)]) {
        for (final e in [_dmPlus, _qrPlus]) {
          final avant = PagedProductSearch(() => api);
          await avant.run(e);
          await s.run(e);
          expect(s.refusGs1, isNull);
          expect(s.items.map((p) => p.lgFAMILLEID).toList(), avant.items.map((p) => p.lgFAMILLEID).toList());
          expect(s.notFound, avant.notFound);
        }
      }
      expect(srv.appels, 0);
    });

    test('4.9.3 — Dépôt, lecture ACTIVE : étiquette étendue ni refusée ni envoyée à vente/gs1, recherche d\'avant', () async {
      Gs1Vente.instance.actifPourTests = true;
      final api = _Api();
      for (final e in [_dmPlus, _dmPlus.replaceAll('\u001d', '|'), _dmPlus.replaceAll('\u001d', '<GS>'), _qrPlus, ']Q3$_qrPlus']) {
        final avant = PagedProductSearch(() => api);
        await avant.run(e);
        final depot = PagedProductSearch(() => api, gs1Vente: true);
        await depot.run(e);
        expect((depot.refusGs1, depot.avertissementGs1), (null, null));
        expect(depot.items.map((p) => p.lgFAMILLEID).toList(), avant.items.map((p) => p.lgFAMILLEID).toList());
        expect((depot.notFound, depot.error, depot.byCode), (avant.notFound, avant.error, avant.byCode));
      }
      expect(srv.appels, 0, reason: 'jamais vente/gs1 pour une étiquette étendue au Dépôt');
      // Étiquette normale au Dépôt, lecture active : verdict du serveur comme en 4.9.1.
      await PagedProductSearch(() => api, gs1Vente: true).run(_gs1);
      expect(srv.appels, 1);
    });

    test('4.9.3 — Proforma et vente, lecture active : étiquette étendue toujours refusée', () async {
      Gs1Vente.instance.actifPourTests = true;
      final api = _Api();
      final proforma = PagedProductSearch(() => api, gs1Vente: true, etendueRefusee: true);
      await proforma.run(_qrPlus);
      expect(proforma.refusGs1, Gs1Refus.messageEtendue);
      final r = (await rechercherEtiquetteGs1(_dmPlus, recherche))!;
      expect(r.refus?.message, Gs1Refus.messageEtendue);
      expect(srv.appels, 0);
    });

    test('ProductLookup inchangé pour une étiquette normale', () async {
      final r = await ProductLookup.byCode(_gs1, recherche);
      expect(r.valueOrNull!.exact!.lgFAMILLEID, 'P83');
    });
  });
}
