// B1 — Borne de vente libre-service : désactivée par défaut, activation (code admin), parcours complet
// avec faux serveur, plafonds, indisponible non ajoutable, écart de prix, ticket (produits + numéro),
// ticket discret, inactivité / retour accueil (panier vidé), hors ligne, sortie du kiosque (code admin),
// 360 px / tablette portrait / paysage, 3 présentations ; intégration réelle (sautée sans serveur).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/licence_lookup.dart';
import 'package:prestige_vente_app/api/models/licence_model.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_kiosque.dart';
import 'package:prestige_vente_app/borne/borne_launcher.dart';
import 'package:prestige_vente_app/borne/borne_panier.dart';
import 'package:prestige_vente_app/borne/borne_produit.dart';
import 'package:prestige_vente_app/borne/borne_screen.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/borne/borne_widgets.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/horsligne/client_ref.dart';
import 'package:prestige_vente_app/horsligne/horsligne_ui.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/parametres/parametres_logic.dart';
import 'package:prestige_vente_app/parametres/parametres_screen.dart';
import 'package:prestige_vente_app/parametres/parametres_services.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductSearchResult _p(String id, String nom, String cip, int prix, int stock) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: nom, intCIP: cip, intPRICE: prix, intNUMBERAVAILABLE: stock, strLIBELLEE: '', intPAF: 0);

/// Faux serveur Prestige (routes de la Pré-vente) avec clé client H4.
class _Gw implements VenteGateway, ClientRefGateway {
  final Map<String, ProductSearchResult> produits = {
    'P1': _p('P1', 'DOLIPRANE 1000MG CP B/8', '3595583', 1500, 40),
    'P2': _p('P2', 'DOLIPRANE 2,4% SUSP BUV FL/100ML', '3400001', 2100, 5),
    'P3': _p('P3', 'DOLIMEX 1G CPR EFFV B/8', '8452285', 1100, 0),
    'P4': _p('P4', 'GEL INTIME 200ML', '5000001', 4800, 12),
  };
  bool panne = false;
  int recherches = 0;
  final ajouts = <({String produit, int qte, int pu, String? vente})>[];
  final cles = <String>[];
  String? _cle;
  int terminees = 0;
  int retraits = 0;
  String reference = '20261011000042';

  @override
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async {
    recherches++;
    if (panne) return const VenteFailed('Serveur injoignable (rechercher le produit).');
    final q = query.toUpperCase().replaceAll('%', ' ').trim();
    final mots = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final all = produits.values.where((p) => p.intCIP == q || mots.every(p.strNAME.toUpperCase().contains)).toList();
    final page = all.skip(start).take(limit).toList();
    return VenteOk(ProductPage(page, all.length));
  }

  @override
  Future<VenteResult<String>> addItemVno({required String produitId, required int qte, required int itemPu, String? venteId, required bool prevente}) async {
    if (venteId == null && _cle != null) cles.add(_cle!);
    _cle = null;
    ajouts.add((produit: produitId, qte: qte, pu: itemPu, vente: venteId));
    return const VenteOk('V1');
  }

  List<SaleItemDetail> get _lignes => [
        for (final (i, a) in ajouts.indexed)
          SaleItemDetail(
            lgPREENREGISTREMENTDETAILID: 'D$i',
            lgFAMILLEID: a.produit,
            strNAME: produits[a.produit]!.strNAME,
            intCIP: produits[a.produit]!.intCIP,
            intQUANTITY: a.qte,
            intPRICEUNITAIR: a.pu,
            intPRICE: a.qte * a.pu,
            strREF: reference,
          )
      ];

  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) async {
    final t = _lignes.fold<int>(0, (s, l) => s + l.intPRICE);
    return VenteOk(SaleSummary(montant: t, montantNet: t, reference: reference, venteId: venteId));
  }

  @override
  Future<VenteResult<void>> terminerPrevente(String venteId) async {
    terminees++;
    return const VenteOk(null);
  }

  @override
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async => VenteOk(_lignes);

  @override
  Future<VenteResult<void>> removeItem(String itemId) async {
    retraits++;
    return const VenteOk(null);
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId) async => VenteOk({'strREF': reference});

  @override
  Future<bool> clientRefSupporte() async => true;

  @override
  Future<VenteResult<ClientRefInfo?>> lireClientRef(String ref) async => const VenteOk(null);

  @override
  VenteGateway avecClientRef(String ref) {
    _cle = ref;
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _Imprimante implements BorneImprimante {
  bool ok = true;
  final tickets = <BorneTicket>[];
  @override
  Future<bool> imprimer(BorneTicket t) async {
    tickets.add(t);
    return ok;
  }
}

class _Env {
  final gw = _Gw();
  final monitor = ServerMonitor();
  final imprimante = _Imprimante();
  final kiosque = KiosqueSimule();
  int adminChecks = 0;
  bool adminAnswer = true;
  int sorties = 0;
  late final BorneService service = BorneService(gw);
  final GlobalKey<BorneScreenState> cle = GlobalKey();

  Widget app(BorneConfig c) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: BorneScreen(
          key: cle,
          service: service,
          config: c,
          monitor: monitor,
          imprimante: imprimante,
          kiosque: kiosque,
          officine: 'PHARMACIE LES PALMIERS',
          adminCheck: (_) async {
            adminChecks++;
            return adminAnswer;
          },
          onSortie: (_) => sorties++,
        ),
      );
}

