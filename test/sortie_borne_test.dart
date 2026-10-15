// 4.1.2 — Retours du pharmacien sur les modes « borne » :
// - borne libre-service : bloqué sans pouvoir sortir une fois l'appli épinglée ; « elle n'affiche pas les données »
//   une fois activée sur un téléphone ;
// - terminal de pointage : impossible de quitter, même par l'appui long sur le cadenas.
// Causes : l'infobulle du bouton désactivé captait l'appui long (terminal) ; zone de sortie invisible, à moitié
// sous la barre d'état, 5 s (borne) ; à la sortie, mode borne gardé actif (la borne se rouvrait au démarrage) ;
// échec de connexion de l'utilisateur borne affiché comme un « indisponible » muet ; session de l'utilisateur
// borne expirée → écran de connexion de l'appli sur une borne épinglée.
// Vérifié ici : sortie simple et fiable (cadenas, appui long 2 s, confirmation, code administrateur) — e2e
// « activer puis quitter » sur l'application entière —, cause affichée et « Tester la borne », reconnexion de
// l'utilisateur borne, terminal de pointage « entrer puis quitter ».
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_diagnostic.dart';
import 'package:prestige_vente_app/borne/borne_kiosque.dart';
import 'package:prestige_vente_app/borne/borne_launcher.dart';
import 'package:prestige_vente_app/borne/borne_reglages_page.dart';
import 'package:prestige_vente_app/borne/borne_screen.dart';
import 'package:prestige_vente_app/rh/terminal_pointage_screen.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/services/pin_securise.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sortie_kiosque.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/app_e2e.dart';
import 'pointage_photo_test.dart' show Env, pump;

const _loginBorne = 'borne.accueil';
const _mdpBorne = 'Borne#2026';
const _doli = 'DOLIPRANE 1000MG CP B/8';

/// Code administrateur de l'appareil (vraie fenêtre PinCodeDialog, vérification simulée : 4827).
class _Code extends CodeAdmin {
  int demandes = 0;
  @override
  Future<Duration?> attenteRestante() async => null;
  @override
  Future<VerificationPin> verifier(String saisie) async {
    demandes++;
    return saisie == '4827' ? VerificationPin.accepte : VerificationPin.refuse;
  }
}

_Code _installerCode() {
  final avant = CodeAdmin.instance;
  final c = _Code();
  CodeAdmin.instance = c;
  addTearDown(() => CodeAdmin.instance = avant);
  return c;
}

KiosqueSimule _installerKiosque() {
  final avant = BorneKiosque.instance;
  final k = KiosqueSimule();
  BorneKiosque.instance = k;
  addTearDown(() => BorneKiosque.instance = avant);
  return k;
}

MemoireBorneSecrets _installerSecrets([String? mdp]) {
  final avant = BorneReglages.secrets;
  final s = MemoireBorneSecrets(mdp);
  BorneReglages.secrets = s;
  addTearDown(() {
    BorneReglages.secrets = avant;
    BorneReglages.courant.value = const BorneConfig();
  });
  return s;
}

Future<void> _saisirCode(WidgetTester t, AppE2E app, String code) async {
  expect(await app.attendreQue(t, find.byKey(const Key('pin_admin_saisie'))), isTrue, reason: 'code administrateur demandé');
  await t.enterText(find.byKey(const Key('pin_admin_saisie')), code);
  await t.tap(find.text('Valider'));
  await app.attendre(t, const Duration(seconds: 1));
}

