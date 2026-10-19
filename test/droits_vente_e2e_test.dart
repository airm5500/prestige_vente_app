// 4.5.1 — e2e, application entière (faux serveur Prestige en mémoire, données fictives) : sécurité des ventes
// (demande du serveur du 19/10/2026).
//  - compte « Pre-vente » : pas de « ENCAISSER » (nouvelle et ancienne interface), pas de « préventes à encaisser »,
//    « PRÉVENTE » seule ; hors ligne : pas d'encaissement espèces provisoire ;
//  - appel forcé (serveur ancien sans GET v1/user/droits, bouton affiché) : 403 interdit → message du serveur, vente
//    toujours en cours, utilisateur toujours connecté, une seule tentative ;
//  - changement de compte (déconnexion → autre compte) : POST v1/user/logout, cookies vidés, panier et vente à
//    reprendre effacés, droits relus pour le nouveau compte ;
//  - 409 sessionChangee : message, compte et droits relus, retour à l'accueil, rien d'exécuté ;
//  - en-tête X-Prestige-Utilisateur sur les requêtes de la session.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/connexion/changement_utilisateur.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart' show CatalogueCategorie;
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/ventes/core/pending_sale_store.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

import 'outils/app_e2e.dart';
import 'outils/parcours_vente.dart';

const _stagiaire = 'stagiaire.demo';
const _mdpStagiaire = 'Stage#2026';

/// Faux serveur : comptes de la pharmacie + stagiaire au profil « Pre-vente » ; droits par compte (null : route
/// absente, serveur ancien).
(AppE2E, CatalogueFictif) _app({bool routeDroits = true}) {
  final app = AppE2E(serveur: FauxServeurPrestige(comptes: {
    DonneesFictives.login: DonneesFictives.motDePasse,
    DonneesFictives.admin: DonneesFictives.motDePasseAdmin,
    _stagiaire: _mdpStagiaire,
  }));
  if (!routeDroits) {
    app.serveur.droitsComptes = null;
  } else {
    app.serveur.droitsComptes = {
      _stagiaire: ['P_SM_VENTE'],
      DonneesFictives.login: ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE'],
      DonneesFictives.admin: ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE', 'P_SM_VENTEDEPOT', 'P_BT_ANNULER_VENTE'],
    };
  }
  final c = CatalogueFictif(app.serveur, nombre: 10);
  return (app, c);
}

AuthProvider _auth(WidgetTester t) => Provider.of<AuthProvider>(t.element(find.byType(Navigator).first), listen: false);

