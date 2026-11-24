// 5.5.0 — Garde-fous (non-régression) du refus « heure du serveur fausse » (transmission du 24/11/2026) :
//  - tous les clients HTTP de Prestige observent le 423 (avecDeploiement pose IntercepteurHorloge) ;
//  - un 423 n'est jamais pris pour une panne (injoignable / indisponible) ni pour un 404 de Payara ;
//  - les files (ventes, stock, pointages, empreintes, centre de support) ne marquent jamais refusée / à vérifier une
//    opération refusée par l'horloge ; le msg du serveur n'est jamais écrit au journal ;
//  - aucune route nouvelle (vente-saisie/signal non implémentée) ; routes des points 2/3 : seule
//    ventestats/remove est utilisée.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/serveur/horloge_serveur.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';

String _lire(String p) => File(p).readAsStringSync();

Iterable<File> _dart() => Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

void main() {
  test('avecDeploiement pose IntercepteurHorloge (une fois) ; client de la session compris', () {
    final d = avecDeploiement(avecDeploiement(Dio()));
    expect(d.interceptors.whereType<IntercepteurHorloge>(), hasLength(1));
    expect(DioClient.session.interceptors.whereType<IntercepteurHorloge>(), hasLength(1));
  });

  test('423 jamais pris pour une panne ni un serveur indisponible', () {
    final r = Response<dynamic>(
      requestOptions: RequestOptions(path: '/vente/add/vno', method: 'POST'),
      statusCode: 423,
      data: {'success': false, 'horlogeBloquee': true, 'msg': 'Opération refusée : heure fausse (fictif).'},
    );
    expect(reponseIndisponible(r), isFalse);
    expect(panneDe(DioException(requestOptions: r.requestOptions, response: r, type: DioExceptionType.badResponse)), isNull);
    expect(corpsNonPrestige(r.data), isFalse, reason: 'jamais vérifié comme un 404 de Payara');
  });

  test('files : un refus horloge arrête l\'envoi sans marquer l\'opération refusée', () {
    expect(_lire('lib/horsligne/ventes_sync.dart'), contains('if (r.horlogeBloquee) throw _Panne('));
    expect(_lire('lib/horsligne/stock/stock_sender.dart'), contains('throw StockHorlogeBloquee(horloge)'));
    final rh = _lire('lib/rh/pointage_rh.dart');
    expect(RegExp('horlogeBloqueeDe\\(r\\.status, r\\.body\\)').allMatches(rh), hasLength(2), reason: 'en ligne et envoi de la file');
    expect(_lire('lib/rh/empreintes_partagees.dart'), contains('horlogeBloqueeDe(r.status, r.body) != null) return false'));
    expect(_lire('lib/support/support_centre.dart'), contains('return SupportReponse.echec'));
  });

  test('journal : catégorie seulement, jamais le msg du serveur', () {
    expect(_lire('lib/horsligne/ventes_sync.dart'), contains('motif: e.horloge ? motifJournalHorloge : e.message'));
    expect(_lire('lib/horsligne/stock/stock_queue.dart'), contains('motif: horloge ? motifJournalHorloge : e.message'));
    expect(_lire('lib/rh/pointage_rh.dart'), contains("motif: horloge ? motifJournalHorloge : ''"));
    expect(_lire('lib/serveur/horloge_serveur.dart'), contains('motif: motifJournalHorloge'));
    expect(motifJournalHorloge, isNot(contains('administrateur')));
  });

  test('aucune route nouvelle : vente-saisie/signal non implémentée ; points 2/3 non utilisés sauf ventestats/remove', () {
    final tout = _dart().map((f) => f.readAsStringSync()).join('\n');
    expect(tout, isNot(contains('vente-saisie')));
    for (final r in ['update-created-date', 'reglementdiffere', '/vente/rappel/', 'is_Trash']) {
      expect(tout, isNot(contains(r)), reason: r);
    }
    expect(tout, contains("'/ventestats/remove/"));
  });
}
