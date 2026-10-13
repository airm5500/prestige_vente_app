// Photo de contrôle au pointage par badge (anti « pointage pour un collègue ») :
// - unitaires : réglages, compression, rétention / purge, marquage « sans photo », prise de photo (caméra simulée) ;
// - écrans : terminal de pointage (aperçu + compte à rebours, panne de caméra, annulation, empreinte inchangée),
//   ergonomie aux tailles 720×1440, 1080×1920 et tablette 1920×1200 (sans débordement, textes lisibles, boutons ≥ 48 dp),
//   entrée « Pointage présence » (simple bouton désactivable, photos réservées au gestionnaire), pointage local,
//   Paramètres › Équipe & pointage.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/parametres/parametres_widgets.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/pointage/pointage_logic.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/rh/photo_controle_screen.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/rh/rh_pointage_screen.dart';
import 'package:prestige_vente_app/rh/rh_store.dart';
import 'package:prestige_vente_app/rh/terminal_pointage_screen.dart';
import 'package:prestige_vente_app/screens/pointage/pointage_kiosk_screen.dart';
import 'package:prestige_vente_app/services/nfc_service.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Caméra simulée, serveur et matériel factices
// ---------------------------------------------------------------------------

/// JPEG de test : dégradé (rapide) ou bruit (difficile à compresser).
Uint8List jpegTest(int w, int h, {bool bruit = false, int qualite = 92}) {
  final im = img.Image(width: w, height: h);
  final r = Random(7);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (bruit) {
        im.setPixelRgb(x, y, r.nextInt(256), r.nextInt(256), r.nextInt(256));
      } else {
        im.setPixelRgb(x, y, (x * 255) ~/ w, (y * 255) ~/ h, 128);
      }
    }
  }
  return img.encodeJpg(im, quality: qualite);
}

final Uint8List _photoBrute = jpegTest(960, 720);

class FausseCamera implements CameraControle {
  MotifSansPhoto? echec;
  Object? erreurBrute;
  bool echecCapture = false;
  Duration delaiOuverture = Duration.zero;
  Uint8List image;
  int ouvertures = 0, fermetures = 0, captures = 0;
  FausseCamera({Uint8List? image}) : image = image ?? _photoBrute;

  @override
  Future<SessionCamera> ouvrir() async {
    ouvertures++;
    if (delaiOuverture > Duration.zero) await Future<void>.delayed(delaiOuverture);
    if (erreurBrute != null) throw erreurBrute!;
    if (echec != null) throw CameraIndisponible(echec!);
    return _FausseSession(this);
  }
}

class _FausseSession implements SessionCamera {
  final FausseCamera c;
  _FausseSession(this.c);
  @override
  Widget apercu() => Container(key: const Key('fausse_camera_apercu'), color: Colors.blueGrey);
  @override
  Future<Uint8List> capturer() async {
    c.captures++;
    if (c.echecCapture) throw CameraException('CaptureError', 'capteur');
    return c.image;
  }

  @override
  Future<void> fermer() async => c.fermetures++;
}

class FauxRh implements RhServeur {
  bool offline = false;
  final posts = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> employes = [
    {'id': 'E1', 'matricule': 'M01', 'badge': 'PV12AB34', 'nom': 'KOUASSI', 'prenoms': 'Awa Marie', 'statut': 'ACTIF'},
    {'id': 'E2', 'matricule': 'M02', 'badge': '04A1B2C3', 'nom': 'YAO', 'prenoms': 'Koffi', 'statut': 'ACTIF'},
  ];

  @override
  Future<ReponseRh> get(String chemin, [Map<String, dynamic> query = const {}]) async {
    if (offline) throw const RhHorsLigne();
    return switch (chemin) {
      '/rh/droits' => (status: 200, body: {'success': true}),
      '/rh/employes' => (status: 200, body: {'success': true, 'data': employes}),
      '/rh/presence' => (status: 200, body: {'success': true, 'data': [], 'pointages': []}),
      _ => (status: 404, body: null),
    };
  }

  @override
  Future<ReponseRh> post(String chemin, Map<String, dynamic> corps) async {
    if (offline) throw const RhHorsLigne();
    posts.add(corps);
    return (status: 200, body: {'success': true, 'message': 'Pointage manuel enregistré.'});
  }
}

class FauxNfc implements NfcReader {
  final _tags = StreamController<String>.broadcast();
  void approcher(String uid) => _tags.add(uid);
  @override
  Future<NfcAvailability> availability() async => NfcAvailability.ready;
  @override
  Stream<String> get tags => _tags.stream;
  @override
  Future<bool> start() async => true;
  @override
  Future<void> stop() async {}
  @override
  Future<void> openSettings() async {}
}

class FausseEmpreinte implements FournisseurEmpreinte {
  @override
  Future<bool> disponible() async => true;
  @override
  Future<Uint8List> enroler() async => Uint8List.fromList([1]);
  @override
  Future<int?> identifier(List<Uint8List> modeles) async => 0;
  @override
  Future<void> annuler() async {}
}

final DateTime h0802 = DateTime(2026, 10, 12, 8, 2);