void _taille(WidgetTester tester, Size s) {
  tester.view.physicalSize = s * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Future<_Env> _borne(WidgetTester tester, {BorneConfig config = const BorneConfig(actif: true, login: 'borne'), Size taille = const Size(360, 740)}) async {
  _taille(tester, taille);
  final env = _Env();
  await tester.pumpWidget(env.app(config));
  await tester.pump();
  return env;
}

Future<void> _chercher(WidgetTester tester, String t) async {
  await tester.enterText(find.byKey(const ValueKey('borne-recherche')), t);
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump();
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
  await tester.pump();
}

/// Fait défiler jusqu'à l'élément (centré).
Future<void> _voir(WidgetTester tester, Finder f) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await tester.pumpAndSettle();
}

/// Fin du test : écran retiré (minuteries annulées).
Future<void> _fin(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

JournalTerminal _journal() {
  final prev = JournalTerminal.instance;
  final j = JournalTerminal(clock: DateTime.now)..utilisateur = 'borne';
  JournalTerminal.instance = j;
  addTearDown(() => JournalTerminal.instance = prev);
  return j;
}

// ---------------------------------------------------------------------------
// Réglages (activation)
// ---------------------------------------------------------------------------

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');
  @override
  Future<User?> login(String login, String password) async =>
      User(userId: 'u1', login: login, firstName: 'Awa', lastName: 'Kouassi', officineName: 'PHCIE TEST');
  @override
  Future<LicenceLookup> lookupLicence() async => LicenceLookup.found(LicenceModel(
        id: 'LIC-42',
        dateStart: '2026-01-01',
        dateEnd: DateTime.now().add(const Duration(days: 21)).toIso8601String().substring(0, 10),
        typeLicence: 'ANNUELLE',
      ));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BorneReglages.courant.value = const BorneConfig();
    BorneReglages.secrets = MemoireBorneSecrets();
    BorneKiosque.instance = KiosqueSimule();
    HorsLigneScope.masquer.value = false;
  });

  group('Réglages', () {
    test('désactivée par défaut : appli inchangée, rien à ouvrir au démarrage', () async {
      final c = await BorneReglages.charger();
      expect(c.actif, isFalse);
      expect(c.presentation, BornePresentation.vitrine);
      expect(c.inactivite, 60);
      expect(c.maxParProduit, 10);
      expect(c.maxArticles, 15);
      expect(c.ticketDiscret, isFalse, reason: 'le client veut les produits sur le ticket');
      expect(BorneLauncher.auDemarrage, isFalse);
      expect(Rubrique.borne.locked, isTrue);
      expect(rubriqueMatches(Rubrique.borne, '', 'kiosque'), isTrue);
      expect(HorsLigneScope.masquer.value, isFalse);
    });

    test('valeurs bornées et lecture tolérante', () {
      final c = BorneConfig.fromJson({'actif': true, 'inactivite': 5, 'maxParProduit': 99, 'maxArticles': 0, 'presentation': 'xx', 'vedettes': ['35%95', '1']});
      expect(c.inactivite, BorneConfig.inactiviteMin);
      expect(c.maxParProduit, 10);
      expect(c.maxArticles, 1);
      expect(c.presentation, BornePresentation.vitrine);
      expect(c.vedettes, ['3595']);
      expect(BorneCategorie.parse('Douleur = doli'), const BorneCategorie('Douleur', 'DOLI'));
      expect(BorneCategorie.parse('X = do'), isNull, reason: 'mot-clé de moins de 3 lettres');
    });

    testWidgets('activation par Réglages › Borne (code admin), mot de passe hors SharedPreferences', (tester) async {
      _taille(tester, const Size(360, 760));
      final api = _FakeApi();
      final settings = SettingsProvider();
      await settings.loadSettings();
      var checks = 0;
      var answer = false;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider<LicenceProvider>.value(value: LicenceProvider(api)),
          ChangeNotifierProvider<AuthProvider>.value(value: AuthProvider(api)),
        ],
        child: MaterialApp(
          home: ParametresScreen(
            services: ParametresServices(
              adminCheck: (_) async {
                checks++;
                return answer;
              },
              pointageRepository: MemoryPointageRepository(),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final rub = find.byKey(const Key('rubrique_borne'));
      await tester.scrollUntilVisible(rub, 120, scrollable: find.byType(Scrollable).first);
      expect(find.text('Désactivée · libre-service client'), findsOneWidget);
      // Code refusé : la rubrique ne s'ouvre pas.
      await tester.tap(rub);
      await tester.pumpAndSettle();
      expect(checks, 1);
      expect(find.byKey(const ValueKey('borne-actif')), findsNothing);
      answer = true;
      await tester.tap(rub);
      await tester.pumpAndSettle();
      expect(checks, 2);
      await tester.tap(find.byKey(const ValueKey('borne-actif')));
      await tester.pump();
      await _voir(tester, find.byKey(const ValueKey('borne-presentation-guidee')));
      await tester.tap(find.byKey(const ValueKey('borne-presentation-guidee')));
      await tester.pump();
      // Sans utilisateur : refus.
      final save = find.byKey(const ValueKey('borne-enregistrer'));
      await _voir(tester, save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('borne-reglages-erreur')), findsOneWidget);
      expect(BorneReglages.courant.value.actif, isFalse);
      await _voir(tester, find.byKey(const ValueKey('borne-login')));
      await tester.enterText(find.byKey(const ValueKey('borne-login')), 'borne');
      await tester.enterText(find.byKey(const ValueKey('borne-mdp')), 'S3cret!');
      await _voir(tester, save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final c = BorneReglages.courant.value;
      expect(c.actif, isTrue);
      expect(c.login, 'borne');
      expect(c.presentation, BornePresentation.guidee);
      expect(await BorneReglages.secrets.lire(), 'S3cret!');
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        expect('${prefs.get(k)}'.contains('S3cret'), isFalse, reason: 'mot de passe en clair dans $k');
      }
      expect(BorneLauncher.auDemarrage, isTrue);
      expect((await BorneReglages.charger()).actif, isTrue, reason: 'réglage gardé sur l\'appareil');
      _sansErreur(tester);
    });
  });

  group('Logique', () {
    test('forme déduite du nom (pictogramme en attendant les images)', () {
      expect(formeDuNom('DOLIPRANE 1000MG CP B/8'), FormeProduit.comprime);
      expect(formeDuNom('DOLIPRANE 2,4% SUSP BUV FL/100ML'), FormeProduit.sirop);
      expect(formeDuNom('BIAFINE CREME TUBE 93G'), FormeProduit.creme);
      expect(formeDuNom('DOLIMEX 125MG SUPPO B/10'), FormeProduit.suppositoire);
      expect(formeDuNom('TOBREX COLLYRE 5ML'), FormeProduit.collyre);
      expect(formeDuNom('CEFTRIAXONE 1G INJ'), FormeProduit.injectable);
      expect(formeDuNom('SMECTA SACHETS B/30'), FormeProduit.sachet);
      expect(formeDuNom('VENTOLINE SPRAY 100UG'), FormeProduit.spray);
      expect(formeDuNom('AMOXICILLINE 500MG GELULES'), FormeProduit.gelule);
      expect(formeDuNom('XYZ'), FormeProduit.autre);
    });

    test('produits avec image mis en avant, puis disponibles (ordre du serveur sinon)', () {
      final a = BorneProduit(_p('A', 'A', '1', 100, 0));
      final b = BorneProduit(_p('B', 'B', '2', 100, 3));
      final c = BorneProduit(_p('C', 'C', '3', 100, 3), image: 'img://c');
      final d = BorneProduit(_p('D', 'D', '4', 100, 3));
      expect(trierPourBorne([a, b, c, d]).map((p) => p.id), ['C', 'B', 'D', 'A']);
    });

    test('panier : plafonds par produit et total, indisponible refusé, stock', () {
      final pan = BornePanier(maxParProduit: 3, maxArticles: 4);
      final p1 = BorneProduit(_p('P1', 'X', '1', 1000, 40));
      final p2 = BorneProduit(_p('P2', 'Y', '2', 500, 2));
      final p3 = BorneProduit(_p('P3', 'Z', '3', 500, 0));
      expect(pan.ajouter(p3, 1), contains('indisponible'));
      expect(pan.ajouter(p1, 3), isNull);
      expect(pan.ajouter(p1, 1), contains('3 par produit'));
      expect(pan.restePour('P1'), 0);
      expect(pan.ajouter(p2, 2), contains('4 articles'));
      expect(pan.ajouter(p2, 1), isNull);
      expect(pan.articles, 4);
      expect(pan.total, 3500);
      expect(pan.changer('P2', 3), isNotNull);
      expect(pan.changer('P1', 0), isNull);
      expect(pan.ajouter(p2, 2), contains('Stock insuffisant'));
      pan.vider();
      expect(pan.vide, isTrue);
    });

    test('recherche : nettoyée, bornée, rien sous 3 caractères', () {
      expect(BorneService.texteRecherche('do'), isNull);
      expect(BorneService.texteRecherche('  d\u0000o '), isNull);
      expect(BorneService.texteRecherche('%%%'), isNull);
      expect(BorneService.texteRecherche('doli'), 'doli');
      expect(BorneService.texteRecherche('x' * 200)!.length, 60);
    });

    test('vérification : prix changé, stock réduit, produit disparu', () async {
      final gw = _Gw();
      final s = BorneService(gw);
      final lignes = [
        BorneLigne(BorneProduit(gw.produits['P1']!), 2),
        BorneLigne(BorneProduit(gw.produits['P2']!), 4),
        BorneLigne(BorneProduit(gw.produits['P4']!), 1),
      ];
      gw.produits['P1'] = _p('P1', 'DOLIPRANE 1000MG CP B/8', '3595583', 1700, 40);
      gw.produits['P2'] = _p('P2', 'DOLIPRANE 2,4% SUSP BUV FL/100ML', '3400001', 2100, 3);
      gw.produits.remove('P4');
      final v = (await s.verifier(lignes)).valueOrNull!;
      expect(v.ecarts.length, 3);
      expect(v.ecarts[0].texte, contains('${_n(1500)} F → ${_n(1700)} F'));
      expect(v.ecarts[1].texte, contains('ramenée à 3'));
      expect(v.ecarts[2].retire, isTrue);
      expect(v.total, 2 * 1700 + 3 * 2100);
      gw.panne = true;
      expect((await s.verifier(lignes)).isOk, isFalse, reason: 'panne ≠ « aucun écart »');
    });

    test('ticket : numéro, produits, total, invitation ; discret sans les noms', () {
      final p = BornePrevente(
        venteId: 'V1',
        reference: '20261011000042',
        total: 5100,
        lignes: [SaleItemDetail(lgPREENREGISTREMENTDETAILID: 'D', lgFAMILLEID: 'P1', strNAME: 'DOLIPRANE 1000MG CP B/8', intCIP: '1', intQUANTITY: 2, intPRICEUNITAIR: 1500, intPRICE: 3000, strREF: '')],
        at: DateTime(2026, 10, 11, 9, 30),
      );
      expect(p.numero, '0042');
      final t = BorneTicket(officine: 'PHCIE', prevente: p);
      expect(t.lignes.join('\n'), contains('DOLIPRANE 1000MG'));
      expect(t.lignes.join('\n'), contains('2 x ${_n(1500)}'));
      expect(t.lignes.last, 'TOTAL A PAYER: ${_n(5100)} F');
      expect(t.date, '11/10/2026 09:30');
      final d = BorneTicket(officine: 'PHCIE', prevente: p, discret: true);
      expect(d.lignes.join('\n'), isNot(contains('DOLIPRANE')));
      expect(d.lignes.first, '2 articles');
    });
  });

  group('Parcours', () {
    testWidgets('parcours complet : recherche, fiche, panier, prévente, ticket imprimé, retour accueil', (tester) async {
      final j = _journal();
      final env = await _borne(tester);
      expect(env.kiosque.demarrages, 1, reason: 'épinglage demandé à l\'ouverture');
      expect(HorsLigneScope.masquer.value, isTrue);
      expect(find.text(BorneConfig.accueilDefaut), findsOneWidget);
      expect(find.text('Douleur'), findsOneWidget);

      // Moins de 3 lettres : rien n'est envoyé.
      await _chercher(tester, 'do');
      expect(env.gw.recherches, 0);
      await _chercher(tester, 'doli');
      expect(env.gw.recherches, 1);
      expect(find.byKey(const ValueKey('borne-produit-P1')), findsOneWidget);
      // Indisponible : affiché, non ajoutable.
      expect(find.text('Indisponible'), findsWidgets);
      expect(find.byKey(const ValueKey('borne-ajouter-P3')), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('borne-produit-P3')));
      expect(find.byKey(const ValueKey('borne-fiche-indisponible')), findsOneWidget);
      expect(find.byKey(const ValueKey('borne-fiche-ajouter')), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('borne-retour')));

      // Fiche : 2 boîtes.
      await _tap(tester, find.byKey(const ValueKey('borne-produit-P1')));
      expect(find.byKey(const ValueKey('borne-fiche-prix')), findsOneWidget);
      expect(find.text(prixF(1500)), findsWidgets);
      await _tap(tester, find.byKey(const ValueKey('borne-fiche-qte-plus')));
      expect(find.byKey(const ValueKey('borne-fiche-qte-valeur')).evaluate().isNotEmpty, isTrue);
      await _tap(tester, find.byKey(const ValueKey('borne-fiche-ajouter')));
      // Ajout rapide depuis la liste.
      await _tap(tester, find.byKey(const ValueKey('borne-ajouter-P2')));
      expect(find.text('3 articles'), findsOneWidget);
      expect(find.text(prixF(5100)), findsWidgets);

      await _tap(tester, find.byKey(const ValueKey('borne-voir-panier')));
      expect(find.byKey(const ValueKey('borne-total')), findsOneWidget);
      // Retirer puis remettre (modifier).
      await _tap(tester, find.byKey(const ValueKey('borne-retirer-P2')));
      expect(find.text(prixF(3000)), findsWidgets);
      await _tap(tester, find.byKey(const ValueKey('borne-panier-qte-P1-plus')));
      expect(env.cle.currentState!.panier.qteDe('P1'), 3);

      // Payer en caisse : double appui = une seule prévente.
      final payer = find.byKey(const ValueKey('borne-payer'));
      await tester.ensureVisible(payer);
      await tester.tap(payer);
      await tester.tap(payer, warnIfMissed: false);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(env.gw.ajouts.length, 1);
      expect(env.gw.ajouts.single.qte, 3);
      expect(env.gw.cles.single, startsWith('BORNE-'), reason: 'X-Client-Ref sur la création');
      expect(env.gw.terminees, 1);
      expect(find.byKey(const ValueKey('borne-numero')), findsOneWidget);
      expect(find.text('0042'), findsOneWidget);
      final t = env.imprimante.tickets.single;
      expect(t.lignes.join(' '), contains('DOLIPRANE 1000MG'));
      expect(t.prevente.reference, '20261011000042');
      expect(t.prevente.total, 4500);
      expect(env.cle.currentState!.panier.vide, isTrue);

      // Journal : prévente borne créée, montant, référence.
      final e = (await j.lire()).where((e) => e.action == 'Prévente borne créée').single;
      expect(e.montant, 4500);
      expect(e.refServeur, '20261011000042');
      expect(e.type, TypeJournal.prevente);

      // Retour automatique à l'accueil après 10 s.
      await tester.pump(const Duration(seconds: 11));
      await tester.pump();
      expect(env.cle.currentState!.vue, BorneVue.accueil);
      expect(find.byKey(const ValueKey('borne-accueil-texte')), findsOneWidget);
      _sansErreur(tester);
      await _fin(tester);
      expect(HorsLigneScope.masquer.value, isFalse);
    });

    testWidgets('écart de prix montré avant confirmation ; prévente au prix du serveur', (tester) async {
      _journal();
      final env = await _borne(tester);
      await _chercher(tester, 'doli');
      await _tap(tester, find.byKey(const ValueKey('borne-ajouter-P1')));
      env.gw.produits['P1'] = _p('P1', 'DOLIPRANE 1000MG CP B/8', '3595583', 1700, 40);
      await _tap(tester, find.byKey(const ValueKey('borne-voir-panier')));
      await _tap(tester, find.byKey(const ValueKey('borne-payer')));
      expect(env.cle.currentState!.vue, BorneVue.ecarts);
      expect(find.textContaining('${_n(1500)} F → ${_n(1700)} F'), findsOneWidget);
      expect(env.gw.ajouts, isEmpty, reason: 'rien n\'est créé avant l\'accord du client');
      await _tap(tester, find.byKey(const ValueKey('borne-confirmer-ecarts')));
      expect(env.gw.ajouts.single.pu, 1700);
      expect(find.text('0042'), findsOneWidget);
      await _fin(tester);
    });

    testWidgets('sans imprimante : numéro + QR plein écran ; ticket discret', (tester) async {
      _journal();
      final env = await _borne(tester, config: const BorneConfig(actif: true, login: 'b', ticketDiscret: true));
      env.imprimante.ok = false;
      await _chercher(tester, 'gel intime');
      await _tap(tester, find.byKey(const ValueKey('borne-ajouter-P4')));
      await _tap(tester, find.byKey(const ValueKey('borne-voir-panier')));
      await _tap(tester, find.byKey(const ValueKey('borne-payer')));
      expect(find.byKey(const ValueKey('borne-qr')), findsOneWidget);
      expect(find.byKey(const ValueKey('borne-reference')), findsOneWidget);
      final t = env.imprimante.tickets.single;
      expect(t.discret, isTrue);
      expect(t.lignes.join(), isNot(contains('INTIME')));
      await _fin(tester);
    });

    testWidgets('plafond par produit : « + » bloqué au maximum', (tester) async {
      final env = await _borne(tester, config: const BorneConfig(actif: true, login: 'b', maxParProduit: 2));
      await _chercher(tester, 'doli');
      await _tap(tester, find.byKey(const ValueKey('borne-produit-P1')));
      await _tap(tester, find.byKey(const ValueKey('borne-fiche-qte-plus')));
      final plus = tester.widget<OutlinedButton>(find.byKey(const ValueKey('borne-fiche-qte-plus')));
      expect(plus.onPressed, isNull);
      await _tap(tester, find.byKey(const ValueKey('borne-fiche-ajouter')));
      await _tap(tester, find.byKey(const ValueKey('borne-produit-P1')));
      expect(find.byKey(const ValueKey('borne-fiche-plafond')), findsOneWidget);
      expect(env.cle.currentState!.panier.qteDe('P1'), 2);
      await _fin(tester);
    });

    testWidgets('inactivité : « Êtes-vous toujours là ? » 10 s avant, puis accueil et panier vidé', (tester) async {
      final env = await _borne(tester, config: const BorneConfig(actif: true, login: 'b', inactivite: 20));
      await _chercher(tester, 'doli');
      await _tap(tester, find.byKey(const ValueKey('borne-ajouter-P1')));
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(find.text(BorneScreen.toujoursLa), findsOneWidget);
      // Toucher l'écran : la session continue.
      await tester.tap(find.text('Je suis là'));
      await tester.pump();
      expect(find.text(BorneScreen.toujoursLa), findsNothing);
      expect(env.cle.currentState!.panier.vide, isFalse);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(find.text(BorneScreen.toujoursLa), findsOneWidget);
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text(BorneScreen.toujoursLa), findsNothing);
      expect(env.cle.currentState!.vue, BorneVue.accueil);
      expect(env.cle.currentState!.panier.vide, isTrue);
      await _fin(tester);
    });

    testWidgets('serveur injoignable : borne indisponible, retour automatique quand il revient', (tester) async {
      final env = await _borne(tester);
      await _chercher(tester, 'doli');
      await _tap(tester, find.byKey(const ValueKey('borne-ajouter-P1')));
      env.monitor.goOffline(manuel: false);
      await tester.pump();
      expect(find.text(BorneScreen.indisponibleTitre), findsOneWidget);
      expect(find.text(BorneScreen.indisponibleTexte), findsOneWidget);
      expect(env.cle.currentState!.panier.vide, isTrue, reason: 'confidentialité');
      expect(find.byKey(const ValueKey('borne-recherche')), findsNothing);
      env.monitor.goOnline();
      await tester.pump();
      expect(find.text(BorneScreen.indisponibleTitre), findsNothing);
      expect(find.byKey(const ValueKey('borne-recherche')), findsOneWidget);
      // Panne pendant une recherche : message + Réessayer (jamais « aucun produit »).
      env.gw.panne = true;
      await _chercher(tester, 'doli');
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.byKey(const ValueKey('borne-aucun')), findsNothing);
      await _fin(tester);
    });

    testWidgets('connexion de l\'utilisateur borne : indisponible tant qu\'elle échoue', (tester) async {
      _taille(tester, const Size(360, 740));
      final env = _Env();
      var ok = false;
      var essais = 0;
      await tester.pumpWidget(MaterialApp(
        home: BorneScreen(
          service: env.service,
          config: const BorneConfig(actif: true, login: 'b'),
          monitor: env.monitor,
          imprimante: env.imprimante,
          adminCheck: (_) async => true,
          onSortie: (_) {},
          connexion: () async {
            essais++;
            return ok;
          },
        ),
      ));
      await tester.pump();
      expect(find.text(BorneScreen.indisponibleTitre), findsOneWidget);
      ok = true;
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(essais, 2);
      expect(find.text(BorneScreen.indisponibleTitre), findsNothing);
      await _fin(tester);
    });

    testWidgets('kiosque : retour neutralisé ; sortie par appui long 5 s + code admin', (tester) async {
      final env = await _borne(tester);
      // Bouton retour Android : on reste sur la borne.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(const ValueKey('borne-accueil-texte')), findsOneWidget);
      // Appui court : rien.
      await tester.tap(find.byKey(const ValueKey('borne-sortie')));
      await tester.pump(const Duration(seconds: 6));
      expect(env.adminChecks, 0);
      // Appui long 5 s, code refusé : on reste.
      env.adminAnswer = false;
      var g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('borne-sortie'))));
      await tester.pump(const Duration(seconds: 6));
      await g.up();
      await tester.pump();
      expect(env.adminChecks, 1);
      expect(env.sorties, 0);
      expect(env.kiosque.arrets, 0);
      env.adminAnswer = true;
      g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('borne-sortie'))));
      await tester.pump(const Duration(seconds: 6));
      await g.up();
      await tester.pump();
      expect(env.adminChecks, 2);
      expect(env.kiosque.arrets, 1);
      expect(env.sorties, 1);
      await _fin(tester);
    });
  });

  group('Responsive et présentations', () {
    for (final pres in BornePresentation.values) {
      for (final (nom, taille, lateral) in [
        ('360 px', const Size(360, 740), false),
        ('tablette portrait', const Size(800, 1280), false),
        ('tablette paysage', const Size(1280, 800), true),
      ]) {
        testWidgets('${pres.label} · $nom : accueil, résultats, fiche, panier sans débordement', (tester) async {
          final env = await _borne(tester, config: BorneConfig(actif: true, login: 'b', presentation: pres), taille: taille);
          _sansErreur(tester);
          await _chercher(tester, 'doli');
          _sansErreur(tester);
          expect(find.byKey(const ValueKey('borne-panier-lateral')), lateral ? findsOneWidget : findsNothing);
          await _tap(tester, find.byKey(const ValueKey('borne-ajouter-P1')));
          if (!lateral) {
            await _tap(tester, find.byKey(const ValueKey('borne-voir-panier')));
          } else {
            await _tap(tester, find.byKey(const ValueKey('borne-panier-lateral-payer')));
          }
          expect(find.byKey(const ValueKey('borne-payer')), findsOneWidget);
          // Boutons tactiles d'au moins 56 px.
          expect(tester.getSize(find.byKey(const ValueKey('borne-payer'))).height, greaterThanOrEqualTo(56));
          _sansErreur(tester);
          expect(env.gw.recherches, greaterThan(0));
          await _fin(tester);
        });
      }
    }

    test('colonnes : 1 (terminal), 2–3 (tablette portrait), 4 + panier latéral (paysage)', () {
      expect(BorneScreenState.colonnes(360), 1);
      expect(BorneScreenState.colonnes(700), 2);
      expect(BorneScreenState.colonnes(800), 3);
      expect(BorneScreenState.colonnes(1280), 4);
      expect(BorneScreenState.panierLateral(800), isFalse);
      expect(BorneScreenState.panierLateral(1280), isTrue);
    });
  });

  group('Aperçus', () {
    // Génère docs/maquettes/apercus/borne_*.png (BORNE_APERCUS=1 flutter test test/borne_test.dart).
    final actif = Platform.environment['BORNE_APERCUS'] == '1';
    for (final (nom, pres, taille) in [
      ('vitrine_terminal', BornePresentation.vitrine, const Size(360, 720)),
      ('liste_rapide_terminal', BornePresentation.listeRapide, const Size(360, 720)),
      ('guidee_tablette', BornePresentation.guidee, const Size(800, 1100)),
      ('vitrine_paysage', BornePresentation.vitrine, const Size(1280, 800)),
    ]) {
      testWidgets('aperçu $nom', (tester) async {
        await _polices();
        _taille(tester, taille);
        final env = _Env();
        await tester.pumpWidget(RepaintBoundary(key: const ValueKey('cadre'), child: env.app(BorneConfig(actif: true, login: 'b', presentation: pres))));
        await tester.pump();
        await _png(tester, 'borne_${nom}_accueil');
        await _chercher(tester, 'doli');
        await _tap(tester, find.byKey(const ValueKey('borne-ajouter-P1')));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        await _png(tester, 'borne_${nom}_resultats');
        if (nom == 'vitrine_terminal') {
          await _tap(tester, find.byKey(const ValueKey('borne-voir-panier')));
          await tester.pump(const Duration(seconds: 1));
          await _png(tester, 'borne_panier_terminal');
          await _tap(tester, find.byKey(const ValueKey('borne-retour')));
          await _tap(tester, find.byKey(const ValueKey('borne-produit-P1')));
          await _png(tester, 'borne_fiche_terminal');
          await _tap(tester, find.byKey(const ValueKey('borne-retour')));
          await _tap(tester, find.byKey(const ValueKey('borne-voir-panier')));
          await _tap(tester, find.byKey(const ValueKey('borne-payer')));
          await _png(tester, 'borne_ticket_terminal');
        }
        await _fin(tester);
      }, skip: !actif);
    }
  });

  group('Intégration serveur de test', () {
    final url = Platform.environment['PRESTIGE_TEST_URL'] ?? 'http://localhost:8080/prestige/api/v1';
    test('prévente borne créée sur le vrai serveur (retrouvable par sa référence), puis supprimée', () => HttpOverrides.runWithHttpOverrides(() async {
          try {
            final r = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 2), receiveTimeout: const Duration(seconds: 5))).get('$url/officine');
            if (r.statusCode != 200) throw StateError('code ${r.statusCode}');
          } catch (_) {
            markTestSkipped('Serveur de test injoignable : $url');
            return;
          }
          final api = ApiService(baseUrl: url);
          if (await api.login('admin', 'Test1234') == null) {
            markTestSkipped('Connexion admin impossible sur $url');
            return;
          }
          final gw = DioVenteGateway(api);
          final page = await gw.searchProductsPage('DOLIMEX', 0, 50);
          final p = page.valueOrNull?.items.where((x) => x.intNUMBERAVAILABLE > 0 && x.intPRICE > 0).firstOrNull;
          if (p == null) {
            markTestSkipped('Aucun produit DOLIMEX en stock sur le serveur de test.');
            return;
          }
          final s = BorneService(gw);
          final v = await s.verifier([BorneLigne(BorneProduit(p), 1)]);
          expect(v.valueOrNull?.ecarts, isEmpty, reason: v.message);
          final r = await s.creerPrevente(v.valueOrNull!.lignes);
          expect(r.isOk, isTrue, reason: r.message);
          final pv = r.valueOrNull!;
          try {
            expect(pv.reference, isNotEmpty);
            expect(pv.lignes.single.lgFAMILLEID, p.lgFAMILLEID);
            // Le caissier la retrouve dans « Préventes à encaisser » par la référence du ticket.
            final liste = await gw.preventes();
            final trouvee = liste.valueOrNull!.where((x) => x.strREF.toLowerCase().contains(pv.reference.toLowerCase())).toList();
            expect(trouvee.map((x) => x.lgPREENREGISTREMENTID), contains(pv.venteId));
          } finally {
            final del = await api.dio.post('/ventestats/remove/${pv.venteId}');
            // ignore: avoid_print
            print('Borne intégration : prévente ${pv.reference} supprimée (${del.data}).');
          }
        }, _RealHttp()), timeout: const Timeout(Duration(minutes: 2)));
  });
}

