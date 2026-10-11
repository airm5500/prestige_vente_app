// H5 — mise à jour différentielle du catalogue (patch serveur docs/serveur/H5_catalogue_delta.patch).
// - sans capacité (ancien serveur, 401 « expire ») : copie complète d'origine, jamais de changements ;
// - avec capacité : copie complète une première fois, puis seulement les changements (5 min, et 30 min) ;
// - suppression / ajout, chevauchement de 2 min, horloge du SERVEUR (pas celle du téléphone) ;
// - vérification complète quotidienne (suppressions que les changements ne voient pas) ;
// - transaction : échec d'écriture = rien d'appliqué, curseur inchangé (mémoire et SQLite) ;
// - repli sur la copie complète, pause pendant l'activité, minuterie 5 min, Réglages ;
// - intégration contre le serveur de test (sautée s'il est injoignable ou sans le patch).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/horsligne/catalogue_delta.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/routes_app_vente.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/horsligne/ventes_sync.dart';
import 'package:prestige_vente_app/parametres/hors_ligne_page.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> _prod(String id, String name, {int stock = 3, int prix = 1000}) => {
      'lgFAMILLEID': id,
      'strNAME': name,
      'strDESCRIPTION': name,
      'intCIP': '30${id.hashCode.abs() % 100000}',
      'intPRICE': prix,
      'intNUMBERAVAILABLE': stock,
      'intNUMBER': stock,
      'strLIBELLEE': 'RAYON A',
      'intPAF': 800,
      'lgFAMILLEPARENTID': '',
      'boolDECONDITIONNE': 0,
    };

/// Faux serveur Prestige : catalogue, horloge propre (≠ téléphone), journal des modifications.
class _Srv {
  /// Horloge du SERVEUR (base de données).
  DateTime now = DateTime.utc(2026, 10, 10, 14, 0, 0);
  final Map<String, Map<String, dynamic>> produits = {};
  final Map<String, DateTime> modifie = {};
  bool capacite = true;

  /// Préfixe des routes H5 servies : '/app-vente' (patch actuel) ou '/mobile' (1ʳᵉ version du patch).
  String prefixe = RoutesAppVente.prefixe;
  bool deltaEnPanne = false;
  final log = <String>[];
  final requetes = <Map<String, dynamic>>[];

  /// Appelé pendant la copie complète (modification pendant le téléchargement).
  void Function()? pendantCopie;

  _Srv(int n) {
    for (var i = 1; i <= n; i++) {
      produits['p$i'] = _prod('p$i', 'PRODUIT ${i.toString().padLeft(3, '0')}');
    }
  }

  void maj(String id, Map<String, dynamic> row) {
    produits[id] = row;
    modifie[id] = now;
  }

  void supprimer(String id) {
    produits.remove(id);
    modifie[id] = now;
  }

  void avance(Duration d) => now = now.add(d);

  int compte(String path) => log.where((p) => p == path).length;

  /// Même lecture que l'appli (HorsLigne._capacites) : /app-vente/capacites, repli sur /mobile/capacites.
  Future<({int status, Object? body})> capacites() async {
    final r = await RoutesAppVente.lireCapacites(_serveurTest, (chemin) async {
      log.add(chemin);
      if (capacite && chemin == '$prefixe/capacites') {
        return (
          status: 200,
          body: {'success': true, 'clientRef': true, 'catalogueDelta': true, 'serveurMaintenant': CatalogueDelta.ecrireHeure(now)}
        );
      }
      // Route inconnue : 404 ; v1/mobile/ de la branche serveur à jour = API à jeton → 401 « expire ».
      if (chemin == '/mobile/capacites') return (status: 401, body: {'success': false, 'expire': true});
      return (status: 404, body: <String, dynamic>{});
    });
    return (status: r.status, body: r.body);
  }

