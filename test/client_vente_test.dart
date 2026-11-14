// ÉCRANS — 4.13.0 : zone « Client » de la vente comptant (faux service, données FICTIVES) :
//  - zone absente sans la capacité (passerelle sans ClientVenteGateway : écrans d'avant inchangés), absente avant
//    le 1er article, présente ensuite ;
//  - recherche : rien avant 3 caractères ou 4 chiffres, une seule requête pour une frappe rapide, résultats nom,
//    prénom, téléphone ;
//  - nom affiché SEULEMENT après success:true ; refus → msg tel quel, client précédent gardé ;
//  - croix : rouge au 1er appui (rien envoyé), redevient grise après le délai, 2e appui → clientId null ; échec du
//    retrait → client gardé ;
//  - « Nouveau client » : refus du serveur tel quel ; création réussie mais rattachement refusé → « Associer le client
//    créé » sans recréer ; réponse perdue → recherche proposée (jamais un second client) ;
//  - reprise (resumeVenteId) : client lu avec la vente ; relecture impossible → « Réessayer » ;
//  - encaissement : clientId = client rattaché ou vide ; plus aucun appel « client = mode de règlement » ;
//  - 403 interdit (recherche, création, rattachement) : msg, aucune déconnexion.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/client_vente.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final produitFictif = ProductSearchResult(
  lgFAMILLEID: 'P1',
  strNAME: 'PRODUIT FICTIF 500MG CP B/16',
  intCIP: '3400930000001',
  intPRICE: 1500,
  intNUMBERAVAILABLE: 10,
  strLIBELLEE: '',
  intPAF: 0,
);

const clientA = ClientVente(id: 'CL-A', nom: 'KOFFI-TEST', prenom: 'AMANI', telephone: '0700000001');
const clientB = ClientVente(id: 'CL-B', nom: 'YAO-FICTIF', prenom: 'CELESTE', telephone: '0100000003');

/// Passerelle simulée de la vente comptant, SANS la capacité Client (comme les écrans d'avant 4.13.0).
class FauxVenteSansClient implements VenteGateway {
  Duration delai = const Duration(milliseconds: 20);
  final Map<String, List<SaleItemDetail>> ventes = {};
  final Map<String, String> statut = {};
  final List<String> clotureClientIds = [];
  final List<String> updateClientAppels = [];
  int creations = 0;

  Future<void> _w() => Future.delayed(delai);

  @override
  Future<VenteResult<List<ProductSearchResult>>> searchProducts(String query) async {
    await _w();
    return VenteOk([produitFictif]);
  }

  @override
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async {
    await _w();
    return VenteOk(ProductPage(start == 0 ? [produitFictif] : const [], 1));
  }

  @override
  Future<VenteResult<String>> addItemVno({required String produitId, required int qte, required int itemPu, String? venteId, required bool prevente}) async {
    await _w();
    final id = venteId ?? 'V${++creations}';
    statut.putIfAbsent(id, () => 'pending');
    final l = ventes.putIfAbsent(id, () => []);
    l.add(SaleItemDetail(
      lgPREENREGISTREMENTDETAILID: '$id-L${l.length + 1}',
      lgFAMILLEID: produitId,
      strNAME: produitFictif.strNAME,
      intCIP: produitFictif.intCIP,
      intQUANTITY: qte,
      intPRICEUNITAIR: itemPu,
      intPRICE: qte * itemPu,
      strREF: 'REF-$id',
    ));
    return VenteOk(id);
  }

