// Retours du client sur l'APK (accueil, nouvelle version) :
// - scan : EAN-13 / DataMatrix avec et sans séparateur GS (codes du serveur de test) → fiche produit,
//   échec explicite (« Code lu … — Aucun produit avec ce code » + Rechercher par nom), douchette Sunmi
//   (saisie clavier + Entrée) sur l'accueil et dans la recherche, UPC-A, libellé explicite de l'onglet ;
// - en-tête : Prénom Nom sans le rôle, sur la même ligne que l'état du serveur (A / B / C, 360 px) ;
// - Caisse dans la famille Ventes, favoris et organisation enregistrés conservés ;
// - cloche de notifications (pastille, liste, action) à la place de « À faire maintenant » ;
// - choix de la présentation (thème) réservé à l'administrateur (en-tête et Réglages › Apparence) ;
// - fiche produit immédiate puis complément en arrière-plan (squelettes, cache court, abandon), image prioritaire.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/api/models/licence_model.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_info.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/images/produit_images.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/bl_control/bl_list_screen.dart';
import 'package:prestige_vente_app/screens/common/camera_scan_screen.dart';
import 'package:prestige_vente_app/services/datamatrix_parser.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _gs = '\u001d';

// Produits réels du serveur de test (laborex) : CIP local, EAN-13 de la boîte.
ProductSearchResult _prod(String id, String nom, String cip, {int prix = 2080, int stock = 1}) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: nom, intCIP: cip, intPRICE: prix, intNUMBERAVAILABLE: stock, strLIBELLEE: 'SIROPS', intPAF: 0);
final _helicidine = _prod('16819534304091710993', 'HELICIDINE 10% SS EDULCORE SPF/125ML', '2238556'); // EAN 3400922385563
final _ultralevure = _prod('F-ULTRA', 'ULTRALEVURE 250 SACH B/10', '2010273', prix: 4350, stock: 6); // EAN 3583315558079
final _novavinc = _prod('F-NOVA', 'NOVAVINCC 2,5G/5ML IM/IV INJ AMP/5ML B/5', '8735439'); // EAN 3990000017153 (2 produits)
final _novavincDet = _prod('F-NOVA-D', 'NOVAVINCC 2,5G/5ML IM/IV INJ AMP/5ML B/5 DET', '8735439D');

/// Recherche comme /vente/search du serveur de test : CIP (commence par) ou EAN-13 exact.
class _Api extends ApiService {
  _Api() : super(baseUrl: 'http://localhost');
  final requetes = <String>[];
  bool taches = true;
  Duration delaiInfo = Duration.zero;
  int infos = 0;

  static final _ean = {
    '3400922385563': [_helicidine],
    '3583315558079': [_ultralevure],
    '3990000017153': [_novavinc, _novavincDet],
  };

  @override
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    requetes.add(query);
    final parEan = _ean[query];
    if (parEan != null) return ProductPage(parEan, parEan.length);
    final parCip = [_helicidine, _ultralevure, _novavinc, _novavincDet].where((p) => query.isNotEmpty && p.intCIP.startsWith(query)).toList();
    if (parCip.isNotEmpty) return ProductPage(parCip, parCip.length);
    if (query.toLowerCase().startsWith('heli')) return ProductPage([_helicidine], 1);
    return const ProductPage([], 0);
  }

  @override
  Future<ProductInfo?> getProductInfo(String codeCip) async {
    infos++;
    if (delaiInfo > Duration.zero) await Future<void>.delayed(delaiInfo);
    return ProductInfo(
        codeCip: codeCip, emplacement: 'SIROPS ET GOUTTES BUVABLES', grossiste: 'LABOREX-CI YOP', libelle: '', moyenne: 0, prixAchat: 0, prixVente: 0, produitId: '', stock: 1);
  }

  @override
  Future<Officine?> fetchOfficineInfo() async => Officine(fullName: 'KONAN KOU', nomComplet: 'PHARMACIE LES PALMIERS');

  @override
  Future<List<PreventeListItem>> getPreventes() async => taches
      ? [
          for (var i = 0; i < 3; i++)
            PreventeListItem(
                lgPREENREGISTREMENTID: 'p$i', heure: '09:1$i:00', dtUPDATED: '10/10/2026', intPRICE: 1000, strREF: 'PV-$i', userFullName: 'Koffi', lgTYPEVENTEID: '1'),
        ]
      : [];

  @override
  Future<List<BonLivraison>> getBonsLivraison({String query = '', String? dtStart, String? dtEnd}) async => taches
      ? [
          BonLivraison(id: 'b1', ref: 'BL1', grossiste: 'LABOREX', date: '', nbreLignes: 3, montantTotal: 0, statutTraitement: 'EN_COURS', strStatut: ''),
          BonLivraison(id: 'b2', ref: 'BL2', grossiste: 'COPHARMED', date: '', nbreLignes: 3, montantTotal: 0, statutTraitement: 'A_FAIRE', strStatut: ''),
        ]
      : [];
}

