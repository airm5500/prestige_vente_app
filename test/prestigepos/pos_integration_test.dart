// PrestigePOS — intégration contre le faux serveur Prestige en VRAI HTTP local (127.0.0.1) : parcours complet de
// la borne avec le code partagé (BorneService, DioVenteGateway, ApiService, session JSESSIONID de l'utilisateur
// borne) puis impression ESC/POS sur une imprimante réseau simulée (vrai socket TCP) :
//   connexion de l'utilisateur borne → recherche (pages) → vérification prix / stock (écart détecté) →
//   prévente créée sur le serveur → ticket 58 mm imprimé, octets reçus identiques au ticket attendu.
// Aussi : « Tester la borne » (TesteurBorne) contre le même serveur, utilisateur refusé.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/session_expiree.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_diagnostic.dart';
import 'package:prestige_vente_app/borne/borne_panier.dart';
import 'package:prestige_vente_app/borne/borne_produit.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_pos.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_reglages.dart';
import 'package:prestige_vente_app/prestigepos/impression/ticket_escpos.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../outils/faux_serveur_prestige.dart';
import 'outils/pos_e2e.dart' show catalogueDefaut, loginBorne, mdpBorne;

void main() {
  late FauxServeurPrestige srv;
  late ApiService api;
  late List<Map<String, dynamic>> catalogue;

  setUp(() => avecVraiHttp(() async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        SessionExpiree.instance = SessionExpiree();
        await DioClient.cookieJar.deleteAll();
        catalogue = [for (final p in catalogueDefaut) Map<String, dynamic>.from(p)];
        srv = FauxServeurPrestige(comptes: {loginBorne: mdpBorne});
        srv.routes['GET /vente/search'] = (r) {
          final q = (r.query['query'] ?? '').toUpperCase();
          final mots = q.split('%').where((m) => m.isNotEmpty).toList();
          final start = int.tryParse(r.query['start'] ?? '') ?? 0;
          final limit = int.tryParse(r.query['limit'] ?? '') ?? 20;
          final l = [for (final p in catalogue) if (p['intCIP'] == q || mots.every((m) => (p['strNAME'] as String).contains(m))) p];
          return FauxServeurPrestige.ok({'data': l.skip(start).take(limit).toList(), 'total': l.length});
        };
        await srv.demarrer();
        api = ApiService(baseUrl: srv.base);
      }));
  tearDown(() => avecVraiHttp(() async {
        await srv.arreter();
        await DioClient.cookieJar.deleteAll();
      }));

  test('parcours borne complet → prévente sur le serveur → ticket ESC/POS sur imprimante réseau', () => avecVraiHttp(() async {
        // Imprimante réseau simulée (port local).
        final recus = BytesBuilder();
        final fin = Completer<void>();
        final imprimanteTcp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(imprimanteTcp.close);
        imprimanteTcp.listen((c) => c.listen(recus.add, onDone: () {
              c.destroy();
              if (!fin.isCompleted) fin.complete();
            }));

        // 1. Connexion de l'utilisateur borne (session JSESSIONID).
        expect(await api.login(loginBorne, mdpBorne), isNotNull);
        expect(srv.connexions, 1);
        final service = BorneService(DioVenteGateway(api), nouvelleCle: () => 'BORNE-TEST');

        // 2. Recherche paginée.
        final pager = service.pager('DOLI');
        expect(await pager.loadMore(), isTrue);
        expect(pager.items.map((p) => p.lgFAMILLEID), containsAll(['F1', 'F2']));

        // 3. Panier local, puis vérification : le prix du Doliprane a changé sur le serveur entre-temps.
        final panier = BornePanier();
        final doli = BorneProduit(pager.items.firstWhere((p) => p.lgFAMILLEID == 'F1'));
        final rhume = BorneProduit(pager.items.firstWhere((p) => p.lgFAMILLEID == 'F2'));
        expect(panier.ajouter(doli, 2), isNull);
        expect(panier.ajouter(rhume, 1), isNull);
        catalogue[0]['intPRICE'] = 1600;
        final v = await service.verifier(panier.lignes);
        expect(v, isA<VenteOk<BorneVerification>>());
        final verif = (v as VenteOk<BorneVerification>).value;
        expect(verif.ecarts.single.texte, contains('1 500 F → 1 600 F'.replaceAll(' ', ' ').replaceAll(' F', ' F').replaceAll(' → ', ' → ')));
        expect(verif.total, 2 * 1600 + 2850);

        // 4. Prévente créée sur le serveur (1er article, articles suivants, net, terminer la prévente).
        final r = await service.creerPrevente(verif.lignes);
        expect(r, isA<VenteOk<BornePrevente>>());
        final p = (r as VenteOk<BornePrevente>).value;
        expect(srv.ventes[p.venteId]!.map((l) => (l['lgFAMILLEID'], l['intQUANTITY'], l['intPRICEUNITAIR'])), [('F1', 2, 1600), ('F2', 1, 2850)]);
        expect(srv.statutVentes[p.venteId], 'is_Process', reason: 'prévente à encaisser');
        expect(p.reference, 'REF-${p.venteId}');
        expect(p.total, 6050);
        expect(srv.recues.where((q) => q.chemin.endsWith('/vente/terminerprevente/${p.venteId}')).length, 1);

        // 5. Ticket ESC/POS 58 mm envoyé à l'imprimante réseau.
        final c = ImprimanteConfig(type: TypeImprimante.reseau, hote: '127.0.0.1', port: imprimanteTcp.port);
        final ticket = BorneTicket(officine: 'PHARMACIE DE DEMONSTRATION', prevente: p, largeur: c.papier);
        final imp = ImprimantePos(config: () => c, sunmi: () async => false);
        expect(await imp.imprimer(ticket), isTrue);
        await fin.future.timeout(const Duration(seconds: 5));
        expect(recus.takeBytes(), TicketEscPos.ticket(ticket, c));
      }));

  test('session de l\'utilisateur borne expirée : refus 401 « Veuillez vous connecter », sans créer de vente', () => avecVraiHttp(() async {
        expect(await api.login(loginBorne, mdpBorne), isNotNull);
        final service = BorneService(DioVenteGateway(api));
        srv.expirerSessions();
        final r = await service.creerPrevente([
          BorneLigne(
              BorneProduit(ProductSearchResult(lgFAMILLEID: 'F1', strNAME: 'DOLIPRANE', intCIP: '3595583', intPRICE: 1500, intNUMBERAVAILABLE: 4, strLIBELLEE: '', intPAF: 0)),
              1),
        ]);
        expect(r.isOk, isFalse);
        expect(srv.ventes, isEmpty);
        expect(srv.refusSession, greaterThan(0));
      }));

  test('« Tester la borne » contre le serveur : prête ; mot de passe refusé : cause précise', () => avecVraiHttp(() async {
        final ok = await TesteurBorne(baseUrl: srv.base, secrets: MemoireBorneSecrets(mdpBorne)).tester(const BorneConfig(actif: true, login: loginBorne));
        expect(ok.ok, isTrue, reason: ok.etapes.join('\n'));
        final ko = await TesteurBorne(baseUrl: srv.base, secrets: MemoireBorneSecrets('faux')).tester(const BorneConfig(actif: true, login: loginBorne));
        expect(ko.ok, isFalse);
        expect(ko.conclusion, contains('Connexion refusée'));
        expect(srv.sessions, isEmpty, reason: 'session d\'essai fermée');
      }));
}
