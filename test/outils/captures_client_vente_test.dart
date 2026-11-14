// Captures PNG RÉELLES (rendu Flutter de l'application entière, faux serveur, données FICTIVES) de la zone « Client »
// de la vente comptant (4.13.0), pour présentation au pharmacien : Sunmi V2s (720 × 1440) et tablette (1920 × 1200).
// Hors de la suite de la CI (dossier test/outils/, ignoré sans la variable APERCUS). Pour régénérer :
//   APERCUS=1 CAPTURES=/chemin flutter test test/outils/captures_client_vente_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'app_e2e.dart';
import 'clients_vente_fictifs.dart';
import 'parcours_vente.dart';

final _actif = Platform.environment.containsKey('APERCUS');
final _dossier = Platform.environment['CAPTURES'] ?? '/tmp/captures_client';

Future<void> _polices() async {
  final dossier = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<ByteData> lire(String f) async => ByteData.sublistView(await File('$dossier/$f').readAsBytes());
  for (final famille in ['Roboto', 'FlutterTest', '', 'Ahem', 'sans-serif', 'Roboto Flex']) {
    final l = FontLoader(famille);
    for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
      l.addFont(lire(f));
    }
    await l.load();
  }
  await (FontLoader('MaterialIcons')..addFont(lire('MaterialIcons-Regular.otf'))).load();
}

Future<void> _capture(WidgetTester t, String nom) async {
  await t.pump();
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile(Uri.file('$_dossier/$nom.png')));
}

void main() {
  setUpAll(() async {
    if (_actif) await _polices();
  });

  for (final (taille, code) in [(TailleEcran.sunmiV2s, 'sunmi_v2s'), (TailleEcran.tablette, 'tablette')]) {
    testWidgets('captures zone Client — $code', (t) async {
      taille.appliquer(t);
      final app = AppE2E();
      CatalogueFictif(app.serveur, nombre: 10);
      ClientsVenteFictifs(app.serveur);
      await app.preparer(prefs: prefsVente);
      await app.lancer(t);
      expect(await app.seConnecter(t), isTrue);
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
      expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
      await app.attendre(t, const Duration(seconds: 2));
      FocusManager.instance.primaryFocus?.unfocus();
      await app.attendre(t, const Duration(milliseconds: 500));
      await _capture(t, '${code}_1_zone_vide');
      await t.tap(find.byKey(const ValueKey('client-vente-ouvrir')));
      await app.attendre(t, const Duration(milliseconds: 600));
      await t.enterText(find.byKey(const ValueKey('client-vente-recherche')), 'KOFFI');
      await app.attendreQue(t, find.byKey(const ValueKey('client-vente-resultat-CL-FICT-1')));
      await app.attendre(t, const Duration(milliseconds: 500));
      await _capture(t, '${code}_2_recherche');
      await t.tap(find.byKey(const ValueKey('client-vente-nouveau')));
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('client-vente-prenom-saisi')), 'Essai');
      await t.enterText(find.byKey(const ValueKey('client-vente-telephone-saisi')), '07 00 00 99 99');
      await t.ensureVisible(find.byKey(const ValueKey('client-vente-creer')));
      await app.attendre(t, const Duration(milliseconds: 500));
      await _capture(t, '${code}_3_nouveau_client');
      await app.retour(t);
      await t.tap(find.byKey(const ValueKey('client-vente-ouvrir')));
      await app.attendre(t, const Duration(milliseconds: 600));
      await t.enterText(find.byKey(const ValueKey('client-vente-recherche')), 'KOFFI');
      await app.attendreQue(t, find.byKey(const ValueKey('client-vente-resultat-CL-FICT-1')));
      await t.tap(find.byKey(const ValueKey('client-vente-resultat-CL-FICT-1')));
      await app.attendre(t, const Duration(seconds: 5));
      await _capture(t, '${code}_4_client_choisi');
      await t.tap(find.byKey(const ValueKey('client-vente-retirer')));
      await t.pump(const Duration(milliseconds: 300));
      await _capture(t, '${code}_5_croix_rouge');
      await app.attendre(t, const Duration(seconds: 5));
      await app.fermer(t);
    }, skip: !_actif);
  }
}