  @override
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async {
    await _w();
    return VenteOk(List.of(ventes[venteId] ?? const []));
  }

  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) async {
    await _w();
    final t = (ventes[venteId] ?? const []).fold<int>(0, (s, i) => s + i.intPRICE);
    return VenteOk(SaleSummary(montant: t, montantNet: t, venteId: venteId, reference: 'REF-$venteId'));
  }

  @override
  Future<VenteResult<void>> updateClient(String venteId, String clientId) async {
    updateClientAppels.add(clientId);
    return const VenteOk(null);
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> cloturerVno({
    required String venteId,
    required SaleSummary summary,
    required String typeReglementId,
    required String clientId,
    required String userVendeurId,
    int? montantRecu,
    int? montantRemis,
  }) async {
    clotureClientIds.add(clientId);
    await _w();
    statut[venteId] = 'is_Closed';
    return const VenteOk({'success': true});
  }

  @override
  Future<VenteResult<List<PaymentMethod>>> paymentMethods() async => VenteOk([PaymentMethod(id: '1', name: 'Espèces'), PaymentMethod(id: '10', name: 'WAVE')]);
  @override
  Future<VenteResult<List<PaymentMethodQr>>> paymentMethodsWithQr() async => const VenteOk([]);
  @override
  Future<VenteResult<List<PreventeListItem>>> preventes() async => const VenteOk([]);
  @override
  Future<VenteResult<void>> terminerPrevente(String venteId) async => const VenteOk(null);

  Map<String, dynamic>? clientLu;
  VenteResult<Map<String, dynamic>>? lectureForcee;
  int lectures = 0;

  @override
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId) async {
    lectures++;
    await _w();
    final f = lectureForcee;
    if (f != null) return f;
    return VenteOk({'strSTATUT': statut[venteId] ?? 'pending', 'lgTYPEVENTEID': '1', 'client': clientLu});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// Même passerelle, AVEC la capacité Client : réponses programmables, appels notés.
class FauxVenteClient extends FauxVenteSansClient implements ClientVenteGateway {
  List<ClientVente> trouves = [clientA, clientB];
  final List<String> recherches = [];
  final List<({String nom, String prenom, String telephone})> creationsClient = [];
  final List<String?> rattachements = [];
  VenteResult<void> Function(String? clientId)? reponseRattachement;
  VenteResult<ClientVente> Function()? reponseCreation;
  VenteResult<List<ClientVente>>? reponseRecherche;
  Completer<void>? suspendreRattachement;

  @override
  Future<VenteResult<List<ClientVente>>> rechercherClientsVente(String texte) async {
    recherches.add(texte);
    await _w();
    return reponseRecherche ?? VenteOk(trouves);
  }

  @override
  Future<VenteResult<ClientVente>> creerClientVente({required String nom, required String prenom, required String telephone}) async {
    creationsClient.add((nom: nom, prenom: prenom, telephone: telephone));
    await _w();
    final f = reponseCreation;
    if (f != null) return f();
    return VenteOk(ClientVente(id: 'CL-NEW', nom: nom.toUpperCase(), prenom: prenom.toUpperCase(), telephone: telephone));
  }

  @override
  Future<VenteResult<void>> rattacherClientVente(String venteId, String? clientId) async {
    rattachements.add(clientId);
    await _w();
    final s = suspendreRattachement;
    if (s != null) await s.future;
    final f = reponseRattachement;
    return f == null ? const VenteOk(null) : f(clientId);
  }
}

class _Auth extends AuthProvider {
  _Auth() : super(ApiService(baseUrl: 'http://localhost'));
  @override
  User? get user => User(userId: 'U1', login: 'vendeur', firstName: 'Vendeur', lastName: 'Fictif', officineName: 'OFFICINE FICTIVE');
}

/// Monte l'écran de vente (comme le menu Pré-vente / Vente).
Future<void> ouvrirVente(WidgetTester t, FauxVenteSansClient gw, {String? resumeVenteId, ListPresentation presentation = ListPresentation.dashboard}) async {
  SharedPreferences.setMockInitialValues({'enabled_payment_method_ids': ['1', '10']});
  await initializeDateFormatting('fr_FR', null);
  final settings = SettingsProvider();
  await settings.loadSettings();
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
    ],
    child: MaterialApp(home: VenteScreen(gateway: gw, resumeVenteId: resumeVenteId, presentation: presentation)),
  ));
  await t.pumpAndSettle();
}

/// Ajoute le produit fictif (1 boîte) : la vente est créée sur le serveur simulé.
Future<void> ajouterArticle(WidgetTester t) async {
  await t.enterText(find.byKey(const ValueKey('vente-recherche')), 'PRODUIT');
  await t.pump(const Duration(milliseconds: 600));
  await t.pumpAndSettle();
  await t.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), '1');
  await t.tap(find.text('Ajouter'));
  await t.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
}

final zoneClient = find.byKey(const ValueKey('client-vente-zone'));
final nomClient = find.byKey(const ValueKey('client-vente-nom'));
final croixClient = find.byKey(const ValueKey('client-vente-retirer'));
final champRecherche = find.byKey(const ValueKey('client-vente-recherche'));
final erreurClient = find.byKey(const ValueKey('client-vente-erreur'));

Future<void> ouvrirPageClient(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('client-vente-ouvrir')));
  await t.pumpAndSettle();
}

Future<void> chercher(WidgetTester t, String texte) async {
  await t.enterText(champRecherche, texte);
  await t.pump(const Duration(milliseconds: 400));
  await t.pumpAndSettle();
}

