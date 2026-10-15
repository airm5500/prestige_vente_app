// Vidéo de l'application RÉELLE (code de lib/, rendu Flutter) contre le serveur Prestige de test LOCAL (vrai HTTP),
// pour montrer au pharmacien les cas qu'il a signalés (4.3.2) : Analyse article → détail ; recherche de l'accueil →
// fiche produit. Chaque image est capturée pendant le parcours (≈ 10 images/s) puis assemblée en MP4 par ffmpeg
// (script outils_video/assembler.sh du dossier de travail).
// Hors de la suite de la CI (dossier test/outils/, ignoré sans la variable VIDEO). Exemple :
//   VIDEO=/chemin/sortie VIDEO_SERVEUR=127.0.0.1 VIDEO_PORT=8081 flutter test test/outils/video_lenteur_test.dart
// Compte de test du serveur local (jamais un serveur de l'officine) : VIDEO_LOGIN / VIDEO_MDP.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'app_e2e.dart';

final _sortie = Platform.environment['VIDEO'];
final _hote = Platform.environment['VIDEO_SERVEUR'] ?? '127.0.0.1';
final _port = Platform.environment['VIDEO_PORT'] ?? '8081';
final _login = Platform.environment['VIDEO_LOGIN'] ?? 'admin';
final _mdp = Platform.environment['VIDEO_MDP'] ?? '';

Future<void> _polices() async {
  final dossier = '${Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path}'
      '/bin/cache/artifacts/material_fonts';
  Future<ByteData> lire(String f) async => ByteData.sublistView(await File('$dossier/$f').readAsBytes());
  for (final famille in ['Roboto', 'FlutterTest']) {
    final l = FontLoader(famille);
    for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
      l.addFont(lire(f));
    }
    await l.load();
  }
  await (FontLoader('MaterialIcons')..addFont(lire('MaterialIcons-Regular.otf'))).load();
}

/// Enregistreur : images brutes RGBA (une par pas) + horodatage réel de chaque image.
class _Film {
  final String nom;
  final WidgetTester t;
  final RandomAccessFile _f;
  final List<int> _ms = [];
  final Stopwatch _chrono = Stopwatch()..start();
  late int largeur, hauteur;
  final List<String> _etapes = [];
  _Film(this.nom, this.t) : _f = File('$_sortie/$nom.rgba').openSync(mode: FileMode.write);

  static const ratio = 1.5; // 360×720 logiques → 540×1080

  Future<void> image() async {
    final vue = t.binding.renderViews.first;
    final layer = vue.debugLayer! as OffsetLayer;
    // Couche racine en pixels PHYSIQUES (720×1440) : réduite à ×0,75 → 540×1080.
    final taille = t.view.physicalSize;
    final ui.Image img = await layer.toImage(Offset.zero & taille, pixelRatio: ratio / t.view.devicePixelRatio);
    largeur = img.width;
    hauteur = img.height;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    _f.writeFromSync(data!.buffer.asUint8List());
    _ms.add(_chrono.elapsedMilliseconds);
  }

  void etape(String texte) => _etapes.add('${_chrono.elapsedMilliseconds}\t$texte');

  /// [duree] de temps RÉEL (réseau réel), l'interface avançant au même pas ; une image par pas.
  Future<void> filmer(Duration duree, {Duration pas = const Duration(milliseconds: 100)}) async {
    final fin = _chrono.elapsed + duree;
    while (_chrono.elapsed < fin) {
      await t.runAsync(() => Future<void>.delayed(pas));
      await t.pump(pas);
      await t.runAsync(image);
    }
  }

  /// Filme jusqu'à ce que [f] apparaisse (au plus [max]) ; renvoie le temps réel écoulé.
  Future<Duration> jusqua(Finder f, {Duration max = const Duration(seconds: 30)}) async {
    final debut = _chrono.elapsed;
    while (f.evaluate().isEmpty && _chrono.elapsed - debut < max) {
      await filmer(const Duration(milliseconds: 100));
    }
    return _chrono.elapsed - debut;
  }

  Future<void> taper(String texte) async {
    for (var i = 1; i <= texte.length; i++) {
      await t.enterText(find.byType(TextField).first, texte.substring(0, i));
      await filmer(const Duration(milliseconds: 150));
    }
  }

