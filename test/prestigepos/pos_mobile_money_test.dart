// PrestigePOS 1.8.2 — état du Mobile Money (retour du pharmacien du 31/10, accord du 31/10), application ENTIÈRE
// contre le faux serveur en mémoire :
//  - Administration › « Paiement mobile money » : option et ligne d'état (mêmes conditions que la borne : serveur
//    sans module, aucun compte de paiement, utilisateur borne sans droit de clôture → compte nommé, proposé,
//    injoignable) ; capacités relues à l'ouverture et par « Vérifier à nouveau » ; option décochée enregistrée ;
//  - assistant, étape « Présentation » : ligne d'état sous l'option, revérifiée au changement ;
//  - écran CLIENT de la borne : aucun de ces messages ; vente inchangée (« Payer en caisse », mobile money proposé
//    seulement si tout est réuni) ;
//  - Sunmi V2s, texte ×1,3 : ligne lisible, aucun débordement.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/prestigepos/pos_reglages.dart';

import 'outils/pos_e2e.dart';
import 'pos_e2e_test.dart' show attendreBorne, tablettePortrait;

const _ok = {'success': true, 'paiementsMobile': ['orange', 'wave'], 'fournisseur': 'cinetpay'};
const _vide = {'success': true, 'paiementsMobile': <String>[], 'paiementsMobileVersion': 0, 'fournisseur': null};
const _cloture = ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE'];

PosE2E _app({Map<String, dynamic>? capacites, List<String> droitsBorne = _cloture}) {
  final app = PosE2E();
  if (capacites != null) app.serveur.routes['GET /paiements-mobile/capacites'] = (_) => FauxServeurPrestige.ok(capacites);
  app.serveur.droitsComptes = {loginBorne: droitsBorne};
  return app;
}

int _capacites(PosE2E app) => app.serveur.recues.where((r) => r.chemin.endsWith('/paiements-mobile/capacites')).length;

String _etat(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('pos-mobile-money-etat'))).textSpan!.toPlainText();

Future<void> _pageAdmin(WidgetTester t, PosE2E app) async {
  await app.quitterBorne(t);
  final entree = find.byKey(const ValueKey('pos-admin-mobile-money'));
  if (entree.evaluate().isEmpty) await t.scrollUntilVisible(entree, 200, scrollable: find.byType(Scrollable).first);
  await app.toucher(t, 'pos-admin-mobile-money');
  expect(await app.attendreQue(t, find.byKey(const ValueKey('pos-mobile-money-etat'))), isTrue);
}

void main() {
  setUp(() {
    DroitsVente.instance.oublier();
    UtilisateurSession.id = null;
  });

  for (final (nom, cap, droits, attendu) in [
    ('serveur sans module (404)', null, _cloture, 'Serveur sans module Mobile Money (version ancienne).'),
    ('aucun compte de paiement', _vide, _cloture, 'n\'a pas de compte de paiement configuré (agrégateur)'),
    ('utilisateur borne sans droit de clôture', _ok, const ['P_SM_VENTE'], 'le compte de la borne « $loginBorne » n\'a pas le droit de clôturer'),
    ('tout bon', _ok, _cloture, 'Proposé au client : Orange Money, Wave.'),
  ]) {
    testWidgets('Administration › Paiement mobile money : $nom', (t) async {
      tablettePortrait(t);
      final app = _app(capacites: cap, droitsBorne: droits);
      await app.preparer(configure: true);
      await app.lancer(t);
      await attendreBorne(t, app);
      expect(find.textContaining('Mobile Money activé'), findsNothing, reason: 'jamais sur l\'écran client');
      await _pageAdmin(t, app);
      expect(_etat(t), contains(attendu));
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }

  testWidgets('capacités relues (« Vérifier à nouveau ») ; serveur coupé : injoignable ; option décochée enregistrée', (t) async {
    tablettePortrait(t);
    final app = _app(capacites: _vide);
    await app.preparer(configure: true);
    await app.lancer(t);
    await attendreBorne(t, app);
    await _pageAdmin(t, app);
    expect(_etat(t), contains('pas de compte de paiement'));
    final n = _capacites(app);
    app.serveur.routes['GET /paiements-mobile/capacites'] = (_) => FauxServeurPrestige.ok(_ok);
    await app.toucher(t, 'pos-mobile-money-verifier');
    await app.attendre(t, const Duration(seconds: 2));
    expect(_capacites(app), greaterThan(n));
    expect(_etat(t), contains('Proposé au client'));
    await app.serveur.couper();
    await app.toucher(t, 'pos-mobile-money-verifier');
    await app.attendre(t, const Duration(seconds: 20));
    expect(_etat(t), 'Borne : Serveur injoignable : impossible de vérifier.');
    await app.serveur.retablir();
    await app.toucher(t, 'pos-mobile-money');
    await app.attendre(t, const Duration(seconds: 2));
    expect(PosReglages.courant.value.mobileMoney, isFalse);
    expect(PaiementsMobileReglages.actif.value, isFalse);
    expect(find.byKey(const ValueKey('pos-mobile-money-etat')), findsNothing);
    await app.fermer(t);
  });

  testWidgets('assistant, étape Présentation : ligne d\'état sous l\'option, revérifiée au changement', (t) async {
    tablettePortrait(t);
    final app = _app(capacites: _ok, droitsBorne: const ['P_SM_VENTE']);
    await app.preparer(configure: true);
    await app.lancer(t);
    await attendreBorne(t, app);
    await app.quitterBorne(t);
    await app.toucher(t, 'pos-admin-assistant');
    await app.saisir(t, 'pos-serveur-adresse', FauxServeurPrestige.hoteMemoire);
    await app.saisir(t, 'pos-serveur-port', FauxServeurPrestige.portMemoire);
    await app.toucher(t, 'pos-serveur-verifier');
    await app.attendre(t);
    await app.saisir(t, 'pos-borne-login', loginBorne);
    await app.saisir(t, 'pos-borne-mdp', mdpBorne);
    FocusManager.instance.primaryFocus?.unfocus();
    await app.toucher(t, 'pos-suivant');
    await app.attendre(t);
    expect(await app.attendreQue(t, find.byKey(const ValueKey('pos-mobile-money-etat'))), isTrue);
    expect(_etat(t), contains('n\'a pas le droit de clôturer'));
    await app.toucher(t, 'pos-mobile-money');
    await app.attendre(t);
    expect(find.byKey(const ValueKey('pos-mobile-money-etat')), findsNothing, reason: 'option décochée : aucune ligne');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('Sunmi V2s, texte ×1,3 : ligne longue lisible, aucun débordement', (t) async {
    t.view.physicalSize = const Size(720, 1440);
    t.view.devicePixelRatio = 2;
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final app = _app(capacites: _vide, droitsBorne: const ['P_SM_VENTE']);
    await app.preparer(configure: true);
    await app.lancer(t);
    await attendreBorne(t, app);
    await _pageAdmin(t, app);
    expect(_etat(t), contains('pas le droit de clôturer'), reason: 'les deux obstacles');
    final r = t.getRect(find.byKey(const ValueKey('pos-mobile-money-etat')));
    expect(r.right, lessThanOrEqualTo(t.view.physicalSize.width / t.view.devicePixelRatio + 0.5));
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
