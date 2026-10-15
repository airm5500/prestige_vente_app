// Captures PNG RÉELLES de PrestigePOS (rendu Flutter de l'application entière, faux serveur en mémoire, données
// fictives) : docs/prestigepos/captures/*.png.
// Hors de la suite de la CI (dossier test/outils/, ignoré sans la variable APERCUS). Pour régénérer :
//   APERCUS=1 flutter test test/outils/captures_prestigepos_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_reglages.dart';
import 'package:prestige_vente_app/prestigepos/impression/transports.dart';

import '../prestigepos/outils/pos_e2e.dart';

final _actif = Platform.environment.containsKey('APERCUS');
const _dossier = '../../docs/prestigepos/captures';

const _paysage = (Size(1920, 1200), 1.5);
const _borneVerticale = (Size(1080, 1920), 1.0);
const _portrait = (Size(1200, 1920), 1.5);
const _sunmi = (Size(720, 1440), 2.0);

final _catalogue = [
  produit('P1', 'DOLIPRANE 1000MG CP B/8', '3595583', 1500, 40),
  produit('P2', 'DOLIPRANE 500MG CP B/16', '3595590', 1200, 25),
  produit('P3', 'DOLIPRANE 2,4% SUSP BUV FL/100ML', '3400001', 2100, 6),
  produit('P5', 'DOLIKIDS 150MG SUPPO B/10', '3400215', 1350, 9),
  produit('P6', 'DOLIRHUME PARACETAMOL CP B/16', '3400562', 2850, 14),
  produit('V1', 'VITAMINE C UPSA 1000MG CPR EFFV B/20', '3401178', 2300, 18),
  produit('S1', 'SAVON CYTHEROL 100G', '5000123', 1800, 22),
  produit('L1', 'LAIT GUIGOZ 1ER AGE 400G', '7613032', 6500, 5),
  produit('F1', 'FERVEX ADULTES SACHETS B/8', '3400477', 2950, 16),
];

const _borne = BorneConfig(actif: true, login: loginBorne, vedettes: ['3595583', '3401178', '7613032', '5000123', '3400477', '3400562']);

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
  final mono = ['/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf']
      .where((f) => File(f).existsSync())
      .toList();
  if (mono.isNotEmpty) {
    final l = FontLoader('monospace');
    for (final f in mono) {
      l.addFont(lire(f));
    }
    await l.load();
  }
}

void _ecran(WidgetTester t, (Size, double) e) {
  t.view.physicalSize = e.$1;
  t.view.devicePixelRatio = e.$2;
  addTearDown(t.view.reset);
}

Future<void> _capture(WidgetTester t, PosE2E app, String nom) async {
  ScaffoldMessenger.maybeOf(t.element(find.byType(Scaffold).first))?.clearSnackBars();
  FocusManager.instance.primaryFocus?.unfocus();
  await app.attendre(t, const Duration(milliseconds: 800));
  expect(t.takeException(), isNull, reason: '$nom : erreur de rendu');
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dossier/$nom.png'));
}

Future<PosE2E> _borneOuverte(WidgetTester t, (Size, double) e, {BornePresentation presentation = BornePresentation.vitrine}) async {
  _ecran(t, e);
  final app = PosE2E(catalogue: _catalogue);
  await app.preparer(configure: true, prefs: PosE2E.prefsConfigure(borne: _borne.copyWith(presentation: presentation)));
  await app.lancer(t);
  expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-recherche'))), isTrue);
  await app.attendre(t, const Duration(seconds: 2));
  return app;
}

