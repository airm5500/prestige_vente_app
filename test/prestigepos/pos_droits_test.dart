// PrestigePOS 1.3.1 — sécurité des ventes (Prestige Mobile 4.5.1, demande du serveur du 19/10/2026), application
// ENTIÈRE contre le faux serveur Prestige en mémoire (données fictives) :
//  - droits de l'utilisateur borne lus à la connexion de la borne (GET v1/user/droits), en-tête X-Prestige-Utilisateur ;
//  - sans droit de clôture : « PAYER PAR MOBILE MONEY » non proposé, seul le ticket pour la caisse ;
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

PosE2E _app({required List<String> droitsBorne, bool refuserPaiement = false}) {
  final app = PosE2E();
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

  testWidgets('utilisateur borne sans droit de clôture : droits lus avec son en-tête, mobile money non proposé', (t) async {
    tablettePortrait(t);
    final app = _app(droitsBorne: ['P_SM_VENTE']);
    await app.preparer(configure: true, prefs: {'paiements_mobile_actif_v1': true});
    await app.lancer(t);
    await attendreBorne(t, app);
    final lus = app.serveur.recuesSur('/user/droits');
    expect(lus, isNotEmpty);
    expect(lus.last.utilisateur, 'U-$loginBorne');
    expect(DroitsVente.instance.cloturerPaiementMobile, isFalse);
    await _panier(t, app);
    expect(find.byKey(const ValueKey('borne-payer')), findsOneWidget);
    expect(find.byKey(const ValueKey('borne-payer-mobile')), findsNothing);
    expect(t.takeException(), isNull);
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
