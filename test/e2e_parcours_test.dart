// E2E — parcours clés de Prestige Mobile, application ENTIÈRE montée (MyApp : vrais providers, vrais écrans,
// vrai client Dio, intercepteur de session, surveillance du serveur) reliée au faux serveur Prestige en
// mémoire (test/outils/faux_serveur_prestige.dart). Exécuté par `flutter test` sur Linux, sans émulateur.
//
// Lancement → licence (serveur injoignable, 5xx, 401, 403 ≠ « aucune licence ») → connexion (cookie renouvelé)
// → accueil (présentations A / B / C) → chaque menu principal ouvert puis retour → session expirée en cours de
// route (reconnexion silencieuse / écran de connexion) → serveur coupé (message réseau) → vente hors ligne
// puis envoi au retour du serveur.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart' show AccueilScreen;
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/accueil/recherche_globale_screen.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/connexion/lancement_screen.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart' show CatalogueCategorie;
import 'package:prestige_vente_app/horsligne/connexion_toasts.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/parametres/parametres_screen.dart';
import 'package:prestige_vente_app/screens/auth/licence_registration_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';

/// Droits côté serveur du compte connecté.
void droits(FauxServeurPrestige s, {bool admin = false, bool ordonnances = false}) {
  s.routes['GET /roles/est-admin'] = (_) => FauxServeurPrestige.ok({'authorize': admin});
  s.routes['GET /ordonnance-client/droits'] = (_) => FauxServeurPrestige.ok({'success': true, 'consulter': ordonnances, 'modifier': ordonnances});
}

