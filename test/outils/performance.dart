// Outils des tests de PERFORMANCE (test/performance/) et des tests RÉSEAU (test/reseau/) de Prestige Mobile.
// Même principe et même format de mesure que Prestige Inventaire (homogénéité des rapports de livraison).
//
// Principe : chaque mesure est comparée à un SEUIL écrit ici (table [Seuils]) ; au-delà, le test échoue (en
// local comme sur la CI). Chaque mesure est aussi imprimée sur une ligne « PRESTIGE_MESURE {json} », que
// tool/rapport_tests.dart relève dans la sortie JSON de `flutter test` (format `--machine`) pour l'écrire
// dans le rapport de tests de livraison (résumé du job GitHub + artefact `rapport-tests`).
//
// Temps des images : les tests de widgets tournent en temps SIMULÉ, mais le travail de chaque image
// (construction, mise en page, peinture) est réellement exécuté par le processeur : on chronomètre donc chaque
// `tester.pump()` avec une horloge réelle (Stopwatch), image par image ([ChronoImages]). Mode test (JIT,
// assertions actives) : plus lent qu'une version « release » sur le terminal. Les seuils sont des seuils de
// NON-RÉGRESSION en mode test sur la CI Linux, pas des temps d'appareil.
//
// Les tests de la CI tournent EN PARALLÈLE (un fichier par cœur) : les temps sont donc mesurés plusieurs fois
// et c'est le MEILLEUR passage qui est comparé au seuil ([meilleurDe]) quand la mesure peut être répétée, pour
// qu'un pic de charge passager de la machine ne fasse pas échouer la livraison (voir test/README.md).
import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'serveur_json_local.dart';

/// Seuils de performance et de nombre de requêtes. Temps : calibrés sur la CI GitHub (ubuntu-latest,
/// 4 cœurs, suite complète en parallèle) avec une marge d'environ ×3 sur le temps le plus lent mesuré.
/// Requêtes : plafond = nombre voulu par le fonctionnement, SANS marge. Valeurs mesurées : test/README.md
/// (« Seuils de performance »). Un seuil ne se relève qu'avec une justification écrite dans le README.
class Seuils {
  Seuils._();

  // --- Démarrage ---
  /// Lancement de l'application entière (MyApp, licence lue sur le faux serveur) jusqu'à l'écran de
  /// connexion affiché, à froid (première construction de tous les widgets du fichier).
  static const demarrageMs = 6000;

  /// Requêtes avant la connexion : la licence (GET /licence/find) seulement.
  static const demarrageRequetes = 1;

  /// Connexion → accueil affiché (A, B ou C), temps réel du test (images rendues comprises).
  static const accueilMs = 3500;

  /// Pire image de l'accueil après son ouverture (défilement de la page des menus).
  static const imageAccueilMs = 250;

  // --- Longues listes : temps d'UNE image (ms, mode test) ---
  /// PIRE image pendant le défilement d'une longue liste (deuxième passage : code déjà compilé).
  static const imageDefilementMs = 150;

  /// 90 % des images de défilement en dessous.
  static const imageCouranteMs = 80;

  /// Pire image au premier passage (à froid) ou à l'ouverture d'un écran.
  static const imageFroideMs = 500;

  /// Ouverture d'un écran sur une longue liste (lecture du faux serveur, première image), à froid.
  static const ouvertureListeMs = 3000;

  // --- Vente ---
  /// Ajout d'UNE ligne au panier (frappe du code, recherche, quantité, ajout, net), temps réel, en moyenne
  /// sur 50 lignes.
  static const ajoutLigneMs = 600;

  /// Pire image pendant l'ajout des 50 lignes (le panier s'allonge : aucune image ne doit s'envoler).
  static const imageVenteMs = 900;

  // --- Traitement local ---
  /// Classement par début de code (4.0.3 F3) de 5 000 produits, 20 saisies différentes.
  static const classement5000Ms = 400;

  /// Génération de 100 tickets de vente (lignes envoyées à l'imprimante Sunmi simulée).
  static const tickets100Ms = 2500;

  /// Génération de 100 tickets de la borne (lignes calculées, 58 et 80 mm).
  static const ticketsBorne100Ms = 100;

  // --- Empreintes partagées (4.4.0, demande 43) ---
  /// Première synchronisation d'un terminal : 50 employés × 3 gabarits (fictifs, 480 octets) reçus, appliqués et
  /// écrits dans le coffre (serveur simulé en mémoire : temps de l'application seulement).
  static const synchroEmpreintes50Ms = 500;

  /// Synchronisation suivante sans changement (incrémentale).
  static const synchroEmpreintesVideMs = 100;

  /// Préparation de l'identification 1:N (150 modèles des 50 employés actifs) avant l'appel au lecteur.
  static const identification150Ms = 100;
}

