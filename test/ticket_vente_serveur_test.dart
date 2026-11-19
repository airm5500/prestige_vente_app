// UNITAIRES — 4.14.0 : ticket de vente mis en page comme le serveur (demande du pharmacien du 19/11/2026 : « ticket
// assurance désordonné, le prix passe sur 2 lignes ») et ticket dessiné par le serveur (route image).
// Données FICTIVES uniquement (test/outils/tickets_vente_fictifs.dart).
//  - cause reproduite : ticket composé pour 80 mm (48 colonnes) sur l'imprimante de 58 mm (32 colonnes) ;
//  - références (« golden ») en 32 et 48 colonnes : comptant (avec / sans remise, différé), assurance, carnet (crédit) ;
//  - chaque ligne ≤ largeur, montants alignés à droite, « quantité x prix » et montant sur UNE ligne, traits exacts ;
//  - largeur : règle du serveur, imprimante intégrée imposée ;
//  - route GET v1/vente/ticket/{type}/{id}/image : réponse lue, 404 / 405 → gabarit local, refus, largeur fausse.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/services/largeur_ticket.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/services/ticket_texte.dart';

import 'outils/remises_fictives.dart';
import 'outils/tickets_vente_fictifs.dart';

/// Montant en fin de ligne (« 1 500 », « 39 630 F », « - 4 070 F CFA »).
final _montantFinal = RegExp(r'\d[\d ]* ?(F|F CFA)?$');

/// Ce que fait une imprimante de [cols] colonnes d'une ligne plus longue : elle la coupe.
List<String> _imprimeSur(String ligne, int cols) => [for (var i = 0; i < ligne.length; i += cols) ligne.substring(i, (i + cols).clamp(0, ligne.length))];

class _Adaptateur implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions o) repondre;
  final List<RequestOptions> recues = [];
  _Adaptateur(this.repondre);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    recues.add(o);
    return repondre(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object corps, [int statut = 200]) =>
    ResponseBody.fromString(jsonEncode(corps), statut, headers: {Headers.contentTypeHeader: ['application/json']});

Dio _dio(ResponseBody Function(RequestOptions o) r, [List<RequestOptions>? recues]) {
  final a = _Adaptateur(r);
  final d = Dio(BaseOptions(baseUrl: 'http://serveur-fictif/prestige/api/v1'))..httpClientAdapter = a;
  if (recues != null) a.recues.addAll(recues);
  return d;
}

Map<String, dynamic> _image(int points, {int n = 1}) => {
      'success': true,
      'largeur': points == 384 ? 58 : 80,
      'tickets': [for (var i = 0; i < n; i++) {'modele': 'VENTE', 'png': base64Encode(RemisesFictives.pngFictif(points, 40)), 'largeurPoints': points, 'hauteurPoints': 40}],
    };

