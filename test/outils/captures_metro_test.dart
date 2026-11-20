// Captures RÉELLES (polices Roboto) des présentations de l'accueil 5.2.0 et de leur réglage, données fictives.
// Outil hors CI, comme les autres test/outils/captures_* :
//   CAPTURES=/dossier flutter test test/outils/captures_metro_test.dart --update-goldens
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/connexion/connexion_reglages.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'app_e2e.dart';
import 'captures_store_v3_test.dart' show chargerPolicesReelles, capturerFidele;
import 'parcours_vente.dart';

final _base = Platform.environment['CAPTURES'] ?? '/tmp/captures_metro';
final _actif = Platform.environment['CAPTURES'] != null;

const _tablettePortrait = TailleEcran('Tablette 1200×1920', Size(1200, 1920), 1.5);
const _terminalLong = TailleEcran('Terminal page entière', Size(720, 3000), 1.8);

Future<AppE2E> _ouvrir(WidgetTester t, TailleEcran taille, AccueilPresentation p) async {
  taille.appliquer(t);
  final app = AppE2E(serveur: FauxServeurPrestige(comptes: {DonneesFictives.admin: DonneesFictives.motDePasseAdmin}));
  await app.preparer(prefs: {...prefsVente, ConnexionReglages.cleOfficine: 'PHARMACIE DÉMO', PresentationPrefs.cleAccueil: p.name});
  await app.lancer(t);
  expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
  await app.attendre(t, const Duration(seconds: 2));
  return app;
}

void main() {
  setUpAll(() async {
    if (_actif) await chargerPolicesReelles();
  });

  final tailles = [
    (TailleEcran.sunmiV2s, 'terminal'),
    (_terminalLong, 'terminal_page_entiere'),
    (TailleEcran.tablette, 'tablette'),
    (_tablettePortrait, 'tablette_portrait'),
  ];
  for (final p in AccueilPresentation.values) {
    for (final (taille, nom) in tailles) {
      testWidgets('accueil ${p.name} — $nom', (t) async {
        final app = await _ouvrir(t, taille, p);
        await capturerFidele(t, find.byType(MaterialApp).first, Uri.file('$_base/accueil_${p.name}_$nom.png'));
        await app.fermer(t);
      }, skip: !_actif);
    }
  }

  for (final (taille, nom) in [(TailleEcran.sunmiV2s, 'terminal'), (TailleEcran.tablette, 'tablette')]) {
    testWidgets('réglage de la présentation de l\'accueil — $nom', (t) async {
      final app = await _ouvrir(t, taille, AccueilPresentation.metroMosaique);
      await t.tap(find.text('Réglages'));
      await app.attendre(t, const Duration(seconds: 1));
      await t.tap(find.byKey(const Key('rubrique_apparence')));
      await app.attendre(t, const Duration(seconds: 1));
      final carte = find.byKey(const Key('presentation_accueil'));
      await t.scrollUntilVisible(carte, 200, scrollable: find.byType(Scrollable).last);
      await t.runAsync(() async {});
      Scrollable.ensureVisible(t.element(carte), alignment: 0.02);
      await app.attendre(t, const Duration(milliseconds: 500));
      await capturerFidele(t, find.byType(MaterialApp).first, Uri.file('$_base/reglage_presentation_accueil_$nom.png'));
      await app.fermer(t);
    }, skip: !_actif);
  }
}
