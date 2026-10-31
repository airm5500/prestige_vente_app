// PrestigePOS — ergonomie de l'application entière sur les appareils visés : tablette paysage et portrait, borne
// verticale 1080 × 1920, terminaux Sunmi V2s / V3 ; texte ×1,0 et ×1,3. Pour chaque écran (accueil du premier
// lancement, assistant : serveur et imprimante, borne : accueil, résultats, panier, ticket, administration) :
// aucun débordement ni erreur de rendu, cibles tactiles ≥ 48 dp (de l'interface : Compact automatique des petits
// écrans, docs/TAILLE_ECRAN.md), contraste du texte suffisant.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../outils/ergonomie.dart' show ciblesTactiles, facteurEcran;
import 'outils/pos_e2e.dart';
import 'pos_e2e_test.dart' show attendreBorne;

class Appareil {
  final String nom;
  final Size pixels;
  final double densite;
  const Appareil(this.nom, this.pixels, this.densite);
}

const appareils = [
  Appareil('tablette paysage 1920×1200', Size(1920, 1200), 1.5),
  Appareil('tablette portrait 1200×1920', Size(1200, 1920), 1.5),
  Appareil('borne verticale 1080×1920', Size(1080, 1920), 1.0),
  Appareil('Sunmi V2s 720×1440', Size(720, 1440), 2.0),
  Appareil('Sunmi V3 1080×1920', Size(1080, 1920), 2.625),
];

/// Contrôles d'un écran ; tous les échecs rapportés ensemble.
Future<void> controler(WidgetTester t, String ecran) async {
  final facteur = facteurEcran(t);
  final ctx = '$ecran — ${t.view.physicalSize.width.toInt()}×${t.view.physicalSize.height.toInt()} '
      'texte ×${t.platformDispatcher.textScaleFactor}${facteur == 1.0 ? '' : ', interface ×$facteur'}';
  final echecs = <String>[];
  Future<void> c(String nom, Future<void> Function() f) async {
    try {
      await f();
    } on TestFailure catch (x) {
      echecs.add('[$nom] ${x.message}');
    }
  }

  await c('rendu', () async => expect(t.takeException(), isNull, reason: '$ctx : erreur de rendu (débordement…)'));
  final h = t.ensureSemantics();
  await c('cibles', () => expectLater(t, meetsGuideline(ciblesTactiles(facteur)), reason: '$ctx : cibles tactiles'));
  await c('contraste', () => expectLater(t, meetsGuideline(textContrastGuideline), reason: '$ctx : contraste'));
  h.dispose();
  if (echecs.isNotEmpty) fail(echecs.join('\n\n'));
}

void main() {
  for (final a in appareils) {
    for (final texte in [1.0, 1.3]) {
      testWidgets('${a.nom}, texte ×$texte : premier lancement et assistant', (t) async {
        t.view.physicalSize = a.pixels;
        t.view.devicePixelRatio = a.densite;
        t.platformDispatcher.textScaleFactorTestValue = texte;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final app = PosE2E();
        await app.preparer();
        await app.lancer(t);
        expect(await app.attendreQue(t, find.byKey(const ValueKey('pos-bienvenue'))), isTrue);
        await controler(t, 'Bienvenue');
        await app.toucher(t, 'pos-configurer');
        await app.saisirCode(t);
        await controler(t, 'Assistant › Serveur');
        await app.saisir(t, 'pos-serveur-adresse', FauxServeurPrestige.hoteMemoire);
        await app.toucher(t, 'pos-serveur-verifier');
        await app.attendre(t);
        await app.saisir(t, 'pos-borne-login', loginBorne);
        await app.saisir(t, 'pos-borne-mdp', mdpBorne);
        FocusManager.instance.primaryFocus?.unfocus();
        await app.toucher(t, 'pos-borne-tester');
        await app.attendre(t);
        await controler(t, 'Assistant › Utilisateur borne (test)');
        await app.toucher(t, 'pos-suivant');
        await app.toucher(t, 'pos-suivant');
        await app.toucher(t, 'imp-type-bluetooth');
        await app.toucher(t, 'imp-bt-rechercher');
        await app.attendre(t, const Duration(seconds: 1));
        await controler(t, 'Assistant › Imprimante (recherche Bluetooth)');
        await app.fermer(t);
      });

      testWidgets('${a.nom}, texte ×$texte : borne (accueil, résultats, panier, ticket) et administration', (t) async {
        t.view.physicalSize = a.pixels;
        t.view.devicePixelRatio = a.densite;
        t.platformDispatcher.textScaleFactorTestValue = texte;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final app = PosE2E();
        await app.preparer(configure: true);
        await app.lancer(t);
        await attendreBorne(t, app);
        await controler(t, 'Borne › Accueil (Vitrine)');
        await app.chercher(t, 'doli');
        FocusManager.instance.primaryFocus?.unfocus();
        await app.attendre(t, const Duration(milliseconds: 500));
        await controler(t, 'Borne › Résultats');
        await app.toucher(t, 'borne-ajouter-F1');
        await app.attendre(t, const Duration(milliseconds: 2600));
        if (find.byKey(const ValueKey('borne-voir-panier')).evaluate().isNotEmpty) {
          await app.toucher(t, 'borne-voir-panier');
        } else {
          await app.toucher(t, 'borne-panier-lateral-payer');
        }
        await controler(t, 'Borne › Panier');
        await app.toucher(t, 'borne-payer');
        expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-numero'))), isTrue);
        await controler(t, 'Borne › Ticket');
        await app.toucher(t, 'borne-termine');
        await app.quitterBorne(t);
        await controler(t, 'Administration');
        await app.fermer(t);
      });
    }
  }

  // 1.8.1 (retour du pharmacien du 31/10 : « les icônes sont coupées par le bas ») : Sunmi V2s avec la « Taille de
  // l'affichage » d'Android agrandie (densité 2,25 à 2,75) : accueil de la borne sans débordement, tuiles « Catégories »
  // entières (pictogramme et libellé dans la tuile).
  for (final (densite, texte) in const [(2.25, 1.0), (2.25, 1.3), (2.5, 1.0), (2.75, 1.0)]) {
    testWidgets('Sunmi V2s densité $densite, texte ×$texte : accueil de la borne, tuiles de catégorie entières', (t) async {
      t.view.physicalSize = const Size(720, 1440);
      t.view.devicePixelRatio = densite;
      t.platformDispatcher.textScaleFactorTestValue = texte;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final app = PosE2E();
      await app.preparer(configure: true);
      await app.lancer(t);
      await attendreBorne(t, app);
      expect(t.takeException(), isNull, reason: 'aucun débordement');
      final tuile = find.byKey(const ValueKey('borne-categorie-Douleur'));
      await t.ensureVisible(tuile);
      await t.pump();
      final r = t.getRect(tuile);
      for (final x in [find.byType(Icon), find.text('Douleur')]) {
        final e = t.getRect(find.descendant(of: tuile, matching: x));
        expect(e.top >= r.top - 0.5 && e.bottom <= r.bottom + 0.5, isTrue, reason: '$e hors de la tuile $r');
      }
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }
}
