// 4.3.0 — Réponse du serveur du 15/10/2026 (docs/serveur/REPONSE_SERVEUR_2026-10-15.md) : intégrations de Prestige
// Mobile, chacune avec REPLI sur un serveur qui n'a pas les nouvelles routes (404 / 405 / ancienne réponse) :
//   4  GET v1/reserve/droits {traiter} : décide du menu Réserve quand il répond ;
//   5  GET v1/posos/droits {analyser} : menu Analyse posologie masqué si analyser = false ;
//      403 {interdit:true, msg:"Droit manquant : …"} : message du serveur, jamais une déconnexion ;
//   10 role {code, libelle} de user/auth : libellé affiché (« Qui êtes-vous ? ») ;
//   11 licence : « Activez la licence après connexion d'un administrateur » (option A) ;
//   18 X-Client-Ref sur /commande/add-lot et /retourfournisseur/add-item envoyés hors ligne ;
//   28 suggestion ANNULEE ou d'un autre emplacement : consultation seule / « introuvable » ;
//   31 (pointage + photo) : test/pointage_photo_integration_test.dart.
// Données fictives uniquement.
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart' show masquerSerie;
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/connexion/connexion_commun.dart';
import 'package:prestige_vente_app/droits/droits_modules.dart';
import 'package:prestige_vente_app/horsligne/client_ref.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_sender.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/services/datamatrix_parser.dart';
import 'package:prestige_vente_app/reserve/reserve_api.dart';
import 'package:prestige_vente_app/reserve/reserve_models.dart';
import 'package:prestige_vente_app/reserve/reserve_traitement_screen.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/rh/rh_store.dart';
import 'package:prestige_vente_app/screens/auth/licence_registration_screen.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/serveur/erreur_vue.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';

/// Dernière série reçue par le faux serveur stock (test D18 hors ligne).
String? srv0Serie;

List<String> _ids() => orderedMenus(const []).map((m) => m.id).toList();

/// Serveur stock simulé (routes réception / retour) : enregistre chemin, en-têtes et corps de chaque appel.
class _Stock implements StockServer {
  final appels = <({String methode, String chemin, Map<String, String>? entetes, Object? corps})>[];
  StockHttp? Function(String methode, String chemin)? reponse;
  String? coupe; // chemin dont le prochain appel n'arrive pas (serveur injoignable)
  void Function(Object? corps)? surAppel;

  @override
  Future<StockHttp> call(String method, String path, {Map<String, dynamic>? query, Object? data, Map<String, String>? headers}) async {
    if (coupe == path) {
      coupe = null;
      throw const StockStopException('Serveur injoignable : envoi interrompu.');
    }
    appels.add((methode: method, chemin: path, entetes: headers, corps: data));
    surAppel?.call(data);
    final r = reponse?.call(method, path);
    if (r != null) return r;
    if (path.startsWith('/commande/bon/items/') && method == 'GET') {
      return const StockHttp(200, {
        'data': [
          {'lg_BON_LIVRAISON_DETAIL': 'd1', 'quantiteSaisie': 0, 'lots': '', 'str_STATUT': 'enable'},
          {'lg_BON_LIVRAISON_DETAIL': 'd2', 'quantiteSaisie': 0, 'lots': '', 'str_STATUT': 'enable'},
        ]
      });
    }
    if (path == '/retourfournisseur/retours-items') return const StockHttp(200, {'data': []});
    if (path.contains('capacites')) return const StockHttp(404, '');
    return const StockHttp(200, {'success': true});
  }

  List<String?> clesSur(String chemin) => [for (final a in appels) if (a.chemin == chemin) a.entetes?[enteteClientRef]];
}

StockOp _reception() => StockOp(
      id: 'HL3-20261015083000-ab12',
      type: StockOpType.reception,
      createdAt: DateTime(2026, 10, 15, 8, 30),
      refId: 'bl1',
      reference: 'BL-001',
      lines: [
        StockOpLine(key: 'd1|L1', label: 'PRODUIT A', data: {'detailId': 'd1', 'qty': 2, 'ug': 0, 'numLot': 'L1', 'expiry': '2027-01-31'}),
        StockOpLine(key: 'd2|L2', label: 'PRODUIT B', data: {'detailId': 'd2', 'qty': 1, 'ug': 0, 'numLot': 'L2', 'expiry': '2027-02-28'}),
      ],
    );

