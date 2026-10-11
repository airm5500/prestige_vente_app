// B2 — Images des produits (API EXISTANTE du serveur, session cookie) : avec / sans capacité, cache disque,
// pas de retéléchargement (le serveur n'a pas d'ETag : fichier gardé tant que l'identifiant ne change pas),
// cache négatif daté, hors ligne depuis le cache (y compris après redémarrage), éviction, concurrence,
// borne : produits avec image d'abord, ajout de photo (réglage, droit), réglages par défaut, liste de vente
// (vignettes désactivées = aucune requête), préparation de la photo ; intégration réelle (sautée sans serveur).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_kiosque.dart';
import 'package:prestige_vente_app/borne/borne_screen.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/images/images_reglages.dart';
import 'package:prestige_vente_app/images/photo_produit.dart';
import 'package:prestige_vente_app/images/produit_image_widget.dart';
import 'package:prestige_vente_app/images/produit_images.dart';
import 'package:prestige_vente_app/parametres/parametres_logic.dart';
import 'package:prestige_vente_app/ventes/common/product_list_modal.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _png([int w = 4, int h = 4]) => Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)));

class _Api implements ProduitImagesApi {
  /// familleId → identifiants des images (la 1ʳᵉ est la principale).
  final Map<String, List<String>> images = {};
  bool sansRoute = false;
  bool panne = false;
  bool modifiable = false;
  int listes = 0;
  int fichiers = 0;
  int simultanees = 0;
  int maxSimultanees = 0;
  Duration delai = Duration.zero;
  int tailleFichier = 0;
  final ajouts = <String>[];

  @override
  Future<VenteResult<ImagesListe?>> lister(String familleId) async {
    listes++;
    simultanees++;
    if (simultanees > maxSimultanees) maxSimultanees = simultanees;
    try {
      if (delai > Duration.zero) await Future<void>.delayed(delai);
      if (panne) return const VenteFailed('Serveur injoignable');
      if (sansRoute) return const VenteOk(null);
      final ids = images[familleId] ?? const [];
      return VenteOk(ImagesListe([for (final (i, id) in ids.indexed) ImageProduitInfo(id: id, principale: i == 0)], modifiable: modifiable));
    } finally {
      simultanees--;
    }
  }

  @override
  Future<VenteResult<Uint8List>> fichier(String familleId, String imageId, {bool vignette = true}) async {
    fichiers++;
    if (panne) return const VenteFailed('Serveur injoignable');
    return VenteOk(tailleFichier > 0 ? Uint8List(tailleFichier) : _png());
  }

  @override
  Future<VenteResult<String>> ajouter(String familleId, Uint8List octets, {String nom = 'photo.jpg', bool principale = true}) async {
    if (!modifiable) return const VenteRefused('Vous n\'avez pas le droit de modifier les images des produits.');
    ajouts.add(familleId);
    final id = 'N${ajouts.length}';
    images[familleId] = [id, ...?images[familleId]?.skip(1)];
    return VenteOk(id);
  }
}

late Directory _tmp;
DateTime _now = DateTime(2026, 10, 11, 9);

ProduitImages _service(_Api api, {int? max, bool Function()? horsLigne}) {
  final s = ProduitImages(api: api, dossier: () async => _tmp, clock: () => _now, tailleMaxOctets: max);
  if (horsLigne != null) s.horsLigne = horsLigne;
  return s;
}

ProductSearchResult _p(String id, String nom, {int stock = 5}) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: nom, intCIP: '${id.hashCode.abs()}', intPRICE: 1000, intNUMBERAVAILABLE: stock, strLIBELLEE: '', intPAF: 0);

