// UNITAIRES + ÉCRANS — 5.4.0 : lisibilité du ticket imprimé (retour du pharmacien, SUNMI V3 : libellés « Matricule
// assuré », « Bénéficiaire », « Bon N° », « Part du client », organismes, « 1 ligne · 1 article », « Total » fins et
// pâles, comme tramés ; gras nets).
//
// Images de référence : test/references/tickets/image_serveur_fictive_*.png, dessinées par le code du serveur
// (RenduTicket.imageImprimante, 76aa5fc1) avec des données FICTIVES et la police métriquement identique à « Arial
// Narrow » (Liberation Sans Narrow), code-barres Code 128 comme GenerateTicketServiceImpl.buildLineBarecode, QR de la
// prévente. Mesures : au seuil 128 (5.3.0), la majorité des traits verticaux des textes normaux n'a qu'UN point de large ;
// contraste renforcé : traits doublés, gras et barres inchangés, aucune lettre collée, code-barres et QR identiques.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/contraste_impression.dart';
import 'package:prestige_vente_app/services/impression_ticket.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/services/ticket_1bit.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/ticket_capture.dart';
import 'outils/tickets_vente_fictifs.dart';

Uint8List _ref(String nom) => File('test/references/tickets/image_serveur_fictive_$nom.png').readAsBytesSync();

/// Longueurs des suites de points noirs de chaque ligne, entre [y0] et [y1].
List<int> _suites(Raster1Bit r, int y0, int y1) {
  final out = <int>[];
  for (var y = y0; y < y1; y++) {
    var n = 0;
    for (var x = 0; x < r.largeur; x++) {
      if (r.noir(x, y)) {
        n++;
      } else if (n > 0) {
        out.add(n);
        n = 0;
      }
    }
    if (n > 0) out.add(n);
  }
  return out;
}

double _partFine(Raster1Bit r, int y0, int y1) {
  final s = _suites(r, y0, y1);
  return s.where((n) => n == 1).length / s.length;
}

int _suitesParLigne(Raster1Bit r, int y) => _suites(r, y, y + 1).length;

