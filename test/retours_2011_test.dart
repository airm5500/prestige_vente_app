// 5.1.0 — Retours du pharmacien du 20/11/2026 (unitaires et écrans, données FICTIVES uniquement) :
//  1. recherche produit de la vente : la liste des résultats reprend le texte tapé (champ rempli, curseur à la fin,
//     clavier ouvert), le filtre cherche chaque mot (« DOLI 1000 »), ne vide jamais les résultats du serveur
//     (variantes EAN / CIP) et, liste incomplète, un texte plus précis relance la recherche sur le serveur ;
//  2. fenêtre de quantité : « NOM · CIP xxxx » sur deux lignes au plus, plus de pastille CIP ;
//  3. imprimante intégrée Sunmi : service lié au démarrage, connexion RÉELLE attendue avant d'imprimer (canal simulé
//     dont la connexion arrive en retard), largeur jamais mémorisée sans connexion, autres appareils inchangés ;
//  4. « Préparation du ticket… » pendant que le serveur dessine le ticket ;
//  5. taux des organismes affichés plafonnés à 100 % (ticket local) ;
//  6. Analyse article : au clic, le CIP exact est demandé tout de suite, sans attendre le lot de la saisie.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/api/models/article_analysis_model.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/services/impression_ticket.dart';
import 'package:prestige_vente_app/services/imprimante_sunmi.dart';
import 'package:prestige_vente_app/services/largeur_ticket.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/ventes/common/product_list_modal.dart';
import 'package:prestige_vente_app/ventes/common/quantity_dialog.dart';
import 'package:prestige_vente_app/ventes/common/vente_product_search.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/taux_affiches.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/analyse_fictive.dart';
import 'outils/remises_fictives.dart';
import 'outils/tickets_vente_fictifs.dart';

ProductSearchResult _p(String id, String nom, String cip, {int prix = 1000, int stock = 10}) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: nom, intCIP: cip, intPRICE: prix, intNUMBERAVAILABLE: stock, strLIBELLEE: '', intPAF: 0);

/// Catalogue fictif : 120 « DOLI PRODUIT nnn », deux DOLIPRANE 1000.
final _catalogue = [
  for (var i = 0; i < 120; i++) _p('P$i', 'DOLI PRODUIT ${i.toString().padLeft(3, '0')}', '35955${i.toString().padLeft(2, '0')}'),
  _p('D1', 'DOLIPRANE 1000MG CP B/8', '3400930000001'),
  _p('D2', 'DOLIPRANE 1000MG EFF B/8', '3400930000002'),
];

/// Serveur fictif de recherche par pages : « commence par » ; « %a%b » (Contient) : chaque mot dans l'ordre.
class _Serveur {
  final List<String> requetes = [];
  Duration delai = Duration.zero;

  Future<VenteResult<ProductPage>> chercher(String q, int start, int limit) async {
    requetes.add(q);
    if (delai > Duration.zero) await Future<void>.delayed(delai);
    bool garde(ProductSearchResult p) {
      if (q.startsWith('%')) {
        var i = 0;
        for (final w in q.split('%').where((w) => w.isNotEmpty)) {
          final j = p.strNAME.toUpperCase().indexOf(w.toUpperCase(), i);
          if (j < 0) return false;
          i = j + w.length;
        }
        return true;
      }
      return p.strNAME.toUpperCase().startsWith(q.toUpperCase()) || p.intCIP.startsWith(q);
    }

    final all = _catalogue.where(garde).toList();
    return VenteOk(ProductPage(all.skip(start).take(limit).toList(), all.length));
  }
}

void _telephone(WidgetTester t) {
  t.view.physicalSize = const Size(720, 1440);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
}

Finder get _filtre => find.byKey(const ValueKey('liste-produits-filtre'));
EditableText _champFiltre(WidgetTester t) => t.widget<EditableText>(find.descendant(of: _filtre, matching: find.byType(EditableText)));

// --- Imprimante Sunmi simulée : le service se connecte en retard (comme onServiceConnected sur le terminal) ---
class _SunmiLent {
  final Duration connexion;
  bool jamais;
  DateTime? lieA;
  final List<String> appels = [];

