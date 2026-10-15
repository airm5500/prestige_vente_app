// Écrans principaux contrôlés par les tests d'ergonomie (test/ergonomie_test.dart, test/ergonomie_taille_ecran_test.dart) :
// comment les ouvrir dans l'application entière (faux serveur Prestige en mémoire) et le champ à garder visible au-dessus
// du clavier.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/reserve/reserve_api.dart';
import 'package:prestige_vente_app/reserve/reserve_traitement_screen.dart';
import 'package:prestige_vente_app/serveur/client_contexte.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/rh/photo_controle_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'app_e2e.dart';
import 'ergonomie.dart';

/// Caméra frontale simulée (aperçu coloré, photo fictive).
class _Camera implements CameraControle {
  @override
  Future<SessionCamera> ouvrir() async => _Session();
}

class _Session implements SessionCamera {
  @override
  Widget apercu() => Container(color: Colors.blueGrey);
  @override
  Future<Uint8List> capturer() async => Uint8List.fromList(List.filled(64, 7));
  @override
  Future<void> fermer() async {}
}

NavigatorState get _nav => HorsLigne.navigatorKey.currentState!;

Future<void> _pousser(WidgetTester t, AppE2E app, Widget ecran) async {
  _nav.push(MaterialPageRoute(builder: (_) => ecran));
  await app.attendre(t);
}

