// ERGONOMIE — 5.4.0 : écran « Réédition des ventes » et réglage « Contraste d'impression » sur un SUNMI V3 / V2s
// (320 et 360 dp), une tablette, texte ×1,0 et ×1,3 : aucun débordement, filtres et « Réimprimer » visibles et
// touchables (48 dp au moins), numéro de ticket lisible ; question « Ticket suivant (2/2) » lisible. Données FICTIVES.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/impression_ticket.dart';
import 'package:prestige_vente_app/ventes/common/copies_ticket.dart';
import 'package:prestige_vente_app/ventes/reedition/reedition_ventes_screen.dart';
import 'package:prestige_vente_app/ventes/reedition/ventes_du_terminal.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Liste implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    final jour = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final data = [
      for (final (i, type) in [(1, '1'), (2, '2'), (3, '3'), (4, '2')])
        {
          'lgPREENREGISTREMENTID': 'V-$i',
          'strREF': 'REF-$i',
          'strREFTICKET': '520000000$i',
          'intPRICE': 125400 * i,
          'dtUPDATED': jour,
          'heure': '1$i:0$i',
          'strTYPEVENTE': type == '1' ? 'VNO' : 'VO',
          'lgTYPEVENTEID': type,
          'cancel': i == 4,
          'posteSaisie': 'Poste test',
          'posteEncaissement': 'Poste test',
          'clientFullName': 'CLIENT FICTIF AU NOM TRES LONG POUR LE TEST DE DEBORDEMENT $i',
        }
    ];
    return ResponseBody.fromString(jsonEncode({'total': data.length, 'data': data}), 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

final _tailles = [(const Size(640, 1280), 2.0, '320 dp'), (const Size(720, 1440), 2.0, '360 dp'), (const Size(1600, 2560), 2.0, 'tablette')];

Future<void> _taille(WidgetTester t, Size s, double densite, double texte) async {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = densite;
  t.platformDispatcher.textScaleFactorTestValue = texte;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

void _touchable(WidgetTester t, Finder f, String nom, {Type? bouton}) {
  expect(f.hitTestable(), findsOneWidget, reason: '$nom non touchable');
  final cible = bouton == null ? f : find.ancestor(of: f, matching: find.byType(bouton)).first;
  expect(t.getSize(cible).height, greaterThanOrEqualTo(40), reason: '$nom trop petit');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VentesDuTerminal.reinitialiser();
  });

  for (final (s, densite, nom) in _tailles) {
    for (final texte in [1.0, 1.3]) {
      testWidgets('réédition des ventes — $nom, texte ×$texte : filtres, liste et « Réimprimer » sans débordement', (t) async {
        await _taille(t, s, densite, texte);
        final settings = SettingsProvider();
        await settings.loadSettings();
        await t.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: MaterialApp(home: ReeditionVentesScreen(dio: Dio(BaseOptions(baseUrl: 'http://serveur-fictif/prestige/api/v1'))..httpClientAdapter = _Liste())),
        ));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'aucun débordement');
        _touchable(t, find.text('Ce terminal'), 'Ce terminal', bouton: SegmentedButton<PorteeReedition>);
        _touchable(t, find.text('Tous les postes'), 'Tous les postes', bouton: SegmentedButton<PorteeReedition>);
        _touchable(t, find.byKey(const ValueKey('reedition-recherche')), 'recherche');
        for (final k in ['tous', 'comptant', 'assurance', 'carnet']) {
          expect(find.byKey(ValueKey('reedition-type-$k')).hitTestable(), findsOneWidget, reason: 'type $k visible sans défiler');
        }
        expect(find.text('N° 5200000004'), findsOneWidget, reason: 'la plus récente en tête');
        expect(find.text('Annulée'), findsOneWidget);
        final b = find.byKey(const ValueKey('reedition-reimprimer-V-1'));
        await t.scrollUntilVisible(b, 120, scrollable: find.descendant(of: find.byKey(const ValueKey('reedition-liste')), matching: find.byType(Scrollable)));
        await t.pumpAndSettle();
        expect(find.text('N° 5200000001'), findsOneWidget);
        _touchable(t, b, 'Réimprimer');
        expect(t.getSize(b).height, greaterThanOrEqualTo(48));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('Réglages › Impression, contraste — $nom, texte ×1,3 : deux choix touchables, aide lisible', (t) async {
      await _taille(t, s, densite, 1.3);
      final settings = SettingsProvider();
      await settings.loadSettings();
      await t.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(value: settings, child: MaterialApp(home: ImpressionPage(printTest: (_) async {}))));
      await t.pumpAndSettle();
      final seg = find.byKey(const ValueKey('contraste-impression'));
      await t.ensureVisible(seg);
      await t.pumpAndSettle();
      _touchable(t, find.descendant(of: seg, matching: find.text('Normal')), 'Normal', bouton: InkWell);
      _touchable(t, find.descendant(of: seg, matching: find.text('Renforcé')), 'Renforcé', bouton: InkWell);
      expect(find.textContaining('Traits fins épaissis'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('question « Ticket suivant (2/2) » — $nom, texte ×1,3 : titre, consigne, boutons de 48 dp', (t) async {
      await _taille(t, s, densite, 1.3);
      ImpressionTicket.reinitialiser();
      await t.pumpWidget(MaterialApp(home: Builder(builder: (c) => Scaffold(body: Center(child: ElevatedButton(onPressed: () => confirmerTicketSuivant(c, 2, 2), child: const Text('go')))))));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text('Ticket suivant (2/2)'), findsOneWidget);
      expect(find.text('Coupez le ticket, puis imprimez le suivant.'), findsOneWidget);
      expect(t.getSize(find.byKey(const ValueKey('ticket-suivant-imprimer'))).height, greaterThanOrEqualTo(48));
      expect(t.getSize(find.byKey(const ValueKey('ticket-suivant-arreter'))).height, greaterThanOrEqualTo(48));
      expect(t.takeException(), isNull);
    });
  }
}
