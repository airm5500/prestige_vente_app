// ERGONOMIE — Prestige Pointage, application ENTIÈRE (PrestigePointageApp → RacineTailleEcran → MaterialApp), sur le
// Sunmi V2s (720×1440), un téléphone 360×640 dp, un téléphone 1080×2400 et une tablette, texte ×1 / ×1,3 / ×2 :
//  - assistant d'enrôlement (serveur, compte de l'administrateur) ;
//  - borne avec un bandeau d'état (« Appareil retiré ») ;
//  - administration de la borne ;
// aucun débordement ni exception ; champ du badge et boutons principaux visibles et touchables (≥ 48 dp de haut).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/prestigepointage/pointage_app.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart' as ecran;

import '../outils/app_e2e.dart' show TailleEcran;
import 'outils/pointage_e2e.dart';

void main() {
  const tailles = [TailleEcran.sunmiV2s, TailleEcran.telephone, TailleEcran.telephone360x800, TailleEcran.tablette];
  const echelles = [1.0, 1.3, 2.0];

  void toucheable(WidgetTester t, Finder f, String contexte) {
    expect(f, findsOneWidget, reason: contexte);
    final r = t.getRect(f);
    final reel = t.view.physicalSize / t.view.devicePixelRatio;
    // 48 dp DE L'INTERFACE (Compact automatique des petits écrans : 48 × facteur dp réels, comme Prestige Mobile).
    final k = ecran.TailleEcranReglage.effective(ecran.TailleEcranReglage.active.value, reel).facteur;
    expect(r.height, greaterThanOrEqualTo(48 * k - 0.1), reason: '$contexte : cible de ${r.height} dp (facteur $k)');
    expect(r.left >= -0.5 && r.right <= reel.width + 0.5 && r.top >= -0.5 && r.bottom <= reel.height + 0.5, isTrue, reason: '$contexte : coupé ($r)');
  }

  /// Fait défiler l'écran [ecranCle] jusqu'à [f] (listes construites à la demande), puis l'amène à l'écran.
  Future<void> montrer(WidgetTester t, Finder f, String ecranCle) async {
    await t.scrollUntilVisible(f, 120, scrollable: find.descendant(of: find.byKey(Key(ecranCle)), matching: find.byType(Scrollable)).first);
    await t.ensureVisible(f);
    await t.pump();
  }

  for (final taille in tailles) {
    for (final echelle in echelles) {
      testWidgets('$taille, texte ×$echelle : assistant, borne (bandeau), administration', (t) async {
        taille.appliquer(t);
        t.platformDispatcher.textScaleFactorTestValue = echelle;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final ctx = '$taille ×$echelle';

        // Assistant (premier lancement).
        final a = PointageE2E();
        await a.preparer(configure: true);
        await a.lancer(t);
        await a.attendre(t, const Duration(milliseconds: 500));
        expect(t.takeException(), isNull, reason: '$ctx assistant');
        await montrer(t, find.byKey(const Key('pointage_serveur_suivant')), 'pointage_assistant');
        toucheable(t, find.byKey(const Key('pointage_serveur_suivant')), '$ctx serveur');
        await t.tap(find.byKey(const Key('pointage_serveur_suivant')));
        expect(await a.attendreQue(t, find.byKey(const Key('pointage_admin_login'))), isTrue, reason: ctx);
        await montrer(t, find.byKey(const Key('pointage_enroler')), 'pointage_assistant');
        toucheable(t, find.byKey(const Key('pointage_enroler')), '$ctx enrôler');
        expect(t.takeException(), isNull, reason: '$ctx compte');
        await a.fermer(t);

        // Borne : bandeau d'état puis administration.
        final b = PointageE2E();
        await b.preparer(configure: true);
        final i = await b.enrolerDirectement();
        await b.lancer(t);
        expect(await b.attendreQue(t, find.byKey(const Key('rh_badge_champ'))), isTrue, reason: ctx);
        await b.attendre(t);
        b.bornes.retirer(i.borneId);
        await b.fini(t, PointageApp.controleur.verifier());
        await t.pump();
        expect(find.byKey(const Key('pointage_bandeau_revoquee')), findsOneWidget, reason: ctx);
        expect(t.takeException(), isNull, reason: '$ctx borne');
        toucheable(t, find.byKey(const Key('pointage_admin')), '$ctx administration');
        await montrer(t, find.byKey(const Key('rh_badge_champ')), 'rh_terminal');
        expect(t.getRect(find.byKey(const Key('rh_badge_champ'))).width, greaterThan(150), reason: '$ctx champ du badge');
        await t.tap(find.byKey(const Key('pointage_admin')));
        expect(await b.attendreQue(t, find.byKey(const Key('pointage_administration'))), isTrue, reason: ctx);
        await b.attendre(t, const Duration(milliseconds: 500));
        expect(t.takeException(), isNull, reason: '$ctx administration');
        await montrer(t, find.byKey(const Key('pointage_admin_verifier')), 'pointage_administration');
        toucheable(t, find.byKey(const Key('pointage_admin_verifier')), '$ctx vérifier');
        await b.fermer(t);
      });
    }
  }
}
