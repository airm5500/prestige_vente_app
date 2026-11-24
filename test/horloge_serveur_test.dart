// 5.5.0 — Transmission du serveur du 24/11/2026 (plan/24112026) : HEURE DU SERVEUR FAUSSE (règles, sans écran).
//  - 423 `{success:false, horlogeBloquee:true, msg}` reconnu (objet, texte, octets) ; sans le marqueur : rien ;
//  - `GET v1/horloge/public` : OK / BLOQUE / REGULARISATION, 404 (serveur ancien) = rien ; texte du bandeau ;
//  - état de l'application : blocage, déblocage par une écriture acceptée (jamais par v1/user/auth), journal sans le
//    `msg` du serveur ;
//  - couches : ClientPrestige → HorlogeBloquee (refus, titre propre), passerelle des ventes → VenteRefused horloge,
//    envoi du stock → StockHorlogeBloquee, photos des produits, file des ventes : vente gardée en attente.
// Données fictives uniquement.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_sender.dart';
import 'package:prestige_vente_app/images/produit_images.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/serveur/erreur_vue.dart';
import 'package:prestige_vente_app/serveur/horloge_serveur.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

const _msg = 'Opération refusée : l\'heure du serveur est fausse. L\'administrateur doit la corriger sur le serveur.';
const _corps = {'success': false, 'horlogeBloquee': true, 'msg': _msg};

/// Transport Dio scripté : chaque requête reçoit la réponse de [repondre].
class _Transport implements HttpClientAdapter {
  final ({int statut, Object corps}) Function(RequestOptions o) repondre;
  final List<String> recues = [];
  _Transport(this.repondre);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    recues.add('${o.method} ${o.uri.path}');
    final r = repondre(o);
    return ResponseBody.fromString(r.corps is String ? r.corps as String : jsonEncode(r.corps), r.statut,
        headers: {'content-type': ['application/json; charset=utf-8']});
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_Transport t, {bool tousStatuts = false}) {
  final d = Dio(BaseOptions(baseUrl: 'http://serveur-fictif:8080/prestige/api/v1', validateStatus: tousStatuts ? (_) => true : null));
  d.httpClientAdapter = t;
  return avecDeploiement(d);
}

