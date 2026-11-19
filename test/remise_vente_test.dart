// ÉCRANS — 4.14.0 : remise sur les ventes comptant, assurance et carnet (demande du pharmacien du 19/11/2026).
// Contrat du web (lib/ventes/common/remise_vente.dart), passerelle simulée, données FICTIVES :
//  - liste du serveur (mêmes choix que le web, « SANS REMISE » = « Retirer ») ;
//  - remise appliquée seulement après `success:true`, net relu sur le serveur AVEC la remise (sinon net/vno l'efface) ;
//  - retrait ; refus (msg tel quel, état gardé) ; 403 interdit → zone masquée pour la session ; réponse perdue → relue ;
//  - droits : compte sans « terminer une vente » (profil prévente) → pas de remise ; droit P_REMISE_VENTE → remise ;
//  - hors ligne : jamais proposée ; reprise d'une vente remisée : remise relue AVANT le net ;
//  - assurance / carnet : même contrat (net/assurance lit la remise de la vente, à défaut celle du client) ;
//  - passerelle sans la capacité : aucune zone (écran d'avant inchangé).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/ventes/common/remise_vente.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';

import 'client_vente_test.dart' show FauxVenteClient, FauxVenteSansClient, produitFictif, ouvrirVente, ajouterArticle, encaisserEspeces;

const remisesFictives = [RemiseOption(id: 'REM-FICT-10', nom: 'REMISE FICTIVE 10 %'), RemiseOption(id: 'REM-FICT-5', nom: 'REMISE FICTIVE 5 %')];

/// Passerelle comptant avec la remise (règles du serveur : remise de la vente, net/vno sans remiseId = remise effacée).
class FauxVenteRemise extends FauxVenteClient implements RemiseVenteGateway {
  final Map<String, String> remiseDe = {};
  final List<(String, String?)> poses = [];
  final List<(String, String?)> nets = [];
  VenteResult<void> Function(String? remiseId)? reponsePose;
  VenteResult<List<RemiseOption>>? reponseListe;
  int listes = 0;

  int _remise(String venteId, String? remiseId) {
    final posee = remiseDe[venteId];
    if (remiseId == null || posee == null) return 0;
    final t = (ventes[venteId] ?? const []).fold<int>(0, (s, i) => s + i.intPRICE);
    final taux = posee == 'REM-FICT-10' ? 10 : 5;
    final net = ((t - t * taux ~/ 100) / 5).round() * 5;
    return t - net;
  }

  @override
  Future<VenteResult<List<RemiseOption>>> remisesVente() async {
    listes++;
    return reponseListe ?? const VenteOk(remisesFictives);
  }

  @override
  Future<VenteResult<void>> appliquerRemise(String venteId, String? remiseId) async {
    poses.add((venteId, remiseId));
    final f = reponsePose;
    if (f != null) {
      final r = f(remiseId);
      if (r is VenteFailed<void> && r.maybeApplied) {
        // Appliquée sur le serveur, réponse perdue.
        if (remiseId == null) {
          remiseDe.remove(venteId);
        } else {
          remiseDe[venteId] = remiseId;
        }
      }
      return r;
    }
    if (remiseId == null) {
      remiseDe.remove(venteId);
    } else {
      remiseDe[venteId] = remiseId;
    }
    return const VenteOk(null);
  }

  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) => netVnoRemise(venteId, null);

  @override
  Future<VenteResult<SaleSummary>> netVnoRemise(String venteId, String? remiseId) async {
    nets.add((venteId, remiseId));
    final t = (ventes[venteId] ?? const []).fold<int>(0, (s, i) => s + i.intPRICE);
    final r = _remise(venteId, remiseId);
    return VenteOk(SaleSummary(montant: t, remise: r, montantNet: t - r, venteId: venteId, reference: 'REF-$venteId'));
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId) async {
    final r = await super.fullSale(venteId);
    return r.map((m) => {...m, 'lgREMISEID': remiseDe[venteId]});
  }
}

final zoneRemise = find.byKey(const ValueKey('remise-vente-zone'));
final choisirRemise = find.byKey(const ValueKey('remise-vente-choisir'));
final retirerRemise = find.byKey(const ValueKey('remise-vente-retirer'));
final nomRemise = find.byKey(const ValueKey('remise-vente-nom'));
final montantRemise = find.byKey(const ValueKey('remise-vente-montant'));

