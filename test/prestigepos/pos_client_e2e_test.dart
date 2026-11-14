// PrestigePOS 1.11.0 — e2e, application ENTIÈRE (PrestigePosApp, faux serveur Prestige en mémoire, données FICTIVES) :
// client facultatif de la vente comptant de la BORNE (décision du pharmacien du 14/11/2026) :
//  - client trouvé (≥ 3 caractères), choisi : la liste et le texte disparaissent ; « Payer en caisse » → prévente
//    créée, client rattaché (POST vente/update/client) AVANT de la terminer ; ticket « Votre nom est associé » ;
//  - nouveau client (nom, prénom, téléphone) → créé (type 6) puis rattaché à la prévente ;
//  - croix rouge puis second appui : nom retiré, prévente sans client ;
//  - sans client : mêmes requêtes qu'en 1.10.1 (aucune route client) ;
//  - rattachement refusé (403) : prévente valable, ticket « Nom non associé : msg » ; pas de déconnexion ;
//  - CONFIDENTIALITÉ : après « TERMINÉ », après l'abandon (inactivité) et serveur perdu : client suivant sans nom,
//    sans résultat, sans texte du précédent ; le nom n'est jamais affiché sur l'écran du ticket ;
//  - hors ligne : aucune zone Client.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prestige_vente_app/horsligne/horsligne.dart';

import '../outils/clients_vente_fictifs.dart';
import 'outils/pos_e2e.dart';
import 'pos_e2e_test.dart' show attendreBorne, tablettePortrait;

final _ouvrir = find.byKey(const ValueKey('borne-client-ouvrir'));
final _nom = find.byKey(const ValueKey('borne-client-nom'));
Finder _resultat(String id) => find.byKey(ValueKey('borne-client-resultat-$id'));

Future<(PosE2E, ClientsVenteFictifs)> _panier(WidgetTester t, {Size taille = const Size(1200, 1920), double densite = 1.5}) async {
  t.view.physicalSize = taille;
  t.view.devicePixelRatio = densite;
  addTearDown(t.view.reset);
  final app = PosE2E();
  final cl = ClientsVenteFictifs(app.serveur);
  await app.preparer(configure: true);
  await app.lancer(t);
  await attendreBorne(t, app);
  await _ajouter(t, app);
  return (app, cl);
}

Future<void> _ajouter(WidgetTester t, PosE2E app) async {
  await app.chercher(t, 'doli');
  await app.toucher(t, 'borne-ajouter-F1');
  await app.attendre(t, const Duration(milliseconds: 2600));
  if (find.byKey(const ValueKey('borne-voir-panier')).evaluate().isNotEmpty) {
    await app.toucher(t, 'borne-voir-panier');
  } else {
    await app.toucher(t, 'borne-panier-lateral-payer');
  }
  expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-payer'))), isTrue);
}

Future<void> _choisir(WidgetTester t, PosE2E app, String texte, String id) async {
  await app.toucher(t, 'borne-client-ouvrir');
  await app.saisir(t, 'borne-client-recherche', texte);
  expect(await app.attendreQue(t, _resultat(id)), isTrue, reason: 'résultat $id');
  await t.ensureVisible(_resultat(id));
  await t.tap(_resultat(id));
  await app.attendre(t, const Duration(milliseconds: 600));
}

Future<void> _payer(WidgetTester t, PosE2E app) async {
  await app.toucher(t, 'borne-payer');
  expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-numero'))), isTrue, reason: 'écran du ticket');
}

/// Aucune trace d'un client précédent à l'écran.
void _rienDuClient(WidgetTester t, List<String> textes) {
  for (final x in textes) {
    expect(find.textContaining(x), findsNothing, reason: 'visible : « $x »');
  }
  expect(_nom, findsNothing);
  expect(find.byKey(const ValueKey('borne-client-page')), findsNothing);
}

