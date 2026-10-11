// lib/ordonnances/o4/banc_o4.dart
// Étape O4 au banc d'essai : candidat « O3 + apprentissages » et mode « apprentissage simulé ».
//
// Mode normal : la correspondance O3 utilise les apprentissages RÉELS de l'appareil (lecture seule).
// Mode simulé (deux passages) : apprentissages vierges EN MÉMOIRE ; 1ᵉʳ passage : chaque ordonnance est lue, puis
// les « corrections du pharmacien » (= la vérité terrain) sont apprises comme à l'écran Ordonnance ; 2ᵉ passage :
// relecture et mesure. Rien n'est enregistré sur l'appareil ni envoyé au serveur (ni apprentissage, ni file de
// partage, ni compteur des produits validés). Le texte lu n'est gardé qu'en mémoire pendant la mesure.
//
// Attention à la lecture du résultat : le 2ᵉ passage relit LES MÊMES ordonnances ; il montre l'effet de
// l'apprentissage pour des ordonnances revues (même médecin, même écriture), pas une généralisation.
import 'dart:io';

import 'package:prestige_vente_app/ordonnances/banc_essai/normalisation_produit.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/pipeline_ordonnance.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/score_banc.dart';
import 'package:prestige_vente_app/ordonnances/o2/decoupage_ordonnance.dart';
import 'package:prestige_vente_app/ordonnances/o3/correspondance_o3.dart';
import 'package:prestige_vente_app/ordonnances/o3/similarite.dart';
import 'package:prestige_vente_app/ordonnances/o4/apprentissage_o4.dart';
import 'package:prestige_vente_app/ordonnances/o4/segment_medicament.dart';
import 'package:prestige_vente_app/services/ocr_service.dart';
import 'package:prestige_vente_app/services/prescription_matcher.dart';
import 'package:prestige_vente_app/services/prescription_parser.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';

/// Pipeline capable d'apprendre des corrections (banc d'essai simulé).
abstract class PipelineApprenant implements PipelineOrdonnance {
  /// Apprentissages vierges en mémoire (rien de réel n'est touché) jusqu'à [terminerSimulation].
  void commencerSimulation();
  void terminerSimulation();

  /// Corrections simulées du pharmacien (vérité terrain) sur la dernière lecture de [image] ; renvoie le nombre
  /// de lignes apprises.
  Future<int> apprendreDe(String image, VeriteOrdonnance verite);
}

/// Une ligne lue et le produit proposé (mémoire de la dernière analyse, pour l'apprentissage simulé).
class _LigneLue {
  final PrescriptionLine ligne;
  final String? propose;
  final bool cip;
  const _LigneLue(this.ligne, this.propose, this.cip);
}

class PipelineO3Appris implements PipelineApprenant {
  @override
  final String id;
  @override
  final String libelle;
  final LecteurTexte lecteur;
  final DecoupageLignes decoupage;
  final ProductPageSearch recherche;

  /// Correspondance O3 du catalogue (sans apprentissages : ils sont ajoutés ici).
  final Future<CorrespondanceO3> Function() correspondance;

  /// Apprentissages réels (mode normal).
  final Future<SourceApprentissages> Function() apprentissagesReels;

  /// Préparation d'image facultative (O2 image améliorée).
  final PreparationImage? preparation;

  PipelineO3Appris({
    this.id = 'o3_appris',
    this.libelle = 'O3 + apprentissages',
    LecteurTexte? lecteur,
    DecoupageLignes? decoupage,
    required this.recherche,
    required this.correspondance,
    Future<SourceApprentissages> Function()? apprentissagesReels,
    this.preparation,
  })  : lecteur = lecteur ?? OcrService.readImageFile,
        decoupage = decoupage ?? DecoupageOrdonnance.extraire,
        apprentissagesReels = apprentissagesReels ?? ApprentissagesO4.charger;

  Future<CorrespondanceO3>? _base;
  ApprentissagesO4? _simule;
  final Map<String, List<String>> _textes = {};
  final Map<String, List<_LigneLue>> _derniere = {};

  /// Apprentissages simulés (tests).
  ApprentissagesO4? get simule => _simule;

  @override
  void commencerSimulation() {
    _simule = ApprentissagesO4.memoire();
    _textes.clear();
    _derniere.clear();
  }

  @override
  void terminerSimulation() {
    _simule = null;
    _textes.clear();
    _derniere.clear();
  }

