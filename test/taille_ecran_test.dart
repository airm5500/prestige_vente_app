// TAILLE DE L'ÉCRAN (4.0.1) — module repris de Prestige Inventaire (lib/ui/taille_ecran.dart, docs/TAILLE_ECRAN.md).
//
// Unitaires : facteurs Automatique / Compact / Très compact ; seuil « petit écran » (côté long < 740 dp ou côté
// court < 340 dp) calibré sur le parc (Sunmi V2s 360 × 720 dp → Compact, Sunmi V3 / V3H / V3mix 360 × 640 dp →
// Compact, téléphones 1080 × 2400 → taille normale, tablettes → normale) ; choix manuel prioritaire ; persistance
// (prochain lancement, valeur abîmée) ; données d'écran ramenées à l'échelle (taille, marges, clavier, densité).
// Compatibilité propre à Prestige Mobile :
//   - impression Sunmi : le ticket est fait de commandes texte / QR / code-barres de l'imprimante ; aucun code
//     d'impression ne lit la taille de l'écran ni la densité (garde-fou sur les sources) ;
//   - caméra : le cadre de capture (DataMatrix, ordonnance) est calculé en proportions de l'aperçu, donc la zone
//     découpée dans la photo est la même à toutes les tailles ; les photos gardent la résolution du capteur ;
//   - touchers : justes à travers la réduction ; clavier système : viewInsets ramenés à l'échelle ;
//   - images des produits : taille de décodage = dp × densité effective = pixels réels.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/services/capture/capture_geometry.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart';
import 'package:shared_preferences/shared_preferences.dart';

Size _dp(double l, double h, double densite) => Size(l / densite, h / densite);