void main() {
  testWidgets('client trouvé → liste effacée au choix → payer : rattaché à la prévente, ticket « associé » sans le nom', (t) async {
    final (app, cl) = await _panier(t);
    expect(_ouvrir, findsOneWidget, reason: 'zone Client dans le panier, en ligne');
    await _choisir(t, app, 'KOFFI', 'CL-FICT-1');
    expect(find.byKey(const ValueKey('borne-client-page')), findsNothing, reason: 'retour au panier');
    expect(t.widget<Text>(_nom).data, 'KOFFI-TEST AMANI');
    expect(cl.rattachements, isEmpty, reason: 'la prévente n\'existe pas encore');
    await _payer(t, app);
    expect(cl.rattachements, [(venteId: 'V-1', clientId: 'CL-FICT-1')]);
    expect(cl.clientDeVente['V-1'], 'CL-FICT-1');
    final ordre = [for (final r in app.serveur.recues) r.chemin.replaceFirst(RegExp(r'^.*/api/v1'), '')];
    expect(ordre.indexOf('/vente/update/client'), lessThan(ordre.indexWhere((c) => c.startsWith('/vente/terminerprevente'))),
        reason: 'rattaché avant de terminer la prévente');
    expect(find.byKey(const ValueKey('borne-client-associe')), findsOneWidget);
    expect(find.textContaining('KOFFI-TEST'), findsNothing, reason: 'jamais le nom sur l\'écran du ticket');
    await app.toucher(t, 'borne-termine');
    // Client suivant : rien du précédent.
    await _ajouter(t, app);
    _rienDuClient(t, ['KOFFI', 'AMANI', '0700000001']);
    expect(_ouvrir, findsOneWidget);
    await app.toucher(t, 'borne-client-ouvrir');
    expect(t.widget<TextField>(find.byKey(const ValueKey('borne-client-recherche'))).controller!.text, isEmpty);
    expect(_resultat('CL-FICT-1'), findsNothing, reason: 'aucun résultat du client précédent');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('nouveau client : créé (type 6), rattaché à la prévente ; un seul client créé', (t) async {
    final (app, cl) = await _panier(t);
    await app.toucher(t, 'borne-client-ouvrir');
    await app.toucher(t, 'borne-client-nouveau');
    await app.saisir(t, 'borne-client-nom-saisi', 'Nouveau-Fictif');
    await app.saisir(t, 'borne-client-prenom-saisi', 'Essai');
    await app.saisir(t, 'borne-client-telephone-saisi', '0700009999');
    final tel = t.widget<TextField>(find.byKey(const ValueKey('borne-client-telephone-saisi')));
    expect(tel.keyboardType, TextInputType.phone, reason: 'clavier téléphone');
    expect(t.widget<TextField>(find.byKey(const ValueKey('borne-client-nom-saisi'))).keyboardType, TextInputType.name);
    await app.toucher(t, 'borne-client-creer');
    expect(cl.creations.single, {'strFIRSTNAME': 'Nouveau-Fictif', 'strLASTNAME': 'Essai', 'strADRESSE': '0700009999', 'lgTYPECLIENTID': '6'});
    expect(t.widget<Text>(_nom).data, 'NOUVEAU-FICTIF ESSAI');
    await _payer(t, app);
    expect(cl.clientDeVente['V-1'], 'CL-CREE-1');
    expect(cl.creations, hasLength(1));
    await app.fermer(t);
  });

  testWidgets('croix rouge puis second appui : nom retiré, prévente sans client', (t) async {
    final (app, cl) = await _panier(t);
    await _choisir(t, app, 'YAO', 'CL-FICT-3');
    await app.toucher(t, 'borne-client-retirer');
    expect(find.byKey(const ValueKey('borne-client-confirmer')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await app.toucher(t, 'borne-client-retirer');
    expect(_nom, findsNothing);
    await _payer(t, app);
    expect(cl.rattachements, isEmpty);
    expect(cl.clientDeVente, isEmpty);
    expect(find.byKey(const ValueKey('borne-client-associe')), findsNothing);
    await app.fermer(t);
  });

  testWidgets('sans client : aucune route client (comme 1.10.1)', (t) async {
    final (app, cl) = await _panier(t);
    await _payer(t, app);
    final routes = [for (final r in app.serveur.recues) r.chemin];
    expect(routes.where((c) => c.contains('/client')), isEmpty, reason: '$routes');
    expect(cl.rattachements, isEmpty);
    await app.fermer(t);
  });

  testWidgets('rattachement refusé (403) : prévente valable, « Nom non associé : msg », pas de déconnexion', (t) async {
    final (app, cl) = await _panier(t);
    cl.forcerRattachement = (_) => ClientsVenteFictifs.interdit403;
    await _choisir(t, app, 'KOFFI', 'CL-FICT-1');
    await _payer(t, app);
    expect(find.byKey(const ValueKey('borne-client-refus')), findsOneWidget);
    expect(find.textContaining('pas le droit d\'associer'), findsOneWidget);
    expect(app.serveur.statutVentes['V-1'], 'is_Process', reason: 'prévente terminée quand même');
    expect(app.serveur.connexions, 1);
    await app.fermer(t);
  });

  testWidgets('abandon (inactivité) : retour à l\'accueil, client et résultats effacés', (t) async {
    final (app, _) = await _panier(t);
    await app.toucher(t, 'borne-client-ouvrir');
    await app.saisir(t, 'borne-client-recherche', 'KOFFI');
    expect(await app.attendreQue(t, _resultat('CL-FICT-1')), isTrue);
    // Le client part sans rien toucher : avertissement puis accueil.
    await app.attendre(t, const Duration(seconds: 200));
    expect(find.byKey(const ValueKey('borne-client-page')), findsNothing);
    _rienDuClient(t, ['KOFFI', 'AMANI', 'BINTOU']);
    await _ajouter(t, app);
    _rienDuClient(t, ['KOFFI', 'AMANI', 'BINTOU']);
    await app.toucher(t, 'borne-client-ouvrir');
    expect(_resultat('CL-FICT-1'), findsNothing);
    await app.fermer(t);
  });

  testWidgets('client choisi puis serveur perdu : borne indisponible, tout est effacé ; au retour, rien du client', (t) async {
    final (app, _) = await _panier(t);
    await _choisir(t, app, 'KOFFI', 'CL-FICT-1');
    HorsLigne.instance.monitor.goOffline(); // serveur perdu (surveillance du serveur)
    expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-indisponible'))), isTrue);
    _rienDuClient(t, ['KOFFI', 'AMANI']);
    HorsLigne.instance.monitor.goOnline();
    expect(await app.attendreQue(t, find.byKey(const ValueKey('borne-recherche')), max: const Duration(seconds: 30)), isTrue);
    await _ajouter(t, app);
    _rienDuClient(t, ['KOFFI', 'AMANI']);
    await app.fermer(t);
  });

  testWidgets('Sunmi V2s : même parcours', (t) async {
    final (app, cl) = await _panier(t, taille: const Size(720, 1440), densite: 2.0);
    await _choisir(t, app, '0500', 'CL-FICT-2');
    expect(cl.recherches.last, '0500');
    await _payer(t, app);
    expect(cl.clientDeVente['V-1'], 'CL-FICT-2');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('tablette portrait : la recherche sous 3 caractères n\'envoie rien', (t) async {
    tablettePortrait(t);
    final (app, cl) = await _panier(t);
    await app.toucher(t, 'borne-client-ouvrir');
    await app.saisir(t, 'borne-client-recherche', 'KO');
    await app.attendre(t, const Duration(seconds: 1));
    expect(cl.recherches, isEmpty);
    expect(find.byKey(const ValueKey('borne-client-aide')), findsOneWidget);
    await app.saisir(t, 'borne-client-recherche', '070');
    await app.attendre(t, const Duration(seconds: 1));
    expect(cl.recherches, isEmpty);
    await app.fermer(t);
  });
}
