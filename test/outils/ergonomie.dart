// Contrôles d'ergonomie et de cohérence d'affichage réutilisables (voir test/ergonomie_test.dart et test/README.md).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart' as ecran;
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'app_e2e.dart';

/// Un écran contrôlé : comment l'ouvrir depuis l'accueil, le champ de saisie à garder visible au-dessus du clavier.
class EcranControle {
  final String id;
  final String nom;

  /// Contrôlé sur l'écran de connexion (avant toute connexion).
  final bool avantConnexion;

  /// Présentation de l'accueil imposée (préférence de l'appareil).
  final ListPresentation? presentation;

  /// Ouverture depuis l'accueil (après la connexion).
  final Future<void> Function(WidgetTester t, AppE2E app)? ouvrir;

  /// Geste qui fait apparaître le champ de saisie (dialogue de quantité, de mesure…).
  final Future<void> Function(WidgetTester t, AppE2E app)? avantSaisie;

  /// Champ de saisie qui doit rester visible au-dessus du clavier.
  final Finder Function()? champ;

  /// En-tête / barres en bleu nuit de la charte (écrans de la nouvelle interface).
  final bool charte;

  const EcranControle(this.id, this.nom,
      {this.avantConnexion = false, this.presentation, this.ouvrir, this.avantSaisie, this.champ, this.charte = false});
}

/// Contrôles effectués sur chaque écran.
enum Controle {
  rendu('rendu sans débordement ni exception'),
  cibles('cibles tactiles ≥ 48 dp'),
  contraste('contraste des textes'),
  charte('couleurs de la charte'),
  clavier('champ visible au-dessus du clavier');

  final String libelle;
  const Controle(this.libelle);
}

/// Anomalies d'ergonomie connues (décrites dans test/README.md) : le contrôle concerné est sauté UNIQUEMENT sur la
/// configuration touchée (test séparé marqué « sauté » avec l'identifiant), les autres contrôles restent actifs.
/// Clé : 'écran|contrôle|taille|échelle' ; '*' pour toutes les tailles ou toutes les échelles.
const Map<String, String> anomaliesErgonomie = {
  // ANO-02 : puce « Début / Contient » (lib/services/search_mode.dart) haute de 32 dp. Widget partagé présent sur l'écran
  // de vente dont le rendu à 360 px est figé par test/responsive_reference_360.json : correction à arbitrer.
  'recherche_globale|cibles|*|*': 'ANO-02 puce « Début / Contient » 32 dp',
  'vente|cibles|*|*': 'ANO-02 puce « Début / Contient » 32 dp',
  // ANO-03 : onglet unique « Fiche client » (SegmentedPills, widget partagé des présentations) haut de 40 dp.
  'ordonnances_clients|cibles|*|*': 'ANO-03 onglet « Fiche client » 40 dp',
  'fiche_client|cibles|*|*': 'ANO-03 onglet « Fiche client » 40 dp',
  // ANO-06 : pied de la vente au-dessus du clavier (lib/ventes/prevente/vente_screen.dart, « vente-pied-clavier »)
  // déborde de 27 px à droite sur 360 dp de large quand le texte est agrandi à 130 %.
  // 4.0.1 : sur Sunmi V2s / V3 et 360×640 dp, Automatique applique Compact (400 dp de large vus par l'interface) :
  // l'anomalie n'y apparaît plus. Elle reste sur les téléphones de 360 dp de large à la taille normale.
  'vente|clavier|Téléphone 1080×2400 (360×800 dp)|1.3': 'ANO-06 pied de vente déborde (360 dp, texte ×1,3)',
  // ANO-07 : pastille du sens (SensBadge, lib/reserve/reserve_widgets.dart) déborde de 35 px dans la fenêtre de
  // saisie de quantité sur 360 dp de large, texte agrandi à 130 %.
  'reserve_quantites|clavier|Téléphone 1080×2400 (360×800 dp)|1.3': 'ANO-07 pastille du sens déborde (360 dp, texte ×1,3)',
};

/// Identifiant de l'anomalie connue pour ce contrôle et cette configuration, ou null.
String? anomalieConnue(String ecran, Controle c, TailleEcran taille, double echelle) {
  for (final t in [taille.nom, '*']) {
    for (final e in ['$echelle', '*']) {
      final a = anomaliesErgonomie['$ecran|${c.name}|$t|$e'];
      if (a != null) return a;
    }
  }
  return null;
}

/// Couleurs de Material 3 par défaut (« lavande ») interdites sur les en-têtes et barres.
final Set<int> couleursLavande = () {
  final s = ThemeData(useMaterial3: true).colorScheme;
  return {
    s.primary,
    s.primaryContainer,
    s.secondaryContainer,
    s.tertiaryContainer,
    s.inversePrimary,
    s.surface,
    s.surfaceContainerLow,
    s.surfaceContainer,
    s.surfaceContainerHigh,
    s.surfaceContainerHighest,
    s.surfaceDim,
  }.map((c) => c.toARGB32()).toSet();
}();

/// Couleur de fond d'une barre (premier Material sous le widget).
Color? fondBarre(WidgetTester t, Element barre) {
  final m = find.descendant(of: find.byWidget(barre.widget), matching: find.byType(Material));
  if (m.evaluate().isEmpty) return null;
  return t.widget<Material>(m.first).color;
}

