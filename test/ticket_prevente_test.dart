// Ticket de PRÉVENTE (4.1.1) : réglage « Afficher les produits sur le ticket de prévente » (Réglages › Impression
// et Configuration d'origine, désactivé par défaut) et nom de produit long sur deux lignes.
//
//  - Unitaires : coupure des noms (deux lignes, sans couper un mot si possible, « .. » au-delà), lignes produits,
//    nombre d'articles, réglage enregistré.
//  - Contenu du ticket (impression Sunmi simulée par le canal `sunmi_printer_plus`, et aperçu du mode test) :
//    lignes produits présentes / absentes selon le réglage, totaux, référence et code identiques.
//  - Borne : nom long sur deux lignes (capture « …CPR EFFV » sans « B/20 »), ticket discret inchangé.
//  - Non-régression : avec les réglages par défaut, TOUS les tickets (prévente comptant / assurance / carnet, vente,
//    vente assurance, borne aux noms courts ; 58 / 80 mm, QR / code-barres, provisoire ou non, Sunmi et aperçu)
//    sont identiques, appel par appel, à ceux de la 4.1.0 (`test/ticket_prevente_reference.json`).
//  - Écrans : interrupteur dans Réglages › Impression (nouvelle interface) et dans la Configuration d'origine.
// Données fictives uniquement.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/parametres/parametres_logic.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/settings_screen.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/services/ticket_prevente.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/app_e2e.dart';
import 'outils/ticket_capture.dart';

