// Captures PNG RÉELLES (rendu Flutter, faux serveur, données FICTIVES) — 4.14.0 : zone Remise de la vente comptant et
// aperçus des tickets comptant / assurance / carnet AVEC remise, mis en page comme le serveur, en 58 et 80 mm ; plus
// le texte de chaque ticket (vidage). Sunmi V2s (720 × 1440) et tablette (1920 × 1200).
// Hors de la suite de la CI. Pour régénérer :
//   APERCUS=1 CAPTURES=/chemin flutter test test/outils/captures_ticket_remise_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/services/ticket_texte.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'app_e2e.dart';
import 'clients_vente_fictifs.dart';
import 'parcours_vente.dart';
import 'remises_fictives.dart';
import 'tickets_vente_fictifs.dart';

final _actif = Platform.environment.containsKey('APERCUS');
final _dossier = Platform.environment['CAPTURES'] ?? '/tmp/captures_ticket_remise';

Future<void> _polices() async {
  final dossier = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<ByteData> lire(String f) async => ByteData.sublistView(await File(f.startsWith('/') ? f : '$dossier/$f').readAsBytes());
  for (final famille in ['Roboto', 'FlutterTest', '', 'Ahem', 'sans-serif', 'Roboto Flex']) {
    final l = FontLoader(famille);
    for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
      l.addFont(lire(f));
    }
    await l.load();
  }
  // Police à chasse fixe du ticket (comme la police 12 × 24 de l'imprimante).
  final mono = FontLoader('monospace');
  for (final f in ['/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf']) {
    if (File(f).existsSync()) mono.addFont(lire(f));
  }
  await mono.load();
  await (FontLoader('MaterialIcons')..addFont(lire('MaterialIcons-Regular.otf'))).load();
}

Future<void> _capture(WidgetTester t, String nom) async {
  await t.pump();
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile(Uri.file('$_dossier/$nom.png')));
}

/// Aperçu d'un ticket sur fond gris, papier blanc à la largeur du rouleau.
Widget _papier(TicketTexte ticket) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFE5E7EB),
        body: SingleChildScrollView(
          child: Center(
            child: Container(
              width: ticket.colonnes == 32 ? 330 : 480,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: ReceiptService.apercuTicketTexte(ticket, 'QR_CODE'),
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    if (_actif) await _polices();
  });

  test('vidages texte des tickets (comptant, assurance, carnet, avec remise ; 58 et 80 mm)', () {
    Directory(_dossier).createSync(recursive: true);
    for (final e in ticketsReference().entries) {
      File('$_dossier/ticket_${e.key}.txt').writeAsStringSync('${e.value.texte}\n');
    }
  }, skip: !_actif);

  for (final (taille, code) in [(TailleEcran.sunmiV2s, 'sunmi_v2s'), (TailleEcran.tablette, 'tablette')]) {
    testWidgets('captures remise — $code', (t) async {
      taille.appliquer(t);
      TicketServeur.oublier();
      final app = AppE2E();
      CatalogueFictif(app.serveur, nombre: 10);
      ClientsVenteFictifs(app.serveur);
      RemisesFictives(app.serveur);
      await app.preparer(prefs: {...prefsVente, 'is_test_print_mode': true});
      await app.lancer(t);
      expect(await app.seConnecter(t), isTrue);
      await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
      expect(await ajouterAuPanier(t, app, nomCourt(3), qte: '4'), isTrue);
      await app.attendre(t, const Duration(seconds: 2));
      FocusManager.instance.primaryFocus?.unfocus();
      await app.attendre(t, const Duration(milliseconds: 500));
      await _capture(t, '${code}_1_remise_aucune');
      await t.tap(find.byKey(const ValueKey('remise-vente-choisir')));
      await app.attendre(t, const Duration(seconds: 1));
      await _capture(t, '${code}_2_liste_remises');
      await t.tap(find.byKey(const ValueKey('remise-option-REM-FICT-10')));
      await app.attendre(t, const Duration(seconds: 2));
      await _capture(t, '${code}_3_remise_appliquee');
      await t.tap(find.byKey(const ValueKey('vente-encaisser')));
      await app.attendreQue(t, find.text('Exact'));
      await t.tap(find.text('Exact'));
      await t.pump();
      final v = find.byKey(const ValueKey('encaissement-valider'));
      await t.ensureVisible(v);
      await t.tap(v);
      await app.attendre(t, const Duration(seconds: 3));
      await _capture(t, '${code}_4_ticket_comptant_remise');
      await t.tap(find.text('Fermer'));
      await app.attendre(t);
      await app.fermer(t);
    }, skip: !_actif);
  }

  for (final p in [58, 80]) {
    testWidgets('captures tickets $p mm (comptant, assurance, carnet avec remise)', (t) async {
      t.view.physicalSize = const Size(1040, 2600);
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.reset);
      for (final (nom, ticket) in [('comptant', ticketComptant(p)), ('assurance', ticketAssurance(p)), ('carnet', ticketCarnet(p))]) {
        await t.pumpWidget(_papier(ticket));
        await t.pumpAndSettle();
        await _capture(t, 'ticket_${nom}_remise_${p}mm');
      }
    }, skip: !_actif);
  }
}