void main() {
  group('Compte « Pre-vente »', () {
    testWidgets('nouvelle interface : pas de « ENCAISSER » ; « PRÉVENTE » enregistre la vente', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final (app, _) = _app();
      await app.preparer(prefs: prefsVente);
      await app.lancer(t);
      expect(await app.seConnecter(t, login: _stagiaire, motDePasse: _mdpStagiaire), isTrue);
      expect(app.serveur.recuesSur('/user/droits'), hasLength(1), reason: 'droits lus à la connexion');
      expect(DroitsVente.instance.preventeSeule, isTrue);
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
      expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
      await app.attendre(t, const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('vente-encaisser')), findsNothing);
      expect(find.byKey(const ValueKey('vente-encaissement-reserve')), findsOneWidget);
      expect(find.text(DroitsVente.messageReserve), findsOneWidget);
      final prevente = find.byKey(const ValueKey('vente-enregistrer-prevente'));
      expect(prevente, findsOneWidget);
      await t.tap(prevente);
      await app.attendre(t, const Duration(seconds: 2));
      expect(app.serveur.recues.where((r) => r.chemin.contains('/vente/terminerprevente/')), hasLength(1),
          reason: '« Terminer la prévente » reste permis');
      expect(app.serveur.recuesSur('/vente/cloturer/vno'), isEmpty);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('témoin : compte avec le droit de clôture → « ENCAISSER » visible', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final (app, _) = _app();
      await app.preparer(prefs: prefsVente);
      await app.lancer(t);
      expect(await app.seConnecter(t), isTrue);
      expect(DroitsVente.instance.terminerVente, isTrue);
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
      expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
      await app.attendre(t, const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('vente-encaisser')), findsOneWidget);
      expect(find.byKey(const ValueKey('vente-encaissement-reserve')), findsNothing);
      await app.fermer(t);
    });

    testWidgets('ancienne interface des ventes : onglet VENTE sans bouton d\'encaissement', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final (app, _) = _app();
      await app.preparer(prefs: {...prefsVente, 'ventes_nouvelle_version_v1': false});
      await app.lancer(t);
      expect(await app.seConnecter(t, login: _stagiaire, motDePasse: _mdpStagiaire), isTrue);
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
      await t.tap(find.text('VENTE'));
      await app.attendre(t, const Duration(seconds: 1));
      expect(find.byKey(const Key('encaissement_reserve')), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      await t.tap(find.text('PREVENTE'));
      await app.attendre(t, const Duration(seconds: 1));
      expect(find.byKey(const Key('encaissement_reserve')), findsNothing, reason: 'onglet PREVENTE inchangé');
      await app.fermer(t);
    });

    testWidgets('hors ligne : pas d\'encaissement espèces provisoire, seulement la prévente provisoire', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final (app, _) = _app();
      await app.preparer(prefs: prefsVente);
      await app.lancer(t);
      expect(await app.seConnecter(t, login: _stagiaire, motDePasse: _mdpStagiaire), isTrue);
      await app.horsLigne.store.replace(CatalogueCategorie.produits, [for (var i = 1; i <= 5; i++) produitFictif(i)], DateTime.now());
      await app.horsLigne.sync.refreshStats();
      await app.serveur.couper();
      expect(await app.attendreQue(t, find.text('Continuer hors ligne'), max: const Duration(minutes: 3)), isTrue);
      await t.tap(find.text('Continuer hors ligne'));
      await app.attendre(t);
      expect(DroitsVente.instance.preventeSeule, isTrue, reason: 'droits en mémoire de la dernière lecture');
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
      expect(await ajouterAuPanier(t, app, nomCourt(2)), isTrue);
      await app.attendre(t, const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('vente-hl-especes')), findsNothing);
      expect(find.byKey(const ValueKey('vente-hl-prevente')), findsOneWidget);
      await app.serveur.retablir();
      await app.fermer(t);
    });
  });

  testWidgets('appel forcé (serveur sans lecture des droits) : 403 interdit → message, vente en cours, toujours connecté', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, c) = _app(routeDroits: false);
    var clotures = 0;
    app.serveur.routes['POST /vente/cloturer/vno'] = (_) {
      clotures++;
      return FauxServeurPrestige.interdit('Droit manquant : votre profil ne permet pas de terminer une vente.');
    };
    await app.preparer(prefs: prefsVente);
    await app.lancer(t);
    expect(await app.seConnecter(t, login: _stagiaire, motDePasse: _mdpStagiaire), isTrue);
    expect(DroitsVente.instance.routeAbsente, isTrue, reason: 'serveur ancien : repli, bouton affiché');
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
    await app.attendre(t, const Duration(seconds: 2));
    await validerEncaissementEspeces(t, app);
    await app.attendre(t, const Duration(seconds: 3));
    expect(find.textContaining('votre profil ne permet pas de terminer une vente'), findsWidgets, reason: 'message du serveur affiché');
    expect(clotures, 1, reason: 'aucune nouvelle tentative');
    expect(c.clotures, 0);
    expect(app.serveur.statutVentes['V-1'], 'is_Process', reason: 'vente toujours en cours');
    expect(app.serveur.connexions, 1, reason: 'aucune reconnexion');
    expect(app.serveur.recuesSur('/user/logout'), isEmpty, reason: 'jamais déconnecté sur un 403');
    expect(_auth(t).status, AuthStatus.Authenticated);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('changement de compte : déconnexion (POST logout, cookies vidés), panier et vente à reprendre effacés', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, _) = _app();
    await app.preparer(prefs: prefsVente);
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    expect(await ajouterAuPanier(t, app, nomCourt(4)), isTrue);
    await app.attendre(t, const Duration(seconds: 2));
    expect(await PendingSaleStore.load(VenteMenu.prevente), isNotNull, reason: 'vente en cours mémorisée pour ce compte');
    await app.retour(t);
    if (find.text('Quitter').evaluate().isNotEmpty) await t.tap(find.text('Quitter'));
    await app.attendre(t);
    expect(await app.attendreQue(t, find.byType(AccueilScreen)), isTrue);
    final avant = EtatLocalVente.effacements;
    await app.defilerJusqua(t, find.byKey(const Key('accueil_deconnexion')));
    await t.tap(find.byKey(const Key('accueil_deconnexion')));
    await app.attendre(t, const Duration(milliseconds: 500));
    await t.tap(find.widgetWithText(ElevatedButton, 'Se déconnecter'));
    await app.attendre(t, const Duration(seconds: 2));
    expect(app.serveur.recuesSur('/user/logout'), hasLength(1));
    expect(await DioClient.cookieJar.loadForRequest(Uri.parse('http://${FauxServeurPrestige.hoteMemoire}:${FauxServeurPrestige.portMemoire}/prestige/api/v1/x')), isEmpty);
    expect(EtatLocalVente.effacements, greaterThan(avant));
    expect(DroitsVente.instance.connus, isFalse, reason: 'droits du compte précédent oubliés');
    expect(await PendingSaleStore.load(VenteMenu.prevente), isNull, reason: 'vente à reprendre effacée');
    // Autre compte : droits relus, panier vide.
    expect(await app.seConnecter(t, login: _stagiaire, motDePasse: _mdpStagiaire), isTrue);
    expect(DroitsVente.instance.utilisateur, 'U-$_stagiaire');
    expect(DroitsVente.instance.preventeSeule, isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    await app.attendre(t, const Duration(seconds: 1));
    expect(find.textContaining('Reprendre'), findsNothing);
    expect(find.text('Le panier est vide'), findsOneWidget);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('409 sessionChangee : message, compte et droits relus, retour à l\'accueil, rien d\'exécuté', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final (app, _) = _app();
    await app.preparer(prefs: prefsVente);
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    expect(app.serveur.recues.where((r) => r.chemin.endsWith('/officine') || r.chemin.endsWith('/user/droits')).last.utilisateur,
        'U-${DonneesFictives.login}', reason: 'en-tête X-Prestige-Utilisateur envoyé');
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    // Un autre compte s'est connecté sur la même session (vue web partagée).
    app.serveur.basculerSession(DonneesFictives.admin);
    await t.enterText(champRechercheVente, nomCourt(5));
    await app.attendre(t, const Duration(seconds: 3));
    expect(app.serveur.refus409, greaterThan(0));
    expect(await app.attendreQue(t, find.byKey(const Key('session_changee'))), isTrue);
    expect(find.descendant(of: find.byKey(const Key('session_changee')), matching: find.textContaining('Un autre compte (${DonneesFictives.admin})')),
        findsOneWidget);
    expect(find.byType(AccueilScreen), findsOneWidget, reason: 'retour à l\'accueil');
    expect(app.serveur.recuesSur('/user/account'), hasLength(1));
    expect(_auth(t).user?.userId, 'U-${DonneesFictives.admin}');
    expect(DroitsVente.instance.utilisateur, 'U-${DonneesFictives.admin}', reason: 'droits relus (lectures : ${DroitsVente.instance.lectures})');
    expect(app.serveur.recuesSur('/user/account').single.utilisateur, isEmpty, reason: 'compte relu sans l\'en-tête de l\'ancien compte');
    expect(app.serveur.ventes, isEmpty, reason: 'aucune vente créée');
    await t.tap(find.text('OK'));
    await app.attendre(t);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
