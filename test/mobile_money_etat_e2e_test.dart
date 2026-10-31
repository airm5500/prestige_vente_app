// E2E — Prestige Mobile 4.10.2 : Réglages › Paiements mobile money, ligne d'état sous l'option (retour du pharmacien
// du 31/10), application ENTIÈRE contre le faux serveur Prestige en mémoire, Sunmi V2s :
//  - encaissement sur cet appareil (compte connecté) : serveur sans module (404), aucun compte de paiement (liste
//    vide), compte sans droit de clôture, tout bon (« Proposé au client : … »), serveur coupé ;
//  - borne libre-service configurée (utilisateur borne, connexion d'essai à part) : sans droit de clôture → compte de
//    la borne nommé ; droit présent → proposé ;
//  - capacités relues à chaque ouverture et « Vérifier à nouveau » ;
//  - « Tester la borne » : étape « Module Mobile Money ».
// Données FICTIVES.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/parametres/parametres_logic.dart';
import 'package:prestige_vente_app/services/pin_securise.dart';

import 'outils/app_e2e.dart';

const _borne = 'borne.e2e';
const _mdpBorne = 'MotDePasseBorneFictif1';

class _Code extends CodeAdmin {
  @override
  Future<Duration?> attenteRestante() async => null;
  @override
  Future<VerificationPin> verifier(String saisie) async => saisie == '4827' ? VerificationPin.accepte : VerificationPin.refuse;
}

int _capacites(AppE2E app) => app.serveur.recues.where((r) => r.chemin.endsWith('/paiements-mobile/capacites')).length;

Future<AppE2E> _ouvrir(WidgetTester t, {Object? capacites, List<String>? droitsCompte, List<String>? droitsBorne, bool borne = false}) async {
  TailleEcran.sunmiV2s.appliquer(t);
  final avant = CodeAdmin.instance;
  CodeAdmin.instance = _Code();
  addTearDown(() => CodeAdmin.instance = avant);
  final secretsAvant = BorneReglages.secrets;
  BorneReglages.secrets = MemoireBorneSecrets(borne ? _mdpBorne : null);
  addTearDown(() {
    BorneReglages.secrets = secretsAvant;
    BorneReglages.courant.value = const BorneConfig();
  });
  final app = AppE2E(serveur: FauxServeurPrestige(comptes: {DonneesFictives.login: DonneesFictives.motDePasse, _borne: _mdpBorne}));
  if (capacites != null) app.serveur.routes['GET /paiements-mobile/capacites'] = (_) => FauxServeurPrestige.ok(capacites as Map<String, dynamic>);
  app.serveur.droitsComptes = {
    if (droitsCompte != null) DonneesFictives.login: droitsCompte,
    if (droitsBorne != null) _borne: droitsBorne,
  };
  await app.preparer(prefs: {
    'paiements_mobile_actif_v1': true,
    if (borne) 'borne_config_v1': jsonEncode(const BorneConfig(login: _borne).toJson()),
  });
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await t.tap(find.text('Réglages'));
  await app.attendre(t);
  final rub = find.byKey(Key('rubrique_${Rubrique.paiementsMobile.name}'));
  await app.defilerJusqua(t, rub);
  await t.tap(rub);
  await app.attendre(t, const Duration(seconds: 1));
  await t.enterText(find.byKey(const Key('pin_admin_saisie')), '4827');
  await t.tap(find.text('Valider'));
  await app.attendre(t, const Duration(seconds: 2));
  return app;
}

String _texte(WidgetTester t, String cle) {
  final w = t.widget<Text>(find.byKey(ValueKey(cle)));
  return w.textSpan!.toPlainText();
}

