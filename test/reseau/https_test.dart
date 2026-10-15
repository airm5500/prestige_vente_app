// RÉSEAU — HTTPS, CERTIFICAT REFUSÉ, application entière (complète test/https_integration_test.dart, qui
// vérifie les clients contre un VRAI serveur HTTPS local et un vrai certificat de test). Ici, le faux serveur
// en mémoire simule la poignée de main TLS refusée (HandshakeException « CERTIFICATE_VERIFY_FAILED », comme un
// certificat auto-signé ou expiré sur le téléphone) :
//  - au lancement : « Certificat du serveur refusé » (lancement_certificat), ni « serveur injoignable », ni
//    « aucune licence » ; certificat corrigé → Réessayer → écran de connexion ;
//  - en cours de session (certificat renouvelé mal installé) : la recherche de la vente et l'Analyse article
//    affichent le message du certificat, pas « injoignable » ; rien n'est créé sur le serveur ;
//  - application en http : un certificat refusé ne la concerne pas (aucun changement).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/serveur/adresse_serveur.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import '../outils/app_e2e.dart';
import '../outils/parcours_vente.dart';

const prefsHttps = <String, Object>{'local_ip': 'https://${FauxServeurPrestige.hoteMemoire}', 'port': '443'};

Finder texteCertificat() => find.textContaining(RegExp('certificat', caseSensitive: false));

void main() {
  testWidgets('lancement : certificat refusé → « Certificat du serveur refusé », jamais injoignable ni licence ; corrigé → connexion', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = AppE2E()..serveur.certificatRefuse = true;
    await app.preparer(prefs: prefsHttps);
    await app.lancer(t);
    expect(await app.attendreQue(t, find.byKey(const Key('lancement_certificat'))), isTrue);
    expect(find.text(ErreurTls.certificat.titre), findsOneWidget);
    expect(find.byKey(const Key('lancement_injoignable')), findsNothing);
    expect(find.byKey(const Key('lancement_licence')), findsNothing);
    expect(find.textContaining('Aucune licence'), findsNothing);
    expect(app.serveur.recues, isEmpty, reason: 'aucune requête n\'a atteint le serveur');
    expect(app.serveur.tentatives.every((u) => u.scheme == 'https' && u.port == 443), isTrue, reason: 'toujours en https');

    app.serveur.certificatRefuse = false;
    await t.tap(find.byKey(const Key('lancement_reessayer')));
    expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('en cours de session : certificat refusé → message du certificat (vente, Analyse article), rien de créé', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = AppE2E();
    CatalogueFictif(app.serveur, nombre: 10);
    await app.preparer(prefs: {...prefsVente, ...prefsHttps});
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    await app.attendre(t, const Duration(seconds: 3));
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');

    app.serveur.certificatRefuse = true;
    await t.enterText(champRechercheVente, nomCourt(2));
    await app.attendre(t, const Duration(seconds: 2));
    expect(texteCertificat(), findsWidgets, reason: 'motif exact : certificat refusé');
    expect(find.textContaining('injoignable'), findsNothing);
    expect(champQuantite, findsNothing);
    expect(app.serveur.ventes, isEmpty);
    await app.retour(t);

    await app.ouvrirMenu(t, ListPresentation.dashboard, 'analyse_article');
    app.serveur.certificatRefuse = false;
    await t.enterText(find.byType(TextField).first, nomCourt(2));
    await app.attendre(t, const Duration(seconds: 1));
    app.serveur.certificatRefuse = true;
    await t.tap(find.text('PRODUIT 0002 CPR B/20').hitTestable().first);
    await app.attendre(t, const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('analyse-detail-erreur')), findsOneWidget);
    expect(find.textContaining(ErreurTls.messageCertificat), findsWidgets);
    expect(t.takeException(), isNull);
    app.serveur.certificatRefuse = false;
    await app.fermer(t);
  });

  testWidgets('application en http : un certificat refusé ne change rien', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = AppE2E()..serveur.certificatRefuse = true;
    await app.preparer();
    await app.lancer(t);
    expect(await app.seConnecter(t), isTrue);
    expect(app.serveur.tentatives.every((u) => u.scheme == 'http'), isTrue);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