void _telephone(WidgetTester t) {
  t.view.physicalSize = const Size(720, 1440);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
}

Future<void> choisir(WidgetTester t, String id) async {
  await t.tap(choisirRemise);
  await t.pumpAndSettle();
  await t.tap(find.byKey(ValueKey('remise-option-$id')));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    DroitsVente.instance.fixer(null);
    DroitsVente.instance.oublierControles();
  });

  testWidgets('passerelle sans la capacité : aucune zone Remise (écran d\'avant inchangé)', (t) async {
    _telephone(t);
    final gw = FauxVenteClient();
    await ouvrirVente(t, gw);
    await ajouterArticle(t);
    expect(zoneRemise, findsNothing);
  });

  testWidgets('comptant : choisir → appliquée après le serveur, net relu AVEC la remise, puis encaissée', (t) async {
    _telephone(t);
    final gw = FauxVenteRemise();
    await ouvrirVente(t, gw);
    expect(zoneRemise, findsNothing, reason: 'avant la création de la vente');
    await ajouterArticle(t);
    expect(zoneRemise, findsOneWidget);
    expect(t.widget<Text>(montantRemise).data, 'Aucune remise');
    await t.tap(choisirRemise);
    await t.pumpAndSettle();
    expect(find.text('REMISE FICTIVE 10 %'), findsOneWidget);
    expect(find.text('REMISE FICTIVE 5 %'), findsOneWidget);
    expect(find.text('SANS REMISE'), findsNothing, reason: '« Retirer » à la place');
    await t.tap(find.byKey(const ValueKey('remise-option-REM-FICT-10')));
    await t.pumpAndSettle();
    expect(gw.poses, [('V1', 'REM-FICT-10')]);
    expect(gw.nets.last, ('V1', 'REM-FICT-10'), reason: 'net/vno envoyé avec la remise');
    expect(t.widget<Text>(nomRemise).data, 'REMISE FICTIVE 10 %');
    expect(find.text('Remise appliquée : REMISE FICTIVE 10 %.'), findsOneWidget);
    // Ajout d'un article : le net garde la remise.
    await ajouterArticle(t);
    expect(gw.nets.last, ('V1', 'REM-FICT-10'));
    await encaisserEspeces(t);
    expect(gw.clotureClientIds, hasLength(1));
  });

  testWidgets('retirer : POST remise null, net sans remise ; refus : message tel quel, remise gardée', (t) async {
    _telephone(t);
    final gw = FauxVenteRemise();
    await ouvrirVente(t, gw);
    await ajouterArticle(t);
    await choisir(t, 'REM-FICT-5');
    gw.reponsePose = (_) => const VenteRefused('Erreur::: L\'Opération n\'a pas aboutie');
    await t.tap(retirerRemise);
    await t.pumpAndSettle();
    expect(find.text('Erreur::: L\'Opération n\'a pas aboutie'), findsOneWidget);
    expect(t.widget<Text>(nomRemise).data, 'REMISE FICTIVE 5 %', reason: 'état gardé');
    gw.reponsePose = null;
    await t.tap(retirerRemise);
    await t.pumpAndSettle();
    expect(gw.poses.last, ('V1', null));
    expect(gw.nets.last, ('V1', null));
    expect(t.widget<Text>(montantRemise).data, 'Aucune remise');
    expect(retirerRemise, findsNothing);
  });

  testWidgets('403 interdit : message, remise masquée pour la session, jamais de déconnexion', (t) async {
    _telephone(t);
    final gw = FauxVenteRemise()..reponsePose = (_) => const VenteRefused('Accès refusé (droit fictif).', code: VenteRefused.codeInterdit);
    await ouvrirVente(t, gw);
    await ajouterArticle(t);
    await choisir(t, 'REM-FICT-10');
    expect(find.text('Accès refusé (droit fictif).'), findsOneWidget);
    await t.pumpAndSettle();
    expect(zoneRemise, findsNothing);
    expect(DroitsVente.instance.controle(droitRemiseVente), isTrue);
  });

  // 4.15.0 (décision du pharmacien du 19/11) : remise ouverte aux comptes de prévente, comme le web (4.14.0 : non).
  test('droits : profil prévente (sans terminer une vente) → remise, comme le web ; P_REMISE_VENTE → remise ; 403 → masquée', () {
    final d = DroitsVente();
    d.fixer(null);
    expect(remiseAutorisee(d), isTrue, reason: 'droits inconnus (serveur ancien) : comme avant, le serveur reste juge');
    d.fixer({'P_SM_CLOTURER_CAISSE'});
    expect(remiseAutorisee(d), isTrue);
    d.fixer({'P_PREVENTE_FICTIF'});
    expect(remiseAutorisee(d), isTrue, reason: '4.15.0 : compte de prévente, comme le web');
    d.fixer({'P_PREVENTE_FICTIF', droitRemiseVente});
    expect(remiseAutorisee(d), isTrue);
    d.fixer({'P_SM_CLOTURER_CAISSE'});
    d.controleConstate(droitRemiseVente);
    expect(remiseAutorisee(d), isFalse);
  });

  testWidgets('profil prévente : zone Remise proposée (4.15.0, comme le web)', (t) async {
    _telephone(t);
    DroitsVente.instance.fixer({'P_PREVENTE_FICTIF'});
    final gw = FauxVenteRemise();
    await ouvrirVente(t, gw);
    await ajouterArticle(t);
    expect(zoneRemise, findsOneWidget);
  });

  test('réponse perdue : la remise de la vente est relue, appliquée seulement si le serveur l\'a', () async {
    final gw = FauxVenteRemise()..delai = Duration.zero;
    final c = VenteController(gateway: gw);
    await c.addProduct(produitFictif, 2);
    gw.reponsePose = (_) => const VenteFailed('Le serveur met trop de temps à répondre.', maybeApplied: true);
    expect((await c.choisirRemise(remisesFictives.first)).isOk, isTrue);
    expect(c.remiseId, 'REM-FICT-10');
    expect(c.montantRemise, greaterThan(0));
    gw.reponsePose = (_) => const VenteFailed('Serveur injoignable.');
    final r = await c.choisirRemise(remisesFictives.last);
    expect(r.isOk, isFalse);
    expect(c.remiseId, 'REM-FICT-10', reason: 'non appliquée sans confirmation');
  });

  test('reprise d\'une vente remisée : remise relue AVANT le net (une seule lecture de la vente)', () async {
    final gw = FauxVenteRemise()..delai = Duration.zero;
    final c = VenteController(gateway: gw);
    await c.addProduct(produitFictif, 1);
    await c.choisirRemise(remisesFictives.first);
    final id = c.venteId!;
    final lecturesAvant = gw.lectures;
    final c2 = VenteController(gateway: gw);
    await c2.loadVente(id);
    expect(c2.remiseId, 'REM-FICT-10');
    expect(gw.nets.last, (id, 'REM-FICT-10'));
    expect(gw.lectures - lecturesAvant, 1);
  });

  test('vente terminée ou sans vente : refus clair, rien envoyé', () async {
    final gw = FauxVenteRemise()..delai = Duration.zero;
    final c = VenteController(gateway: gw);
    expect((await c.choisirRemise(remisesFictives.first)).message, contains('Aucune vente'));
    expect(gw.poses, isEmpty);
    expect(c.remiseDisponible, isFalse);
  });

  test('liste : lue une fois par vente ; panne → message (jamais « aucune remise »)', () async {
    final gw = FauxVenteRemise()..delai = Duration.zero;
    final c = VenteController(gateway: gw);
    await c.addProduct(produitFictif, 1);
    await c.remisesProposees();
    await c.remisesProposees();
    expect(gw.listes, 1);
    final gw2 = FauxVenteRemise()
      ..delai = Duration.zero
      ..reponseListe = const VenteFailed('Serveur injoignable (lire les remises)');
    final c2 = VenteController(gateway: gw2);
    await c2.addProduct(produitFictif, 1);
    expect((await c2.remisesProposees()).message, contains('injoignable'));
  });

  test('RemiseOption : « SANS REMISE » (id null) ignorée, nom par défaut', () {
    expect(RemiseOption.depuisJson({'lgREMISEID': null, 'strNAME': 'SANS REMISE'}), isNull);
    expect(RemiseOption.depuisJson({'lgREMISEID': 'R1', 'strNAME': ''})!.nom, 'Remise');
    expect(RemiseOption.depuisJson('x'), isNull);
  });

  test('FauxVenteSansClient reste utilisable (capacités indépendantes)', () {
    expect(FauxVenteSansClient() is RemiseVenteGateway, isFalse);
  });
}
