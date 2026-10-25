// 4.6.2 — QR des badges RH (serveur util.BadgeQr, demande du 16/10) : PRESTIGE-BADGE|1|numéro|login|secret.
//  - format : contenu exact, douchette QWERTY sur AZERTY (avec et sans verrouillage des majuscules), version
//    inconnue, lecture incomplète ou déformée, numéro vide ; codes-barres et UID NFC inchangés ;
//  - terminal : le numéro identifie l'employé ; le login et le secret ne sont ni affichés, ni journalisés, ni envoyés ;
//    le champ de lecture masque le QR dès ses premiers caractères ; ancien kiosque de pointage aussi.
// Données FICTIVES : le secret d'essai n'est pas un vrai secret de badge.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/rh/badge_qr.dart';
import 'package:prestige_vente_app/rh/identification.dart' show MoyenIdentification;
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/terminal_pointage_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rh_pointage_test.dart' show Env, pump, tailleTelephone;

const _secret = 'SECRETfictif-0123_azqwmAQZWM9';
const _login = 'awa.fictive';
String _qr(String numero, {String version = '1', String login = _login, String secret = _secret}) =>
    'PRESTIGE-BADGE|$version|$numero|$login|$secret';

// Ce qu'envoie une douchette en QWERTY sur un appareil AZERTY (tables de util.BadgeQr, sens inverse).
const _us = '1234567890-_|aqzwmAQZWM';
const _fr = '&é"\'(-è_çà)°µqawz,QAWZ?';
const _usMaj = '-_|aqzwmAQZWM';
const _frMaj = '°)*qawz,QAWZ?';
String _qwerty(String s, {bool maj = false}) {
  final us = maj ? _usMaj : _us, fr = maj ? _frMaj : _fr;
  return s.split('').map((c) => us.contains(c) ? fr[us.indexOf(c)] : c).join();
}

