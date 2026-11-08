// PERFORMANCE — Prestige Mobile 4.11.0, plan du pharmacien du 08/11 :
//  - saisie de la péremption : 100 000 dates lues (règle commune) en moins de 1 s (douchette, saisie rapide) ;
//  - réserve, saisie rapide : UNE requête par produit saisi au CIP (deux au plus pour un DataMatrix : GTIN puis CIP),
//    aucune relecture des suggestions entre deux produits ;
//  - échelle des icônes : calcul du thème en moins de 2 ms par construction (1 000 constructions < 2 s).
// Données FICTIVES.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/reserve/reserve_api.dart';
import 'package:prestige_vente_app/reserve/reserve_models.dart';
import 'package:prestige_vente_app/reserve/reserve_panier_screen.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/services/saisie_peremption.dart';
import 'package:prestige_vente_app/ui/icones.dart';

class _Api extends ReserveApi {
  _Api() : super(ClientPrestige(() => 'http://127.0.0.1:1/prestige/api/v1'));
  final recherches = <String>[];
  int lecturesAttente = 0;
  @override
  Future<List<EnteteSuggestion>> enAttente({int limit = 200}) async {
    lecturesAttente++;
    return const [];
  }

  @override
  Future<List<MotifReserve>> motifs(SensReserve sens) async => const [MotifReserve(id: 1, libelle: 'Motif fictif', categorie: 'RAYON')];
  @override
  Future<PageArticles> articles(String recherche, {String type = '', int start = 0, int limit = 30}) async {
    recherches.add(recherche);
    return PageArticles([ArticleReserve(familleId: 'F$recherche', cip: recherche, nom: 'PRODUIT $recherche', stockRayon: 1, stockReserve: 50)], 1);
  }
}

void main() {
  test('péremption : 100 000 saisies lues en moins de 1 s', () {
    final saisies = ['0128', '010128', '01012028', '31/12/2027', '05/2028', '310228', '1/1/28'];
    final sw = Stopwatch()..start();
    var n = 0;
    for (var i = 0; i < 100000; i++) {
      if (lireDatePeremption(saisies[i % saisies.length]) != null) n++;
    }
    sw.stop();
    expect(n, greaterThan(80000));
    expect(sw.elapsedMilliseconds, lessThan(1000), reason: '${sw.elapsedMilliseconds} ms');
  });

  testWidgets('réserve, saisie rapide : 1 requête par produit (CIP), aucune relecture des suggestions entre deux produits', (t) async {
    t.view.physicalSize = const Size(720, 1440);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final api = _Api();
    await t.pumpWidget(MaterialApp(home: ReservePanierScreen(sens: SensReserve.versRayon, api: api)));
    await t.pumpAndSettle();
    final lectures = api.lecturesAttente;
    final champ = find.byKey(const ValueKey('reserve-saisie'));
    for (var i = 0; i < 20; i++) {
      await t.tap(champ);
      await t.enterText(champ, '${3400000 + i}');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('reserve-quantite')), '1');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
    }
    expect(api.recherches, hasLength(20), reason: 'une requête par produit');
    expect(api.lecturesAttente, lectures, reason: 'aucune relecture des suggestions pendant la saisie');
    expect(find.textContaining('Créer la suggestion (20 produit(s), 20 boîte(s))'), findsOneWidget);
  });

  test('icônes : thème mis à l\'échelle, 1 000 constructions en moins de 2 s', () {
    final base = ThemeData();
    final sw = Stopwatch()..start();
    for (var i = 0; i < 1000; i++) {
      EchelleIcones.theme(base, EchelleIcones.tablette);
    }
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(2000), reason: '${sw.elapsedMilliseconds} ms');
  });
}
