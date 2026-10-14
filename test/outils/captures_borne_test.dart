// Captures PNG RÉELLES (rendu Flutter de l'application) de la borne libre-service (« vente discrète »),
// pour présentation au pharmacien : docs/maquettes/captures_borne/*.png.
// Données fictives (pharmacie ivoirienne, prix en F CFA) ; quelques produits ont une photo (boîtes
// dessinées ici), les autres gardent le pictogramme de leur forme. Aucun code de lib/ n'est modifié :
// l'écran BorneScreen est rendu tel quel avec un faux serveur en mémoire.
// Hors de la suite de la CI (dossier test/outils/, ignoré sans la variable APERCUS). Pour régénérer :
//   APERCUS=1 flutter test test/outils/captures_borne_test.dart --update-goldens
// Tailles en pixels physiques : tablette 1920×1200 (densité 1,5 → 1280×800 logiques), tablette portrait
// 1200×1920, terminal Sunmi V2s 720×1440 (densité 2 → 360×720).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_kiosque.dart';
import 'package:prestige_vente_app/borne/borne_produit.dart';
import 'package:prestige_vente_app/borne/borne_reglages_page.dart';
import 'package:prestige_vente_app/borne/borne_screen.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/horsligne/horsligne_ui.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _actif = Platform.environment.containsKey('APERCUS');
const _repli = 'DejaVuSans';

/// Thème de l'application (main.dart), avec une police de repli pour les signes absents de la Roboto des tests.
ThemeData get _theme {
  final t = AppTheme.lightTheme;
  return t.copyWith(textTheme: t.textTheme.apply(fontFamilyFallback: const [_repli]));
}

const _dossier = '../../docs/maquettes/captures_borne';
const _officine = 'PHARMACIE DES PALMIERS · COCODY';

// Écrans (taille physique, densité).
const _paysage = (Size(1920, 1200), 1.5);
const _portrait = (Size(1200, 1920), 1.5);
const _sunmi = (Size(720, 1440), 2.0);

ProductSearchResult _p(String id, String nom, String cip, int prix, int stock) =>
    ProductSearchResult(lgFAMILLEID: id, strNAME: nom, intCIP: cip, intPRICE: prix, intNUMBERAVAILABLE: stock, strLIBELLEE: '', intPAF: 0);

/// Catalogue fictif.
Map<String, ProductSearchResult> _catalogue() => {
      for (final p in [
        _p('P1', 'DOLIPRANE 1000MG CP B/8', '3595583', 1500, 40),
        _p('P2', 'DOLIPRANE 500MG CP B/16', '3595590', 1200, 25),
        _p('P3', 'DOLIPRANE 2,4% SUSP BUV FL/100ML', '3400001', 2100, 6),
        _p('P4', 'DOLIMEX 1G CPR EFFV B/8', '8452285', 1100, 0),
        _p('P5', 'DOLIKIDS 150MG SUPPO B/10', '3400215', 1350, 9),
        _p('P6', 'DOLIRHUME PARACETAMOL CP B/16', '3400562', 2850, 14),
        _p('E1', 'EFFERALGAN 1G CPR EFFV B/8', '3400933', 1250, 30),
        _p('V1', 'VITAMINE C UPSA 1000MG CPR EFFV B/20', '3401178', 2300, 18),
        _p('S1', 'SAVON CYTHEROL 100G', '5000123', 1800, 22),
        _p('G1', 'GEL INTIME SAFORELLE 250ML', '5000001', 4800, 12),
        _p('R1', 'RHINOFEBRAL GELULES B/16', '3401551', 2900, 8),
        _p('L1', 'LAIT GUIGOZ 1ER AGE 400G', '7613032', 6500, 5),
        _p('F1', 'FERVEX ADULTES SACHETS B/8', '3400477', 2950, 16),
        _p('VO', 'VOLTARENE EMULGEL 1% TUBE 50G', '3400602', 3600, 11),
      ])
        p.lgFAMILLEID: p
    };

