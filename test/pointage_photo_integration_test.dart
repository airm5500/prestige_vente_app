// Intégration : flux complet du pointage par badge avec photo de contrôle, contre un serveur Prestige simulé
// (HttpServer local, vraies requêtes HTTP de DioRhServeur) :
// badge lu → caméra frontale (simulée) → photo compressée gardée sur le terminal → POST v1/rh/pointages ; caméra en
// échec → pointage envoyé quand même, marqué « sans photo » ; serveur injoignable → pointage en file avec sa photo,
// puis envoyé au retour du serveur.
// 4.3.0 (réponse du serveur du 15/10/2026, demande 31) : le corps porte en plus `id` (identifiant du terminal) et
// `controle` ; serveur À JOUR : photo envoyée en multipart (POST rh/pointages/{id}/photo), renvoi du même id →
// `deja:true` (déjà enregistré) ; serveur ANCIEN (route photo absente, 404) : une seule tentative par session, la
// photo reste sur le terminal comme avant.
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

  /// Serveur à jour (demande 31) : route photo et `id` du terminal gérés.
  bool aJour = false;
  final ids = <String>{};

  /// Envois de la photo : chemin, type de contenu, taille du corps, champs du formulaire présents.
  final photos = <({String chemin, String type, int taille, bool champPhoto, bool champPrise, bool jpeg})>[];
  int statutPhoto = 200;
  Map<String, dynamic> reponsePhoto = const {'success': true, 'message': 'Photo de contrôle enregistrée.'};

  Future<void> demarrer([int port = 0]) async {
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    http.listen((req) async {
      final res = req.response..headers.contentType = ContentType.json;
      final chemin = req.uri.path;
      if (chemin.contains('/rh/pointages/') && chemin.endsWith('/photo') && req.method == 'POST') {
        final octets = await req.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
        final texte = latin1.decode(octets);
        photos.add((
          chemin: chemin,
          type: req.headers.contentType?.mimeType ?? '',
          taille: octets.length,
          champPhoto: texte.contains('name="photo"'),
          champPrise: texte.contains('name="prise"'),
          jpeg: texte.contains('\u00ff\u00d8\u00ff'),
        ));
        if (!aJour) {
          res.statusCode = 404;
        } else {
          res.statusCode = statutPhoto;
          res.write(jsonEncode(reponsePhoto));
        }
        await res.close();
        return;
      }
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
        final j = Map<String, dynamic>.from(jsonDecode(corps) as Map);
        posts.add(j);
        final id = '${j['id'] ?? ''}';
        if (aJour && id.isNotEmpty && !ids.add(id)) {
          res.write(jsonEncode({'success': true, 'id': id, 'deja': true, 'message': 'Pointage déjà existant.'}));
        } else {
          res.write(jsonEncode({'success': true, if (aJour) 'id': id, 'message': 'Pointage manuel enregistré.'}));
        }
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

  test('badge → photo (caméra simulée) → POST rh/pointages (+ id et contrôle), photo gardée sur le terminal et liée ; serveur ancien : 1 essai d\'envoi de photo (404)', () async {
    await monter(() async {
      expect(await pr.rafraichirEmployes(), isNull);
      final r = await pointer('pv12ab34');
      expect(r.issue, IssueBadge.enregistre);
      // Serveur : le corps JSON habituel + id du terminal et contrôle (4.3.0), sans photo, petit.
      expect(serveur.posts.single.keys, unorderedEquals(['id', 'employeId', 'jour', 'heure', 'sens', 'motif', 'controle']));
      expect(serveur.posts.single['id'], r.pointage.id);
      expect(serveur.posts.single['controle'], {'photo': true});
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
      // Serveur ancien : la route photo répond 404 → la photo reste ici, plus d'essai pendant la session.
      await pr.envoiPhotos;
      expect(serveur.photos, hasLength(1));
      expect(registre.photos.single.photoServeur, '', reason: 'pas marquée envoyée');
      await pointer('04A1B2C3');
      await pr.envoiPhotos;
      expect(serveur.photos, hasLength(1), reason: 'route absente : aucun nouvel essai');
    });
  });

  test('serveur À JOUR (demande 31) : photo envoyée en multipart après le pointage, liée par l\'id ; renvoi du même id → déjà enregistré', () async {
    await monter(() async {
      serveur.aJour = true;
      await pr.rafraichirEmployes();
      final r = await pointer('PV12AB34');
      expect(r.issue, IssueBadge.enregistre);
      expect(await pr.envoiPhotos, 1);
      final ph = serveur.photos.single;
      expect(ph.chemin, endsWith('/rh/pointages/${r.pointage.id}/photo'));
      expect(ph.type, 'multipart/form-data');
      expect([ph.champPhoto, ph.champPrise, ph.jpeg], [true, true, true]);
      expect(ph.taille, lessThan(150 * 1024), reason: 'limite du serveur : 150 Ko');
      expect(registre.photos.single.photoServeur, 'envoyee');
      // Aucune photo renvoyée ensuite.
      expect(await pr.envoyerPhotos(), 0);
      expect(serveur.photos, hasLength(1));
      // Même pointage renvoyé (réponse perdue puis file rejouée) : deja:true → déjà enregistré, rien de créé.
      final again = await DioRhServeur(() => base).post('/rh/pointages', r.pointage.corps);
      expect(again.body?['deja'], isTrue);
      await journal.idle;
      final j = [for (final x in await journal.lire()) '${x.action} ${x.motif}'].join('\n');
      expect(j, contains('Photo de contrôle envoyée à Prestige'));
    });
  });

  test('serveur À JOUR : refus de la photo (trop lourde) → marquée refusée, jamais renvoyée en boucle ; sans photo → contrôle {photo:false, motif}', () async {
    await monter(() async {
      serveur.aJour = true;
      serveur.reponsePhoto = const {'success': false, 'message': 'Photo trop lourde : 160 Ko, 150 Ko au plus.'};
      await pr.rafraichirEmployes();
      await pointer('PV12AB34');
      await pr.envoiPhotos;
      expect(registre.photos.single.photoServeur, 'refusee');
      expect(await pr.envoyerPhotos(), 0);
      expect(serveur.photos, hasLength(1));
      camera.echec = MotifSansPhoto.cameraAbsente;
      await pointer('04A1B2C3');
      expect(serveur.posts.last['controle'], {'photo': false, 'motif': 'CAMERA_ABSENTE'});
      await pr.envoiPhotos;
      expect(serveur.photos, hasLength(1), reason: 'aucune photo à envoyer pour un pointage sans photo');
    });
  });

  test('caméra en échec → pointage envoyé quand même, marqué « sans photo (motif) » et signalé', () async {
    await monter(() async {
      await pr.rafraichirEmployes();
      camera.echec = MotifSansPhoto.permissionRefusee;
      final r = await pointer('04A1B2C3');
      expect(r.issue, IssueBadge.enregistre);
      expect(serveur.posts.single['employeId'], 'E2');
      expect(serveur.posts.single['controle'], {'photo': false, 'motif': 'PERMISSION_REFUSEE'});
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
      await pr.envoiPhotos;
      expect(serveur.posts.single['employeId'], 'E1');
      expect(serveur.posts.single.containsKey('photo'), isFalse);
      expect(serveur.posts.single['id'], r.pointage.id, reason: 'même identifiant que celui de la file');
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
