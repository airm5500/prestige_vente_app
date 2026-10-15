// PrestigePOS 1.1.0 — démarrage automatique de la borne avec l'appareil (coupure de courant, redémarrage) :
//  - unitaires : réglage désactivé par défaut, activation / désactivation, « Revenir à Android », état et conseils
//    selon la version d'Android, aucune exception si Android refuse ;
//  - intégration : canal « prestigepos/demarrage » (noms des méthodes et arguments reçus par Android) ;
//  - construction : alias d'accueil DÉSACTIVÉ par défaut, récepteurs et permission dans la saveur pos SEULEMENT
//    (Prestige Mobile inchangé) ;
//  - e2e : Administration (après le code administrateur) › Démarrage automatique ; appareil redémarré → borne
//    ouverte directement en kiosque ; sans licence → la borne ne travaille pas ; serveur pas encore joignable au
//    démarrage (réseau) → « momentanément indisponible » puis reprise ;
//  - ergonomie : page aux 5 appareils × texte ×1,0 / ×1,3.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/prestigepos/demarrage_auto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/pos_e2e.dart';
import 'pos_e2e_test.dart' show attendreBorne;
import 'pos_ergonomie_test.dart' show appareils, controler;

String _lire(String f) => File(f).readAsStringSync();

/// Administration : fait défiler la liste jusqu'à l'entrée [cle] (petits écrans : liste construite à la demande).
Future<void> _versEntree(WidgetTester t, String cle) async {
  await t.scrollUntilVisible(find.byKey(ValueKey(cle)), 200, scrollable: find.byType(Scrollable).first);
  await t.pump();
}

