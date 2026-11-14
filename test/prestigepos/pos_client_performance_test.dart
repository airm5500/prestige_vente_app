// PrestigePOS 1.11.0 — PERFORMANCE de la zone Client de la borne (application entière, données FICTIVES) :
//  - « Payer en caisse » SANS client : exactement les requêtes de 1.10.1 (aucune route client) ;
//  - AVEC un client : UNE requête de plus (POST vente/update/client) ;
//  - recherche tapée vite : UNE requête GET client/lambda ; choisir : AUCUNE requête (rattaché à la création).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../outils/clients_vente_fictifs.dart';
import '../outils/performance.dart' show mesurer;
import 'outils/pos_e2e.dart';
import 'pos_e2e_test.dart' show attendreBorne, tablettePortrait;

String _route(RequeteRecue r) => '${r.methode} ${r.chemin.replaceFirst(RegExp(r'^.*/api/v1'), '').replaceAll(RegExp(r'V-\d+'), '{id}')}';

Future<List<String>> _payer(WidgetTester t, PosE2E app, {String? client}) async {
  await app.chercher(t, 'doli');
  await app.toucher(t, 'borne-ajouter-F1');
  await app.attendre(t, const Duration(milliseconds: 2600));
  await app.toucher(t, 'borne-voir-panier');
  if (client != null) {
    await app.toucher(t, 'borne-client-ouvrir');
    final avant = app.serveur.recues.length;
    for (final s in ['K', 'KO', 'KOF', 'KOFF', 'KOFFI']) {
      await t.enterText(find.byKey(const ValueKey('borne-client-recherche')), s);
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(await app.attendreQue(t, find.byKey(ValueKey('borne-client-resultat-$client'))), isTrue);
    final rech = [for (final r in app.serveur.recues.skip(avant)) _route(r)];
    mesurer('PrestigePOS — Client : recherche tapée vite', rech.length, seuil: 1, unite: 'requêtes', detail: rech.join(', '));
    final avantChoix = app.serveur.recues.length;
    await app.toucher(t, 'borne-client-resultat-$client');
    mesurer('PrestigePOS — Client : choix (rattaché à la création)', app.serveur.recues.length - avantChoix, seuil: 0, unite: 'requêtes');
  }
  final avant = app.serveur.recues.length;
  await app.toucher(t, 'borne-payer');
  expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-numero'))), isTrue);
  final rs = [for (final r in app.serveur.recues.skip(avant)) _route(r)];
  await app.toucher(t, 'borne-termine');
  return rs;
}

void main() {
  testWidgets('payer sans client : aucune route client ; avec client : +1 POST vente/update/client', (t) async {
    tablettePortrait(t);
    final app = PosE2E();
    ClientsVenteFictifs(app.serveur);
    await app.preparer(configure: true);
    await app.lancer(t);
    await attendreBorne(t, app);
    final sans = await _payer(t, app);
    expect(sans.where((r) => r.contains('/client')), isEmpty, reason: '$sans');
    final avec = await _payer(t, app, client: 'CL-FICT-1');
    final metier = [for (final r in avec) if (!r.contains('capacites')) r];
    final metierSans = [for (final r in sans) if (!r.contains('capacites')) r];
    mesurer('PrestigePOS — payer avec client : requêtes en plus', metier.length - metierSans.length, seuil: 1, unite: 'requêtes', detail: avec.join(', '));
    expect(avec.where((r) => r == 'POST /vente/update/client'), hasLength(1));
    expect([...metier]..remove('POST /vente/update/client'), metierSans);
    await app.fermer(t);
  });
}