/// En-têtes (AppBar) et barres (NavigationBar, BottomNavigationBar, BottomAppBar) affichés : jamais lavande ;
/// bleu nuit de la charte si [charte].
void verifierCharte(WidgetTester t, {required bool charte, required String contexte}) {
  final barres = [
    ...find.byType(AppBar).hitTestable().evaluate(),
    ...find.byType(NavigationBar).hitTestable().evaluate(),
    ...find.byType(BottomNavigationBar).hitTestable().evaluate(),
    ...find.byType(BottomAppBar).hitTestable().evaluate(),
  ];
  for (final b in barres) {
    final c = fondBarre(t, b);
    if (c == null || c.a == 0) continue;
    expect(couleursLavande.contains(c.toARGB32()), isFalse, reason: '$contexte : ${b.widget.runtimeType} en lavande Material par défaut ($c)');
    if (charte) expect(c.toARGB32(), Pal.navy.toARGB32(), reason: '$contexte : ${b.widget.runtimeType} hors charte ($c)');
  }
}

/// Le champ [champ] reste visible au-dessus du clavier simulé (40 % de la hauteur de l'écran).
Future<void> verifierClavier(WidgetTester t, AppE2E app, Finder champ, {required String contexte}) async {
  expect(champ, findsWidgets, reason: '$contexte : champ de saisie introuvable');
  await t.ensureVisible(champ.first);
  await t.pump();
  await t.tap(champ.first, warnIfMissed: false);
  final clavier = t.view.physicalSize.height * 0.4;
  t.view.viewInsets = FakeViewPadding(bottom: clavier);
  addTearDown(t.view.resetViewInsets);
  await app.attendre(t, const Duration(milliseconds: 800));
  expect(t.takeException(), isNull, reason: '$contexte : erreur de rendu avec le clavier ouvert');
  final hauteurVisible = (t.view.physicalSize.height - clavier) / t.view.devicePixelRatio;
  final r = t.getRect(champ.first);
  expect(r.top, greaterThanOrEqualTo(0), reason: '$contexte : champ sous le bord haut avec le clavier');
  expect(r.bottom, lessThanOrEqualTo(hauteurVisible + 0.5), reason: '$contexte : champ caché par le clavier ($r, zone visible ${hauteurVisible.toStringAsFixed(0)} dp)');
  t.view.resetViewInsets();
  await app.attendre(t, const Duration(milliseconds: 500));
}

/// Facteur de réduction appliqué par l'application (MyApp → RacineTailleEcran) sur l'écran simulé : réglage
/// lu au lancement, Automatique → Compact (0,9) sur un petit écran (côté long < 740 dp ou court < 340 dp).
double facteurEcran(WidgetTester t) =>
    ecran.TailleEcranReglage.effective(ecran.TailleEcranReglage.active.value, t.view.physicalSize / t.view.devicePixelRatio).facteur;

/// Cibles tactiles : 48 dp DE L'INTERFACE. Interface réduite (Compact / Très compact, Compact automatique des
/// petits écrans) : 48 × facteur dp réels (43,2 / 38,4 dp), réduction voulue (docs/TAILLE_ECRAN.md) ; règle
/// Android inchangée à la taille normale. La règle de Flutter mesure en dp réels, d'où l'ajustement.
AccessibilityGuideline ciblesTactiles(double facteur) => facteur == 1.0
    ? androidTapTargetGuideline
    : MinimumTapTargetGuideline(size: Size.square(48 * facteur), link: 'https://support.google.com/accessibility/android/answer/7101858');

/// Tous les contrôles d'un écran, sauf ceux de [sautes] (anomalies connues) ; tous les échecs sont rapportés ensemble.
Future<void> verifierEcran(WidgetTester t, AppE2E app, EcranControle e, {Set<Controle> sautes = const {}}) async {
  final facteur = facteurEcran(t);
  final contexte = '${e.nom} ${t.view.physicalSize.width.toInt()}×${t.view.physicalSize.height.toInt()} '
      'texte ×${t.platformDispatcher.textScaleFactor}${facteur == 1.0 ? '' : ', interface ×$facteur'}';
  final echecs = <String>[];
  Future<void> controle(Controle c, Future<void> Function() f) async {
    if (sautes.contains(c)) return;
    try {
      await f();
    } on TestFailure catch (x) {
      echecs.add('[${c.libelle}] ${x.message}');
    }
  }

  await controle(Controle.rendu, () async => expect(t.takeException(), isNull, reason: '$contexte : erreur de rendu (débordement, exception)'));
  final handle = t.ensureSemantics();
  await controle(Controle.cibles, () => expectLater(t, meetsGuideline(ciblesTactiles(facteur)), reason: '$contexte : cibles tactiles < 48 dp (de l\'interface)'));
  await controle(Controle.contraste, () => expectLater(t, meetsGuideline(textContrastGuideline), reason: '$contexte : contraste insuffisant'));
  handle.dispose();
  await controle(Controle.charte, () async => verifierCharte(t, charte: e.charte, contexte: contexte));
  if (e.champ != null) {
    await controle(Controle.clavier, () async {
      await e.avantSaisie?.call(t, app);
      expect(t.takeException(), isNull, reason: '$contexte : erreur de rendu avant la saisie');
      await verifierClavier(t, app, e.champ!(), contexte: contexte);
    });
  }
  await controle(Controle.rendu, () async => expect(t.takeException(), isNull, reason: '$contexte : erreur de rendu'));
  if (echecs.isNotEmpty) fail(echecs.join('\n\n'));
}
