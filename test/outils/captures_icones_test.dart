// CAPTURES (hors CI, APERCUS=1) — 4.11.0, plan du pharmacien du 08/11 : « les icônes sont trop petites, sur tablette
// et sur terminal ». Application entière contre le faux serveur (données FICTIVES), polices réelles : accueil (tuiles),
// Réserve, Réception, Ventes, aux tailles Sunmi V2s / V3, téléphone 360 × 800 dp, tablette 10″ (portrait et paysage).
// Écrit un PNG par écran et par taille dans CAPTURES, et un relevé des tailles d'icônes réellement rendues
// (dp RÉELS, après « Taille de l'écran ») dans CAPTURES/tailles.txt, pour comparer avant / après.
//   APERCUS=1 CAPTURES=/chemin flutter test test/outils/captures_icones_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'app_e2e.dart';

final _actif = Platform.environment.containsKey('APERCUS');
final _dossier = Platform.environment['CAPTURES'] ?? '/tmp/captures_icones';

const _tailles = <String, (Size, double)>{
  'sunmi_v2s_720x1440': (Size(720, 1440), 2.0),
  'sunmi_v3_1080x1920': (Size(1080, 1920), 2.625),
  'telephone_360x800dp': (Size(1080, 2400), 3.0),
  'tablette10_portrait_800x1280dp': (Size(1200, 1920), 1.5),
  'tablette10_paysage_1280x800dp': (Size(1920, 1200), 1.5),
};

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

final _releve = StringBuffer();

/// Taille RÉELLE (dp physiques / densité de la vue) des icônes visibles : minimum, médiane, maximum.
void _mesurer(WidgetTester t, String nom) {
  final ecran = Offset.zero & (t.view.physicalSize / t.view.devicePixelRatio);
  final tailles = <double>[];
  for (final e in find.byType(Icon).evaluate()) {
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final r = MatrixUtils.transformRect(ro.getTransformTo(null), Offset.zero & ro.size);
    if (!ecran.overlaps(r) || r.height < 4) continue;
    tailles.add(r.height);
  }
  tailles.sort();
  if (tailles.isEmpty) {
    _releve.writeln('$nom : aucune icône');
    return;
  }
  final med = tailles[tailles.length ~/ 2];
  _releve.writeln('$nom : ${tailles.length} icônes, min ${tailles.first.toStringAsFixed(1)} dp, médiane ${med.toStringAsFixed(1)} dp, '
      'max ${tailles.last.toStringAsFixed(1)} dp');
}

Future<void> _capturer(WidgetTester t, String nom) async {
  await t.pump(const Duration(milliseconds: 300));
  _mesurer(t, nom);
  final ro = t.binding.renderViews.first;
  final layer = ro.debugLayer! as OffsetLayer;
  // La couche racine applique déjà la densité : image en pixels physiques avec pixelRatio 1.
  final image = await t.runAsync(() => layer.toImage(Offset.zero & t.view.physicalSize, pixelRatio: 1.0));
  final png = await t.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
  await t.runAsync(() => File('$_dossier/$nom.png').writeAsBytes(png!.buffer.asUint8List()));
}

void main() {
  setUpAll(() async {
    if (!_actif) return;
    await _polices();
    Directory(_dossier).createSync(recursive: true);
  });
  tearDownAll(() {
    if (_actif) File('$_dossier/tailles.txt').writeAsStringSync(_releve.toString());
  });

  for (final MapEntry(key: nom, value: (pixels, densite)) in _tailles.entries) {
    testWidgets('icônes : $nom', (t) async {
      t.view.physicalSize = pixels;
      t.view.devicePixelRatio = densite;
      addTearDown(t.view.reset);
      final app = AppE2E();
      await app.preparer(prefs: {'hiddenMenuIds': <String>[], 'enabled_payment_method_ids': ['1', '10']});
      await app.lancer(t);
      expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
      await app.attendre(t, const Duration(seconds: 2));
      await _capturer(t, '${nom}_1_accueil');
      for (final (id, cle) in [('reserve', '2_reserve'), ('reception_bl', '3_reception'), ('prevente', '4_vente')]) {
        try {
          await app.ouvrirMenu(t, ListPresentation.dashboard, id);
          await app.attendre(t, const Duration(seconds: 2));
          await _capturer(t, '${nom}_$cle');
          await app.retour(t);
          if (find.text('Quitter').evaluate().isNotEmpty) await t.tap(find.text('Quitter'));
          await app.attendre(t, const Duration(seconds: 1));
        } catch (e) {
          _releve.writeln('$nom $cle : non capturé ($e)');
        }
      }
      expect(t.takeException(), isNull);
      await app.fermer(t);
    }, skip: !_actif);
  }
}
