// ERGONOMIE — Taille de l'écran (4.0.1), application ENTIÈRE (MyApp → RacineTailleEcran → MaterialApp, comme main()),
// faux serveur Prestige en mémoire.
//
// 1. Sunmi V2s 720×1440 (360 × 720 dp) aux 3 tailles : Automatique (Compact appliqué d'office : 400 dp vus par
//    l'interface), Compact (400 dp), Très compact (450 dp) — écrans principaux (connexion, accueil A / B / C, recherche,
//    fiche produit, vente, recherche et analyse article, posologie, ordonnances, fiche client, réserve, pointage,
//    réglages) : interface qui remplit exactement l'écran réel (rien de coupé, pas de bande vide), aucun débordement ni
//    exception, cibles ≥ 48 dp de l'interface, contraste, charte, champ au-dessus du clavier.
//    (Automatique × texte 1,3 : test/ergonomie_test.dart, où le V2s est désormais en Compact automatique.)
// 2. Vente sur V2s en Automatique, CLAVIER OUVERT : article ajouté, panier, total et Prévente / Encaisser au-dessus du
//    clavier réel ; douchette Sunmi (touches + Entrée) sur l'accueil réduit.
// 3. Autres appareils en Automatique : Sunmi V3 360 × 640 dp → Compact ; téléphones 1080 × 2400 et tablette : RIEN ne
//    change (aucune réduction).
// 4. Réglage : Réglages › Apparence (nouvelle interface) et Configuration (d'origine) — code administrateur, choix
//    enregistré pour le prochain lancement, « Relancer maintenant » (retour à l'accueil, session gardée), libellé
//    « Automatique (Compact appliqué sur cet écran) ».
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/parametres/taille_ecran_reglage.dart';
import 'package:prestige_vente_app/screens/auth/settings_screen.dart';
import 'package:prestige_vente_app/services/pin_securise.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart' as ecran;
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/app_e2e.dart';
import 'outils/ecrans_ergonomie.dart';
import 'outils/ergonomie.dart';

const _v2s = TailleEcran.sunmiV2s;

/// Sunmi V3 / V3H / V3mix : 1080 × 1920 px, densité 3 → 360 × 640 dp.
const _v3 = TailleEcran('Sunmi V3 1080×1920 ×3', Size(1080, 1920), 3.0);

/// Téléphone courant 1080 × 2400 px, densité 2,625 → 411 × 914 dp.
const _telephone = TailleEcran('Téléphone 1080×2400 ×2,625', Size(1080, 2400), 2.625);

NavigatorState get _nav => HorsLigne.navigatorKey.currentState!;

/// Taille vue par l'interface (MediaQuery sous la racine).
Size _surface() => MediaQuery.sizeOf(_nav.context);

/// L'interface remplit exactement l'écran réel : rien de coupé à droite ni en bas, pas de bande vide.
void _remplitEcran(WidgetTester t, {required String contexte}) {
  final reel = t.view.physicalSize / t.view.devicePixelRatio;
  final r = t.getRect(find.byType(Navigator).first);
  expect(r.left.abs() + r.top.abs(), lessThan(0.01), reason: '$contexte : interface décalée ($r)');
  expect((r.width - reel.width).abs(), lessThan(0.01), reason: '$contexte : largeur ${r.width} ≠ écran ${reel.width}');
  expect((r.height - reel.height).abs(), lessThan(0.01), reason: '$contexte : hauteur ${r.height} ≠ écran ${reel.height}');
}

/// Lance l'application connectée (administrateur) avec la taille [reglage] enregistrée sur l'appareil.
Future<AppE2E> _lancer(WidgetTester t, TailleEcran appareil, ecran.TailleEcran reglage,
    {ListPresentation? presentation, bool connecter = true}) async {
  appareil.appliquer(t);
  final app = AppE2E()..serveur.activerModules();
  await app.preparer(prefs: {
    'hiddenMenuIds': <String>[],
    ecran.TailleEcranReglage.cle: reglage.name,
    if (presentation != null) 'presentation_listes_v1': presentation.name,
  });
  await app.lancer(t);
  if (connecter) {
    expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
    await app.attendre(t);
  }
  return app;
}

