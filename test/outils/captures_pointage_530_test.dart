// Captures RÉELLES (polices Roboto) du pointage 5.3.0 sur un SUNMI V3 simulé (service d'empreinte Sunmi absent),
// données FICTIVES : bandeau « badge ou code personnel » (terminal de Prestige Mobile, borne Prestige Pointage, gestion
// des empreintes), réglage « Confirmer le pointage par empreinte » (Réglages › Équipe & pointage), panneau affiché
// pendant la demande d'empreinte (la fenêtre d'Android, dessinée par le système, s'affiche par-dessus sur le terminal),
// refus et mention. Outil hors CI, comme les autres test/outils/captures_* :
//   CAPTURES=/dossier flutter test test/outils/captures_pointage_530_test.dart --update-goldens
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/rh/empreintes_screen.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_e2e.dart' show TailleEcran;
import 'captures_store_v3_test.dart' show chargerPolicesReelles, capturerFidele;
import 'empreinte_terminal_fictif.dart';

final _base = Platform.environment['CAPTURES'] ?? '/tmp/captures_pointage_530';
final _actif = Platform.environment['CAPTURES'] != null;

Future<void> _capture(WidgetTester t, String nom) =>
    capturerFidele(t, find.byType(MaterialApp).first, Uri.file('$_base/$nom.png'));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    if (_actif) await chargerPolicesReelles();
  });

  final tailles = [(TailleEcran.sunmiV3, 'sunmi_v3'), (TailleEcran.tablette, 'tablette')];

  for (final (taille, nom) in tailles) {
    testWidgets('bandeau du terminal — $nom', (t) async {
      SharedPreferences.setMockInitialValues({ReglagesPointageTerminal.prefConfirmationEmpreinte: true});
      taille.appliquer(t);
      final e = TerminalEmpreinte();
      await e.preparer(t);
      await afficher(t, e.ecran());
      await _capture(t, '1_bandeau_terminal_$nom');
      await finir(t);
    }, skip: !_actif);

    testWidgets('bandeau de la borne Prestige Pointage — $nom', (t) async {
      SharedPreferences.setMockInitialValues({});
      taille.appliquer(t);
      final e = TerminalEmpreinte();
      await e.preparer(t);
      await afficher(t, e.ecran(borne: true, gestion: false));
      await _capture(t, '2_bandeau_borne_$nom');
      await finir(t);
    }, skip: !_actif);

    testWidgets('réglage « Confirmer le pointage par empreinte » — $nom', (t) async {
      SharedPreferences.setMockInitialValues({ReglagesPointageTerminal.prefConfirmationEmpreinte: true});
      taille.appliquer(t);
      final photo = PhotoControle(registre: RegistrePhotosPointage(stockage: StockagePhotosMemoire()));
      await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, home: EquipePage(repository: MemoryPointageRepository(), photo: photo)));
      await t.pumpAndSettle();
      final k = find.byKey(const Key('rh_reglage_confirmation_empreinte'));
      await t.scrollUntilVisible(k, 200, scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      Scrollable.ensureVisible(t.element(k), alignment: 0.3);
      await t.pumpAndSettle();
      await _capture(t, '3_reglage_confirmation_$nom');
    }, skip: !_actif);

    testWidgets('demande de confirmation par empreinte — $nom', (t) async {
      SharedPreferences.setMockInitialValues({ReglagesPointageTerminal.prefConfirmationEmpreinte: true});
      taille.appliquer(t);
      final e = TerminalEmpreinte();
      await e.preparer(t);
      final reponse = Completer<Object?>();
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(CanalEmpreinteSimule.canal, (c) async {
        if (c.method == 'hardwareInfo') return materielSunmiV3();
        if (c.method == 'isServiceInstalled') return false;
        if (c.method == 'authenticate') return reponse.future;
        return null;
      });
      await afficher(t, e.ecran());
      await lireBadge(t, badgeFictif1);
      await _capture(t, '4_demande_confirmation_$nom');
      reponse.completeError(PlatformException(code: 'CANCELED'));
      await t.pump();
      await t.pump();
      await _capture(t, '5_confirmation_annulee_$nom');
      await finir(t);
    }, skip: !_actif);

    testWidgets('pointage enregistré sans confirmation (aucune empreinte dans Android) — $nom', (t) async {
      SharedPreferences.setMockInitialValues({ReglagesPointageTerminal.prefConfirmationEmpreinte: true});
      taille.appliquer(t);
      final e = TerminalEmpreinte();
      e.canal.materiel = materielSunmiV3(biometricStatus: 11);
      await e.preparer(t);
      await afficher(t, e.ecran());
      await lireBadge(t, badgeFictif1);
      await t.tap(find.byKey(const Key('rh_valider')));
      await t.pump();
      await t.pump();
      await _capture(t, '6_mention_sans_empreinte_$nom');
      await finir(t);
    }, skip: !_actif);

    testWidgets('gestion des empreintes sans lecteur — $nom', (t) async {
      SharedPreferences.setMockInitialValues({});
      taille.appliquer(t);
      final e = TerminalEmpreinte();
      await e.preparer(t);
      await e.identification.enregistrer(EmpreintesEmploye(employeId: 'EX1', modeles: [Uint8List.fromList([1])], consentementLe: e.now));
      await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, home: EmpreintesScreen(rh: e.pr, identification: e.identification, codeAdmin: (_) async => true)));
      await t.pumpAndSettle();
      await _capture(t, '7_gestion_empreintes_$nom');
    }, skip: !_actif);
  }
}