void main() {
  tearDown(() => DroitsModules.instance.oublier());

  // =======================================================================================================
  group('droits Réserve et Posos (demandes 4 et 5)', () {
    test('règles : droit dédié connu = décide (compte « admin » gardé) ; route absente = règle d\'avant', () {
      // Route absente (null) : inchangé.
      expect(menuReserveVisible(adminLocal: false, adminServeur: true), isTrue);
      expect(menuReserveVisible(adminLocal: true), isTrue);
      expect(menuReserveVisible(adminLocal: false), isFalse);
      // Route présente : le droit décide.
      expect(menuReserveVisible(adminLocal: false, adminServeur: true, droitDedie: false), isFalse,
          reason: 'chaque action serait refusée (403) : menu inutile');
      expect(menuReserveVisible(adminLocal: false, adminServeur: false, droitDedie: true), isTrue);
      expect(menuReserveVisible(adminLocal: true, droitDedie: false), isTrue);
      // Posos.
      expect(menuPososVisible(connu: true), isTrue);
      expect(menuPososVisible(connu: true, analyser: true), isTrue);
      expect(menuPososVisible(connu: true, analyser: false), isFalse);
      expect(menuPososVisible(connu: false, analyser: true), isFalse);
    });

    test('menus de l\'accueil : Analyse posologie masquée si le serveur refuse, présente sinon', () {
      DroitsModules.instance.fixer(pososAnalyser: false);
      expect(_ids(), isNot(contains('posos')));
      DroitsModules.instance.fixer(pososAnalyser: true);
      expect(_ids(), contains('posos'));
      DroitsModules.instance.fixer();
      expect(_ids(), contains('posos'), reason: 'serveur sans la route : comme avant');
    });

    group('serveur local', () {
      late ServeurJsonLocal srv;
      setUp(() => avecVraiHttp(() async {
            srv = ServeurJsonLocal();
            await srv.demarrer();
            srv.routes['GET /ordonnance-client/droits'] = (_) => const ReponseLocale({'success': true, 'consulter': false, 'modifier': false});
          }));
      tearDown(() => avecVraiHttp(() => srv.arreter()));

      test('serveur à jour : reserve/droits {traiter:false} masque la Réserve d\'un profil administrateur ; posos/droits {analyser:false} masque Posos',
          () => avecVraiHttp(() async {
                srv.routes['GET /roles/est-admin'] = (_) => const ReponseLocale({'authorize': true});
                srv.routes['GET /reserve/droits'] = (_) => const ReponseLocale({'success': true, 'traiter': false, 'annulerMouvement': false});
                srv.routes['GET /posos/droits'] = (_) => const ReponseLocale({'success': true, 'analyser': false});
                final d = DroitsModules();
                await d.actualiser(ClientPrestige(() => srv.base), utilisateur: 'u1', adminLocal: false);
                expect(d.reserve, isFalse);
                expect(d.posos, isFalse);
                srv.routes['GET /reserve/droits'] = (_) => const ReponseLocale({'success': true, 'traiter': true, 'annulerMouvement': false});
                srv.routes['GET /posos/droits'] = (_) => const ReponseLocale({'success': true, 'analyser': true});
                await d.actualiser(ClientPrestige(() => srv.base), utilisateur: 'u1', adminLocal: false, forcer: true);
                expect(d.reserve, isTrue);
                expect(d.posos, isTrue);
                // Une requête par route et par lecture (réseau : 4 lectures en parallèle).
                expect(srv.recuesSur('/posos/droits'), hasLength(2));
              }));

      test('ancien serveur (404 / 405 sur les nouvelles routes) : Réserve aux administrateurs, Posos ouvert', () => avecVraiHttp(() async {
            srv.routes['GET /roles/est-admin'] = (_) => const ReponseLocale({'authorize': true});
            srv.routes['GET /posos/droits'] = (_) => const ReponseLocale('Method Not Allowed', statut: 405);
            final d = DroitsModules();
            await d.actualiser(ClientPrestige(() => srv.base), utilisateur: 'u1', adminLocal: false);
            expect(d.reserve, isTrue);
            expect(d.posos, isTrue);
          }));

      test('403 « Droit manquant » (interdit:true) : message du serveur, ni session expirée ni déconnexion', () => avecVraiHttp(() async {
            srv.routes['PUT /S1/traiter'] =
                (_) => const ReponseLocale({'success': false, 'interdit': true, 'msg': 'Droit manquant : Traiter la réserve'}, statut: 403);
            Object? e;
            try {
              await ReserveApi(ClientPrestige(() => srv.base)).traiter('S1');
            } catch (x) {
              e = x;
            }
            expect(e, isA<ErreurHttp>());
            expect((e as ErreurHttp).droitManquant, isTrue);
            expect(e.message, 'Droit manquant : Traiter la réserve');
            expect(titreErreur(e), 'Droit manquant');
            // Autre 403 (page du filtre) : message générique d'avant.
            srv.routes['PUT /S1/traiter'] = (_) => const ReponseLocale('<html>Forbidden</html>', statut: 403);
            try {
              await ReserveApi(ClientPrestige(() => srv.base)).traiter('S1');
            } catch (x) {
              e = x;
            }
            expect((e as ErreurHttp).droitManquant, isFalse);
            expect(e.message, 'Accès refusé par le serveur (code 403).');
          }));
    });

    test('messageDroitManquant : corps texte ou objet ; autre 403 → null', () {
      expect(messageDroitManquant('{"success":false,"interdit":true,"msg":"Droit manquant : Posos"}'), 'Droit manquant : Posos');
      expect(messageDroitManquant({'interdit': true}), contains('Droit manquant'));
      expect(messageDroitManquant('Veuillez vous connecter'), isNull);
      expect(messageDroitManquant({'success': false, 'msg': 'x'}), isNull);
    });
  });

  // =======================================================================================================
  group('rôle de user/auth (demande 10)', () {
    test('role {code, libelle} : libellé affiché ; ancienne réponse (texte ou absent) inchangée', () {
      expect(User.fromJson({'str_LOGIN': 'a', 'role': {'code': 'PHARMACIEN', 'libelle': 'Pharmacien'}}).role, 'Pharmacien');
      expect(User.fromJson({'str_LOGIN': 'a', 'role': {'code': 'AUTRE', 'libelle': ''}}).role, '');
      expect(User.fromJson({'str_LOGIN': 'a', 'str_ROLE': 'Caissier'}).role, 'Caissier');
      expect(User.fromJson({'str_LOGIN': 'a'}).role, '');
      expect(roleDe(User.fromJson({'str_LOGIN': 'x', 'role': {'code': 'ADMINISTRATEUR', 'libelle': 'Administrateur'}}), 'x'), 'Administrateur');
    });
  });

  // =======================================================================================================
  group('hors ligne : X-Client-Ref sur add-lot et add-item (demande 18)', () {
    test('clé d\'événement par ligne : stable, distincte, 64 caractères au plus', () {
      final op = _reception();
      final k1 = cleEvenementLigne(op, op.lines[0]), k2 = cleEvenementLigne(op, op.lines[1]);
      expect(k1, 'HL3-20261015083000-ab12-L1');
      expect(k2, 'HL3-20261015083000-ab12-L2');
      expect(k1.length, lessThanOrEqualTo(64));
      // Relue après enregistrement sur le téléphone : même clé.
      final relue = StockOp.fromJson(op.toJson());
      expect(cleEvenementLigne(relue, relue.lines[0]), k1);
    });

    test('réception : chaque lot porte sa clé ; renvoi après coupure = même clé (serveur à jour : enregistré une seule fois)', () async {
      final srv = _Stock();
      final op = _reception();
      final sender = StockSender(srv, persist: (_) async {});
      srv.coupe = '/commande/add-lot'; // 1er lot : réponse jamais arrivée
      await expectLater(sender.apply(op), throwsA(isA<StockStopException>()));
      await sender.apply(op);
      final cles = srv.clesSur('/commande/add-lot');
      expect(cles, ['HL3-20261015083000-ab12-L1', 'HL3-20261015083000-ab12-L2']);
      expect(op.lines.map((l) => l.etat), everyElement(StockLineEtat.applied));
      // Corps inchangé : aucun champ inconnu d'un ancien serveur (pas de clientEventId).
      for (final a in srv.appels.where((a) => a.chemin == '/commande/add-lot')) {
        expect((a.corps as Map).containsKey('clientEventId'), isFalse);
      }
    });

    test('retour : add-item porte la clé de sa ligne ; création (new) inchangée', () async {
      final srv = _Stock()
        ..reponse = (m, c) => (c == '/retourfournisseur/new'
            ? const StockHttp(200, {'success': true, 'data': {'lgRETOURFRSID': 'R1', 'strREFRETOURFRS': '9001'}})
            : null);
      final op = StockOp(
        id: 'HL3-20261015090000-zz99',
        type: StockOpType.retour,
        createdAt: DateTime(2026, 10, 15, 9),
        refId: 'bl1',
        meta: {'marker': '[HL:HL3-20261015090000-zz99]', 'blRef': 'BL-001'},
        lines: [
          StockOpLine(key: 'p1', label: 'PRODUIT A', data: {'produitId': 'p1', 'motifId': '01', 'qty': 1}),
          StockOpLine(key: 'p2', label: 'PRODUIT B', data: {'produitId': 'p2', 'motifId': '01', 'qty': 2}),
        ],
      );
      await StockSender(srv, persist: (_) async {}).apply(op);
      expect(srv.clesSur('/retourfournisseur/add-item'), ['HL3-20261015090000-zz99-L2']);
      expect(op.lines.map((l) => l.etat), everyElement(StockLineEtat.applied));
    });

    test('403 « Droit manquant » : ligne refusée avec le message du serveur, pas « session expirée »', () async {
      final srv = _Stock()
        ..reponse = (m, c) => c == '/commande/add-lot'
            ? const StockHttp(403, {'success': false, 'interdit': true, 'msg': 'Droit manquant : Réception mobile'})
            : null;
      final op = _reception();
      await StockSender(srv, persist: (_) async {}).apply(op);
      expect(op.lines.map((l) => l.etat), everyElement(StockLineEtat.rejected));
      expect(op.lines.first.motif, 'Droit manquant : Réception mobile');
      // 403 du filtre de connexion (texte) : toujours « session expirée », rien de refusé.
      final srv2 = _Stock()..reponse = (m, c) => c == '/commande/add-lot' ? const StockHttp(403, 'Veuillez vous connecter') : null;
      final op2 = _reception();
      await expectLater(StockSender(srv2, persist: (_) async {}).apply(op2), throwsA(isA<StockStopException>()));
      expect(op2.lines.where((l) => l.etat == StockLineEtat.rejected), isEmpty);
    });
  });

  // =======================================================================================================
  group('D18 (4.3.1) : boîte déjà scannée refusée', () {
    const gs = '\u001d';
    const gtin = '03400935955838';
    test('DataMatrix GS1 : numéro de série (AI 21) lu avec le GTIN ; absent → null', () {
      final a = DataMatrixParser.parse('01${gtin}21SN0001${gs}17271031' '10A123')!;
      expect([a.gtin, a.serie, a.lot], [gtin, 'SN0001', 'A123']);
      final b = DataMatrixParser.parse('(01)$gtin(21)XY-77(17)271031(10)L9')!;
      expect(b.serie, 'XY-77');
      expect(DataMatrixParser.parse('01${gtin}17271031' '10A123')!.serie, isNull);
    });

    test('corps, refus et journal : série seulement si connue, message clair, jamais en clair dans le journal', () {
      expect(champsSerie('SN1', gtin), {'serie': 'SN1', 'gtin': gtin});
      expect(champsSerie('SN1', null), {'serie': 'SN1'});
      expect(champsSerie(null, gtin), isEmpty);
      expect(champsSerie(' ', gtin), isEmpty);
      expect(champsSerie('SN1', gtin, avecSerie: false), isEmpty);
      final r = resultatAjoutLot(const ReceptionResult(false, 'Boîte déjà scannée', {'success': false, 'code': 'SERIE_DEJA_CONSOMMEE'}));
      expect(r.message, startsWith('Boîte déjà scannée'));
      expect(r.message, contains('Aucune quantité ajoutée'));
      expect(resultatAjoutLot(const ReceptionResult(false, 'Autre refus')).message, 'Autre refus');
      expect(masquerSerie('{idBonDetail: d1, qty: 1, serie: SN0001, gtin: $gtin}'), isNot(contains('SN0001')));
      expect(masquerSerie('{"qty":1,"serie":"SN0001","gtin":"$gtin"}'), isNot(contains('SN0001')));
      expect(masquerSerie('{"qty":1,"serie":"SN0001"}'), contains('"serie":"***"'));
      expect(masquerSerie('GET /info'), 'GET /info');
    });

    group('en ligne (vrai HTTP local)', () {
      late ServeurJsonLocal srv;
      setUp(() => avecVraiHttp(() async {
            srv = ServeurJsonLocal();
            await srv.demarrer();
          }));
      tearDown(() => avecVraiHttp(() => srv.arreter()));
      DioReceptionGateway gw() => DioReceptionGateway(Dio(BaseOptions(baseUrl: srv.base)));

      test('serveur à jour : 1 requête avec serie et gtin ; boîte déjà scannée → refus clair', () => avecVraiHttp(() async {
            final vues = <String>{};
            srv.routes['POST /commande/add-lot'] = (r) {
              final j = r.json;
              if (j['serie'] != null && !vues.add('${j['gtin']}/${j['serie']}')) {
                return const ReponseLocale({'success': false, 'code': 'SERIE_DEJA_CONSOMMEE', 'msg': 'Boîte déjà scannée'});
              }
              return const ReponseLocale({'success': true});
            };
            final a = await gw().addLot(detailId: 'd1', quantity: 1, freeQty: 0, numLot: 'A1', serie: 'SN1', gtin: gtin);
            expect(a.success, isTrue);
            expect(srv.recues.single.json, containsPair('serie', 'SN1'));
            expect(srv.recues.single.json, containsPair('gtin', gtin));
            final b = await gw().addLot(detailId: 'd1', quantity: 1, freeQty: 0, numLot: 'A1', serie: 'SN1', gtin: gtin);
            expect(b.success, isFalse);
            expect(b.message, startsWith('Boîte déjà scannée'));
            expect(b.data['code'], 'SERIE_DEJA_CONSOMMEE');
            expect(srv.recues, hasLength(2), reason: 'aucun renvoi automatique');
          }));

      test('ancien serveur (dev) : champs inconnus ignorés → accepté ; serveur qui les refuserait (400) → renvoi sans série', () => avecVraiHttp(() async {
            srv.routes['POST /commande/add-lot'] = (_) => const ReponseLocale({'success': true});
            expect((await gw().addLot(detailId: 'd1', quantity: 1, freeQty: 0, numLot: 'A1', serie: 'SN1', gtin: gtin)).success, isTrue);
            srv.recues.clear();
            srv.routes['POST /commande/add-lot'] = (r) => r.json.containsKey('serie')
                ? const ReponseLocale('Unrecognized field "serie"', statut: 400)
                : const ReponseLocale({'success': true});
            final r = await gw().addLot(detailId: 'd1', quantity: 2, freeQty: 0, numLot: 'A1', serie: 'SN2', gtin: gtin);
            expect(r.success, isTrue);
            expect(srv.recues, hasLength(2));
            expect(srv.recues.last.json.containsKey('serie'), isFalse);
            expect(srv.recues.last.json['qty'], 2);
            // Sans série : jamais de 2e envoi.
            srv.recues.clear();
            srv.routes['POST /commande/add-lot'] = (_) => const ReponseLocale('Bad request', statut: 400);
            expect((await gw().addLot(detailId: 'd1', quantity: 1, freeQty: 0, numLot: 'A1')).success, isFalse);
            expect(srv.recues, hasLength(1));
          }));

      test('réseau : réponse trop lente (délai dépassé) → « lot non enregistré » (jamais « boîte déjà scannée »), aucun renvoi', () => avecVraiHttp(() async {
            srv.routes['POST /commande/add-lot'] = (_) => const ReponseLocale({'success': true}, delai: Duration(seconds: 4));
            final g = DioReceptionGateway(Dio(BaseOptions(baseUrl: srv.base, receiveTimeout: const Duration(seconds: 1))));
            final r = await g.addLot(detailId: 'd1', quantity: 1, freeQty: 0, numLot: 'A1', serie: 'SN1', gtin: gtin);
            expect(r.success, isFalse);
            expect(r.message, isNot(contains('déjà scannée')));
            expect(srv.recues, hasLength(1));
          }));
    });

    test('hors ligne : série gardée dans la file, envoyée à la synchro ; boîte déjà scannée → ligne refusée lisible, jamais renvoyée', () async {
      final srv = _Stock()
        ..reponse = (m, c) => c == '/commande/add-lot' && srv0Serie != null && srv0Serie!.contains('SN-DEJA')
            ? const StockHttp(200, {'success': false, 'code': 'SERIE_DEJA_CONSOMMEE', 'msg': 'Boîte déjà scannée'})
            : null;
      final op = StockOp(
        id: 'HL3-20261015100000-se18',
        type: StockOpType.reception,
        createdAt: DateTime(2026, 10, 15, 10),
        refId: 'bl1',
        lines: [
          StockOpLine(key: 'k1', label: 'PRODUIT A', data: {'detailId': 'd1', 'qty': 1, 'ug': 0, 'numLot': 'L1', 'expiry': '2027-01-31', 'serie': 'SN-DEJA', 'gtin': gtin}),
          StockOpLine(key: 'k2', label: 'PRODUIT B', data: {'detailId': 'd2', 'qty': 1, 'ug': 0, 'numLot': 'L2', 'expiry': '2027-01-31', 'serie': 'SN-NEUF', 'gtin': gtin}),
        ],
      );
      srv.surAppel = (corps) => srv0Serie = corps is Map ? '${corps['serie']}' : null;
      final sender = StockSender(srv, persist: (_) async {});
      await sender.apply(op);
      final lots = [for (final a in srv.appels) if (a.chemin == '/commande/add-lot') a.corps as Map];
      expect(lots.map((c) => c['serie']), ['SN-DEJA', 'SN-NEUF']);
      expect(lots.first['gtin'], gtin);
      expect(op.lines[0].etat, StockLineEtat.rejected);
      expect(op.lines[0].motif, startsWith('Boîte déjà scannée'));
      expect(op.lines[0].motif, isNot(contains('SN-DEJA')), reason: 'motif lisible, sans le numéro de série');
      expect(op.lines[1].etat, StockLineEtat.applied);
      // Synchro suivante : la ligne refusée n'est jamais renvoyée (pas de boucle).
      final avant = srv.appels.length;
      await sender.apply(op);
      expect(srv.appels.length, avant);
    });
  });

  // =======================================================================================================
  group('pointage : id du terminal et contrôle (demande 31, unitaires)', () {
    test('corps : id + champs habituels + contrôle ; ancien pointage relu sans contrôle', () {
      final p = PointageBadge(
          id: 'id-1', employeId: 'E1', lu: DateTime(2026, 10, 15, 8, 2), sens: SensPointage.entree, motif: 'Badge terminal Accueil', controle: const {'photo': true});
      expect(p.corps, {'id': 'id-1', 'employeId': 'E1', 'jour': '2026-10-15', 'heure': '08:02', 'sens': 'ENTREE', 'motif': 'Badge terminal Accueil', 'controle': {'photo': true}});
      final relu = PointageBadge.fromJson(p.toJson());
      expect(relu.corps, p.corps, reason: 'file hors ligne : même corps au renvoi');
      final ancien = PointageBadge.fromJson({'id': 'id-2', 'employeId': 'E1', 'lu': '2026-10-15T08:02:00', 'sens': 'SORTIE', 'motif': 'm'});
      expect(ancien.corps.containsKey('controle'), isFalse);
      expect(ancien.corps['id'], 'id-2');
    });

    test('codes « sans photo » attendus par le serveur', () {
      expect(controlePhoto(const PhotoAbsente(MotifSansPhoto.permissionRefusee)), {'photo': false, 'motif': 'PERMISSION_REFUSEE'});
      expect({for (final m in MotifSansPhoto.values) codeSansPhoto(m)},
          {'CAMERA_ABSENTE', 'PERMISSION_REFUSEE', 'ERREUR_CAMERA', 'DELAI_DEPASSE', 'PHOTO_ILLISIBLE'});
      expect(isoLocal(DateTime(2026, 1, 5, 7, 3, 9)), '2026-01-05T07:03:09');
    });
  });

  // =======================================================================================================
  group('réseau : envoi de la photo de pointage (demande 31)', () {
    PointageRh monter(_RhLent rh, RegistrePhotosPointage reg) => PointageRh(
          store: MemoryRhStore(),
          serveur: rh,
          photos: PhotoControle(registre: reg, reglages: () async => const ReglagesPointageTerminal()),
          horsLigne: () => false,
          nomTerminal: () => 'Accueil',
          journal: () => JournalTerminal(store: MemoryJournalStore()),
        );
    final badge = BadgeAConfirmer(const EmployeRh(id: 'E1', nom: 'KOUASSI', prenoms: 'Awa'), SensPointage.entree, DateTime(2026, 10, 15, 8, 2));
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 0xFF, 0xD9]);

    test('serveur lent (8 s) sur la photo : le pointage est confirmé tout de suite, la photo part ensuite', () async {
      final rh = _RhLent()..attentePhoto = Completer<void>();
      final reg = RegistrePhotosPointage(stockage: StockagePhotosMemoire(), journal: () => JournalTerminal(store: MemoryJournalStore()), retentionJours: () async => 30);
      final pr = monter(rh, reg);
      final sw = Stopwatch()..start();
      final r = await pr.enregistrerAvecPhoto(badge, SensPointage.entree, photo: Future.value(PhotoPrise(jpeg)));
      expect(r.issue, IssueBadge.enregistre);
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)), reason: 'l\'employé n\'attend pas la photo');
      expect(rh.photosRecues, 0);
      await Future<void>.delayed(Duration.zero);
      expect(rh.photosEnCours, 1, reason: 'envoi lancé en arrière-plan');
      rh.attentePhoto!.complete();
      expect(await pr.envoiPhotos, 1);
      expect(reg.photos.single.photoServeur, 'envoyee');
    });

    test('coupure pendant l\'envoi de la photo : gardée, réessayée au prochain envoi (une seule photo reçue)', () async {
      final rh = _RhLent()..couperPhoto = true;
      final reg = RegistrePhotosPointage(stockage: StockagePhotosMemoire(), journal: () => JournalTerminal(store: MemoryJournalStore()), retentionJours: () async => 30);
      final pr = monter(rh, reg);
      await pr.enregistrerAvecPhoto(badge, SensPointage.entree, photo: Future.value(PhotoPrise(jpeg)));
      expect(await pr.envoiPhotos, 0);
      expect(reg.photos.single.photoServeur, '', reason: 'pas perdue : réessayée');
      rh.couperPhoto = false;
      expect(await pr.envoyerPhotos(), 1);
      expect(await pr.envoyerPhotos(), 0);
      expect(rh.photosRecues, 1);
    });
  });

  // =======================================================================================================
  group('licence : activation après connexion d\'un administrateur (demande 11)', () {
    test('serveur qui exige une session : message de l\'option A, pas « clé invalide » ni panne réseau', () async {
      final api = ApiService(baseUrl: 'http://serveur.test/prestige/api/v1');
      api.dio.httpClientAdapter = _Adaptateur((o) => o.path.contains('/licence/save/') ? (401, 'Veuillez vous connecter') : (200, ''));
      final p = LicenceProvider(api);
      expect(await p.registerLicence('ABC-123'), isFalse);
      expect(p.errorMessage, LicenceProvider.messageActivationAdministrateur);
      expect(p.sessionRequise, isTrue);
      expect(p.issue, isNull, reason: 'pas un problème de connexion');
      // 403 « Veuillez vous connecter » (variante du filtre) : même message.
      api.dio.httpClientAdapter = _Adaptateur((o) => o.path.contains('/licence/save/') ? (403, 'Veuillez vous connecter') : (200, ''));
      expect(await p.registerLicence('ABC-123'), isFalse);
      expect(p.sessionRequise, isTrue);
      // Ancien serveur (route ouverte) : 200 puis licence valide, comme avant.
      api.dio.httpClientAdapter = _Adaptateur((o) => o.path.contains('/licence/save/')
          ? (200, '')
          : (200, '{"id":"LIC-DEMO","dateStart":"2026-01-01","dateEnd":"2099-12-31","typeLicence":"ANNUELLE"}'));
      expect(await p.registerLicence('ABC-123'), isTrue);
      expect(p.sessionRequise, isFalse);
    });

    testWidgets('e2e : licence expirée constatée à la connexion de l\'ADMINISTRATEUR → session gardée, activation, puis déconnexion', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      var licenceValide = true;
      app.serveur.routes['GET /licence/find'] = (_) =>
          ReponseLocale(licenceValide ? DonneesFictives.licence() : DonneesFictives.licence(dateEnd: '2020-01-01'));
      app.serveur.routes['GET /licence/save/CLE-DEMO-2027'] = (r) {
        // Comme le serveur à jour : la route exige une session.
        if (r.jsessionid == null || !app.serveur.sessions.contains(r.jsessionid)) return FauxServeurPrestige.nonConnecte401;
        licenceValide = true;
        return const ReponseLocale('');
      };
      await app.preparer();
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byKey(const Key('connexion_login'))), isTrue);
      licenceValide = false;
      await t.enterText(find.byKey(const Key('connexion_login')), DonneesFictives.admin);
      await t.enterText(find.byKey(const Key('connexion_mdp')), DonneesFictives.motDePasseAdmin);
      await t.ensureVisible(find.byKey(const Key('se_connecter')));
      await t.tap(find.byKey(const Key('se_connecter')));
      expect(await app.attendreQue(t, find.byType(LicenceRegistrationScreen)), isTrue);
      expect(app.serveur.recuesSur('/user/logout'), isEmpty, reason: 'administrateur : session gardée pour l\'activation');
      await app.attendre(t, const Duration(seconds: 1)); // fin de la transition vers « Clé de licence »
      await t.enterText(find.descendant(of: find.byType(LicenceRegistrationScreen), matching: find.byType(TextFormField)), 'CLE-DEMO-2027');
      await t.tap(find.text('ACTIVER LA LICENCE'));
      await app.attendre(t, const Duration(seconds: 2));
      expect(app.serveur.recuesSur('/licence/save/CLE-DEMO-2027'), hasLength(1));
      expect(find.byKey(const Key('licence_session_requise')), findsNothing);
      expect(app.serveur.recuesSur('/user/logout'), hasLength(1), reason: 'session fermée après l\'activation');
      expect(await app.attendreQue(t, find.byKey(const Key('connexion_login'))), isTrue);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('e2e : compte NON administrateur → déconnexion (comme avant) ; activation refusée expliquée, bouton « Connexion administrateur »', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      var licenceValide = true;
      app.serveur.routes['GET /licence/find'] = (_) =>
          ReponseLocale(licenceValide ? DonneesFictives.licence() : DonneesFictives.licence(dateEnd: '2020-01-01'));
      app.serveur.routes['GET /licence/save/CLE-DEMO-2027'] = (r) => app.serveur.sessions.contains(r.jsessionid) ? const ReponseLocale('') : FauxServeurPrestige.nonConnecte401;
      await app.preparer();
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byKey(const Key('connexion_login'))), isTrue);
      licenceValide = false;
      await t.enterText(find.byKey(const Key('connexion_login')), DonneesFictives.login);
      await t.enterText(find.byKey(const Key('connexion_mdp')), DonneesFictives.motDePasse);
      await t.ensureVisible(find.byKey(const Key('se_connecter')));
      await t.tap(find.byKey(const Key('se_connecter')));
      expect(await app.attendreQue(t, find.byType(LicenceRegistrationScreen)), isTrue);
      expect(app.serveur.recuesSur('/user/logout'), hasLength(1), reason: 'non administrateur : déconnexion comme avant');
      await app.attendre(t, const Duration(seconds: 1)); // fin de la transition vers « Clé de licence »
      await t.enterText(find.descendant(of: find.byType(LicenceRegistrationScreen), matching: find.byType(TextFormField)), 'CLE-DEMO-2027');
      await t.tap(find.text('ACTIVER LA LICENCE'));
      await app.attendre(t, const Duration(seconds: 2));
      expect(find.byKey(const Key('licence_session_requise')), findsOneWidget);
      expect(find.text(LicenceProvider.messageActivationAdministrateur), findsWidgets);
      await t.ensureVisible(find.byKey(const Key('licence_connexion_admin')));
      expect(t.getSize(find.byKey(const Key('licence_connexion_admin'))).height, greaterThanOrEqualTo(48));
      await t.tap(find.byKey(const Key('licence_connexion_admin')));
      expect(await app.attendreQue(t, find.byKey(const Key('connexion_login'))), isTrue);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });

  // =======================================================================================================
  group('réserve : emplacement et suggestion annulée (demande 28)', () {
    testWidgets('suggestion ANNULEE : consultation seule, aucun bouton Traiter, aucun verrou à libérer', (t) async {
      t.view.physicalSize = const Size(720, 1440);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final api = _Reserve(() async => SuggestionOuverte.fromJson({
            'entete': _entete(statut: 'ANNULEE'),
            'lignes': [_ligne('1')],
            'modifiable': false,
            'motif_lecture_seule': 'Cette suggestion est cloturee : elle est consultable uniquement.',
          }));
      await t.pumpWidget(MaterialApp(home: ReserveTraitementScreen(suggestionId: 'S1', api: api)));
      await t.pumpAndSettle();
      expect(find.textContaining('consultable uniquement'), findsOneWidget);
      expect(find.byKey(const ValueKey('reserve-traiter')), findsNothing);
      await t.pumpWidget(const SizedBox());
      expect(api.liberations, 0);
      expect(t.takeException(), isNull);
    });

    testWidgets('suggestion d\'un autre emplacement : « Suggestion introuvable. » affiché, avec « Réessayer »', (t) async {
      t.view.physicalSize = const Size(720, 1440);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final api = _Reserve(() async => throw const RefusMetier('Suggestion introuvable.'));
      await t.pumpWidget(MaterialApp(home: ReserveTraitementScreen(suggestionId: 'S9', api: api)));
      await t.pumpAndSettle();
      expect(find.textContaining('Suggestion introuvable.'), findsWidgets);
      expect(find.text('Réessayer'), findsWidgets);
      expect(t.takeException(), isNull);
    });
  });

  // =======================================================================================================
  group('e2e : menus selon les droits du serveur à jour', () {
    testWidgets('posos/droits {analyser:false} → Analyse posologie absente de l\'accueil ; serveur sans la route → présente', (t) async {
      for (final refuse in [true, false]) {
        TailleEcran.sunmiV2s.appliquer(t);
        final app = AppE2E();
        if (refuse) app.serveur.routes['GET /posos/droits'] = (_) => const ReponseLocale({'success': true, 'analyser': false});
        await app.preparer(prefs: {'hiddenMenuIds': <String>[]});
        await app.lancer(t);
        expect(await app.seConnecter(t), isTrue);
        await app.attendre(t, const Duration(seconds: 3));
        expect(await app.menuPresent(t, ListPresentation.dashboard, 'posos'), !refuse, reason: refuse ? 'refusé' : 'route absente');
        await app.fermer(t);
      }
    });
  });
}