class _Gw implements VenteGateway {
  final List<ProductSearchResult> produits;
  _Gw(this.produits);
  @override
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async =>
      VenteOk(ProductPage(produits.skip(start).take(limit).toList(), produits.length));
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _Imp implements BorneImprimante {
  @override
  Future<bool> imprimer(BorneTicket t) async => true;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ImagesReglages.courant.value = const ImagesConfig();
    _tmp = Directory.systemTemp.createTempSync('images_produits_');
    _now = DateTime(2026, 10, 11, 9);
  });
  tearDown(() {
    try {
      _tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('réglages par défaut : images actives, vignettes de vente et photo du terminal désactivées, cache 500 Mo', () async {
    final c = await ImagesReglages.charger();
    expect(c.actif, isTrue);
    expect(c.vignettesVentes, isFalse);
    expect(c.photoTerminal, isFalse);
    expect(c.prechargement, isFalse);
    expect(c.cacheMo, 500);
    expect(Rubrique.images.locked, isTrue);
    expect(ImagesConfig.fromJson({'cacheMo': 1}).cacheMo, ImagesConfig.cacheMoMin);
  });

  test('lecture des réponses du serveur (liste, 404 = pas d\'API, page HTML, ajout en text/html)', () {
    final l = imagesListeDepuis(200, {
      'success': true,
      'modifiable': true,
      'total': 2,
      'data': [
        {'id': 'A', 'principale': true, 'vignette': '../api/v1/produit-images/F/A/fichier?taille=vignette'},
        {'id': 'B', 'principale': false, 'vignette': '../api/v1/produit-images/F/B/fichier'},
      ],
    }).valueOrNull!;
    expect(l.principale!.id, 'A');
    expect(l.images[0].vignette, isTrue);
    expect(l.images[1].vignette, isFalse, reason: 'WEBP : pas de vignette');
    expect(l.modifiable, isTrue);
    expect(imagesListeDepuis(404, '<html>').valueOrNull, isNull);
    expect(imagesListeDepuis(404, '<html>').isOk, isTrue);
    expect(imagesListeDepuis(200, '<html>Not found</html>').valueOrNull, isNull);
    expect(imagesListeDepuis(401, null).isOk, isFalse);
    expect(imagesListeDepuis(200, {'success': false, 'message': 'Déconnecté'}).message, 'Déconnecté');
    expect(ajoutDepuis(200, '{"success":true,"id":"X1"}').valueOrNull, 'X1');
    expect(ajoutDepuis(200, '<pre>{"success":false,"message":"L\'image dépasse 5 Mo."}</pre>').message, contains('5 Mo'));
  });

  test('sans capacité (serveur sans l\'API) : pictogrammes seulement, plus aucune requête', () async {
    final api = _Api()..sansRoute = true;
    final s = _service(api);
    expect(await s.demander('P1'), isNull);
    expect(s.capacite, CapaciteImages.non);
    expect(await s.demander('P2'), isNull);
    expect(await s.demander('P3'), isNull);
    expect(api.listes, 1, reason: 'aucune requête après la détection');
    // Revérifiée après 30 min (mise à jour du serveur).
    _now = _now.add(const Duration(minutes: 31));
    await s.demander('P2');
    expect(api.listes, 2);
  });

  test('avec capacité : téléchargement, cache, pas de retéléchargement, nouvelle image remplacée', () async {
    final api = _Api()..images['P1'] = ['I1'];
    final s = _service(api);
    final f = await s.demander('P1');
    expect(f, isNotNull);
    expect(f!.existsSync(), isTrue);
    expect(s.aImage('P1'), isTrue);
    expect(s.capacite, CapaciteImages.oui);
    expect((api.listes, api.fichiers), (1, 1));
    // Frais : aucune requête.
    await s.demander('P1');
    expect((api.listes, api.fichiers), (1, 1));
    // 25 h plus tard : liste relue, même image → pas de retéléchargement (équivalent d'un « 304 »).
    _now = _now.add(const Duration(hours: 25));
    await s.demander('P1');
    expect((api.listes, api.fichiers), (2, 1));
    // Nouvelle image principale : téléchargée, l'ancienne supprimée.
    api.images['P1'] = ['I2'];
    _now = _now.add(const Duration(hours: 25));
    final f2 = await s.demander('P1');
    expect(api.fichiers, 2);
    expect(f2!.path, isNot(f.path));
    expect(f.existsSync(), isFalse);
  });

  test('cache négatif daté : pas d\'image = pas de nouvelle requête pendant 24 h', () async {
    final api = _Api();
    final s = _service(api);
    expect(await s.demander('P9'), isNull);
    expect(s.aImage('P9'), isFalse);
    expect(s.aImage('PX'), isNull);
    await s.demander('P9');
    expect(api.listes, 1);
    _now = _now.add(const Duration(hours: 25));
    api.images['P9'] = ['I9'];
    expect(await s.demander('P9'), isNotNull, reason: 'image ajoutée sur le serveur : vue au bout de 24 h');
  });

  test('hors ligne : images du cache, aucune requête ; après redémarrage aussi (index sur disque)', () async {
    final api = _Api()..images['P1'] = ['I1'];
    var hors = false;
    final s = _service(api, horsLigne: () => hors);
    await s.demander('P1');
    await s.flush();
    hors = true;
    _now = _now.add(const Duration(days: 3));
    expect(await s.demander('P1'), isNotNull);
    expect(await s.demander('P2'), isNull);
    expect(api.listes, 1);
    // Redémarrage de l'appli, toujours hors ligne.
    final s2 = _service(api, horsLigne: () => true);
    await s2.init();
    expect(s2.aImage('P1'), isTrue);
    expect(s2.fichierConnu('P1')!.existsSync(), isTrue);
    expect(api.listes, 1);
    // Panne pendant une revérification : le cache est gardé.
    final s3 = _service(api);
    await s3.init();
    api.panne = true;
    expect(await s3.demander('P1'), isNotNull);
  });

  test('taille maximale du cache : les images vues il y a le plus longtemps sont retirées', () async {
    final api = _Api()..tailleFichier = 1000;
    for (var i = 0; i < 5; i++) {
      api.images['P$i'] = ['I$i'];
    }
    final s = _service(api, max: 3500);
    for (var i = 0; i < 5; i++) {
      _now = _now.add(const Duration(minutes: 1));
      await s.demander('P$i');
    }
    expect(s.tailleCache, lessThanOrEqualTo(3500));
    expect(s.aImage('P0'), isNull, reason: 'la plus ancienne est retirée');
    expect(s.aImage('P4'), isTrue);
    await s.vider();
    expect(s.tailleCache, 0);
  });

  test('3 demandes au plus en même temps ; une seule demande par produit', () async {
    final api = _Api()..delai = const Duration(milliseconds: 20);
    final s = _service(api);
    await Future.wait([for (var i = 0; i < 12; i++) s.demander('P${i % 10}')]);
    expect(api.maxSimultanees, lessThanOrEqualTo(3));
    expect(api.listes, 10);
  });

  test('préchargement par lots, interrompu à la demande', () async {
    final api = _Api()..images['P2'] = ['I2'];
    final s = _service(api);
    Stream<List<String>> lots() async* {
      yield ['P1', 'P2'];
      yield ['P3'];
    }

    expect(await s.precharger(lots()), 3);
    expect(s.aImage('P2'), isTrue);
    s.arreter();
    Stream<List<String>> encore() async* {
      yield ['P7', 'P8'];
    }

    final n = s.precharger(encore(), occupe: () => true, attente: const Duration(milliseconds: 5));
    s.arreter();
    expect(await n, 0, reason: 'appli occupée puis arrêt : rien de plus');
  });

  test('photo du produit : réglage désactivé = refus ; sans le droit = refus ; avec le droit = envoyée et affichée', () async {
    final api = _Api();
    final s = _service(api);
    final jpeg = _png();
    expect((await s.ajouterPhoto('P1', jpeg)).message, contains('désactivé'));
    ImagesReglages.courant.value = const ImagesConfig(photoTerminal: true);
    expect((await s.ajouterPhoto('P1', jpeg)).message, contains('droit'));
    expect(api.ajouts, isEmpty);
    api.modifiable = true;
    final r = await s.ajouterPhoto('P1', jpeg);
    expect(r.valueOrNull, 'N1');
    expect(s.aImage('P1'), isTrue);
    // Hors ligne : rien n'est envoyé.
    s.horsLigne = () => true;
    expect((await s.ajouterPhoto('P1', jpeg)).isOk, isFalse);
    expect(api.ajouts.length, 1);
  });

  test('préparation de la photo : carré centré, réduit, JPEG', () {
    final src = Uint8List.fromList(img.encodePng(img.Image(width: 300, height: 200)));
    final out = preparerPhoto(src, cote: 128)!;
    final d = img.decodeJpg(out)!;
    expect((d.width, d.height), (128, 128));
    expect(preparerPhoto(Uint8List.fromList([1, 2, 3])), isNull);
  });

  testWidgets('bouton « Photo du produit » caché par défaut, visible avec le réglage et le droit', (tester) async {
    final api = _Api()..modifiable = true;
    late ProduitImages s;
    await tester.runAsync(() async {
      s = _service(api);
      await s.demander('P1');
    });
    Widget app() => MaterialApp(home: Scaffold(body: PhotoProduitBouton(familleId: 'P1', images: s, capturer: (_) async => _png())));
    await tester.pumpWidget(app());
    expect(find.byKey(const ValueKey('photo-produit')), findsNothing);
    ImagesReglages.courant.value = const ImagesConfig(photoTerminal: true);
    await tester.pump();
    expect(find.byKey(const ValueKey('photo-produit')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('photo-produit')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(api.ajouts, ['P1']);
  });

  testWidgets('borne : produits avec image en premier, image affichée à la place du pictogramme', (tester) async {
    tester.view.physicalSize = const Size(720, 1480);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final api = _Api()..images['B'] = ['IB'];
    late ProduitImages s;
    await tester.runAsync(() async {
      s = _service(api);
      await s.demander('B');
      await s.demander('A');
    });
    final gw = _Gw([_p('A', 'DOLIPRANE 1000MG CP'), _p('B', 'DOLIPRANE SIROP 100ML'), _p('C', 'DOLIPRANE SUPPO')]);
    BorneKiosque.instance = KiosqueSimule();
    await tester.pumpWidget(MaterialApp(
      home: BorneScreen(
        service: BorneService(gw),
        config: const BorneConfig(actif: true, login: 'b', presentation: BornePresentation.listeRapide),
        monitor: ServerMonitor(),
        imprimante: _Imp(),
        kiosque: KiosqueSimule(),
        adminCheck: (_) async => true,
        onSortie: (_) {},
        image: (p, taille, picto) => ProduitImage(familleId: p.id, taille: taille, placeholder: picto, images: s, charger: false),
        imageConnue: s.aImage,
      ),
    ));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('borne-recherche')), 'doli');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.pump();
    final yA = tester.getTopLeft(find.byKey(const ValueKey('borne-produit-A'))).dy;
    final yB = tester.getTopLeft(find.byKey(const ValueKey('borne-produit-B'))).dy;
    expect(yB, lessThan(yA), reason: 'produit avec image mis en avant');
    expect(find.byKey(const ValueKey('image-produit-B')), findsOneWidget);
    expect(find.byKey(const ValueKey('image-produit-A')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('liste de vente : vignettes désactivées = aucune requête ; activées = seulement les lignes affichées', (tester) async {
    final api = _Api();
    final produits = [for (var i = 0; i < 200; i++) _p('P$i', 'PRODUIT $i')];
    final prev = ProduitImages.instance;
    addTearDown(() => ProduitImages.instance = prev);
    ProduitImages.instance = _service(api);
    Future<void> ouvrir() async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProductListModal(results: produits, initialQuery: '', onProductSelected: (_) {}))));
      await tester.pump();
    }

    await ouvrir();
    expect(find.text('PRODUIT 0'), findsOneWidget);
    expect(api.listes, 0);
    ImagesReglages.courant.value = const ImagesConfig(vignettesVentes: true);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await ouvrir();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(api.listes, greaterThan(0));
    expect(api.listes, lessThan(40), reason: 'liste paresseuse : pas 200 requêtes');
  });

  group('Intégration serveur de test (API images existante)', () {
    final url = Platform.environment['PRESTIGE_TEST_URL'] ?? 'http://localhost:8080/prestige/api/v1';
    test('liste, ajout, vignette, suppression', () => HttpOverrides.runWithHttpOverrides(() async {
          try {
            final r = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 2))).get('$url/officine');
            if (r.statusCode != 200) throw StateError('');
          } catch (_) {
            markTestSkipped('Serveur de test injoignable : $url');
            return;
          }
          final api = ApiService(baseUrl: url);
          if (await api.login('admin', 'Test1234') == null) {
            markTestSkipped('Connexion impossible');
            return;
          }
          final images = DioProduitImagesApi(() => url);
          final page = await DioVenteGateway(api).searchProductsPage('DOLIMEX', 0, 50);
          final cible = page.valueOrNull?.items.firstOrNull;
          if (cible == null) {
            markTestSkipped('Aucun produit DOLIMEX');
            return;
          }
          final l = await images.lister(cible.lgFAMILLEID);
          if (l.valueOrNull == null) {
            markTestSkipped('Serveur sans l\'API images (${l.message ?? 'route absente'})');
            return;
          }
          if (l.valueOrNull!.images.isNotEmpty) {
            markTestSkipped('Le produit a déjà une image : rien n\'est modifié.');
            return;
          }
          expect(l.valueOrNull!.modifiable, isTrue, reason: 'admin');
          final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 400, height: 400)));
          final a = await images.ajouter(cible.lgFAMILLEID, jpeg);
          expect(a.isOk, isTrue, reason: a.message);
          try {
            final l2 = await images.lister(cible.lgFAMILLEID);
            expect(l2.valueOrNull!.principale!.id, a.valueOrNull);
            final f = await images.fichier(cible.lgFAMILLEID, a.valueOrNull!, vignette: l2.valueOrNull!.principale!.vignette);
            expect(f.valueOrNull, isNotNull, reason: f.message);
            expect(img.decodeImage(f.valueOrNull!)!.width, lessThanOrEqualTo(400));
          } finally {
            final d = await images.dio.delete('/produit-images/${cible.lgFAMILLEID}/${a.valueOrNull}');
            // ignore: avoid_print
            print('Images intégration : image ${a.valueOrNull} supprimée (${d.data}).');
          }
        }, _RealHttp()), timeout: const Timeout(Duration(minutes: 1)));
  });
}

class _RealHttp extends HttpOverrides {}
