// 5.3.0 — ERGONOMIE : bandeau « badge ou code personnel », rappel de la confirmation, panneau pendant la demande
// d'empreinte, résultat avec mention, réglage (Réglages › Équipe & pointage) et gestion des empreintes sans lecteur, sur
// 320 × 640 dp, 360 × 800 dp et tablette 1 280 × 800 dp, texte ×1,0 et ×1,3 ; borne (Prestige Pointage : mode borne,
// texte plafonné à ×1,3). Contrôles : aucun débordement, textes jamais tronqués, boutons d'au moins 48 dp de haut,
// tout dans la largeur de l'écran. Données FICTIVES seulement.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/rh/confirmation_empreinte.dart';
import 'package:prestige_vente_app/rh/empreintes_screen.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/empreinte_terminal_fictif.dart';

const _tailles = [
  ('320 dp', Size(320, 640)),
  ('360 dp', Size(360, 800)),
  ('tablette', Size(1280, 800)),
];

Widget _avecTexte(Widget w, double echelle) => MaterialApp(
      key: UniqueKey(),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(echelle)), child: child!),
      home: w,
    );

void _dansLEcran(WidgetTester t, Finder f, Size ecran) {
  for (final e in f.evaluate()) {
    final r = t.getRect(find.byWidget(e.widget).first);
    expect(r.left, greaterThanOrEqualTo(-0.5), reason: '${e.widget.key} à gauche');
    expect(r.right, lessThanOrEqualTo(ecran.width + 0.5), reason: '${e.widget.key} à droite');
  }
}

void _boutonsAccessibles(WidgetTester t, List<Key> cles) {
  for (final k in cles) {
    final f = find.byKey(k);
    if (f.evaluate().isEmpty) continue;
    expect(t.getSize(f).height, greaterThanOrEqualTo(48), reason: '$k : cible tactile ≥ 48 dp');
  }
}

