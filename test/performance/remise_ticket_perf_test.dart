// PERFORMANCE — 4.14.0 (données FICTIVES) :
//  - composer un ticket de 300 lignes en 58 et 80 mm : moins de 200 ms ;
//  - choisir une remise : DEUX requêtes (POST v1/vente/remise, POST v1/vente/net/vno) plus la relecture du panier,
//    la liste des remises lue UNE fois ; aucune requête de remise sans action du vendeur ;
//  - route image absente : UN seul essai pour plusieurs tickets (mémoire de la route absente).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import '../outils/app_e2e.dart';
import '../outils/clients_vente_fictifs.dart';
import '../outils/parcours_vente.dart';
import '../outils/remises_fictives.dart';
import '../outils/tickets_vente_fictifs.dart';

void main() {
  test('300 lignes : ticket composé en moins de 200 ms (58 et 80 mm)', () {
    final lignes = [for (var i = 0; i < 300; i++) ligneTicket('PRODUIT FICTIF NUMERO $i AU NOM ASSEZ LONG POUR PASSER A LA LIGNE', 1 + i % 3, 100 + i)];
    for (final p in [58, 80]) {
      final sw = Stopwatch()..start();
      final t = ReceiptService.ticketVenteComptant(
          papier: p, officine: officineTicket, saleSummary: SaleSummary(montant: 1, montantNet: 1), items: lignes,
          paymentMethod: PaymentMethod(id: '1', name: 'ESPECES'), currentUser: vendeurTicket, date: dateFictive);
      sw.stop();
      expect(t.lignes.length, greaterThan(600));
      expect(sw.elapsedMilliseconds, lessThan(200));
    }
  });

  testWidgets('remise : requêtes comptées (application entière)', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    TicketServeur.oublier();
    final app = AppE2E();
    CatalogueFictif(app.serveur, nombre: 10);
    ClientsVenteFictifs(app.serveur);
    final rf = RemisesFictives(app.serveur);
    await app.preparer(prefs: prefsVente);
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
    await app.attendre(t, const Duration(seconds: 2));
    expect(app.serveur.recuesSur('/vente/remise'), isEmpty);
    expect(app.serveur.recuesSur('/common/remises-client'), isEmpty, reason: 'liste lue seulement à l\'ouverture');
    final avant = app.serveur.recues.length;
    for (final id in ['REM-FICT-10', 'REM-FICT-5']) {
      await t.tap(find.byKey(const ValueKey('remise-vente-choisir')));
      await app.attendre(t, const Duration(milliseconds: 900));
      await t.tap(find.byKey(ValueKey('remise-option-$id')));
      await app.attendre(t, const Duration(seconds: 2));
    }
    final apres = app.serveur.recues.skip(avant).map((r) => r.chemin.split('/v1').last).toList();
    expect(apres.where((c) => c == '/common/remises-client'), hasLength(1));
    expect(apres.where((c) => c == '/vente/remise'), hasLength(2));
    expect(apres.where((c) => c == '/vente/net/vno'), hasLength(2));
    expect(apres.length, 7, reason: 'liste + 2 × (remise, net, panier) : $apres');
    expect(rf.poses, hasLength(2));
    await app.fermer(t);
  });
}
