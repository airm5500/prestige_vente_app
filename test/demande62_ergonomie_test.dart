// ERGONOMIE — 4.15.0 : demande 62, données FICTIVES :
//  - bandeau « Déjà payée par … » : aucun débordement de 320 dp à la tablette, texte ×1.3, numéro long ;
//  - encaissement d'une prévente payée : mode imposé lisible, bouton « TERMINER LA VENTE » ≥ 48 dp, aucun
//    débordement (net égal, augmenté avec complément, diminué) ;
//  - liste des préventes : badge « Payée Wave … » sans débordement à 320 dp.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/paiements/prevente_payee.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/encaissement_page.dart';
import 'package:prestige_vente_app/ventes/prevente/prevente_list.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'demande62_test.dart' show venteFictivePayee;

const _tailles = [Size(320, 640), Size(360, 720), Size(960, 600)];

PreventePayee _payee({String reference = 'TX-FICT-0042'}) {
  final v = venteFictivePayee();
  (v['paiementMobile'] as Map)['referenceFournisseur'] = reference;
  return PreventePayee.depuisVente(v)!;
}

void _taille(WidgetTester t, Size s) {
  t.view.physicalSize = s * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
}

Future<void> _page(WidgetTester t, Size s, {int net = 4125, double texte = 1.0}) async {
  _taille(t, s);
  SharedPreferences.setMockInitialValues({'enabled_payment_method_ids': ['1', '10']});
  final settings = SettingsProvider();
  await settings.loadSettings();
  await t.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
    value: settings,
    child: MaterialApp(
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(texte)), child: w!),
      home: EncaissementPage(
        actions: EncaissementActions(
          paymentMethods: () async =>
              VenteOk([PaymentMethod(id: '1', name: 'Espèces'), PaymentMethod(id: '7', name: 'ORANGE MONEY'), PaymentMethod(id: '10', name: 'WAVE')]),
          loadQrMethods: () async {},
          qrFor: (_) => null,
          encaisser: (m, r, x) async => const VenteOk((dejaCloturee: false)),
          encaisserReglements: (l, r, x) async => const VenteOk((dejaCloturee: false)),
        ),
        expectedChanges: 1,
        summary: SaleSummary(montant: net, montantNet: net, reference: 'REF-FICT-0001', venteId: 'V-FICT-1'),
        itemCount: 3,
        presentation: ListPresentation.dashboard,
        initialCopies: 1,
        dejaPayee: _payee(),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => DroitsVente.instance.fixer(null));
  tearDown(() => DroitsVente.instance.oublier());

  for (final s in _tailles) {
    for (final texte in [1.0, 1.3]) {
      testWidgets('bandeau ${s.width.toInt()} dp, texte ×$texte : sans débordement (net égal, augmenté, diminué ; numéro long)', (t) async {
        _taille(t, s);
        for (final net in [4125, 5000, 3000]) {
          await t.pumpWidget(MaterialApp(
            builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(texte)), child: w!),
            home: Scaffold(
                body: SingleChildScrollView(
                    child: PreventePayeeBandeau(payee: _payee(reference: 'TX-FICT-${'9' * 40}'), net: net))),
          ));
          await t.pump();
          expect(t.takeException(), isNull);
          expect(find.byKey(const ValueKey('prevente-payee-consigne')), findsOneWidget);
        }
      });
    }

    testWidgets('encaissement d\'une prévente payée ${s.width.toInt()} dp : bouton ≥ 48 dp, mode imposé, sans débordement', (t) async {
      for (final net in [4125, 5000, 3000]) {
        await _page(t, s, net: net);
        expect(t.takeException(), isNull);
        expect(t.getSize(find.byKey(const ValueKey('encaissement-valider'))).height, greaterThanOrEqualTo(48));
        expect(find.text('TERMINER LA VENTE'), findsOneWidget);
        final mode = find.byKey(const ValueKey('mode-impose-10'));
        await t.scrollUntilVisible(mode, 80, scrollable: find.descendant(of: find.byKey(const ValueKey('encaissement-payee')), matching: find.byType(Scrollable)).first);
        expect(mode, findsOneWidget);
        expect(t.takeException(), isNull);
      }
    });
  }

  testWidgets('encaissement d\'une prévente payée, texte ×1.3 (Sunmi V2s) : sans débordement', (t) async {
    await _page(t, const Size(360, 720), net: 5000, texte: 1.3);
    expect(t.takeException(), isNull);
  });

  testWidgets('liste des préventes 320 dp : badge « Payée Wave … » sans débordement', (t) async {
    _taille(t, const Size(320, 640));
    SharedPreferences.setMockInitialValues({});
    final ligne = {
      ...venteFictivePayee(montant: 1234567),
      'lgPREENREGISTREMENTID': 'V-A',
      'heure': '10:42:00',
      'dtUPDATED': '19/11/2026',
      'intPRICE': 1234567,
      'strREF': 'REF-FICT-TRES-LONGUE-0001',
      'userFullName': 'Vendeur Fictif Au Nom Long',
      'lgTYPEVENTEID': '1',
    };
    for (final style in ListPresentation.values) {
      await t.pumpWidget(MaterialApp(
        home: PreventeListScreen(load: () async => VenteOk([PreventeListItem.fromJson(ligne)]), onSelect: (_) async => true, presentation: style),
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '$style');
      expect(find.byKey(const ValueKey('prevente-payee-V-A')), findsOneWidget);
    }
  });
}