void main() {
  const ok = {'success': true, 'paiementsMobile': ['orange', 'wave'], 'fournisseur': 'cinetpay'};
  const vide = {'success': true, 'paiementsMobile': <String>[], 'paiementsMobileVersion': 0, 'fournisseur': null};
  const cloture = ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE'];

  testWidgets('serveur sans module (404) : « Serveur sans module Mobile Money (version ancienne) »', (t) async {
    final app = await _ouvrir(t);
    expect(_texte(t, 'pm-etat-appareil'), contains('Serveur sans module Mobile Money (version ancienne).'));
    expect(find.byKey(const ValueKey('pm-etat-borne')), findsNothing, reason: 'borne non configurée');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('aucun compte de paiement sur le serveur : message, capacités relues par « Vérifier à nouveau »', (t) async {
    final app = await _ouvrir(t, capacites: vide, droitsCompte: cloture);
    expect(_texte(t, 'pm-etat-appareil'), contains('n\'a pas de compte de paiement configuré (agrégateur)'));
    final n = _capacites(app);
    app.serveur.routes['GET /paiements-mobile/capacites'] = (_) => FauxServeurPrestige.ok(ok);
    await t.tap(find.byKey(const ValueKey('pm-verifier')));
    await app.attendre(t, const Duration(seconds: 2));
    expect(_capacites(app), greaterThan(n), reason: 'capacités relues');
    expect(_texte(t, 'pm-etat-appareil'), contains('Proposé au client : Orange Money, Wave.'));
    await app.fermer(t);
  });

  testWidgets('compte connecté sans droit de clôture : compte nommé, droits à donner', (t) async {
    final app = await _ouvrir(t, capacites: ok, droitsCompte: const ['P_SM_VENTE']);
    expect(_texte(t, 'pm-etat-appareil'),
        contains('mais le compte « ${DonneesFictives.login} » n\'a pas le droit de clôturer : donnez-lui P_SM_CLOTURER_CAISSE'));
    await app.fermer(t);
  });

  testWidgets('borne configurée : utilisateur borne sans droit → compte de la borne nommé ; avec le droit → proposé', (t) async {
    final app = await _ouvrir(t, capacites: ok, droitsCompte: cloture, droitsBorne: const ['P_SM_VENTE'], borne: true);
    expect(_texte(t, 'pm-etat-appareil'), contains('Proposé au client'));
    expect(_texte(t, 'pm-etat-borne'), contains('le compte de la borne « $_borne » n\'a pas le droit de clôturer'));
    expect(app.serveur.recuesSur('/user/logout'), isNotEmpty, reason: 'session d\'essai de la borne fermée');
    app.serveur.droitsComptes = {DonneesFictives.login: cloture, _borne: cloture};
    await t.tap(find.byKey(const ValueKey('pm-verifier')));
    await app.attendre(t, const Duration(seconds: 3));
    expect(_texte(t, 'pm-etat-borne'), contains('Proposé au client : Orange Money, Wave.'));
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('serveur coupé : « Serveur injoignable : impossible de vérifier »', (t) async {
    final app = await _ouvrir(t, capacites: ok, droitsCompte: cloture);
    await app.serveur.couper();
    await t.tap(find.byKey(const ValueKey('pm-verifier')));
    await app.attendre(t, const Duration(seconds: 12));
    expect(_texte(t, 'pm-etat-appareil'), contains('Serveur injoignable : impossible de vérifier.'));
    await app.serveur.retablir();
    await app.fermer(t);
  });

  testWidgets('option décochée : aucune ligne d\'état, aucune requête de capacités', (t) async {
    final app = await _ouvrir(t, capacites: ok, droitsCompte: cloture);
    await t.tap(find.byKey(const ValueKey('pm-actif')));
    await app.attendre(t);
    final n = _capacites(app);
    expect(find.byKey(const ValueKey('pm-etat-appareil')), findsNothing);
    await app.attendre(t);
    expect(_capacites(app), n);
    await app.fermer(t);
  });

  // Ergonomie : Sunmi V2s, texte ×1,3, deux lignes d'état longues (aucun compte de paiement + droit manquant).
  testWidgets('Sunmi V2s, texte ×1,3 : lignes d\'état longues lisibles, aucun débordement', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final app = await _ouvrir(t, capacites: vide, droitsCompte: const ['P_SM_VENTE'], droitsBorne: const ['P_SM_VENTE'], borne: true);
    expect(_texte(t, 'pm-etat-appareil'), contains('pas le droit de clôturer'), reason: 'les deux obstacles');
    final ecran = t.view.physicalSize / t.view.devicePixelRatio;
    for (final cle in ['pm-etat-appareil', 'pm-etat-borne']) {
      final r = t.getRect(find.byKey(ValueKey(cle)));
      expect(r.right, lessThanOrEqualTo(ecran.width + 0.5), reason: cle);
    }
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
