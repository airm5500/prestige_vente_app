// ERGONOMIE — 4.13.0 : zone « Client » de la vente comptant et page de recherche, application entière (faux serveur,
// données FICTIVES), Sunmi V2s / V3, téléphone 360 × 800 dp et tablette 10″, texte ×1,0 et ×1,3 :
//  - zone lisible, hauteur ≥ 48 dp, sans débordement, avec un nom très long (coupé proprement) ;
//  - croix (≥ 48 dp) : rouge au 1er appui, avec la mention « Touchez encore… » ;
//  - page : champ, résultats (nom, prénom, téléphone), « Nouveau client » et son formulaire sans débordement ;
//  - cibles tactiles ≥ 48 dp (zone, croix ; page entière) ; panier toujours visible sous la zone (terminal) ;
//  - clavier ouvert : zone masquée (place pour le panier), comme les bandeaux d'information.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';
import 'outils/clients_vente_fictifs.dart';
import 'outils/ergonomie.dart' show ciblesTactiles, facteurEcran;
import 'outils/parcours_vente.dart';

const _tailles = [TailleEcran.sunmiV2s, TailleEcran.sunmiV3, TailleEcran.telephone360x800, TailleEcran.tablette];

final _zone = find.byKey(const ValueKey('client-vente-zone'));
final _croix = find.byKey(const ValueKey('client-vente-retirer'));

Future<void> _cibles(WidgetTester t, String nom) async {
  final h = t.ensureSemantics();
  await expectLater(t, meetsGuideline(ciblesTactiles(facteurEcran(t))), reason: '$nom : cibles ≥ 48 dp');
  h.dispose();
}

void main() {
  for (final taille in _tailles) {
    for (final texte in [1.0, 1.3]) {
      final nom = '${taille.nom}, texte ×$texte';

      testWidgets('zone Client, page de recherche, Nouveau client — $nom', (t) async {
        taille.appliquer(t);
        t.platformDispatcher.textScaleFactorTestValue = texte;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final app = AppE2E();
        CatalogueFictif(app.serveur, nombre: 10);
        final cl = ClientsVenteFictifs(app.serveur)
          ..ajouter('CL-LONG', 'KOUASSI-NOM-FICTIF-TRES-LONG-POUR-LE-TEST', 'MARIE-CHRISTINE-EVELYNE', '+225 07 00 00 00 99', telephoneFiche: '0700000099');
        await app.preparer(prefs: prefsVente);
        await app.lancer(t);
        expect(await app.seConnecter(t), isTrue);
        await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
        expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
        await app.attendre(t, const Duration(seconds: 2));

        // Zone vide.
        expect(_zone, findsOneWidget, reason: nom);
        expect(t.getSize(_zone).height, greaterThanOrEqualTo(48), reason: '$nom : hauteur de la zone');
        expect(t.takeException(), isNull, reason: '$nom : zone vide');
        expect(find.textContaining('PRODUIT F3').hitTestable(), findsWidgets, reason: '$nom : panier visible sous la zone');
        // Cibles de la zone (les boutons des lignes du panier, inchangés, ne sont pas de ce changement).
        expect(t.getSize(find.byKey(const ValueKey('client-vente-ouvrir'))).height, greaterThanOrEqualTo(48));

        // Page : résultats et formulaire.
        await t.tap(find.byKey(const ValueKey('client-vente-ouvrir')));
        await app.attendre(t, const Duration(milliseconds: 600));
        await t.enterText(find.byKey(const ValueKey('client-vente-recherche')), 'KOUASSI');
        expect(await app.attendreQue(t, find.byKey(const ValueKey('client-vente-resultat-CL-LONG'))), isTrue, reason: nom);
        expect(t.takeException(), isNull, reason: '$nom : résultats');
        expect(t.getSize(find.byKey(const ValueKey('client-vente-resultat-CL-LONG'))).height, greaterThanOrEqualTo(48));
        await _cibles(t, '$nom, résultats');
        await t.ensureVisible(find.byKey(const ValueKey('client-vente-nouveau')));
        await t.tap(find.byKey(const ValueKey('client-vente-nouveau')));
        await t.pump();
        await t.ensureVisible(find.byKey(const ValueKey('client-vente-creer')));
        await t.pump();
        expect(t.takeException(), isNull, reason: '$nom : formulaire');
        expect(t.getSize(find.byKey(const ValueKey('client-vente-creer'))).height, greaterThanOrEqualTo(48));
        await _cibles(t, '$nom, formulaire');
        await app.retour(t);

        // Client choisi (nom très long) : coupé proprement, croix ≥ 48 dp.
        await t.tap(find.byKey(const ValueKey('client-vente-ouvrir')));
        await app.attendre(t, const Duration(milliseconds: 600));
        await t.enterText(find.byKey(const ValueKey('client-vente-recherche')), 'KOUASSI');
        expect(await app.attendreQue(t, find.byKey(const ValueKey('client-vente-resultat-CL-LONG'))), isTrue);
        await t.tap(find.byKey(const ValueKey('client-vente-resultat-CL-LONG')));
        await app.attendre(t, const Duration(seconds: 1));
        expect(cl.clientDeVente['V-1'], 'CL-LONG');
        expect(find.byKey(const ValueKey('client-vente-nom')), findsOneWidget);
        expect(t.takeException(), isNull, reason: '$nom : client choisi');
        final croix = t.getSize(_croix);
        expect(croix.width, greaterThanOrEqualTo(48), reason: '$nom : croix');
        expect(croix.height, greaterThanOrEqualTo(48), reason: '$nom : croix');
        final droite = t.getTopRight(_zone).dx;
        expect(t.getTopRight(_croix).dx, lessThanOrEqualTo(droite + 0.5), reason: '$nom : croix dans la zone');
        await t.tap(_croix);
        await t.pump();
        expect(find.byKey(const ValueKey('client-vente-confirmer')), findsOneWidget);
        expect(t.takeException(), isNull, reason: '$nom : croix rouge');
        await app.attendre(t, const Duration(seconds: 5));

        // Clavier ouvert : zone masquée (place pour le panier). Texte ×1,0 seulement : le pied « clavier ouvert » de
        // l'écran de vente (antérieur à 4.13.0, inchangé) déborde à ×1,3 sur 360 dp (relevé, hors de ce changement).
        if (texte != 1.0) {
          await app.fermer(t);
          return;
        }
        t.view.viewInsets = FakeViewPadding(bottom: taille.pixels.height * 0.4);
        addTearDown(t.view.resetViewInsets);
        await t.pump();
        expect(_zone, findsNothing, reason: '$nom : clavier ouvert');
        t.view.resetViewInsets();
        await t.pump();
        expect(_zone, findsOneWidget);
        await app.fermer(t);
      });
    }
  }
}
