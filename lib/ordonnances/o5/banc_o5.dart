// lib/ordonnances/o5/banc_o5.dart
// Étape O5 au banc d'essai : candidat « Lecture avancée (en ligne) », proposé seulement si la lecture avancée est
// activée (consentement) et annoncée par le serveur. Chaque image est recadrée sur la page sans ses bandes haut / bas
// (masquées), sans métadonnées, puis envoyée ; le banc demande une confirmation explicite avant d'envoyer le jeu.
// Les lignes lues passent par le découpage O2 et la correspondance O3 comme les autres candidats.
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:prestige_vente_app/ordonnances/banc_essai/pipeline_ordonnance.dart';
import 'package:prestige_vente_app/ordonnances/o2/decoupage_ordonnance.dart';
import 'package:prestige_vente_app/ordonnances/o3/correspondance_o3.dart';
import 'package:prestige_vente_app/ordonnances/o5/lecture_avancee.dart';
import 'package:prestige_vente_app/ordonnances/o5/masquage_o5.dart';

class PipelineLectureAvancee implements PipelineOrdonnance {
  @override
  String get id => 'o5';
  @override
  String get libelle => 'Lecture avancée (en ligne)';

  final LectureAvancee service;
  final Future<CorrespondanceO3> Function() correspondance;
  Future<CorrespondanceO3>? _o3;

  PipelineLectureAvancee({required this.service, required this.correspondance});

  @override
  Future<ResultatPipeline> analyser(String cheminImage) async {
    final Uint8List source;
    try {
      source = await File(cheminImage).readAsBytes();
    } catch (e) {
      return ResultatPipeline(produits: const [], erreur: 'Lecture impossible : ${e.runtimeType}');
    }
    final jpeg = await Isolate.run(() => MasquageO5.preparer(source, MasquageO5.zoneBanc));
    final r = await service.lire(jpeg, origine: 'banc d\'essai');
    if (!r.ok) return ResultatPipeline(produits: const [], erreur: r.erreur);
    final lignes = DecoupageOrdonnance.extraire(r.texte);
    final o3 = await (_o3 ??= correspondance());
    final produits = <String>[];
    var sans = 0;
    for (final l in lignes) {
      final p = (await o3.proposer(l)).meilleure?.produit.strNAME;
      if (p == null) {
        sans++;
      } else {
        produits.add(p);
      }
    }
    return ResultatPipeline(produits: produits, lignesDetectees: lignes.length, lignesSansProduit: sans);
  }
}