class Env {
  final rh = FauxRh();
  final camera = FausseCamera();
  final nfc = FauxNfc();
  final journal = JournalTerminal(store: MemoryJournalStore());
  final stockage = StockagePhotosMemoire();
  ReglagesPointageTerminal reglages = const ReglagesPointageTerminal();
  bool horsLigne = false;
  bool empreinte = false;
  DateTime now = h0802;
  late final IdentificationEmploye identification = IdentificationEmploye(
      empreinte: empreinte ? FausseEmpreinte() : _SansEmpreinte(), nfc: nfc, coffre: CoffreEmpreintesMemoire());
  late final RegistrePhotosPointage registre =
      RegistrePhotosPointage(stockage: stockage, clock: () => now, journal: () => journal, retentionJours: () async => reglages.retentionJours);
  late final PhotoControle photo = PhotoControle(
    camera: camera,
    registre: registre,
    reglages: () async => reglages,
    compresser: (b) async => compresserPhoto(b),
  );
  late final PointageRh pr = PointageRh(
    store: MemoryRhStore(),
    serveur: rh,
    identification: identification,
    photos: photo,
    clock: () => now,
    horsLigne: () => horsLigne,
    nomTerminal: () => 'Accueil',
    journal: () => journal,
  );

  Future<Env> pret() async {
    await pr.verifierAcces();
    await pr.rafraichirEmployes();
    return this;
  }
}

class _SansEmpreinte implements FournisseurEmpreinte {
  @override
  Future<bool> disponible() async => false;
  @override
  Future<Uint8List> enroler() async => throw const EmpreinteIndisponible();
  @override
  Future<int?> identifier(List<Uint8List> modeles) async => throw const EmpreinteIndisponible();
  @override
  Future<void> annuler() async {}
}

/// Tailles d'écran demandées : 720×1440 et 1080×1920 (densités réalistes), tablette 1920×1200.
const tailles = <(String, Size, double)>[
  ('720×1440', Size(720, 1440), 2.0),
  ('1080×1920', Size(1080, 1920), 2.625),
  ('tablette 1920×1200', Size(1920, 1200), 1.5),
];

void taille(WidgetTester t, Size physique, double densite) {
  t.view.physicalSize = physique;
  t.view.devicePixelRatio = densite;
  addTearDown(t.view.reset);
}

