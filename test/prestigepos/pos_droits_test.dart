// PrestigePOS 1.3.1 — sécurité des ventes (Prestige Mobile 4.5.1, demande du serveur du 19/10/2026), application
// ENTIÈRE contre le faux serveur Prestige en mémoire (données fictives) :
//  - droits de l'utilisateur borne lus à la connexion de la borne (GET v1/user/droits), en-tête X-Prestige-Utilisateur ;
//  - 1.11.1 (retour du pharmacien du 15/11) : compte borne au profil prévente → mobile money avec cloturer:false ;
//    1.13.2 (Prestige Mobile 4.15.2, demande 64, règle du pharmacien du 19/11 : « s'il paye par mobile money la vente
//    est validée ») : sans droit de clôture, « PAYER PAR MOBILE MONEY » n'est PLUS proposé ; jamais cloturer:false ;
//    avec le droit : cloturer:true (inchangé) ; caisse de la borne fermée sur un serveur avec la demande 64 → refus
//    avant paiement, ticket de prévente, « payez à la caisse » ;
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

/// Faux module de paiement, règles de la branche serveur de la demande 62 : `cloturer:true` accepté avec « Terminer une
/// vente » ou (si [d62]) P_BORNE_PAIEMENT_MOBILE, sinon 403 avant toute création ; clôture automatique faite à la
/// confirmation seulement si la caisse du compte de la borne est ouverte ([caisseOuverte]).
PosE2E _app({required List<String> droitsBorne, bool refuserPaiement = false, bool paye = false, bool d62 = false, bool caisseOuverte = true, bool d64 = false}) {
  final app = PosE2E();
  var auto = false;
  app.serveur.routes['GET /paiements-mobile/PM1'] = (_) => FauxServeurPrestige.ok({
        'success': true,
        'data': {
          'id': 'PM1',
          'venteId': 'V-1',
          'reference': 'R',
          'montant': 1500,
          'operateur': 'wave',
          'statut': paye ? 'paye' : 'en_attente',
          'lien': '',
          'clotureAuto': auto,
          'cloture': paye && auto && caisseOuverte,
          'message': paye && auto && !caisseOuverte ? 'Clôture refusée : Votre caisse est fermée' : '',
        }
      });
  app.serveur.droitsComptes = {loginBorne: droitsBorne};
  app.serveur.routes['GET /paiements-mobile/capacites'] =
      (_) => FauxServeurPrestige.ok({'success': true, 'paiementsMobile': ['wave'], 'fournisseur': 'simulateur'});
  app.serveur.routes['POST /paiements-mobile'] = (r) {
    final cloturer = r.json['cloturer'] == true;
    final droit = droitsBorne.any(DroitsVente.terminerVenteDroits.contains) || (d62 && droitsBorne.contains(DroitsVente.bornePaiementMobileDroit));
    if (refuserPaiement || (cloturer && !droit)) return FauxServeurPrestige.interdit('Droit manquant : terminer une vente.');
    // Demande 64 : contrôles de la clôture AVANT toute création (caisse du compte de la borne fermée → refus, champ message).
    if (d64 && cloturer && !caisseOuverte) {
      return FauxServeurPrestige.ok({
        'success': false,
        'message': 'Paiement mobile money impossible : la caisse de la borne est fermée. Le client paie à la caisse.'
      });
    }
    auto = cloturer;
    return FauxServeurPrestige.ok({
      'success': true,
      'data': {'id': 'PM1', 'venteId': 'V-1', 'reference': 'R', 'montant': 1500, 'operateur': 'wave', 'statut': 'EN_ATTENTE', 'lien': 'simulateur://PM1', 'clotureAuto': cloturer}
    });
  };
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

  testWidgets('profil prévente + option active : 1.13.2, mobile money NON proposé (plus de cloturer:false), payer en caisse', (t) async {
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
    expect(find.byKey(const ValueKey('borne-payer-mobile')), findsNothing,
        reason: 'règle du pharmacien du 19/11 : payer à la borne termine la vente ; sans droit de clôture, pas de paiement');
    expect(app.serveur.recues.where((r) => r.methode == 'POST' && r.chemin.endsWith('/paiements-mobile')), isEmpty);
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
    expect(app.ticketsTexte().last, isNot(contains('PAYEE, presentez')), reason: 'vente terminée par le serveur');
    await app.fermer(t);
  });

  // 1.13.0 (demande 62) : droit P_BORNE_PAIEMENT_MOBILE du compte de la borne (serveur correctif/demande62-1911).
  testWidgets('demande 62, cas du pharmacien : droit de la borne + caisse ouverte → cloturer:true, vente terminée', (t) async {
    tablettePortrait(t);
    final app = _app(droitsBorne: ['P_SM_VENTE', 'P_BORNE_PAIEMENT_MOBILE'], paye: true, d62: true);
    await app.preparer(configure: true, prefs: {'paiements_mobile_actif_v1': true});
    await app.lancer(t);
    await attendreBorne(t, app);
    expect((DroitsVente.instance.cloturerPaiementMobile, DroitsVente.instance.terminerVente), (true, false));
    await _panier(t, app);
    await app.toucher(t, 'borne-payer-mobile');
    await app.toucher(t, 'borne-operateur-wave');
    expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-numero'))), isTrue);
    expect(app.serveur.recues.where((r) => r.methode == 'POST' && r.chemin.endsWith('/paiements-mobile')).single.json['cloturer'], isTrue);
    expect(app.ticketsTexte().last, isNot(contains('PAYEE, presentez')));
    expect(find.byKey(const ValueKey('remise-vente-zone')), findsNothing);
    await app.fermer(t);
  });

  testWidgets('demande 62 : droit de la borne SANS caisse ouverte → payé, non clôturé, ticket PAYÉE', (t) async {
    tablettePortrait(t);
    final app = _app(droitsBorne: ['P_SM_VENTE', 'P_BORNE_PAIEMENT_MOBILE'], paye: true, d62: true, caisseOuverte: false);
    await app.preparer(configure: true, prefs: {'paiements_mobile_actif_v1': true});
    await app.lancer(t);
    await attendreBorne(t, app);
    await _panier(t, app);
    await app.toucher(t, 'borne-payer-mobile');
    await app.toucher(t, 'borne-operateur-wave');
    expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-numero'))), isTrue);
    expect(app.ticketsTexte().last, contains('PAYEE, presentez ce ticket a la caisse'));
    await app.fermer(t);
  });

  // 1.13.2 (demande 64) : sur un serveur avec la demande 64, la caisse fermée est refusée AVANT tout paiement.
  testWidgets('demande 64 : droit de la borne, caisse fermée → refus avant paiement, aucun QR, ticket de prévente', (t) async {
    tablettePortrait(t);
    final app = _app(droitsBorne: ['P_SM_VENTE', 'P_BORNE_PAIEMENT_MOBILE'], paye: true, d62: true, d64: true, caisseOuverte: false);
    await app.preparer(configure: true, prefs: {'paiements_mobile_actif_v1': true});
    await app.lancer(t);
    await attendreBorne(t, app);
    await _panier(t, app);
    await app.toucher(t, 'borne-payer-mobile');
    await app.toucher(t, 'borne-operateur-wave');
    expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-numero'))), isTrue);
    expect(find.byKey(const ValueKey('pm-qr')), findsNothing);
    expect(find.text(BorneScreen.avisMobileIndisponible), findsOneWidget);
    final demandes = app.serveur.recues.where((r) => r.methode == 'POST' && r.chemin.endsWith('/paiements-mobile')).toList();
    expect(demandes.map((r) => r.json['cloturer']), [true], reason: 'une seule demande, jamais cloturer:false');
    expect(app.serveur.recues.where((r) => r.chemin.endsWith('/paiements-mobile/PM1')), isEmpty, reason: 'aucun paiement à suivre');
    final ticket = app.ticketsTexte().last;
    expect(ticket, isNot(contains('PAYEE')), reason: 'ticket de PRÉVENTE pour la caisse');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('demande 62 : droit retiré sur le serveur (403 à cloturer:true) → 1.13.2 : aucune demande cloturer:false, ticket de prévente', (t) async {
    tablettePortrait(t);
    final app = _app(droitsBorne: ['P_SM_VENTE', 'P_BORNE_PAIEMENT_MOBILE'], paye: true);
    await app.preparer(configure: true, prefs: {'paiements_mobile_actif_v1': true});
    await app.lancer(t);
    await attendreBorne(t, app);
    await _panier(t, app);
    await app.toucher(t, 'borne-payer-mobile');
    await app.toucher(t, 'borne-operateur-wave');
    expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-numero'))), isTrue);
    final demandes = app.serveur.recues.where((r) => r.methode == 'POST' && r.chemin.endsWith('/paiements-mobile')).toList();
    expect(demandes.map((r) => r.json['cloturer']), [true]);
    expect(find.text(BorneScreen.avisMobileIndisponible), findsOneWidget);
    expect(app.ticketsTexte().last, isNot(contains('PAYEE')));
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
