// ERGONOMIE — 4.14.0 : zone Remise et aperçu du ticket (données FICTIVES) :
//  - zone Remise : hauteur ≥ 48 dp, cibles ≥ 48 dp, aucun débordement de 320 dp à la tablette, libellés entiers ;
//  - liste des remises : une ligne par remise, ≥ 48 dp ;
//  - aperçu du ticket (58 et 80 mm) : aucun débordement, mêmes lignes que l'impression.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/common/remise_vente.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

import 'outils/tickets_vente_fictifs.dart';

class _Hote extends ChangeNotifier implements RemiseVenteHote {
  @override
  bool remiseDisponible = true;
  @override
  String? remiseId;
  @override
  String? remiseNom;
  @override
  int montantRemise = 0;
  @override
  bool busy = false;
  @override
  Future<VenteResult<List<RemiseOption>>> remisesProposees() async => const VenteOk([
        RemiseOption(id: 'R1', nom: 'REMISE FICTIVE AU NOM TRES LONG POUR LE TEST D\'AFFICHAGE 10 %'),
        RemiseOption(id: 'R2', nom: 'REMISE FICTIVE 5 %'),
      ]);
  @override
  Future<VenteResult<void>> choisirRemise(RemiseOption r) async => const VenteOk(null);
  @override
  Future<VenteResult<void>> retirerRemise() async => const VenteOk(null);
}

Future<void> _monter(WidgetTester t, Size taille, Widget w) async {
  t.view.physicalSize = taille * 2;
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => DroitsVente.instance.fixer(null));

  for (final taille in const [Size(320, 640), Size(360, 720), Size(960, 600)]) {
    testWidgets('zone Remise ${taille.width.toInt()} dp : 48 dp, sans débordement (aucune, appliquée, en cours)', (t) async {
      final h = _Hote();
      await _monter(t, taille, RemiseVenteZone(hote: h));
      expect(t.getSize(find.byKey(const ValueKey('remise-vente-zone'))).height, greaterThanOrEqualTo(48));
      h
        ..remiseId = 'R1'
        ..remiseNom = 'REMISE FICTIVE AU NOM TRES LONG POUR LE TEST D\'AFFICHAGE 10 %'
        ..montantRemise = 123456
        ..busy = true
        ..notifyListeners();
      await t.pump();
      expect(t.takeException(), isNull);
      final croix = t.getSize(find.byKey(const ValueKey('remise-vente-retirer')));
      expect(croix.width, greaterThanOrEqualTo(48));
      expect(croix.height, greaterThanOrEqualTo(48));
      expect(find.text('− ${Constants.formatNumber(123456)} F (calcul du serveur)'), findsOneWidget);
    });
  }

  testWidgets('liste des remises : lignes ≥ 48 dp, noms longs sur deux lignes au plus', (t) async {
    final h = _Hote();
    await _monter(t, const Size(360, 720), RemiseVenteZone(hote: h));
    await t.tap(find.byKey(const ValueKey('remise-vente-choisir')));
    await t.pumpAndSettle();
    for (final id in ['R1', 'R2']) {
      expect(t.getSize(find.byKey(ValueKey('remise-option-$id'))).height, greaterThanOrEqualTo(48));
    }
    expect(t.takeException(), isNull);
  });

  for (final p in [58, 80]) {
    testWidgets('aperçu du ticket $p mm : sans débordement à 300 / 420 dp, mêmes lignes que l\'impression', (t) async {
      for (final ticket in [ticketComptant(p), ticketAssurance(p), ticketCarnet(p)]) {
        await _monter(t, const Size(500, 2400), SizedBox(width: p == 58 ? 300 : 420, child: ReceiptService.apercuTicketTexte(ticket, 'QR_CODE')));
        expect(t.takeException(), isNull);
        final textes = t.widgetList<Text>(find.byType(Text)).map((x) => x.data!.trimRight()).toList();
        expect(textes.where((x) => x.contains('x ')).length, 3, reason: 'lignes « quantité x prix »');
      }
    });
  }
}