class _Licence extends LicenceProvider {
  _Licence(super.api, {this.days = 200});
  final int days;
  @override
  LicenceStatus get status => LicenceStatus.valid;
  @override
  LicenceModel? get licence => LicenceModel(id: '1', dateStart: '', dateEnd: '', typeLicence: '');
  @override
  int get remainingDays => days;
  @override
  Future<bool> mustBlockAccess() async => false;
  @override
  void checkReminders(BuildContext context) {}
}

class _Auth extends AuthProvider {
  _Auth(super.api, {this.admin = false, this.prenom = 'Awa', this.nom = 'Kouassi'});
  final bool admin;
  final String prenom;
  final String nom;
  @override
  User? get user => User(userId: 'U1', login: admin ? 'admin' : 'awa', firstName: prenom, lastName: nom, officineName: 'TEST');
  @override
  bool get isAdmin => admin;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Future<_Api> _accueil(
  WidgetTester tester, {
  ListPresentation style = ListPresentation.dashboard,
  Future<String?> Function(BuildContext)? scanner,
  bool admin = false,
  String prenom = 'Awa',
  String nom = 'Kouassi',
  bool taches = true,
  int licence = 200,
  SettingsProvider? settings,
}) async {
  final api = _Api()..taches = taches;
  final s = settings ?? SettingsProvider();
  if (settings == null) await s.saveMenuConfig(const [], const []);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: s),
      Provider<ApiService>.value(value: api),
      ChangeNotifierProvider<LicenceProvider>.value(value: _Licence(api, days: licence)),
      ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(api, admin: admin, prenom: prenom, nom: nom)),
      ChangeNotifierProvider(create: (_) => SaleProvider(api)),
      ChangeNotifierProvider(create: (_) => BlControlProvider(api)),
    ],
    child: MaterialApp(home: AccueilScreen(presentation: style, serverCheck: () async => true, scanner: scanner)),
  ));
  await tester.pumpAndSettle();
  return api;
}

