// 4.5.0 — Ergonomie sur iPhone et iPad (application entière, faux serveur, plateforme iOS simulée) :
// iPhone SE 375×667, iPhone Pro Max 430×932, iPad 768×1024 (portrait) et iPad Pro 1024×1366 (portrait), plus l'iPad
// Pro en paysage : écrans principaux sans débordement, cibles ≥ 48 dp, contraste, charte, champ au-dessus du clavier ;
// fonctions Android / Sunmi absentes (borne, pointage local, imprimante Sunmi) sans écran cassé.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/parametres/parametres_logic.dart';
import 'package:prestige_vente_app/plateforme/capacites.dart';
import 'package:prestige_vente_app/services/pin_securise.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import '../outils/app_e2e.dart';
import '../outils/ecrans_ergonomie.dart';
import '../outils/ergonomie.dart';

const iphoneSe = TailleEcran('iPhone SE 375×667', Size(750, 1334), 2.0);
const iphoneProMax = TailleEcran('iPhone Pro Max 430×932', Size(1290, 2796), 3.0);
const ipad = TailleEcran('iPad 768×1024', Size(1536, 2048), 2.0);
const ipadPro = TailleEcran('iPad Pro 1024×1366', Size(2048, 2732), 2.0);
const ipadProPaysage = TailleEcran('iPad Pro 1366×1024 (paysage)', Size(2732, 2048), 2.0);
const taillesIos = [iphoneSe, iphoneProMax, ipad, ipadPro, ipadProPaysage];

class _Code extends CodeAdmin {
  @override
  Future<Duration?> attenteRestante() async => null;
  @override
  Future<VerificationPin> verifier(String saisie) async => saisie == '4827' ? VerificationPin.accepte : VerificationPin.refuse;
}

/// Plateforme iOS pendant [corps] (remise à zéro avant la fin du test, exigée par flutter_test).
Future<void> enIos(Future<void> Function() corps) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  try {
    expect(CapacitesPlateforme.courant.ios, isTrue);
    await corps();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<AppE2E> lancer(WidgetTester t, TailleEcran taille, {Map<String, Object> prefs = const {}}) async {
  taille.appliquer(t);
  final app = AppE2E()..serveur.activerModules();
  await app.preparer(prefs: {'hiddenMenuIds': <String>[], ...prefs});
  await app.lancer(t);
  // Grands écrans (iPad Pro) : laisser l'écran de lancement finir avant de saisir.
  await app.attendreQue(t, find.byType(ConnexionScreen));
  await app.attendre(t, const Duration(seconds: 2));
  return app;
}

/// La tuile [id] apparaît-elle en parcourant toute la page d'accueil ?
Future<bool> tuilePresente(WidgetTester t, String id) async {
  final f = find.byKey(ValueKey('tuile_$id'));
  final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
  pos.jumpTo(pos.minScrollExtent);
  await t.pump();
  var vu = f.evaluate().isNotEmpty;
  while (!vu && pos.pixels < pos.maxScrollExtent) {
    pos.jumpTo((pos.pixels + 250).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    await t.pump();
    vu = f.evaluate().isNotEmpty;
  }
  pos.jumpTo(pos.minScrollExtent);
  await t.pump();
  return vu;
}

void main() {
  for (final taille in taillesIos) {
    group('$taille (iOS)', () {
      for (final e in ecransErgonomie) {
        final controles = {for (final c in Controle.values) if (c != Controle.clavier || e.champ != null) c};
        // Anomalies connues (test/README.md, ex. ANO-03) : sautées comme sur Android, avec leur identifiant.
        final connues = <Controle, String>{
          for (final c in controles)
            if (anomalieConnue(e.id, c, taille, 1.0) case final a?) c: a,
        };
        connues.forEach((c, a) => testWidgets('${e.nom} — ${c.libelle} — sauté : $a', skip: true, (t) async {}));
        testWidgets(e.nom, (t) async {
          await enIos(() async {
            final app = await lancer(t, taille, prefs: {if (e.presentation != null) 'presentation_listes_v1': e.presentation!.name});
            if (e.avantConnexion) {
              expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
            } else {
              expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
              await app.attendre(t);
              await e.ouvrir?.call(t, app);
            }
            await verifierEcran(t, app, e, sautes: {...Controle.values.toSet().difference(controles), ...connues.keys});
            await app.fermer(t);
          });
        });
      }
    });
  }

  group('fonctions absentes sur iOS : masquées, aucun écran cassé', () {
    testWidgets('accueil (administrateur) : ni « Borne » ni « Pointage local » ; Android : présents', (t) async {
      await enIos(() async {
        final app = await lancer(t, ipad);
        expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
        await app.attendre(t);
        expect(await tuilePresente(t, 'borne_admin'), isFalse);
        expect(await tuilePresente(t, 'empreinte'), isFalse);
        expect(await app.menuPresent(t, ListPresentation.dashboard, 'pointage_rh'), isTrue, reason: 'pointage présence disponible');
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });
    });

    testWidgets('Réglages : pas de rubrique Borne ; Impression : tickets à l\'écran ; Équipe : pas de pointage local', (t) async {
      final avant = CodeAdmin.instance;
      CodeAdmin.instance = _Code();
      addTearDown(() => CodeAdmin.instance = avant);
      await enIos(() async {
        final app = await lancer(t, iphoneProMax);
        expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
        await app.attendre(t);
        await t.tap(find.text('Réglages').last);
        await app.attendre(t, const Duration(seconds: 1));
        expect(find.byKey(Key('rubrique_${Rubrique.borne.name}')), findsNothing);
        await app.defilerJusqua(t, find.byKey(Key('rubrique_${Rubrique.impression.name}')));
        await t.tap(find.byKey(Key('rubrique_${Rubrique.impression.name}')));
        await app.attendre(t, const Duration(seconds: 1));
        expect(find.byKey(const Key('impression_ios')), findsOneWidget);
        expect(find.textContaining('APERÇU D\'UN TICKET'), findsOneWidget);
        expect(find.textContaining('IMPRIMER UN TICKET D\'ESSAI'), findsNothing);
        await app.retour(t);
        await app.defilerJusqua(t, find.byKey(Key('rubrique_${Rubrique.equipe.name}')));
        await t.tap(find.byKey(Key('rubrique_${Rubrique.equipe.name}')));
        await app.attendre(t, const Duration(seconds: 1));
        if (find.byKey(const Key('pin_admin_saisie')).evaluate().isNotEmpty) {
          await t.enterText(find.byKey(const Key('pin_admin_saisie')), '4827');
          await t.tap(find.text('Valider'));
          await app.attendre(t, const Duration(seconds: 1));
        }
        expect(find.text('Pointage local (non envoyé à Prestige)'), findsNothing);
        expect(find.byKey(const Key('pointage_local_visible')), findsNothing);
        await app.defilerJusqua(t, find.byKey(const Key('rh_reglage_photo')));
        expect(find.byKey(const Key('rh_reglage_photo')), findsOneWidget, reason: 'photo de contrôle disponible (caméra iOS)');
        expect(t.takeException(), isNull);
        await app.fermer(t);
      });
    });
  });
}