/// Code administrateur de l'appareil (vraie fenêtre PinCodeDialog, vérification simulée : 4827).
class _Code extends CodeAdmin {
  int demandes = 0;
  @override
  Future<Duration?> attenteRestante() async => null;
  @override
  Future<VerificationPin> verifier(String saisie) async {
    demandes++;
    return saisie == '4827' ? VerificationPin.accepte : VerificationPin.refuse;
  }
}

_Code _installerCode() {
  final avant = CodeAdmin.instance;
  final c = _Code();
  CodeAdmin.instance = c;
  addTearDown(() => CodeAdmin.instance = avant);
  return c;
}

Future<void> _saisirCode(WidgetTester t, AppE2E app, String code) async {
  expect(find.byKey(const Key('pin_admin_saisie')), findsOneWidget, reason: 'code administrateur demandé');
  await t.enterText(find.byKey(const Key('pin_admin_saisie')), code);
  await t.tap(find.text('Valider'));
  await app.attendre(t, const Duration(seconds: 1));
}

/// Douchette Sunmi : chaque caractère arrive comme une touche du clavier matériel, puis Entrée.
Future<void> _douchette(WidgetTester t, String code) async {
  for (final ch in code.split('')) {
    final k = LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + int.parse(ch));
    await t.sendKeyDownEvent(k, character: ch);
    await t.sendKeyUpEvent(k);
  }
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
}