Map<String, dynamic> _entete({String statut = 'A_TRAITER'}) => {
      'lg_SUGGESTION_RESERVE_ID': 'S1',
      'str_REF': 'SR-RAY-261015-090000',
      'str_CATEGORIE': 'RAYON',
      'str_ORIGINE': 'MANUELLE',
      'str_STATUT': statut,
      'motif_id': 1,
      'motif_libelle': 'Reappro rayon',
      'str_USER_CREATEUR': 'Préparateur Test',
      'dt_CREATED': '15/10/2026 09:00',
      'nb_produits': 1,
    };

Map<String, dynamic> _ligne(String id) => {
      'lg_SUGGESTION_RESERVE_DETAIL_ID': id,
      'lg_FAMILLE_ID': 'F$id',
      'int_CIP': '100$id',
      'str_NAME': 'PRODUIT TEST $id',
      'int_QTE_PROPOSEE': 3,
      'int_STOCK_RAYON': 1,
      'int_STOCK_RESERVE': 5,
      'int_STOCK_RAYON_ACTUEL': 1,
      'int_STOCK_RESERVE_ACTUEL': 5,
      'str_ETAT': 'ANNULEE',
    };

class _Reserve extends ReserveApi {
  final Future<SuggestionOuverte> Function() _ouvrir;
  int liberations = 0;
  _Reserve(this._ouvrir) : super(ClientPrestige(() => 'http://127.0.0.1:1/prestige/api/v1'));
  @override
  Future<SuggestionOuverte> ouvrir(String id) => _ouvrir();
  @override
  Future<void> liberer(String id) async => liberations++;
}