void main() {
  group('unitaires', () {
    late DemarrageSimule android;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      android = DemarrageSimule();
      DemarrageAuto.plateforme = android;
      DemarrageAuto.courant.value = const EtatDemarrage();
    });
    tearDown(() => DemarrageAuto.plateforme = CanalDemarrage());

    test('désactivé par défaut ; activation gardée et transmise à Android ; « Revenir à Android » désactive', () async {
      expect((await DemarrageAuto.lire()).actif, isFalse);
      final e = await DemarrageAuto.activer(true);
      expect(e.actif, isTrue);
      expect(e.accueilPropose, isTrue);
      expect((await SharedPreferences.getInstance()).getBool(DemarrageAuto.cle), isTrue);
      expect(e.conseil, contains('application d\'accueil'));
      expect(e.fiable, isFalse, reason: 'Android 13 sans accueil par défaut ni propriétaire');
      await DemarrageAuto.ouvrirChoixAccueil();
      final e2 = await DemarrageAuto.lire();
      expect(e2.accueilParDefaut, isTrue);
      expect(e2.fiable, isTrue);
      expect(e2.conseil, isEmpty);
      await DemarrageAuto.revenirAndroid();
      expect(DemarrageAuto.courant.value.actif, isFalse);
      expect(DemarrageAuto.courant.value.accueilPropose, isFalse);
      expect(android.appels, ['activer:true', 'ouvrirChoixAccueil', 'activer:false', 'revenirAndroid']);
    });

    test('état et conseil selon Android : 9 et moins (récepteur de démarrage), propriétaire de l\'appareil', () {
      expect(EtatDemarrage.depuis(const {'api': 28}, actif: true).fiable, isTrue);
      expect(EtatDemarrage.depuis(const {'api': 28}, actif: true).conseil, contains('Android 9'));
      expect(EtatDemarrage.depuis(const {'api': 34, 'proprietaire': true}, actif: true).fiable, isTrue);
      expect(EtatDemarrage.depuis(const {'api': 34}, actif: false).fiable, isFalse);
      expect(EtatDemarrage.depuis(null, actif: true).api, 0);
    });

    test('retirer le propriétaire de l\'appareil : état relu', () async {
      android.proprietaire = true;
      expect((await DemarrageAuto.lire()).proprietaire, isTrue);
      expect((await DemarrageAuto.retirerProprietaire()).proprietaire, isFalse);
      expect(android.appels, ['retirerProprietaire']);
    });

    test('synchronisation au lancement : Android remis d\'accord avec le réglage', () async {
      SharedPreferences.setMockInitialValues({DemarrageAuto.cle: true});
      await DemarrageAuto.synchroniser();
      expect(android.appels, ['activer:true']);
      expect(DemarrageAuto.courant.value.actif, isTrue);
    });

    test('Android refuse (erreur du canal) : aucune exception, réglage gardé', () async {
      DemarrageAuto.plateforme = _Panne();
      final e = await DemarrageAuto.activer(true);
      expect(e.actif, isTrue);
      await DemarrageAuto.revenirAndroid();
      await DemarrageAuto.ouvrirChoixAccueil();
      await DemarrageAuto.retirerProprietaire();
      expect((await DemarrageAuto.lire()).actif, isFalse);
    });
  });

  group('intégration : canal Android « prestigepos/demarrage »', () {
    testWidgets('méthodes et arguments', (t) async {
      final recus = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(CanalDemarrage.canal, (c) async {
        recus.add('${c.method}${c.arguments == null ? '' : ' ${c.arguments}'}');
        return c.method == 'etat' ? {'accueilPropose': true, 'accueilParDefaut': true, 'proprietaire': false, 'api': 30} : true;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(CanalDemarrage.canal, null));
      SharedPreferences.setMockInitialValues({});
      DemarrageAuto.plateforme = CanalDemarrage();
      final e = await DemarrageAuto.activer(true);
      expect(e.accueilParDefaut, isTrue);
      expect(e.api, 30);
      await DemarrageAuto.ouvrirChoixAccueil();
      await DemarrageAuto.revenirAndroid();
      expect(recus, ['activer {actif: true}', 'etat', 'ouvrirChoixAccueil', 'activer {actif: false}', 'etat', 'revenirAndroid']);
    });
  });

  group('construction : saveur pos seulement, accueil désactivé par défaut', () {
    test('manifeste pos : alias HOME désactivé, récepteurs, permission de démarrage ; Prestige Mobile sans', () {
      final pos = _lire('android/app/src/pos/AndroidManifest.xml');
      final main = _lire('android/app/src/main/AndroidManifest.xml');
      final alias = RegExp(r'<activity-alias[\s\S]*?</activity-alias>').firstMatch(pos)!.group(0)!;
      expect(alias, contains('android:name="com.dici.prestigepos.AccueilBorne"'));
      expect(alias, contains('android:enabled="false"'), reason: 'jamais accueil sans le réglage');
      expect(alias, contains('android.intent.category.HOME'));
      expect(pos, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
      expect(pos, contains('com.dici.prestigepos.DemarrageReceiver'));
      expect(pos, contains('android.intent.action.BOOT_COMPLETED'));
      expect(pos, contains('com.dici.prestigepos.PosAdminReceiver'));
      expect(pos, contains('android.permission.BIND_DEVICE_ADMIN'));
      expect(pos, contains('android:lockTaskMode="if_whitelisted"'));
      for (final x in ['RECEIVE_BOOT_COMPLETED', 'category.HOME', 'BOOT_COMPLETED', 'DEVICE_ADMIN', 'BIND_DEVICE_ADMIN']) {
        expect(main, isNot(contains(x)), reason: 'Prestige Mobile inchangé : $x');
      }
      final admin = _lire('android/app/src/pos/res/xml/prestigepos_admin.xml');
      expect(admin, contains('<uses-policies />'), reason: 'aucune politique (ni effacement, ni mot de passe)');
      for (final f in ['DemarrageBridge.kt', 'DemarrageReceiver.kt', 'PosAdminReceiver.kt']) {
        expect(File('android/app/src/pos/kotlin/com/dici/prestigepos/$f').existsSync(), isTrue, reason: f);
      }
      expect(Directory('android/app/src/main/kotlin').listSync(recursive: true).where((f) => f.path.contains('Demarrage')), isEmpty);
      final bridge = _lire('android/app/src/pos/kotlin/com/dici/prestigepos/DemarrageBridge.kt');
      expect(bridge, contains('"prestigepos/demarrage"'));
      expect(bridge, contains('stopLockTask'), reason: 'sortie vers Android : verrouillage arrêté');
      expect(bridge, contains('COMPONENT_ENABLED_STATE_DISABLED'), reason: 'sortie : PrestigePOS n\'est plus l\'accueil');
      expect(pos, isNot(contains('android.intent.action.LOCKED_BOOT_COMPLETED')), reason: 'réglages chiffrés illisibles avant le déverrouillage');
    });
  });

  group('e2e', () {
    testWidgets('Administration (code administrateur) › Démarrage automatique : activer, choisir l\'accueil, revenir à Android', (t) async {
      t.view.physicalSize = const Size(1200, 1920);
      t.view.devicePixelRatio = 1.5;
      addTearDown(t.view.reset);
      final app = PosE2E();
      await app.preparer(configure: true);
      await app.lancer(t);
      await attendreBorne(t, app);
      await app.quitterBorne(t); // cadenas 2 s, confirmation, code administrateur
      expect(await app.attendreQue(t, find.byKey(const ValueKey('pos-admin'))), isTrue);
      await _versEntree(t, 'pos-admin-demarrage');
      expect(find.text('Désactivé'), findsOneWidget, reason: 'désactivé par défaut');
      await app.toucher(t, 'pos-admin-demarrage');
      expect(find.byKey(const ValueKey('pos-demarrage-page')), findsOneWidget);
      expect(t.widget<SwitchListTile>(find.byKey(const ValueKey('pos-demarrage-auto'))).value, isFalse);
      await app.toucher(t, 'pos-demarrage-auto');
      expect(t.widget<SwitchListTile>(find.byKey(const ValueKey('pos-demarrage-auto'))).value, isTrue);
      expect(find.byKey(const ValueKey('pos-demarrage-conseil')), findsOneWidget);
      expect(find.byKey(const ValueKey('pos-demarrage-accueil-non')), findsOneWidget);
      await app.toucher(t, 'pos-demarrage-choisir-accueil');
      // Retour de l'écran d'Android : état relu.
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await app.attendre(t, const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('pos-demarrage-accueil-oui')), findsOneWidget);
      expect(find.byKey(const ValueKey('pos-demarrage-conseil')), findsNothing);
      expect((await SharedPreferences.getInstance()).getBool(DemarrageAuto.cle), isTrue);
      await app.toucher(t, 'pos-demarrage-android');
      expect(app.demarrage.appels, containsAllInOrder(['activer:true', 'ouvrirChoixAccueil', 'activer:false', 'revenirAndroid']));
      expect((await SharedPreferences.getInstance()).getBool(DemarrageAuto.cle), isFalse);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('« Revenir à Android » directement depuis l\'Administration', (t) async {
      t.view.physicalSize = const Size(720, 1440);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final app = PosE2E();
      await app.preparer(configure: true, prefs: {DemarrageAuto.cle: true});
      await app.lancer(t);
      await attendreBorne(t, app);
      await app.quitterBorne(t);
      await _versEntree(t, 'pos-admin-android');
      expect(find.textContaining('Activé'), findsOneWidget);
      await app.toucher(t, 'pos-admin-android');
      expect(app.demarrage.appels.last, 'revenirAndroid');
      expect((await SharedPreferences.getInstance()).getBool(DemarrageAuto.cle), isFalse);
      await app.fermer(t);
    });

    testWidgets('appareil redémarré (réglage actif) : borne ouverte directement en kiosque, sans assistant ni confirmation', (t) async {
      t.view.physicalSize = const Size(1080, 1920);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final app = PosE2E();
      await app.preparer(configure: true, prefs: {DemarrageAuto.cle: true});
      await app.lancer(t);
      await attendreBorne(t, app);
      expect(app.kiosque.demarrages, 1, reason: 'verrouillage demandé à l\'ouverture');
      expect(find.byKey(const ValueKey('pos-bienvenue')), findsNothing);
      expect(app.demarrage.appels.first, 'activer:true', reason: 'Android remis d\'accord au lancement');
      await app.fermer(t);
    });

    testWidgets('redémarrage sans licence valide : la borne ne travaille pas (écran de licence)', (t) async {
      final app = PosE2E();
      await app.preparer(configure: true, prefs: {DemarrageAuto.cle: true});
      app.serveur.licence = const ReponseLocale('');
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byKey(const ValueKey('pos-licence'))), isTrue);
      expect(find.byKey(const ValueKey('borne-recherche')), findsNothing);
      expect(app.kiosque.demarrages, 0);
      await app.fermer(t);
    });

    testWidgets('réseau : serveur pas encore joignable au démarrage (box qui redémarre) → indisponible puis reprise seule', (t) async {
      final app = PosE2E();
      await app.preparer(configure: true, prefs: {DemarrageAuto.cle: true});
      await app.serveur.couper();
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-indisponible')), max: const Duration(seconds: 60)), isTrue);
      await app.serveur.retablir();
      expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-recherche')), max: const Duration(seconds: 90)), isTrue);
      await app.fermer(t);
    });
  });

  group('ergonomie : page « Démarrage automatique »', () {
    for (final a in appareils) {
      for (final texte in [1.0, 1.3]) {
        testWidgets('${a.nom}, texte ×$texte', (t) async {
          t.view.physicalSize = a.pixels;
          t.view.devicePixelRatio = a.densite;
          t.platformDispatcher.textScaleFactorTestValue = texte;
          addTearDown(t.view.reset);
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          final app = PosE2E();
          await app.preparer(configure: true, prefs: {DemarrageAuto.cle: true});
          await app.lancer(t);
          await attendreBorne(t, app);
          await app.quitterBorne(t);
          await _versEntree(t, 'pos-admin-android');
          await controler(t, 'Administration (démarrage automatique)');
          await app.toucher(t, 'pos-admin-demarrage');
          await controler(t, 'Démarrage automatique');
          await app.fermer(t);
        });
      }
    }
  });
}

class _Panne implements PlateformeDemarrage {
  @override
  Future<void> retirerProprietaire() async => throw PlatformException(code: 'DEMARRAGE');
  @override
  Future<Map<Object?, Object?>?> etat() async => throw PlatformException(code: 'DEMARRAGE');
  @override
  Future<void> activer(bool actif) async => throw PlatformException(code: 'DEMARRAGE');
  @override
  Future<void> ouvrirChoixAccueil() async => throw PlatformException(code: 'DEMARRAGE');
  @override
  Future<void> revenirAndroid() async => throw PlatformException(code: 'DEMARRAGE');
}
