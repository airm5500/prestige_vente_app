// Intégration : flux complet du pointage par badge avec photo de contrôle, contre un serveur Prestige simulé
// (HttpServer local, vraies requêtes HTTP de DioRhServeur) :
// badge lu → caméra frontale (simulée) → photo compressée gardée sur le terminal → POST v1/rh/pointages (contrat
// inchangé : aucune photo envoyée, le serveur n'en accepte pas) ; caméra en échec → pointage envoyé quand même,
// marqué « sans photo » ; serveur injoignable → pointage en file avec sa photo, puis envoyé au retour du serveur.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/rh/rh_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RealHttp extends HttpOverrides {}

/// Photo « capteur » 1280×960 (détails aléatoires : compression réaliste).
Uint8List _photoCapteur() {
  final im = img.Image(width: 1280, height: 960);
  final r = Random(3);
  for (var y = 0; y < 960; y++) {
    for (var x = 0; x < 1280; x++) {
      final v = (x + y) % 256;
      im.setPixelRgb(x, y, (v + r.nextInt(40)) % 256, (v * 2) % 256, r.nextInt(256));
    }
  }
  return img.encodeJpg(im, quality: 95);
}

class _Camera implements CameraControle {
  MotifSansPhoto? echec;
  final Uint8List image;
  int captures = 0;
  _Camera(this.image);
  @override
  Future<SessionCamera> ouvrir() async {
    if (echec != null) throw CameraIndisponible(echec!);
    return _Session(this);
  }
}

class _Session implements SessionCamera {
  final _Camera c;
  _Session(this.c);
  @override
  Widget apercu() => const SizedBox();
  @override
  Future<Uint8List> capturer() async {
    c.captures++;
    return c.image;
  }

  @override
  Future<void> fermer() async {}
}

/// Serveur Prestige simulé : routes v1/rh utilisées par le terminal.
class _Serveur {
  late HttpServer http;
  final posts = <Map<String, dynamic>>[];
  final typesContenu = <String>[];
  final tailles = <int>[];

  Future<void> demarrer([int port = 0]) async {
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    http.listen((req) async {
      final res = req.response..headers.contentType = ContentType.json;
      final chemin = req.uri.path;
      final corps = await utf8.decoder.bind(req).join();
      if (chemin.endsWith('/rh/droits')) {
        res.write(jsonEncode({'success': true}));
      } else if (chemin.endsWith('/rh/employes')) {
        res.write(jsonEncode({
          'success': true,
          'data': [
            {'id': 'E1', 'matricule': 'M01', 'badge': 'PV12AB34', 'nom': 'KOUASSI', 'prenoms': 'Awa', 'statut': 'ACTIF'},
            {'id': 'E2', 'matricule': 'M02', 'badge': '04A1B2C3', 'nom': 'YAO', 'prenoms': 'Koffi', 'statut': 'ACTIF'},
          ],
        }));
      } else if (chemin.endsWith('/rh/pointages') && req.method == 'POST') {
        typesContenu.add(req.headers.contentType?.mimeType ?? '');
        tailles.add(corps.length);
        posts.add(Map<String, dynamic>.from(jsonDecode(corps) as Map));
        res.write(jsonEncode({'success': true, 'message': 'Pointage manuel enregistré.'}));
      } else {
        res.statusCode = 404;
      }
      await res.close();
    });
  }

  int get port => http.port;
  Future<void> arreter() => http.close(force: true);
}