/// Adaptateur HTTP de test : (code, corps texte) selon la requête.
class _Adaptateur implements HttpClientAdapter {
  final (int, String) Function(RequestOptions o) reponse;
  _Adaptateur(this.reponse);
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    final (code, corps) = reponse(options);
    return ResponseBody.fromString(corps, code, headers: {
      Headers.contentTypeHeader: [corps.startsWith('{') ? 'application/json' : 'text/plain'],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Serveur RH (pointages + photo) réglable : photo lente ou coupée.
class _RhLent implements RhServeur, RhPhotos {
  Completer<void>? attentePhoto;
  bool couperPhoto = false;
  int photosRecues = 0, photosEnCours = 0;
  @override
  Future<ReponseRh> get(String chemin, [Map<String, dynamic> query = const {}]) async => (status: 404, body: null);
  @override
  Future<ReponseRh> post(String chemin, Map<String, dynamic> corps) async =>
      (status: 200, body: {'success': true, 'id': corps['id'], 'message': 'Pointage manuel enregistré.'});
  @override
  Future<ReponseRh> envoyerPhoto(String pointageId, Uint8List jpeg, DateTime prise) async {
    if (couperPhoto) throw const RhHorsLigne();
    photosEnCours++;
    await attentePhoto?.future;
    photosRecues++;
    return (status: 200, body: {'success': true});
  }
}