class _RealHttp extends HttpOverrides {}

/// Aucune erreur de rendu (débordement…) ; sinon le détail est affiché.
void _sansErreur(WidgetTester tester) {
  if (Platform.environment['BORNE_DEBUG'] == '1') return;
  final e = tester.takeException();
  if (e != null) fail(e is FlutterError ? e.toStringDeep() : '$e');
}

String _n(int v) => Constants.formatNumber(v);

bool _policesChargees = false;

/// Polices réelles (Roboto + icônes) pour des aperçus lisibles.
Future<void> _polices() async {
  if (_policesChargees) return;
  _policesChargees = true;
  final sdk = Platform.environment['FLUTTER_ROOT'] ?? '';
  final dir = Directory('$sdk/bin/cache/artifacts/material_fonts');
  Future<void> charger(String famille, List<String> fichiers) async {
    final l = FontLoader(famille);
    for (final f in fichiers) {
      final file = File('${dir.path}/$f');
      if (file.existsSync()) l.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    }
    await l.load();
  }

  await charger('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await charger('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

Future<void> _png(WidgetTester tester, String nom) async {
  await tester.runAsync(() async {
    final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('cadre')));
    final img = await ro.toImage(pixelRatio: 1.5);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File('docs/maquettes/apercus/$nom.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}