void main() {
  late _Serveur serveur;
  late String base;
  late _Camera camera;
  late StockagePhotosMemoire stockage;
  late RegistrePhotosPointage registre;
  late JournalTerminal journal;
  late PointageRh pr;
  final maintenant = DateTime.now();
  final photoCapteur = _photoCapteur();

  Future<void> monter(Future<void> Function() corps) => HttpOverrides.runWithHttpOverrides(() async {
        SharedPreferences.setMockInitialValues({});
        await DioClient.cookieJar.deleteAll();
        serveur = _Serveur();
        await serveur.demarrer();
        base = 'http://127.0.0.1:${serveur.port}/prestige/api/v1';
        camera = _Camera(photoCapteur);
        stockage = StockagePhotosMemoire();
        journal = JournalTerminal(store: MemoryJournalStore());
        registre = RegistrePhotosPointage(stockage: stockage, journal: () => journal, retentionJours: () async => 30);
        pr = PointageRh(
          store: MemoryRhStore(),
          serveur: DioRhServeur(() => base),
          photos: PhotoControle(
            camera: camera,
            registre: registre,
            reglages: () async => const ReglagesPointageTerminal(),
            compresser: (b) async => compresserPhoto(b),
            delaiApercu: const Duration(milliseconds: 80),
          ),
          horsLigne: () => false,
          nomTerminal: () => 'Accueil',
          journal: () => journal,
        );
        try {
          await corps();
        } finally {
          await serveur.arreter();
          await DioClient.cookieJar.deleteAll();
        }
      }, _RealHttp());

  /// Lecture du badge puis pointage avec la photo de contrôle (comme l'écran du terminal).
  Future<ResultatBadge> pointer(String badge) async {
    final l = await pr.lireAvecRafraichissement(badge);
    expect(l, isA<BadgeAConfirmer>());
    final a = l as BadgeAConfirmer;
    final capture = pr.photos!.demarrer();
    try {
      return await pr.enregistrerAvecPhoto(a, a.sens, photo: capture.resultat);
    } finally {
      capture.dispose();
    }
  }

  test('badge → photo (caméra simulée) → POST rh/pointages : contrat inchangé, photo gardée sur le terminal et liée', () async {
    await monter(() async {
      expect(await pr.rafraichirEmployes(), isNull);
      final r = await pointer('pv12ab34');
      expect(r.issue, IssueBadge.enregistre);
      // Serveur : le corps JSON habituel, sans photo (le serveur n'en accepte pas), petit.
      expect(serveur.posts.single.keys, unorderedEquals(['employeId', 'jour', 'heure', 'sens', 'motif']));
      expect(serveur.posts.single['employeId'], 'E1');
      expect(serveur.posts.single['sens'], 'ENTREE');
      expect(serveur.posts.single['motif'], 'Badge terminal Accueil');
      expect(serveur.typesContenu.single, 'application/json');
      expect(serveur.tailles.single, lessThan(400));
      // Terminal : photo compressée liée à l'identifiant du pointage.
      final p = registre.photos.single;
      expect(p.id, r.pointage.id);
      expect(p.avecPhoto, isTrue);
      expect(p.envoi, StatutPointageBadge.envoye.name);
      final jpeg = await registre.image(p.id);
      expect(jpeg!.length, lessThan(100 * 1024));
      final d = img.decodeJpg(jpeg)!;
      expect(max(d.width, d.height), lessThanOrEqualTo(640));
      expect(camera.captures, 1);
      // Aucune photo dans le journal.
      await journal.idle;
      final j = [for (final x in await journal.lire()) '${x.action} ${x.motif} ${x.refLocale}'].join('\n');
      expect(j, contains('Photo de contrôle prise'));
      expect(j, isNot(contains(base64Encode(jpeg).substring(0, 40))));
    });
  });

  test('caméra en échec → pointage envoyé quand même, marqué « sans photo (motif) » et signalé', () async {
    await monter(() async {
      await pr.rafraichirEmployes();
      camera.echec = MotifSansPhoto.permissionRefusee;
      final r = await pointer('04A1B2C3');
      expect(r.issue, IssueBadge.enregistre);
      expect(serveur.posts.single['employeId'], 'E2');
      final p = registre.photos.single;
      expect([p.id, p.avecPhoto, p.motif], [r.pointage.id, false, MotifSansPhoto.permissionRefusee]);
      expect(registre.anomaliesNonTraitees, 1);
      expect(registre.anomaliesList.single.type, contains('sans photo (autorisation de la caméra refusée)'));
      await journal.idle;
      expect((await journal.lire()).map((x) => x.action).join('\n'), contains('sans photo (autorisation de la caméra refusée)'));
      expect(await registre.image(p.id), isNull);
    });
  });

  test('serveur injoignable → pointage gardé en file AVEC sa photo ; au retour du serveur, envoyé et état mis à jour', () async {
    await monter(() async {
      await pr.rafraichirEmployes();
      final port = serveur.port;
      await serveur.arreter();
      final r = await pointer('PV12AB34');
      expect(r.issue, IssueBadge.enFile);
      expect(pr.enAttente, 1);
      final p = registre.photos.single;
      expect(p.id, r.pointage.id);
      expect(p.avecPhoto, isTrue);
      expect(p.envoi, StatutPointageBadge.enAttente.name);
      // Retour du serveur (même adresse) : la file part, la photo suit l'état d'envoi.
      await serveur.demarrer(port);
      final bilan = await pr.envoyer();
      expect(bilan.envoyes, 1);
      expect(serveur.posts.single['employeId'], 'E1');
      expect(serveur.posts.single.containsKey('photo'), isFalse);
      expect(registre.photos.single.envoi, StatutPointageBadge.envoye.name);
      // 31 jours plus tard (conservation 30 j par défaut), la photo est effacée automatiquement.
      final plusTard = RegistrePhotosPointage(
          stockage: stockage, clock: () => maintenant.add(const Duration(days: 31)), journal: () => journal, retentionJours: () async => 30);
      await plusTard.charger();
      expect(plusTard.photos, isEmpty);
      expect(stockage.images, isEmpty);
    });
  });
}