/// Douchette Sunmi : chaque caractère arrive comme une touche, puis Entrée.
Future<void> _douchette(WidgetTester tester, String code) async {
  for (final ch in code.split('')) {
    final key = switch (ch) {
      _ when RegExp(r'\d').hasMatch(ch) => LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + int.parse(ch)),
      _gs => LogicalKeyboardKey.keyG,
      _ => LogicalKeyboardKey.keyA,
    };
    await tester.sendKeyDownEvent(key, character: ch);
    await tester.sendKeyUpEvent(key);
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ---------------------------------------------------------------------------
  // 1 a) Scan
  // ---------------------------------------------------------------------------
  group('Scan : chaînes réelles → codes essayés', () {
    test('EAN-13 de la boîte (34009…) : EAN puis CIP7 français ; autre EAN : tel quel', () {
      expect(ProductLookup.codeCandidates('3400922385563'), ['3400922385563', '2238556']);
      expect(ProductLookup.codeCandidates('3583315558079'), ['3583315558079']);
    });

    test('DataMatrix GS1 avec GS, sans GS, GS en tête, préfixe ]d2, GS visible « ␝ » : GTIN-14 → EAN-13 d\'abord', () {
      for (final dm in [
        '0103400922385563172710311012345${_gs}21XYZ987', // avec GS (FNC1)
        '01034009223855631727103110AB12C', // sans GS
        '${_gs}010340092238556317271031${_gs}10AB12C', // FNC1 en tête
        ']d2010340092238556317271031${_gs}10LOT1', // identifiant de symbologie
        '0103400922385563172710311012345␝21XYZ987', // GS rendu visible par le champ de saisie
      ]) {
        final c = ProductLookup.codeCandidates(dm);
        expect(c.first, '3400922385563', reason: dm);
        expect(c, contains('2238556'), reason: dm);
        expect(ProductLookup.looksLikeCode(dm), isTrue, reason: dm);
      }
      expect(DataMatrixParser.parse('0103583315558079${_gs}17271031${_gs}10LOT1')!.ean13, '3583315558079');
    });

    test('UPC-A (EAN-13 commençant par 0, lu sur 12 chiffres) : EAN-13 complet', () {
      expect(ProductLookup.codeCandidates('012345678905'), contains('0012345678905'));
      expect(CameraScanScreen.valueOf(const Barcode(rawValue: '012345678905', format: BarcodeFormat.upcA)), '0012345678905');
      expect(CameraScanScreen.valueOf(const Barcode(rawValue: '3400922385563', format: BarcodeFormat.ean13)), '3400922385563');
      // Appareil photo de l'accueil : DataMatrix ET codes-barres classiques (dont UPC, Code 39, ITF).
      for (final f in [BarcodeFormat.dataMatrix, BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE, BarcodeFormat.code128, BarcodeFormat.code39, BarcodeFormat.itf]) {
        expect(CameraScanScreen.formatsProduit, contains(f));
      }
    });
  });

  group('Scan (appareil photo) → fiche produit', () {
    final cas = {
      'EAN-13 34009…': '3400922385563',
      'DataMatrix avec GS': '0103400922385563172710311012345${_gs}21XYZ987',
      'DataMatrix sans GS': '01034009223855631727103110AB12C',
      'DataMatrix FNC1 en tête': '${_gs}010340092238556317271031${_gs}10AB12C',
    };
    cas.forEach((nom, code) {
      testWidgets('$nom : la fiche HELICIDINE s\'ouvre directement', (tester) async {
        _phone(tester);
        await _accueil(tester, scanner: (_) async => code);
        await tester.tap(find.text('Scanner').last);
        await tester.pumpAndSettle();
        expect(find.byType(FicheProduitScreen), findsOneWidget);
        expect(find.text('HELICIDINE 10% SS EDULCORE SPF/125ML'), findsOneWidget);
        expect(find.text('2238556'), findsOneWidget);
        expect(find.text('SIROPS ET GOUTTES BUVABLES'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('EAN non 34009 (ULTRALEVURE) : fiche directe', (tester) async {
      _phone(tester);
      await _accueil(tester, scanner: (_) async => '3583315558079');
      await tester.tap(find.text('Scanner').last);
      await tester.pumpAndSettle();
      expect(find.byType(FicheProduitScreen), findsOneWidget);
      expect(find.text('ULTRALEVURE 250 SACH B/10'), findsOneWidget);
    });

    testWidgets('EAN partagé (boîte + détail) : la liste des 2 produits, au choix', (tester) async {
      _phone(tester);
      await _accueil(tester, scanner: (_) async => '3990000017153');
      await tester.tap(find.text('Scanner').last);
      await tester.pumpAndSettle();
      expect(find.byType(FicheProduitScreen), findsNothing);
      expect(find.text('2 produits pour ce code : choisissez le bon.'), findsOneWidget);
      await tester.tap(find.text('NOVAVINCC 2,5G/5ML IM/IV INJ AMP/5ML B/5 DET'));
      await tester.pumpAndSettle();
      expect(find.byType(FicheProduitScreen), findsOneWidget);
    });

    testWidgets('code inconnu : code lu, « Aucun produit avec ce code », Rechercher par nom', (tester) async {
      _phone(tester);
      await _accueil(tester, scanner: (_) async => '0103400930000120172710311012345${_gs}21SN1');
      await tester.tap(find.text('Scanner').last);
      await tester.pumpAndSettle();
      expect(find.byType(FicheProduitScreen), findsNothing);
      expect(find.byKey(const ValueKey('code-introuvable')), findsOneWidget);
      expect(find.text('Aucun produit avec ce code'), findsOneWidget);
      expect(find.text('Code lu : 0103400930000120172710311012345␝21SN1'), findsOneWidget);
      expect(find.textContaining('3400930000120'), findsWidgets); // codes essayés
      expect(find.text('Scanner à nouveau'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('rechercher-par-nom')));
      await tester.pumpAndSettle();
      final champ = tester.widget<TextField>(find.byType(TextField));
      expect(champ.controller!.text, isEmpty);
      expect(champ.focusNode!.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField), 'heli');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('HELICIDINE 10% SS EDULCORE SPF/125ML'), findsOneWidget);
    });

    testWidgets('onglet « Scanner » : libellé explicite (infobulle)', (tester) async {
      _phone(tester);
      await _accueil(tester);
      expect(find.byTooltip('Scanner un produit — Code-barres ou DataMatrix → fiche produit'), findsWidgets);
    });
  });

  group('Douchette Sunmi (saisie clavier + Entrée)', () {
    testWidgets('sur l\'accueil (aucun champ) : EAN-13 → fiche', (tester) async {
      _phone(tester);
      await _accueil(tester);
      await _douchette(tester, '3400922385563');
      expect(find.byType(FicheProduitScreen), findsOneWidget);
      expect(find.text('HELICIDINE 10% SS EDULCORE SPF/125ML'), findsOneWidget);
    });

    testWidgets('sur l\'accueil : DataMatrix avec GS → fiche', (tester) async {
      _phone(tester);
      await _accueil(tester);
      await _douchette(tester, '0103583315558079172710311012345${_gs}21XYZ9');
      expect(find.byType(FicheProduitScreen), findsOneWidget);
      expect(find.text('ULTRALEVURE 250 SACH B/10'), findsOneWidget);
    });

    testWidgets('dans la recherche : code tapé + Entrée → fiche directe ; GS gardé visible « ␝ »', (tester) async {
      _phone(tester);
      await _accueil(tester);
      await tester.tap(find.text('Rechercher un menu ou un produit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '01034009223855631727103110AB12C${_gs}21SERIE');
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '01034009223855631727103110AB12C␝21SERIE');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.byType(FicheProduitScreen), findsOneWidget);
      expect(find.text('HELICIDINE 10% SS EDULCORE SPF/125ML'), findsOneWidget);
    });

    testWidgets('code inconnu puis Entrée : code relu tel quel (GS jamais remplacé par un espace)', (tester) async {
      _phone(tester);
      final api = await _accueil(tester, scanner: (_) async => '0103400930000120172710311012345${_gs}21SN1');
      await tester.tap(find.text('Scanner').last);
      await tester.pumpAndSettle();
      final avant = api.requetes.length;
      expect(avant, greaterThan(0));
      await tester.showKeyboard(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(api.requetes.length, greaterThan(avant));
      expect(api.requetes.where((q) => q.contains(' ')), isEmpty);
      expect(api.requetes.skip(avant).first, '3400930000120'); // DataMatrix relu : EAN-13 d'abord
      expect(find.byKey(const ValueKey('code-introuvable')), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // 1 b) En-tête : Prénom Nom, sans rôle, sur la ligne de l'état du serveur
  // ---------------------------------------------------------------------------
  group('En-tête', () {
    for (final style in ListPresentation.values) {
      testWidgets('${style.label} : Prénom Nom sans rôle, même ligne que l\'état du serveur, 360 px', (tester) async {
        _phone(tester);
        await _accueil(tester, style: style, licence: 21);
        expect(find.textContaining('Utilisateur'), findsNothing);
        expect(find.textContaining('Administrateur'), findsNothing);
        final nom = find.byKey(const ValueKey('accueil-utilisateur'));
        expect(tester.widget<Text>(nom).data, 'Awa Kouassi');
        final etat = find.textContaining(RegExp('Serveur connecté|En ligne'));
        expect((tester.getCenter(nom).dy - tester.getCenter(etat).dy).abs(), lessThan(4), reason: 'même ligne');
        expect(tester.getTopRight(nom).dx, lessThanOrEqualTo(360));
        expect(find.byKey(const Key('accueil_deconnexion')), findsOneWidget);
        expect(tester.getTopRight(find.byKey(const Key('accueil_deconnexion'))).dx, greaterThan(300));
        expect(find.text('Licence : 21 jour(s)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('${style.label} : nom très long tronqué proprement (…)', (tester) async {
        _phone(tester);
        await _accueil(tester, style: style, prenom: 'Marie-Christine Adjoua', nom: 'KOUAKOU-BROU N\'GUESSAN EPSE YAO');
        final t = tester.widget<Text>(find.byKey(const ValueKey('accueil-utilisateur')));
        expect(t.maxLines, 1);
        expect(t.overflow, TextOverflow.ellipsis);
        expect(tester.getTopRight(find.byKey(const ValueKey('accueil-utilisateur'))).dx, lessThanOrEqualTo(360));
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ---------------------------------------------------------------------------
  // 1 c) Caisse dans Ventes
  // ---------------------------------------------------------------------------
  group('Caisse dans la famille Ventes', () {
    test('catalogue : Caisse rangée dans Ventes, plus de famille Caisse', () {
      expect(accueilMenuById['caisse']!.famille, MenuFamille.ventes);
      expect(MenuFamille.values.map((f) => f.label), isNot(contains('Caisse')));
      final f = menusByFamille(const [], const []);
      expect(f[MenuFamille.ventes]!.map((m) => m.id), containsAllInOrder(['prevente', 'ordonnance', 'caisse']));
    });

    testWidgets('favoris et organisation enregistrés (avant le déplacement) conservés', (tester) async {
      _phone(tester);
      // Organisation enregistrée par l'ancienne version : ordre par familles (Caisse à part), Dépôt masqué,
      // favoris dont la Caisse.
      SharedPreferences.setMockInitialValues({
        AccueilFavoris.key: ['caisse', 'carnet', 'search', 'reception_bl'],
      });
      final settings = SettingsProvider();
      await settings.loadSettings();
      await settings.saveMenuConfig(
          ['carnet', 'prevente', 'assurance', 'depot', 'proforma', 'ordonnance', 'caisse', 'reception_bl', 'retour_frs', 'stock'], ['depot']);
      expect(await AccueilFavoris.load(), ['caisse', 'carnet', 'search', 'reception_bl']);
      final familles = menusByFamille(settings.menuOrder, settings.hiddenMenuIds);
      expect(familles[MenuFamille.ventes]!.map((m) => m.id), ['carnet', 'prevente', 'assurance', 'proforma', 'ordonnance', 'caisse']);

      await _accueil(tester, settings: settings);
      expect(find.text('CAISSE'), findsNothing);
      expect(find.text('VENTES'), findsOneWidget);
      // Favori « Caisse » toujours en tête des favoris.
      expect(find.text('Caisse'), findsWidgets);
      final ventes = tester.getTopLeft(find.text('VENTES')).dy;
      final ys = [for (final e in find.text('Caisse').evaluate()) (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dy];
      expect(ys.where((y) => y < ventes), hasLength(1), reason: 'favori Caisse conservé');
      expect(ys.where((y) => y > ventes), hasLength(1), reason: 'tuile Caisse dans Ventes');
      final ordonnance = tester.getTopLeft(find.text('Ordonnance')).dy;
      expect(ys.last, greaterThanOrEqualTo(ordonnance), reason: 'à la place enregistrée (après Ordonnance)');
      expect(find.text('Dépôt'), findsNothing); // toujours masqué
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // 3) Cloche de notifications
  // ---------------------------------------------------------------------------
  group('Cloche de notifications', () {
    testWidgets('avec des choses à faire : pastille 5, liste, action qui ouvre l\'écran', (tester) async {
      _phone(tester);
      await _accueil(tester);
      expect(find.text('À FAIRE MAINTENANT'), findsNothing);
      final cloche = find.byKey(const Key('accueil_cloche'));
      expect(find.descendant(of: cloche, matching: find.text('5')), findsOneWidget);
      expect(find.byTooltip('Notifications : 5 à faire'), findsOneWidget);
      await tester.tap(cloche);
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('3 prévente(s) à encaisser'), findsOneWidget);
      expect(find.textContaining('La plus ancienne : 09:1'), findsOneWidget);
      expect(find.text('2 BL à pointer'), findsOneWidget);
      expect(find.text('Encaisser'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(TextButton, 'Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.byType(BlListScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sans élément : cloche sans pastille, « Tout est à jour ✓ »', (tester) async {
      _phone(tester);
      await _accueil(tester, taches: false);
      final cloche = find.byKey(const Key('accueil_cloche'));
      expect(tester.widget<Badge>(find.byKey(const Key('accueil_cloche_pastille'))).isLabelVisible, isFalse);
      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
      await tester.tap(cloche);
      await tester.pumpAndSettle();
      expect(find.text('Tout est à jour ✓'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final style in ListPresentation.values) {
      testWidgets('${style.label} : cloche dans l\'en-tête, section retirée de la page', (tester) async {
        _phone(tester);
        await _accueil(tester, style: style);
        expect(find.byKey(const Key('accueil_cloche')), findsOneWidget);
        expect(find.text('À FAIRE MAINTENANT'), findsNothing);
        expect(find.byKey(const ValueKey('accueil-a-faire')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ---------------------------------------------------------------------------
  // 5) Choix du thème (présentation) réservé à l'administrateur
  // ---------------------------------------------------------------------------
  group('Choix de la présentation : administrateur seulement', () {
    testWidgets('non-admin : bouton masqué ; admin : bouton à côté de la cloche', (tester) async {
      _phone(tester);
      await _accueil(tester);
      expect(find.byTooltip('Présentation'), findsNothing);
      expect(find.byType(PresentationMenuButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _accueil(tester, admin: true);
      expect(find.byType(PresentationMenuButton), findsOneWidget);
      final p = tester.getCenter(find.byType(PresentationMenuButton));
      final c = tester.getCenter(find.byKey(const Key('accueil_cloche')));
      expect((p.dy - c.dy).abs(), lessThan(2));
      expect(c.dx, greaterThan(p.dx));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Réglages › Apparence : choix masqué pour un non-admin, présent pour l\'admin', (tester) async {
      _phone(tester);
      Future<void> page(bool admin) async {
        await tester.pumpWidget(MaterialApp(
            home: ApparencePage(initial: ListPresentation.compact, openOrganiser: (_) async {}, choixPresentation: admin)));
        await tester.pumpAndSettle();
      }

      await page(false);
      expect(find.byKey(const Key('presentation_dashboard')), findsNothing);
      expect(find.byKey(const Key('presentation_reservee')), findsOneWidget);
      expect(find.text('Choix réservé au compte administrateur.'), findsOneWidget);
      expect(find.text('Organiser l\'accueil'), findsOneWidget); // le reste de la rubrique est inchangé
      await page(true);
      expect(find.byKey(const Key('presentation_dashboard')), findsOneWidget);
      expect(find.byKey(const Key('presentation_reservee')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // 4) Fiche produit : immédiate, complément en arrière-plan
  // ---------------------------------------------------------------------------
  group('Fiche produit immédiate', () {
    ProductInfo info(String cip) => ProductInfo(
        codeCip: cip, emplacement: 'RAYON B2', grossiste: 'LABOREX', libelle: '', moyenne: 0, prixAchat: 0, prixVente: 0, produitId: '', stock: 1);

    testWidgets('données de la ligne tout de suite, squelettes, puis détails ; réouverture sans attente', (tester) async {
      _phone(tester);
      final cache = FicheInfoCache();
      var appels = 0;
      Future<ProductInfo?> lent(String cip) async {
        appels++;
        await Future<void>.delayed(const Duration(milliseconds: 800));
        return info(cip);
      }

      // Avant : la fiche attendait GET /info (barre de progression) et le redemandait à chaque ouverture.
      // Après : 1ʳᵉ image = nom, CIP, prix, stock + squelettes ; détails à la réponse ; réouverture : 0 ms, 0 requête.
      await tester.pumpWidget(MaterialApp(home: FicheProduitScreen(produit: _helicidine, loadInfo: lent, cache: cache)));
      expect(find.text('HELICIDINE 10% SS EDULCORE SPF/125ML'), findsOneWidget);
      expect(find.text('2238556'), findsOneWidget);
      expect(find.text('${Constants.formatNumber(2080)} F'), findsOneWidget);
      expect(find.text('1'), findsOneWidget); // stock
      expect(find.byKey(const ValueKey('fiche-squelette-Emplacement')), findsOneWidget);
      expect(find.byKey(const ValueKey('fiche-squelette-Grossiste')), findsOneWidget);
      expect(find.text('RAYON B2'), findsNothing);
      await tester.pump(const Duration(milliseconds: 799));
      expect(find.text('RAYON B2'), findsNothing);
      await tester.pump(const Duration(milliseconds: 2));
      expect(find.text('RAYON B2'), findsOneWidget);
      expect(find.byKey(const ValueKey('fiche-squelette-Emplacement')), findsNothing);
      expect(appels, 1);

      // Réouverture (cache 60 s) : détails dès la 1ʳᵉ image, aucune requête.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: FicheProduitScreen(produit: _helicidine, loadInfo: lent, cache: cache)));
      expect(find.text('RAYON B2'), findsOneWidget);
      expect(appels, 1);
      expect(cache.requetes, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fiche quittée avant la réponse : requête abandonnée, aucune erreur', (tester) async {
      _phone(tester);
      final cache = FicheInfoCache();
      final reponse = Completer<ProductInfo?>();
      await tester.pumpWidget(MaterialApp(home: FicheProduitScreen(produit: _helicidine, loadInfo: (_) => reponse.future, cache: cache)));
      await tester.pumpWidget(const SizedBox()); // on quitte
      expect(cache.abandons, 1);
      reponse.complete(info('2238556'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('depuis la recherche : la fiche s\'affiche avant la réponse de GET /info', (tester) async {
      _phone(tester);
      final api = await _accueil(tester);
      api.delaiInfo = const Duration(seconds: 2);
      await tester.tap(find.text('Rechercher un menu ou un produit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'heli');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HELICIDINE 10% SS EDULCORE SPF/125ML'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // transition de page
      expect(find.byType(FicheProduitScreen), findsOneWidget);
      expect(find.text('HELICIDINE 10% SS EDULCORE SPF/125ML'), findsOneWidget);
      expect(find.byKey(const ValueKey('fiche-squelette-Emplacement')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('SIROPS ET GOUTTES BUVABLES'), findsOneWidget);
      expect(api.infos, 1);
      expect(tester.takeException(), isNull);
    });

    test('image de la fiche servie avant les vignettes en attente de la liste (mesure avant/après)', () async {
      final dir = Directory.systemTemp.createTempSync('retours_img');
      addTearDown(() => dir.deleteSync(recursive: true));
      Future<int> rangDeLaFiche({required bool prioritaire}) async {
        final api = _ImgApi();
        final s = ProduitImages(api: api, dossier: () async => dir, concurrence: 3);
        final f = [for (var i = 0; i < 12; i++) s.demander('L$i')]; // vignettes de la liste de résultats
        f.add(s.demander('FICHE', prioritaire: prioritaire));
        await Future.wait(f);
        return api.ordre.indexOf('FICHE');
      }

      final avant = await rangDeLaFiche(prioritaire: false);
      final apres = await rangDeLaFiche(prioritaire: true);
      expect(avant, 12, reason: 'avant : la fiche attendait les 12 vignettes');
      expect(apres, 3, reason: 'après : servie dès la première place libre (3 en cours)');
    });
  });
}

class _ImgApi implements ProduitImagesApi {
  final ordre = <String>[];
  @override
  Future<VenteResult<ImagesListe?>> lister(String familleId) async {
    ordre.add(familleId);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return const VenteOk(ImagesListe([]));
  }

  @override
  Future<VenteResult<Uint8List>> fichier(String familleId, String imageId, {bool vignette = true}) async => VenteOk(Uint8List(0));

  @override
  Future<VenteResult<String>> ajouter(String familleId, Uint8List octets, {String nom = 'photo.jpg', bool principale = true}) async =>
      const VenteFailed('non');
}