  Future<Map<String, dynamic>> fetch(String path, Map<String, dynamic> q) async {
    log.add(path);
    switch (path) {
      case '/vente/search':
        pendantCopie?.call();
        final l = produits.values.toList()..sort((a, b) => '${a['lgFAMILLEID']}'.compareTo('${b['lgFAMILLEID']}'));
        final start = q['start'] as int, limit = q['limit'] as int;
        return {'total': l.length, 'data': l.skip(start).take(limit).toList()};
      case final p when p == '$prefixe/catalogue/changements':
        if (deltaEnPanne || !capacite) throw const CatalogueSyncException('Erreur du serveur (code 404).');
        requetes.add(Map.of(q));
        final depuis = CatalogueDelta.lireHeure('${q['depuis']}')!;
        final jusqua = q['jusqua'] == null ? now : CatalogueDelta.lireHeure('${q['jusqua']}')!;
        final ids = [
          for (final e in modifie.entries)
            if (e.value.isAfter(depuis) && !e.value.isAfter(jusqua)) e.key
        ]..sort();
        final start = q['start'] as int, limit = q['limit'] as int;
        return {
          'success': true,
          'depuis': q['depuis'],
          'serveurMaintenant': CatalogueDelta.ecrireHeure(jusqua),
          'total': ids.length,
          'data': [
            for (final id in ids.skip(start).take(limit))
              produits.containsKey(id) ? {...produits[id]!, 'statut': 'actif'} : {'lgFAMILLEID': id, 'statut': 'supprime'}
          ],
        };
      default:
        return {'total': 0, 'data': <Object>[]};
    }
  }
}

class _Env {
  final _Srv srv;
  final LocalStore store;
  final CatalogueSync sync;
  DateTime phone;
  _Env(this.srv, this.store, this.sync, this.phone);

  Future<Map<String, dynamic>?> local(String id) async {
    final page = await store.searchProducts('%', 0, 10000);
    for (final p in page.items) {
      if (p.lgFAMILLEID == id) return {'stock': p.intNUMBERAVAILABLE, 'nom': p.strNAME};
    }
    return null;
  }

  Future<int> count() async => (await store.stats()).count(CatalogueCategorie.produits);
}

const _serveurTest = 'http://srv-test/prestige/api/v1';

_Env _env({int n = 12, bool capacite = true, LocalStore? store, int pageSize = 5, bool Function()? occupee}) {
  final srv = _Srv(n)..capacite = capacite;
  final s = store ?? MemoryLocalStore();
  late _Env env;
  final sync = CatalogueSync(
    store: s,
    fetch: srv.fetch,
    clock: () => env.phone,
    pageSize: pageSize,
    pause: const Duration(milliseconds: 5),
    occupee: occupee ?? () => false,
  )
    ..capacites = srv.capacites
    ..serveur = () => _serveurTest;
  // Téléphone volontairement DÉCALÉ du serveur (ici : 5 h 30 de moins).
  env = _Env(srv, s, sync, DateTime(2026, 10, 10, 8, 30));
  return env;
}

bool _ffiOk() {
  try {
    sqfliteFfiInit();
    return true;
  } catch (_) {
    return false;
  }
}

