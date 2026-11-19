// PERFORMANCE — 4.15.0 : demande 62, données FICTIVES :
//  - liste de 5 000 préventes dont la moitié payées : lue en moins de 300 ms ;
//  - reprise d'une prévente payée (application entière) : MÊMES requêtes qu'une prévente non payée (le paiement
//    arrive avec GET ventestats/{id}, aucune requête de plus) ; « TERMINER LA VENTE » : UNE seule clôture.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import '../demande62_test.dart' show venteFictivePayee;
import '../outils/app_e2e.dart';
import '../outils/clients_vente_fictifs.dart';
import '../outils/demande62_fictive.dart';
import '../outils/parcours_vente.dart';

void main() {
  test('5 000 préventes (moitié payées) lues en moins de 300 ms', () {
    final rows = [
      for (var i = 0; i < 5000; i++)
        {
          if (i.isEven) ...venteFictivePayee(montant: 1000 + i),
          'lgPREENREGISTREMENTID': 'V$i',
          'heure': '10:42:00',
          'dtUPDATED': '19/11/2026',
          'intPRICE': 1000 + i,
          'strREF': 'REF-$i',
          'userFullName': 'Vendeur Fictif',
          'lgTYPEVENTEID': '1',
        }
    ];
    final sw = Stopwatch()..start();
    final l = [for (final r in rows) PreventeListItem.fromJson(r)];
    final colonnes = [for (final p in l) p.paiementMobile?.colonne];
    sw.stop();
    expect(colonnes.whereType<String>(), hasLength(2500));
    expect(sw.elapsedMilliseconds, lessThan(300));
  });

  testWidgets('reprise d\'une prévente payée : aucune requête de plus ; terminer : une seule clôture', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = AppE2E();
    CatalogueFictif(app.serveur, nombre: 5);
    ClientsVenteFictifs(app.serveur);
    final d = Demande62Fictive(app.serveur);
    await app.preparer(prefs: prefsVente);
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    final payee = d.preventeDeLaBorne();
    final autre = d.preventeDeLaBorne(payee: false);

    Future<List<String>> reprendre(String id) async {
      await t.tap(find.byTooltip('Préventes à encaisser').first);
      expect(await app.attendreQue(t, find.text('REF-$id')), isTrue);
      await app.attendre(t, const Duration(milliseconds: 600));
      final avant = app.serveur.recues.length;
      await t.tap(find.text('REF-$id'));
      await app.attendre(t, const Duration(seconds: 1));
      // Panier précédent ouvert : « Ouvrir … sans l'enregistrer ».
      final sans = find.textContaining('sans l\'enregistrer');
      if (sans.evaluate().isNotEmpty) {
        await t.tap(sans.first);
        await app.attendre(t, const Duration(seconds: 2));
      } else {
        await app.attendre(t, const Duration(seconds: 1));
      }
      return app.serveur.recues.skip(avant).map((r) => r.chemin.split('/v1').last).toList()..sort();
    }

    final reqAutre = await reprendre(autre);
    final reqPayee = await reprendre(payee);
    expect(reqPayee.map((c) => c.replaceAll(payee, 'ID')).toList(), reqAutre.map((c) => c.replaceAll(autre, 'ID')).toList(),
        reason: 'mêmes requêtes : $reqPayee');
    expect(find.byKey(const ValueKey('prevente-payee-bandeau')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('vente-encaisser')));
    await app.attendre(t, const Duration(seconds: 1));
    final imprimer = find.byKey(const ValueKey('encaissement-imprimer'));
    await app.defilerJusqua(t, imprimer, zone: find.byType(Scrollable).last);
    await t.tap(imprimer);
    await t.pump();
    final avant = app.serveur.recues.length;
    await t.tap(find.byKey(const ValueKey('encaissement-valider')));
    await app.attendre(t, const Duration(seconds: 2));
    expect(app.serveur.recues.skip(avant).where((r) => r.chemin.endsWith('/vente/cloturer/vno')), hasLength(1));
    expect(d.clotures, hasLength(1));
    await app.fermer(t);
  });
}
