// NON-RÉGRESSION — 4.14.0 (demande du 19/11/2026) :
//  - le mobile n'appelle JAMAIS POST v1/vente/ticket/vno ni ticket/vo (impression sur l'imprimante du serveur) ;
//  - un seul gabarit local de ticket de VENTE (ticket_texte.dart), gardé tant que la route image n'est pas déployée ;
//    l'ancien gabarit à colonnes (« Qte*P.U ») n'existe plus ;
//  - la largeur de l'imprimante intégrée passe avant le réglage (cause du ticket du 19/11) ;
//  - aucun texte de ticket, nom de client ou de patient dans les journaux (impression, remise) ;
//  - la borne ne propose jamais de remise ; chaque calcul du net comptant envoie la remise choisie ;
//  - tickets de prévente inchangés (test/ticket_prevente_test.dart garde leur référence 4.1.0).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/services/ticket_texte.dart';

import 'outils/tickets_vente_fictifs.dart';

String _lire(String p) => File(p).readAsStringSync();
Iterable<File> _dart(String dossier) => Directory(dossier).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

void main() {
  test('aucun appel aux routes qui impriment sur l\'imprimante du serveur', () {
    final motif = RegExp(r'''post\(\s*['"]/vente/ticket/(vno|vo)['"/]''');
    for (final f in _dart('lib')) {
      expect(motif.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
    expect(_lire('lib/services/ticket_serveur.dart'), contains("'/vente/ticket/\${type.chemin}/\${Uri.encodeComponent(id)}/image'"));
  });

  test('un seul gabarit local de vente, ancien gabarit à colonnes retiré, gabarit gardé (route pas encore déployée)', () {
    final r = _lire('lib/services/receipt_service.dart');
    expect(r, isNot(contains('Qte*P.U')));
    expect(r, isNot(contains('_printSaleTicketSunmi')));
    expect(r, isNot(contains('_printAssuranceSaleTicketSunmi')));
    expect(r, contains('TicketVenteTexte.vente('));
    expect(r, contains('ImpressionTicket.parServeur'));
    expect(RegExp('TypeTicketServeur\\.(vno|vo|prevente)').allMatches(r).map((m) => m.group(1)).toSet(), {'vno', 'vo', 'prevente'});
  });

  test('largeur : imprimante intégrée d\'abord, réglage ensuite, pour chaque ticket (vente, prévente, rapport, borne)', () {
    final r = _lire('lib/services/receipt_service.dart');
    expect(RegExp(r'LargeurTicket\.pourImpression\(').allMatches(r).length, greaterThanOrEqualTo(5));
    expect(_lire('lib/borne/borne_ticket.dart'), contains('LargeurTicket.pourImpression('));
  });

  test('confidentialité : aucun journal dans le ticket, l\'impression et la remise', () {
    for (final p in ['lib/services/ticket_texte.dart', 'lib/services/ticket_serveur.dart', 'lib/services/impression_ticket.dart', 'lib/services/largeur_ticket.dart', 'lib/ventes/common/remise_vente.dart']) {
      final s = _lire(p);
      expect(RegExp(r'\b(print|debugPrint|journalErreur|log)\(').hasMatch(s), isFalse, reason: p);
    }
  });

  test('borne : jamais de zone Remise ; net comptant toujours envoyé avec la remise choisie', () {
    for (final f in [..._dart('lib/borne'), if (Directory('lib/prestigepos').existsSync()) ..._dart('lib/prestigepos')]) {
      expect(f.readAsStringSync(), isNot(contains('RemiseVenteZone')), reason: f.path);
    }
    final c = _lire('lib/ventes/prevente/vente_controller.dart');
    expect(c, contains('Future.wait([gateway.saleDetails(id), _netVno(id)])'));
    expect(RegExp(r'gateway\.netVno\(').allMatches(c), hasLength(1), reason: 'seul repli : aucune remise choisie');
  });

  test('tickets : aucune ligne plus large que le papier, quel que soit le ticket de référence', () {
    for (final t in ticketsReference().values) {
      for (final l in t.lignes.where((l) => !l.code)) {
        expect(l.imprimee(l.grand ? t.colonnesGrand : t.colonnes).length, lessThanOrEqualTo(l.grand ? t.colonnesGrand : t.colonnes));
      }
    }
    expect(TicketTexte.colonnesPour(58), 32);
    expect(TicketTexte.colonnesPour(80), 48);
  });
}