/// Produits avec photo : (couleur de la boîte, couleur du bandeau, marque, dosage).
const _photos = <String, (Color, Color, String, String)>{
  'P1': (Color(0xFFFFFFFF), Color(0xFFFFC20E), 'DOLIPRANE', '1000 mg'),
  'P2': (Color(0xFFFFFFFF), Color(0xFF1E88E5), 'DOLIPRANE', '500 mg'),
  'E1': (Color(0xFFF5F5F5), Color(0xFF2E7D32), 'EFFERALGAN', '1 g'),
  'V1': (Color(0xFFFF9800), Color(0xFFE65100), 'VITAMINE C', '1000 mg'),
  'VO': (Color(0xFFE3F2FD), Color(0xFF0D47A1), 'VOLTARENE', 'Emulgel 1%'),
  'L1': (Color(0xFFFFFFFF), Color(0xFF00897B), 'GUIGOZ', '1er âge'),
};

/// Images PNG des boîtes, générées au lancement.
final Map<String, Uint8List> _images = {};

class _Gw implements VenteGateway {
  final produits = _catalogue();
  final ajouts = <({String produit, int qte, int pu})>[];
  String reference = '20261014000127';

  @override
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async {
    final q = query.toUpperCase().replaceAll('%', ' ').trim();
    final mots = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final all = produits.values.where((p) => p.intCIP == q || mots.every(p.strNAME.toUpperCase().contains)).toList();
    return VenteOk(ProductPage(all.skip(start).take(limit).toList(), all.length));
  }

  @override
  Future<VenteResult<String>> addItemVno({required String produitId, required int qte, required int itemPu, String? venteId, required bool prevente}) async {
    ajouts.add((produit: produitId, qte: qte, pu: itemPu));
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
  Future<VenteResult<void>> terminerPrevente(String venteId) async => const VenteOk(null);

  @override
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async => VenteOk(_lignes);

  @override
  Future<VenteResult<void>> removeItem(String itemId) async => const VenteOk(null);

  @override
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId) async => VenteOk({'strREF': reference});

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _Imprimante implements BorneImprimante {
  @override
  Future<bool> imprimer(BorneTicket ticket) async => false; // pas d'imprimante : numéro + QR à l'écran
}

class _Env {
  final gw = _Gw();
  final monitor = ServerMonitor();
  final GlobalKey<BorneScreenState> cle = GlobalKey();
  late final BorneService service = BorneService(gw);

  BorneScreenState get etat => cle.currentState!;
  BorneProduit produit(String id) => BorneProduit(gw.produits[id]!, image: _photos.containsKey(id) ? 'cache' : null);

  Widget app(BorneConfig c) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme,
        home: BorneScreen(
          key: cle,
          service: service,
          config: c,
          monitor: monitor,
          imprimante: _Imprimante(),
          kiosque: KiosqueSimule(),
          officine: _officine,
          adminCheck: (_) async => false,
          onSortie: (_) {},
          image: (p, taille, picto) {
            final png = _images[p.id];
            return png == null ? picto : Image.memory(png, width: taille, height: taille, fit: BoxFit.cover, gaplessPlayback: true);
          },
          imageConnue: (id) => _photos.containsKey(id),
        ),
      );
}

const _config = BorneConfig(
  actif: true,
  login: 'borne',
  vedettes: ['3595583', '3401178', '3400602', '7613032', '5000123', '3401551', '3400477', '3400933'],
);

// ---------------------------------------------------------------------------
// Polices et images
// ---------------------------------------------------------------------------

Future<void> _polices() async {
  final dossier = '${Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path}'
      '/bin/cache/artifacts/material_fonts';
  Future<ByteData> lire(String f) async => ByteData.sublistView(await File(f.startsWith('/') ? f : '$dossier/$f').readAsBytes());
  const roboto = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf'];
  for (final famille in ['Roboto', 'FlutterTest']) {
    final l = FontLoader(famille);
    for (final f in roboto) {
      l.addFont(lire(f));
    }
    await l.load();
  }
  await (FontLoader('MaterialIcons')..addFont(lire('MaterialIcons-Regular.otf'))).load();
  // Repli pour les signes absents de la Roboto des tests (ex. « → ») : sur l'appareil, Android les trouve.
  final repli = ['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf']
      .where((f) => File(f).existsSync())
      .toList();
  if (repli.isNotEmpty) {
    final l = FontLoader(_repli);
    for (final f in repli) {
      l.addFont(lire(f));
    }
    await l.load();
  }
  // Aperçu du ticket (police « monospace ») : police à chasse fixe du système si elle existe.
  final mono = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf',
  ].where((f) => File(f).existsSync()).toList();
  if (mono.isNotEmpty) {
    final l = FontLoader('monospace');
    for (final f in mono) {
      l.addFont(lire(f));
    }
    await l.load();
  }
}