  void fermer() {
    _f.closeSync();
    File('$_sortie/$nom.txt').writeAsStringSync('largeur=$largeur\nhauteur=$hauteur\nimages=${_ms.length}\n'
        'duree_ms=${_ms.isEmpty ? 0 : _ms.last}\n${_ms.join(' ')}\n');
    File('$_sortie/$nom.etapes.txt').writeAsStringSync(_etapes.join('\n'));
  }
}

Future<AppE2E> _ouvrirApp(WidgetTester t) async {
  t.view.physicalSize = const Size(720, 1440);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
  final app = AppE2E();
  await app.preparer(prefs: {
    'local_ip': _hote,
    'port': _port,
    'hiddenMenuIds': <String>[],
    'presentation_listes_v1': ListPresentation.dashboard.name,
  });
  // Vrai réseau vers le serveur de test local (au lieu du faux serveur en mémoire).
  HttpOverrides.global = null;
  DioClient.getClient('').httpClientAdapter = IOHttpClientAdapter();
  await app.lancer(t);
  return app;
}

Future<void> _connexion(WidgetTester t, _Film film) async {
  await film.jusqua(find.byType(ConnexionScreen));
  await t.enterText(find.byKey(const Key('connexion_login')), _login);
  await t.enterText(find.byKey(const Key('connexion_mdp')), _mdp);
  await t.ensureVisible(find.byKey(const Key('se_connecter')));
  await t.tap(find.byKey(const Key('se_connecter')));
  await film.jusqua(find.byType(AccueilScreen));
  await film.filmer(const Duration(seconds: 2));
}

void main() {
  final actif = _sortie != null;
  setUpAll(() async {
    if (actif) await _polices();
  });

  testWidgets('Analyse article : « artef » → détail de deux produits', (t) async {
    final film = _Film('analyse_article', t);
    final app = await _ouvrirApp(t);
    await _connexion(t, film);
    film.etape('menu Analyse article');
    final tuile = find.byKey(const ValueKey('tuile_analyse_article'));
    await app.defilerJusqua(t, tuile);
    await film.filmer(const Duration(milliseconds: 400));
    await t.tap(tuile);
    await film.filmer(const Duration(seconds: 1));
    film.etape('saisie « artef »');
    await film.taper('artef');
    final liste = await film.jusqua(find.textContaining('ARTEFAN 20/120MG'));
    film.etape('liste affichée (${liste.inMilliseconds} ms après la saisie)');
    await film.filmer(const Duration(milliseconds: 1500)); // le temps de lire la liste, comme dans la vidéo
    for (final nom in ['ARTEFAN 20/120MG CPR DISP B/6', 'ARTEFAN 40MG/240MG PDRE SUSP BUV F/30ML']) {
      film.etape('clic sur $nom');
      await t.tap(find.text(nom).hitTestable().first);
      final graphe = await film.jusqua(find.text('Évolution des ventes mensuelles:'));
      film.etape('graphe affiché ${graphe.inMilliseconds} ms après le clic');
      await film.filmer(const Duration(milliseconds: 1800));
      await t.tap(find.text('Fermer').last);
      await film.filmer(const Duration(milliseconds: 1200));
    }
    film.fermer();
    await t.pumpWidget(const SizedBox());
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump(const Duration(seconds: 31));
  }, skip: !actif, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('Recherche de l\'accueil : « ferce » → fiche produit', (t) async {
    final film = _Film('recherche_accueil', t);
    await _ouvrirApp(t);
    await _connexion(t, film);
    film.etape('recherche de l\'accueil');
    await t.tap(find.text('Rechercher un menu ou un produit'));
    await film.filmer(const Duration(milliseconds: 800));
    film.etape('saisie « ferce »');
    await film.taper('ferce');
    final liste = await film.jusqua(find.text('FERCEFOL CPR B/30'));
    film.etape('liste affichée (${liste.inMilliseconds} ms après la saisie)');
    await film.filmer(const Duration(milliseconds: 1000));
    film.etape('clic sur FERCEFOL CPR B/30');
    await t.tap(find.text('FERCEFOL CPR B/30').hitTestable().first);
    final analyse = await film.jusqua(find.text('LABOREX-CI YOP'));
    film.etape('grossiste (analyse GET /info) affiché ${analyse.inMilliseconds} ms après le clic');
    await film.filmer(const Duration(milliseconds: 2500));
    film.fermer();
    await t.pumpWidget(const SizedBox());
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump(const Duration(seconds: 31));
  }, skip: !actif, timeout: const Timeout(Duration(minutes: 5)));
}
