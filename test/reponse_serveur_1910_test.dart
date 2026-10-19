// 4.6.0 — Réponse du serveur du 19/10/2026 (docs/serveur/REPONSE_SERVEUR_2026-10-19.md), sans écran ou écran isolé :
//  - 12 : refus PRODUITS_NON_SAISIS lu (liste, sinon message) ; P_BL_MOBILE_SCANNER : masqué seulement quand le
//    serveur le contrôle (403 interdit constaté ou capacité annoncée), jamais sur un serveur ancien ; 403 sur add-lot
//    / creerbl → message, pas de déconnexion ;
//  - 17 D7 : `data.message` de retourfournisseur/add-item affiché ;
//  - 51 : « Mon pointage » sous la session (v1/rh/moi) : aucune connexion v1/mobile, jeton effacé, X-Client-Ref,
//    repli v1/mobile sur 404 ;
//  - 52 : gestion RH = administrateur de l'application ET gerer:true ; employés aux champs réduits lus sans erreur.
// Données fictives uniquement.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/horsligne/routes_app_vente.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/retour/retour_gateway.dart';
import 'package:prestige_vente_app/rh/droits_rh.dart';
import 'package:prestige_vente_app/rh/mobile_api.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_bl_screen.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_summary_screen.dart';

import 'outils/serveur_json_local.dart';
import 'reception_bl_test.dart' show FakePrestige;

const _produits = [
  '3400935955838 DOLIPRANE 1000MG CP B/8 (3/10)',
  '3400930000007 AMOXICILLINE 500MG GEL B/12 (0/6)',
];

/// Faux module RH de session (« moi ») : réponses et requêtes notées.
class _Session implements TransportSession {
  final List<String> appels = [];
  final List<String?> cles = [];
  int statutMoi = 200;
  @override
  Future<ReponseHttp> envoyer(String methode, String chemin, {Map<String, dynamic>? corps, String? clientRef}) async {
    appels.add('$methode $chemin');
    if (statutMoi != 200) return (status: statutMoi, body: null);
    if (chemin == 'moi') {
      return (
        status: 200,
        body: <String, dynamic>{
          'success': true,
          'utilisateur': {'id': 'U-awa', 'login': 'awa', 'nom': 'TEST Awa'},
          'employe': {'id': 'E-awa', 'matricule': '07', 'nom': 'TEST Awa'},
          'droits': {'pointage': true, 'photos': false},
          'pointage': {'qr': false, 'gps': false},
        }
      );
    }
    if (chemin == 'moi/pointages' && methode == 'POST') {
      cles.add(clientRef);
      return (status: 200, body: <String, dynamic>{'success': true, 'sens': corps?['sens'] ?? 'ENTREE', 'heure': '08:02'});
    }
    return (status: 200, body: <String, dynamic>{'success': true, 'data': [{'heure': '08:02', 'sens': 'ENTREE', 'source': 'MOBILE'}]});
  }
}

/// Faux transport v1/mobile : chaque appel est noté (aucun ne doit partir sous la session).
class _Jeton implements TransportMobile {
  final List<String> appels = [];
  @override
  Future<ReponseHttp> envoyer(String methode, String chemin, {Map<String, dynamic>? corps, String? jeton}) async {
    appels.add('$methode $chemin');
    return (status: 404, body: null);
  }
}