/// Dessine une boîte de médicament simple (face, dessus, côté) et la rend en PNG.
Future<Uint8List> _boite(Color fond, Color bandeau, String marque, String dosage) async {
  const n = 400.0;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, n, n), Paint()..color = const Color(0xFFF2F4F7));
  c.translate(-40, -50); // boîte (dessinée sur 480 px) centrée et agrandie
  // Ombre au sol.
  c.drawOval(const Rect.fromLTWH(70, 395, 360, 40), Paint()..color = const Color(0x33000000));
  const face = Rect.fromLTWH(70, 140, 280, 270);
  final dessus = Path()
    ..moveTo(70, 140)
    ..lineTo(130, 85)
    ..lineTo(410, 85)
    ..lineTo(350, 140)
    ..close();
  final cote = Path()
    ..moveTo(350, 140)
    ..lineTo(410, 85)
    ..lineTo(410, 355)
    ..lineTo(350, 410)
    ..close();
  c.drawPath(dessus, Paint()..color = Color.lerp(fond, Colors.white, .35)!);
  c.drawPath(cote, Paint()..color = Color.lerp(fond, Colors.black, .18)!);
  c.drawRect(face, Paint()..color = fond);
  c.drawRect(Rect.fromLTWH(face.left, face.top + 150, face.width, 70), Paint()..color = bandeau);
  final coteBandeau = Path()
    ..moveTo(350, 290)
    ..lineTo(410, 235)
    ..lineTo(410, 305)
    ..lineTo(350, 360)
    ..close();
  c.drawPath(coteBandeau, Paint()..color = Color.lerp(bandeau, Colors.black, .2)!);
  c.drawRect(face, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..color = const Color(0x22000000));
  final encre = fond.computeLuminance() > .5 ? const Color(0xFF14213D) : Colors.white;
  void texte(String t, double y, double taille, Color couleur, {FontWeight poids = FontWeight.w900}) {
    final b = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center, fontFamily: 'Roboto', fontSize: taille, fontWeight: poids, maxLines: 1))
      ..pushStyle(ui.TextStyle(color: couleur, fontFamily: 'Roboto', fontSize: taille, fontWeight: poids))
      ..addText(t);
    final p = b.build()..layout(ui.ParagraphConstraints(width: face.width - 20));
    c.drawParagraph(p, Offset(face.left + 10, y));
  }

  texte(marque, face.top + 42, marque.length > 9 ? 34 : 40, encre);
  texte(dosage, face.top + 96, 28, encre, poids: FontWeight.w500);
  texte('Prestige', face.top + 168, 30, bandeau.computeLuminance() > .5 ? const Color(0xFF14213D) : Colors.white, poids: FontWeight.w700);
  final img = await rec.endRecording().toImage(n.toInt(), n.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

// ---------------------------------------------------------------------------
// Capture
// ---------------------------------------------------------------------------

/// Erreurs de rendu (débordements…) relevées pendant les captures : affichées en fin de test.
final _defauts = <String>[];

void _ecran(WidgetTester t, (Size, double) e) {
  t.view.physicalSize = e.$1;
  t.view.devicePixelRatio = e.$2;
  addTearDown(t.view.reset);
}

Future<void> _attendre(WidgetTester t, [Duration d = const Duration(milliseconds: 300)]) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pump(d);
}

