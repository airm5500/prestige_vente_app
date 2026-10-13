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

import 'outils/faux_serveur_prestige.dart';

/// Fichiers de test volontairement hors de la CI (outil manuel), avec la raison.
const _horsCI = {
  'test/outils/apercus_connexion_test.dart': 'génère des aperçus PNG (APERCUS=1), jamais en CI',
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
  });
}