/// Écrans principaux (accueil A / B / C, recherche, fiche produit, vente, analyses, ordonnances, fiche client, réserve,
/// pointage, réglages).
final ecransErgonomie = <EcranControle>[
  EcranControle('connexion', 'Connexion', avantConnexion: true, champ: () => find.byKey(const Key('connexion_mdp'))),
  const EcranControle('accueil_A', 'Accueil (A tableau de bord)', presentation: ListPresentation.dashboard, charte: true),
  const EcranControle('accueil_B', 'Accueil (B liste compacte)', presentation: ListPresentation.compact, charte: true),
  const EcranControle('accueil_C', 'Accueil (C guidé)', presentation: ListPresentation.guided, charte: true),
  EcranControle('recherche_globale', 'Recherche (menus et produits)', ouvrir: (t, app) async {
    await app.defilerJusqua(t, find.text('Rechercher un menu ou un produit'));
    await t.tap(find.text('Rechercher un menu ou un produit'));
    await app.attendre(t);
  }),
  EcranControle('fiche_produit', 'Fiche produit',
      ouvrir: (t, app) => _pousser(t, app, FicheProduitScreen(produit: ProductSearchResult.fromJson(DonneesFictives.produitRecherche())))),
  EcranControle('vente', 'Vente (pré-vente)',
      ouvrir: (t, app) => app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente'), champ: () => find.byKey(const ValueKey('vente-recherche'))),
  EcranControle('recherche_article', 'Recherche article', ouvrir: (t, app) => app.ouvrirMenu(t, ListPresentation.dashboard, 'search')),
  EcranControle('analyse_article', 'Analyse article', ouvrir: (t, app) => app.ouvrirMenu(t, ListPresentation.dashboard, 'analyse_article')),
  EcranControle('posos', 'Analyse posologie', ouvrir: (t, app) => app.ouvrirMenu(t, ListPresentation.dashboard, 'posos')),
  EcranControle('ordonnances_clients', 'Ordonnances des clients',
      ouvrir: (t, app) => app.ouvrirMenu(t, ListPresentation.dashboard, 'ordonnances_clients')),
  EcranControle('fiche_client', 'Fiche client (dossier, mesures)',
      ouvrir: (t, app) async {
        await app.ouvrirMenu(t, ListPresentation.dashboard, 'ordonnances_clients');
        await t.enterText(find.byKey(const ValueKey('fiche-recherche')), 'DEMO');
        expect(await app.attendreQue(t, find.byKey(const ValueKey('fiche-client-C1'))), isTrue);
        await t.tap(find.byKey(const ValueKey('fiche-client-C1')));
        await app.attendre(t);
      },
      avantSaisie: (t, app) async {
        await app.defilerJusqua(t, find.byKey(const ValueKey('fiche-ajouter-mesure')), zone: find.byType(Scrollable).last);
        await t.tap(find.byKey(const ValueKey('fiche-ajouter-mesure')));
        await app.attendre(t);
      },
      champ: () => find.byKey(const ValueKey('fiche-valeur'))),
  EcranControle('reserve', 'Réserve', ouvrir: (t, app) => app.ouvrirMenu(t, ListPresentation.dashboard, 'reserve')),
  // 4.1.2 : onglet « Automatique » de la Réserve (onglet « Manuel » ouvert par défaut : écran « reserve »).
  EcranControle('reserve_automatique', 'Réserve : onglet Automatique', ouvrir: (t, app) async {
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'reserve');
    await t.tap(find.byKey(const ValueKey('reserve-onglet-auto')));
    await app.attendre(t);
  }),
  // 4.1.2 : fenêtres de la nouvelle interface à la charte (plus de lavande Material) : déconnexion, code administrateur.
  EcranControle('deconnexion', 'Fenêtre « Se déconnecter ? »', charte: true, ouvrir: (t, app) async {
    await t.tap(find.byKey(const Key('accueil_deconnexion')));
    await app.attendre(t, const Duration(seconds: 1));
  }),
  EcranControle('code_administrateur', 'Fenêtre « Accès sécurisé » (code administrateur)',
      charte: true, ouvrir: (t, app) => app.ouvrirMenu(t, ListPresentation.dashboard, 'ajustement'), champ: () => find.byKey(const Key('pin_admin_saisie'))),
  EcranControle('reserve_quantites', 'Réserve : traitement et quantités',
      ouvrir: (t, app) => _pousser(t, app, ReserveTraitementScreen(suggestionId: 'S1', api: ReserveApi(clientPrestige(_nav.context)))),
      avantSaisie: (t, app) async {
        await t.tap(find.byKey(const ValueKey('reserve-qte-1')));
        await app.attendre(t);
      },
      champ: () => find.byKey(const ValueKey('reserve-quantite'))),
  EcranControle('pointage', 'Pointage présence', ouvrir: (t, app) => app.ouvrirMenu(t, ListPresentation.dashboard, 'pointage_rh')),
  EcranControle('photo_pointage', 'Photo de contrôle du pointage', ouvrir: (t, app) async {
    final photo = PhotoControle(
      camera: _Camera(),
      registre: RegistrePhotosPointage(stockage: StockagePhotosMemoire(), journal: () => JournalTerminal(), retentionJours: () async => 30),
      reglages: () async => const ReglagesPointageTerminal(),
      compresser: (b) async => b,
      delaiApercu: const Duration(minutes: 5), // compte à rebours affiché pendant les contrôles
    );
    PhotoControleScreen.ouvrir(_nav.context, photo, 'Awa Test');
    await app.attendre(t);
  }),
  EcranControle('photos_pointage', 'Photos de pointage (liste)', ouvrir: (t, app) async {
    final registre = RegistrePhotosPointage(stockage: StockagePhotosMemoire(), journal: () => JournalTerminal(), retentionJours: () async => 30);
    await registre.ajouter(
        id: 'p1', employeId: 'E1', employeNom: 'TEST Awa', lu: DateTime.now(), sens: 'Entrée', moyen: 'Scan du badge', resultat: const PhotoAbsente(MotifSansPhoto.cameraAbsente));
    await _pousser(t, app, PhotosPointageScreen(registre: registre, retentionJours: 30));
  }),
  EcranControle('reglages', 'Réglages', charte: true, ouvrir: (t, app) async {
    await t.tap(find.text('Réglages'));
    await app.attendre(t);
  }),
];