  /// Commandes reçues alors que le service n'était pas encore connecté (perdues sur le vrai terminal).
  final List<String> perdues = [];
  _SunmiLent({this.connexion = const Duration(milliseconds: 400), this.jamais = false});

  bool get connecte => !jamais && lieA != null && DateTime.now().difference(lieA!) >= connexion;

  void installer() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ImprimanteSunmi.canal, (call) async {
      appels.add(call.method);
      switch (call.method) {
        case 'BIND_PRINTER_SERVICE':
          lieA ??= DateTime.now();
          return true; // comme le paquet : true dès la DEMANDE de liaison
        case 'PRINTER_VERSION':
          return connecte ? '2.4.1' : 'NOT FOUND';
        case 'PAPER_SIZE':
          return 1;
        case 'GET_UPDATE_PRINTER':
          return connecte ? 'NORMAL' : 'ERROR';
        default:
          if (!connecte) perdues.add(call.method);
          return null;
      }
    });
  }

  void retirer() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ImprimanteSunmi.canal, null);
}

TicketImage _image() => TicketImage(modele: 'VENTE', png: RemisesFictives.pngFictif(384, 40), largeurPoints: 384, hauteurPoints: 40);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ===========================================================================================================
  group('1. Filtre de la liste des résultats (unitaires)', () {
    final doli = _p('D1', 'DOLIPRANE 1000MG CP B/8', '3400930000001');
    test('chaque mot, dans n\'importe quel ordre, dans le nom ou le CIP ; % et _ = espaces', () {
      expect(ProductListFilter.matches(doli, 'DOLI 1000'), isTrue);
      expect(ProductListFilter.matches(doli, '1000 doli'), isTrue);
      expect(ProductListFilter.matches(doli, 'doli%1000'), isTrue);
      expect(ProductListFilter.matches(doli, 'doli 500'), isFalse);
      expect(ProductListFilter.matches(doli, '34009300'), isTrue);
      expect(ProductListFilter.matches(doli, '   '), isTrue);
      expect(ProductListFilter.norm('  Doli   1000 '), 'doli 1000');
      expect(ProductListFilter.extends_('DOLI P', 'doli'), isTrue);
      expect(ProductListFilter.extends_('doli', 'doli'), isFalse);
      expect(ProductListFilter.extends_('ibex', 'doli'), isFalse);
    });

    test('ProductPager.refine : même recherche, nouveau texte, aucune page chargée', () async {
      final s = _Serveur();
      final base = ProductPager(s.chercher, 'DOLI', mode: SearchMode.commencePar);
      await base.loadMore();
      final r = base.refine('DOLI PRODUIT 11');
      expect(r.query, 'DOLI PRODUIT 11');
      expect(r.mode, SearchMode.commencePar);
      expect(r.items, isEmpty);
      expect(r.total, 0);
      await r.loadMore();
      expect(r.items.length, 10);
      expect(s.requetes, ['DOLI', 'DOLI PRODUIT 11']);
    });
  });

  // ===========================================================================================================
  group('1. Liste des résultats (écran)', () {
    Future<List<Object?>> ouvrir(WidgetTester t, List<ProductSearchResult> r, {String q = '', ProductPager? pager}) async {
      final res = <Object?>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async => res.add(await showProductListModal(ctx, r, initialQuery: q, pager: pager)),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      return res;
    }

    testWidgets('texte tapé repris : champ rempli, focus, curseur à la fin, clavier ouvert', (t) async {
      _telephone(t);
      await ouvrir(t, _catalogue.sublist(0, 3), q: 'DOLI PRO');
      expect(_champFiltre(t).controller.text, 'DOLI PRO');
      expect(_champFiltre(t).focusNode.hasFocus, isTrue);
      expect(_champFiltre(t).controller.selection, const TextSelection.collapsed(offset: 8));
      expect(t.testTextInput.isVisible, isTrue, reason: 'clavier ouvert');
      expect(find.text('Résultats (3)'), findsOneWidget, reason: 'texte repris : aucun filtre, tous les résultats');
    });

    testWidgets('résultats d\'un code (variantes EAN / CIP) jamais vidés par le texte repris', (t) async {
      _telephone(t);
      // EAN-13 tapé : le serveur a renvoyé deux produits dont ni le nom ni le CIP ne contiennent ce texte.
      await ouvrir(t, [_catalogue[83], _catalogue[84]], q: '3400935955838');
      expect(find.text('Résultats (2)'), findsOneWidget);
      expect(find.text('DOLI PRODUIT 083'), findsOneWidget);
      expect(find.text('Aucun produit dans cette liste'), findsNothing);
      // Texte modifié par l'utilisateur : le filtre s'applique (mot par mot).
      await t.enterText(_filtre, '084');
      await t.pump();
      expect(find.text('Résultats (1)'), findsOneWidget);
    });

    testWidgets('« Contient » sur plusieurs mots (« DOLI 1000 ») : résultats gardés, filtre mot par mot', (t) async {
      _telephone(t);
      await ouvrir(t, [_catalogue[120], _catalogue[121]], q: 'DOLI 1000');
      expect(find.text('Résultats (2)'), findsOneWidget, reason: 'avant 5.1.0 : « doli 1000 » cherché en entier → liste vide');
      await t.enterText(_filtre, 'DOLI 1000 EFF');
      await t.pump();
      expect(find.text('Résultats (1)'), findsOneWidget);
      expect(find.text('DOLIPRANE 1000MG EFF B/8'), findsOneWidget);
    });

    testWidgets('liste incomplète (50 sur 120) : texte précisé → UNE nouvelle recherche serveur après la frappe, clavier ouvert', (t) async {
      _telephone(t);
      final s = _Serveur();
      final base = ProductPager(s.chercher, 'DOLI', mode: SearchMode.commencePar);
      await base.loadMore();
      await ouvrir(t, base.items, q: 'DOLI', pager: base);
      expect(find.text('Résultats (50 sur 122)'), findsOneWidget);
      // Frappe rapide « DOLI P… 11 » : une seule requête, celle du texte final (les précédentes abandonnées).
      for (final txt in ['DOLI P', 'DOLI PRODUIT', 'DOLI PRODUIT 1', 'DOLI PRODUIT 11']) {
        await t.enterText(_filtre, txt);
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('DOLI PRODUIT 110'), findsNothing, reason: 'pas encore chargé (50 premiers seulement)');
      await t.pump(const Duration(milliseconds: 500));
      await t.pump();
      expect(s.requetes, ['DOLI', 'DOLI PRODUIT 11']);
      expect(find.text('Résultats (10 sur 10)'), findsOneWidget);
      expect(find.text('DOLI PRODUIT 110'), findsOneWidget);
      expect(_champFiltre(t).focusNode.hasFocus, isTrue);
      expect(t.testTextInput.isVisible, isTrue, reason: 'le clavier reste ouvert');
      // Texte encore plus précis, liste précise complète : filtre local, aucune requête.
      await t.enterText(_filtre, 'DOLI PRODUIT 115');
      await t.pump(const Duration(milliseconds: 600));
      expect(s.requetes, hasLength(2));
      expect(find.widgetWithText(ListTile, 'DOLI PRODUIT 115'), findsOneWidget);
      // Retour au texte d'origine : la liste d'origine revient, sans requête.
      await t.enterText(_filtre, 'DOLI');
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Résultats (50 sur 122)'), findsOneWidget);
      expect(s.requetes, hasLength(2));
      expect(t.takeException(), isNull);
    });

    testWidgets('serveur lent pendant la recherche précise : filtre local tout de suite, indicateur, puis liste du serveur', (t) async {
      _telephone(t);
      final s = _Serveur();
      final base = ProductPager(s.chercher, 'DOLI', mode: SearchMode.commencePar);
      await base.loadMore();
      s.delai = const Duration(seconds: 2);
      await ouvrir(t, base.items, q: 'DOLI', pager: base);
      await t.enterText(_filtre, 'DOLI PRODUIT 04');
      await t.pump();
      expect(find.text('DOLI PRODUIT 004'), findsOneWidget, reason: 'filtre local (mot par mot) des produits déjà chargés');
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('liste-produits-recherche')), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      await t.pump();
      expect(find.byKey(const ValueKey('liste-produits-recherche')), findsNothing);
      expect(find.text('Résultats (10 sur 10)'), findsOneWidget);
    });
  });

  // ===========================================================================================================
  group('1. Recherche de la vente → liste (régression 963fcb6 / ca2c7dd)', () {
    testWidgets('« DOLI » tapé : la liste s\'ouvre avec « DOLI » dans le filtre, focus, curseur à la fin ; on continue à taper', (t) async {
      _telephone(t);
      final s = _Serveur();
      final ajoutes = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            VenteProductSearch(
              search: (q) async => const VenteOk([]),
              pageSearch: s.chercher,
              addProduct: (p, q) async {
                ajoutes.add('${p.lgFAMILLEID}×$q');
                return true;
              },
              debounce: const Duration(milliseconds: 10),
            ),
          ]),
        ),
      ));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('vente-recherche')), 'DOLI');
      await t.pump(const Duration(milliseconds: 50));
      await t.pumpAndSettle();
      expect(find.text('Résultats (50 sur 122)'), findsOneWidget);
      expect(_champFiltre(t).controller.text, 'DOLI', reason: 'avant : champ du filtre vide');
      expect(_champFiltre(t).focusNode.hasFocus, isTrue, reason: 'avant : aucun focus');
      expect(_champFiltre(t).controller.selection, const TextSelection.collapsed(offset: 4));
      // On continue à taper : « DOLI PRODUIT 11 » → recherche serveur, le 110 (au-delà des 50 chargés) apparaît.
      await t.enterText(_filtre, 'DOLI PRODUIT 11');
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(s.requetes.last, 'DOLI PRODUIT 11');
      await t.tap(find.text('DOLI PRODUIT 110'));
      await t.pumpAndSettle();
      expect(find.text('DOLI PRODUIT 110 · CIP 35955110', findRichText: true), findsOneWidget, reason: 'fenêtre de quantité');
      await t.tap(find.text('Ajouter'));
      await t.pumpAndSettle();
      expect(ajoutes, ['P110×1']);
    });

    testWidgets('« Contient » : « DOLI 1000 » → les deux DOLIPRANE 1000 restent affichés', (t) async {
      _telephone(t);
      SearchModePrefs.mode.value = SearchMode.contient;
      addTearDown(() => SearchModePrefs.mode.value = SearchMode.commencePar);
      final s = _Serveur();
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            VenteProductSearch(
              search: (q) async => const VenteOk([]),
              pageSearch: s.chercher,
              addProduct: (p, q) async => true,
              debounce: const Duration(milliseconds: 10),
            ),
          ]),
        ),
      ));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('vente-recherche')), 'DOLI 1000');
      await t.pump(const Duration(milliseconds: 50));
      await t.pumpAndSettle();
      expect(s.requetes, ['%DOLI%1000']);
      expect(find.text('Résultats (2 sur 2)'), findsOneWidget);
      expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
      expect(find.text('DOLIPRANE 1000MG EFF B/8'), findsOneWidget);
      expect(find.text('Aucun produit dans cette liste'), findsNothing);
    });
  });

  // ===========================================================================================================
  group('2. Fenêtre de quantité : nom et CIP', () {
    testWidgets('« NOM · CIP xxxx » : 15 px semi-gras, CIP gris plus petit, 2 lignes au plus ; pastilles prix et stock seulement', (t) async {
      _telephone(t);
      final p = _p('X', 'PRODUIT FICTIF AU NOM TRES TRES LONG POUR VOIR LA COUPURE SUR DEUX LIGNES 1000MG CPR B/30', '3400930099999');
      await t.pumpWidget(MaterialApp(home: Scaffold(body: QuantityDialog(product: p))));
      await t.pump();
      final rich = t.widget<RichText>(find.descendant(of: find.byKey(const ValueKey('quantite-nom-cip')), matching: find.byType(RichText)));
      expect(rich.maxLines, 2);
      expect(rich.overflow, TextOverflow.ellipsis);
      final racine = rich.text as TextSpan;
      expect(racine.style!.fontSize, 15);
      expect(racine.style!.fontWeight, FontWeight.w600);
      expect(racine.toPlainText(), '${p.strNAME} · CIP 3400930099999');
      final cip = (racine.children!.first as TextSpan).children!.last as TextSpan;
      expect(cip.text, ' · CIP 3400930099999');
      expect(cip.style!.fontSize, lessThan(15));
      expect(cip.style!.color, isNot(racine.style!.color));
      expect(find.textContaining('Prix unitaire'), findsOneWidget);
      expect(find.textContaining('Stock'), findsOneWidget);
      expect(find.text('CIP 3400930099999', findRichText: true), findsNothing, reason: 'plus de pastille CIP');
      final hauteur = t.getSize(find.byKey(const ValueKey('quantite-nom-cip'))).height;
      expect(hauteur, lessThanOrEqualTo(2 * 15 * 1.25 + 1), reason: 'deux lignes au plus');
    });
  });

  // ===========================================================================================================
  group('3. Imprimante intégrée Sunmi (canal simulé, connexion en retard)', () {
    late _SunmiLent sunmi;
    setUp(() {
      ImprimanteSunmi.reinitialiser(avec: () async => true, pas: const Duration(milliseconds: 50));
      LargeurTicket.reinitialiser();
    });
    tearDown(() {
      sunmi.retirer();
      ImprimanteSunmi.reinitialiser();
      LargeurTicket.reinitialiser();
    });

    test('premier ticket juste après le lancement : attend la connexion réelle, imprimé, aucune commande perdue', () async {
      sunmi = _SunmiLent()..installer();
      ImprimanteSunmi.lierAuDemarrage();
      final echec = await ImpressionTicket.imprimerSunmi([_image()]);
      expect(echec, isNull);
      expect(sunmi.perdues, isEmpty, reason: 'avant 5.1.0 : commandes envoyées avant onServiceConnected');
      expect(sunmi.appels, contains('RAW_DATA'));
      expect(sunmi.appels.first, 'BIND_PRINTER_SERVICE');
      expect(sunmi.appels.where((a) => a == 'BIND_PRINTER_SERVICE'), hasLength(1), reason: 'liaison demandée une fois');
      expect(LargeurTicket.integreeConnue, 58);
      // Réimprimer : immédiat (service connecté), largeur mémorisée.
      final n = sunmi.appels.length;
      expect(await ImpressionTicket.imprimerSunmi([_image()]), isNull);
      expect(sunmi.appels.skip(n).where((a) => a == 'PAPER_SIZE'), isEmpty);
      expect(sunmi.perdues, isEmpty);
    });

    test('service pas encore connecté au bout du délai : motif clair, largeur NON mémorisée ; Réimprimer imprime ensuite', () async {
      sunmi = _SunmiLent(jamais: true, connexion: Duration.zero)..installer();
      ImprimanteSunmi.reinitialiser(avec: () async => true, pas: const Duration(milliseconds: 20), delai: const Duration(milliseconds: 200));
      final echec = await ImpressionTicket.imprimerSunmi([_image()]);
      expect(echec, ImprimanteSunmi.motifNonConnectee);
      expect(sunmi.appels, isNot(contains('RAW_DATA')));
      expect(await LargeurTicket.integree(), isNull);
      expect(LargeurTicket.integreeConnue, isNull);
      // Le service se connecte : « Réimprimer » réussit (avant : « aucune imprimante intégrée » pour toute la session).
      sunmi.jamais = false;
      expect(await ImpressionTicket.imprimerSunmi([_image()]), isNull);
      expect(await LargeurTicket.integree(), 58);
      expect(sunmi.perdues, isEmpty);
    });

    test('ticket du gabarit local et borne : même attente de la connexion avant les commandes', () async {
      sunmi = _SunmiLent()..installer();
      final ok = await ReceiptService().printBorneTicket(
          officine: 'Pharmacie Fictive', numero: '12', reference: 'REF-FICT-1', lignes: const ['PRODUIT FICTIF x1'], pied: const ['Merci'], codeType: 'QR_CODE');
      expect(ok, isTrue);
      expect(sunmi.perdues, isEmpty);
      expect(sunmi.appels, contains('PRINT_TEXT'));
    });

    test('autre appareil (tablette, téléphone) : aucune attente, aucune lecture de version, comportement d\'avant', () async {
      sunmi = _SunmiLent()..installer();
      ImprimanteSunmi.reinitialiser(avec: () async => false);
      final debut = DateTime.now();
      final echec = await ImpressionTicket.imprimerSunmi([_image()]);
      expect(DateTime.now().difference(debut), lessThan(const Duration(milliseconds: 300)));
      expect(echec, 'aucune imprimante intégrée sur cet appareil.');
      expect(sunmi.appels, ['BIND_PRINTER_SERVICE', 'GET_UPDATE_PRINTER']);
      expect(await ImprimanteSunmi.pret(), isTrue, reason: 'réponse de BIND, comme avant');
      ImprimanteSunmi.lierAuDemarrage();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ImprimanteSunmi.liaisonDemandee, isFalse, reason: 'aucune liaison au démarrage hors Sunmi');
    });

    test('sans canal (tests, web) : jamais d\'exception', () async {
      sunmi = _SunmiLent()..installer();
      sunmi.retirer();
      ImprimanteSunmi.reinitialiser(avec: () async => true, pas: const Duration(milliseconds: 10), delai: const Duration(milliseconds: 50));
      expect(await ImprimanteSunmi.version(), isNull);
      expect(await ImprimanteSunmi.attendreConnexion(), isFalse);
    });
  });

  // ===========================================================================================================
  group('4. « Préparation du ticket… » pendant la lecture de l\'image du serveur', () {
    testWidgets('affiché après 300 ms d\'attente, retiré à la réponse ; réponse rapide : rien ne clignote', (t) async {
      ImpressionTicket.reinitialiser();
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }))));
      final lent = Completer<int>();
      final f = ImpressionTicket.avecPreparation(ctx, () => lent.future);
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text(ImpressionTicket.textePreparation), findsNothing);
      await t.pump(const Duration(milliseconds: 150));
      expect(find.text('Préparation du ticket…'), findsOneWidget);
      lent.complete(7);
      expect(await f, 7);
      await t.pump();
      expect(find.text('Préparation du ticket…'), findsNothing);

      final rapide = ImpressionTicket.avecPreparation(ctx, () async => 1);
      await t.pump(const Duration(milliseconds: 50));
      expect(await rapide, 1);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Préparation du ticket…'), findsNothing);

      // Erreur : indicateur retiré aussi.
      final err = Completer<int>();
      final fe = ImpressionTicket.avecPreparation(ctx, () => err.future);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Préparation du ticket…'), findsOneWidget);
      err.completeError(StateError('réseau'));
      await expectLater(fe, throwsStateError);
      await t.pump();
      expect(find.text('Préparation du ticket…'), findsNothing);
    });

    testWidgets('ticket de vente : indicateur pendant GET v1/vente/ticket/vno/{id}/image (serveur lent), puis impression', (t) async {
      ImpressionTicket.reinitialiser();
      TicketServeur.oublier();
      addTearDown(ImpressionTicket.reinitialiser);
      final dio = Dio(BaseOptions(baseUrl: 'http://serveur-fictif/prestige/api/v1'))..httpClientAdapter = _ImageLente();
      ImpressionTicket.dioDe = (_) => dio;
      final imprimes = <int>[];
      ImpressionTicket.imprimeur = (tickets) async {
        imprimes.add(tickets.length);
        return null;
      };
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }))));
      bool? fait;
      ImpressionTicket.parServeur(ctx, type: TypeTicketServeur.vno, venteId: 'V-FICT', largeur: 58, apercu: false).then((v) => fait = v);
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Préparation du ticket…'), findsNothing);
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Préparation du ticket…'), findsOneWidget, reason: 'le serveur dessine le ticket');
      for (var i = 0; i < 30 && fait == null; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(fait, isTrue);
      expect(imprimes, [1]);
      expect(find.text('Préparation du ticket…'), findsNothing);
    });
  });

  // ===========================================================================================================
  group('5. Taux des organismes plafonnés à 100 % (comme le web)', () {
    test('règle du serveur (CreditLigne.tauxAffiches)', () {
      expect(tauxAffiches([80, 30]), [80, 20]);
      expect(tauxAffiches([70, 30]), [70, 30]);
      expect(tauxAffiches([50, 30]), [50, 30]);
      expect(tauxAffiches([100, 30]), [100, 0]);
      expect(tauxAffiches([60, 30, 20]), [60, 30, 10]);
      expect(tauxAffiches([70, 29]), [70, 30], reason: 'dernier à 1 ou 2 points de 100 % : le reste exact');
      expect(tauxAffiches([80]), [80]);
      expect(tauxAffiches([-5, 50]), [0, 50]);
      expect(tauxAffiches([]), isEmpty);
    });

    test('ticket local d\'assurance : « [80%] » et « [20%] », jamais « [30%] » ; parts inchangées', () {
      final t = ReceiptService.ticketVenteAssurance(
        papier: 80,
        officine: officineTicket,
        saleSummary: AssuranceSaleSummary(
          montant: 10000,
          montantTp: 10000,
          montantNet: 0,
          tierspayants: [
            TiersPayantSummary(numBon: 'BON-FICT-1', taux: 80, compteTp: 'CT1', tpnet: 8000),
            TiersPayantSummary(numBon: 'BON-FICT-2', taux: 30, compteTp: 'CT2', tpnet: 2000),
          ],
          reference: 'REF-FICT',
          venteId: 'V-FICT-A',
        ),
        items: lignesTicket,
        client: clientTicket,
        ayantDroit: ayantDroitTicket,
        paymentMethod: PaymentMethod(id: '1', name: 'ESPECES'),
        currentUser: vendeurTicket,
        reference: 'REF-FICT',
        title: 'VENTE ASSURANCE',
        date: dateFictive,
      );
      final texte = t.imprimees.join('\n');
      expect(texte, contains('[80%]'));
      expect(texte, contains('[20%]'));
      expect(texte, isNot(contains('[30%]')));
      expect(texte, contains('8 000'));
      expect(texte, contains('2 000'));
    });
  });

  // ===========================================================================================================
  group('6. Analyse article : clic sans attendre le lot de la saisie', () {
    final doli = ProductSearchResult.fromJson(catalogueAnalyse[0]);
    test('lot lent (jamais arrivé) : le détail répond DÈS la réponse du CIP exact', () async {
      final c = FicheInfoCache();
      final lot = Completer<List<ArticleAnalysis>>(); // lot de 30 produits, très lent
      c.chargerSaisie('S', 'doli', (_) => lot.future);
      final cip = Completer<ArticleAnalysis?>();
      var arrive = false;
      final f = c.charger('S|F1|3595583', (_) => cip.future, produit: doli).then((a) {
        arrive = true;
        return a;
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(arrive, isFalse);
      cip.complete(ArticleAnalysis.fromJson(infoAnalyseSearch('3595583').last));
      final a = await f;
      expect(arrive, isTrue, reason: 'avant 5.1.0 : attendait la fin du lot');
      expect(a!.emplacement, 'RAYON F-DOLI');
      expect(lot.isCompleted, isFalse);
      expect(c.requetes, 1);
    });

    test('lot seulement pour une liste de 5 produits au plus (30 avant)', () {
      expect(produitsMaxLot, 5);
    });
  });
}

/// Route image lente (900 ms) : un ticket PNG fictif.
class _ImageLente implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return ResponseBody.fromString(
      '{"success":true,"largeur":58,"tickets":[{"modele":"VENTE","png":"${base64Png()}","largeurPoints":384,"hauteurPoints":40}]}',
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  static String base64Png() => base64.encode(RemisesFictives.pngFictif(384, 40));

  @override
  void close({bool force = false}) {}
}