void main() {
  setUp(TicketServeur.oublier);

  group('Cause du ticket désordonné (photo du 19/11, reproduite avec des données fictives)', () {
    test('ancien gabarit 80 mm (colonnes 26 + 10 + 10) sur une imprimante de 32 colonnes : prix et en-tête coupés', () {
      // Lignes exactes de l'ancien code (receipt_service.dart 4.13.1) pour paperWidth = 80.
      String fit(String s, int len) => s.length <= len ? s.padRight(len) : s.substring(0, len);
      final entete = fit('Article', 26) + fit('Qte*P.U', 10) + fit('Total', 10);
      final detail = fit('', 26) + '1*1 500'.padRight(10) + '1 500'.padLeft(10);
      expect(_imprimeSur(entete, 32), ['Article                   Qte*P.', 'U   Total     ']);
      expect(_imprimeSur(detail, 32).first.trimLeft(), '1*1 50');
      expect(_imprimeSur(detail, 32)[1].trim(), startsWith('0'));
      expect(_imprimeSur('-' * 48, 32), hasLength(2), reason: 'trait sur deux lignes');
    });

    test('nouveau : largeur de l\'imprimante intégrée imposée (58 mm) même si le réglage dit 80 mm', () async {
      LargeurTicket.reinitialiser(avec: () async => 58);
      addTearDown(LargeurTicket.reinitialiser);
      expect(await LargeurTicket.pourImpression(80), 58);
      final t = ticketComptant(await LargeurTicket.pourImpression(80));
      for (final l in t.imprimees) {
        expect(_imprimeSur(l, 32), hasLength(lessThanOrEqualTo(1)), reason: 'ligne « $l » coupée par l\'imprimante');
      }
    });

    test('tablette (pas d\'imprimante intégrée) : le réglage 58 / 80 mm, ramené par la règle du serveur', () async {
      LargeurTicket.reinitialiser(avec: () async => null);
      addTearDown(LargeurTicket.reinitialiser);
      expect(await LargeurTicket.pourImpression(80), 80);
      expect(await LargeurTicket.pourImpression(58), 58);
      expect(LargeurTicket.valide(57), 58);
      expect(LargeurTicket.valide(100), 80);
      expect(LargeurTicket.points(58), 384);
      expect(LargeurTicket.points(80), 576);
    });
  });

  group('Références en 32 et 48 colonnes (comptant, différé, assurance, carnet / crédit)', () {
    final tickets = ticketsReference();
    for (final e in tickets.entries) {
      test('${e.key} : identique à test/references/tickets/${e.key}.txt', () {
        final ref = File('test/references/tickets/${e.key}.txt').readAsStringSync();
        expect('${e.value.texte}\n', ref);
      });

      test('${e.key} : chaque ligne tient, montants à droite, traits à la largeur exacte', () {
        final t = e.value;
        final cols = t.colonnes;
        expect(cols, e.key.endsWith('_58') ? 32 : 48);
        for (final l in t.lignes) {
          if (l.code) continue;
          final largeur = l.grand ? t.colonnesGrand : cols;
          final txt = l.imprimee(largeur);
          expect(txt.runes.length, lessThanOrEqualTo(largeur), reason: '« $txt »');
          expect(txt.runes.every((r) => r == 0x20 || (r > 0x20 && r <= 0xFF)), isTrue, reason: 'caractère de deux colonnes dans « $txt »');
          if (RegExp(r'^-+$').hasMatch(txt)) expect(txt.length, cols, reason: 'trait');
        }
        final lignes = t.imprimees;
        // « quantité x prix » et montant sur la même ligne, montant collé au bord droit.
        final details = lignes.where((l) => RegExp(r'^\d+ x \d').hasMatch(l)).toList();
        expect(details, hasLength(3));
        for (final d in details) {
          expect(d.length, cols);
          expect(_montantFinal.hasMatch(d), isTrue);
        }
        for (final l in lignes.where((l) => l.startsWith('Total') || l.startsWith('*') || l.startsWith('Part du client'))) {
          expect(l.length, cols, reason: '« $l » aligné à droite');
          expect(l.endsWith(cols == 32 ? ' F' : ' F CFA'), isTrue);
        }
        // Désignation longue : jamais tronquée.
        expect(lignes.join(' '), contains('B/40'));
      });
    }

    test('ordre des blocs du serveur : en-tête, titre, vendeur, client, articles, récapitulatif, totaux, net, règlement, pied', () {
      final l = ticketAssurance(58).imprimees.map((x) => x.trim()).toList();
      int i(String debut) => l.indexWhere((x) => x.startsWith(debut));
      final ordre = [i('PHARMACIE FICTIVE'), i('VENTE ASSURANCE'), i('Vendeur :'), i('Client :'), i('Part du client'), i('PRODUIT FICTIF A'),
        i('3 lignes'), i('Total'), i('*'), i('NET'), i('Règlement'), i('19/11/26'), i('[CODE]'), i('20261119000046')];
      expect(ordre.every((x) => x >= 0), isTrue, reason: '$ordre');
      expect(ordre, orderedEquals([...ordre]..sort()));
    });

    test('remise : « Total » puis « * - montant », net du serveur ; sans remise : aucune ligne « * »', () {
      expect(ticketComptant(58).imprimees, containsAllInOrder(['Total                   43 700 F', '*                      - 4 070 F']));
      expect(ticketComptant(58, remise: false).imprimees.where((l) => l.startsWith('*')), isEmpty);
      expect(ticketCarnet(80).imprimees, contains('Pris sur le carnet                  39 630 F CFA'));
      expect(ticketAssurance(80).imprimees.where((l) => l.startsWith('Vente à terme')), isEmpty, reason: 'part client non nulle');
    });

    test('comptant : toutes les informations d\'avant gardées (total, net, versé, monnaie, mode, vendeur, date, référence)', () {
      final l = ticketComptant(58).texte;
      for (final s in ['Total', 'NET', 'Espèces versées', 'Monnaie rendue', 'ESPECES', 'Vendeur : Vendeur Fictif', '19/11/26 10:42', '20261119000045', '[CODE]']) {
        expect(l, contains(s));
      }
    });

    test('espaces insécables des milliers (intl fr) remplacés : une colonne par caractère', () {
      expect(MiseEnPageTicket.nombre(1234567), '1 234 567');
      expect(MiseEnPageTicket.propre('1 500 × 2 − 3 · 4'), '1 500 x 2 - 3 - 4');
      expect(MiseEnPageTicket.paire('Libellé très long qui ne tient pas sur une ligne de ticket', '12 345 F', 32).last, endsWith('12 345 F'));
      expect(MiseEnPageTicket.paire('X', '1' * 40, 32).single.length, 32, reason: 'valeur trop large : jamais coupée sur deux lignes');
    });

    test('page de test : règle et traits de la largeur exacte', () {
      for (final p in [58, 80]) {
        final t = ReceiptService.pageTestLargeur(p);
        expect(t.imprimees.where((l) => RegExp(r'^[=<1]').hasMatch(l)).every((l) => l.length == TicketTexte.colonnesPour(p)), isTrue);
      }
    });
  });

  group('Borne (prévente) : même largeur imposée, ticket du serveur seulement pour une prévente à payer non discrète', () {
    final p = BornePrevente(venteId: 'V-B1', reference: '20261119000042', total: 1500, lignes: lignesTicket.take(1).toList(), at: dateFictive);
    test('ticket recomposé à la largeur de l\'imprimante (80 → 58 mm : 32 colonnes)', () {
      final t80 = BorneTicket(officine: 'Pharmacie Fictive', prevente: p, largeur: 80);
      final t58 = t80.aLargeur(58);
      expect(t58.lignes.every((l) => l.length <= 32), isTrue);
      expect(t80.lignes.any((l) => l.length > 32), isTrue);
      expect(identical(t80.aLargeur(80), t80), isTrue);
    });

    test('route image : prévente à payer oui ; payée (mobile money) ou « ticket discret » : gabarit de la borne', () async {
      expect(BorneTicket(officine: 'P', prevente: p).serveurPossible, isTrue);
      expect(BorneTicket(officine: 'P', prevente: p, payePar: 'WAVE').serveurPossible, isFalse);
      expect(BorneTicket(officine: 'P', prevente: p, discret: true).serveurPossible, isFalse);
      expect(await ticketBorneServeur(null, BorneTicket(officine: 'P', prevente: p)), isNull);
      final d = _dio((o) => _json(_image(384)));
      expect(await ticketBorneServeur(d, BorneTicket(officine: 'P', prevente: p)), hasLength(1));
      expect(await ticketBorneServeur(d, BorneTicket(officine: 'P', prevente: p, discret: true)), isNull);
    });
  });

  group('Route image du serveur (contrat de la demande du 19/11, faux serveur)', () {
    test('200 : tickets lus dans l\'ordre, largeur demandée (58 → 384 points, 80 → 576), état « présente »', () async {
      final recues = <RequestOptions>[];
      final d = _dio((o) {
        recues.add(o);
        return _json(_image(o.queryParameters['largeur'] == 58 ? 384 : 576, n: 2));
      });
      final r = await TicketServeur.lire(d, type: TypeTicketServeur.vo, id: 'V-FICT-A', largeur: 58);
      expect(r, isA<TicketsServeur>());
      expect((r as TicketsServeur).tickets, hasLength(2));
      expect(r.tickets.first.largeurPoints, 384);
      expect(recues.single.path, '/vente/ticket/vo/V-FICT-A/image');
      expect(recues.single.queryParameters, {'largeur': 58, 'dpi': 203});
      expect(recues.single.method, 'GET');
      expect(TicketServeur.etat(d.options.baseUrl), EtatRouteTicket.presente);
      final r80 = await TicketServeur.lire(d, type: TypeTicketServeur.vno, id: 'V-1', largeur: 100);
      expect((r80 as TicketsServeur).tickets.first.largeurPoints, 576);
      expect(recues.last.path, '/vente/ticket/vno/V-1/image');
    });

    test('404 / 405 : route absente → gabarit local, pas de nouvel essai avant 30 min', () async {
      for (final code in [404, 405]) {
        TicketServeur.oublier();
        var t0 = DateTime(2026, 11, 19, 10);
        TicketServeur.maintenant = () => t0;
        final d = _dio((o) => _json({'success': false, 'message': 'route inconnue'}, code));
        expect(await TicketServeur.lire(d, type: TypeTicketServeur.prevente, id: 'V-1', largeur: 58), isA<RouteTicketAbsente>());
        expect(TicketServeur.etat(d.options.baseUrl), EtatRouteTicket.absente);
        t0 = t0.add(const Duration(minutes: 31));
        expect(TicketServeur.etat(d.options.baseUrl), EtatRouteTicket.inconnue);
      }
    });

    test('refus : 403 interdit, success:false (vente introuvable), largeur fausse, PNG illisible ; 503 → réseau', () async {
      final cas = <Object, Matcher>{
        _json({'success': false, 'interdit': true, 'msg': 'Accès refusé (droit fictif).'}, 403): isA<TicketRefuse>().having((r) => r.message, 'msg', 'Accès refusé (droit fictif).'),
        _json({'success': false, 'msg': 'Vente introuvable'}): isA<TicketRefuse>().having((r) => r.message, 'msg', 'Vente introuvable'),
        _json(_image(576)): isA<TicketRefuse>(),
        _json({'success': true, 'tickets': [{'modele': 'VENTE', 'png': base64Encode([1, 2, 3]), 'largeurPoints': 384}]}): isA<TicketRefuse>(),
        _json({'success': true, 'tickets': []}): isA<TicketRefuse>(),
        _json('<html>503</html>', 503): isA<TicketReseauIndisponible>(),
      };
      for (final e in cas.entries) {
        final d = _dio((o) => e.key as ResponseBody);
        expect(await TicketServeur.lire(d, type: TypeTicketServeur.vno, id: 'V-1', largeur: 58), e.value);
      }
    });

    test('réseau coupé : « réseau indisponible », jamais d\'exception', () async {
      final d = _dio((o) => throw DioException.connectionError(requestOptions: o, reason: 'coupé'));
      expect(await TicketServeur.lire(d, type: TypeTicketServeur.vno, id: 'V-1', largeur: 58), isA<TicketReseauIndisponible>());
      expect(TicketServeur.messageReseau, 'Ticket non imprimé : réseau indisponible');
    });
  });
}