class _RealHttp extends HttpOverrides {}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RoutesAppVente.vider();
  });
  final ffi = _ffiOk() && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  group('sans capacité (serveur sans le patch H5)', () {
    test('copie complète à chaque mise à jour, aucun appel aux changements, rien affiché', () async {
      final e = _env(capacite: false);
      expect(await e.sync.syncAll(auto: true), isTrue);
      expect(e.srv.compte('/vente/search'), 3); // 12 produits, pages de 5
      expect(await e.count(), 12);
      e.srv.avance(const Duration(minutes: 3));
      e.srv.maj('p2', _prod('p2', 'PRODUIT 002', stock: 9));
      expect(await e.sync.syncChangements(), isFalse);
      expect(e.srv.compte(CatalogueDelta.route), 0);
      expect(e.sync.deltaActif, isFalse);
      expect(e.sync.deltaLibelle, isNull);
      expect(await e.sync.syncAll(auto: true), isTrue);
      expect(e.srv.compte('/vente/search'), 6, reason: 'copie complète, comme avant');
      expect(e.srv.compte(CatalogueDelta.route), 0);
      expect((await e.local('p2'))!['stock'], 9);
      expect(await e.store.metas(CatalogueDelta.prefixe), isEmpty);
    });

    test('sans branchement des capacités : exactement le fonctionnement d\'origine', () async {
      final e = _env();
      e.sync.capacites = null;
      expect(await e.sync.syncAll(auto: true), isTrue);
      expect(await e.sync.syncAll(auto: true), isTrue);
      expect(e.srv.log.where((p) => p.endsWith('/capacites') || p == CatalogueDelta.route), isEmpty);
      expect(e.srv.compte('/vente/search'), 6);
      expect(e.sync.deltaActif, isFalse);
    });

    test('capacité perdue (serveur remplacé par une version sans H5) : retour à la copie complète, curseur oublié', () async {
      final e = _env();
      await e.sync.syncAll(auto: true);
      expect(e.sync.deltaActif, isTrue);
      e.srv.capacite = false;
      e.srv.avance(const Duration(minutes: 5));
      expect(await e.sync.syncChangements(), isTrue, reason: e.sync.error);
      expect(e.srv.compte('/vente/search'), 6, reason: 'repli sur la copie complète');
      expect(e.sync.deltaActif, isFalse);
      expect(await e.store.metas(CatalogueDelta.prefixe), isEmpty);
      expect(await e.sync.syncChangements(), isFalse);
    });
  });

  group('préfixe des routes (/app-vente, repli /mobile)', () {
    test('nouveau préfixe : une seule lecture des capacités, changements sous /app-vente', () async {
      final e = _env();
      expect(await e.sync.syncAll(auto: true), isTrue);
      expect(e.srv.log.where((p) => p.endsWith('/capacites')), ['/app-vente/capacites']);
      expect(e.sync.delta.prefixe, '/app-vente');
      e.srv.avance(const Duration(minutes: 5));
      e.srv.maj('p2', _prod('p2', 'PRODUIT 002', stock: 7));
      final avant = e.srv.log.length;
      expect(await e.sync.syncChangements(), isTrue, reason: e.sync.error);
      expect(e.srv.log.sublist(avant), ['/app-vente/catalogue/changements']);
      expect((await e.local('p2'))!['stock'], 7);
    });

    test('ancien préfixe (serveur de test, 1ʳᵉ version du patch) : repli, changements sous /mobile, gardé après redémarrage',
        () async {
      final store = MemoryLocalStore();
      var e = _env(store: store);
      e.srv.prefixe = '/mobile';
      expect(await e.sync.syncAll(auto: true), isTrue);
      expect(e.srv.log.where((p) => p.endsWith('/capacites')), ['/app-vente/capacites', '/mobile/capacites']);
      expect(e.sync.deltaActif, isTrue);
      expect(e.sync.delta.prefixe, '/mobile');
      // Redémarrage de l'appli : préfixe relu dans la copie locale, sans nouvelle lecture des capacités.
      RoutesAppVente.vider();
      final srv = e.srv;
      e = _env(store: store);
      e.srv
        ..prefixe = '/mobile'
        ..now = srv.now.add(const Duration(minutes: 5))
        ..maj('p2', _prod('p2', 'PRODUIT 002', stock: 4));
      await e.sync.refreshStats();
      expect(e.sync.deltaActif, isTrue);
      expect(await e.sync.syncChangements(), isTrue, reason: e.sync.error);
      expect(e.srv.log, ['/mobile/catalogue/changements']);
      expect((await e.local('p2'))!['stock'], 4);
    });

    test('serveur passé de /mobile à /app-vente (patchs mis à jour) : copie complète de reprise, puis /app-vente', () async {
      final e = _env();
      e.srv.prefixe = '/mobile';
      await e.sync.syncAll(auto: true);
      expect(e.sync.delta.prefixe, '/mobile');
      e.srv.prefixe = '/app-vente';
      e.srv.avance(const Duration(minutes: 5));
      expect(await e.sync.syncChangements(), isTrue, reason: e.sync.error);
      expect(e.sync.delta.prefixe, '/app-vente', reason: 'préfixe relu avec la capacité lors de la copie de reprise');
      e.srv.avance(const Duration(minutes: 5));
      final avant = e.srv.log.length;
      expect(await e.sync.syncChangements(), isTrue, reason: e.sync.error);
      expect(e.srv.log.sublist(avant), ['/app-vente/catalogue/changements']);
    });

    test('aucun préfixe (serveur à jour sans H5) : 404 puis 401 « expire » → copie complète, rien gardé', () async {
      final e = _env(capacite: false);
      expect(await e.sync.syncAll(auto: true), isTrue);
      expect(e.srv.log.where((p) => p.endsWith('/capacites')), ['/app-vente/capacites', '/mobile/capacites']);
      expect(e.sync.deltaActif, isFalse);
      expect(await e.store.metas(CatalogueDelta.prefixe), isEmpty);
    });
  });

  group('avec capacité', () {
    test('copie complète une première fois, puis seulement les changements', () async {
      final e = _env();
      expect(await e.sync.syncAll(auto: true), isTrue);
      expect(e.srv.compte('/vente/search'), 3);
      expect(e.srv.compte(CatalogueDelta.route), 0);
      expect(e.sync.delta.curseur, '2026-10-10 14:00:00', reason: 'horloge du serveur lue avant la copie');
      expect(e.sync.deltaActif, isTrue);
      expect(e.sync.deltaLibelle, 'Dernière mise à jour : à l\'instant (copie complète)');

      e.srv.avance(const Duration(minutes: 5));
      e.srv.maj('p2', _prod('p2', 'PRODUIT 002', stock: 7, prix: 1200));
      e.phone = e.phone.add(const Duration(minutes: 5));
      final avant = e.srv.log.length;
      expect(await e.sync.syncChangements(), isTrue, reason: e.sync.error);
      expect(e.srv.log.sublist(avant), [CatalogueDelta.route], reason: 'une seule requête, pas de copie complète');
      expect((await e.local('p2'))!['stock'], 7);
      expect(await e.count(), 12);
      expect(e.sync.delta.n, 1);
      expect(e.sync.delta.curseur, '2026-10-10 14:05:00');
      expect(e.sync.deltaLibelle, 'Dernière mise à jour : à l\'instant (1 produit modifié)');
      e.phone = e.phone.add(const Duration(minutes: 4));
      expect(e.sync.deltaLibelle, 'Dernière mise à jour : il y a 4 min (1 produit modifié)');
      expect(e.sync.catalogueAt, DateTime(2026, 10, 10, 8, 35), reason: 'date du catalogue = dernière mise à jour');

      // Mise à jour automatique des 30 min : produits par changements, le reste en entier.
      e.srv.avance(const Duration(minutes: 1));
      e.srv.maj('p3', _prod('p3', 'PRODUIT 003', stock: 0));
      e.srv.maj('p4', _prod('p4', 'PRODUIT 004', stock: 1));
      final a2 = e.srv.log.length;
      expect(await e.sync.syncAll(auto: true), isTrue);
      final l2 = e.srv.log.sublist(a2);
      expect(l2, isNot(contains('/vente/search')));
      expect(l2, contains(CatalogueDelta.route));
      expect(l2, contains('/client/all'));
      expect(e.sync.delta.n, 3, reason: 'p2 (chevauchement) + p3 + p4');
      expect((await e.local('p3'))!['stock'], 0);

      // Mise à jour manuelle : copie complète (et nouveau curseur).
      e.srv.avance(const Duration(minutes: 1));
      final a3 = e.srv.log.length;
      expect(await e.sync.syncAll(), isTrue);
      expect(e.srv.log.sublist(a3), contains('/vente/search'));
      expect(e.sync.delta.curseur, '2026-10-10 14:07:00');
      expect(e.sync.delta.n, isNull);
    });

    test('produit supprimé / désactivé retiré, nouveau produit ajouté, ligne identique au serveur', () async {
      final e = _env();
      await e.sync.syncAll(auto: true);
      e.srv.avance(const Duration(minutes: 5));
      e.srv.supprimer('p1');
      e.srv.maj('p99', _prod('p99', 'NOUVEAU PRODUIT', stock: 4));
      expect(await e.sync.syncChangements(), isTrue, reason: e.sync.error);
      expect(await e.local('p1'), isNull);
      expect((await e.local('p99'))!['stock'], 4);
      expect(await e.count(), 12);
      final p = (await e.store.searchProducts('NOUVEAU', 0, 10)).items.single;
      expect(p.lgFAMILLEID, 'p99');
      expect(e.sync.delta.n, 2);
      expect(e.sync.deltaLibelle, contains('(2 produits modifiés)'));
      // Ré-activé ensuite : revient.
      e.srv.avance(const Duration(minutes: 5));
      e.srv.maj('p1', _prod('p1', 'PRODUIT 001'));
      await e.sync.syncChangements();
      expect(await e.local('p1'), isNotNull);
    });

    test('pages des changements figées par « jusqua » (curseur = horloge de la 1ʳᵉ page)', () async {
      final e = _env(n: 30);
      await e.sync.syncAll(auto: true);
      e.srv.avance(const Duration(minutes: 5));
      for (var i = 1; i <= 12; i++) {
        e.srv.maj('p$i', _prod('p$i', 'PRODUIT ${i.toString().padLeft(3, '0')}', stock: 50 + i));
      }
      // Progression affichée comme pour la copie complète (étape 1/1, pages).
      final vus = <String>{};
      void ecoute() {
        if (e.sync.running && e.sync.progressionLabel != null) vus.add('${e.sync.etapeNum}/${e.sync.etapesTotal} ${e.sync.progressionLabel}');
      }

      e.sync.addListener(ecoute);
      expect(await e.sync.syncChangements(), isTrue, reason: e.sync.error);
      e.sync.removeListener(ecoute);
      expect(vus, containsAll(['1/1 Produits (changements) : page 1/3 (5 / 12)', '1/1 Produits (changements) : page 3/3 (12 / 12)']));
      expect(e.srv.requetes.length, 3, reason: '12 changements, pages de 5');
      expect(e.srv.requetes.first.containsKey('jusqua'), isFalse);
      expect(e.srv.requetes.skip(1).map((q) => q['jusqua']).toSet(), {'2026-10-10 14:05:00'});
      expect([for (final q in e.srv.requetes) q['start']], [0, 5, 10]);
      expect((await e.local('p12'))!['stock'], 62);
      expect(e.sync.delta.n, 12);
    });
  });

  group('chevauchement et horloge du serveur', () {
    test('depuis = dernier serveurMaintenant − 2 min ; modification de la même seconde jamais perdue', () async {
      final e = _env();
      await e.sync.syncAll(auto: true); // curseur 14:00:00
      // Modifiée À LA MÊME SECONDE que l'horloge lue, mais après la lecture.
      e.srv.maj('p5', _prod('p5', 'PRODUIT 005', stock: 0));
      e.srv.avance(const Duration(seconds: 50));
      expect(await e.sync.syncChangements(), isTrue);
      expect(e.srv.requetes.single['depuis'], '2026-10-10 13:58:00');
      expect((await e.local('p5'))!['stock'], 0);
      // Suivante : depuis = 14:00:50 − 2 min ; p5 renvoyé (chevauchement), sans effet.
      e.srv.avance(const Duration(minutes: 5));
      await e.sync.syncChangements();
      expect(e.srv.requetes.last['depuis'], '2026-10-10 13:58:50');
      expect(e.sync.delta.n, 1);
      e.srv.avance(const Duration(minutes: 5));
      await e.sync.syncChangements();
      expect(e.sync.delta.n, 0);
      expect(e.sync.deltaLibelle, 'Dernière mise à jour : à l\'instant (0 produit modifié)');
    });

    test('horloge du téléphone ignorée : téléphone en avance d\'un an ou en retard, même requête', () async {
      for (final phone in [DateTime(2027, 10, 10, 9), DateTime(2020, 1, 1, 9)]) {
        final e = _env();
        e.phone = phone;
        await e.sync.syncAll(auto: true);
        e.srv.avance(const Duration(minutes: 5));
        e.srv.maj('p2', _prod('p2', 'PRODUIT 002', stock: 8));
        expect(await e.sync.syncChangements(), isTrue);
        expect(e.srv.requetes.single['depuis'], '2026-10-10 13:58:00');
        expect((await e.local('p2'))!['stock'], 8);
      }
    });

    test('modification PENDANT la copie complète : rattrapée par les changements suivants', () async {
      final e = _env(n: 12);
      var fait = false;
      e.srv.pendantCopie = () {
        // Après la 1ʳᵉ page (p1..p5 déjà reçus) : p1 change sur le serveur.
        if (e.srv.log.where((p) => p == '/vente/search').length == 2 && !fait) {
          fait = true;
          e.srv.avance(const Duration(seconds: 20));
          e.srv.maj('p1', _prod('p1', 'PRODUIT 001', stock: 0));
        }
      };
      await e.sync.syncAll(auto: true);
      expect((await e.local('p1'))!['stock'], 3, reason: 'copie téléchargée avant la modification');
      expect(e.sync.delta.curseur, '2026-10-10 14:00:00', reason: 'horloge lue AVANT le téléchargement');
      e.srv.avance(const Duration(minutes: 5));
      await e.sync.syncChangements();
      expect((await e.local('p1'))!['stock'], 0);
    });

    test('heures du serveur : lecture / écriture', () {
      expect(CatalogueDelta.lireHeure('2026-10-10 23:14:35'), DateTime.utc(2026, 10, 10, 23, 14, 35));
      expect(CatalogueDelta.lireHeure('2026-10-10T23:14:35.000'), DateTime.utc(2026, 10, 10, 23, 14, 35));
      expect(CatalogueDelta.lireHeure('2026-02-31 10:00:00'), isNull);
      expect(CatalogueDelta.lireHeure('hier'), isNull);
      expect(CatalogueDelta.depuis('2026-10-11 00:01:00'), '2026-10-10 23:59:00');
      expect(CatalogueDelta.capaciteDepuisReponse(200, {'catalogueDelta': true}), isTrue);
      expect(CatalogueDelta.capaciteDepuisReponse(200, {'clientRef': true}), isFalse);
      expect(CatalogueDelta.capaciteDepuisReponse(401, {'expire': true}), isFalse);
      expect(CatalogueDelta.capaciteDepuisReponse(404, null), isFalse);
      expect(CatalogueDelta.capaciteDepuisReponse(500, null), isNull);
    });
  });

  group('vérification complète quotidienne', () {
    test('première mise à jour d\'un nouveau jour : copie complète (suppressions oubliées rattrapées)', () async {
      final e = _env();
      await e.sync.syncAll(auto: true);
      // Produit retiré sans trace visible par les changements (ex. suppression par l'ancien écran).
      e.srv.produits.remove('p6');
      e.srv.avance(const Duration(minutes: 5));
      e.phone = DateTime(2026, 10, 10, 23, 50);
      await e.sync.syncChangements();
      expect(await e.local('p6'), isNotNull, reason: 'même jour : changements seulement');
      expect(e.srv.compte('/vente/search'), 3);
      // La nuit (après minuit) : copie complète.
      e.phone = DateTime(2026, 10, 11, 0, 5);
      e.srv.avance(const Duration(minutes: 15));
      expect(await e.sync.syncChangements(), isTrue);
      expect(e.srv.compte('/vente/search'), 6);
      expect(await e.local('p6'), isNull);
      expect(e.sync.delta.complet, DateTime(2026, 10, 11, 0, 5));
      expect(e.sync.delta.curseur, CatalogueDelta.ecrireHeure(e.srv.now));
      // Puis de nouveau les changements seulement.
      e.phone = DateTime(2026, 10, 11, 0, 10);
      e.srv.avance(const Duration(minutes: 5));
      await e.sync.syncChangements();
      expect(e.srv.compte('/vente/search'), 6);
    });

    test('première connexion du jour : copie complète même si la copie a moins de 12 h', () async {
      final e = _env();
      e.phone = DateTime(2026, 10, 10, 22, 0);
      await e.sync.syncAll(auto: true);
      e.phone = DateTime(2026, 10, 11, 7, 0);
      expect(e.sync.isStale(), isFalse, reason: '9 h seulement');
      e.srv.avance(const Duration(hours: 9));
      await e.sync.syncIfStale();
      expect(e.srv.compte('/vente/search'), 6);
      expect(e.sync.delta.complet, DateTime(2026, 10, 11, 7, 0));
      // Même jour, 2ᵉ connexion : rien.
      e.phone = DateTime(2026, 10, 11, 9, 0);
      await e.sync.syncIfStale();
      expect(e.srv.compte('/vente/search'), 6);
    });

    test('sans capacité, syncIfStale garde la règle des 12 h', () async {
      final e = _env(capacite: false);
      e.phone = DateTime(2026, 10, 10, 22, 0);
      await e.sync.syncAll(auto: true);
      e.phone = DateTime(2026, 10, 11, 7, 0);
      await e.sync.syncIfStale();
      expect(e.srv.compte('/vente/search'), 3);
    });
  });

  group('transaction', () {
    test('écriture refusée : rien appliqué, curseur inchangé ; la suivante applique tout', () async {
      final e = _env();
      await e.sync.syncAll(auto: true);
      e.srv.avance(const Duration(minutes: 5));
      e.srv.maj('p2', _prod('p2', 'PRODUIT 002', stock: 9));
      e.srv.supprimer('p3');
      (e.store as MemoryLocalStore).failNextWrite = true;
      expect(await e.sync.syncChangements(), isFalse);
      expect(e.sync.error, contains('écriture refusée'));
      expect((await e.local('p2'))!['stock'], 3);
      expect(await e.local('p3'), isNotNull);
      expect(e.sync.delta.curseur, '2026-10-10 14:00:00');
      e.srv.avance(const Duration(minutes: 5));
      expect(await e.sync.syncChangements(), isTrue);
      expect((await e.local('p2'))!['stock'], 9);
      expect(await e.local('p3'), isNull);
    });

    test('serveur injoignable pendant les changements : rien appliqué, curseur inchangé', () async {
      final e = _env();
      await e.sync.syncAll(auto: true);
      e.srv.avance(const Duration(minutes: 5));
      e.srv.maj('p2', _prod('p2', 'PRODUIT 002', stock: 9));
      e.sync.fetch = (p, q) async => throw const CatalogueSyncException('Serveur injoignable.', network: true);
      expect(await e.sync.syncChangements(), isFalse);
      expect(e.sync.delta.curseur, '2026-10-10 14:00:00');
      expect(e.srv.compte('/vente/search'), 3, reason: 'pas de repli sur la copie complète si le réseau est coupé');
    });

    test('réponse inattendue des changements : repli sur la copie complète', () async {
      final e = _env();
      await e.sync.syncAll(auto: true);
      e.srv.deltaEnPanne = true;
      e.srv.avance(const Duration(minutes: 5));
      expect(await e.sync.syncChangements(), isTrue);
      expect(e.srv.compte('/vente/search'), 6);
      expect(e.sync.deltaActif, isTrue);
    });

    test('SQLite : changements + curseur en une transaction ; échec = rien (ni suppression, ni curseur)', () async {
      final store = SqfliteLocalStore(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final e = _env(store: store);
      await e.sync.syncAll(auto: true);
      expect(await e.count(), 12);
      expect((await store.metas(CatalogueDelta.prefixe))[CatalogueDelta.kCurseur], '2026-10-10 14:00:00');
      // Échec au milieu : une ligne illisible (DateTime non sérialisable) après la suppression de p1.
      await expectLater(
          store.appliquerProduits([
            _prod('p2', 'PRODUIT 002', stock: 99),
            {..._prod('p4', 'PRODUIT 004'), 'bad': DateTime(2026)},
          ], ['p1'], DateTime(2026, 10, 10, 9), meta: {CatalogueDelta.kCurseur: '2026-10-10 15:00:00'}),
          throwsA(anything));
      expect(await e.local('p1'), isNotNull);
      expect((await e.local('p2'))!['stock'], 3);
      expect((await store.metas(CatalogueDelta.prefixe))[CatalogueDelta.kCurseur], '2026-10-10 14:00:00');
      // Cycle réel.
      e.srv.avance(const Duration(minutes: 5));
      e.srv.supprimer('p1');
      e.srv.maj('p2', _prod('p2', 'PRODUIT 002', stock: 99));
      e.phone = e.phone.add(const Duration(minutes: 5));
      expect(await e.sync.syncChangements(), isTrue, reason: e.sync.error);
      expect(await e.local('p1'), isNull);
      expect((await e.local('p2'))!['stock'], 99);
      expect(await e.count(), 11);
      final m = await store.metas(CatalogueDelta.prefixe);
      expect(m[CatalogueDelta.kCurseur], '2026-10-10 14:05:00');
      expect(m[CatalogueDelta.kN], '2');
      // « Vider la copie locale » efface aussi le curseur : la suivante sera complète.
      await store.clear();
      await e.sync.refreshStats();
      expect(e.sync.deltaActif, isFalse);
      await store.close();
    }, skip: ffi ? false : 'SQLite (ffi) indisponible');
  });

  group('automatique', () {
    test('pause tant que l\'utilisateur travaille, puis reprise', () async {
      var occupe = false;
      final e = _env(occupee: () => occupe);
      await e.sync.syncAll(auto: true);
      e.srv.avance(const Duration(minutes: 5));
      e.srv.maj('p2', _prod('p2', 'PRODUIT 002', stock: 9));
      occupe = true;
      final f = e.sync.syncChangements();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(e.sync.enPause, isTrue);
      expect(e.srv.compte(CatalogueDelta.route), 0);
      occupe = false;
      expect(await f, isTrue);
      expect((await e.local('p2'))!['stock'], 9);
    });

    testWidgets('minuterie : changements toutes les 5 min avec la capacité, rien sans', (tester) async {
      for (final cap in [true, false]) {
        final e = _env(capacite: cap);
        await tester.runAsync(() => e.sync.syncAll(auto: true));
        final avant = e.srv.log.length;
        e.sync.startAuto(() => true);
        e.srv.avance(const Duration(minutes: 5));
        await tester.pump(const Duration(minutes: 5));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        expect(e.srv.log.sublist(avant), cap ? [CatalogueDelta.route] : isEmpty);
        e.sync.stopAuto();
      }
    });

    testWidgets('Réglages › Hors ligne : « dernière mise à jour : il y a X min (N produits modifiés) »', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final e = _env();
      final hl = HorsLigne(monitor: ServerMonitor(ping: () async => true), store: e.store, sync: e.sync, ventes: FileVentesHL(store: MemoryVentesHLStore()));
      await tester.runAsync(() async {
        await e.sync.syncAll(auto: true);
        e.srv.avance(const Duration(minutes: 5));
        e.srv.maj('p2', _prod('p2', 'PRODUIT 002', stock: 9));
        e.srv.maj('p3', _prod('p3', 'PRODUIT 003', stock: 9));
        await e.sync.syncChangements();
      });
      e.phone = e.phone.add(const Duration(minutes: 3));
      await tester.pumpWidget(MaterialApp(home: HorsLignePage(horsLigne: hl)));
      await tester.pump();
      await tester.dragUntilVisible(find.byKey(const Key('maj_differentielle')), find.byType(ListView), const Offset(0, -200));
      expect(find.text('Dernière mise à jour : il y a 3 min (2 produits modifiés)'), findsOneWidget);
      await tester.dragUntilVisible(find.textContaining('toutes les 5 min'), find.byType(ListView), const Offset(0, -200));
      expect(find.textContaining('toutes les 5 min'), findsOneWidget);
    });
  });

  group('Intégration serveur de test', () {
    final url = Platform.environment['PRESTIGE_TEST_URL'] ?? 'http://localhost:8080/prestige/api/v1';

    test('vente clôturée → produit dans les changements, stock local à jour ; mesures complète / différentielle', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final api = ApiService(baseUrl: url);
        try {
          final r = await api.dio.get('/officine');
          if (r.statusCode != 200) throw StateError('code ${r.statusCode}');
        } catch (_) {
          markTestSkipped('Serveur de test injoignable : $url');
          return;
        }
        final user = await api.login('admin', 'Test1234');
        if (user == null) {
          markTestSkipped('Connexion impossible au serveur de test.');
          return;
        }
        final store = MemoryLocalStore();
        final hl = HorsLigne(monitor: ServerMonitor(ping: () async => true), store: store, ventes: FileVentesHL(store: MemoryVentesHLStore()));
        hl.bind(api);
        final sync = hl.sync;
        final cap = await sync.capacites!();
        if (CatalogueDelta.capaciteDepuisReponse(cap.status, cap.body) != true) {
          markTestSkipped('Serveur de test sans le patch H5.');
          return;
        }
        final sw = Stopwatch()..start();
        expect(await sync.syncAll(auto: true), isTrue, reason: sync.error);
        final complet = sw.elapsed;
        final n = (await store.stats()).count(CatalogueCategorie.produits);
        expect(sync.deltaActif, isTrue);
        // Vente comptant clôturée d'un produit en stock.
        final gw = DioVenteGateway(api);
        final page = await gw.searchProductsPage('A-CEF', 0, 20);
        final p = page.valueOrNull?.items.where((x) => x.intNUMBERAVAILABLE > 0).firstOrNull;
        if (p == null) {
          markTestSkipped('Aucun produit A-CEF en stock.');
          return;
        }
        final v = await gw.addItemVno(produitId: p.lgFAMILLEID, qte: 1, itemPu: p.intPRICE, prevente: false);
        expect(v.isOk, isTrue, reason: v.message);
        final net = await gw.netVno(v.valueOrNull!);
        final SaleSummary s = net.valueOrNull!;
        final cl = await gw.cloturerVno(venteId: v.valueOrNull!, summary: s, typeReglementId: '1', clientId: '', userVendeurId: user.userId);
        expect(cl.isOk, isTrue, reason: cl.message);
        // Les requêtes de vente mettent la mise à jour automatique en pause 2 s (ActiviteApp) : on attend.
        await Future<void>.delayed(const Duration(milliseconds: 2100));
        sw.reset();
        expect(await sync.syncChangements(), isTrue, reason: sync.error);
        final diff = sw.elapsed;
        final local = (await store.searchProducts(p.intCIP, 0, 5)).items.firstWhere((x) => x.lgFAMILLEID == p.lgFAMILLEID);
        expect(local.intNUMBERAVAILABLE, p.intNUMBERAVAILABLE - 1);
        expect(sync.delta.n, greaterThanOrEqualTo(1));
        // ignore: avoid_print
        print('H5 intégration : $n produits ; copie complète (catalogue entier) ${complet.inMilliseconds} ms, '
            'changements ${diff.inMilliseconds} ms (${sync.delta.n} produit(s)) ; '
            'vente de test ${v.valueOrNull} (${p.strNAME}) — à supprimer du serveur de test.');
      }, _RealHttp());
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