void main() {
  // ---------------------------------------------------------------------------
  group('Lancement et licence', () {
    testWidgets('serveur injoignable : « Serveur indisponible, veuillez réessayer », jamais « Aucune licence » ; Réessayer → connexion', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      await app.preparer();
      await app.serveur.couper();
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byKey(const Key('lancement_injoignable'))), isTrue);
      expect(find.text('Serveur indisponible, veuillez réessayer'), findsOneWidget);
      expect(find.textContaining('La licence n\'est pas en cause'), findsOneWidget);
      expect(find.byKey(const Key('lancement_licence')), findsNothing);
      expect(find.textContaining('Aucune licence'), findsNothing);

      await app.serveur.retablir();
      await t.tap(find.byKey(const Key('lancement_reessayer')));
      expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    final erreurs = <String, ReponseLocale>{
      'HTTP 500': FauxServeurPrestige.erreurServeur(500),
      'HTTP 503': FauxServeurPrestige.erreurServeur(503),
      'HTTP 401 « Veuillez vous connecter »': FauxServeurPrestige.nonConnecte401,
      'HTTP 403 « Veuillez vous connecter »': FauxServeurPrestige.nonConnecte403,
    };
    erreurs.forEach((nom, reponse) {
      testWidgets('licence en $nom : problème de serveur, pas « aucune licence » (aucun écran de clé)', (t) async {
        TailleEcran.sunmiV2s.appliquer(t);
        final app = AppE2E();
        app.serveur.licence = reponse;
        await app.preparer();
        await app.lancer(t);
        expect(await app.attendreQue(t, find.byKey(const Key('lancement_injoignable'))), isTrue);
        expect(find.byKey(const Key('lancement_licence')), findsNothing);
        expect(find.textContaining('Aucune licence'), findsNothing);
        expect(find.byType(LicenceRegistrationScreen), findsNothing);
        expect(find.byType(LancementScreen), findsOneWidget);
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });
    });

    testWidgets('témoin : réponse vide = aucune licence enregistrée → explication et saisie de la clé', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      app.serveur.licence = const ReponseLocale('');
      await app.preparer();
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byKey(const Key('lancement_licence'))), isTrue);
      expect(find.text('Aucune licence enregistrée'), findsOneWidget);
      expect(find.byKey(const Key('saisir_licence')), findsOneWidget);
      await app.fermer(t);
    });
  });

  // ---------------------------------------------------------------------------
  group('Connexion', () {
    testWidgets('cookie renouvelé : seul le JSESSIONID de la connexion est envoyé ensuite, aucune requête refusée', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      // La lecture de la licence AVANT la connexion pose un premier cookie (cas réel du serveur Prestige).
      // (le serveur ne crée une session que pour une requête qui n'en porte pas).
      app.serveur.routes['GET /licence/find'] = (r) => ReponseLocale(DonneesFictives.licence(),
          entetes: r.jsessionid == null ? {'set-cookie': 'JSESSIONID=ANCIEN; Path=/prestige; HttpOnly'} : const {});
      await app.preparer();
      await app.lancer(t);
      expect(await app.seConnecter(t), isTrue);
      final session = app.serveur.derniereSession;
      expect(session, isNotNull);
      expect(app.serveur.connexions, 1);
      final apres = app.serveur.recues.where((r) => !routePubliquePrestige(r.chemin)).toList();
      expect(apres, isNotEmpty, reason: 'chargements après la connexion (préventes, BL, modes de règlement, droits)');
      for (final r in apres) {
        expect(r.jsessionid, session, reason: '$r doit porter la session de la connexion');
        expect(r.cookie, isNot(contains('ANCIEN')), reason: '$r ne doit plus porter l\'ancien cookie');
      }
      expect(app.serveur.refusSession, 0);
      expect(find.text('Awa Test'), findsOneWidget);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('mot de passe refusé : message clair, pas d\'accueil, aucune session', (t) async {
      TailleEcran.telephone.appliquer(t);
      final app = AppE2E();
      await app.preparer();
      await app.lancer(t);
      expect(await app.seConnecter(t, motDePasse: 'faux'), isFalse);
      expect(find.textContaining('Identifiant ou mot de passe incorrect'), findsOneWidget);
      expect(app.serveur.connexions, 0);
      await app.fermer(t);
    });
  });

  // ---------------------------------------------------------------------------
  group('Accueil : chaque menu principal ouvert puis retour', () {
    const principaux = ['prevente', 'search', 'analyse_article', 'posos', 'ordonnances_clients', 'reserve', 'pointage_rh'];

    for (final style in ListPresentation.values) {
      testWidgets('présentation ${style.name} (${style.label}) — administrateur, droits ordonnances', (t) async {
        TailleEcran.sunmiV2s.appliquer(t);
        final app = AppE2E();
        droits(app.serveur, admin: true, ordonnances: true);
        await app.preparer(prefs: {'presentation_listes_v1': style.name, 'hiddenMenuIds': <String>[]});
        await app.lancer(t);
        expect(await app.seConnecter(t), isTrue);
        expect(find.byType(AccueilScreen), findsOneWidget);

        for (final id in principaux) {
          final m = [...accueilMenus, ...menusSousDroits].firstWhere((m) => m.id == id);
          await app.ouvrirMenu(t, style, id);
          expect(find.byType(m.screen().runtimeType), findsOneWidget, reason: 'menu $id ouvert');
          expect(t.takeException(), isNull, reason: 'menu $id');
          await app.retour(t);
          expect(find.byType(m.screen().runtimeType), findsNothing, reason: 'retour depuis $id');
          expect(ModalRoute.of(t.element(find.byType(AccueilScreen)))!.isCurrent, isTrue, reason: 'accueil après $id');
        }

        // Recherche globale (en-tête / « Chercher un produit ») puis fiche produit par code.
        final entree = style == ListPresentation.guided ? find.text('Chercher un produit') : find.text('Rechercher un menu ou un produit');
        await app.defilerJusqua(t, entree);
        await t.tap(entree);
        await app.attendre(t, const Duration(seconds: 1));
        expect(find.byType(RechercheGlobaleScreen), findsOneWidget);
        await t.enterText(find.byType(TextField).first, '9990001');
        await t.testTextInput.receiveAction(TextInputAction.search);
        expect(await app.attendreQue(t, find.byType(FicheProduitScreen)), isTrue, reason: 'fiche produit ouverte par le code');
        await app.attendre(t);
        expect(find.textContaining('PARACETAMOL TEST'), findsWidgets);
        await app.retour(t);
        await app.retour(t);
        expect(find.byType(RechercheGlobaleScreen), findsNothing);

        // Réglages (barre du bas).
        await t.tap(find.text('Réglages'));
        await app.attendre(t, const Duration(seconds: 1));
        expect(find.byType(ParametresScreen), findsOneWidget);
        await app.retour(t);
        expect(find.byType(ParametresScreen), findsNothing);
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });
    }

    testWidgets('droits : Réserve absente pour un non-administrateur, Fiche client absente sans le droit', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      droits(app.serveur);
      await app.preparer(prefs: {'hiddenMenuIds': <String>[]});
      await app.lancer(t);
      expect(await app.seConnecter(t), isTrue);
      await app.attendre(t);
      expect(await app.menuPresent(t, ListPresentation.dashboard, 'reserve'), isFalse);
      expect(await app.menuPresent(t, ListPresentation.dashboard, 'ordonnances_clients'), isFalse);
      expect(await app.menuPresent(t, ListPresentation.dashboard, 'posos'), isTrue, reason: 'analyse posologie : tout compte connecté');
      expect(await app.menuPresent(t, ListPresentation.dashboard, 'pointage_rh'), isTrue);
      await app.fermer(t);
    });

    testWidgets('droits : compte « admin » de l\'application → Réserve visible même sans profil administrateur serveur', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      droits(app.serveur);
      await app.preparer(prefs: {'hiddenMenuIds': <String>[]});
      await app.lancer(t);
      expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
      await app.attendre(t);
      expect(await app.menuPresent(t, ListPresentation.dashboard, 'reserve'), isTrue);
      expect(await app.menuPresent(t, ListPresentation.dashboard, 'ordonnances_clients'), isFalse);
      await app.fermer(t);
    });
  });

  // ---------------------------------------------------------------------------
  group('Session expirée en cours de route', () {
    Future<void> actualiser(WidgetTester t, AppE2E app) async {
      await t.tap(find.byTooltip('Plus d\'actions'));
      await app.attendre(t, const Duration(milliseconds: 500));
      await t.tap(find.text('Actualiser'));
      await app.attendre(t);
    }

    testWidgets('« Rester connecté » : reconnexion silencieuse, l\'utilisateur reste sur l\'accueil', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      await app.preparer(resterConnecte: true);
      await app.lancer(t);
      // Connexion automatique au lancement.
      expect(await app.attendreQue(t, find.byType(AccueilScreen)), isTrue);
      await app.attendre(t);
      expect(app.serveur.connexions, 1);
      final premiere = app.serveur.derniereSession;

      app.serveur.expirerSessions(); // durée de session dépassée côté serveur
      await actualiser(t, app);
      expect(app.serveur.connexions, 2, reason: 'une reconnexion silencieuse');
      expect(app.serveur.derniereSession, isNot(premiere));
      expect(app.serveur.refusSession, greaterThan(0));
      expect(find.byType(AccueilScreen), findsOneWidget);
      expect(find.byType(ConnexionScreen), findsNothing);
      expect(find.text('Votre session a expiré, reconnectez-vous'), findsNothing);
      // Les requêtes rejouées portent la nouvelle session.
      final dernieres = app.serveur.recuesSur('/ventestats/preventes');
      expect(dernieres.last.jsessionid, app.serveur.derniereSession);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('sans « Rester connecté » : retour à l\'écran de connexion avec le message', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      await app.preparer();
      await app.lancer(t);
      expect(await app.seConnecter(t), isTrue);
      app.serveur.expirerSessions();
      await actualiser(t, app);
      expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
      expect(find.text('Votre session a expiré, reconnectez-vous'), findsOneWidget);
      expect(find.byType(AccueilScreen), findsNothing);
      expect(app.serveur.connexions, 1, reason: 'aucune reconnexion sans identifiants mémorisés');
      // Reconnexion manuelle : retour à l'accueil.
      expect(await app.seConnecter(t), isTrue);
      expect(app.serveur.connexions, 2);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });

  // ---------------------------------------------------------------------------
  group('Réseau', () {
    testWidgets('serveur coupé en cours de route : « Connexion au serveur perdue », puis « De nouveau en ligne »', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      await app.preparer();
      await app.lancer(t);
      expect(await app.seConnecter(t), isTrue);
      await app.serveur.couper();
      expect(await app.attendreQue(t, find.text(ConnexionToasts.perteTexte), max: const Duration(minutes: 3)), isTrue);
      expect(app.horsLigne.monitor.etat, isNot(EtatServeur.enLigne));
      await app.attendre(t, const Duration(seconds: 5));
      expect(find.textContaining('injoignable'), findsWidgets);

      await app.serveur.retablir();
      expect(await app.attendreQue(t, find.text(ConnexionToasts.retourTexte), max: const Duration(minutes: 2)), isTrue);
      expect(app.horsLigne.monitor.etat, EtatServeur.enLigne);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('vente hors ligne (prévente provisoire) puis envoi au retour du serveur après confirmation', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      await app.preparer(prefs: {'hiddenMenuIds': <String>[]});
      await app.lancer(t);
      expect(await app.seConnecter(t), isTrue);
      await app.attendre(t, const Duration(seconds: 3));
      // Copie locale du catalogue (mise à jour normalement au fil de l'eau).
      await app.horsLigne.store.replace(CatalogueCategorie.produits, [DonneesFictives.produitRecherche()], DateTime.now());
      await app.horsLigne.sync.refreshStats();

      // Coupure → serveur injoignable → « Continuer hors ligne ».
      await app.serveur.couper();
      expect(await app.attendreQue(t, find.text('Continuer hors ligne'), max: const Duration(minutes: 3)), isTrue);
      await t.tap(find.text('Continuer hors ligne'));
      await app.attendre(t);
      expect(app.horsLigne.offline, isTrue);

      // Vente comptant hors ligne : prévente provisoire.
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
      await t.enterText(find.byKey(const ValueKey('vente-recherche')), 'para');
      await app.attendre(t);
      final champQte = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));
      expect(await app.attendreQue(t, champQte), isTrue, reason: 'produit trouvé dans la copie locale');
      await t.enterText(champQte, '2');
      await t.tap(find.text('Ajouter'));
      await app.attendre(t);
      expect(find.byKey(const ValueKey('vente-etat-hors-ligne')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('vente-hl-prevente')));
      await app.attendre(t);
      expect(find.text('Prévente provisoire enregistrée'), findsOneWidget);
      await t.tap(find.text('Non')); // pas d'impression du ticket provisoire
      await app.attendre(t);
      expect(app.horsLigne.ventes.enAttente, 1);
      expect(app.serveur.ventes, isEmpty, reason: 'rien n\'est envoyé hors ligne');
      await app.retour(t);

      // Retour du serveur : repasser en ligne, confirmation, envoi.
      await app.serveur.retablir();
      app.horsLigne.monitor.goOnline();
      expect(await app.attendreQue(t, find.byKey(const Key('confirmation_envoi')), max: const Duration(minutes: 2)), isTrue);
      await t.tap(find.byKey(const Key('envoyer_selection')));
      await app.attendre(t, const Duration(seconds: 5));
      expect(app.serveur.ventes.keys, ['V-1'], reason: 'la prévente provisoire est créée sur le serveur');
      expect(app.serveur.ventes['V-1']!.single['intQUANTITY'], 2);
      expect(app.serveur.statutVentes['V-1'], 'is_Process', reason: 'prévente enregistrée (à encaisser)');
      expect(app.horsLigne.ventes.enAttente, 0);
      expect(app.horsLigne.ventes.aVerifier, 0);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });
}