void main() {
  tearDown(TailleEcranReglage.reinitialiser);

  group('Facteurs et données d\'écran', () {
    test('Automatique 1,0 ; Compact 0,9 ; Très compact 0,8 (mêmes que Prestige Inventaire)', () {
      expect(TailleEcran.values.map((t) => t.facteur), [1.0, 0.9, 0.8]);
      expect(TailleEcran.values.map((t) => t.libelle), ['Automatique', 'Compact', 'Très compact']);
      expect(TailleEcranReglage.cle, 'taille_ecran_v1');
    });

    test('données d\'écran ramenées à l\'échelle (taille, marges, clavier, densité)', () {
      const mq = MediaQueryData(
        size: Size(360, 720),
        devicePixelRatio: 2,
        padding: EdgeInsets.only(top: 24),
        viewPadding: EdgeInsets.only(top: 24),
        viewInsets: EdgeInsets.only(bottom: 288),
      );
      expect(EchelleInterface.donnees(mq, 1.0), same(mq), reason: 'Automatique hors petit écran : rien ne change');
      final c = EchelleInterface.donnees(mq, 0.9);
      expect(c.size.width, closeTo(400, 1e-9));
      expect(c.size.height, closeTo(800, 1e-9));
      expect(c.devicePixelRatio, closeTo(1.8, 1e-9));
      final tc = EchelleInterface.donnees(mq, 0.8);
      expect(tc.size, const Size(450, 900));
      expect(tc.devicePixelRatio, closeTo(1.6, 1e-9));
      expect(tc.padding.top, 30);
      expect(tc.viewInsets.bottom, 360, reason: 'clavier de 288 dp réels = 360 dp de l\'interface, réduits ensuite : 288 dp réels');
    });

    test('images des produits : dp × densité effective = pixels réels (décodage ni flou ni surdimensionné)', () {
      const mq = MediaQueryData(size: Size(360, 720), devicePixelRatio: 2);
      for (final t in TailleEcran.values) {
        final interne = EchelleInterface.donnees(mq, t.facteur);
        // Une vignette de 56 dp de l'interface occupe 56 × facteur dp réels, soit 56 × facteur × 2 pixels.
        expect(56 * interne.devicePixelRatio, closeTo(56 * t.facteur * 2, 1e-9));
      }
    });
  });

  group('Petit écran : Automatique → Compact', () {
    final petits = <String, Size>{
      'Sunmi V2s 720×1440, ×2 (360 × 720 dp)': _dp(720, 1440, 2),
      'Sunmi V2s sans barre de navigation (360 × 672 dp)': const Size(360, 672),
      'Sunmi V2s couché (720 × 360 dp)': _dp(1440, 720, 2),
      'Sunmi V3 / V3H / V3mix 1080×1920, ×3 (360 × 640 dp)': _dp(1080, 1920, 3),
      'Sunmi V3 1080×1920, ×2,625 (411 × 731 dp)': _dp(1080, 1920, 2.625),
      'téléphone 720×1280, ×2 (360 × 640 dp)': _dp(720, 1280, 2),
      'téléphone très étroit 320 × 800 dp': const Size(320, 800),
    };
    final normaux = <String, Size>{
      'téléphone 1080×2400, ×2,625 (411 × 914 dp)': _dp(1080, 2400, 2.625),
      'téléphone 1080×2400 couché': _dp(2400, 1080, 2.625),
      'téléphone 1080×2400, ×2,75 (393 × 873 dp)': _dp(1080, 2400, 2.75),
      'téléphone 1080×2400, ×3 (360 × 800 dp, Samsung)': _dp(1080, 2400, 3),
      'téléphone 1080×2400, ×3, sans barre de navigation (360 × 752 dp)': const Size(360, 752),
      'téléphone 1080×2340, ×2,75 (393 × 851 dp)': _dp(1080, 2340, 2.75),
      'tablette 1920×1200, ×1,5': _dp(1920, 1200, 1.5),
      'tablette 800 × 1280 dp': const Size(800, 1280),
    };
    for (final e in petits.entries) {
      test('petit : ${e.key}', () {
        expect(TailleEcranReglage.petitEcran(e.value), isTrue);
        expect(TailleEcranReglage.effective(TailleEcran.automatique, e.value), TailleEcran.compact);
      });
    }
    for (final e in normaux.entries) {
      test('normal : ${e.key}', () {
        expect(TailleEcranReglage.petitEcran(e.value), isFalse);
        expect(TailleEcranReglage.effective(TailleEcran.automatique, e.value), TailleEcran.automatique);
      });
    }

    test('seuils exacts : côté long 740 dp, côté court 340 dp (limites incluses = taille normale)', () {
      expect(TailleEcranReglage.petitEcran(const Size(360, 739.9)), isTrue);
      expect(TailleEcranReglage.petitEcran(const Size(360, 740)), isFalse);
      expect(TailleEcranReglage.petitEcran(const Size(339.9, 900)), isTrue);
      expect(TailleEcranReglage.petitEcran(const Size(340, 900)), isFalse);
      expect(TailleEcranReglage.petitEcran(Size.zero), isFalse, reason: 'taille inconnue : rien d\'imposé');
    });

    test('le choix manuel est prioritaire (petit écran, téléphone, tablette)', () {
      for (final ecran in [_dp(720, 1440, 2), _dp(1080, 1920, 3), _dp(1080, 2400, 2.625), _dp(1920, 1200, 1.5)]) {
        expect(TailleEcranReglage.effective(TailleEcran.compact, ecran), TailleEcran.compact);
        expect(TailleEcranReglage.effective(TailleEcran.tresCompact, ecran), TailleEcran.tresCompact);
      }
    });
  });

  group('Persistance', () {
    test('réglage mémorisé, appliqué au prochain lancement ; « Relancer maintenant » l\'applique', () async {
      SharedPreferences.setMockInitialValues({});
      await TailleEcranReglage.charger();
      expect(TailleEcranReglage.active.value, TailleEcran.automatique, reason: 'défaut');
      await TailleEcranReglage.enregistrer(TailleEcran.tresCompact);
      expect((await SharedPreferences.getInstance()).getString(TailleEcranReglage.cle), 'tresCompact');
      expect(TailleEcranReglage.active.value, TailleEcran.automatique, reason: 'appliqué au prochain lancement');
      expect(TailleEcranReglage.enAttente, isTrue);
      await TailleEcranReglage.charger(); // nouveau lancement
      expect(TailleEcranReglage.active.value, TailleEcran.tresCompact);
      expect(TailleEcranReglage.enAttente, isFalse);
      await TailleEcranReglage.enregistrer(TailleEcran.compact);
      TailleEcranReglage.appliquerMaintenant();
      expect(TailleEcranReglage.active.value, TailleEcran.compact);
    });

    test('valeur abîmée ou inconnue : Automatique', () async {
      SharedPreferences.setMockInitialValues({TailleEcranReglage.cle: 'inconnue'});
      await TailleEcranReglage.charger();
      expect(TailleEcranReglage.active.value, TailleEcran.automatique);
      expect(TailleEcranReglage.depuisNom(null), TailleEcran.automatique);
      expect(TailleEcranReglage.depuisNom('compact'), TailleEcran.compact);
    });
  });

  group('Interface réduite', () {
    testWidgets('touchers justes à travers la réduction (Très compact, Sunmi V2s)', (t) async {
      t.view.physicalSize = const Size(720, 1440);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      var touches = 0;
      await t.pumpWidget(EchelleInterface(
        facteur: 0.8,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: SizedBox(width: 60, height: 60, child: ElevatedButton(key: const Key('b'), onPressed: () => touches++, child: const Text('OK'))),
            ),
          ),
        ),
      ));
      final r = t.getRect(find.byKey(const Key('b')));
      expect(r.width, closeTo(48, 0.01), reason: '60 dp de l\'interface = 48 dp réels');
      expect(r.right, closeTo(360, 0.01));
      expect(r.bottom, closeTo(720, 0.01));
      expect(MediaQuery.sizeOf(t.element(find.byKey(const Key('b')))), const Size(450, 900));
      await t.tapAt(r.center);
      expect(touches, 1);
      await t.tapAt(r.topLeft - const Offset(4, 4)); // juste à côté : rien
      expect(touches, 1);
    });

    testWidgets('clavier système : champ posé au-dessus du clavier réel (Compact)', (t) async {
      t.view.physicalSize = const Size(720, 1440);
      t.view.devicePixelRatio = 2;
      t.view.viewInsets = const FakeViewPadding(bottom: 600); // 300 dp réels
      addTearDown(t.view.reset);
      await t.pumpWidget(const EchelleInterface(
        facteur: 0.9,
        child: MaterialApp(home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: TextField(key: Key('champ'))))),
      ));
      final r = t.getRect(find.byKey(const Key('champ')));
      expect(r.bottom, closeTo(720 - 300, 0.5), reason: 'bas du champ = haut du clavier, en dp réels');
    });

    testWidgets('RacineTailleEcran : Automatique → Compact sur un V2s, taille normale sur un téléphone 1080×2400', (t) async {
      Future<Size> surface(Size px, double densite, TailleEcran reglage) async {
        t.view.physicalSize = px;
        t.view.devicePixelRatio = densite;
        TailleEcranReglage.enregistree = reglage;
        TailleEcranReglage.appliquerMaintenant();
        await t.pumpWidget(RacineTailleEcran(child: MaterialApp(home: Builder(builder: (c) => Text('${MediaQuery.sizeOf(c)}', key: const Key('s'))))));
        return MediaQuery.sizeOf(t.element(find.byKey(const Key('s'))));
      }

      addTearDown(t.view.reset);
      final v2s = await surface(const Size(720, 1440), 2, TailleEcran.automatique);
      expect(v2s.width, closeTo(400, 0.01));
      expect(v2s.height, closeTo(800, 0.01));
      final v3 = await surface(const Size(1080, 1920), 3, TailleEcran.automatique);
      expect(v3.width, closeTo(400, 0.01));
      final tel = await surface(const Size(1080, 2400), 2.625, TailleEcran.automatique);
      expect(tel, _dp(1080, 2400, 2.625), reason: 'téléphone courant : rien ne change');
      final samsung = await surface(const Size(1080, 2400), 3, TailleEcran.automatique);
      expect(samsung, const Size(360, 800), reason: 'Samsung 360 × 800 dp : taille normale');
      final tablette = await surface(const Size(1920, 1200), 1.5, TailleEcran.automatique);
      expect(tablette, const Size(1280, 800));
      final manuel = await surface(const Size(1080, 2400), 2.625, TailleEcran.tresCompact);
      expect(manuel.width, closeTo(1080 / 2.625 / 0.8, 0.01), reason: 'choix manuel prioritaire');
    });
  });

  group('Compatibilité Prestige Mobile', () {
    test('impression Sunmi et PDF : aucune dépendance à la taille de l\'écran ni à la densité', () {
      // Le ticket Sunmi est envoyé en commandes (printText / printQRCode / printBarCode / lineWrap) : sa mise en
      // page dépend de la largeur du papier (58 / 80 mm), jamais de l'écran. Les PDF (rapports, ajustements) non
      // plus. Garde-fou : aucune lecture de MediaQuery / View / devicePixelRatio / capture d'écran dans ce code.
      final fichiers = [
        'lib/services/receipt_service.dart',
        'lib/borne/borne_ticket.dart',
        'lib/services/pdf_service.dart',
        'lib/services/pdf_ajustement_service.dart',
      ];
      final interdit = RegExp(r'devicePixelRatio|View\.of|View\.maybeOf|physicalSize|RepaintBoundary|toImage\(|PlatformDispatcher');
      for (final f in fichiers) {
        final src = File(f).readAsStringSync();
        expect(interdit.hasMatch(src), isFalse, reason: '$f dépend de l\'écran : ${interdit.firstMatch(src)?.group(0)}');
      }
      // Les seules lectures de MediaQuery tolérées : l'aperçu à l'écran du ticket (mode test), pas l'impression.
      final ticket = File('lib/services/receipt_service.dart').readAsStringSync();
      expect(ticket.contains('MediaQuery'), isFalse);
      expect(RegExp(r'SunmiPrinter\.printText').allMatches(ticket).length, greaterThan(10));
    });

    test('caméra : zone découpée dans la photo identique à toutes les tailles (cadre en proportions de l\'aperçu)', () {
      const image = Size(3000, 4000); // photo redressée (portrait), résolution du capteur
      const reelle = Size(360, 672); // aperçu plein écran sur un V2s, en dp réels
      for (final page in [false, true]) {
        Rect zone(double f) {
          final vue = reelle / f; // le même aperçu vu par l'interface réduite
          final cadre = page ? CaptureGeometry.pageFrameInView(vue) : CaptureGeometry.frameInView(vue);
          return CaptureGeometry.frameInImage(image: image, view: vue, frame: cadre);
        }

        final ref = zone(1.0);
        for (final t in TailleEcran.values) {
          final z = zone(t.facteur);
          expect((z.left - ref.left).abs() + (z.top - ref.top).abs() + (z.right - ref.right).abs() + (z.bottom - ref.bottom).abs(),
              lessThan(0.5), reason: '${page ? 'ordonnance' : 'étiquette / DataMatrix'}, ${t.libelle}');
        }
      }
    });

    test('pas de vue native Android dans l\'interface (elle ne serait pas réduite)', () {
      final natif = RegExp(r'AndroidView|PlatformViewLink|UiKitView|AndroidViewSurface');
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        expect(natif.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });

    test('une seule MaterialApp, sous RacineTailleEcran (main.dart) ; réglage lu avant runApp', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main.indexOf('TailleEcranReglage.charger()'), lessThan(main.indexOf('runApp(')));
      expect(main.indexOf('RacineTailleEcran('), lessThan(main.indexOf('MaterialApp(')));
      expect(main.indexOf('MultiProvider('), lessThan(main.indexOf('RacineTailleEcran(')), reason: 'providers gardés à la relance');
      final apps = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart') && RegExp(r'\bMaterialApp\(').hasMatch(f.readAsStringSync()));
      // Une MaterialApp par application : Prestige Mobile (main.dart) et Prestige Pointage (saveur pointage, même règle).
      expect(apps.map((f) => f.path.replaceAll('\\', '/')).toSet(), {'lib/main.dart', 'lib/prestigepointage/pointage_app.dart'});
      final pointage = File('lib/prestigepointage/pointage_app.dart').readAsStringSync();
      expect(pointage.indexOf('RacineTailleEcran('), lessThan(pointage.indexOf('MaterialApp(')));
      expect(pointage.indexOf('MultiProvider('), lessThan(pointage.indexOf('RacineTailleEcran(')));
      final mainPointage = File('lib/main_pointage.dart').readAsStringSync();
      expect(mainPointage.indexOf('TailleEcranReglage.charger()'), greaterThan(0));
      expect(mainPointage.indexOf('initialiserPrestigePointage();', mainPointage.indexOf('Future<void> main()')), lessThan(mainPointage.indexOf('runApp(')));
    });
  });
}