/// Lignes de totaux d'un ticket (montants) : identiques avec ou sans produits.
List<String> _totaux(List<String> lignes) =>
    [for (final l in lignes) if (RegExp(r'^(NET A PAYER|Total Brut|Part Assurance|PART CLIENT|TOTAL)').hasMatch(l.trim())) l.trim()];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Unitaires : nom du produit et lignes produits', () {
    test('nom qui tient : une ligne, complétée par des espaces (comme avant)', () {
      expect(TicketPrevente.nom('EFFERALGAN 500MG', 32), ['EFFERALGAN 500MG'.padRight(32)]);
      expect(TicketPrevente.nom('X' * 32, 32), ['X' * 32]);
    });

    test('nom de la capture de la borne (37 caractères) : deux lignes, « B/20 » n\'est plus perdu', () {
      final l = TicketPrevente.nom('PARACETAMOL BIOGARAN 1G CPR EFFV B/20', 32);
      expect(l.map((e) => e.trimRight()), ['PARACETAMOL BIOGARAN 1G CPR EFFV', 'B/20']);
      expect(l.every((e) => e.length == 32), isTrue);
      // 80 mm (48 caractères) : tient sur une ligne.
      expect(TicketPrevente.nom('PARACETAMOL BIOGARAN 1G CPR EFFV B/20', 48).single.trimRight(), 'PARACETAMOL BIOGARAN 1G CPR EFFV B/20');
    });

    test('coupure à un espace : aucun mot coupé quand c\'est possible', () {
      final l = TicketPrevente.nom('DOLIPRANE 1000MG COMPRIMES PELLICULES BOITE', 32).map((e) => e.trimRight()).toList();
      expect(l, ['DOLIPRANE 1000MG COMPRIMES', 'PELLICULES BOITE']);
      for (final mot in 'DOLIPRANE 1000MG COMPRIMES PELLICULES BOITE'.split(' ')) {
        expect(l.any((x) => x.split(' ').contains(mot)), isTrue, reason: mot);
      }
    });

    test('mot plus long que la ligne : coupé (seul cas), suite sur la 2e ligne', () {
      final l = TicketPrevente.nom('${'A' * 40} B', 32).map((e) => e.trimRight()).toList();
      expect(l, ['A' * 32, '${'A' * 8} B']);
    });

    test('au-delà de deux lignes : « .. » signale le nom raccourci, jamais plus de deux lignes', () {
      final l = TicketPrevente.nom('DOLIPRANE 1000MG COMPRIMES PELLICULES BOITE DE 8 SECABLES SANS SUCRE', 32);
      expect(l, hasLength(2));
      expect(l.last.trimRight(), endsWith('..'));
      expect(l.every((e) => e.length == 32), isTrue);
    });

    test('lignes d\'un produit : nom puis « quantité x prix » et total alignés à droite', () {
      final l = TicketPrevente.produit(article('EFFERALGAN 500MG', 2, 1200), 32);
      expect(l, hasLength(2));
      expect(l[1], startsWith('  2 x 1'));
      expect(l[1].length, 32);
      expect(l[1].trimRight(), endsWith('2 400'));
      expect(TicketPrevente.nombreArticles(articlesFictifs), 6);
      expect(TicketPrevente.articles(1), '1 article');
      expect(TicketPrevente.articles(6), '6 articles');
    });

    test('lignes sans nom (référence seule) ignorées ; chargement seulement si le réglage est activé', () async {
      final vide = SaleItemDetail(
          lgPREENREGISTREMENTDETAILID: '', lgFAMILLEID: '', strNAME: '', intCIP: '', intQUANTITY: 0, intPRICEUNITAIR: 0, intPRICE: 0, strREF: 'R');
      expect(TicketPrevente.imprimables([vide, ...articlesFictifs]), articlesFictifs);
      var appels = 0;
      Future<List<SaleItemDetail>> charger() async {
        appels++;
        return articlesFictifs;
      }

      expect(await TicketPrevente.chargerProduits(false, charger), isEmpty);
      expect(appels, 0, reason: 'réglage désactivé : aucune requête');
      expect(await TicketPrevente.chargerProduits(true, charger), articlesFictifs);
      expect(await TicketPrevente.chargerProduits(true, () async => throw Exception('panne')), isEmpty);
    });

    test('réglage : désactivé par défaut, enregistré, relu au démarrage', () async {
      final s = SettingsProvider();
      await s.loadSettings();
      expect(s.afficherProduitsPrevente, isFalse);
      expect(ParametresSummary.impression(s), isNot(contains('produits')));
      await s.setAfficherProduitsPrevente(true);
      expect(ParametresSummary.impression(s), contains('produits sur la prévente'));
      final relu = SettingsProvider();
      await relu.loadSettings();
      expect(relu.afficherProduitsPrevente, isTrue);
      expect(rubriqueMatches(Rubrique.impression, '', 'prévente'), isTrue);
    });
  });

  group('Contenu du ticket de prévente (Sunmi simulé)', () {
    final r = ReceiptService();

    for (final largeur in [58, 80]) {
      testWidgets('comptant $largeur mm : produits selon le réglage, totaux et code identiques', (t) async {
        Future<ImprimanteSimulee> imprimer(bool afficher) async {
          final ctx = await contexteTicket(t);
          final p = ImprimanteSimulee()..installer(t);
          await r.printPreventeTicket(
              context: ctx, officine: officineFictive, saleSummary: resumeFictif, currentUser: userFictif, isTestMode: false,
              paperWidth: largeur, ticketCodeType: 'QR_CODE', items: articlesFictifs, afficherProduits: afficher);
          p.retirer(t);
          return p;
        }

        final sans = await imprimer(false), avec = await imprimer(true);
        final cols = TicketPrevente.colonnes(largeur);
        // Désactivé : aucun nom, aucune ligne quantité × prix.
        for (final a in articlesFictifs) {
          expect(sans.textes.any((l) => l.contains(a.strNAME.substring(0, 10))), isFalse, reason: a.strNAME);
        }
        expect(sans.textes.any((l) => l.contains(' x ')), isFalse);
        // Activé : toutes les lignes produits, puis le nombre d'articles.
        final attendues = TicketPrevente.produits(articlesFictifs, cols);
        final i = avec.textes.indexOf(attendues.first);
        expect(i, greaterThan(0));
        expect(avec.textes.sublist(i, i + attendues.length), attendues);
        expect(avec.textes, contains('6 articles'));
        if (largeur == 58) {
          expect(avec.textes, contains('B/20'.padRight(32)), reason: 'nom long sur deux lignes');
        }
        // Le reste du ticket est le même : en-tête, totaux, référence, QR, vendeur.
        final reste = [for (final l in avec.textes) if (!attendues.contains(l) && l != '6 articles') l];
        expect(reste, [...sans.textes.take(sans.textes.indexOf('NET A PAYER: 6 650')), List.filled(cols, '-').join(), ...sans.textes.skip(sans.textes.indexOf('NET A PAYER: 6 650'))]);
        expect(_totaux(avec.textes), _totaux(sans.textes));
        expect(avec.appels.where((a) => a.startsWith('PRINT_QRCODE')), sans.appels.where((a) => a.startsWith('PRINT_QRCODE')));
        expect(avec.textes, contains(resumeFictif.reference));
      });
    }

    testWidgets('assurance et carnet : produits selon le réglage, part assurance et part client identiques', (t) async {
      for (final carnet in [false, true]) {
        Future<ImprimanteSimulee> imprimer(bool afficher) async {
          final ctx = await contexteTicket(t);
          final p = ImprimanteSimulee()..installer(t);
          await r.printAssurancePreventeTicket(
              context: ctx, officine: officineFictive, saleSummary: resumeAssuranceFictif, items: articlesFictifs, client: clientFictif,
              ayantDroit: ayantDroitFictif, currentUser: userFictif, isTestMode: false, paperWidth: 58, ticketCodeType: 'BARCODE',
              carnet: carnet, reference: '20261014000043', afficherProduits: afficher);
          p.retirer(t);
          return p;
        }

        final sans = await imprimer(false), avec = await imprimer(true);
        expect(sans.textes.any((l) => l.contains('EFFERALGAN')), isFalse);
        expect(avec.textes, containsAllInOrder([...TicketPrevente.produits(articlesFictifs, 32), '6 articles']));
        expect(_totaux(avec.textes), _totaux(sans.textes));
        expect(_totaux(sans.textes), containsAll(['Part Assurance: 5 320', 'PART CLIENT: 1 330']));
        expect(avec.textes.first, sans.textes.first);
        expect(avec.textes, contains(carnet ? 'PRE-VENTE CARNET' : 'PRE-VENTE ASSURANCE'));
        expect(avec.appels.where((a) => a.startsWith('PRINT_BARCODE')), sans.appels.where((a) => a.startsWith('PRINT_BARCODE')));
      }
    });

    testWidgets('prévente provisoire (hors ligne) : produits si activé, toujours sans code', (t) async {
      final ctx = await contexteTicket(t);
      final p = ImprimanteSimulee()..installer(t);
      await r.printPreventeTicket(
          context: ctx, officine: officineFictive, saleSummary: resumeFictif, currentUser: userFictif, isTestMode: false, paperWidth: 58,
          ticketCodeType: 'QR_CODE', provisoire: 'HL-0007', items: articlesFictifs, afficherProduits: true);
      p.retirer(t);
      expect(p.textes, contains(provisoireTitre('HL-0007')));
      expect(p.textes, contains('6 articles'));
      expect(p.appels.any((a) => a.startsWith('PRINT_QRCODE')), isFalse);
    });

    testWidgets('aperçu (mode test) : mêmes lignes produits, absentes si désactivé', (t) async {
      final avec = await apercu(t, (c) => r.printPreventeTicket(
          context: c, officine: officineFictive, saleSummary: resumeFictif, currentUser: userFictif, isTestMode: true, paperWidth: 58,
          ticketCodeType: 'QR_CODE', items: articlesFictifs, afficherProduits: true));
      expect(avec, containsAllInOrder([...TicketPrevente.produits(articlesFictifs, 32), '6 articles', 'NET A PAYER: 6 650', '[QR]']));
      final sans = await apercu(t, (c) => r.printPreventeTicket(
          context: c, officine: officineFictive, saleSummary: resumeFictif, currentUser: userFictif, isTestMode: true, paperWidth: 58,
          ticketCodeType: 'QR_CODE', items: articlesFictifs));
      expect(sans.any((l) => l.contains('EFFERALGAN')), isFalse);
      expect(_totaux(avec), _totaux(sans));
      final assurance = await apercu(t, (c) => r.printAssurancePreventeTicket(
          context: c, officine: officineFictive, saleSummary: resumeAssuranceFictif, items: articlesFictifs, client: clientFictif,
          ayantDroit: ayantDroitFictif, currentUser: userFictif, isTestMode: true, paperWidth: 80, ticketCodeType: 'QR_CODE',
          reference: '20261014000043', afficherProduits: true));
      expect(assurance, containsAllInOrder(['Matricule: M-001', ...TicketPrevente.produits(articlesFictifs, 48), '6 articles', 'PART CLIENT: 1 330']));
    });
  });

  group('Borne : réglage propre « ticket discret », nom long sur deux lignes', () {
    test('nom de la capture : deux lignes sur 58 mm, total inchangé', () {
      final lignes = [article('PARACETAMOL BIOGARAN 1G CPR EFFV B/20', 1, 950)];
      final tk = BorneTicket(officine: 'Pharmacie Fictive', prevente: preventeBorne(lignes)).lignes;
      expect(tk.map((l) => l.trimRight()), ['PARACETAMOL BIOGARAN 1G CPR EFFV', 'B/20', '  1 x 950                    950', '-' * 32, 'TOTAL A PAYER: 950 F']);
    });

    test('ticket discret : aucun nom, nombre d\'articles et total identiques', () {
      final p = preventeBorne(articlesFictifs);
      final detail = BorneTicket(officine: 'P', prevente: p).lignes;
      final discret = BorneTicket(officine: 'P', prevente: p, discret: true).lignes;
      expect(discret, ['6 articles', '-' * 32, 'TOTAL A PAYER: 6 650 F']);
      expect(detail.last, discret.last);
      expect(detail, containsAll(TicketPrevente.produits(articlesFictifs, 32)));
    });
  });

  group('Non-régression : réglages par défaut = tickets de la 4.1.0', () {
    testWidgets('tous les tickets identiques appel par appel (Sunmi) et ligne par ligne (aperçu, borne)', (t) async {
      final reference = (jsonDecode(File('test/ticket_prevente_reference.json').readAsStringSync()) as Map)
          .map((k, v) => MapEntry('$k', [for (final l in v as List) '$l']));
      final actuels = await tousLesTicketsParDefaut(t);
      expect(actuels.keys.toSet(), reference.keys.toSet());
      for (final k in reference.keys) {
        expect(actuels[k], reference[k], reason: k);
      }
    });

    testWidgets('produits fournis mais réglage désactivé : ticket d\'origine', (t) async {
      final reference = (jsonDecode(File('test/ticket_prevente_reference.json').readAsStringSync()) as Map);
      for (final largeur in [58, 80]) {
        final appels = await appelsSunmi(t, (c) => ReceiptService().printPreventeTicket(
            context: c, officine: officineFictive, saleSummary: resumeFictif, currentUser: userFictif, isTestMode: false, paperWidth: largeur,
            ticketCodeType: 'QR_CODE', items: articlesFictifs, afficherProduits: false));
        expect(appels, reference['prevente $largeur QR_CODE prov=null sunmi']);
        final assurance = await appelsSunmi(t, (c) => ReceiptService().printAssurancePreventeTicket(
            context: c, officine: officineFictive, saleSummary: resumeAssuranceFictif, items: articlesFictifs, client: clientFictif,
            ayantDroit: ayantDroitFictif, currentUser: userFictif, isTestMode: false, paperWidth: largeur, ticketCodeType: 'QR_CODE',
            carnet: true, reference: '20261014000043', afficherProduits: false));
        expect(assurance, reference['prevente-assurance carnet=true $largeur QR_CODE prov=null sunmi']);
      }
    });
  });

  group('Écrans de réglage', () {
    testWidgets('Réglages › Impression : interrupteur désactivé par défaut, appliqué immédiatement, rétabli par défaut', (t) async {
      t.view.physicalSize = const Size(720, 1400);
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.reset);
      final s = SettingsProvider();
      await s.loadSettings();
      await t.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
        value: s,
        child: MaterialApp(home: ImpressionPage(printTest: (_) async {})),
      ));
      await t.pumpAndSettle();
      final carte = find.byKey(const Key('afficher_produits_prevente'));
      await t.scrollUntilVisible(carte, 120, scrollable: find.byType(Scrollable).first);
      await t.ensureVisible(carte);
      await t.pumpAndSettle();
      expect(find.text(TicketPrevente.libelleReglage), findsOneWidget);
      expect(find.textContaining('Ticket discret'), findsOneWidget, reason: 'phrase d\'aide : la borne a son propre réglage');
      Switch inter() => t.widget<Switch>(find.descendant(of: carte, matching: find.byType(Switch)));
      expect(inter().value, isFalse);
      await t.tap(carte);
      await t.pumpAndSettle();
      expect(s.afficherProduitsPrevente, isTrue);
      expect(inter().value, isTrue);
      expect((await SharedPreferences.getInstance()).getBool(SettingsProvider.afficherProduitsPreventeKey), isTrue);

      await t.scrollUntilVisible(find.text('Rétablir les valeurs par défaut'), 200, scrollable: find.byType(Scrollable).first);
      await t.ensureVisible(find.text('Rétablir les valeurs par défaut'));
      await t.pumpAndSettle();
      await t.tap(find.text('Rétablir les valeurs par défaut'));
      await t.pumpAndSettle();
      expect(find.textContaining('produits non affichés sur la prévente'), findsOneWidget);
      await t.tap(find.text('Rétablir'));
      await t.pumpAndSettle();
      expect(s.afficherProduitsPrevente, isFalse);
      expect(t.takeException(), isNull);
    });

    testWidgets('Configuration d\'origine : même réglage, désactivé par défaut, enregistré', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      final app = AppE2E();
      await app.preparer(interfaceNouvelle: false, prefs: const {'local_ip': '', 'remote_ip': ''});
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byType(SettingsScreen)), isTrue);
      await app.attendre(t);
      final settings = Provider.of<SettingsProvider>(t.element(find.byType(SettingsScreen)), listen: false);
      final zone = find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first;
      final ligne = find.byKey(const Key('origine_afficher_produits_prevente'));
      await app.defilerJusqua(t, ligne, zone: zone);
      expect(find.descendant(of: ligne, matching: find.text(TicketPrevente.libelleReglage)), findsOneWidget);
      expect(find.text(TicketPrevente.aideReglage), findsOneWidget);
      final inter = find.descendant(of: ligne, matching: find.byType(Switch));
      expect(t.widget<Switch>(inter).value, isFalse);
      await t.tap(inter);
      await t.pump();
      expect(settings.afficherProduitsPrevente, isTrue);
      expect(t.widget<Switch>(inter).value, isTrue);
      expect(t.takeException(), isNull);
      await app.fermer(t);
    });
  });
}