void main() {
  setUp(() {
    DroitsVente.instance.oublier();
    DroitsVente.instance.oublierControles();
  });

  group('12 — Réception BL', () {
    test('PRODUITS_NON_SAISIS : liste du serveur, sinon lue dans le message ; autre refus : null', () {
      expect(produitsNonSaisis(const ReceptionResult(false, 'x', {'code': 'PRODUITS_NON_SAISIS', 'produits': _produits})), _produits);
      expect(
          produitsNonSaisis(ReceptionResult(false, 'Produits non saisis : ${_produits.join(', ')}', const {'code': 'PRODUITS_NON_SAISIS'})), _produits);
      expect(produitsNonSaisis(const ReceptionResult(false, 'Caisse fermée', {})), isNull);
      expect(produitsNonSaisis(const ReceptionResult(true, 'ok', {'code': 'PRODUITS_NON_SAISIS'})), isNull);
    });

    test('P_BL_MOBILE_SCANNER : serveur ancien (personne ne l\'a) → scan gardé ; contrôle constaté → masqué sans le droit', () {
      final d = DroitsVente.instance;
      expect(d.scannerBl, isTrue, reason: 'droits inconnus');
      d.fixer({'P_SM_BL', 'P_ENTREE_EN_STOCK'});
      expect(d.scannerBl, isTrue, reason: 'droit absent de la liste d\'un serveur ancien : comportement actuel');
      d.controleConstate(DroitsVente.scannerBlDroit);
      expect(d.scannerBl, isFalse);
      d.fixer({'P_SM_BL', DroitsVente.scannerBlDroit});
      expect(d.scannerBl, isTrue);
      d.oublier();
      d.fixer({'P_SM_BL'}, utilisateur: 'autre');
      expect(d.scannerBl, isFalse, reason: 'le contrôle appartient au serveur, pas au compte');
      d.oublierControles();
      expect(d.scannerBl, isTrue);
    });

    test('capacités du serveur : « droitScannerBl » annoncé → contrôle connu d\'emblée', () async {
      DroitsVente.instance.fixer({'P_SM_BL'});
      await RoutesAppVente.lireCapacites('http://srv-12', (_) async => (status: 200, body: {'success': true, 'droitScannerBl': true}));
      expect(DroitsVente.instance.scannerBl, isFalse);
    });

    test('403 interdit sur add-lot / creerbl : message du serveur, contrôle constaté (scan masqué ensuite)', () async {
      await avecVraiHttp(() async {
        final s = ServeurJsonLocal();
        await s.demarrer();
        addTearDown(s.arreter);
        const refus = ReponseLocale({'success': false, 'interdit': true, 'msg': 'Droit manquant : scanner les BL.'}, statut: 403);
        s.routes['POST /commande/add-lot'] = (_) => refus;
        s.routes['POST /commande/creerbl'] = (_) => refus;
        DroitsVente.instance.fixer({'P_SM_BL'});
        final gw = DioReceptionGateway(Dio(BaseOptions(baseUrl: s.base)));
        final r = await gw.addLot(detailId: 'd1', quantity: 2, freeQty: 0, numLot: 'L1', serie: 'S1', gtin: '03400930000007');
        expect(r.success, isFalse);
        expect(r.message, 'Droit manquant : scanner les BL.');
        expect(s.recuesSur('/commande/add-lot'), hasLength(1), reason: 'pas de nouvel essai sans série');
        expect(DroitsVente.instance.scannerBl, isFalse);
        final c = await gw.createBl(orderId: 'o1', ref: 'BL-1', date: DateTime(2026, 10, 19), amountHt: 1, tva: 0);
        expect(c.message, 'Droit manquant : scanner les BL.');
      });
    });

    testWidgets('écran de saisie : sans le droit (contrôlé), pas de champ de scan, message clair', (t) async {
      DroitsVente.instance.fixer({'P_SM_BL'});
      DroitsVente.instance.controleConstate(DroitsVente.scannerBlDroit);
      final server = FakePrestige()..add('d1', 'DOLIPRANE 1000MG CP', '3595583', '3400935955838', 24);
      t.view.physicalSize = const Size(720, 1440);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
          home: ReceptionBlScreen(
              bl: const ReceptionBl(id: 'bl1', ref: 'BL-778', grossiste: 'LABOREX', peremptionOptional: true), gateway: server, settings: const ReceptionSettings())));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('reception_scan_reserve')), findsOneWidget);
      expect(find.text(DroitsVente.messageScannerBl), findsOneWidget);
      expect(find.text('Scannez un produit du BL'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('entrée en stock refusée : liste des produits lisible et défilable sur un petit écran (Sunmi V2s)', (t) async {
      final liste = [for (var i = 1; i <= 30; i++) '340093${i.toString().padLeft(7, '0')} PRODUIT FICTIF $i AU NOM ASSEZ LONG POUR PASSER À LA LIGNE (0/$i)'];
      final server = _Refus(liste)..add('d1', 'DOLIPRANE 1000MG CP', '3595583', '3400935955838', 24);
      t.view.physicalSize = const Size(720, 1440);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
          home: ReceptionSummaryScreen(
        bl: const ReceptionBl(id: 'bl1', ref: 'BL-778', grossiste: 'LABOREX', peremptionOptional: true),
        gateway: server,
        settings: const ReceptionSettings(terminalValidation: true),
        lines: await server.lines('bl1'),
      )));
      await t.pumpAndSettle();
      await t.tap(find.text('Valider l\'entrée en stock'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ElevatedButton, 'Valider'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bl_produits_non_saisis')), findsOneWidget);
      expect(find.text('30 produits non saisis : saisissez leurs lots puis validez à nouveau.'), findsOneWidget);
      expect(find.text(liste.first), findsOneWidget);
      await t.scrollUntilVisible(find.text(liste.last), 200, scrollable: find.descendant(of: find.byKey(const Key('bl_produits_non_saisis_liste')), matching: find.byType(Scrollable)));
      expect(find.text(liste.last), findsOneWidget);
      expect(t.takeException(), isNull, reason: 'aucun débordement');
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.text('Entrée en stock effectuée'), findsNothing);
    });
  });

  group('17 D7 — Retour fournisseur', () {
    test('data.message affiché quand présent ; sinon « Produit ajouté »', () async {
      await avecVraiHttp(() async {
        final s = ServeurJsonLocal();
        await s.demarrer();
        addTearDown(s.arreter);
        var motifDifferent = true;
        s.routes['POST /retourfournisseur/add-item'] = (_) => ReponseLocale({
              'success': true,
              'data': motifDifferent ? {'message': 'Vous avez ajouté ce produit avec un motif différent'} : {}
            });
        final gw = DioRetourGateway(Dio(BaseOptions(baseUrl: s.base)));
        var r = await gw.addItem(retourId: 'R1', produitId: 'P1', motifId: 'M2', quantity: 1);
        expect(r.message, 'Vous avez ajouté ce produit avec un motif différent');
        motifDifferent = false;
        r = await gw.addItem(retourId: 'R1', produitId: 'P1', motifId: 'M2', quantity: 1);
        expect(r.message, messageProduitAjoute);
        expect(avisAjoutRetour({'success': true, 'data': 'x'}), isNull);
      });
    });
  });

  group('51 — Mon pointage sous la session', () {
    test('routes v1/rh/moi présentes : aucune connexion v1/mobile, jeton effacé, pointage avec X-Client-Ref unique', () async {
      final session = _Session(), jeton = _Jeton();
      final coffre = CoffreJetonMemoire(jsonEncode({'jeton': 'ANCIEN', 'utilisateur': {'login': 'awa'}}));
      final m = MobileApi(transport: jeton, transportSession: session, coffre: coffre, appareil: () => 't', nomAppareil: () => 't');
      expect(await m.lier('awa'), isFalse);
      expect(m.voieSession, isTrue);
      expect(coffre.valeur, isNull, reason: 'plus de jeton v1/mobile');
      final s = await m.reprendre();
      expect(s?.employeNom, 'TEST Awa');
      expect(s?.peutPointer, isTrue);
      await m.moi();
      expect((await m.pointer(sens: SensPointage.entree)).ok, isTrue);
      expect((await m.pointer(sens: SensPointage.sortie)).ok, isTrue);
      expect(await m.mesPointages(), hasLength(1));
      expect(session.cles, hasLength(2));
      expect(session.cles.toSet(), hasLength(2), reason: 'une clé par pointage');
      expect(session.cles.every((c) => c != null && c.startsWith('PT-')), isTrue);
      expect(jeton.appels, isEmpty, reason: 'aucun appel v1/mobile');
      expect(await m.sonder(), (existe: true, actif: true));
    });

    test('serveur ancien (404) : voie v1/mobile comme avant ; session de l\'application absente (401) : idem, sans conclure', () async {
      final session = _Session()..statutMoi = 404, jeton = _Jeton();
      final m = MobileApi(transport: jeton, transportSession: session, coffre: CoffreJetonMemoire(), appareil: () => 't', nomAppareil: () => 't');
      await m.lier('awa');
      expect(m.voieSession, isFalse);
      expect(await m.reprendre(), isNull, reason: 'connexion v1/mobile demandée, comme avant');
      await m.sonder();
      expect(jeton.appels, ['POST connexion'], reason: 'sonde v1/mobile d\'origine');
      expect(session.appels, ['GET moi'], reason: '404 retenu : pas de nouvelle sonde');
      final s401 = _Session()..statutMoi = 401;
      final m2 = MobileApi(transport: _Jeton(), transportSession: s401, coffre: CoffreJetonMemoire(), appareil: () => 't', nomAppareil: () => 't');
      await m2.lier('awa');
      await m2.sonderSession();
      expect(s401.appels, ['GET moi', 'GET moi'], reason: '401 : réessayé à la prochaine ouverture');
    });
  });

  group('52 — Terminal avec P_RH_POINTER', () {
    test('gestion : administrateur de l\'application ET gerer:true ; serveur sans « gerer » : comme la 4.4.0', () {
      expect(estGestionnaireRh(adminLocal: true, gerer: false), isFalse);
      expect(estGestionnaireRh(adminLocal: true, gerer: true), isTrue);
      expect(estGestionnaireRh(adminLocal: true), isTrue, reason: 'serveur ancien');
      expect(estGestionnaireRh(adminLocal: false, adminServeur: false, gerer: true), isFalse, reason: 'P_SM_RH seul ne suffit pas');
    });

    test('employés aux champs réduits (sans P_SM_RH) : lus sans erreur', () {
      final e = EmployeRh.fromJson({'id': 'E1', 'matricule': '01', 'nom': 'KOUASSI', 'prenoms': 'Awa Marie', 'badge': 'B001', 'statut': 'ACTIF'});
      expect(e.poste, '');
      expect(e.actif, isTrue);
      expect(e.nomComplet, 'KOUASSI Awa Marie');
      expect(e.prenomAffiche, 'Awa');
      expect(EmployeRh.fromJson(e.toJson()).badge, 'B001');
    });
  });
}

/// Réception : entrée en stock refusée, produits non saisis nommés.
class _Refus extends FakePrestige {
  final List<String> produits;
  _Refus(this.produits);
  @override
  Future<ReceptionResult> validate(String blId) async {
    validateCalls++;
    return ReceptionResult(false, 'Produits non saisis : ${produits.join(', ')}', {'success': false, 'code': 'PRODUITS_NON_SAISIS', 'produits': produits});
  }
}
