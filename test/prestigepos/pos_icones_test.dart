// PrestigePOS 1.9.0 — Prestige Mobile 4.11.0 agrandit les icônes de SES écrans sur tablette et terminal (plan du
// pharmacien du 08/11, lib/ui/icones.dart). PrestigePOS n'est PAS concerné : l'écran CLIENT de la borne garde la mise
// en page réglée en 1.8.1 (SansEchelleIcones) et l'administration de PrestigePOS ne passe pas par ce thème.
// Application entière contre le faux serveur, borne configurée, données FICTIVES : tablette portrait et Sunmi V2s,
// aucune icône par défaut agrandie (24 dp), aucune erreur de rendu.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'outils/pos_e2e.dart';
import 'pos_e2e_test.dart' show attendreBorne;

void main() {
  for (final (nom, taille, densite) in [('tablette portrait', const Size(1200, 1920), 1.5), ('Sunmi V2s', const Size(720, 1440), 2.0)]) {
    testWidgets('borne et administration : tailles d\'icônes d\'origine — $nom', (t) async {
      t.view.physicalSize = taille;
      t.view.devicePixelRatio = densite;
      addTearDown(t.view.reset);
      final app = PosE2E();
      await app.preparer(configure: true);
      await app.lancer(t);
      await attendreBorne(t, app);
      final borne = find.byKey(const ValueKey('borne-recherche'));
      expect(IconTheme.of(t.element(borne)).size ?? 24, 24, reason: 'borne : thème d\'icônes d\'origine');
      expect(t.takeException(), isNull);
      await app.quitterBorne(t);
      final entree = find.byKey(const ValueKey('pos-admin-mobile-money'));
      if (entree.evaluate().isEmpty) await t.scrollUntilVisible(entree, 200, scrollable: find.byType(Scrollable).first);
      expect(IconTheme.of(t.element(entree)).size ?? 24, 24, reason: 'administration : thème d\'icônes d\'origine');
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  }
}
