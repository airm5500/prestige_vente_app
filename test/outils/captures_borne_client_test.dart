// Captures PNG RÉELLES (application PrestigePOS entière, faux serveur, données FICTIVES) de la zone « Client » de la
// borne (1.11.0) : Sunmi V2s 720 × 1440 et tablette paysage 1920 × 1200. Hors de la CI (APERCUS=1) :
//   APERCUS=1 CAPTURES=/chemin flutter test test/outils/captures_borne_client_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../prestigepos/outils/pos_e2e.dart';
import '../prestigepos/pos_e2e_test.dart' show attendreBorne;
import 'clients_vente_fictifs.dart';

final _actif = Platform.environment.containsKey('APERCUS');
final _dossier = Platform.environment['CAPTURES'] ?? '/tmp/captures_client';

Future<void> _polices() async {
  final dossier = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<ByteData> lire(String f) async => ByteData.sublistView(await File('$dossier/$f').readAsBytes());
  for (final famille in ['Roboto', 'FlutterTest']) {
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

  for (final (taille, densite, code) in [(const Size(720, 1440), 2.0, 'borne_sunmi_v2s'), (const Size(1920, 1200), 1.5, 'borne_tablette')]) {
    testWidgets('captures zone Client de la borne — $code', (t) async {
      t.view.physicalSize = taille;
      t.view.devicePixelRatio = densite;
      addTearDown(t.view.reset);
      final app = PosE2E();
      ClientsVenteFictifs(app.serveur);
      await app.preparer(configure: true);
      await app.lancer(t);
      await attendreBorne(t, app);
      await app.chercher(t, 'doli');
      await app.toucher(t, 'borne-ajouter-F1');
      await app.attendre(t, const Duration(milliseconds: 2600));
      if (find.byKey(const ValueKey('borne-voir-panier')).evaluate().isNotEmpty) {
        await app.toucher(t, 'borne-voir-panier');
      } else {
        await app.toucher(t, 'borne-panier-lateral-payer');
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await app.attendre(t, const Duration(milliseconds: 500));
      await _capture(t, '${code}_1_panier');
      await app.toucher(t, 'borne-client-ouvrir');
      await app.saisir(t, 'borne-client-recherche', 'KOFFI');
      await app.attendreQue(t, find.byKey(const ValueKey('borne-client-resultat-CL-FICT-1')));
      FocusManager.instance.primaryFocus?.unfocus();
      await app.attendre(t, const Duration(milliseconds: 500));
      await _capture(t, '${code}_2_recherche');
      await app.toucher(t, 'borne-client-nouveau');
      await app.saisir(t, 'borne-client-prenom-saisi', 'Essai');
      await app.saisir(t, 'borne-client-telephone-saisi', '07 00 00 99 99');
      FocusManager.instance.primaryFocus?.unfocus();
      await app.attendre(t, const Duration(milliseconds: 500));
      await _capture(t, '${code}_3_nouveau_client');
      await app.toucher(t, 'borne-client-retour');
      await app.toucher(t, 'borne-client-ouvrir');
      await app.saisir(t, 'borne-client-recherche', 'KOFFI');
      await app.attendreQue(t, find.byKey(const ValueKey('borne-client-resultat-CL-FICT-1')));
      await app.toucher(t, 'borne-client-resultat-CL-FICT-1');
      FocusManager.instance.primaryFocus?.unfocus();
      await app.attendre(t, const Duration(milliseconds: 500));
      await _capture(t, '${code}_4_client_choisi');
      await t.tap(find.byKey(const ValueKey('borne-client-retirer')));
      await t.pump(const Duration(milliseconds: 300));
      await _capture(t, '${code}_5_croix_rouge');
      await t.pump(const Duration(seconds: 5));
      await app.toucher(t, 'borne-payer');
      await app.attendreQue(t, find.byKey(const ValueKey('borne-numero')));
      await app.attendre(t, const Duration(milliseconds: 500));
      await _capture(t, '${code}_6_ticket');
      await app.toucher(t, 'borne-termine');
      await app.fermer(t);
    }, skip: !_actif);
  }
}
