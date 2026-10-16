// 4.4.0 — Menu « Photos produits » : scanner (douchette / appareil photo) ou chercher le produit → photo → aperçu
// → OK : enregistrée (ajout de photo existant, aucune nouvelle route) et produit suivant ; Reprendre / Annuler ;
// photo actuelle signalée ; mêmes droits que l'ajout de photo de la fiche produit. Produits et images FICTIFS.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/droits/droits_modules.dart';
import 'package:prestige_vente_app/images/images_reglages.dart';
import 'package:prestige_vente_app/images/photos_produits_screen.dart';
import 'package:prestige_vente_app/images/produit_images.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

class _Api implements ProduitImagesApi {
  final Map<String, List<String>> images = {};
  bool modifiable = true;
  bool sansRoute = false;
  VenteResult<String>? reponseAjout;
  final ajouts = <(String, int)>[];
  int listes = 0;

  @override
  Future<VenteResult<ImagesListe?>> lister(String familleId) async {
    listes++;
    if (sansRoute) return const VenteOk(null);
    final ids = images[familleId] ?? const [];
    return VenteOk(ImagesListe([for (final (i, id) in ids.indexed) ImageProduitInfo(id: id, principale: i == 0)], modifiable: modifiable));
  }

  @override
  Future<VenteResult<Uint8List>> fichier(String familleId, String imageId, {bool vignette = true}) async =>
      VenteOk(Uint8List.fromList(img.encodeJpg(img.Image(width: 4, height: 4))));

  @override
  Future<VenteResult<String>> ajouter(String familleId, Uint8List octets, {String nom = 'photo.jpg', bool principale = true}) async {
    final r = reponseAjout ?? const VenteOk('IMG-NOUVELLE');
    if (r.isOk) {
      ajouts.add((familleId, octets.length));
      images[familleId] = ['IMG-NOUVELLE'];
    }
    return r;
  }
}

ProductSearchResult _produit(String id, String nom, String cip) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: nom, intCIP: cip, intPRICE: 1000, intNUMBERAVAILABLE: 3, strLIBELLEE: '', intPAF: 700);

final _a = _produit('PF-A', 'PRODUIT FICTIF A 500MG B/16', '9990001');
final _b = _produit('PF-B', 'PRODUIT FICTIF B SIROP 125ML', '9990002');