/// Aucun texte coupé par des points de suspension ni limité en lignes dans [racine].
void _textesEntiers(WidgetTester t, Finder racine) {
  for (final e in find.descendant(of: racine, matching: find.byType(Text)).evaluate()) {
    final w = e.widget as Text;
    expect(w.overflow == TextOverflow.ellipsis && w.maxLines != null, isFalse, reason: 'texte tronqué : ${w.data}');
    final rp = e.findRenderObject();
    if (rp is RenderParagraph) expect(rp.didExceedMaxLines, isFalse, reason: 'texte coupé : ${w.data}');
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({ReglagesPointageTerminal.prefConfirmationEmpreinte: true}));

  for (final (nom, ecran) in _tailles) {
    for (final echelle in [1.0, 1.3]) {
      final cas = '$nom, texte ×$echelle';

      testWidgets('terminal sans service Sunmi — bandeau et rappel ($cas)', (t) async {
        taille(t, ecran);
        final e = TerminalEmpreinte();
        await e.preparer(t);
        await t.pumpWidget(_avecTexte(e.ecran(), echelle));
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('rh_sans_empreinte')), findsOneWidget);
        _dansLEcran(t, find.byKey(const Key('rh_sans_empreinte')), ecran);
        _dansLEcran(t, find.byKey(const Key('rh_sans_empreinte_badge')), ecran);
        _dansLEcran(t, find.byKey(const Key('rh_sans_empreinte_code')), ecran);
        _boutonsAccessibles(t, const [Key('rh_sans_empreinte_badge'), Key('rh_sans_empreinte_code')]);
        _textesEntiers(t, find.byKey(const Key('rh_sans_empreinte')));
        expect(find.text(texteSansEmpreinte), findsOneWidget);
        // Lecteur de badge (douchette, scanner intégré) : champ construit et focalisé même poussé sous le bas de l'écran.
        expect(t.widget<TextField>(find.byKey(const Key('rh_badge_champ'), skipOffstage: false)).focusNode!.hasFocus, isTrue);
        // Bandeau en tête : visible sans défiler, au-dessus de la zone du badge.
        expect(t.getRect(find.byKey(const Key('rh_sans_empreinte'))).top, lessThan(ecran.height / 2));
        await t.scrollUntilVisible(find.byKey(const Key('rh_confirmation_info')), 120, scrollable: find.byType(Scrollable).first);
        _textesEntiers(t, find.byKey(const Key('rh_confirmation_info')));
        expect(t.takeException(), isNull);
        await finir(t);
      });

      testWidgets('demande d\'empreinte puis résultat avec mention ($cas)', (t) async {
        taille(t, ecran);
        final e = TerminalEmpreinte();
        await e.preparer(t);
        final reponse = Completer<Object?>();
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(CanalEmpreinteSimule.canal, (c) async {
          if (c.method == 'hardwareInfo') return materielSunmiV3();
          if (c.method == 'isServiceInstalled') return false;
          if (c.method == 'authenticate') return reponse.future;
          return null;
        });
        await t.pumpWidget(_avecTexte(e.ecran(), echelle));
        await t.pump();
        await lireBadge(t, badgeFictif1);
        expect(find.byKey(const Key('rh_confirmation_empreinte')), findsOneWidget);
        _textesEntiers(t, find.byKey(const Key('rh_confirmation_empreinte')));
        expect(t.takeException(), isNull);
        reponse.completeError(PlatformException(code: 'HW_ERROR', message: 'panne simulée'));
        await t.pump();
        await t.pump();
        // Lecteur en panne → indisponible → confirmation habituelle, puis résultat avec mention.
        expect(find.byKey(const Key('rh_confirmation')), findsOneWidget);
        await t.ensureVisible(find.byKey(const Key('rh_valider'), skipOffstage: false));
        await t.pump();
        _boutonsAccessibles(t, const [Key('rh_valider'), Key('rh_annuler'), Key('rh_corriger')]);
        await t.tap(find.byKey(const Key('rh_valider')));
        await t.pump();
        await t.pump();
        expect(find.byKey(const Key('rh_resultat_confirmation')), findsOneWidget);
        _dansLEcran(t, find.byKey(const Key('rh_resultat_confirmation')), ecran);
        expect(t.takeException(), isNull);
        await finir(t);
      });

      testWidgets('refus : message lisible ($cas)', (t) async {
        taille(t, ecran);
        final e = TerminalEmpreinte();
        e.canal.reponseAuthentification = 'LOCKOUT';
        await e.preparer(t);
        await t.pumpWidget(_avecTexte(e.ecran(), echelle));
        await t.pump();
        await lireBadge(t, badgeFictif1);
        expect(find.byKey(const Key('rh_resultat')), findsOneWidget);
        _textesEntiers(t, find.byKey(const Key('rh_resultat')));
        expect(t.takeException(), isNull);
        await finir(t);
      });

      testWidgets('Réglages › Équipe & pointage : réglage de confirmation ($cas)', (t) async {
        taille(t, ecran);
        final photo = PhotoControle(registre: RegistrePhotosPointage(stockage: StockagePhotosMemoire()));
        await t.pumpWidget(_avecTexte(EquipePage(repository: MemoryPointageRepository(), photo: photo), echelle));
        await t.pumpAndSettle();
        final k = find.byKey(const Key('rh_reglage_confirmation_empreinte'));
        await t.scrollUntilVisible(k, 200, scrollable: find.byType(Scrollable).first);
        await t.pumpAndSettle();
        _dansLEcran(t, k, ecran);
        _textesEntiers(t, k);
        expect(find.descendant(of: k, matching: find.text(titreReglageConfirmationEmpreinte)), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('gestion des empreintes sans lecteur : bandeau ($cas)', (t) async {
        taille(t, ecran);
        final e = TerminalEmpreinte();
        await e.preparer(t);
        await e.identification.enregistrer(EmpreintesEmploye(employeId: 'EX1', modeles: [Uint8List.fromList([1])], consentementLe: e.now));
        await t.pumpWidget(_avecTexte(EmpreintesScreen(rh: e.pr, identification: e.identification, codeAdmin: (_) async => true), echelle));
        await t.pumpAndSettle();
        _dansLEcran(t, find.byKey(const Key('rh_sans_empreinte')), ecran);
        _textesEntiers(t, find.byKey(const Key('rh_sans_empreinte')));
        _boutonsAccessibles(t, const [Key('rh_sans_empreinte_details')]);
        expect(t.takeException(), isNull);
      });
    }
  }

  for (final (nom, ecran) in _tailles) {
    testWidgets('borne Prestige Pointage (mode borne, texte ×1,3) : bandeau sans lien technique ($nom)', (t) async {
      taille(t, ecran);
      final e = TerminalEmpreinte();
      await e.preparer(t);
      await t.pumpWidget(_avecTexte(e.ecran(borne: true, gestion: false), 1.3));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('rh_sans_empreinte')), findsOneWidget);
      expect(find.byKey(const Key('rh_sans_empreinte_details')), findsNothing);
      _dansLEcran(t, find.byKey(const Key('rh_sans_empreinte')), ecran);
      _textesEntiers(t, find.byKey(const Key('rh_sans_empreinte')));
      expect(t.takeException(), isNull);
      await finir(t);
    });
  }
}