Future<void> encaisserEspeces(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('vente-encaisser')));
  await t.pumpAndSettle();
  await t.tap(find.text('Exact'));
  await t.pump();
  await t.tap(find.byKey(const ValueKey('encaissement-imprimer')));
  await t.pump();
  final v = find.byKey(const ValueKey('encaissement-valider'));
  await t.ensureVisible(v);
  await t.tap(v);
  await t.pumpAndSettle();
}

void _telephone(WidgetTester t) {
  t.view.physicalSize = const Size(720, 1440);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('passerelle sans la capacité Client : aucune zone (écran d\'avant inchangé), encaissement sans client', (t) async {
    _telephone(t);
    final gw = FauxVenteSansClient();
    await ouvrirVente(t, gw);
    await ajouterArticle(t);
    expect(zoneClient, findsNothing);
    await encaisserEspeces(t);
    expect(gw.clotureClientIds, ['']);
    expect(gw.updateClientAppels, isEmpty, reason: 'plus jamais le nom du mode de règlement dans clientId');
    expect(gw.lectures, 0, reason: 'aucune relecture ajoutée sans la capacité');
  });

  testWidgets('zone absente avant le 1er article, présente ensuite ; recherche : seuils et une seule requête', (t) async {
    _telephone(t);
    final gw = FauxVenteClient();
    await ouvrirVente(t, gw);
    expect(zoneClient, findsNothing);
    await ajouterArticle(t);
    expect(zoneClient, findsOneWidget);
    expect(find.text('Client (facultatif)'), findsOneWidget);
    await ouvrirPageClient(t);
    await chercher(t, 'KO');
    expect(gw.recherches, isEmpty);
    expect(find.byKey(const ValueKey('client-vente-aide')), findsOneWidget);
    await chercher(t, '070');
    expect(gw.recherches, isEmpty, reason: 'numéro : 4 chiffres');
    // Frappe rapide : une seule requête (anti-rebond).
    for (final s in ['K', 'KO', 'KOF', 'KOFF', 'KOFFI']) {
      await t.enterText(champRecherche, s);
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(gw.recherches, ['KOFFI']);
    expect(find.text('KOFFI-TEST AMANI'), findsOneWidget);
    expect(find.text('0700000001'), findsOneWidget);
    expect(find.text('YAO-FICTIF CELESTE'), findsOneWidget);
    expect(find.text('2 clients'), findsOneWidget);
    await chercher(t, '0700');
    expect(gw.recherches.last, '0700');
    gw.reponseRecherche = const VenteOk([]);
    await chercher(t, 'ZZZ');
    expect(find.text('Aucun client trouvé.'), findsOneWidget);
  });

  testWidgets('nom affiché seulement après success:true ; refus → msg tel quel, client précédent gardé', (t) async {
    _telephone(t);
    final gw = FauxVenteClient();
    await ouvrirVente(t, gw);
    await ajouterArticle(t);
    await ouvrirPageClient(t);
    await chercher(t, 'KOFFI');
    gw.suspendreRattachement = Completer<void>();
    await t.tap(find.byKey(const ValueKey('client-vente-resultat-CL-A')));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('client-vente-page')), findsOneWidget, reason: 'en attente du serveur');
    expect(nomClient, findsNothing);
    gw.suspendreRattachement!.complete();
    gw.suspendreRattachement = null;
    await t.pumpAndSettle();
    expect(t.widget<Text>(nomClient).data, 'KOFFI-TEST AMANI');
    expect(find.text('Client associé à la vente.'), findsOneWidget);
    // Changer pour B : refusé par le serveur → A reste.
    gw.reponseRattachement = (_) => const VenteRefused('La vente REF-V1 est déjà terminée : elle ne peut plus être modifiée.');
    await ouvrirPageClient(t);
    await chercher(t, 'YAO');
    await t.tap(find.byKey(const ValueKey('client-vente-resultat-CL-B')));
    await t.pumpAndSettle();
    expect(find.text('La vente REF-V1 est déjà terminée : elle ne peut plus être modifiée.'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(t.widget<Text>(nomClient).data, 'KOFFI-TEST AMANI');
    expect(gw.rattachements, ['CL-A', 'CL-B']);
    await encaisserEspeces(t);
    expect(gw.clotureClientIds, ['CL-A']);
    expect(gw.updateClientAppels, isEmpty);
  });

  testWidgets('client changé : seul le second reste, la clôture porte le second', (t) async {
    _telephone(t);
    final gw = FauxVenteClient();
    await ouvrirVente(t, gw);
    await ajouterArticle(t);
    await ouvrirPageClient(t);
    await chercher(t, 'KOFFI');
    await t.tap(find.byKey(const ValueKey('client-vente-resultat-CL-A')));
    await t.pumpAndSettle();
    await ouvrirPageClient(t);
    await chercher(t, 'YAO');
    await t.tap(find.byKey(const ValueKey('client-vente-resultat-CL-B')));
    await t.pumpAndSettle();
    expect(t.widget<Text>(nomClient).data, 'YAO-FICTIF CELESTE');
    await encaisserEspeces(t);
    expect(gw.clotureClientIds, ['CL-B']);
  });

  testWidgets('croix : rouge au 1er appui (rien envoyé), grise après le délai ; 2e appui → retrait (clientId null)', (t) async {
    _telephone(t);
    final gw = FauxVenteClient();
    await ouvrirVente(t, gw);
    await ajouterArticle(t);
    await ouvrirPageClient(t);
    await chercher(t, 'KOFFI');
    await t.tap(find.byKey(const ValueKey('client-vente-resultat-CL-A')));
    await t.pumpAndSettle();
    Color couleur() => t.widget<Icon>(find.descendant(of: croixClient, matching: find.byType(Icon))).color!;
    final grise = couleur();
    await t.tap(croixClient);
    await t.pump();
    expect(couleur(), Colors.red.shade700);
    expect(find.byKey(const ValueKey('client-vente-confirmer')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing, reason: 'pas de fenêtre de confirmation');
    expect(gw.rattachements, ['CL-A']);
    await t.pump(delaiCroixRouge + const Duration(milliseconds: 100));
    expect(couleur(), grise, reason: 'désarmée après le délai');
    expect(nomClient, findsOneWidget);
    // Échec du retrait : client gardé, message.
    gw.reponseRattachement = (id) => id == null ? const VenteRefused('Vous n\'avez pas le droit de modifier cette vente.', code: VenteRefused.codeInterdit) : const VenteOk(null);
    await t.tap(croixClient);
    await t.pump();
    await t.tap(croixClient);
    await t.pumpAndSettle();
    expect(find.text('Vous n\'avez pas le droit de modifier cette vente.'), findsOneWidget);
    expect(nomClient, findsOneWidget);
    gw.reponseRattachement = null;
    await t.pump(const Duration(seconds: 5));
    await t.tap(croixClient);
    await t.pump();
    await t.tap(croixClient);
    await t.pumpAndSettle();
    expect(gw.rattachements, ['CL-A', null, null]);
    expect(nomClient, findsNothing);
    expect(find.text('Client (facultatif)'), findsOneWidget);
    await encaisserEspeces(t);
    expect(gw.clotureClientIds, ['']);
  });

  testWidgets('Nouveau client : refus du serveur tel quel ; rattachement refusé → « Associer le client créé » sans recréer',
      (t) async {
    _telephone(t);
    final gw = FauxVenteClient();
    await ouvrirVente(t, gw);
    await ajouterArticle(t);
    await ouvrirPageClient(t);
    await chercher(t, 'Nouveau-Fictif');
    await t.tap(find.byKey(const ValueKey('client-vente-nouveau')));
    await t.pumpAndSettle();
    final nom = find.byKey(const ValueKey('client-vente-nom-saisi'));
    expect(t.widget<TextField>(nom).controller!.text, 'NOUVEAU-FICTIF', reason: 'texte cherché proposé comme nom');
    await t.enterText(find.byKey(const ValueKey('client-vente-prenom-saisi')), 'Essai');
    await t.enterText(find.byKey(const ValueKey('client-vente-telephone-saisi')), '07 00 00 99 99');
    gw.reponseCreation = () => const VenteRefused('L\'adresse ou le téléphone ne doit pas dépasser 50 caractères.');
    final creer = find.byKey(const ValueKey('client-vente-creer'));
    await t.ensureVisible(creer);
    await t.tap(creer);
    await t.pumpAndSettle();
    expect(find.text('L\'adresse ou le téléphone ne doit pas dépasser 50 caractères.'), findsOneWidget);
    expect(gw.rattachements, isEmpty);
    gw.reponseCreation = null;
    gw.reponseRattachement = (_) => const VenteFailed('Serveur injoignable (associer le client)');
    await t.tap(creer);
    await t.pumpAndSettle();
    expect(find.textContaining('Client créé, mais non associé à la vente'), findsOneWidget);
    expect(find.text('Associer le client créé'), findsOneWidget);
    expect(gw.creationsClient, hasLength(2));
    expect(gw.creationsClient.last, (nom: 'NOUVEAU-FICTIF', prenom: 'Essai', telephone: '07 00 00 99 99'));
    gw.reponseRattachement = null;
    await t.tap(creer);
    await t.pumpAndSettle();
    expect(gw.creationsClient, hasLength(2), reason: 'jamais recréé');
    expect(gw.rattachements, ['CL-NEW', 'CL-NEW']);
    expect(t.widget<Text>(nomClient).data, 'NOUVEAU-FICTIF ESSAI');
  });

  testWidgets('Nouveau client, réponse perdue : la recherche du nom est relancée (pas de second client à l\'aveugle)', (t) async {
    _telephone(t);
    final gw = FauxVenteClient();
    await ouvrirVente(t, gw);
    await ajouterArticle(t);
    await ouvrirPageClient(t);
    await t.tap(find.byKey(const ValueKey('client-vente-nouveau')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('client-vente-nom-saisi')), 'PERDU-FICTIF');
    gw.reponseCreation = () => const VenteFailed('Le serveur met trop de temps à répondre (créer le client).', maybeApplied: true);
    final creer = find.byKey(const ValueKey('client-vente-creer'));
    await t.ensureVisible(creer);
    await t.tap(creer);
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    expect(find.textContaining('trop de temps'), findsOneWidget);
    expect(gw.recherches, ['PERDU-FICTIF'], reason: 'recherche relancée');
    expect(find.byKey(const ValueKey('client-vente-formulaire')), findsNothing);
    expect(gw.creationsClient, hasLength(1));
  });

  testWidgets('reprise (resumeVenteId) : client lu avec la vente ; relecture impossible → Réessayer', (t) async {
    _telephone(t);
    final gw = FauxVenteClient();
    await t.runAsync(() => gw.addItemVno(produitId: 'P1', qte: 1, itemPu: 1500, prevente: true));
    gw.clientLu = {'lgCLIENTID': 'CL-A', 'strFIRSTNAME': 'KOFFI-TEST', 'strLASTNAME': 'AMANI', 'strADRESSE': '0700000001'};
    gw.lectureForcee = const VenteFailed('Serveur injoignable (charger la vente)');
    await ouvrirVente(t, gw, resumeVenteId: 'V1');
    expect(find.byKey(const ValueKey('client-vente-non-lu')), findsOneWidget);
    expect(find.byKey(const ValueKey('client-vente-ouvrir')), findsOneWidget);
    gw.lectureForcee = null;
    await t.tap(find.byKey(const ValueKey('client-vente-relire')));
    await t.pumpAndSettle();
    expect(t.widget<Text>(nomClient).data, 'KOFFI-TEST AMANI');
    expect(gw.rattachements, isEmpty, reason: 'lecture seule');
    await encaisserEspeces(t);
    expect(gw.clotureClientIds, ['CL-A']);
  });

  testWidgets('403 interdit à la recherche et au rattachement : msg affiché, écran gardé', (t) async {
    _telephone(t);
    final gw = FauxVenteClient();
    await ouvrirVente(t, gw);
    await ajouterArticle(t);
    await ouvrirPageClient(t);
    gw.reponseRecherche = const VenteRefused('Vous n\'avez pas le droit de rechercher un client.', code: VenteRefused.codeInterdit);
    await chercher(t, 'KOFFI');
    expect(find.text('Vous n\'avez pas le droit de rechercher un client.'), findsOneWidget);
    gw.reponseRecherche = null;
    gw.reponseRattachement = (_) => const VenteRefused('Vous n\'avez pas le droit d\'associer un client.', code: VenteRefused.codeInterdit);
    await chercher(t, 'KOFFI-TEST');
    await t.tap(find.byKey(const ValueKey('client-vente-resultat-CL-A')));
    await t.pumpAndSettle();
    expect(find.text('Vous n\'avez pas le droit d\'associer un client.'), findsOneWidget);
    expect(find.byKey(const ValueKey('client-vente-page')), findsOneWidget);
  });

  testWidgets('ClientVenteZone seule : aucune action pendant un encaissement (enabled:false)', (t) async {
    _telephone(t);
    final gw = FauxVenteClient();
    await ouvrirVente(t, gw);
    await ajouterArticle(t);
    final zone = t.widget<ClientVenteZone>(find.byType(ClientVenteZone));
    expect(zone.enabled, isTrue);
  });
}
