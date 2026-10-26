// E2E — Prestige Mobile 4.10.0 : bouton « Pointer » sur l'écran de connexion et tuile « Pointer » de l'accueil
// (groupe Équipe), application ENTIÈRE (MyApp) et faux serveur en mémoire :
//  - Prestige Pointage installée : bouton visible AVANT toute connexion → ouvre l'application (aucune requête, la
//    session n'est pas touchée) ; après la connexion, tuile de l'accueil → ouvre l'application, session gardée ;
//  - non installée : ni bouton ni tuile ; le reste de l'accueil (23 menus) inchangé.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/prestigepointage/lanceur_pointage.dart';

import '../outils/app_e2e.dart';

void main() {
  late int ouvertures;
  setUp(() {
    LanceurPointage.reinitialiser();
    ouvertures = 0;
    LanceurPointage.ouvreur = () async {
      ouvertures++;
      return true;
    };
  });
  tearDown(LanceurPointage.reinitialiser);

  Finder texteTuile() => find.text(menuPrestigePointage.label);
  Finder tuile() => find.byKey(const ValueKey('tuile_prestige_pointage'));

  Future<bool> tuilePresente(WidgetTester t) async {
    final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    pos.jumpTo(pos.minScrollExtent);
    await t.pump();
    while (tuile().evaluate().isEmpty && texteTuile().evaluate().isEmpty && pos.pixels < pos.maxScrollExtent) {
      pos.jumpTo((pos.pixels + 250).clamp(pos.minScrollExtent, pos.maxScrollExtent));
      await t.pump();
    }
    return tuile().evaluate().isNotEmpty || texteTuile().evaluate().isNotEmpty;
  }

  testWidgets('installée : « Pointer » à la connexion puis tuile de l\'accueil ; la session de vente est gardée', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    LanceurPointage.detecteur = () async => true;
    final app = AppE2E();
    await app.preparer();
    await app.lancer(t);
    expect(await app.attendreQue(t, find.byKey(const Key('bouton_pointer'))), isTrue, reason: 'avant toute connexion');
    final avant = app.serveur.recues.length;
    await t.ensureVisible(find.byKey(const Key('bouton_pointer')));
    await t.tap(find.byKey(const Key('bouton_pointer')));
    await app.attendre(t, const Duration(milliseconds: 500));
    expect(ouvertures, 1);
    expect(app.serveur.recues.length, avant, reason: 'aucune requête : rien n\'est échangé avec Prestige Pointage');
    expect(await app.seConnecter(t), isTrue);
    expect(await tuilePresente(t), isTrue, reason: 'tuile « Pointer » du groupe Équipe');
    final f = tuile().evaluate().isNotEmpty ? tuile() : texteTuile();
    await t.ensureVisible(f.first);
    await t.tap(f.first);
    await app.attendre(t, const Duration(seconds: 1));
    expect(ouvertures, 2);
    expect(find.byType(AccueilScreen), findsOneWidget, reason: 'aucun écran ouvert, session gardée');
    expect(app.serveur.recuesSur('/user/logout'), isEmpty);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('non installée : ni bouton ni tuile ; menus d\'origine inchangés', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    LanceurPointage.detecteur = () async => false;
    final app = AppE2E();
    await app.preparer();
    await app.lancer(t);
    await app.attendre(t);
    expect(find.byKey(const Key('bouton_pointer')), findsNothing);
    expect(await app.seConnecter(t), isTrue);
    expect(await tuilePresente(t), isFalse);
    expect(accueilMenus, hasLength(23), reason: 'catalogue d\'origine inchangé');
    expect(accueilMenus.any((m) => m.id == 'prestige_pointage'), isFalse);
    expect(ouvertures, 0);
    await app.fermer(t);
  });
}
