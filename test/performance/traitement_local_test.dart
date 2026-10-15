// PERFORMANCE — TRAITEMENTS LOCAUX (sans réseau) : temps réel mesuré, meilleur de 3 passages (la CI joue les
// tests en parallèle) :
//  - classement par début de code (4.0.3 F3 : Recherche Article, Évaluation Vente, accueil, Analyse article) de
//    5 000 produits, pour 20 saisies (CIP, CIP7, EAN-13, début de code) — résultat contrôlé ;
//  - génération de 100 tickets de vente (lignes envoyées à l'imprimante Sunmi simulée, 58 et 80 mm) ;
//  - génération de 100 tickets de la borne (lignes calculées, discret / normal, 58 et 80 mm).
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/services/classement_code.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';

import '../outils/performance.dart';
import '../outils/ticket_capture.dart';

typedef Produit = ({String cip, String ean, String nom});

/// 5 000 produits fictifs : CIP7 / CIP13 / EAN, triés par NOM (comme la réponse du serveur).
List<Produit> catalogue5000() {
  final l = <Produit>[
    for (var i = 0; i < 5000; i++)
      (
        cip: i.isEven ? '${3400900000000 + i * 7}' : (1000000 + i * 13).toString(),
        ean: '${3583310000000 + i}',
        nom: 'PRODUIT ${((i * 7919) % 5000).toString().padLeft(4, '0')}',
      ),
  ];
  return l..sort((a, b) => a.nom.compareTo(b.nom));
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('classement par début de code : 5 000 produits, 20 saisies', () async {
    final produits = catalogue5000();
    final saisies = [
      for (var i = 0; i < 20; i++) i.isEven ? produits[i * 211].cip.substring(0, 4 + i % 6) : produits[i * 197].ean.substring(0, 6 + i % 7),
    ];
    late List<Produit> dernier;
    final ms = await meilleurDe(3, () async {
      final sw = Stopwatch()..start();
      for (final s in saisies) {
        dernier = classerParCode(produits, s, (p) => p.cip, autres: (p) => [p.ean]);
      }
      return sw.elapsedMicroseconds / 1000;
    });
    mesurer('Classement par code de 5 000 produits (20 saisies)', ms, seuil: Seuils.classement5000Ms, unite: 'ms');
    // Résultat : même nombre de produits, ceux dont un code commence par la saisie en tête.
    expect(dernier, hasLength(5000));
    final s = saisies.last;
    final enTete = dernier.takeWhile((p) => p.cip.startsWith(s) || p.ean.startsWith(s)).length;
    expect(enTete, greaterThan(0));
    expect(dernier.skip(enTete).where((p) => p.cip.startsWith(s) || p.ean.startsWith(s)), isEmpty, reason: 'correspondances toutes en tête');
  });

  testWidgets('100 tickets de vente (imprimante Sunmi simulée)', (t) async {
    final ctx = await contexteTicket(t);
    final p = ImprimanteSimulee()..installer(t);
    addTearDown(() => p.retirer(t));
    final r = ReceiptService();
    final articles = [for (var i = 1; i <= 8; i++) article('PRODUIT ${i.toString().padLeft(4, '0')} COMPRIMES PELLICULES B/30', 1 + i % 3, 900 + 50 * i, id: 'L$i')];
    final total = articles.fold<int>(0, (s, a) => s + a.intPRICE);
    Future<void> tickets() async {
      for (var i = 0; i < 100; i++) {
        await r.printSaleTicket(
            context: ctx,
            officine: officineFictive,
            saleSummary: SaleSummary(montant: total, montantNet: total, reference: '2026101400${i.toString().padLeft(4, '0')}', venteId: 'V$i'),
            items: articles,
            paymentMethod: PaymentMethod(id: '1', name: 'Espèces'),
            currentUser: userFictif,
            isTestMode: false,
            paperWidth: i.isEven ? 58 : 80,
            showQrCode: true,
            ticketCodeType: i % 4 < 2 ? 'QR_CODE' : 'BARCODE',
            montantVerse: total + 1000,
            monnaie: 1000);
      }
    }

    // runAsync : l'imprimante simulée répond par des messages de plateforme (temps réel).
    final ms = await t.runAsync(() => meilleurDe(3, () async {
          p.textes.clear();
          final sw = Stopwatch()..start();
          await tickets();
          return sw.elapsedMicroseconds / 1000;
        }));
    mesurer('Génération de 100 tickets de vente (Sunmi simulée)', ms!, seuil: Seuils.tickets100Ms, unite: 'ms');
    expect(p.textes.where((l) => l.contains('PRODUIT 0008')), hasLength(100), reason: 'chaque ticket contient ses lignes');
  });

  test('100 tickets de la borne (58 / 80 mm, discret ou non)', () async {
    final lignes = [for (var i = 1; i <= 6; i++) article('PRODUIT ${i.toString().padLeft(4, '0')} CPR', 1 + i % 2, 1000 + i, id: 'L$i')];
    var n = 0;
    final ms = await meilleurDe(3, () async {
      n = 0;
      final sw = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        n += BorneTicket(officine: 'Pharmacie Fictive', prevente: preventeBorne(lignes), discret: i.isOdd, largeur: i % 4 < 2 ? 58 : 80).lignes.length;
      }
      return sw.elapsedMicroseconds / 1000;
    });
    mesurer('Génération de 100 tickets de la borne', ms, seuil: Seuils.ticketsBorne100Ms, unite: 'ms');
    expect(n, greaterThan(100 * 6));
  });
}
