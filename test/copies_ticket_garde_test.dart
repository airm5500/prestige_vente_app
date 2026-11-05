// NON-RÉGRESSION — 4.10.3 : garde-fous sur le code des ventes de la nouvelle interface (lib/ventes) — retour du
// pharmacien « copies imprimées à la suite » :
//  - aucune boucle d'impression de copies hors de imprimerCopiesAvecPause (lib/ventes/common/copies_ticket.dart) ;
//  - tout appel à printSaleTicket / printAssuranceSaleTicket imprime UNE copie (numberOfCopies: 1 ou défaut) ;
//  - ancienne interface (lib/screens) inchangée : ReceiptService garde « Réimpression » par défaut (confirmEachCopy).
// Et : la borne (PrestigePOS, écran client) n'imprime qu'un ticket, jamais de dialogue de caisse.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dart(String dossier) =>
    Directory(dossier).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

void main() {
  test('nouvelle interface : aucune impression de copies en boucle, une copie par appel', () {
    for (final f in _dart('lib/ventes')) {
      final s = f.readAsStringSync();
      if (f.path.endsWith('copies_ticket.dart')) continue; // la boucle avec la pause elle-même
      expect(RegExp(r'for \([^)]*copies').hasMatch(s), isFalse, reason: '${f.path} : boucle de copies sans pause');
      for (final m in RegExp(r'numberOfCopies:\s*([^,\n]+)').allMatches(s)) {
        expect(m.group(1)!.trim(), '1', reason: '${f.path} : numberOfCopies ≠ 1 (copies à la suite)');
      }
      if (RegExp(r'print(Sale|AssuranceSale)Ticket\(').hasMatch(s)) {
        expect(s, contains('imprimerCopiesAvecPause('), reason: '${f.path} : ticket de vente sans la pause entre les copies');
      }
    }
  });

  test('ancienne interface inchangée : « Réimpression » par défaut dans ReceiptService', () {
    final s = File('lib/services/receipt_service.dart').readAsStringSync();
    expect(RegExp('bool confirmEachCopy = true').allMatches(s), hasLength(2));
    expect(s, contains('Voulez-vous réimprimer le ticket ?'));
  });

  test('borne : un seul ticket, aucun dialogue de caisse', () {
    final s = File('lib/borne/borne_ticket.dart').readAsStringSync();
    expect(s, isNot(contains('imprimerCopiesAvecPause')));
    expect(s, isNot(contains('numberOfCopies')));
    expect(File('lib/services/receipt_service.dart').readAsStringSync(), contains('printBorneTicket('));
  });
}