void main() {
  late _Api api;
  late ProduitImages images;
  late Directory dossier;
  final codesDemandes = <String?>[];
  var captures = 0;
  Uint8List jpeg() => Uint8List.fromList(img.encodeJpg(img.Image(width: 32, height: 32)));

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('photos_produits_test');
    addTearDown(() => dossier.delete(recursive: true));
    api = _Api()..images['PF-B'] = ['IMG-B'];
    images = ProduitImages(api: api, dossier: () async => dossier);
    ImagesReglages.courant.value = const ImagesConfig(); // photoAdmin activé, photoTerminal désactivé (défauts)
    codesDemandes.clear();
    captures = 0;
  });

  Widget ecran({bool admin = true, ProductSearchResult? Function(String? code)? choix}) => MaterialApp(
        home: PhotosProduitsScreen(
          images: images,
          admin: admin,
          choixProduit: (_, {code}) async {
            codesDemandes.add(code);
            return (choix ?? (c) => c == '9990002' ? _b : _a)(code);
          },
          scanner: (_) async => '9990002',
          capturer: (_) async {
            captures++;
            return jpeg();
          },
        ),
      );

  EditableText champ(WidgetTester t) => t.widget<EditableText>(find.descendant(of: find.byKey(const Key('photos_recherche')), matching: find.byType(EditableText)));

  Future<void> douchette(WidgetTester t, String code) async {
    // Douchette Sunmi : saisie clavier puis Entrée dans le champ qui a le curseur.
    t.testTextInput.enterText(code);
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
  }

  test('menu visible avec les mêmes droits que l\'ajout de photo de la fiche produit', () {
    const def = ImagesConfig();
    expect(menuPhotosProduitsVisible(config: def, admin: true), isTrue, reason: 'administrateur, photoAdmin par défaut');
    expect(menuPhotosProduitsVisible(config: def, admin: false), isFalse, reason: 'autre compte sans « photo terminal »');
    expect(menuPhotosProduitsVisible(config: def.copyWith(photoTerminal: true), admin: false), isTrue);
    expect(menuPhotosProduitsVisible(config: def.copyWith(photoAdmin: false), admin: true), isFalse);
    expect(menuPhotosProduitsVisible(config: def.copyWith(actif: false, photoTerminal: true), admin: true), isFalse, reason: 'images désactivées');
    final m = menusSousDroits.firstWhere((m) => m.id == 'photos_produits');
    expect(m.label, 'Photos produits');
    DroitsModules.instance.fixer(adminLocal: true);
    addTearDown(DroitsModules.instance.oublier);
    expect(m.visible, isTrue);
    DroitsModules.instance.fixer(adminLocal: false);
    expect(m.visible, isFalse);
  });

  testWidgets('douchette → produit « Sans photo » → photo → aperçu → OK : enregistrée, produit suivant (curseur prêt)', (t) async {
    t.view.physicalSize = const Size(720, 1440);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(ecran());
    await t.pumpAndSettle();
    expect(champ(t).focusNode.hasFocus, isTrue, reason: 'curseur prêt pour la douchette dès l\'ouverture');
    await douchette(t, '9990001');
    expect(codesDemandes, ['9990001']);
    expect(find.text(_a.strNAME), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('photos_etat')), matching: find.text('Sans photo')), findsOneWidget);
    expect(find.text('Prendre la photo'), findsOneWidget);
    await t.tap(find.byKey(const Key('photos_prendre')));
    await t.pumpAndSettle();
    expect(captures, 1);
    expect(find.byKey(const Key('photos_apercu')), findsOneWidget);
    expect(api.ajouts, isEmpty, reason: 'rien n\'est envoyé avant OK');
    await t.tap(find.byKey(const Key('photos_ok')));
    await t.pumpAndSettle();
    expect(api.ajouts.single.$1, 'PF-A');
    expect(find.textContaining('Photo enregistrée : ${_a.strNAME}. Produit suivant.'), findsOneWidget);
    // Produit suivant : champ vide, curseur prêt, compteur.
    expect(find.byKey(const Key('photos_produit')), findsNothing);
    expect(champ(t).controller.text, '');
    expect(champ(t).focusNode.hasFocus, isTrue);
    expect(find.text('Faits dans cette séance (1)'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 3)); // fin du message
  });

  testWidgets('produit qui a déjà une photo (scan appareil photo) : signalé ; Reprendre relance la capture ; Annuler n\'envoie rien', (t) async {
    t.view.physicalSize = const Size(720, 1440);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(ecran());
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('photos_scanner')));
    await t.pumpAndSettle();
    expect(codesDemandes, ['9990002']);
    expect(find.descendant(of: find.byKey(const Key('photos_etat')), matching: find.text('A déjà une photo')), findsOneWidget);
    expect(find.text('La nouvelle photo remplacera la photo actuelle.'), findsOneWidget);
    await t.tap(find.byKey(const Key('photos_prendre')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('photos_reprendre')));
    await t.pumpAndSettle();
    expect(captures, 2);
    expect(find.byKey(const Key('photos_apercu')), findsOneWidget);
    await t.tap(find.byKey(const Key('photos_annuler')));
    await t.pumpAndSettle();
    expect(api.ajouts, isEmpty);
    expect(find.byKey(const Key('photos_apercu')), findsNothing);
    expect(champ(t).focusNode.hasFocus, isTrue);
  });

  testWidgets('recherche par nom ; sans droit du serveur : bouton désactivé et expliqué ; serveur sans images : expliqué', (t) async {
    t.view.physicalSize = const Size(720, 1440);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    api.modifiable = false;
    await t.pumpWidget(ecran());
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('photos_rechercher')));
    await t.pumpAndSettle();
    expect(codesDemandes, [null], reason: 'recherche ouverte sans code');
    expect(t.widget<ElevatedButton>(find.byKey(const Key('photos_prendre'))).onPressed, isNull);
    expect(find.textContaining('pas le droit de modifier les images'), findsOneWidget);
    await t.tap(find.byKey(const Key('photos_produit_suivant')));
    await t.pumpAndSettle();
    api.sansRoute = true;
    await douchette(t, '9990001');
    expect(find.text('Ce serveur ne gère pas les images des produits.'), findsOneWidget);
    expect(t.widget<ElevatedButton>(find.byKey(const Key('photos_prendre'))).onPressed, isNull);
  });

  testWidgets('envoi refusé : message, aperçu gardé, « Réessayer l\'envoi » ; réglages : refus sans droit (autre compte)', (t) async {
    t.view.physicalSize = const Size(720, 1440);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    api.reponseAjout = const VenteFailed('Serveur injoignable : photo non envoyée.');
    await t.pumpWidget(ecran());
    await t.pumpAndSettle();
    await douchette(t, '9990001');
    await t.tap(find.byKey(const Key('photos_prendre')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('photos_ok')));
    await t.pumpAndSettle();
    expect(find.text('Serveur injoignable : photo non envoyée.'), findsOneWidget);
    expect(find.byKey(const Key('photos_apercu')), findsOneWidget);
    expect(find.text('Réessayer l\'envoi'), findsOneWidget);
    api.reponseAjout = null;
    await t.tap(find.byKey(const Key('photos_ok')));
    await t.pumpAndSettle();
    expect(api.ajouts, hasLength(1));
    // Autre compte (pas administrateur, « photo terminal » désactivé) : ajout refusé comme dans la fiche produit.
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(ecran(admin: false));
    await t.pumpAndSettle();
    await douchette(t, '9990001');
    await t.tap(find.byKey(const Key('photos_prendre')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('photos_ok')));
    await t.pumpAndSettle();
    expect(find.text('Ajout de photo désactivé (Réglages).'), findsOneWidget);
    expect(api.ajouts, hasLength(1));
    await t.pump(const Duration(seconds: 3));
  });

  for (final (nom, taille, echelle) in [('Sunmi V2s', const Size(720, 1440), 1.0), ('téléphone 360×640', const Size(720, 1280), 1.3), ('tablette', const Size(1920, 1200), 1.0)]) {
    testWidgets('ergonomie $nom, texte ×$echelle : sans débordement, boutons ≥ 48 dp', (t) async {
      t.view.physicalSize = taille;
      t.view.devicePixelRatio = taille.width > 1000 ? 1.5 : 2;
      addTearDown(t.view.reset);
      t.platformDispatcher.textScaleFactorTestValue = echelle;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpWidget(ecran());
      await t.pumpAndSettle();
      await douchette(t, '9990002');
      await t.ensureVisible(find.byKey(const Key('photos_prendre')));
      await t.pumpAndSettle();
      expect(t.getSize(find.byKey(const Key('photos_prendre'))).height, greaterThanOrEqualTo(48));
      await t.tap(find.byKey(const Key('photos_prendre')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('photos_ok')));
      for (final k in ['photos_ok', 'photos_reprendre', 'photos_annuler']) {
        expect(t.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(48), reason: k);
      }
      expect(t.takeException(), isNull);
    });
  }
}
