// 4.13.0 — e2e, application entière (faux serveur Prestige en mémoire, données FICTIVES) : client d'une vente comptant
// (demande du 13/11/2026), section « Pour vérifier » :
//  - client TROUVÉ puis encaissé : la vente porte ce client (clientId de la clôture = lgCLIENTID) ;
//  - client CRÉÉ depuis le téléphone : il est trouvé par la recherche du serveur, la vente lui est rattachée ;
//  - client choisi puis RETIRÉ (croix rouge, second appui) : la vente se termine sans client ;
//  - client choisi puis CHANGÉ : seul le second reste ;
//  - vente SANS client : mêmes requêtes qu'avant, sauf l'ancien « client = nom du mode » supprimé ;
//  - vente DÉJÀ TERMINÉE : rattachement refusé avec le message du serveur, nom jamais affiché ;
//  - espèces, puis mobile money (WAVE) : le client choisi n'est jamais remplacé à l'encaissement ;
//  - bilan : un seul client créé, aucune ligne de tiers payant, clôture identique à une vente sans client (stock,
//    caisse) hormis clientId ;
//  - reprise d'une vente : client lu avec la vente ; 403 `interdit` : msg, pas de déconnexion ; 409 → accueil.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';
import 'outils/clients_vente_fictifs.dart';
import 'outils/parcours_vente.dart';

final _zone = find.byKey(const ValueKey('client-vente-zone'));
final _ouvrir = find.byKey(const ValueKey('client-vente-ouvrir'));
final _nom = find.byKey(const ValueKey('client-vente-nom'));
final _croix = find.byKey(const ValueKey('client-vente-retirer'));
final _recherche = find.byKey(const ValueKey('client-vente-recherche'));
final _erreur = find.byKey(const ValueKey('client-vente-erreur'));
Finder _resultat(String id) => find.byKey(ValueKey('client-vente-resultat-$id'));

/// Vente comptant ouverte, un article au panier (vente V-1 créée sur le serveur).
Future<(AppE2E, ClientsVenteFictifs)> _vente(WidgetTester t, {TailleEcran taille = TailleEcran.sunmiV2s}) async {
  taille.appliquer(t);
  final app = AppE2E();
  CatalogueFictif(app.serveur, nombre: 10);
  final cl = ClientsVenteFictifs(app.serveur);
  await app.preparer(prefs: prefsVente);
  await app.lancer(t);
  expect(await app.seConnecter(t), isTrue);
  await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
  expect(_zone, findsNothing, reason: 'pas de zone Client avant la création de la vente');
  expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
  await app.attendre(t, const Duration(seconds: 2));
  expect(_zone, findsOneWidget, reason: 'zone Client après le 1er article');
  return (app, cl);
}

/// Ouvre la recherche, tape [texte] et choisit le client [id].
Future<void> _choisir(WidgetTester t, AppE2E app, String texte, String id) async {
  await t.tap(_ouvrir);
  await app.attendre(t, const Duration(milliseconds: 600));
  await t.enterText(_recherche, texte);
  expect(await app.attendreQue(t, _resultat(id)), isTrue, reason: 'résultat $id');
  await t.tap(_resultat(id));
  await app.attendre(t, const Duration(seconds: 1));
}

String _nomAffiche(WidgetTester t) => t.widget<Text>(_nom).data!;

