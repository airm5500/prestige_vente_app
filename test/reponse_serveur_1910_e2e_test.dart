// 4.6.0 — e2e, application entière (faux serveur Prestige en mémoire, données fictives) : réponse du serveur du
// 19/10/2026.
//  - BL refusé avec liste : PUT commande/validerbl → PRODUITS_NON_SAISIS, liste des produits affichée (Sunmi V2s) ;
//  - « Mon pointage » sans seconde connexion : v1/rh/moi sous la session, jeton v1/mobile gardé effacé, pointage reçu
//    pour le compte de la session ;
//  - compte avec P_RH_POINTER seul (gerer:false) : terminal ouvert, employés aux champs réduits, aucune gestion
//    (présences, photos, empreintes) même pour l'administrateur de l'application ; témoin avec gerer:true.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/rh/mobile_pointage_screen.dart';
import 'package:prestige_vente_app/rh/terminal_pointage_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';

const _cleJeton = 'prestige_rh_session_mobile_v1';

void main() {
  testWidgets('BL refusé : « Entrée en stock refusée », produits non saisis listés et défilables (Sunmi V2s)', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = AppE2E();
    final s = app.serveur;
    final produits = [for (var i = 1; i <= 12; i++) '340093000${i.toString().padLeft(4, '0')} PRODUIT FICTIF $i CP B/30 (${i % 3}/${i + 2})'];
    var validations = 0;
    s.routes['GET /commande/list-bons'] = (_) => FauxServeurPrestige.ok({
          'data': [
            {'lg_BON_LIVRAISON_ID': 'BL1', 'str_REF_LIVRAISON': 'BL-901', 'str_GROSSISTE_LIBELLE': 'GROSSISTE FICTIF', 'DISPLAYFILTER': true, 'int_NBRE_LIGNE_BL_DETAIL': 12}
          ],
          'total': 1
        });
    s.routes['GET /commande/list'] = (_) => FauxServeurPrestige.ok({'data': [], 'total': 0});
    s.routes['GET /commande/list/passees'] = (_) => FauxServeurPrestige.ok({'data': [], 'total': 0});
    s.routes['GET /commande/bon/items/BL1'] = (_) => FauxServeurPrestige.ok({
          'data': [
            for (var i = 1; i <= 12; i++)
              {
                'lg_BON_LIVRAISON_DETAIL': 'D$i',
                'lg_FAMILLE_ID': 'F$i',
                'lg_FAMILLE_NAME': 'PRODUIT FICTIF $i CP B/30',
                'lg_FAMILLE_CIP': '340093000${i.toString().padLeft(4, '0')}',
                'int_QTE_CMDE': i + 2,
                'quantiteSaisie': 0,
                'str_REF_LIVRAISON': 'BL-901',
              }
          ],
          'total': 12
        });
    s.routes['GET /commande/entree-stock/autorisation'] = (_) => FauxServeurPrestige.ok({'authorize': true});
    s.routes['PUT /commande/validerbl/BL1'] = (_) {
      validations++;
      return FauxServeurPrestige.ok({'success': false, 'code': 'PRODUITS_NON_SAISIS', 'produits': produits, 'msg': 'Produits non saisis : ${produits.join(', ')}'});
    };
    await app.preparer(prefs: {
      'hiddenMenuIds': <String>[],
      'reception_bl_settings_v1': jsonEncode({'terminalValidation': true, 'shortExpiryMonths': 6}),
    });
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'reception_bl');
    await app.attendre(t);
    final onglet = find.textContaining('BL à entrer ·');
    if (onglet.evaluate().isNotEmpty) {
      await t.tap(onglet.first);
      await app.attendre(t);
    }
    await app.defilerJusqua(t, find.text('BL BL-901'));
    final ouvrir = find.text('Commencer la saisie');
    await app.defilerJusqua(t, ouvrir);
    await t.tap(ouvrir.first);
    await app.attendre(t);
    final terminer = find.text('Terminer et vérifier');
    expect(await app.attendreQue(t, terminer), isTrue);
    await t.ensureVisible(terminer);
    await t.tap(terminer);
    await app.attendre(t);
    final valider = find.text('Valider l\'entrée en stock');
    await app.defilerJusqua(t, valider);
    await t.tap(valider);
    await app.attendre(t, const Duration(seconds: 1));
    await t.tap(find.widgetWithText(ElevatedButton, 'Valider'));
    await app.attendre(t);
    expect(validations, 1);
    expect(find.byKey(const Key('bl_produits_non_saisis')), findsOneWidget);
    expect(find.text('Entrée en stock refusée'), findsOneWidget);
    expect(find.text('12 produits non saisis : saisissez leurs lots puis validez à nouveau.'), findsOneWidget);
    expect(find.text(produits.first), findsOneWidget);
    await t.scrollUntilVisible(find.text(produits.last), 150,
        scrollable: find.descendant(of: find.byKey(const Key('bl_produits_non_saisis_liste')), matching: find.byType(Scrollable)));
    expect(find.text(produits.last), findsOneWidget);
    expect(t.takeException(), isNull, reason: 'aucun débordement sur le petit écran');
    await t.tap(find.text('OK'));
    await app.attendre(t);
    expect(find.text('Entrée en stock effectuée'), findsNothing);
    expect(s.recuesSur('/user/logout'), isEmpty);
    await app.fermer(t);
  });

  testWidgets('« Mon pointage » sans seconde connexion : session de l\'application, jeton effacé, pointage pour ce compte', (t) async {
    TailleEcran.telephone360x800.appliquer(t);
    final app = AppE2E()
      ..serveur.activerPointageMobile({DonneesFictives.login: 'TEST Awa'})
      ..serveur.activerPointageSession({DonneesFictives.login: 'TEST Awa'});
    await app.preparer(prefs: const {'hiddenMenuIds': <String>[]});
    // Un ancien jeton v1/mobile du même compte reste sur le téléphone.
    FlutterSecureStorage.setMockInitialValues({
      _cleJeton: jsonEncode({
        'jeton': 'JETON-ANCIEN',
        'expiration': '2099-12-31T23:59:00Z',
        'utilisateur': {'id': 'U-${DonneesFictives.login}', 'login': DonneesFictives.login, 'nom': 'TEST Awa'},
      }),
    });
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'pointage_rh');
    expect(await app.attendreQue(t, find.byKey(const Key('rh_voie_a'))), isTrue);
    await app.attendre(t, const Duration(seconds: 1));
    await t.tap(find.byKey(const Key('rh_voie_a')));
    expect(await app.attendreQue(t, find.byType(MobilePointageScreen)), isTrue);
    await app.attendre(t, const Duration(seconds: 1));
    expect(find.byKey(const Key('rh_mobile_mdp')), findsNothing, reason: 'aucun mot de passe demandé');
    expect(find.byKey(const Key('rh_mobile_deconnexion')), findsNothing, reason: 'aucun jeton du téléphone');
    expect(app.serveur.connexionsMobile, isEmpty, reason: 'aucune seconde connexion (v1/mobile)');
    expect(await const FlutterSecureStorage().read(key: _cleJeton), isNull, reason: 'ancien jeton effacé');
    await t.tap(find.byKey(const Key('rh_arrivee')));
    await app.attendre(t, const Duration(seconds: 6)); // position facultative : 5 s au plus
    expect(app.serveur.pointagesSession.map((p) => p.login), [DonneesFictives.login]);
    expect(app.serveur.pointagesSession.single.cle, startsWith('PT-'), reason: 'X-Client-Ref envoyé');
    expect(app.serveur.pointagesMobile, isEmpty, reason: 'rien par v1/mobile');
    expect(find.text('Entrée enregistrée à 08:02.'), findsOneWidget);
    expect(app.serveur.recues.where((r) => RegExp(r'/mobile/(connexion|moi|pointages)').hasMatch(r.chemin)), isEmpty);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  Future<void> terminal(WidgetTester t, {required bool gerer}) async {
    TailleEcran.telephone360x800.appliquer(t);
    final app = AppE2E()..serveur.activerTerminalRh();
    app.serveur.droitsRh[DonneesFictives.admin] = (pointer: true, gerer: gerer);
    await app.preparer(prefs: const {'hiddenMenuIds': <String>[]});
    await app.lancer(t);
    // Compte « admin » de l'application : administrateur local (gestion permise jusqu'ici par la 4.4.0).
    expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'pointage_rh');
    expect(await app.attendreQue(t, find.byKey(const Key('rh_voie_b'))), isTrue);
    await app.attendre(t, const Duration(seconds: 2));
    expect(find.byKey(const Key('rh_presences')), gerer ? findsOneWidget : findsNothing);
    expect(find.byKey(const Key('rh_photos')), gerer ? findsWidgets : findsNothing);
    await t.tap(find.byKey(const Key('rh_voie_b')));
    expect(await app.attendreQue(t, find.byType(TerminalPointageScreen)), isTrue);
    await app.attendre(t, const Duration(seconds: 2));
    expect(app.serveur.recuesSur('/rh/employes'), isNotEmpty);
    expect(find.byKey(const Key('rh_gerer_empreintes')), findsNothing, reason: 'enrôlement des empreintes : gestion seulement');
    if (!gerer) {
      expect(app.serveur.recuesSur('/rh/presence'), isEmpty, reason: 'aucune route de gestion appelée');
      expect(app.serveur.recuesSur('/rh/tableau'), isEmpty);
    }
    expect(t.takeException(), isNull, reason: 'employés aux seuls champs id, matricule, nom, prénoms, badge, statut');
    await app.fermer(t);
  }

  testWidgets('compte avec P_RH_POINTER seul (gerer:false) : terminal ouvert, aucune gestion même pour l\'administrateur', (t) async {
    await terminal(t, gerer: false);
  });

  testWidgets('témoin : P_SM_RH (gerer:true) et administrateur de l\'application → présences et photos proposées', (t) async {
    await terminal(t, gerer: true);
  });
}