void main() {
  // ---------------------------------------------------------------------------
  // 1. Écrans principaux sur Sunmi V2s aux trois tailles
  // ---------------------------------------------------------------------------
  final configurations = <(ecran.TailleEcran, double)>[
    (ecran.TailleEcran.automatique, 1.0),
    (ecran.TailleEcran.compact, 1.0),
    (ecran.TailleEcran.compact, 1.3),
    (ecran.TailleEcran.tresCompact, 1.0),
    (ecran.TailleEcran.tresCompact, 1.3),
  ];
  for (final (reglage, echelle) in configurations) {
    final attendu = _v2s.dp.width / ecran.TailleEcranReglage.effective(reglage, _v2s.dp).facteur;
    group('Sunmi V2s, taille ${reglage.libelle}, texte ×$echelle', () {
      for (final e in ecransErgonomie) {
        final sautes = <Controle>{};
        for (final c in Controle.values) {
          final a = anomalieConnue(e.id, c, _v2s, echelle);
          if (a != null) sautes.add(c);
        }
        testWidgets('${e.nom} : ${attendu.toStringAsFixed(0)} dp de large, rien de coupé${sautes.isEmpty ? '' : ' (sauf ${sautes.map((c) => c.name).join(', ')} : anomalie connue)'}',
            (t) async {
          t.platformDispatcher.textScaleFactorTestValue = echelle;
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          final app = await _lancer(t, _v2s, reglage, presentation: e.presentation, connecter: !e.avantConnexion);
          if (e.avantConnexion) {
            expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
          } else {
            await e.ouvrir?.call(t, app);
          }
          expect(_surface().width, closeTo(attendu, 0.01), reason: 'surface vue par l\'interface');
          _remplitEcran(t, contexte: e.nom);
          await verifierEcran(t, app, e, sautes: sautes);
          await app.fermer(t);
        });
      }
    });
  }

  // ---------------------------------------------------------------------------
  // 2. Vente clavier ouvert et douchette, Sunmi V2s en Automatique (Compact appliqué)
  // ---------------------------------------------------------------------------
  group('Sunmi V2s, Automatique : vente et douchette', () {
    testWidgets('vente, clavier ouvert : panier, total, Prévente et Encaisser au-dessus du clavier réel', (t) async {
      final app = await _lancer(t, _v2s, ecran.TailleEcran.automatique);
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
      expect(_surface().width, closeTo(400, 0.01));
      await t.enterText(find.byKey(const ValueKey('vente-recherche')), 'para');
      await app.attendre(t);
      final champQte = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField));
      expect(await app.attendreQue(t, champQte), isTrue, reason: 'fenêtre de quantité (réduite avec l\'interface)');
      await t.enterText(champQte, '2');
      await t.tap(find.text('Ajouter'));
      await app.attendre(t, const Duration(seconds: 3));
      expect(app.serveur.ventes.values.single.single['intQUANTITY'], 2, reason: 'touchers justes : article ajouté');

      // Clavier système de 280 dp réels (560 px) : zone visible 0 → 440 dp réels.
      await t.tap(find.byKey(const ValueKey('vente-recherche')));
      t.view.viewInsets = const FakeViewPadding(bottom: 560);
      addTearDown(t.view.resetViewInsets);
      await app.attendre(t, const Duration(seconds: 1));
      const visible = 720.0 - 280;
      expect(t.takeException(), isNull);
      final pied = find.byKey(const ValueKey('vente-pied-clavier'));
      expect(pied, findsOneWidget, reason: 'pied « clavier ouvert » affiché');
      expect(t.getRect(pied).bottom, lessThanOrEqualTo(visible + 0.5), reason: 'pied posé sur le clavier réel');
      expect(t.getRect(find.byKey(const ValueKey('vente-net'))).bottom, lessThanOrEqualTo(visible + 0.5));
      expect(find.byKey(const ValueKey('vente-encaisser')).hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('vente-enregistrer-prevente')).hitTestable(), findsOneWidget);
      expect(find.text('PARACETAMOL TEST 500MG CP B/16').hitTestable(), findsOneWidget, reason: 'ligne du panier visible');
      final champ = t.getRect(find.byKey(const ValueKey('vente-recherche')));
      expect(champ.top, greaterThanOrEqualTo(0));
      expect(champ.bottom, lessThanOrEqualTo(visible));
      t.view.resetViewInsets();
      await app.attendre(t, const Duration(seconds: 1));
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('douchette Sunmi (clavier matériel) sur l\'accueil réduit : code lu → fiche produit', (t) async {
      final app = await _lancer(t, _v2s, ecran.TailleEcran.automatique);
      expect(find.byType(AccueilScreen), findsOneWidget);
      await _douchette(t, '9990001');
      await app.attendre(t, const Duration(seconds: 3));
      expect(find.byType(FicheProduitScreen), findsOneWidget, reason: 'les touches de la douchette ne passent pas par la réduction');
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Autres appareils en Automatique
  // ---------------------------------------------------------------------------
  group('Automatique selon l\'appareil', () {
    final cas = <(TailleEcran, double)>[
      (_v3, 360 / 0.9), // petit : Compact
      (TailleEcran.telephone, 360 / 0.9), // 360 × 640 dp : Compact
      (_telephone, 1080 / 2.625), // téléphone courant : inchangé
      (TailleEcran.telephone360x800, 360), // Samsung 360 × 800 dp : inchangé
      (TailleEcran.tablette, 1280), // tablette : inchangée
    ];
    for (final (appareil, largeur) in cas) {
      testWidgets('$appareil : ${largeur.toStringAsFixed(1)} dp vus par l\'interface, accueil sans débordement', (t) async {
        final app = await _lancer(t, appareil, ecran.TailleEcran.automatique);
        expect(_surface().width, closeTo(largeur, 0.01));
        _remplitEcran(t, contexte: appareil.nom);
        if (largeur == appareil.dp.width) {
          expect(MediaQuery.of(_nav.context).devicePixelRatio, appareil.densite, reason: 'rien ne change : densité Android');
        }
        expect(find.byType(AccueilScreen), findsOneWidget);
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });
    }
  });

  // ---------------------------------------------------------------------------
  // 4. Le réglage dans les deux interfaces
  // ---------------------------------------------------------------------------
  group('Réglage « Taille de l\'écran »', () {
    Future<void> ouvrirApparence(WidgetTester t, AppE2E app) async {
      await t.tap(find.text('Réglages'));
      await app.attendre(t);
      await t.tap(find.text('Apparence'));
      await app.attendre(t);
      await app.defilerJusqua(t, find.byKey(const ValueKey('taille-ecran-aide')), zone: find.byType(Scrollable).last);
    }

    testWidgets('Réglages › Apparence (V2s) : « Automatique (Compact appliqué sur cet écran) », code, Relancer maintenant', (t) async {
      final code = _installerCode();
      final app = await _lancer(t, _v2s, ecran.TailleEcran.automatique);
      await ouvrirApparence(t, app);
      expect(find.text('Automatique (Compact appliqué sur cet écran)'), findsOneWidget);
      expect(find.text('Taille de l\'écran'), findsOneWidget);

      // Code refusé : rien ne change.
      await t.tap(find.byKey(const ValueKey('taille-ecran-tresCompact')));
      await app.attendre(t, const Duration(seconds: 1));
      await _saisirCode(t, app, '0000');
      await t.tap(find.text('Annuler'));
      await app.attendre(t, const Duration(seconds: 1));
      expect(ecran.TailleEcranReglage.enregistree, ecran.TailleEcran.automatique);

      // Bon code : enregistré, fenêtre « Relancer maintenant ».
      await t.tap(find.byKey(const ValueKey('taille-ecran-tresCompact')));
      await app.attendre(t, const Duration(seconds: 1));
      await _saisirCode(t, app, '4827');
      expect(code.demandes, 2);
      expect(find.text('Taille de l\'écran : Très compact'), findsOneWidget);
      expect((await SharedPreferences.getInstance()).getString(ecran.TailleEcranReglage.cle), 'tresCompact');
      expect(_surface().width, closeTo(400, 0.01), reason: 'pas encore appliqué');
      await t.tap(find.byKey(const ValueKey('taille-ecran-relancer-maintenant')));
      await app.attendre(t, const Duration(seconds: 2));

      expect(find.byType(AccueilScreen), findsOneWidget, reason: 'retour à l\'accueil');
      expect(find.byType(ConnexionScreen), findsNothing, reason: 'session gardée');
      expect(_surface().width, closeTo(450, 0.01), reason: 'Très compact appliqué');
      _remplitEcran(t, contexte: 'après relance');
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });

    testWidgets('Réglages › Apparence : « Plus tard » → appliqué au prochain lancement seulement', (t) async {
      _installerCode();
      final app = await _lancer(t, _v2s, ecran.TailleEcran.automatique);
      await ouvrirApparence(t, app);
      await t.tap(find.byKey(const ValueKey('taille-ecran-compact')));
      await app.attendre(t, const Duration(seconds: 1));
      await _saisirCode(t, app, '4827');
      await t.tap(find.text('Plus tard'));
      await app.attendre(t, const Duration(seconds: 1));
      expect(find.text('Choix enregistré : appliqué au prochain lancement.'), findsOneWidget);
      expect(ecran.TailleEcranReglage.enAttente, isTrue);
      expect(ecran.TailleEcranReglage.active.value, ecran.TailleEcran.automatique);
      await ecran.TailleEcranReglage.charger(); // prochain lancement
      expect(ecran.TailleEcranReglage.active.value, ecran.TailleEcran.compact);
      await app.fermer(t);
    });

    testWidgets('téléphone 1080×2400 : pas de mention « Compact appliqué », taille normale', (t) async {
      final app = await _lancer(t, _telephone, ecran.TailleEcran.automatique);
      await ouvrirApparence(t, app);
      expect(find.byKey(const ValueKey('taille-ecran-automatique')), findsOneWidget);
      expect(find.byKey(const ValueKey('taille-ecran-auto-compact')), findsNothing);
      await app.fermer(t);
    });

    testWidgets('Configuration d\'origine : même réglage, protégé par le code administrateur', (t) async {
      // F1 (4.0.3) : la Configuration d'origine ne déborde plus (test/configuration_origine_test.dart).
      final code = _installerCode();
      final app = await _lancer(t, _v2s, ecran.TailleEcran.automatique);
      // Configuration d'origine (InterfaceVersion.settings() quand « Nouvel accueil et nouveaux réglages » est désactivé).
      _nav.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      await app.attendre(t);
      expect(find.byType(TailleEcranSetting), findsOneWidget);
      await app.defilerJusqua(t, find.byKey(const ValueKey('taille-ecran-compact')), zone: find.byType(Scrollable).last);
      expect(find.text('Automatique (Compact appliqué sur cet écran)'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('taille-ecran-compact')));
      await app.attendre(t, const Duration(seconds: 1));
      await _saisirCode(t, app, '4827');
      expect(code.demandes, 1);
      expect(find.text('Taille de l\'écran : Compact'), findsOneWidget);
      await t.tap(find.text('Plus tard'));
      await app.attendre(t, const Duration(seconds: 1));
      expect(ecran.TailleEcranReglage.enregistree, ecran.TailleEcran.compact);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });
}