void main() {
  testWidgets('client TROUVÉ puis encaissé : nom après success:true, clôture avec son lgCLIENTID, rien d\'autre', (t) async {
    final (app, cl) = await _vente(t);
    await _choisir(t, app, 'KOFFI', 'CL-FICT-1');
    expect(_nomAffiche(t), 'KOFFI-TEST AMANI');
    expect(find.text('0700000001'), findsOneWidget, reason: 'téléphone (strADRESSE) affiché');
    expect(cl.rattachements, [(venteId: 'V-1', clientId: 'CL-FICT-1')]);
    await validerEncaissementEspeces(t, app);
    await app.attendre(t, const Duration(seconds: 2));
    expect(find.textContaining('Vente encaissée'), findsOneWidget);
    expect(cl.clotures.single['clientId'], 'CL-FICT-1');
    expect(cl.clientDeVente['V-1'], 'CL-FICT-1', reason: 't_preenregistrement.lg_CLIENT_ID = le client');
    expect(cl.rattachements, hasLength(1), reason: 'plus aucun « client = mode de règlement » avant la clôture');
    expect(_zone, findsNothing, reason: 'nouvelle vente : plus de client affiché');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('client CRÉÉ depuis le téléphone : trouvé par la recherche du serveur, vente rattachée, un seul client créé',
      (t) async {
    final (app, cl) = await _vente(t);
    await t.tap(_ouvrir);
    await app.attendre(t, const Duration(milliseconds: 600));
    await t.tap(find.byKey(const ValueKey('client-vente-nouveau')));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('client-vente-nom-saisi')), 'Nouveau-Fictif');
    await t.enterText(find.byKey(const ValueKey('client-vente-prenom-saisi')), 'Essai');
    await t.enterText(find.byKey(const ValueKey('client-vente-telephone-saisi')), '0700009999');
    await t.ensureVisible(find.byKey(const ValueKey('client-vente-creer')));
    await t.tap(find.byKey(const ValueKey('client-vente-creer')));
    await app.attendre(t, const Duration(seconds: 1));
    expect(cl.creations, [
      {'strFIRSTNAME': 'Nouveau-Fictif', 'strLASTNAME': 'Essai', 'strADRESSE': '0700009999', 'lgTYPECLIENTID': '6'}
    ]);
    expect(_nomAffiche(t), 'NOUVEAU-FICTIF ESSAI', reason: 'nom en majuscules (réponse du serveur)');
    expect(cl.chercher('NOUVEAU-FICTIF').single['lgCLIENTID'], 'CL-CREE-1', reason: 'trouvé par la recherche du poste');
    expect(cl.clientDeVente['V-1'], 'CL-CREE-1');
    await validerEncaissementEspeces(t, app);
    await app.attendre(t, const Duration(seconds: 2));
    expect(cl.clotures.single['clientId'], 'CL-CREE-1');
    expect(cl.creations, hasLength(1), reason: 'bilan : un seul client créé');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('client choisi puis RETIRÉ (croix rouge, second appui) : vente terminée sans client', (t) async {
    final (app, cl) = await _vente(t);
    await _choisir(t, app, 'YAO', 'CL-FICT-3');
    expect(_nom, findsOneWidget);
    await t.tap(_croix);
    await t.pump();
    expect(find.byKey(const ValueKey('client-vente-confirmer')), findsOneWidget, reason: 'croix rouge, aucune fenêtre');
    expect(find.byType(AlertDialog), findsNothing);
    expect(cl.rattachements, hasLength(1), reason: 'rien envoyé au 1er appui');
    await t.tap(_croix);
    await app.attendre(t, const Duration(seconds: 1));
    expect(cl.rattachements.last, (venteId: 'V-1', clientId: null));
    expect(_nom, findsNothing);
    expect(cl.clientDeVente.containsKey('V-1'), isFalse);
    await validerEncaissementEspeces(t, app);
    await app.attendre(t, const Duration(seconds: 2));
    expect(cl.clotures.single['clientId'], isNull);
    expect(cl.clientDeVente.containsKey('V-1'), isFalse, reason: 'vente terminée sans client');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('client choisi puis CHANGÉ pour un autre : seul le second reste', (t) async {
    final (app, cl) = await _vente(t);
    await _choisir(t, app, 'KOFFI', 'CL-FICT-1');
    await _choisir(t, app, 'KOFFI-TEST B', 'CL-FICT-2');
    expect(_nomAffiche(t), 'KOFFI-TEST BINTOU');
    expect(cl.clientDeVente['V-1'], 'CL-FICT-2');
    await validerEncaissementEspeces(t, app);
    await app.attendre(t, const Duration(seconds: 2));
    expect(cl.clotures.single['clientId'], 'CL-FICT-2');
    expect(cl.clientDeVente['V-1'], 'CL-FICT-2');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('vente SANS client : aucune route client, clôture comme avant (clientId null) ; bilan identique', (t) async {
    final (app, cl) = await _vente(t);
    final avant = app.serveur.recues.length;
    await validerEncaissementEspeces(t, app);
    await app.attendre(t, const Duration(seconds: 2));
    final routes = [for (final r in app.serveur.recues.skip(avant)) '${r.methode} ${r.chemin.split('/api/v1').last}'];
    expect(routes.where((r) => r.contains('/client')), isEmpty, reason: '$routes');
    expect(cl.rattachements, isEmpty);
    expect(cl.recherches, isEmpty);
    final sans = cl.clotures.single;
    expect(sans['clientId'], isNull);
    // Deuxième vente, avec un client : clôture IDENTIQUE hormis clientId / venteId / référence (stock, caisse, tiers payant).
    expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
    await app.attendre(t, const Duration(seconds: 2));
    await _choisir(t, app, 'KOFFI', 'CL-FICT-1');
    await validerEncaissementEspeces(t, app);
    await app.attendre(t, const Duration(seconds: 2));
    final avec = cl.clotures.last;
    Map<String, dynamic> sansIdentite(Map<String, dynamic> m) => {...m}
      ..remove('clientId')
      ..remove('venteId')
      ..remove('data');
    expect(sansIdentite(avec), sansIdentite(sans), reason: 'mêmes montants, mêmes règlements, partTP 0');
    for (final c in [sans, avec]) {
      expect(c['partTP'], 0);
      expect(c['typeVenteId'], '1');
      expect(c.containsKey('tierspayants'), isFalse, reason: 'aucune ligne de tiers payant');
    }
    expect(cl.creations, isEmpty);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('vente DÉJÀ TERMINÉE : rattachement refusé, message du serveur, nom jamais affiché', (t) async {
    final (app, cl) = await _vente(t);
    app.serveur.statutVentes['V-1'] = 'is_Closed'; // terminée ailleurs (poste)
    await _choisir(t, app, 'KOFFI', 'CL-FICT-1');
    expect(_erreur, findsOneWidget);
    expect(find.textContaining('est déjà terminée'), findsOneWidget, reason: 'msg du serveur tel quel');
    await app.retour(t);
    expect(_nom, findsNothing, reason: 'état précédent gardé (aucun client)');
    expect(cl.clientDeVente, isEmpty);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('espèces puis mobile money (WAVE) : le client choisi n\'est jamais remplacé à l\'encaissement', (t) async {
    final (app, cl) = await _vente(t);
    await _choisir(t, app, 'KOFFI', 'CL-FICT-1');
    await validerEncaissementEspeces(t, app);
    await app.attendre(t, const Duration(seconds: 2));
    expect(cl.clientDeVente['V-1'], 'CL-FICT-1');
    // Deuxième vente, payée en WAVE.
    expect(await ajouterAuPanier(t, app, nomCourt(4)), isTrue);
    await app.attendre(t, const Duration(seconds: 2));
    await _choisir(t, app, 'YAO', 'CL-FICT-3');
    await t.tap(find.byKey(const ValueKey('vente-encaisser')));
    expect(await app.attendreQue(t, find.text('WAVE')), isTrue);
    await t.tap(find.text('WAVE'));
    await app.attendre(t, const Duration(milliseconds: 500));
    await t.tap(find.byKey(const ValueKey('encaissement-imprimer')));
    await t.pump();
    final valider = find.byKey(const ValueKey('encaissement-valider'));
    await t.ensureVisible(valider);
    await t.tap(valider);
    await app.attendre(t, const Duration(seconds: 2));
    expect(cl.clotures, hasLength(2));
    expect(cl.clotures.last['typeRegleId'], '10');
    expect(cl.clotures.last['clientId'], 'CL-FICT-3');
    expect(cl.clientDeVente, {'V-1': 'CL-FICT-1', 'V-2': 'CL-FICT-3'});
    expect(cl.rattachements.map((r) => r.clientId), ['CL-FICT-1', 'CL-FICT-3'], reason: 'jamais « especes » ni « wave »');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('reprise d\'une vente en attente : le client déjà rattaché est affiché (lu avec la vente)', (t) async {
    final (app, cl) = await _vente(t);
    await _choisir(t, app, 'KOFFI', 'CL-FICT-1');
    await app.retour(t);
    await t.tap(find.text('Quitter'));
    await app.attendre(t);
    expect(find.byType(AccueilScreen), findsOneWidget);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    expect(await app.attendreQue(t, find.text('REPRENDRE')), isTrue);
    await t.tap(find.text('REPRENDRE'));
    expect(await app.attendreQue(t, _nom), isTrue, reason: 'client relu avec la vente (GET ventestats/{id})');
    expect(_nomAffiche(t), 'KOFFI-TEST AMANI');
    expect(cl.rattachements, hasLength(1), reason: 'reprise : lecture seule');
    await validerEncaissementEspeces(t, app);
    await app.attendre(t, const Duration(seconds: 2));
    expect(cl.clotures.single['clientId'], 'CL-FICT-1');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('403 interdit au rattachement : msg affiché, PAS de déconnexion, vente intacte', (t) async {
    final (app, cl) = await _vente(t);
    cl.forcerRattachement = (_) => ClientsVenteFictifs.interdit403;
    await _choisir(t, app, 'KOFFI', 'CL-FICT-1');
    expect(find.textContaining('pas le droit d\'associer un client'), findsOneWidget);
    expect(find.byType(ConnexionScreen), findsNothing);
    await app.retour(t);
    expect(_nom, findsNothing);
    expect(find.byKey(const ValueKey('vente-encaisser')), findsOneWidget, reason: 'vente toujours ouverte');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('409 sessionChangee au rattachement : retour à l\'accueil, message du serveur', (t) async {
    final (app, cl) = await _vente(t);
    cl.forcerRattachement = (_) => ClientsVenteFictifs.sessionChangee409;
    await _choisir(t, app, 'KOFFI', 'CL-FICT-1');
    await app.attendre(t);
    expect(find.byKey(const Key('session_changee')), findsOneWidget);
    expect(find.byType(AccueilScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('client-vente-page')), findsNothing);
    expect(cl.clientDeVente, isEmpty);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('tablette : zone Client dans le panier, parcours identique', (t) async {
    final (app, cl) = await _vente(t, taille: TailleEcran.tablette);
    await _choisir(t, app, '0700', 'CL-FICT-1');
    expect(cl.recherches.last, '0700', reason: 'numéro de 4 chiffres');
    expect(_nomAffiche(t), 'KOFFI-TEST AMANI');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