/// Lignes du code-barres : au moins 20 barres sur la ligne, identique à au moins 32 lignes voisines.
List<int> _lignesCodeBarres(Raster1Bit r) {
  final m = r.matrice();
  final out = <int>[];
  for (var y = 0; y < r.hauteur; y++) {
    if (_suitesParLigne(r, y) < 20) continue;
    var meme = 0;
    for (var k = y; k < r.hauteur && k < y + 32; k++) {
      if (listEquals(m[k], m[y])) meme++;
    }
    if (meme >= 32) out.add(y);
  }
  return out;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReglageContraste.reinitialiser();
  });

  group('conversion 1 bit renforcée (Ticket1Bit.renforcer)', () {
    test('trait vertical d\'un point → deux points ; trait de deux points, gras et colonnes hautes inchangés', () {
      const w = 12, h = 40;
      final n = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        if (y < 10) n[y * w + 1] = 1; // trait fin
        if (y < 10) {
          n[y * w + 5] = 1;
          n[y * w + 6] = 1; // trait de deux points
        }
        n[y * w + 9] = 1; // colonne de 40 points (barre de code-barres)
      }
      final r = Ticket1Bit.renforcer(n, w, h);
      expect([for (var x = 0; x < w; x++) r[x]], [0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 0]);
      expect([for (var x = 0; x < w; x++) r[20 * w + x]], [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0], reason: 'barre protégée');
    });

    test('deux traits fins séparés d\'un point blanc : jamais collés', () {
      const w = 6, h = 1;
      final r = Ticket1Bit.renforcer(Uint8List.fromList([1, 0, 1, 0, 0, 0]), w, h);
      expect(r, [1, 0, 1, 1, 0, 0]);
    });

    test('voisin d\'une barre protégée : pas d\'épaississement vers elle', () {
      const w = 4, h = 40;
      final n = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        n[y * w + 3] = 1;
      }
      n[0 * w + 1] = 1;
      final r = Ticket1Bit.renforcer(n, w, h);
      expect([for (var x = 0; x < w; x++) r[x]], [0, 1, 0, 1]);
    });

    // 58 mm (SUNMI V3 : 384 points, police de 8 points) : la majorité des traits n'a qu'un point au seuil 128 ;
    // 80 mm (police de 9 points) : traits déjà plus épais, le renforcement ne touche que les rares traits fins.
    for (final (nom, points, finMin) in [('assurance_58', 384, 0.5), ('assurance_80', 576, 0.0)]) {
      test('ticket assurance $nom (serveur, fictif) : traits fins doublés, largeur exacte, lettres jamais collées', () {
        final png = _ref(nom);
        final avant = Ticket1Bit.depuisPng(png, largeurMax: points)!;
        final apres = Ticket1Bit.depuisPng(png, largeurMax: points, contraste: ContrasteImpression.renforce)!;
        final seuil160 = Ticket1Bit.depuisPng(png, largeurMax: points, seuilNoir: Ticket1Bit.seuilRenforce)!;
        expect((apres.largeur, apres.hauteur), (avant.largeur, avant.hauteur), reason: 'aucun redimensionnement');
        expect(apres.largeur, points);
        // Bloc des libellés (« Matricule assuré » … organismes) : sous le titre, au-dessus du produit.
        final y0 = (avant.hauteur * 0.30).round(), y1 = (avant.hauteur * 0.48).round();
        final finAvant = _partFine(avant, y0, y1), finApres = _partFine(apres, y0, y1);
        expect(finAvant, greaterThan(finMin), reason: '5.3.0 : traits d\'un seul point (mesuré : $finAvant)');
        expect(finApres, lessThan(0.15), reason: 'renforcé : traits d\'au moins deux points (mesuré : $finApres)');
        expect(finApres, lessThan(finAvant));
        expect(apres.pointsNoirs, greaterThan(avant.pointsNoirs));
        // Aucune lettre collée : chaque ligne garde autant de suites noires qu'au seuil 160.
        for (var y = 0; y < apres.hauteur; y++) {
          expect(_suitesParLigne(apres, y), _suitesParLigne(seuil160, y), reason: 'ligne $y');
        }
        // Code-barres : mêmes barres, au point près, qu'en 5.3.0.
        final lignes = _lignesCodeBarres(avant);
        expect(lignes, isNotEmpty, reason: 'code-barres du pied trouvé');
        final ma = avant.matrice(), mb = apres.matrice();
        for (final y in lignes) {
          final fin = ma[y].lastIndexOf(true);
          expect(mb[y].sublist(0, fin + 2), ma[y].sublist(0, fin + 2), reason: 'ligne $y du code-barres');
        }
      });
    }

    test('prévente (QR du serveur) : QR identique module par module, texte renforcé', () {
      final png = _ref('prevente_58');
      final avant = Ticket1Bit.depuisPng(png, largeurMax: 384)!;
      final apres = Ticket1Bit.depuisPng(png, largeurMax: 384, contraste: ContrasteImpression.renforce)!;
      // QR : bloc carré en bas à gauche (pied) ; ses points ne changent pas.
      final ma = avant.matrice(), mb = apres.matrice();
      var bas = avant.hauteur - 1;
      while (bas > 0 && !ma[bas].contains(true)) {
        bas--;
      }
      var differences = 0;
      for (var y = bas - 200; y <= bas; y++) {
        for (var x = 0; x < 230; x++) {
          if (ma[y][x] != mb[y][x] && _dansQr(ma, x, y)) differences++;
        }
      }
      expect(differences, 0);
      expect(apres.pointsNoirs, greaterThan(avant.pointsNoirs));
    });

    test('performance : ticket 576 × 2 400 renforcé en moins de 2 s', () {
      final png = _ref('assurance_80');
      final sw = Stopwatch()..start();
      for (var i = 0; i < 3; i++) {
        Ticket1Bit.depuisPng(png, largeurMax: 576, contraste: ContrasteImpression.renforce);
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('réglage « Contraste d\'impression »', () {
    test('renforcé par défaut ; « normal » gardé sur l\'appareil ; rendu normal = celui de la 5.3.0', () async {
      expect(ReglageContraste.courant.value, ContrasteImpression.renforce);
      await ReglageContraste.charger();
      expect(ReglageContraste.courant.value, ContrasteImpression.renforce);
      final t = TicketImage(modele: 'VENTE_ASSURANCE', png: _ref('assurance_58'), largeurPoints: 384, hauteurPoints: 904);
      final renforce = ImpressionTicket.rasters([t], 384)!.single;
      await ReglageContraste.choisir(ContrasteImpression.normal);
      expect((await SharedPreferences.getInstance()).getString(ReglageContraste.cle), 'normal');
      ReglageContraste.reinitialiser();
      await ReglageContraste.charger();
      expect(ReglageContraste.courant.value, ContrasteImpression.normal);
      final normal = ImpressionTicket.rasters([t], 384)!.single;
      expect(normal.octets, Ticket1Bit.depuisPng(t.png, largeurMax: 384)!.octets, reason: 'identique à la 5.3.0');
      expect(renforce.octets, isNot(normal.octets));
    });

    testWidgets('gabarit local (police de l\'imprimante) : texte en gras de l\'imprimante si renforcé, comme avant si normal', (t) async {
      Future<(int, int)> imprimer(ContrasteImpression c) async {
        ReglageContraste.reinitialiser(c);
        final appels = await appelsSunmi(t, (ctx) => ReceiptService().printBorneTicket(
            officine: 'PHARMACIE FICTIVE', numero: '12', reference: 'REF-FICT-1', lignes: const ['PRODUIT FICTIF x1', 'PRODUIT FICTIF B x2'], pied: const ['Merci', 'Donnees fictives'], codeType: 'QR_CODE'));
        final gras = appels.where((a) => a.startsWith('RAW_DATA') && a.contains('[27, 69, 1]')).length;
        return (gras, appels.where((a) => a.startsWith('PRINT_TEXT')).length);
      }

      final (grasN, textesN) = await imprimer(ContrasteImpression.normal);
      final (grasR, textesR) = await imprimer(ContrasteImpression.renforce);
      expect(textesR, textesN, reason: 'mêmes lignes');
      expect(grasN, 4, reason: 'normal : officine, titre, numéro, 1ʳᵉ ligne du pied (comme avant)');
      expect(grasR, textesR, reason: 'renforcé : chaque ligne en gras');
    });

    testWidgets('Réglages › Impression : « Normal » / « Renforcé », appliqué et gardé ; rétabli par défaut', (t) async {
      t.view.physicalSize = const Size(720, 1400);
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.reset);
      final s = SettingsProvider();
      await s.loadSettings();
      await t.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(value: s, child: MaterialApp(home: ImpressionPage(printTest: (_) async {}))));
      await t.pumpAndSettle();
      expect(find.text('CONTRASTE D\'IMPRESSION'), findsOneWidget);
      expect(find.textContaining('Traits fins épaissis'), findsOneWidget);
      await t.tap(find.descendant(of: find.byKey(const ValueKey('contraste-impression')), matching: find.text('Normal')));
      await t.pumpAndSettle();
      expect(ReglageContraste.courant.value, ContrasteImpression.normal);
      expect((await SharedPreferences.getInstance()).getString(ReglageContraste.cle), 'normal');
      expect(find.textContaining('Rendu d\'avant la 5.4.0'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Rétablir les valeurs par défaut'), 200, scrollable: find.byType(Scrollable).first);
      await t.ensureVisible(find.text('Rétablir les valeurs par défaut'));
      await t.pumpAndSettle();
      await t.tap(find.text('Rétablir les valeurs par défaut'));
      await t.pumpAndSettle();
      expect(find.textContaining('contraste renforcé'), findsOneWidget);
      await t.tap(find.text('Rétablir'));
      await t.pumpAndSettle();
      expect(ReglageContraste.courant.value, ContrasteImpression.renforce);
      expect(t.takeException(), isNull);
    });

    test('données fictives seulement dans les références', () {
      expect(officineTicket.nomComplet, contains('Fictive'));
    });
  });
}

/// Le point (x, y) est-il dans un module de QR (zone dont les lignes voisines ont au moins 6 suites noires) ?
bool _dansQr(List<List<bool>> m, int x, int y) {
  var suites = 0;
  var avant = false;
  for (var k = 0; k < 230 && k < m[y].length; k++) {
    if (m[y][k] && !avant) suites++;
    avant = m[y][k];
  }
  return suites >= 6 && x < 230;
}