Future<void> _capture(WidgetTester t, String nom) async {
  // Le message « Ajouté : … » (2 s) a disparu avant la capture.
  ScaffoldMessenger.maybeOf(t.element(find.byType(Scaffold).first))?.clearSnackBars();
  await _attendre(t);
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await t.pump();
  final err = t.takeException();
  if (err != null) _defauts.add('$nom : ${err is FlutterError ? err.toStringDeep() : err}');
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dossier/$nom.png'));
}

Future<void> _fin(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

Future<_Env> _borne(WidgetTester t, (Size, double) e, {BorneConfig config = _config}) async {
  _ecran(t, e);
  final env = _Env();
  await t.pumpWidget(env.app(config));
  await _attendre(t);
  return env;
}

Future<void> _chercher(WidgetTester t, String q) async {
  await t.enterText(find.byKey(const ValueKey('borne-recherche')), q);
  await t.pump(const Duration(milliseconds: 450));
  await _attendre(t);
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pump();
}

Future<void> _tap(WidgetTester t, String cle) async {
  final f = find.byKey(ValueKey(cle));
  ScaffoldMessenger.maybeOf(t.element(find.byType(Scaffold).first))?.clearSnackBars();
  await _attendre(t);
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await _attendre(t);
}

/// Panier de démonstration : 3 produits.
void _remplir(_Env env) {
  env.etat.ajouter(env.produit('P1'), 2);
  env.etat.ajouter(env.produit('V1'), 1);
  env.etat.ajouter(env.produit('G1'), 1);
}

/// Ticket papier 58 mm, dans l'ordre d'impression de ReceiptService.printBorneTicket.
Widget _papier(BorneTicket t) {
  const s = TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black);
  final code = t.codeType == 'QR_CODE'
      ? QrImageView(data: t.prevente.reference, size: 150, padding: EdgeInsets.zero)
      : BarcodeWidget(barcode: Barcode.code128(), data: t.prevente.reference, width: 250, height: 60, drawText: false);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      body: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 40),
          decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t.officine.toUpperCase(), textAlign: TextAlign.center, style: s.copyWith(fontWeight: FontWeight.bold, fontSize: 14)),
            Text(t.titre, style: s.copyWith(fontWeight: FontWeight.bold)),
            Text('N° ${t.prevente.numero}', style: s.copyWith(fontWeight: FontWeight.w900, fontSize: 30)),
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final l in t.lignes) Text(l, style: s)])),
            const SizedBox(height: 14),
            code,
            const SizedBox(height: 6),
            Text(t.prevente.reference, style: s),
            Text(t.invitationTexte, textAlign: TextAlign.center, style: s.copyWith(fontWeight: FontWeight.bold)),
            Text(t.date, style: s),
          ]),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    if (!_actif) return;
    await _polices();
    for (final e in _photos.entries) {
      final (fond, bandeau, marque, dosage) = e.value;
      _images[e.key] = await _boite(fond, bandeau, marque, dosage);
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BorneReglages.courant.value = const BorneConfig();
    BorneReglages.secrets = MemoireBorneSecrets();
    BorneKiosque.instance = KiosqueSimule();
    HorsLigneScope.masquer.value = false;
  });

  tearDownAll(() {
    if (!_actif) return;
    // ignore: avoid_print
    print(_defauts.isEmpty ? 'Captures borne : aucune erreur de rendu.' : 'Captures borne — erreurs de rendu :\n${_defauts.join('\n\n')}');
  });

  testWidgets('accueil : 3 présentations, tablette paysage / portrait, Sunmi V2s', (t) async {
    for (final (nom, e, pres) in [
      ('01_accueil_vitrine_tablette_paysage', _paysage, BornePresentation.vitrine),
      ('02_accueil_vitrine_tablette_portrait', _portrait, BornePresentation.vitrine),
      ('03_accueil_liste_rapide_tablette_portrait', _portrait, BornePresentation.listeRapide),
      ('04_accueil_guidee_tablette_portrait', _portrait, BornePresentation.guidee),
      ('15_accueil_vitrine_sunmi_v2s', _sunmi, BornePresentation.vitrine),
      ('16_accueil_liste_rapide_sunmi_v2s', _sunmi, BornePresentation.listeRapide),
    ]) {
      await _borne(t, e, config: _config.copyWith(presentation: pres));
      await _capture(t, nom);
      await _fin(t);
    }
  }, skip: !_actif);

  testWidgets('recherche « doli » et fiche produit', (t) async {
    await _borne(t, _portrait);
    await _chercher(t, 'doli');
    await _capture(t, '05_resultats_doli_tablette_portrait');
    await _tap(t, 'borne-produit-P1');
    await _tap(t, 'borne-fiche-qte-plus');
    await _capture(t, '07_fiche_produit_tablette_portrait');
    await _fin(t);

    await _borne(t, _paysage);
    await _chercher(t, 'doli');
    await _capture(t, '06_resultats_doli_tablette_paysage');
    await _tap(t, 'borne-produit-P3');
    await _capture(t, '08_fiche_produit_sans_photo_tablette_paysage');
    await _fin(t);
  }, skip: !_actif);

  testWidgets('panier, écart de prix, ticket à l\'écran', (t) async {
    final env = await _borne(t, _portrait);
    _remplir(env);
    await _attendre(t);
    await _tap(t, 'borne-voir-panier');
    await _capture(t, '09_panier_tablette_portrait');

    // Le prix de la vitamine C a changé sur le serveur depuis l'ajout.
    env.gw.produits['V1'] = _p('V1', 'VITAMINE C UPSA 1000MG CPR EFFV B/20', '3401178', 2500, 18);
    await _tap(t, 'borne-payer');
    await _capture(t, '11_validation_ecart_prix_tablette_portrait');
    await _tap(t, 'borne-confirmer-ecarts');
    await _capture(t, '12_ticket_ecran_qr_tablette_portrait');
    await _fin(t);

    final env2 = await _borne(t, _paysage);
    await _chercher(t, 'doli');
    _remplir(env2);
    await _attendre(t);
    await _capture(t, '10_panier_lateral_tablette_paysage');
    await _fin(t);

    final env3 = await _borne(t, _sunmi);
    _remplir(env3);
    await _attendre(t);
    await _tap(t, 'borne-voir-panier');
    await _tap(t, 'borne-payer');
    await _capture(t, '17_ticket_ecran_qr_sunmi_v2s');
    await _fin(t);
  }, skip: !_actif);

  testWidgets('ticket imprimé : normal (QR) et discret (code-barres)', (t) async {
    _ecran(t, (const Size(840, 1500), 2.0));
    final gw = _Gw();
    for (final (id, q) in [('P1', 2), ('V1', 1), ('G1', 1)]) {
      gw.ajouts.add((produit: id, qte: q, pu: gw.produits[id]!.intPRICE));
    }
    final pv = BornePrevente(
        venteId: 'V1', reference: gw.reference, total: gw._lignes.fold(0, (s, l) => s + l.intPRICE), lignes: gw._lignes, at: DateTime(2026, 10, 14, 10, 42));
    for (final (nom, ticket) in [
      ('13_ticket_imprime_normal_qr', BorneTicket(officine: _officine, prevente: pv)),
      ('14_ticket_imprime_discret_code_barres', BorneTicket(officine: _officine, prevente: pv, discret: true, codeType: 'BARCODE')),
    ]) {
      await t.pumpWidget(_papier(ticket));
      await _capture(t, nom);
    }
    await _fin(t);
  }, skip: !_actif);

  testWidgets('réglages de la borne (administrateur)', (t) async {
    BorneReglages.courant.value = _config.copyWith(login: 'borne.accueil');
    BorneReglages.secrets = MemoireBorneSecrets('motdepasse');
    for (final (nom, e) in [
      ('18_reglages_borne_tablette_portrait', _portrait),
      ('19_reglages_borne_sunmi_v2s', _sunmi),
    ]) {
      _ecran(t, e);
      await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: _theme, home: BornePage(ouvrir: (_) {})));
      await _attendre(t);
      await _capture(t, nom);
      await t.drag(find.byType(ListView).first, const Offset(0, -3000));
      await _attendre(t);
      await _capture(t, '${nom}_suite');
      await _fin(t);
    }
  }, skip: !_actif);
}
