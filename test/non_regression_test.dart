// Non-régression :
//  - garde-fou de la CI : tout fichier test/**/*_test.dart est exécuté par la CI (liste explicite de
//    .github/workflows/build-apk.yml, étape « Tests ») — un test ajouté mais oublié dans la liste ne passerait jamais ;
//  - anomalies corrigées (identifiants dans test/README.md) : elles ne doivent pas revenir.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/horsligne_ui.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_horsligne.dart';
import 'package:prestige_vente_app/reserve/reserve_api.dart';
import 'package:prestige_vente_app/reserve/reserve_models.dart';
import 'package:prestige_vente_app/reserve/reserve_screen.dart';
import 'package:prestige_vente_app/reserve/reserve_widgets.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/connexion/lancement_screen.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/screens/auth/settings_screen.dart';
import 'package:prestige_vente_app/screens/splash_screen.dart';
import 'package:prestige_vente_app/services/search_mode.dart';

import 'outils/app_e2e.dart';

/// Fichiers de test volontairement hors de la CI (outil manuel), avec la raison.
const _horsCI = {
  'test/outils/apercus_connexion_test.dart': 'génère des aperçus PNG (APERCUS=1), jamais en CI',
  'test/outils/captures_borne_test.dart': 'génère les captures PNG de la borne (APERCUS=1), jamais en CI',
};

/// Fichiers listés par l'étape de tests de la CI.
List<String> _listeCI() {
  final lignes = File('.github/workflows/build-apk.yml').readAsLinesSync();
  final l = lignes.where((x) => x.contains('flutter test test/')).toList();
  expect(l, hasLength(1), reason: 'une seule commande « flutter test » attendue dans la CI');
  expect(lignes.indexOf(l.single) + 1, 32, reason: 'commande des tests attendue ligne 32 du workflow (documentée dans test/README.md)');
  return l.single.split('flutter test').last.trim().split(RegExp(r'\s+')).where((x) => x.endsWith('_test.dart')).toList();
}