/// Mesure enregistrée (pour le rapport) et comparée à son seuil.
void mesurer(String nom, num valeur, {required num seuil, required String unite, String? detail}) {
  // ignore: avoid_print
  print('PRESTIGE_MESURE ${json.encode({
        'nom': nom,
        'valeur': valeur is double ? double.parse(valeur.toStringAsFixed(1)) : valeur,
        'seuil': seuil,
        'unite': unite,
        if (detail != null) 'detail': detail,
      })}');
  expect(valeur, lessThanOrEqualTo(seuil), reason: '$nom : $valeur $unite > seuil $seuil $unite${detail == null ? '' : ' ($detail)'}');
}

/// Exécute [n] fois [mesure] (temps en ms) et renvoie le meilleur passage (moins sensible à la charge de la
/// machine partagée par les tests parallèles).
Future<double> meilleurDe(int n, Future<double> Function() mesure) async {
  var best = double.infinity;
  for (var i = 0; i < n; i++) {
    final v = await mesure();
    if (v < best) best = v;
  }
  return best;
}

/// Chronomètre chaque image (chaque `pump`) en temps réel.
class ChronoImages {
  final List<double> ms = [];

  Future<void> pump(WidgetTester tester, [Duration? duree]) async {
    final sw = Stopwatch()..start();
    await tester.pump(duree);
    ms.add(sw.elapsedMicroseconds / 1000);
  }

  int get nombre => ms.length;
  double get max => ms.isEmpty ? 0 : ms.reduce((a, b) => a > b ? a : b);
  double get moyenne => ms.isEmpty ? 0 : ms.reduce((a, b) => a + b) / ms.length;

  /// 90e centile.
  double get p90 {
    if (ms.isEmpty) return 0;
    final t = [...ms]..sort();
    return t[((t.length - 1) * 0.9).round()];
  }

  String get resume => '${ms.length} images, moyenne ${moyenne.toStringAsFixed(1)} ms, p90 ${p90.toStringAsFixed(1)} ms, max ${max.toStringAsFixed(1)} ms';
}

int _images = 0;
bool _compteurBranche = false;

/// Nombre d'images rendues depuis le début du fichier de tests (compteur branché au premier appel).
int imagesRendues() {
  if (!_compteurBranche) {
    SchedulerBinding.instance.addPersistentFrameCallback((_) => _images++);
    _compteurBranche = true;
  }
  return _images;
}

/// Plus grande zone défilante affichée (la liste principale de l'écran).
Finder plusGrandeListe(WidgetTester tester) {
  final tous = find.byType(Scrollable).hitTestable().evaluate().toList();
  tous.sort((a, b) => (b.size?.height ?? 0).compareTo(a.size?.height ?? 0));
  final cible = tous.first;
  return find.byElementPredicate((e) => identical(e, cible));
}

/// Fait défiler [scrollable] (un [Scrollable]) par pas de [pas] dp jusqu'en bas (ou [maxPas] pas), une image
/// chronométrée par pas. [apresPas] : appelé après chaque image (ex. temps simulé pour une page suivante).
/// Renvoie le nombre de pas effectués.
Future<int> defilerJusquEnBas(WidgetTester tester, Finder scrollable, ChronoImages chrono,
    {double pas = 120, int maxPas = 3000, Future<void> Function()? apresPas}) async {
  final etat = tester.state<ScrollableState>(scrollable);
  var n = 0;
  var immobile = 0;
  while (n < maxPas) {
    final avant = etat.position.pixels;
    etat.position.jumpTo((etat.position.pixels + pas).clamp(0, etat.position.maxScrollExtent));
    await chrono.pump(tester);
    n++;
    if (apresPas != null) await apresPas();
    // En bas et plus rien ne se charge (deux images sans mouvement possible).
    if (etat.position.pixels >= etat.position.maxScrollExtent && etat.position.pixels == avant) {
      if (++immobile >= 2) break;
    } else {
      immobile = 0;
    }
  }
  return n;
}

/// Remonte en haut de [scrollable] (une image).
Future<void> remonter(WidgetTester tester, Finder scrollable) async {
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
}

/// Requêtes reçues par [serveur] pendant [action].
Future<List<RequeteRecue>> compterRequetes(ServeurJsonLocal serveur, Future<void> Function() action) async {
  final avant = serveur.recues.length;
  await action();
  return serveur.recues.sublist(avant);
}

/// Détail des requêtes par route (« GET /vente/search ×1, POST /vente/add/vno ×1 ») pour le rapport.
String detailRequetes(List<RequeteRecue> rs) {
  final par = <String, int>{};
  for (final r in rs) {
    final c = r.chemin.replaceFirst(RegExp(r'^.*/api/v1'), '').replaceAll(RegExp(r'/V-\d+$'), '/{id}');
    final k = '${r.methode} $c';
    par[k] = (par[k] ?? 0) + 1;
  }
  return par.entries.map((e) => '${e.key} ×${e.value}').join(', ');
}
