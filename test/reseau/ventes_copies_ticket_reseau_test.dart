// RÉSEAU — 4.10.3 : pause « Ticket suivant (i/N) » entre les copies, application entière (vrai Dio, faux serveur
// Prestige en mémoire, temps simulé) :
//  - clôture lente (5 s) : aucun ticket ni aucune pause avant la réponse du serveur ; puis copie 1, pause ;
//  - serveur coupé PENDANT la pause : la copie suivante s'imprime quand même (rien n'est demandé au serveur entre les
//    copies), aucune seconde clôture, aucune requête pendant la pause.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import '../outils/app_e2e.dart';
import '../outils/parcours_vente.dart';
import '../outils/ticket_capture.dart';

final _pause = find.byKey(const ValueKey('ticket-suivant'));

void main() {
  testWidgets('clôture lente (5 s) puis serveur coupé pendant la pause : 2 tickets, une seule clôture', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final imp = ImprimanteSimulee()..installer(t);
    addTearDown(() => imp.retirer(t));
    int tickets() => imp.appels.where((a) => a.startsWith('BIND_PRINTER_SERVICE')).length;
    final app = AppE2E();
    final c = CatalogueFictif(app.serveur, nombre: 10)..delaiCloture = const Duration(seconds: 5);
    await app.preparer(prefs: {...prefsVente, 'is_test_print_mode': false, 'number_of_tickets': 2});
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    expect(await ajouterAuPanier(t, app, nomCourt(2)), isTrue);
    await app.attendre(t, const Duration(seconds: 2));

    await t.tap(find.byKey(const ValueKey('vente-encaisser')));
    expect(await app.attendreQue(t, find.text('Exact')), isTrue);
    await t.tap(find.text('Exact'));
    await t.pump();
    final valider = find.byKey(const ValueKey('encaissement-valider'));
    await t.ensureVisible(valider);
    await t.pump();
    await t.tap(valider);
    await app.attendre(t, const Duration(seconds: 4));
    expect(tickets(), 0, reason: 'clôture pas encore confirmée : aucun ticket');
    expect(_pause, findsNothing);
    expect(await app.attendreQue(t, _pause, max: const Duration(seconds: 5)), isTrue);
    expect(tickets(), 1);
    expect(find.text('Ticket suivant (2/2)'), findsOneWidget);

    final avant = app.serveur.recues.length;
    await app.serveur.couper();
    await app.attendre(t, const Duration(seconds: 3));
    await t.tap(find.byKey(const ValueKey('ticket-suivant-imprimer')));
    await app.attendre(t);
    expect(tickets(), 2, reason: 'copie imprimée sans le serveur');
    expect(_pause, findsNothing);
    expect(c.clotures, 1, reason: 'une seule clôture');
    expect(app.serveur.recuesSur('/vente/cloturer/vno'), hasLength(1));
    expect(app.serveur.recues.length - avant, lessThanOrEqualTo(1), reason: 'aucune requête de vente entre les copies (au plus la surveillance)');
    await app.serveur.retablir();
    await app.fermer(t);
  });
}