void main() {
  late MemoryJournalStore store;
  setUp(() {
    HorlogeServeur.instance.reinitialiser();
    store = MemoryJournalStore();
    final journal = JournalTerminal(store: store);
    final prev = JournalTerminal.instance;
    JournalTerminal.instance = journal;
    addTearDown(() => JournalTerminal.instance = prev);
  });

  group('Lecture du refus 423', () {
    test('objet, texte et octets ; message du serveur tel quel', () {
      expect(horlogeBloqueeDe(423, _corps), _msg);
      expect(horlogeBloqueeDe(423, jsonEncode(_corps)), _msg);
      expect(horlogeBloqueeDe(423, utf8.encode(jsonEncode(_corps))), _msg);
      expect(horlogeBloqueeDe(423, {'success': false, 'horlogeBloquee': 'true', 'message': 'Autre texte'}), 'Autre texte');
    });

    test('sans message : texte par défaut, sans contournement', () {
      final m = horlogeBloqueeDe(423, {'success': false, 'horlogeBloquee': true});
      expect(m, messageHorlogeParDefaut);
      expect(m, contains('administrateur'));
      expect(m!.toLowerCase(), isNot(contains('réessay')));
    });

    test('autre code ou sans marqueur : rien (jamais pris pour une horloge bloquée)', () {
      expect(horlogeBloqueeDe(200, _corps), isNull);
      expect(horlogeBloqueeDe(409, _corps), isNull);
      expect(horlogeBloqueeDe(423, {'success': false, 'msg': 'Verrouillé'}), isNull);
      expect(horlogeBloqueeDe(423, '<html>Locked</html>'), isNull);
      expect(horlogeBloqueeDe(423, null), isNull);
    });

    test('routes jamais bloquées par le serveur', () {
      for (final c in ['/prestige/api/v1/user/auth', '/api/v1/user/auth-badge', '/api/v1/user/logout?x=1', '/api/v1/horloge/public']) {
        expect(routeHorsBlocage(c), isTrue, reason: c);
      }
      for (final c in ['/api/v1/mobile/connexion', '/api/v1/mobile/pointages', '/api/v1/vente/add/vno', '/api/v1/rh/pointages', '/api/v1/user/authx']) {
        expect(routeHorsBlocage(c), isFalse, reason: c);
      }
    });
  });

  group('GET v1/horloge/public', () {
    test('OK / BLOQUE / REGULARISATION ; 404 ou réponse inconnue : rien', () {
      expect(HorlogePublique.depuis(200, {'etat': 'OK', 'serveur': '24/11/2026 20:52'})!.etat, EtatHorloge.ok);
      expect(HorlogePublique.depuis(200, '{"etat":"BLOQUE","serveur":"24/11/2026 20:52"}')!.bloque, isTrue);
      expect(HorlogePublique.depuis(200, {'etat': 'regularisation'})!.etat, EtatHorloge.regularisation);
      expect(HorlogePublique.depuis(404, '<html>404</html>'), isNull);
      expect(HorlogePublique.depuis(200, {'etat': 'INCONNU'}), isNull);
      expect(HorlogePublique.depuis(200, 'pas du json'), isNull);
    });

    test('bandeau seulement si BLOQUE (REGULARISATION : écritures permises, rien à afficher)', () {
      final b = HorlogePublique.depuis(200, {'etat': 'BLOQUE', 'serveur': '24/11/2026 20:52'})!.texteBandeau!;
      expect(b, contains('24/11/2026 20:52'));
      expect(b, contains('administrateur'));
      expect(HorlogePublique.depuis(200, {'etat': 'OK'})!.texteBandeau, isNull);
      expect(HorlogePublique.depuis(200, {'etat': 'REGULARISATION'})!.texteBandeau, isNull);
    });

    test('lirePublique : appel sans session, 404 = null, jamais d\'exception', () async {
      var etat = 'BLOQUE';
      final t = _Transport((o) => etat == '404' ? (statut: 404, corps: '<html>404</html>') : (statut: 200, corps: {'etat': etat, 'serveur': '24/11/2026 20:52'}));
      final d = Dio(BaseOptions(baseUrl: 'http://serveur-fictif:8080/prestige/api/v1'))..httpClientAdapter = t;
      expect((await HorlogeServeur.lirePublique(d))!.bloque, isTrue);
      expect(t.recues.single, 'GET /prestige/api/v1/horloge/public');
      etat = '404';
      expect(await HorlogeServeur.lirePublique(d), isNull);
    });
  });

  group('État de l\'application', () {
    test('423 → bloqué (une fois par rafale) ; écriture acceptée → débloqué ; journal sans le msg', () async {
      final h = HorlogeServeur.instance;
      h.signaler(_msg);
      h.signaler(_msg);
      expect(h.bloquee, isTrue);
      expect(h.refus, 2);
      expect(h.blocages, 1);
      expect(h.message, _msg);
      h.debloquer();
      h.debloquer();
      expect(h.bloquee, isFalse);
      expect(h.deblocages, 1);
      await Future<void>.delayed(Duration.zero);
      final lignes = (await store.lire(const JournalFiltre())).map((e) => '${e.action} ${e.motif}').join('\n');
      expect(lignes.split('\n'), hasLength(2), reason: 'blocage et déblocage, une ligne chacun');
      expect(lignes, contains(motifJournalHorloge));
      expect(lignes, isNot(contains('administrateur doit')), reason: 'le msg du serveur n\'est jamais journalisé');
    });

    test('horloge/public : BLOQUE bloque, OK et REGULARISATION débloquent, null ne change rien', () {
      final h = HorlogeServeur.instance;
      h.appliquer(null);
      expect(h.bloquee, isFalse);
      h.appliquer(const HorlogePublique(EtatHorloge.bloque, ''));
      expect(h.bloquee, isTrue);
      h.appliquer(null);
      expect(h.bloquee, isTrue);
      h.appliquer(const HorlogePublique(EtatHorloge.regularisation, ''));
      expect(h.bloquee, isFalse);
    });

    test('intercepteur : 423 reconnu sur tout client ; v1/user/auth réussi ne débloque pas ; écriture réussie débloque',
        () async {
      var bloque = true;
      final t = _Transport((o) {
        if (o.uri.path.endsWith('/user/auth')) return (statut: 200, corps: {'success': true});
        if (o.method != 'GET' && bloque) return (statut: 423, corps: _corps);
        return (statut: 200, corps: {'success': true, 'data': []});
      });
      final d = _dio(t);
      await expectLater(d.post('/mobile/pointages', data: {}), throwsA(isA<DioException>()));
      expect(HorlogeServeur.instance.bloquee, isTrue);
      await d.get('/ventestats/preventes');
      await d.post('/user/auth', data: {});
      expect(HorlogeServeur.instance.bloquee, isTrue, reason: 'lecture et connexion ne prouvent rien');
      bloque = false;
      await d.post('/vente/add/vno', data: {});
      expect(HorlogeServeur.instance.bloquee, isFalse);
      expect(t.recues.where((r) => r == 'POST /prestige/api/v1/mobile/pointages'), hasLength(1), reason: 'aucune relance automatique');
    });

    test('verifierSiBloquee : aucun appel quand rien n\'est bloqué', () async {
      final t = _Transport((o) => (statut: 200, corps: {'etat': 'OK'}));
      final d = Dio(BaseOptions(baseUrl: 'http://serveur-fictif:8080/prestige/api/v1'))..httpClientAdapter = t;
      await HorlogeServeur.instance.verifierSiBloquee(d);
      expect(t.recues, isEmpty);
      HorlogeServeur.instance.signaler(_msg);
      await HorlogeServeur.instance.verifierSiBloquee(d);
      expect(t.recues, hasLength(1));
      expect(HorlogeServeur.instance.bloquee, isFalse);
    });
  });

  group('Couches de l\'application', () {
    test('ClientPrestige : HorlogeBloquee (refus métier), message tel quel, titre propre, jamais une panne', () async {
      // Appel réel contre le faux serveur : test/reseau/horloge_serveur_reseau_test.dart.
      const h = HorlogeBloquee(_msg);
      expect(h, isA<RefusMetier>());
      expect(h.code, HorlogeBloquee.codeHorloge);
      expect(messageErreur(h), _msg);
      expect(titreErreur(h), titreHorlogeBloquee);
      expect(titreErreur(h), isNot(contains('injoignable')));
      expect(iconeErreur(h), isNot(iconeErreur(const ServeurInjoignable())));
    });

    test('ventes : VenteRefused horloge (pas une anomalie, pas « déjà clôturée », pas « caisse fermée »)', () {
      const r = VenteRefused<void>(_msg, code: VenteRefused.codeHorloge);
      expect(r.horlogeBloquee, isTrue);
      expect(r.dejaCloturee, isFalse);
      expect(r.caisseFermee, isFalse);
      expect(r.interdit, isFalse);
      expect(r.uncertain, isFalse);
      expect(r.map((_) => 1), isA<VenteRefused<int>>().having((x) => x.horlogeBloquee, 'horloge', isTrue));
    });

    test('photo d\'un produit : 423 → refus avec le message du serveur', () {
      final r = ajoutDepuis(423, jsonEncode(_corps));
      expect(r, isA<VenteRefused<String>>());
      expect((r as VenteRefused).horlogeBloquee, isTrue);
      expect(r.message, _msg);
    });

    test('stock : 423 interrompt l\'envoi (StockHorlogeBloquee), ligne de retour remise « à envoyer », même clé', () async {
      final appels = <String>[];
      final srv = _StockSrv((m, p, h) {
        appels.add('$m $p ${h?['X-Client-Ref'] ?? ''}'.trim());
        if (m == 'GET' && p.contains('capacites')) return const StockHttp(200, {'success': true, 'clientRef': true});
        if (m == 'GET' && p.contains('client-ref')) return const StockHttp(404, {'success': false});
        return const StockHttp(423, _corps);
      });
      final op = StockOp(
        id: 'HL3-fictif-1',
        type: StockOpType.retour,
        refId: 'BL-1',
        meta: {'marker': '[HL:fictif]', 'blRef': 'BL-1'},
        lines: [StockOpLine(key: 'k1', label: 'PRODUIT FICTIF', data: {'produitId': 'P1', 'motifId': 'M1', 'qty': 1})],
        createdAt: DateTime(2026, 11, 24, 9),
      );
      final s = StockSender(srv, persist: (_) async {});
      await expectLater(s.apply(op), throwsA(isA<StockHorlogeBloquee>().having((e) => e.message, 'message', _msg)));
      expect(op.lines.single.etat, StockLineEtat.pending, reason: 'jamais « réponse perdue » au prochain envoi');
      await expectLater(StockSender(srv, persist: (_) async {}).apply(op), throwsA(isA<StockHorlogeBloquee>()));
      final creations = appels.where((a) => a.startsWith('POST /retourfournisseur/new')).toList();
      expect(creations, hasLength(2));
      expect(creations.toSet(), {'POST /retourfournisseur/new HL3-fictif-1'}, reason: 'même X-Client-Ref à chaque envoi');
      expect(op.lines.single.etat, isNot(StockLineEtat.rejected));
    });
  });
}

class _StockSrv implements StockServer {
  final StockHttp Function(String method, String path, Map<String, String>? headers) f;
  _StockSrv(this.f);
  @override
  Future<StockHttp> call(String method, String path, {Map<String, dynamic>? query, Object? data, Map<String, String>? headers}) async =>
      f(method, path, headers);
}