/// Appui long de [duree] sur [f].
Future<void> _appuiLong(WidgetTester t, Finder f, [Duration duree = const Duration(milliseconds: 2100)]) async {
  final g = await t.startGesture(t.getCenter(f));
  await t.pump(duree);
  await g.up();
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

/// Faux serveur : comptes de la pharmacie + utilisateur borne, recherche « contient » / « commence par ».
AppE2E _app() {
  final app = AppE2E(serveur: FauxServeurPrestige(comptes: {
    DonneesFictives.login: DonneesFictives.motDePasse,
    DonneesFictives.admin: DonneesFictives.motDePasseAdmin,
    _loginBorne: _mdpBorne,
  }))
    ..serveur.activerModules();
  final catalogue = [
    {'lgFAMILLEID': 'F1', 'strNAME': _doli, 'intCIP': '3595583', 'intPRICE': 1500, 'intNUMBERAVAILABLE': 40, 'strLIBELLEE': '', 'intPAF': 0},
    {'lgFAMILLEID': 'F2', 'strNAME': 'RHINOFEBRAL GELULES B/16', 'intCIP': '3401551', 'intPRICE': 2900, 'intNUMBERAVAILABLE': 8, 'strLIBELLEE': '', 'intPAF': 0},
  ];
  app.serveur.routes['GET /vente/search'] = (r) {
    final q = (r.query['query'] ?? '').toUpperCase();
    final contient = q.startsWith('%');
    final mots = q.split('%').where((m) => m.isNotEmpty).toList();
    final l = [
      for (final p in catalogue)
        if (p['intCIP'] == q ||
            (contient ? mots.every((m) => (p['strNAME'] as String).contains(m)) : (p['strNAME'] as String).startsWith(q)))
          p
    ];
    return FauxServeurPrestige.ok({'data': l, 'total': l.length});
  };
  return app;
}

/// Borne active sur l'appareil (préférences), ouverte au démarrage.
Map<String, Object> _prefsBorneActive() =>
    {'borne_config_v1': jsonEncode(const BorneConfig(actif: true, login: _loginBorne).toJson()), 'hiddenMenuIds': <String>[]};

void main() {
  // ---------------------------------------------------------------------------------------------------------
  group('Cadenas de sortie (widget commun)', () {
    testWidgets('appui court : aide ; appui de 1 s : rien ; appui long de 2 s : sortie', (t) async {
      var sorties = 0;
      var aides = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(child: BoutonSortieKiosque(key: const Key('c'), onSortie: () => sorties++, onAppuiCourt: () => aides++)),
        ),
      ));
      expect(t.getSize(find.byKey(const Key('c'))), const Size(48, 48), reason: 'cible tactile ≥ 48 dp');
      await t.tap(find.byKey(const Key('c')));
      await t.pump();
      expect((aides, sorties), (1, 0));
      await _appuiLong(t, find.byKey(const Key('c')), const Duration(seconds: 1));
      expect((aides, sorties), (2, 0));
      await _appuiLong(t, find.byKey(const Key('c')));
      expect(sorties, 1);
      expect(aides, 2, reason: 'pas d\'aide après une sortie');
      expect(find.bySemanticsLabel(RegExp('Quitter le mode borne')), findsOneWidget);
    });

    testWidgets('cause du blocage du terminal : l\'infobulle d\'un bouton désactivé capte l\'appui long', (t) async {
      // Ancienne construction (terminal de pointage jusqu'à la 4.1.1) : l'appui long ne partait jamais.
      var ancien = 0;
      var nouveau = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            GestureDetector(
              onLongPress: () => ancien++,
              child: const IconButton(key: Key('ancien'), tooltip: 'Mode borne (appui long pour quitter)', onPressed: null, icon: Icon(Icons.lock)),
            ),
            BoutonSortieKiosque(key: const Key('nouveau'), onSortie: () => nouveau++),
          ]),
        ),
      ));
      await t.longPress(find.byKey(const Key('ancien')));
      await t.pump(const Duration(seconds: 3));
      expect(ancien, 0, reason: 'l\'infobulle gagne : le geste de sortie n\'était jamais reçu');
      await _appuiLong(t, find.byKey(const Key('nouveau')));
      expect(nouveau, 1);
      await t.pump(const Duration(seconds: 5));
    });
  });

  // ---------------------------------------------------------------------------------------------------------
  group('Terminal de pointage (menu Pointage › terminal)', () {
    for (final style in ListPresentation.values) {
      testWidgets('${style.label} : entrer en mode borne, Retour bloqué, puis quitter (2 s, confirmation, code admin)', (t) async {
        t.view.physicalSize = const Size(720, 1440);
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        // Barres système (SystemChrome) : canal de la plateforme simulé, modes demandés relevés.
        final modes = <Object?>[];
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setEnabledSystemUIMode') modes.add(call.arguments);
          return null;
        });
        addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
        final e = await Env().pret();
        var demandes = 0;
        var reponse = false;
        await pump(
            t,
            TerminalPointageScreen(
              rh: e.pr,
              presentation: style,
              identification: e.identification,
              rafraichirAuDemarrage: false,
              codeAdmin: (_) async {
                demandes++;
                return reponse;
              },
            ));
        await t.tap(find.byKey(const Key('rh_mode_borne')));
        await t.pumpAndSettle();
        expect(find.byIcon(Icons.lock_outline), findsOneWidget, reason: 'mode borne : cadenas « Quitter » visible');
        expect(find.text('Quitter'), findsOneWidget);
        // Retour Android : on reste, l'aide est affichée.
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.byType(TerminalPointageScreen), findsOneWidget);
        expect(find.text(aideSortieKiosque), findsOneWidget);
        await t.pump(const Duration(seconds: 5));
        await t.pumpAndSettle();
        // Appui long 2 s → confirmation → « Rester ».
        await _appuiLong(t, find.byKey(const Key('rh_mode_borne')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('sortie-kiosque-rester')));
        await t.pumpAndSettle();
        expect(demandes, 0);
        // Confirmé, code refusé : toujours en mode borne.
        await _appuiLong(t, find.byKey(const Key('rh_mode_borne')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('sortie-kiosque-confirmer')));
        await t.pumpAndSettle();
        expect(demandes, 1);
        expect(find.byIcon(Icons.lock_outline), findsOneWidget);
        // Code accepté : sortie.
        reponse = true;
        await _appuiLong(t, find.byKey(const Key('rh_mode_borne')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('sortie-kiosque-confirmer')));
        await t.pumpAndSettle();
        expect(demandes, 2);
        expect(find.byIcon(Icons.lock_outline), findsNothing);
        expect(find.byIcon(Icons.fullscreen), findsOneWidget, reason: 'mode borne quitté');
        expect(modes, ['SystemUiMode.immersiveSticky', 'SystemUiMode.edgeToEdge'], reason: 'barres système masquées puis rendues');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 5));
      });
    }
  });

  // ---------------------------------------------------------------------------------------------------------
  group('Borne libre-service (application entière)', () {
    testWidgets('e2e : activer (réglages, Tester la borne) → borne épinglée avec ses données → quitter (2 s, code admin) → connexion',
        (t) async {
      TailleEcran.telephone360x800.appliquer(t);
      final code = _installerCode();
      final kiosque = _installerKiosque();
      final secrets = _installerSecrets();
      final app = _app();
      await app.preparer(prefs: {'hiddenMenuIds': <String>[]});
      await app.lancer(t);
      expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
      await app.attendre(t);

      // Accueil › Ventes › « Borne / vente discrète » (administrateur, code demandé).
      await app.defilerJusqua(t, find.byKey(const ValueKey('tuile_borne_admin')));
      await t.tap(find.byKey(const ValueKey('tuile_borne_admin')));
      await app.attendre(t, const Duration(seconds: 1));
      await _saisirCode(t, app, '4827');
      expect(find.byType(BornePage), findsOneWidget);
      expect(find.text('À activer sur l\'appareil qui servira de borne (tablette, borne), pas sur le terminal de caisse.'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('borne-actif')));
      await t.pump();
      await app.defilerJusqua(t, find.byKey(const ValueKey('borne-login')));
      await t.enterText(find.byKey(const ValueKey('borne-login')), _loginBorne);
      await t.enterText(find.byKey(const ValueKey('borne-mdp')), _mdpBorne);
      FocusManager.instance.primaryFocus?.unfocus();
      await app.attendre(t, const Duration(milliseconds: 300));

      // « Tester la borne » : connexion de l'utilisateur borne et produits, sans toucher la session de l'appli.
      final sessionAppli = app.serveur.derniereSession;
      await app.defilerJusqua(t, find.byKey(const ValueKey('borne-tester')));
      await t.tap(find.byKey(const ValueKey('borne-tester')));
      expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-diagnostic-conclusion'))), isTrue);
      expect(find.text('La borne est prête : elle se connecte et trouve des produits.'), findsOneWidget);
      expect(find.textContaining('produit pour la catégorie « Douleur »'), findsOneWidget);
      expect(app.serveur.sessions, contains(sessionAppli), reason: 'session de l\'administrateur intacte');
      expect(secrets.valeur, _mdpBorne, reason: 'mot de passe enregistré (stockage sûr)');
      await t.tap(find.byKey(const ValueKey('borne-diagnostic-fermer')));
      await app.attendre(t, const Duration(milliseconds: 500));

      // Ouvrir la borne : épinglée, données affichées (catégorie Douleur → DOLIPRANE).
      await app.defilerJusqua(t, find.byKey(const ValueKey('borne-ouvrir')));
      await t.tap(find.byKey(const ValueKey('borne-ouvrir')));
      expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-accueil-texte'))), isTrue);
      await app.attendre(t, const Duration(seconds: 1));
      expect(kiosque.demarrages, 1, reason: 'épinglage');
      expect(BorneReglages.courant.value.actif, isTrue);
      await t.tap(find.byKey(const ValueKey('borne-categorie-Douleur')));
      expect(await app.attendreQue(t, find.text(nomEcran(_doli))), isTrue, reason: 'la borne affiche les produits');
      expect(find.text(BorneScreen.indisponibleTitre), findsNothing);

      // Quitter le mode borne : cadenas 2 s → confirmation → code administrateur.
      final cadenas = find.byKey(const ValueKey('borne-sortie'));
      expect(cadenas.hitTestable(), findsOneWidget);
      await _appuiLong(t, cadenas);
      expect(find.byKey(const ValueKey('sortie-kiosque-confirmer')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('sortie-kiosque-confirmer')));
      await app.attendre(t, const Duration(milliseconds: 500));
      final demandes = code.demandes;
      await _saisirCode(t, app, '4827');
      expect(code.demandes, demandes + 1);
      expect(await app.attendreQue(t, find.byType(LoginScreen)), isTrue, reason: 'retour à l\'écran de connexion');
      expect(find.byType(BorneScreen), findsNothing);
      expect(kiosque.arrets, 1, reason: 'désépinglage');
      expect(kiosque.epingle, isFalse);
      expect(BorneReglages.courant.value.actif, isFalse, reason: 'mode borne désactivé sur cet appareil');
      expect(BorneReglages.courant.value.login, _loginBorne, reason: 'autres réglages de la borne gardés');
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('borne_config_v1')!)['actif'], isFalse);
      expect(BorneLauncher.auDemarrage, isFalse, reason: 'la borne ne se rouvre plus au démarrage');
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('borne sans données (mot de passe refusé) : cause affichée, sortie possible depuis « indisponible »', (t) async {
      TailleEcran.telephone360x800.appliquer(t);
      _installerCode();
      final kiosque = _installerKiosque();
      _installerSecrets('mauvais');
      final app = _app();
      await app.preparer(prefs: _prefsBorneActive());
      await app.lancer(t);
      // Démarrage : la borne s'ouvre directement (mode actif), la connexion de l'utilisateur borne est refusée.
      expect(await app.attendreQue(t, find.text(BorneScreen.indisponibleTitre)), isTrue);
      await app.attendre(t, const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('borne-motif')), findsOneWidget);
      expect(find.textContaining('Connexion refusée pour l\'utilisateur borne « $_loginBorne »'), findsOneWidget);
      expect(find.textContaining('Identifiants incorrects'), findsOneWidget);
      expect(kiosque.demarrages, 1);
      // Sortie depuis l'écran « indisponible » (cadenas « Quitter le mode borne »).
      await _appuiLong(t, find.byKey(const ValueKey('borne-sortie')));
      await t.tap(find.byKey(const ValueKey('sortie-kiosque-confirmer')));
      await app.attendre(t, const Duration(milliseconds: 500));
      await _saisirCode(t, app, '4827');
      expect(await app.attendreQue(t, find.byType(LoginScreen)), isTrue);
      expect(kiosque.arrets, 1);
      expect(BorneReglages.courant.value.actif, isFalse);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('utilisateur borne non configuré / mot de passe absent : message clair', (t) async {
      expect(motifConnexionBorne(login: '', motDePasse: true), startsWith('Utilisateur borne non configuré'));
      expect(motifConnexionBorne(login: 'b', motDePasse: false), contains('Mot de passe de l\'utilisateur borne « b » absent'));
      TailleEcran.telephone360x800.appliquer(t);
      _installerCode();
      _installerKiosque();
      _installerSecrets(); // stockage sûr vidé (réinstallation, sauvegarde restaurée…)
      final app = _app();
      await app.preparer(prefs: _prefsBorneActive());
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-motif'))), isTrue);
      expect(find.textContaining('Mot de passe de l\'utilisateur borne « $_loginBorne » absent'), findsOneWidget);
      expect(app.serveur.recuesSur('/user/auth'), isEmpty, reason: 'rien n\'est envoyé sans mot de passe');
      await app.fermer(t);
    });

    testWidgets('session de l\'utilisateur borne expirée : la borne reconnecte SON utilisateur, jamais l\'écran de connexion', (t) async {
      TailleEcran.telephone360x800.appliquer(t);
      _installerCode();
      _installerKiosque();
      _installerSecrets(_mdpBorne);
      final app = _app();
      await app.preparer(prefs: _prefsBorneActive());
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-accueil-texte'))), isTrue);
      await app.attendre(t, const Duration(seconds: 1));
      final connexions = app.serveur.connexions;
      app.serveur.expirerSessions();
      await t.tap(find.byKey(const ValueKey('borne-categorie-Douleur')));
      expect(await app.attendreQue(t, find.text(nomEcran(_doli))), isTrue, reason: 'requête rejouée après reconnexion');
      expect(app.serveur.connexions, connexions + 1);
      final auth = app.serveur.recuesSur('/user/auth').last;
      expect(jsonDecode(auth.corps)['login'], _loginBorne);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(BorneScreen), findsOneWidget);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });

  group('Tester la borne (diagnostic)', () {
    test('étapes : utilisateur, mot de passe, connexion refusée ≠ serveur injoignable, aucun produit', () async {
      final s = MemoireBorneSecrets();
      final d0 = await TesteurBorne(baseUrl: 'http://x', secrets: s).tester(const BorneConfig());
      expect(d0.ok, isFalse);
      expect(d0.conclusion, startsWith('Utilisateur borne non configuré'));
      final d1 = await TesteurBorne(baseUrl: 'http://x', secrets: s).tester(const BorneConfig(login: 'b'));
      expect(d1.conclusion, contains('Mot de passe de l\'utilisateur borne absent'));
    });

    test('faux serveur (vrai HTTP) : connexion refusée, aucun produit pour la catégorie, serveur coupé — causes précises',
        () => avecVraiHttp(() async {
      final s = _app().serveur;
      await s.demarrer();
      addTearDown(s.arreter);
      final base = s.base;
      const c = BorneConfig(actif: true, login: _loginBorne);
      var d = await TesteurBorne(baseUrl: base, secrets: MemoireBorneSecrets('mauvais')).tester(c);
      expect(d.ok, isFalse);
      expect(d.conclusion, allOf(contains('Connexion refusée pour « $_loginBorne »'), contains('Identifiants incorrects')));
      d = await TesteurBorne(baseUrl: base, secrets: MemoireBorneSecrets(_mdpBorne))
          .tester(c.copyWith(categories: const [BorneCategorie('Rien', 'ZZZZ')], vedettes: const ['3595583', '9999999']));
      expect(d.ok, isFalse);
      expect(d.conclusion, contains('Aucun produit trouvé pour la catégorie « Rien »'));
      expect(d.etapes.last.detail, 'Introuvable : 9999999.');
      expect(s.recuesSur('/user/logout'), isNotEmpty, reason: 'session d\'essai fermée');
      d = await TesteurBorne(baseUrl: base, secrets: MemoireBorneSecrets(_mdpBorne)).tester(c);
      expect(d.ok, isTrue, reason: d.etapes.join('\n'));
      await s.couper();
      d = await TesteurBorne(baseUrl: base, secrets: MemoireBorneSecrets(_mdpBorne)).tester(c);
      expect(d.conclusion, startsWith('Serveur injoignable'));
    }));
  });
}

/// Nom tel qu'affiché par la borne (gluon invisible après « / »).
String nomEcran(String nom) => nom.replaceAll('/', '/⁠');