void main() {
  setUpAll(() async {
    if (_actif) await _polices();
  });

  testWidgets('assistant de configuration', (t) async {
    _ecran(t, _portrait);
    final app = PosE2E(catalogue: _catalogue);
    await app.preparer();
    await app.lancer(t);
    await app.attendreQue(t, find.byKey(const ValueKey('pos-bienvenue')));
    await _capture(t, app, '01_premier_lancement_tablette_portrait');
    await app.toucher(t, 'pos-configurer');
    await app.saisirCode(t);
    await app.saisir(t, 'pos-serveur-adresse', 'https://pharmacie-palmiers.exemple.ci');
    await _capture(t, app, '02_assistant_serveur_tablette_portrait');
    await app.saisir(t, 'pos-serveur-adresse', FauxServeurPrestige.hoteMemoire);
    await app.toucher(t, 'pos-serveur-verifier');
    await app.attendre(t);
    await app.saisir(t, 'pos-borne-login', loginBorne);
    await app.saisir(t, 'pos-borne-mdp', mdpBorne);
    await app.toucher(t, 'pos-borne-tester');
    await app.attendre(t);
    await _capture(t, app, '03_assistant_utilisateur_borne_teste_tablette_portrait');
    await app.toucher(t, 'pos-suivant');
    await _capture(t, app, '04_assistant_presentation_tablette_portrait');
    await app.fermer(t);
  }, skip: !_actif);

  testWidgets('réglages imprimante : recherche Bluetooth', (t) async {
    for (final (nom, e) in [('tablette_portrait', _portrait), ('sunmi_v2s', _sunmi)]) {
      _ecran(t, e);
      final app = PosE2E(catalogue: _catalogue);
      app.pont.decouverts = const [
        AppareilImprimante(nom: 'Casque JBL T110', adresse: '10:20:30:40:50:60'),
        AppareilImprimante(nom: 'RPP02N', adresse: '86:67:7A:12:34:56', imprimante: true),
      ];
      await app.preparer(configure: true, prefs: PosE2E.prefsConfigure(borne: _borne));
      await app.lancer(t);
      await app.attendreQue(t, find.byKey(const ValueKey('borne-recherche')));
      await app.attendre(t, const Duration(seconds: 1));
      await app.quitterBorne(t);
      await app.attendre(t);
      await _capture(t, app, '05_administration_$nom');
      await app.toucher(t, 'pos-admin-imprimante');
      await app.toucher(t, 'imp-bt-rechercher');
      await app.attendre(t, const Duration(seconds: 1));
      await app.toucher(t, 'imp-bt-trouve-86:67:7A:12:34:56');
      await _capture(t, app, '06_imprimante_recherche_bluetooth_$nom');
      await app.fermer(t);
    }
  }, skip: !_actif);

  testWidgets('borne : accueil Vitrine (tablette paysage, borne verticale), panier, ticket', (t) async {
    var app = await _borneOuverte(t, _paysage);
    await _capture(t, app, '07_accueil_vitrine_tablette_paysage');
    await app.chercher(t, 'doli');
    await app.toucher(t, 'borne-ajouter-P1');
    await app.toucher(t, 'borne-ajouter-P6');
    await _capture(t, app, '08_resultats_panier_lateral_tablette_paysage');
    await app.fermer(t);

    app = await _borneOuverte(t, _borneVerticale);
    await _capture(t, app, '09_accueil_vitrine_borne_verticale');
    await app.chercher(t, 'doli');
    await app.toucher(t, 'borne-ajouter-P1');
    await app.toucher(t, 'borne-ajouter-P3');
    await app.attendre(t, const Duration(milliseconds: 2600));
    await app.toucher(t, 'borne-panier-lateral-payer');
    await _capture(t, app, '10_panier_borne_verticale');
    await app.toucher(t, 'borne-payer');
    await app.attendreQue(t, find.byKey(const ValueKey('borne-numero')));
    await _capture(t, app, '11_ticket_imprime_borne_verticale');
    await app.fermer(t);

    app = await _borneOuverte(t, _portrait);
    app.pont.echec = EchecImpression('CONNEXION', EchecImpression.messagePour('CONNEXION'));
    await app.chercher(t, 'vitamine');
    await app.toucher(t, 'borne-ajouter-V1');
    await app.attendre(t, const Duration(milliseconds: 2600));
    await app.toucher(t, 'borne-voir-panier');
    await app.toucher(t, 'borne-payer');
    await app.attendreQue(t, find.byKey(const ValueKey('borne-numero')));
    await _capture(t, app, '12_ticket_ecran_imprimante_en_panne_tablette_portrait');
    await app.fermer(t);

    app = await _borneOuverte(t, _sunmi, presentation: BornePresentation.listeRapide);
    await _capture(t, app, '13_accueil_liste_rapide_sunmi_v2s');
    await app.fermer(t);
  }, skip: !_actif);
}
