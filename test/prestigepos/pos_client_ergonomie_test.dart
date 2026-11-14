// PrestigePOS 1.11.0 — ERGONOMIE de la zone Client de la borne (application entière, données FICTIVES) : tablette
// paysage et portrait, borne verticale 1080 × 1920, Sunmi V2s / V3 ; texte ×1,0 et ×1,3. Panier avec la zone
// (vide, puis client choisi avec un nom très long, puis croix rouge), page « Votre nom » (résultats, nouveau client) :
// aucun débordement, cibles tactiles, contraste ; bouton « Ajouter mon nom » et croix ≥ 56 dp (gros boutons de la
// borne) ; « Payer en caisse » toujours visible.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../outils/clients_vente_fictifs.dart';
import 'outils/pos_e2e.dart';
import 'pos_e2e_test.dart' show attendreBorne;
import 'pos_ergonomie_test.dart' show appareils, controler;

void main() {
  for (final a in appareils) {
    for (final texte in [1.0, 1.3]) {
      testWidgets('${a.nom}, texte ×$texte : zone Client et page « Votre nom »', (t) async {
        t.view.physicalSize = a.pixels;
        t.view.devicePixelRatio = a.densite;
        t.platformDispatcher.textScaleFactorTestValue = texte;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final app = PosE2E();
        ClientsVenteFictifs(app.serveur).ajouter('CL-LONG', 'KOUASSI-NOM-FICTIF-TRES-LONG-POUR-LE-TEST', 'MARIE-CHRISTINE-EVELYNE', '+225 07 00 00 00 99');
        await app.preparer(configure: true);
        await app.lancer(t);
        await attendreBorne(t, app);
        await app.chercher(t, 'doli');
        await app.toucher(t, 'borne-ajouter-F1');
        await app.attendre(t, const Duration(milliseconds: 2600));
        if (find.byKey(const ValueKey('borne-voir-panier')).evaluate().isNotEmpty) {
          await app.toucher(t, 'borne-voir-panier');
        } else {
          await app.toucher(t, 'borne-panier-lateral-payer');
        }
        expect(t.getSize(find.byKey(const ValueKey('borne-client-ouvrir'))).height, greaterThanOrEqualTo(56));
        await controler(t, 'Borne › Panier, zone Client vide');
        await app.toucher(t, 'borne-client-ouvrir');
        await app.saisir(t, 'borne-client-recherche', 'KOUASSI');
        expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-client-resultat-CL-LONG'))), isTrue);
        FocusManager.instance.primaryFocus?.unfocus();
        await app.attendre(t, const Duration(milliseconds: 500));
        expect(t.getSize(find.byKey(const ValueKey('borne-client-resultat-CL-LONG'))).height, greaterThanOrEqualTo(56));
        await controler(t, 'Borne › Votre nom, résultats');
        await app.toucher(t, 'borne-client-nouveau');
        FocusManager.instance.primaryFocus?.unfocus();
        await app.attendre(t, const Duration(milliseconds: 300));
        await controler(t, 'Borne › Votre nom, nouveau client');
        await app.toucher(t, 'borne-client-retour');
        await app.toucher(t, 'borne-client-ouvrir');
        await app.saisir(t, 'borne-client-recherche', 'KOUASSI');
        expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-client-resultat-CL-LONG'))), isTrue);
        await app.toucher(t, 'borne-client-resultat-CL-LONG');
        FocusManager.instance.primaryFocus?.unfocus();
        await app.attendre(t, const Duration(milliseconds: 300));
        final croix = t.getSize(find.byKey(const ValueKey('borne-client-retirer')));
        expect(croix.height, greaterThanOrEqualTo(56));
        expect(croix.width, greaterThanOrEqualTo(56));
        await controler(t, 'Borne › Panier, client choisi');
        await t.tap(find.byKey(const ValueKey('borne-client-retirer')));
        await t.pump();
        await controler(t, 'Borne › Panier, croix rouge');
        expect(find.byKey(const ValueKey('borne-payer')).hitTestable(), findsOneWidget, reason: '« Payer en caisse » visible');
        await app.attendre(t, const Duration(seconds: 5));
        await app.fermer(t);
      });
    }
  }
}