/// Texte affiché (hors champ de saisie, dont le contenu masqué est seulement dans le contrôleur).
Finder _affiche(String x) => find.byWidgetPredicate((w) => w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').contains(x));

String? _numero(String lu) => switch (lireBadgeQr(lu)) { BadgeQrReconnu(:final numero) => numero, _ => null };

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('format du QR', () {
    test('contenu exact de BadgeQr.contenu → numéro ; caractères du lecteur ignorés', () {
      expect(_numero(_qr('PHA-26-00012K')), 'PHA-26-00012K');
      expect(_numero('  ${_qr('BDG0042')}\r\n'), 'BDG0042');
      expect(_numero(_qr('PV12AB34', login: 'nom|avec|barres')), 'PV12AB34', reason: 'login avec « | » : le numéro reste lu');
    });

    test('douchette QWERTY sur AZERTY (0f909974) et avec verrouillage des majuscules (81cc8c54)', () {
      final q = _qwerty(_qr('PHA-26-00012K'));
      expect(q, startsWith('PRESTIGE)BQDGEµ&µ'));
      expect(_numero(q), 'PHA-26-00012K');
      final m = _qwerty(_qr('PHA-26-00012K'), maj: true);
      expect(m, startsWith('PRESTIGE°BQDGE*1*'));
      expect(_numero(m), 'PHA-26-00012K');
      // Toutes les lettres permutées (A/Q, Z/W, M) dans le numéro.
      expect(_numero(_qwerty(_qr('AQZWM-19'))), 'AQZWM-19');
      expect(_numero(_qwerty(_qr('AQZWM-19'), maj: true)), 'AQZWM-19');
    });

    test('préfixe en minuscules (verrouillage majuscules) : numéro lu, comparé en majuscules', () {
      expect(_numero('prestige-badge|1|pv12ab34|$_login|$_secret'), 'pv12ab34');
    });

    test('version inconnue, lecture incomplète ou déformée, numéro vide : refus avec la raison seulement', () {
      for (final lu in [
        _qr('PV12AB34', version: '2'),
        'PRESTIGE-BADGE|1|PV12AB34',
        'PRESTIGE#BADGE#1#PV12AB34#$_login#$_secret',
        _qr(''),
        _qr('PV 12;AB'),
        'PRESTIGE',
      ]) {
        final r = lireBadgeQr(lu);
        expect(r, isA<BadgeQrIllisible>(), reason: lu);
        final raison = (r as BadgeQrIllisible).raison;
        expect(raison, isNot(contains(_secret)));
        expect(raison, isNot(contains(_login)));
        expect(raison, isNot(contains('PV12AB34')));
      }
    });

    test('codes-barres, matricules et UID NFC actuels : pas un QR (inchangés)', () {
      for (final lu in ['PV12AB34', ' pv12ab34\r\n', '04A1B2C3D4E5F6', 'M01', 'BDG-0042', '']) {
        expect(lireBadgeQr(lu), isNull, reason: lu);
        expect(ressembleBadgeQr(lu), isFalse, reason: lu);
      }
      expect(ressembleBadgeQr('PRESTIGE'), isTrue);
      expect(ressembleBadgeQr(_qwerty(_qr('X1'), maj: true)), isTrue);
    });
  });

  group('terminal de pointage', () {
    Future<Env> pret() async {
      final e = Env();
      await e.pr.verifierAcces();
      expect(await e.pr.rafraichirEmployes(), isNull);
      return e;
    }

    Future<String> journal(Env e) async => jsonEncode([
          for (final x in await e.journal.lire()) [x.action, x.motif, x.refLocale, x.refServeur, x.source]
        ]);

    test('QR (exact, QWERTY, QWERTY + majuscules) → employé du badge ; secret et login jamais envoyés', () async {
      for (final lu in [_qr('PV12AB34'), _qwerty(_qr('PV12AB34')), _qwerty(_qr('PV12AB34'), maj: true)]) {
        final e = await pret();
        final l = e.pr.lire(lu) as BadgeAConfirmer;
        expect(l.employe.prenomAffiche, 'Awa');
        final r = await e.pr.enregistrer(l, l.sens);
        expect(r.issue, IssueBadge.enregistre);
        final envoye = jsonEncode(e.rh.posts);
        expect(envoye, isNot(contains(_secret)));
        expect(envoye, isNot(contains(_login)));
        expect(envoye, isNot(contains('PRESTIGE')));
        final j = await journal(e);
        expect(j, isNot(contains(_secret)));
        expect(j, isNot(contains(_login)));
      }
    });

    test('QR d\'un badge inconnu : son numéro seul ; QR illisible : raison seulement, jamais le contenu', () async {
      final e = await pret();
      final inconnu = e.pr.lire(_qr('ZZ-26-99999X')) as BadgeInconnu;
      expect((inconnu.code, inconnu.raisonQr), ('ZZ-26-99999X', null));
      final illisible = e.pr.lire(_qr('PV12AB34', version: '9')) as BadgeInconnu;
      expect(illisible.code, isEmpty);
      expect(illisible.raisonQr, contains('version inconnue'));
      // Badge NFC : jamais lu comme un QR.
      expect(e.pr.lire('PV12AB34', moyen: MoyenIdentification.nfc), isNot(isA<BadgeInconnu>()));
    });

    testWidgets('douchette : QR masqué dans le champ dès « PRESTIGE », « Bonjour Awa », secret jamais à l\'écran', (t) async {
      tailleTelephone(t);
      final e = await t.runAsync(pret);
      await pump(
          t,
          TerminalPointageScreen(
            rh: e!.pr,
            presentation: ListPresentation.dashboard,
            identification: e.identification,
            rafraichirAuDemarrage: false,
          ));
      final champ = find.byKey(const Key('rh_badge_champ'));
      // Rafale du lecteur, sans Entrée : masqué dès le début.
      await t.enterText(champ, 'PRESTIGE-BA');
      await t.pump();
      expect(t.widget<TextField>(champ).obscureText, isTrue);
      await t.enterText(champ, _qwerty(_qr('PV12AB34'), maj: true));
      await t.pump();
      expect(t.widget<TextField>(champ).obscureText, isTrue);
      expect(_affiche(_secret), findsNothing);
      await t.pump(const Duration(milliseconds: 350));
      await t.pump();
      expect(find.text('Bonjour Awa'), findsOneWidget);
      expect(t.widget<TextField>(champ).obscureText, isFalse, reason: 'champ vidé et rendu normal');
      await t.pump(const Duration(seconds: 3));
      await t.pump();
      expect(e.rh.posts.single['employeId'], 'E1');
      expect(jsonEncode(e.rh.posts), isNot(contains(_secret)));
      // QR illisible : raison affichée, pas le contenu.
      await t.pump(const Duration(seconds: 5));
      await t.enterText(champ, _qr('PV12AB34', version: '7'));
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(find.textContaining('QR du badge non reconnu'), findsWidgets);
      expect(_affiche(_secret), findsNothing);
      expect(_affiche(_login), findsNothing);
      // Code-barres actuel : affiché et lu comme avant.
      await t.pump(const Duration(seconds: 5));
      await t.enterText(champ, 'INCONNU-01');
      await t.pump();
      expect(t.widget<TextField>(champ).obscureText, isFalse);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(find.textContaining('Badge « INCONNU-01 » inconnu'), findsWidgets);
      // Journal du terminal : vérifié sans écran (test précédent), sa lecture attend hors de l'horloge simulée.
      await t.pump(const Duration(seconds: 5));
      await t.pumpWidget(const SizedBox());
    });
  });
}
