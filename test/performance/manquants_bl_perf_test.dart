// PERFORMANCE — Prestige Mobile 4.12.0 (demande 59), données FICTIVES :
//  - lecture des écarts : 20 réponses de 5 000 lignes (gros BL) en moins de 1 s ;
//  - requêtes de la clôture au reçu avec la capacité : 1 lecture des écarts avant (provisoire), 1 clôture, 1 relecture
//    après, 1 création de retour ; SANS la capacité : aucune requête de plus qu'en 4.11.0 ;
//  - fenêtre du résultat avec 500 lignes en écart : affichée en moins de 2 s, sans erreur.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/reception/manquants_bl.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/screens/reception_bl/bilan_recu_dialog.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_summary_screen.dart';

import '../manquants_bl_test.dart' show FakeManquants;

const _lignes = [
  ReceptionLine(detailId: 'd1', produitId: 'p1', name: 'PRODUIT FICTIF UN', code: '3595583', ordered: 10, entered: 7, lots: ['L1'], blRef: 'BL-778'),
  ReceptionLine(detailId: 'd2', produitId: 'p2', name: 'PRODUIT FICTIF DEUX', code: '3000000', ordered: 5, blRef: 'BL-778'),
];

Map<String, dynamic> _ecart(int i) => {'detailId': 'D$i', 'cip': '${3400000 + i}', 'nom': 'PRODUIT FICTIF $i', 'commande': 10, 'recu': i % 10, 'ug': 0, 'manquant': 10 - i % 10};

Future<void> _parcours(WidgetTester t, FakeManquants g) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
      home: ReceptionSummaryScreen(
          bl: const ReceptionBl(id: 'bl1', ref: 'BL-778', grossiste: 'GROSSISTE FICTIF'),
          gateway: g,
          settings: const ReceptionSettings(terminalValidation: true),
          lines: _lignes,
          clock: () => DateTime(2026, 11, 9))));
  await t.pumpAndSettle();
  await t.ensureVisible(find.byKey(const Key('bl_entrer_recu')));
  await t.tap(find.byKey(const Key('bl_entrer_recu')));
  await t.pumpAndSettle();
  await t.tap(find.text('Entrer le reçu'));
  await t.pumpAndSettle();
}

void main() {
  test('écarts : 20 réponses de 5 000 lignes lues en moins de 1 s', () {
    final corps = {'success': true, 'mode': 'RECU', 'ecarts': [for (var i = 0; i < 5000; i++) _ecart(i)], 'retourManquants': null};
    final sw = Stopwatch()..start();
    var total = 0;
    for (var k = 0; k < 20; k++) {
      total += EcartsBl.fromJson(corps).totalManquant;
    }
    sw.stop();
    expect(total, greaterThan(0));
    expect(sw.elapsedMilliseconds, lessThan(1000), reason: '${sw.elapsedMilliseconds} ms');
  });

  testWidgets('requêtes : avec la capacité, 2 lectures des écarts + 1 clôture + 1 retour', (t) async {
    final avec = FakeManquants()
      ..reponseRecu = const ReceptionResult(true, 'ok', {'success': true, 'totalManquant': 8})
      ..provisoire = const EcartsBl(success: true, mode: 'PROVISOIRE', provisoire: true, totalManquant: 8, ecarts: [LigneEcart(nom: 'X', commande: 8, recu: 0, manquant: 8)])
      ..apres = const EcartsBl(success: true, mode: 'RECU', totalManquant: 8, ecarts: [LigneEcart(nom: 'X', commande: 8, recu: 0, manquant: 8)])
      ..reponsesRetour.add(const RetourManquants(success: true, ref: 'RF-1', statut: 'is_Waiting'));
    await _parcours(t, avec);
    await t.tap(find.byKey(const Key('bl_retour_manquants')));
    await t.pumpAndSettle();
    expect((avec.ecartsLus.length, avec.recuRefs.length, avec.retourRefs.length), (2, 1, 1));
  });

  testWidgets('requêtes : SANS la capacité, 1 clôture seulement (comme 4.11.0)', (t) async {
    final sans = FakeManquants()
      ..capacite = false
      ..reponseRecu = const ReceptionResult(true, 'ok', {'success': true, 'totalManquant': 8});
    await _parcours(t, sans);
    expect((sans.ecartsLus.length, sans.recuRefs.length, sans.retourRefs.length), (0, 1, 0));
  });

  testWidgets('fenêtre du résultat : 500 lignes en écart affichées en moins de 2 s', (t) async {
    t.view.physicalSize = const Size(720, 1440);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    final r = ReceptionResult(true, 'BL entré avec écart', {'success': true, 'ecarts': [for (var i = 0; i < 500; i++) _ecart(i)]});
    final sw = Stopwatch()..start();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: BilanRecuDialog(bl: const ReceptionBl(id: 'bl1', ref: 'BL-778', grossiste: 'G'), resultat: r))));
    await t.pumpAndSettle();
    sw.stop();
    expect(find.text('Écart au rapport :'), findsOneWidget);
    expect(t.takeException(), isNull);
    expect(sw.elapsedMilliseconds, lessThan(2000), reason: '${sw.elapsedMilliseconds} ms');
  });
}