Future<void> pump(WidgetTester t, Widget w) async {
  await t.pumpWidget(MaterialApp(home: KeyedSubtree(key: UniqueKey(), child: w)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

Future<void> lireBadge(WidgetTester t, String code) async {
  await t.enterText(find.byKey(const Key('rh_badge_champ')), code);
  await t.testTextInput.receiveAction(TextInputAction.done);
  await t.pump();
  await t.pump();
}

/// Tous les textes sous [racine] ont une taille lisible (≥ 12).
void textesLisibles(WidgetTester t, Finder racine) {
  for (final r in t.widgetList<RichText>(find.descendant(of: racine, matching: find.byType(RichText)))) {
    final fs = r.text.style?.fontSize ?? 14;
    expect(fs, greaterThanOrEqualTo(12), reason: 'texte trop petit : « ${r.text.toPlainText()} »');
  }
}

/// Bouton ≥ 48 dp de haut (et de large).
void bouton48(WidgetTester t, Key k) {
  final s = t.getSize(find.byKey(k));
  expect(s.height, greaterThanOrEqualTo(48), reason: '$k : hauteur ${s.height}');
  expect(s.width, greaterThanOrEqualTo(48), reason: '$k : largeur ${s.width}');
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PhotoControle.instance = null;
  });

  // =========================================================================
  // Unitaires
  // =========================================================================
  group('Réglages', () {
    test('par défaut : photo activée, simple bouton autorisé (comportement d\'avant), conservation 30 jours', () async {
      final r = await ReglagesPointageTerminal.charger();
      expect(r.photoBadge, isTrue);
      expect(r.simpleBouton, isTrue);
      expect(r.retentionJours, 30);
      expect(const ReglagesPointageTerminal().retentionJours, 30);
    });

    test('enregistrés puis relus ; conservation bornée de 1 à 365 jours', () async {
      await const ReglagesPointageTerminal().copie(photoBadge: false, simpleBouton: false, retentionJours: 7).enregistrer();
      final r = await ReglagesPointageTerminal.charger();
      expect([r.photoBadge, r.simpleBouton, r.retentionJours], [false, false, 7]);
      expect(const ReglagesPointageTerminal().copie(retentionJours: 0).retentionJours, 1);
      expect(const ReglagesPointageTerminal().copie(retentionJours: 5000).retentionJours, 365);
      SharedPreferences.setMockInitialValues({ReglagesPointageTerminal.prefRetention: -3});
      expect((await ReglagesPointageTerminal.charger()).retentionJours, 1);
    });
  });

  group('Compression', () {
    test('grande photo bruitée → JPEG ≤ 640 px et < 100 Ko', () {
      final brut = jpegTest(1600, 1200, bruit: true, qualite: 95);
      expect(brut.length, greaterThan(photoOctetsMax));
      final c = compresserPhoto(brut);
      expect(c.length, lessThan(100 * 1024));
      final d = img.decodeJpg(c)!;
      expect(max(d.width, d.height), lessThanOrEqualTo(640));
      expect(d.width / d.height, closeTo(4 / 3, 0.02));
    });

    test('portrait : le grand côté (hauteur) est ramené à 640 ; petite photo jamais agrandie', () {
      final p = img.decodeJpg(compresserPhoto(jpegTest(720, 1280)))!;
      expect(p.height, 640);
      expect(p.width, 360);
      final s = img.decodeJpg(compresserPhoto(jpegTest(320, 240)))!;
      expect([s.width, s.height], [320, 240]);
    });

    test('photo illisible → FormatException (marquée « sans photo (photo illisible) » par la prise de photo)', () async {
      expect(() => compresserPhoto(Uint8List.fromList([1, 2, 3])), throwsFormatException);
      final cam = FausseCamera(image: Uint8List.fromList([9, 9, 9]));
      final c = CapturePhotoControle(camera: cam, compresser: (b) async => compresserPhoto(b), delaiApercu: const Duration(milliseconds: 20))..lancer();
      final r = await c.resultat;
      expect((r as PhotoAbsente).motif, MotifSansPhoto.photoIllisible);
      c.dispose();
    });
  });

  group('Prise de photo (caméra simulée)', () {
    CapturePhotoControle capture(FausseCamera cam, {Duration ouverture = const Duration(seconds: 2)}) => CapturePhotoControle(
          camera: cam,
          compresser: (b) async => compresserPhoto(b),
          delaiApercu: const Duration(milliseconds: 60),
          delaiOuverture: ouverture,
        )..lancer();

    test('aperçu puis capture automatique : photo compressée, caméra fermée', () async {
      final cam = FausseCamera();
      final c = capture(cam);
      final etats = <EtatCapture>[];
      c.addListener(() => etats.add(c.etat));
      final r = await c.resultat;
      expect(r, isA<PhotoPrise>());
      expect((r as PhotoPrise).jpeg.length, lessThan(photoOctetsMax));
      expect(etats, containsAllInOrder([EtatCapture.apercu, EtatCapture.capture, EtatCapture.prise]));
      expect([cam.ouvertures, cam.captures, cam.fermetures], [1, 1, 1]);
      c.dispose();
    });

    test('pannes → « sans photo (motif) » sans jamais lever d\'erreur', () async {
      for (final (cam, motif) in [
        (FausseCamera()..echec = MotifSansPhoto.cameraAbsente, MotifSansPhoto.cameraAbsente),
        (FausseCamera()..echec = MotifSansPhoto.permissionRefusee, MotifSansPhoto.permissionRefusee),
        (FausseCamera()..erreurBrute = CameraException('CameraAccessDenied', 'refus'), MotifSansPhoto.permissionRefusee),
        (FausseCamera()..erreurBrute = StateError('plugin'), MotifSansPhoto.erreurCamera),
        (FausseCamera()..echecCapture = true, MotifSansPhoto.erreurCamera),
      ]) {
        final c = capture(cam);
        final r = await c.resultat;
        expect((r as PhotoAbsente).motif, motif);
        c.dispose();
      }
    });

    test('caméra trop lente → « caméra trop lente » ; ouverte ensuite, elle est refermée aussitôt', () async {
      final cam = FausseCamera()..delaiOuverture = const Duration(milliseconds: 150);
      final c = capture(cam, ouverture: const Duration(milliseconds: 30));
      expect((await c.resultat as PhotoAbsente).motif, MotifSansPhoto.delaiDepasse);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(cam.fermetures, 1);
      expect(cam.captures, 0);
      c.dispose();
    });

    test('annulation : caméra fermée, aucune photo', () async {
      final cam = FausseCamera();
      final c = CapturePhotoControle(camera: cam, compresser: (b) async => compresserPhoto(b), delaiApercu: const Duration(seconds: 5))..lancer();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.etat, EtatCapture.apercu);
      c.annuler();
      expect(cam.fermetures, 1);
      expect(cam.captures, 0);
      c.dispose();
    });

    test('motifs des erreurs de la caméra Android', () {
      expect(CameraFrontalePlateforme.motifDe(CameraException('CameraAccessDenied', null)), MotifSansPhoto.permissionRefusee);
      expect(CameraFrontalePlateforme.motifDe(CameraException('CameraAccessRestricted', null)), MotifSansPhoto.permissionRefusee);
      expect(CameraFrontalePlateforme.motifDe(CameraException('NoCamera', null)), MotifSansPhoto.cameraAbsente);
      expect(CameraFrontalePlateforme.motifDe(MissingPluginException()), MotifSansPhoto.erreurCamera);
      expect(libelleSansPhoto(MotifSansPhoto.permissionRefusee), 'sans photo (autorisation de la caméra refusée)');
    });
  });

  group('Registre, rétention et marquage « sans photo »', () {
    test('photo liée au pointage ; « sans photo (motif) » signalé (anomalie, journal) ; jamais de photo dans le journal', () async {
      final e = Env();
      final jpeg = compresserPhoto(_photoBrute);
      await e.registre.ajouter(id: 'p1', employeId: 'E1', employeNom: 'KOUASSI Awa', lu: h0802, sens: 'Entrée', moyen: 'Scan du badge', resultat: PhotoPrise(jpeg), envoi: 'envoye');
      await e.registre.ajouter(
          id: 'p2', employeId: 'E2', employeNom: 'YAO Koffi', lu: h0802, sens: 'Entrée', moyen: 'Badge NFC', resultat: const PhotoAbsente(MotifSansPhoto.permissionRefusee));
      expect(await e.registre.image('p1'), jpeg);
      expect(e.registre.photos.map((p) => p.id), containsAll(['p1', 'p2']));
      final p2 = e.registre.photos.firstWhere((p) => p.id == 'p2');
      expect(p2.avecPhoto, isFalse);
      expect(p2.etat, 'sans photo (autorisation de la caméra refusée)');
      expect(e.registre.anomaliesNonTraitees, 1);
      final a = e.registre.anomaliesList.single;
      expect(a.reference, contains('YAO Koffi'));
      expect(a.type, contains('sans photo (autorisation de la caméra refusée)'));
      await e.registre.setTraitee(a.id, true);
      expect(e.registre.anomaliesNonTraitees, 0);
      await e.journal.idle;
      final j = (await e.journal.lire()).map((x) => '${x.action} ${x.motif} ${x.refLocale}').join('\n');
      expect(j, contains('sans photo (autorisation de la caméra refusée)'));
      expect(j, contains('Photo de contrôle prise'));
      expect(j, isNot(contains(base64Encode(jpeg).substring(0, 40))));
      expect(j, isNot(contains('.jpg')));
      expect(j, isNot(contains('photos_pointage')));
    });

    test('purge automatique : au-delà de la durée de conservation (30 j par défaut, paramétrable), fiche ET photo effacées', () async {
      final e = Env();
      final jpeg = compresserPhoto(_photoBrute);
      for (final (id, jours) in [('vieux', 40), ('moyen', 10), ('recent', 1)]) {
        await e.registre.ajouter(id: id, employeId: 'E1', lu: e.now.subtract(Duration(days: jours)), resultat: PhotoPrise(jpeg));
      }
      expect(await e.registre.purger(), 1);
      expect(e.stockage.fiches.keys, unorderedEquals(['moyen', 'recent']));
      expect(e.stockage.images.keys, unorderedEquals(['moyen', 'recent']));
      e.reglages = e.reglages.copie(retentionJours: 7);
      await e.registre.charger();
      expect(e.stockage.fiches.keys, ['recent']);
      expect(e.registre.photos.map((p) => p.id), ['recent']);
      // 30 jours plus tard, avec la durée par défaut.
      e.reglages = const ReglagesPointageTerminal();
      e.now = e.now.add(const Duration(days: 31));
      await e.registre.charger(forcer: true);
      expect(e.stockage.fiches, isEmpty);
      expect(e.stockage.images, isEmpty);
    });

    test('stockage privé (fichiers) : index + JPEG, relecture, purge des fichiers, identifiant dangereux refusé', () async {
      final dir = await Directory.systemTemp.createTemp('photos_pointage_test');
      addTearDown(() => dir.delete(recursive: true));
      final s = StockagePhotosFichiers(() async => Directory('${dir.path}/photos_pointage'));
      final jpeg = compresserPhoto(_photoBrute);
      final reg = RegistrePhotosPointage(stockage: s, clock: () => h0802, journal: () => JournalTerminal(store: MemoryJournalStore()), retentionJours: () async => 30);
      const id = '3f1c2a9e-1111-4c4c-9e9e-123456789abc';
      await reg.ajouter(id: id, employeId: 'E1', lu: h0802, resultat: PhotoPrise(jpeg));
      await reg.ajouter(id: 'vieux', employeId: 'E1', lu: h0802.subtract(const Duration(days: 45)), resultat: PhotoPrise(jpeg));
      expect(File('${dir.path}/photos_pointage/$id.jpg').existsSync(), isTrue);
      final relu = RegistrePhotosPointage(stockage: s, clock: () => h0802, journal: () => JournalTerminal(store: MemoryJournalStore()), retentionJours: () async => 30);
      await relu.charger();
      expect(relu.photos.map((p) => p.id), [id]);
      expect(await relu.image(id), jpeg);
      expect(File('${dir.path}/photos_pointage/vieux.jpg').existsSync(), isFalse);
      expect(() => s.ecrire(PhotoPointage(id: '../evasion', employeId: 'x', lu: h0802, avecPhoto: false)), throwsArgumentError);
      expect(await s.image('../index'), isNull);
    });

    test('PointageRh.enregistrerAvecPhoto : photo liée à l\'identifiant du pointage, état d\'envoi mis à jour après la file', () async {
      final e = await Env().pret();
      e.horsLigne = true;
      final l = e.pr.lire('PV12AB34') as BadgeAConfirmer;
      final c = e.photo.demarrer();
      final r = await e.pr.enregistrerAvecPhoto(l, l.sens, photo: c.resultat);
      expect(r.issue, IssueBadge.enFile);
      final p = e.registre.photos.single;
      expect(p.id, r.pointage.id);
      expect(p.avecPhoto, isTrue);
      expect(p.envoi, StatutPointageBadge.enAttente.name);
      e.horsLigne = false;
      await e.pr.envoyer();
      expect(e.rh.posts.single.keys, unorderedEquals(['employeId', 'jour', 'heure', 'sens', 'motif']));
      expect(e.registre.photos.single.envoi, StatutPointageBadge.envoye.name);
      c.dispose();
    });
  });

  // =========================================================================
  // Écrans
  // =========================================================================
  group('Terminal : photo de contrôle', () {
    Widget terminal(Env e, {ListPresentation style = ListPresentation.dashboard}) =>
        TerminalPointageScreen(rh: e.pr, presentation: style, identification: e.identification, rafraichirAuDemarrage: false);

    Future<void> fin(WidgetTester t) async {
      await t.pump(const Duration(seconds: 5));
      await t.pumpWidget(const SizedBox());
    }

    testWidgets('badge → aperçu caméra frontale + compte à rebours 2 s → photo automatique → pointage envoyé, photo liée', (t) async {
      taille(t, const Size(720, 1440), 2);
      final e = await Env().pret();
      await pump(t, terminal(e));
      expect(find.byKey(const Key('rh_photo_info')), findsOneWidget);
      await lireBadge(t, 'pv12ab34');
      expect(find.text('Bonjour Awa'), findsOneWidget);
      expect(find.byKey(const Key('fausse_camera_apercu')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Regardez l\'écran : photo dans 2 s'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('1'), findsOneWidget);
      expect(e.camera.captures, 0);
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      expect(e.camera.captures, 1);
      expect(find.text('Photo de contrôle prise ✓'), findsOneWidget);
      expect(e.rh.posts, isEmpty);
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      expect(e.rh.posts.single['sens'], 'ENTREE');
      expect(e.rh.posts.single.containsKey('photo'), isFalse);
      expect(find.text('Bonjour Awa — ENTRÉE 08:02 ✓'), findsWidgets);
      expect(find.byKey(const Key('rh_resultat_sans_photo')), findsNothing);
      final p = e.registre.photos.single;
      expect(p.avecPhoto, isTrue);
      // Liée au pointage : même identifiant que celui du journal du terminal (« Pointage ENTRÉE enregistré »).
      await e.journal.idle;
      final ref = (await e.journal.lire()).firstWhere((j) => j.action.startsWith('Pointage ENTRÉE enregistré')).refLocale;
      expect(p.id.substring(0, 8), ref);
      expect(p.employeNom, 'KOUASSI Awa Marie');
      expect(p.moyen, 'Scan du badge');
      expect(p.envoi, StatutPointageBadge.envoye.name);
      expect(e.camera.fermetures, 1);
      expect(t.takeException(), isNull);
      await fin(t);
    });

    testWidgets('caméra refusée : pointage NON bloqué, marqué « sans photo (motif) », signalé', (t) async {
      taille(t, const Size(720, 1440), 2);
      final e = await Env().pret();
      e.camera.echec = MotifSansPhoto.permissionRefusee;
      await pump(t, terminal(e));
      await lireBadge(t, 'PV12AB34');
      expect(find.textContaining('sans photo (autorisation de la caméra refusée)'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await t.pump();
      expect(e.rh.posts, hasLength(1));
      expect(find.byKey(const Key('rh_resultat_sans_photo')), findsOneWidget);
      expect(find.text('Bonjour Awa — ENTRÉE 08:02 ✓'), findsWidgets);
      final p = e.registre.photos.single;
      expect(p.avecPhoto, isFalse);
      expect(p.motif, MotifSansPhoto.permissionRefusee);
      expect(e.registre.anomaliesNonTraitees, 1);
      await fin(t);
    });

    testWidgets('« Valider » avant la fin du compte à rebours : photo prise tout de suite puis pointage', (t) async {
      taille(t, const Size(720, 1440), 2);
      final e = await Env().pret();
      await pump(t, terminal(e));
      await lireBadge(t, 'PV12AB34');
      await t.tap(find.byKey(const Key('rh_valider')));
      await t.pump();
      await t.pump();
      expect(e.camera.captures, 1);
      expect(e.rh.posts, hasLength(1));
      expect(e.registre.photos.single.avecPhoto, isTrue);
      await fin(t);
    });

    testWidgets('annulation : caméra fermée, aucune photo gardée, rien envoyé ; NFC → photo aussi', (t) async {
      taille(t, const Size(720, 1440), 2);
      final e = await Env().pret();
      await pump(t, terminal(e));
      await lireBadge(t, 'PV12AB34');
      await t.tap(find.byKey(const Key('rh_annuler')));
      await t.pump();
      expect(e.camera.fermetures, 1);
      expect(e.camera.captures, 0);
      await t.pump(const Duration(seconds: 4));
      expect(e.rh.posts, isEmpty);
      expect(e.registre.photos, isEmpty);
      e.nfc.approcher('04:a1:b2:c3');
      await t.pump();
      await t.pump();
      expect(find.text('Bonjour Koffi'), findsOneWidget);
      expect(find.byKey(const Key('fausse_camera_apercu')), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await t.pump();
      expect(e.registre.photos.single.moyen, 'Badge NFC');
      await fin(t);
    });

    testWidgets('photo désactivée par l\'administrateur : comportement d\'avant (pas de caméra)', (t) async {
      taille(t, const Size(720, 1440), 2);
      final e = await Env().pret();
      e.reglages = const ReglagesPointageTerminal(photoBadge: false);
      await pump(t, terminal(e));
      expect(find.byKey(const Key('rh_photo_info')), findsNothing);
      await lireBadge(t, 'PV12AB34');
      expect(find.byKey(const Key('photo_apercu')), findsNothing);
      await t.pump(const Duration(seconds: 3));
      await t.pump();
      expect(e.rh.posts, hasLength(1));
      expect(e.camera.ouvertures, 0);
      expect(e.registre.photos, isEmpty);
      await fin(t);
    });

    testWidgets('empreinte : inchangée, aucune photo ; « déjà pointé » inchangé', (t) async {
      taille(t, const Size(720, 1440), 2);
      final e = Env()..empreinte = true;
      await e.pret();
      await e.identification.enregistrer(EmpreintesEmploye(employeId: 'E1', modeles: [Uint8List.fromList([9])], consentementLe: h0802));
      await pump(t, terminal(e));
      await t.pump();
      await t.tap(find.byKey(const Key('rh_empreinte')));
      await t.pump();
      await t.pump();
      expect(find.text('Bonjour Awa'), findsOneWidget);
      expect(find.byKey(const Key('photo_apercu')), findsNothing);
      await t.pump(const Duration(seconds: 3));
      await t.pump();
      expect(e.rh.posts.single['motif'], 'Empreinte terminal Accueil');
      expect(e.camera.ouvertures, 0);
      await t.pump(const Duration(seconds: 5));
      e.now = e.now.add(const Duration(seconds: 30));
      await lireBadge(t, 'PV12AB34');
      expect(find.text('Déjà pointé'), findsOneWidget);
      expect(find.text('Awa, vous avez déjà pointé (ENTRÉE à 08:02)'), findsOneWidget);
      expect(e.camera.ouvertures, 0);
      await fin(t);
    });

    testWidgets('autorisation de la caméra : bandeau pour le gestionnaire, explication puis demande, bandeau retiré', (t) async {
      taille(t, const Size(720, 1440), 2);
      final e = await Env().pret();
      await pump(t, terminal(e));
      expect(find.byKey(const Key('rh_photo_bandeau')), findsOneWidget);
      await t.tap(find.byKey(const Key('rh_photo_autoriser')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('photo_explication')), findsOneWidget);
      expect(find.textContaining('stockage privé'), findsOneWidget);
      await t.tap(find.byKey(const Key('photo_autoriser')));
      await t.pump();
      await t.pump();
      expect(e.camera.ouvertures, 1);
      expect(e.camera.fermetures, 1);
      expect(find.byKey(const Key('rh_photo_bandeau')), findsNothing);
      expect(await PhotoControle.permissionExpliquee(), isTrue);
      await fin(t);
      // Employé (non gestionnaire) : pas de bandeau, seulement l'information.
      SharedPreferences.setMockInitialValues({});
      await pump(t, TerminalPointageScreen(rh: e.pr, presentation: ListPresentation.dashboard, identification: e.identification, rafraichirAuDemarrage: false, gestion: false));
      expect(find.byKey(const Key('rh_photo_bandeau')), findsNothing);
      expect(find.byKey(const Key('rh_photo_info')), findsOneWidget);
      await fin(t);
    });
  });

  group('Ergonomie (720×1440, 1080×1920, tablette 1920×1200)', () {
    for (final (nom, physique, densite) in tailles) {
      testWidgets('$nom : écran badge et confirmation avec aperçu, sans débordement, textes lisibles, boutons ≥ 48 dp', (t) async {
        taille(t, physique, densite);
        final e = await Env().pret();
        for (final style in ListPresentation.values) {
          SharedPreferences.setMockInitialValues({});
          await pump(t, TerminalPointageScreen(rh: e.pr, presentation: style, identification: e.identification, rafraichirAuDemarrage: false));
          expect(t.takeException(), isNull, reason: '$nom $style : écran badge');
          bouton48(t, const Key('rh_badge_camera'));
          bouton48(t, const Key('rh_photo_autoriser'));
          textesLisibles(t, find.byKey(const Key('rh_terminal')));
          await lireBadge(t, 'M02');
          expect(find.text('Bonjour Koffi'), findsOneWidget);
          expect(t.takeException(), isNull, reason: '$nom $style : confirmation');
          final ecran = Offset.zero & t.view.physicalSize / t.view.devicePixelRatio;
          final apercu = t.getRect(find.byKey(const Key('photo_apercu')));
          expect(ecran.contains(apercu.topLeft) && ecran.contains(apercu.bottomRight - const Offset(1, 1)), isTrue, reason: '$nom : aperçu visible');
          expect(apercu.width, greaterThanOrEqualTo(120));
          for (final k in const [Key('rh_corriger'), Key('rh_annuler'), Key('rh_valider')]) {
            bouton48(t, k);
            // visibles sans faire défiler (l'employé peut corriger ou annuler pendant le compte à rebours)
            final r = t.getRect(find.byKey(k));
            expect(r.bottom, lessThanOrEqualTo(ecran.bottom), reason: '$nom $style : $k sous le bas de l\'écran');
          }
          textesLisibles(t, find.byKey(const Key('rh_confirmation')));
          expect(t.widget<Text>(find.byKey(const Key('photo_compte_rebours'))).style!.fontSize, greaterThanOrEqualTo(40));
          await t.pump(const Duration(seconds: 2));
          await t.pump();
          expect(find.text('Photo de contrôle prise ✓'), findsOneWidget);
          await t.pump(const Duration(seconds: 1));
          await t.pump();
          expect(t.takeException(), isNull, reason: '$nom $style : résultat');
          textesLisibles(t, find.byKey(const Key('rh_resultat')));
          await t.pump(const Duration(seconds: 5));
          e.now = e.now.add(const Duration(minutes: 3));
        }
        await t.pumpWidget(const SizedBox());
      });
    }

    for (final (nom, physique, densite) in tailles) {
      testWidgets('$nom : caméra en panne (résultat « sans photo »), écran de photo plein écran et liste des photos', (t) async {
        taille(t, physique, densite);
        final e = await Env().pret();
        e.camera.echec = MotifSansPhoto.cameraAbsente;
        await pump(t, TerminalPointageScreen(rh: e.pr, presentation: ListPresentation.guided, identification: e.identification, rafraichirAuDemarrage: false));
        await lireBadge(t, 'PV12AB34');
        expect(t.takeException(), isNull);
        await t.pump(const Duration(seconds: 3));
        await t.pump();
        expect(find.byKey(const Key('rh_resultat_sans_photo')), findsOneWidget);
        expect(t.takeException(), isNull);
        textesLisibles(t, find.byKey(const Key('rh_resultat')));
        await t.pump(const Duration(seconds: 5));
        e.camera.echec = null;
        await t.pumpWidget(MaterialApp(home: Builder(builder: (c) => ElevatedButton(onPressed: () => PhotoControleScreen.ouvrir(c, e.photo, 'Awa Kouassi'), child: const Text('go')))));
        await t.tap(find.text('go'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('Bonjour Awa Kouassi'), findsOneWidget);
        expect(find.byKey(const Key('photo_compte_rebours')), findsOneWidget);
        expect(t.takeException(), isNull);
        textesLisibles(t, find.byType(PhotoControleScreen));
        await t.pump(const Duration(seconds: 2));
        await t.pump(const Duration(seconds: 1));
        await t.pumpAndSettle();
        expect(find.byType(PhotoControleScreen), findsNothing);
        await pump(t, PhotosPointageScreen(registre: e.registre, retentionJours: 30));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('photos_sans_compte')), findsOneWidget);
        expect(find.textContaining('sans photo (caméra frontale absente)'), findsOneWidget);
        expect(t.takeException(), isNull);
        textesLisibles(t, find.byKey(const Key('photos_liste')));
        final id = e.registre.photos.single.id;
        bouton48(t, Key('photo_vu_$id'));
      });
    }
  });

  group('Pointage présence (entrée) et réglages', () {
    testWidgets('simple bouton désactivé sur ce terminal → « Mon pointage » désactivé et expliqué ; photos : gestionnaire + code admin', (t) async {
      taille(t, const Size(1080, 1920), 2.625);
      final e = await Env().pret();
      await e.registre.ajouter(id: 'p1', employeId: 'E1', employeNom: 'KOUASSI Awa', lu: h0802, sens: 'Entrée', moyen: 'Scan du badge', resultat: PhotoPrise(compresserPhoto(_photoBrute)));
      await e.registre.ajouter(id: 'p2', employeId: 'E2', employeNom: 'YAO Koffi', lu: h0802, sens: 'Entrée', moyen: 'Badge NFC', resultat: const PhotoAbsente(MotifSansPhoto.erreurCamera));
      e.reglages = const ReglagesPointageTerminal(simpleBouton: false);
      var codes = 0;
      await pump(t, RhPointageScreen(rh: e.pr, presentation: ListPresentation.dashboard, gestion: true, codeAdmin: (_) async {
        codes++;
        return true;
      }));
      await t.pumpAndSettle();
      expect(t.widget<InkWell>(find.byKey(const Key('rh_voie_a'))).onTap, isNull);
      expect(find.text(messageSimpleBoutonDesactive), findsOneWidget);
      expect(find.textContaining('1 pointage(s) sans photo à vérifier'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('rh_photos')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rh_photos')));
      await t.pumpAndSettle();
      expect(codes, 1);
      expect(find.text('Photos de contrôle'), findsOneWidget);
      expect(find.text('KOUASSI Awa · Entrée'), findsOneWidget);
      await t.tap(find.byKey(const Key('photo_voir_p1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('photo_detail')), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Fermer'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('photos_filtre_sans')));
      await t.pumpAndSettle();
      expect(find.text('KOUASSI Awa · Entrée'), findsNothing);
      await t.tap(find.byKey(const Key('photo_vu_p2')));
      await t.pumpAndSettle();
      expect(e.registre.anomaliesNonTraitees, 0);
      // Employé : pas de photos ; simple bouton autorisé par défaut → « Mon pointage » garde son explication habituelle.
      e.reglages = const ReglagesPointageTerminal();
      await pump(t, RhPointageScreen(rh: e.pr, presentation: ListPresentation.dashboard, gestion: false));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rh_photos')), findsNothing);
      expect(find.text(messageSimpleBoutonDesactive), findsNothing);
    });

    testWidgets('Paramètres › Équipe & pointage : photo (activée), simple bouton (autorisé), conservation 30 j, enregistrés', (t) async {
      taille(t, const Size(720, 1440), 2);
      final e = Env();
      final photo = PhotoControle(camera: e.camera, registre: e.registre, compresser: (b) async => compresserPhoto(b));
      await t.pumpWidget(MaterialApp(home: EquipePage(repository: MemoryPointageRepository(), photo: photo)));
      await t.pumpAndSettle();
      Future<void> voir(Key k, {bool haut = false}) async {
        if (find.byKey(k).evaluate().isEmpty) {
          await t.scrollUntilVisible(find.byKey(k), haut ? -200 : 200, scrollable: find.byType(Scrollable).first);
        }
        await t.ensureVisible(find.byKey(k));
        await t.pumpAndSettle();
      }

      await voir(const Key('rh_reglage_photo'));
      expect(t.widget<SwitchCard>(find.byKey(const Key('rh_reglage_photo'))).value, isTrue);
      await voir(const Key('rh_reglage_simple_bouton'));
      expect(t.widget<SwitchCard>(find.byKey(const Key('rh_reglage_simple_bouton'))).value, isTrue);
      await voir(const Key('rh_reglage_retention'));
      expect(find.text('30 jours'), findsOneWidget);
      await voir(const Key('rh_reglage_simple_bouton'));
      await t.tap(find.descendant(of: find.byKey(const Key('rh_reglage_simple_bouton')), matching: find.byType(Switch)));
      await t.pumpAndSettle();
      await voir(const Key('rh_reglage_retention'));
      await t.tap(find.byKey(const Key('rh_reglage_retention')));
      await t.pumpAndSettle();
      await t.tap(find.text('7 jours').last);
      await t.pumpAndSettle();
      final r = await ReglagesPointageTerminal.charger();
      expect([r.photoBadge, r.simpleBouton, r.retentionJours], [true, false, 7]);
      await voir(const Key('rh_reglage_photo'), haut: true);
      await t.tap(find.descendant(of: find.byKey(const Key('rh_reglage_photo')), matching: find.byType(Switch)));
      await t.pumpAndSettle();
      expect((await ReglagesPointageTerminal.charger()).photoBadge, isFalse);
      await voir(const Key('rh_reglage_photos'));
      expect(t.takeException(), isNull);
      // le réglage n'installe pas de service global (aucun effet sur les autres écrans)
      expect(PhotoControle.instance, isNull);
    });
  });

  group('Pointage local (badge)', () {
    const awa = Employee(id: 'awa', name: 'Awa Kouassi', badgeCode: 'PV12AB34');
    const koffi = Employee(id: 'koffi', name: 'Koffi Yao');

    Future<MemoryPointageRepository> kiosque(WidgetTester t, Env e, {BadgeMode mode = BadgeMode.both, PointageMode pm = PointageMode.pinOrName}) async {
      taille(t, const Size(1080, 1920), 2.625);
      final repo = MemoryPointageRepository()..employees.addAll([awa, koffi]);
      await t.pumpWidget(MaterialApp(
        key: UniqueKey(),
        home: PointageKioskScreen(
          repository: repo,
          capability: DeviceCapability(mode: pm, device: 'Test'),
          settings: PointageSettings(badgeMode: mode),
          verifier: PointageVerifier(confirmFingerprint: (_) async => true, identify: (_) async => null),
          clock: () => h0802,
          nfc: e.nfc,
          photo: e.photo,
          reglagesTerminal: () async => e.reglages,
        ),
      ));
      await t.pumpAndSettle();
      return repo;
    }

    testWidgets('badge → photo plein écran (aperçu + compte à rebours) → choix → pointage local lié à sa photo', (t) async {
      final e = Env();
      final repo = await kiosque(t, e);
      expect(find.byKey(const Key('pointage_photo_info')), findsOneWidget);
      await t.enterText(find.widgetWithText(TextField, 'Scannez votre badge'), 'PV12AB34');
      await t.pump(const Duration(milliseconds: 350));
      await t.pump();
      await t.pump();
      expect(find.text('Bonjour Awa Kouassi'), findsOneWidget);
      expect(find.byKey(const Key('fausse_camera_apercu')), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      await t.pump();
      expect(e.camera.captures, 1);
      expect(find.text('Photo de contrôle prise ✓'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      await t.tap(find.text('Arrivée'));
      await t.pumpAndSettle();
      final rec = repo.records.single;
      expect(rec.method, PointageMethod.badge);
      final p = e.registre.photos.single;
      expect([p.id, p.source, p.avecPhoto, p.sens], [rec.id, 'local', true, 'Arrivée']);
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('caméra absente : pointage local quand même, « sans photo » ; simple choix du nom désactivable', (t) async {
      final e = Env();
      e.camera.echec = MotifSansPhoto.cameraAbsente;
      final repo = await kiosque(t, e);
      await t.enterText(find.widgetWithText(TextField, 'Scannez votre badge'), 'PV12AB34');
      await t.pump(const Duration(milliseconds: 350));
      await t.pump();
      expect(find.textContaining('sans photo (caméra frontale absente)'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      await t.tap(find.text('Arrivée'));
      await t.pumpAndSettle();
      expect(repo.records, hasLength(1));
      expect(e.registre.photos.single.motif, MotifSansPhoto.cameraAbsente);
      expect(find.textContaining('sans photo (caméra frontale absente)'), findsWidgets);
      await t.pump(const Duration(seconds: 5));

      // Koffi n'a pas de PIN : « Nom seul » refusé quand le simple bouton est désactivé…
      e.reglages = const ReglagesPointageTerminal(simpleBouton: false);
      final repo2 = await kiosque(t, e);
      await t.tap(find.text('Koffi Yao'));
      await t.pumpAndSettle();
      expect(find.textContaining('simple choix du nom désactivé'), findsWidgets);
      expect(repo2.records, isEmpty);
      await t.pump(const Duration(seconds: 5));
      // … et accepté par défaut (comportement d'avant).
      e.reglages = const ReglagesPointageTerminal();
      final repo3 = await kiosque(t, e);
      await t.tap(find.text('Koffi Yao'));
      await t.pumpAndSettle();
      await t.tap(find.text('Arrivée'));
      await t.pumpAndSettle();
      expect(repo3.records.single.method, PointageMethod.manual);
      await t.pump(const Duration(seconds: 5));
    });
  });
}
