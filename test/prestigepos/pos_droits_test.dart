// PrestigePOS 1.3.1 — sécurité des ventes (Prestige Mobile 4.5.1, demande du serveur du 19/10/2026), application
// ENTIÈRE contre le faux serveur Prestige en mémoire (données fictives) :
//  - droits de l'utilisateur borne lus à la connexion de la borne (GET v1/user/droits), en-tête X-Prestige-Utilisateur ;
//  - 1.11.1 (retour du pharmacien du 15/11) : compte borne au PROFIL PRÉVENTE + option « Proposer le paiement mobile
//    money » active → « PAYER PAR MOBILE MONEY » visible ; paiement créé avec cloturer:false ; payé → ticket
//    « VENTE BORNE - PAYEE » imprimé, « présentez ce ticket à la caisse, qui termine la vente » ; avec le droit :
//    cloturer:true (inchangé) ;
//  - 403 interdit pendant le paiement mobile : « Paiement mobile indisponible, rendez-vous à la caisse avec votre
//    ticket », ticket de prévente imprimé (Bluetooth), une seule demande, borne toujours connectée ;
//  - 409 « session changée » branché sur le redémarrage de PrestigePOS.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';
import 'package:prestige_vente_app/borne/borne_screen.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';

import 'outils/pos_e2e.dart';
import 'pos_e2e_test.dart' show attendreBorne, tablettePortrait;

PosE2E _app({required List<String> droitsBorne, bool refuserPaiement = false, bool paye = false}) {
  final app = PosE2E();
  app.serveur.routes['GET /paiements-mobile/PM1'] = (_) => FauxServeurPrestige.ok({
        'success': true,
        'data': {'id': 'PM1', 'venteId': 'V-1', 'reference': 'R', 'montant': 1500, 'operateur': 'wave', 'statut': paye ? 'paye' : 'en_attente', 'lien': ''}
      });
  app.serveur.droitsComptes = {loginBorne: droitsBorne};
  app.serveur.routes['GET /paiements-mobile/capacites'] =
      (_) => FauxServeurPrestige.ok({'success': true, 'paiementsMobile': ['wave'], 'fournisseur': 'simulateur'});
  app.serveur.routes['POST /paiements-mobile'] = (_) => refuserPaiement
      ? FauxServeurPrestige.interdit('Droit manquant : terminer une vente.')
      : FauxServeurPrestige.ok({
          'success': true,
          'data': {'id': 'PM1', 'venteId': 'V-1', 'reference': 'R', 'montant': 1500, 'operateur': 'wave', 'statut': 'EN_ATTENTE', 'lien': 'simulateur://PM1'}
        });
  return app;
}

Future<void> _panier(WidgetTester t, PosE2E app) async {
  await app.chercher(t, 'doli');
  await app.toucher(t, 'borne-ajouter-F1');
  await app.attendre(t, const Duration(milliseconds: 2600));
  await app.toucher(t, 'borne-voir-panier');
}

void main() {
  setUp(() {
    DroitsVente.instance.oublier();
    UtilisateurSession.id = null;
  });

  testWidgets('cas du pharmacien (15/11) : profil prévente + option active → mobile money visible, cloturer:false, ticket PAYÉE', (t) async {
    tablettePortrait(t);
    final app = _app(droitsBorne: ['P_SM_VENTE'], paye: true);
    await app.preparer(configure: true, prefs: {'paiements_mobile_actif_v1': true});
    await app.lancer(t);
    await attendreBorne(t, app);
    final lus = app.serveur.recuesSur('/user/droits');
    expect(lus, isNotEmpty);
    expect(lus.last.utilisateur, 'U-$loginBorne');
    expect(DroitsVente.instance.cloturerPaiementMobile, isFalse);
    await _panier(t, app);
    expect(find.byKey(const ValueKey('borne-payer')), findsOneWidget);
    expect(find.byKey(const ValueKey('borne-payer-mobile')), findsOneWidget, reason: 'bogue du 15/11 : le bouton doit être visible');
    await app.toucher(t, 'borne-payer-mobile');
    await app.toucher(t, 'borne-operateur-wave');
    expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-numero'))), isTrue, reason: 'payé → ticket');
    final demande = app.serveur.recues.where((r) => r.methode == 'POST' && r.chemin.endsWith('/paiements-mobile')).single;
    expect(demande.json['cloturer'], isFalse, reason: 'sans le droit : jamais cloturer:true (403 du serveur)');
    final ticket = app.ticketsTexte().last;
    expect(ticket, contains('VENTE BORNE - PAYEE'));
    expect(ticket, contains('PAYE PAR WAVE'));
    expect(ticket, contains('la caisse, qui termine la vente'));
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('avec le droit de clôture : cloturer:true (inchangé)', (t) async {
    tablettePortrait(t);
    final app = _app(droitsBorne: ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE'], paye: true);
    await app.preparer(configure: true, prefs: {'paiements_mobile_actif_v1': true});
    await app.lancer(t);
    await attendreBorne(t, app);
    await _panier(t, app);
    await app.toucher(t, 'borne-payer-mobile');
    await app.toucher(t, 'borne-operateur-wave');
    expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-numero'))), isTrue);
    expect(app.serveur.recues.where((r) => r.methode == 'POST' && r.chemin.endsWith('/paiements-mobile')).single.json['cloturer'], isTrue);
    expect(app.ticketsTexte().last, isNot(contains('qui termine la vente')));
    await app.fermer(t);
  });

  testWidgets('option « Proposer le paiement mobile money » désactivée : « Payer en caisse » seul', (t) async {
    tablettePortrait(t);
    final app = _app(droitsBorne: ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE']);
    await app.preparer(configure: true, prefs: {'prestigepos_mobile_money_v1': false});
    await app.lancer(t);
    await attendreBorne(t, app);
    await _panier(t, app);
    expect(find.byKey(const ValueKey('borne-payer-mobile')), findsNothing);
    await app.fermer(t);
  });

  testWidgets('403 interdit pendant le paiement mobile : message, ticket de prévente imprimé, borne connectée', (t) async {
    tablettePortrait(t);
    final app = _app(droitsBorne: ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE'], refuserPaiement: true);
    await app.preparer(configure: true, prefs: {'paiements_mobile_actif_v1': true});
    await app.lancer(t);
    await attendreBorne(t, app);
    await _panier(t, app);
    await app.toucher(t, 'borne-payer-mobile');
    await app.toucher(t, 'borne-operateur-wave');
    await app.attendre(t, const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('borne-avis-ticket')), findsOneWidget);
    expect(find.text(BorneScreen.avisMobileIndisponible), findsOneWidget);
    expect(find.byKey(const ValueKey('borne-numero')), findsOneWidget);
    expect(app.pont.envois, isNotEmpty, reason: 'ticket de prévente imprimé pour la caisse');
    await app.attendre(t, const Duration(seconds: 5));
    expect(app.serveur.recues.where((r) => r.methode == 'POST' && r.chemin.endsWith('/paiements-mobile')), hasLength(1),
        reason: 'aucune nouvelle tentative');
    expect(app.serveur.connexions, 1, reason: 'borne toujours connectée');
    expect(app.serveur.recuesSur('/user/logout'), isEmpty);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  test('409 « session changée » branché sur le redémarrage de PrestigePOS', () {
    final s = File('lib/prestigepos/pos_app.dart').readAsStringSync();
    expect(s, contains('brancherChangementUtilisateur(auth, accueil: () => const PosDemarrage());'));
  });
}