/// Ratio de contraste WCAG entre deux couleurs opaques.
double _contraste(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('Garde-fou de la CI', () {
    test('tout fichier test/**/*_test.dart est listé ligne 32 de .github/workflows/build-apk.yml', () {
      final liste = _listeCI();
      final presents = Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path.replaceAll('\\', '/'))
          .where((p) => p.endsWith('_test.dart'))
          .map((p) => p.startsWith('test/') ? p : 'test/${p.split('test/').last}')
          .toSet();
      final oublies = presents.difference(liste.toSet()).difference(_horsCI.keys.toSet()).toList()..sort();
      expect(oublies, isEmpty, reason: 'fichiers de test absents de la CI (à ajouter ligne 32) : ${oublies.join(' ')}');
    });

    test('la liste de la CI ne contient ni doublon, ni fichier absent, ni fichier exclu', () {
      final liste = _listeCI();
      expect(liste.length, liste.toSet().length, reason: 'doublons dans la liste de la CI');
      for (final f in liste) {
        expect(File(f).existsSync(), isTrue, reason: '$f listé dans la CI mais introuvable');
        expect(_horsCI.containsKey(f), isFalse, reason: '$f est déclaré hors CI');
      }
      expect(liste, contains('test/non_regression_test.dart'));
    });
  });

  group('Anomalies corrigées', () {
    testWidgets('ANO-01 : la surveillance du serveur démarre au lancement (ping relié APRÈS le démarrage)', (t) async {
      SharedPreferences.setMockInitialValues({});
      final serveur = FauxServeurPrestige()..installerEnMemoire();
      addTearDown(serveur.desinstaller);
      final store = MemoryLocalStore();
      // Comme l'application : surveillance sans ping au démarrage, ping fourni par HorsLigne.bind.
      final hl = HorsLigne(monitor: ServerMonitor(), store: store, sync: CatalogueSync(store: store, occupee: () => false));
      final avant = HorsLigne.instance;
      HorsLigne.instance = hl;
      StockHorsLigne.instance = null;
      PointageRh.instance = null;
      addTearDown(() {
        HorsLigne.instance = avant;
        StockHorsLigne.instance = null;
        PointageRh.instance = null;
      });
      final api = ApiService(baseUrl: serveur.base);
      await t.pumpWidget(Provider<ApiService>.value(
        value: api,
        child: MaterialApp(builder: (c, child) => HorsLigneScope(horsLigne: hl, child: child!), home: const Scaffold(body: Text('Accueil'))),
      ));
      expect(hl.monitor.ping, isNotNull);
      expect(hl.monitor.surveille, isTrue, reason: 'ping toutes les 30 s dès le lancement');
      await t.pump(const Duration(seconds: 31));
      await t.pump();
      expect(hl.monitor.pings, 1);
      expect(serveur.recuesSur('/officine'), isNotEmpty);
      await t.pumpWidget(const SizedBox());
      expect(hl.monitor.surveille, isFalse);
    });

    testWidgets('ANO-04 : boutons « Préparer » / « Voir les suggestions » de la Réserve ≥ 48 dp', (t) async {
      t.view.physicalSize = const Size(720, 1440);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final s = FauxServeurPrestige()
        ..activerModules()
        ..exigerSession = false;
      s.installerEnMemoire();
      addTearDown(s.desinstaller);
      await t.pumpWidget(MaterialApp(home: ReserveScreen(api: ReserveApi(ClientPrestige(() => s.base)))));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final boutons = find.byType(ElevatedButton);
      expect(boutons, findsWidgets);
      for (final b in boutons.evaluate()) {
        expect(b.size!.height, greaterThanOrEqualTo(48), reason: 'bouton de la Réserve < 48 dp');
      }
      expect(find.text('Préparer'), findsWidgets);
      final source = File('lib/reserve/reserve_screen.dart').readAsStringSync();
      expect(source, isNot(contains('SizedBox(height: 44, child: ElevatedButton')), reason: 'cartes de la Réserve revenues à 44 dp');
    });

    test('ANO-05 : bandeau du sens de la Réserve, contraste du texte ≥ 4,5:1 sur son fond teinté', () {
      for (final sens in SensReserve.values) {
        final c = couleurSens(sens);
        final fond = Color.alphaBlend(c.withValues(alpha: 0.08), Colors.white);
        final texte = Color.lerp(c, Colors.black, 0.2)!;
        expect(_contraste(texte, fond), greaterThanOrEqualTo(4.5), reason: '$sens');
      }
      final source = File('lib/reserve/reserve_widgets.dart').readAsStringSync();
      expect(source, contains('Color.lerp(c, Colors.black, 0.2)'), reason: 'texte du bandeau du sens assombri');
    });

    testWidgets('ANO-02 : puce « Début / Contient » : zone tactile ≥ 48 × 48 dp, aspect inchangé (32 dp), bascule', (t) async {
      SearchModePrefs.mode.value = SearchMode.commencePar;
      addTearDown(() => SearchModePrefs.mode.value = SearchMode.commencePar);
      var bascules = 0;
      await t.pumpWidget(MaterialApp(
          // Comme dans la vente et la recherche : suffixe d'un champ placé dans une colonne.
          home: Scaffold(
              body: Column(children: [
            SizedBox(
                width: 320,
                child: TextField(
                    decoration: InputDecoration(
                        suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [SearchModeChip(onToggle: () => bascules++)])))),
          ]))));
      final zone = t.getSize(find.byKey(const ValueKey('recherche-mode')));
      expect(zone.height, greaterThanOrEqualTo(48));
      expect(zone.width, greaterThanOrEqualTo(48));
      // Aspect : la puce décorée (fond, bordure) garde sa hauteur de 32 dp, centrée dans la zone tactile.
      final puce = find.descendant(of: find.byKey(const ValueKey('recherche-mode')), matching: find.byType(DecoratedBox));
      expect(puce, findsOneWidget);
      expect(t.getSize(puce).height, 32);
      expect(t.getCenter(puce), t.getCenter(find.byKey(const ValueKey('recherche-mode'))));
      // Toucher le bord de la zone (hors de la puce visible) bascule aussi.
      final r = t.getRect(find.byKey(const ValueKey('recherche-mode')));
      await t.tapAt(Offset(r.center.dx, r.top + 3));
      expect(bascules, 1);
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    });

    // ANO-08 : au tout premier appel (vérification de la licence), l'adresse est celle des réglages dans les deux
    // interfaces ; sans configuration, le comportement d'origine est conservé.
    const licenceConfiguree = 'http://${FauxServeurPrestige.hoteMemoire}:${FauxServeurPrestige.portMemoire}/prestige/api/v1/licence/find';
    for (final nouvelle in [false, true]) {
      final nom = nouvelle ? 'nouvelle interface' : 'interface d\'origine';
      testWidgets('ANO-08 ($nom) : la 1re requête du démarrage part vers le serveur configuré (jamais localhost)', (t) async {
        TailleEcran.telephone.appliquer(t);
        final app = AppE2E();
        await app.preparer(interfaceNouvelle: nouvelle);
        await app.lancer(t);
        expect(find.byType(nouvelle ? LancementScreen : AncienSplashScreen), findsOneWidget);
        expect(await app.attendreQue(t, find.byType(nouvelle ? ConnexionScreen : AncienLoginScreen)), isTrue);
        expect(app.serveur.tentatives, isNotEmpty);
        expect(app.serveur.tentatives.first.toString(), licenceConfiguree, reason: '1re requête = licence sur le serveur configuré');
        expect(app.serveur.tentatives.where((u) => u.host != FauxServeurPrestige.hoteMemoire), isEmpty, reason: 'aucune requête vers localhost');
        expect(app.serveur.recuesSur('/licence/find'), hasLength(1), reason: 'licence vérifiée une fois, sans « Réessayer »');
        expect(find.text('Serveur injoignable'), findsNothing);
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });

      testWidgets('ANO-08 ($nom) : sans configuration (aucune adresse), Configuration sans aucune requête', (t) async {
        TailleEcran.tablette.appliquer(t);
        final app = AppE2E();
        await app.preparer(interfaceNouvelle: nouvelle, prefs: const {'local_ip': '', 'remote_ip': ''});
        await app.lancer(t);
        if (nouvelle) {
          expect(await app.attendreQue(t, find.byKey(const Key('lancement_premiere'))), isTrue, reason: '« Première utilisation »');
        } else {
          expect(await app.attendreQue(t, find.byType(SettingsScreen)), isTrue, reason: 'Configuration d\'origine');
        }
        expect(app.serveur.tentatives, isEmpty, reason: 'appareil non configuré : aucune requête');
        // F1 (4.0.3) : la ligne « Type de code ticket » de la Configuration d'origine ne déborde plus (elle débordait
        // de ~132 px sur tablette) : plus aucune exception tolérée (test/configuration_origine_test.dart).
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });
    }

    testWidgets('ANO-08 : 1re installation (réglages absents), même adresse par défaut dans les deux interfaces que « Réessayer »', (t) async {
      final premieres = <bool, Uri>{};
      for (final nouvelle in [false, true]) {
        TailleEcran.telephone.appliquer(t);
        final app = AppE2E();
        await app.preparer(interfaceNouvelle: nouvelle);
        // Aucune adresse enregistrée (seul l'interrupteur d'interface est présent).
        SharedPreferences.setMockInitialValues({'interface_nouvelle_version_v1': nouvelle});
        await app.lancer(t);
        await app.attendreQue(t, nouvelle ? find.byKey(const Key('lancement_injoignable')) : find.text('Serveur injoignable'));
        premieres[nouvelle] = app.serveur.tentatives.first; // 1re requête de l'application
        if (!nouvelle) {
          // « Réessayer » de l'écran d'origine : même adresse qu'au premier appel.
          await t.tap(find.text('Réessayer'));
          await app.attendre(t, const Duration(seconds: 3));
          await app.attendreQue(t, find.text('Serveur injoignable'));
          final licences = app.serveur.tentatives.where((u) => u.path.endsWith('/licence/find')).toList();
          expect(licences, hasLength(2));
          expect(licences.last, premieres[false]);
        }
        await app.fermer(t);
      }
      expect(premieres[false]!.host, isNot('localhost'));
      expect(premieres[false], premieres[true], reason: 'même adresse par défaut (réglages) dans les deux interfaces');
      expect(premieres[false]!.path, endsWith('/licence/find'));
    });
  });
}
