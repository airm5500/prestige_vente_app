// Ergonomie et cohérence d'affichage des écrans principaux (application entière, faux serveur Prestige en mémoire).
//
// Pour chaque écran × taille (Sunmi 720×1440 densité 2, Sunmi 1080×1920 densité 2,625, téléphone 360×640 dp,
// tablette 1920×1200 densité 1,5) × échelle de texte (1,0 et 1,3) :
//   - aucun débordement ni exception de rendu ;
//   - cibles tactiles ≥ 48 dp (androidTapTargetGuideline) ;
//   - contraste des textes (textContrastGuideline) ;
//   - en-têtes / barres aux couleurs de la charte (pas de lavande Material par défaut) ;
//   - écrans de saisie (connexion, vente, quantités réserve, mesures fiche client) : champ visible au-dessus du
//     clavier (viewInsets simulés).
// Pas de captures de référence (goldens) : uniquement des règles mesurables.
// Anomalies connues : sautées UNIQUEMENT sur la configuration touchée, avec leur identifiant (test/README.md).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/reserve/reserve_api.dart';
import 'package:prestige_vente_app/reserve/reserve_traitement_screen.dart';
import 'package:prestige_vente_app/serveur/client_contexte.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/rh/photo_controle_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';
import 'outils/ergonomie.dart';

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

final _ecrans = <EcranControle>[
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

void main() {
  for (final taille in TailleEcran.toutes) {
    for (final echelle in const [1.0, 1.3]) {
      group('$taille, texte ×$echelle', () {
        for (final e in _ecrans) {
          final controles = [for (final c in Controle.values) if (c != Controle.clavier || e.champ != null) c];
          final sautes = <Controle, String>{};
          for (final c in controles) {
            final a = anomalieConnue(e.id, c, taille, echelle);
            if (a != null) sautes[c] = a;
          }
          // Anomalie connue : contrôle sauté sur cette configuration seulement, avec son identifiant.
          sautes.forEach((c, a) => testWidgets('${e.nom} — ${c.libelle} — sauté : $a', skip: true, (t) async {}));
          testWidgets(e.nom, (t) async {
            taille.appliquer(t);
            t.platformDispatcher.textScaleFactorTestValue = echelle;
            addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
            final app = AppE2E()..serveur.activerModules();
            await app.preparer(prefs: {'hiddenMenuIds': <String>[], if (e.presentation != null) 'presentation_listes_v1': e.presentation!.name});
            await app.lancer(t);
            if (e.avantConnexion) {
              expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
            } else {
              expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
              await app.attendre(t);
              await e.ouvrir?.call(t, app);
            }
            await verifierEcran(t, app, e, sautes: sautes.keys.toSet());
            await app.fermer(t);
          });
        }
      });
    }
  }
}