  Future<List<String>> _lire(String image) async {
    final t = _textes[image];
    if (t != null) return t;
    String? temporaire;
    try {
      if (preparation != null) temporaire = await preparation!(image);
      final r = await lecteur(temporaire ?? image);
      // Texte gardé en mémoire seulement pendant la simulation (2 passages sans relire l'image).
      if (_simule != null) _textes[image] = r;
      return r;
    } finally {
      if (temporaire != null && temporaire != image) {
        try {
          final f = File(temporaire);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
  }

  @override
  Future<ResultatPipeline> analyser(String cheminImage) async {
    List<String> texte;
    try {
      texte = await _lire(cheminImage);
    } catch (e) {
      return ResultatPipeline(produits: const [], erreur: 'Lecture impossible : ${e.runtimeType}');
    }
    final base = await (_base ??= correspondance());
    final o3 = base.avec(apprentissages: _simule ?? await apprentissagesReels());
    final lignes = decoupage(texte);
    final produits = <String>[];
    final lues = <_LigneLue>[];
    var sans = 0;
    String? panne;
    for (final l in lignes) {
      String? p;
      var cip = false;
      if (l.cip != null) {
        final m = await PrescriptionMatcher.match(l, recherche);
        if (m.kind == PrescriptionMatchKind.exactCip) {
          p = m.chosen!.strNAME;
          cip = true;
        }
      }
      if (p == null) {
        final r = await o3.proposer(l);
        p = r.meilleure?.produit.strNAME;
        panne ??= p == null ? r.panne : null;
      }
      lues.add(_LigneLue(l, p, cip));
      if (p == null) {
        sans++;
      } else {
        produits.add(p);
      }
    }
    if (_simule != null) _derniere[cheminImage] = lues;
    return ResultatPipeline(
      produits: produits,
      lignesDetectees: lignes.length,
      lignesSansProduit: sans,
      erreur: panne == null ? null : 'Recherche catalogue : $panne',
    );
  }

  @override
  Future<int> apprendreDe(String image, VeriteOrdonnance verite) async {
    final a = _simule, lues = _derniere[image];
    if (a == null || lues == null || !verite.scorable) return 0;
    final base = await (_base ??= correspondance());
    final attendus = [for (final p in verite.produits) (p, NormalisationProduit.normaliser(p.nom))];
    final pris = List<bool>.filled(attendus.length, false);
    final aligne = <(_LigneLue, int)>[];
    final restantes = <_LigneLue>[];
    // 1) Proposition juste : le pharmacien la valide.
    for (final l in lues) {
      if (l.cip) continue;
      final p = l.propose;
      var i = -1;
      if (p != null) {
        final np = NormalisationProduit.normaliser(p);
        for (var k = 0; k < attendus.length; k++) {
          if (!pris[k] && NormalisationProduit.correspond(attendus[k].$2, np)) {
            i = k;
            break;
          }
        }
      }
      if (i >= 0) {
        pris[i] = true;
        aligne.add((l, i));
      } else {
        restantes.add(l);
      }
    }
    // 2) Proposition fausse ou absente : le pharmacien choisit le bon produit (ligne rattachée au produit attendu
    //    le plus ressemblant, sinon dans l'ordre si les nombres concordent). Ligne sans produit attendu : retirée.
    final libres = [for (var k = 0; k < attendus.length; k++) if (!pris[k]) k];
    final sansPaire = <_LigneLue>[];
    for (final l in restantes) {
      final lu = NormalisationProduit.normaliser(l.ligne.text).marque;
      var best = -1;
      var bestS = 0.5;
      for (final k in libres) {
        final s = Similarite.ressemblanceDebut(lu, attendus[k].$2.marque);
        if (s > bestS) {
          bestS = s;
          best = k;
        }
      }
      if (best >= 0) {
        libres.remove(best);
        aligne.add((l, best));
      } else {
        sansPaire.add(l);
      }
    }
    if (sansPaire.length == libres.length) {
      for (var i = 0; i < sansPaire.length; i++) {
        aligne.add((sansPaire[i], libres[i]));
      }
    }
    var n = 0;
    for (final (l, k) in aligne) {
      final segment = SegmentMedicament.extraire(l.ligne.text);
      if (segment == null) continue;
      // Produit du catalogue correspondant au nom attendu (celui que le pharmacien choisirait).
      final r = await base.proposer(PrescriptionLine(text: attendus[k].$1.nom, query: attendus[k].$1.nom), n: 5);
      final p = r.propositions.where((x) => NormalisationProduit.correspond(attendus[k].$2, NormalisationProduit.normaliser(x.produit.strNAME))).firstOrNull;
      if (p == null) continue;
      await a.apprendre(segment: segment, produitId: p.produit.lgFAMILLEID, cip: p.produit.intCIP, nom: p.produit.strNAME);
      n++;
    }
    return n;
  }
}

/// Résultat d'une simulation : passage 1 (apprentissage pendant la lecture), passage 2 (mesure).
class SimulationApprentissage {
  final ScoreGlobal passage1;
  final ScoreGlobal passage2;
  final int lignesApprises;
  const SimulationApprentissage(this.passage1, this.passage2, this.lignesApprises);
}

/// Rejoue le banc deux fois avec apprentissage simulé (rien de réel n'est enregistré).
Future<SimulationApprentissage> simulerApprentissage(
  PipelineApprenant p,
  List<String> images,
  VeriteTerrain verite, {
  void Function()? progres,
}) async {
  String nom(String img) => img.split(RegExp(r'[\\/]')).last;
  p.commencerSimulation();
  try {
    final s1 = <ScoreOrdonnance>[];
    var appris = 0;
    for (final img in images) {
      final r = await p.analyser(img);
      s1.add(BancScore.evaluer(nom(img), verite.pour(img), r.produits, erreur: r.erreur));
      final v = verite.pour(img);
      if (v != null) appris += await p.apprendreDe(img, v);
      progres?.call();
    }
    final s2 = <ScoreOrdonnance>[];
    for (final img in images) {
      final r = await p.analyser(img);
      s2.add(BancScore.evaluer(nom(img), verite.pour(img), r.produits, erreur: r.erreur));
      progres?.call();
    }
    return SimulationApprentissage(ScoreGlobal(s1), ScoreGlobal(s2), appris);
  } finally {
    p.terminerSimulation();
  }
}
