// Captures RÉELLES (polices Roboto) de la 5.4.0 sur un SUNMI V3 simulé, données FICTIVES : écran « Réédition des
// ventes » (ce terminal, tous les postes), choix du nombre d'exemplaires, question « Ticket suivant (2/2) » et réglage
// « Contraste d'impression ». Outil hors CI, comme les autres test/outils/captures_* :
//   CAPTURES=/dossier flutter test test/outils/captures_reedition_540_test.dart --update-goldens
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/impression_ticket.dart';
import 'package:prestige_vente_app/ventes/common/copies_ticket.dart';
import 'package:prestige_vente_app/ventes/reedition/reedition_ventes_screen.dart';
import 'package:prestige_vente_app/ventes/reedition/ventes_du_terminal.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_e2e.dart' show TailleEcran;
import 'captures_store_v3_test.dart' show chargerPolicesReelles, capturerFidele;

final _base = Platform.environment['CAPTURES'] ?? '/tmp/captures_reedition_540';
final _actif = Platform.environment['CAPTURES'] != null;

class _Liste implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    final jour = DateFormat('dd/MM/yyyy').format(DateTime.now());
    Map<String, Object> v(String id, String ticket, String type, String heure, int prix, String poste) => {
          'lgPREENREGISTREMENTID': id,
          'strREF': 'REF-$id',
          'strREFTICKET': ticket,
          'intPRICE': prix,
          'dtUPDATED': jour,
          'heure': heure,
          'strTYPEVENTE': type == '1' ? 'VNO' : 'VO',
          'lgTYPEVENTEID': type,
          'cancel': false,
          'posteSaisie': poste,
          'posteEncaissement': poste,
          'clientFullName': type == '1' ? '' : 'CLIENT FICTIF',
        };
    final data = [
      v('V-5', '4721508936', '2', '17:42', 1530, 'Poste test'),
      v('V-4', '4721508801', '3', '16:20', 8200, 'Poste test'),
      v('V-3', '4721508710', '1', '15:05', 2410, 'Poste test'),
      v('V-2', '4721508655', '2', '11:31', 12650, 'CAISSE 2'),
      v('V-1', '4721508502', '1', '09:12', 650, 'Poste test'),
    ];
    return ResponseBody.fromString(jsonEncode({'total': data.length, 'data': data}), 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _capture(WidgetTester t, String nom) => capturerFidele(t, find.byType(MaterialApp).first, Uri.file('$_base/$nom.png'));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    if (_actif) await chargerPolicesReelles();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VentesDuTerminal.reinitialiser();
    ImpressionTicket.reinitialiser();
  });

  Future<SettingsProvider> monter(WidgetTester t, Widget ecran) async {
    TailleEcran.sunmiV3.appliquer(t);
    final s = SettingsProvider();
    await s.loadSettings();
    await t.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(value: s, child: MaterialApp(debugShowCheckedModeBanner: false, home: ecran)));
    await t.pumpAndSettle();
    return s;
  }

  testWidgets('réédition des ventes — SUNMI V3', (t) async {
    if (!_actif) return markTestSkipped('CAPTURES non défini');
    await monter(t, ReeditionVentesScreen(dio: Dio()..httpClientAdapter = _Liste()));
    await _capture(t, '1_reedition_ce_terminal_sunmi_v3');
    await t.tap(find.text('Tous les postes'));
    await t.pumpAndSettle();
    await _capture(t, '2_reedition_tous_les_postes_sunmi_v3');
    await t.tap(find.text('Ce terminal'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('reedition-reimprimer-V-5')));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Plus de copies'));
    await t.pumpAndSettle();
    await _capture(t, '3_reimprimer_exemplaires_sunmi_v3');
    await t.tap(find.text('Ne pas imprimer'));
    await t.pumpAndSettle();
  });

  testWidgets('question « Ticket suivant (2/2) » — SUNMI V3', (t) async {
    if (!_actif) return markTestSkipped('CAPTURES non défini');
    await monter(t, Builder(builder: (c) => Scaffold(appBar: AppBar(title: const Text('Vente assurance')), body: Center(child: ElevatedButton(onPressed: () => confirmerTicketSuivant(c, 2, 2), child: const Text('go'))))));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await _capture(t, '4_ticket_suivant_2_sur_2_sunmi_v3');
  });

  testWidgets('Réglages › Impression, contraste — SUNMI V3', (t) async {
    if (!_actif) return markTestSkipped('CAPTURES non défini');
    await monter(t, ImpressionPage(printTest: (_) async {}));
    await t.ensureVisible(find.text('CONTRASTE D\'IMPRESSION'));
    await t.pumpAndSettle();
    await _capture(t, '5_reglage_contraste_sunmi_v3');
  });
}
