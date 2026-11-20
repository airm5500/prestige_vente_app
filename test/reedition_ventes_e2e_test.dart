// E2E — 5.4.0 : application entière contre le faux serveur Prestige (route image de la demande 63, comme le serveur
// déployé 76aa5fc1), imprimante intégrée Sunmi simulée, données FICTIVES, SUNMI V2s / V3 (58 mm) :
//  1. vente comptant, 2 tickets : 1er ticket du serveur imprimé, « Ticket suivant (2/2) », 2e ticket (régression
//     de la 5.3.0 : la question n'apparaissait plus) ;
//  2. accueil › « Réédition des ventes » : la vente faite sur CE terminal est listée (une vente d'un autre poste
//     n'apparaît qu'avec « Tous les postes ») ; « Réimprimer » × 2 → deux exemplaires du ticket du serveur.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/services/impression_ticket.dart';
import 'package:prestige_vente_app/services/imprimante_sunmi.dart';
import 'package:prestige_vente_app/services/largeur_ticket.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/ventes/reedition/ventes_du_terminal.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';
import 'outils/demande63_fictive.dart';
import 'outils/parcours_vente.dart';
import 'outils/remises_fictives.dart';
import 'outils/ticket_capture.dart';

final _pause = find.byKey(const ValueKey('ticket-suivant'));

/// Liste « Ventes terminées » du faux serveur (GET v1/ventestats) : ventes clôturées, plus une vente d'un autre poste.
void _listeVentes(FauxServeurPrestige s, List<Map<String, String>> requetes) {
  s.statutVentes['V-AUTRE'] = 'is_Closed';
  s.routes['GET /ventestats'] = (r) {
    requetes.add(r.query);
    final jour = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final data = [
      for (final e in s.statutVentes.entries)
        if (e.value == 'is_Closed')
          {
            'lgPREENREGISTREMENTID': e.key,
            'strREF': 'REF-${e.key}',
            'strREFTICKET': e.key == 'V-AUTRE' ? '9900000001' : '41000${e.key.replaceAll(RegExp(r'\D'), '').padLeft(5, '0')}',
            'intPRICE': 2400,
            'intCUSTPART': 2400,
            'dtUPDATED': jour,
            'heure': e.key == 'V-AUTRE' ? '08:00' : '09:00',
            'strTYPEVENTE': 'VNO',
            'lgTYPEVENTEID': '1',
            'cancel': false,
            // le serveur a noté un autre nom de poste pour la vente de ce terminal : l'application la retrouve par
            // son identifiant noté à la clôture
            'posteSaisie': e.key == 'V-AUTRE' ? 'CAISSE 2' : 'ANCIEN NOM',
            'posteEncaissement': e.key == 'V-AUTRE' ? 'CAISSE 2' : 'ANCIEN NOM',
            'clientFullName': '',
          }
    ];
    return FauxServeurPrestige.ok({'total': data.length, 'data': data});
  };
}

void main() {
  setUp(() {
    TicketServeur.oublier();
    ImpressionTicket.reinitialiser();
    ImprimanteSunmi.reinitialiser();
    // Imprimante intégrée de 58 mm (terminal Sunmi) : le ticket du serveur part en raster vers le canal simulé.
    LargeurTicket.reinitialiser(avec: () async => 58);
    VentesDuTerminal.reinitialiser();
  });
  tearDown(() {
    LargeurTicket.reinitialiser();
    ImpressionTicket.reinitialiser();
  });

  testWidgets('comptant, 2 tickets (ticket du serveur, Sunmi), puis réédition depuis l\'accueil, 2 exemplaires', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = AppE2E();
    CatalogueFictif(app.serveur, nombre: 10);
    final d = Demande63Fictive(app.serveur, RemisesFictives(app.serveur));
    final listes = <Map<String, String>>[];
    _listeVentes(app.serveur, listes);
    final imp = ImprimanteSimulee()..installer(t);
    addTearDown(() => imp.retirer(t));
    await app.preparer(prefs: {...prefsVente, 'is_test_print_mode': false, 'number_of_tickets': 2});
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
    await app.attendre(t, const Duration(seconds: 2));

    // 1. Encaissement, 2 tickets.
    await t.tap(find.byKey(const ValueKey('vente-encaisser')));
    expect(await app.attendreQue(t, find.text('Exact')), isTrue);
    await t.tap(find.text('Exact'));
    await t.pump();
    final valider = find.byKey(const ValueKey('encaissement-valider'));
    await t.ensureVisible(valider);
    await t.pump();
    await t.tap(valider);
    expect(await app.attendreQue(t, _pause), isTrue, reason: 'question du 2e ticket (absente en 5.3.0)');
    expect(d.images, hasLength(1));
    expect(d.images.single, startsWith('vno V-1 58'));
    expect(find.text('Ticket suivant (2/2)'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ticket-suivant-imprimer')));
    await app.attendre(t, const Duration(seconds: 3));
    expect(d.images, hasLength(2), reason: '2e ticket demandé au serveur et imprimé');
    expect(ImpressionTicket.imagesImprimees, 2, reason: 'deux tickets envoyés à l\'imprimante Sunmi');
    expect(imp.appels.where((a) => a.startsWith('RAW_DATA')).length, 2);
    expect(_pause, findsNothing);
    expect(VentesDuTerminal.instance.contient('V-1'), isTrue, reason: 'vente notée sur ce terminal à sa clôture');

    // 2. Réédition depuis l'accueil.
    await app.retour(t);
    await app.attendre(t);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'reedition_ventes');
    expect(await app.attendreQue(t, find.byKey(const ValueKey('reedition-vente-V-1'))), isTrue);
    expect(listes.last['dtStart'], DateFormat('yyyy-MM-dd').format(DateTime.now()));
    expect(find.byKey(const ValueKey('reedition-vente-V-AUTRE')), findsNothing, reason: 'vente d\'un autre poste');
    await t.tap(find.text('Tous les postes'));
    await app.attendre(t, const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('reedition-vente-V-AUTRE')), findsOneWidget);
    await t.tap(find.text('Ce terminal'));
    await app.attendre(t, const Duration(milliseconds: 500));
    await t.tap(find.byKey(const ValueKey('reedition-reimprimer-V-1')));
    await app.attendre(t, const Duration(milliseconds: 500));
    await t.tap(find.byTooltip('Plus de copies'));
    await t.pump();
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Imprimer')));
    expect(await app.attendreQue(t, _pause), isTrue);
    expect(d.images, hasLength(3));
    await t.tap(find.byKey(const ValueKey('ticket-suivant-imprimer')));
    await app.attendre(t, const Duration(seconds: 3));
    expect(d.images, hasLength(4));
    expect(d.images.skip(2).every((i) => i.startsWith('vno V-1 ')), isTrue);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
