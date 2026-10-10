// lib/ordonnances/banc_essai/historique_banc.dart
// Banc d'essai des ordonnances : historique des scores (sur l'appareil uniquement, rien n'est envoyé)
// et rapport texte / CSV SANS le texte reconnu (seulement produits attendus / proposés).
import 'dart:convert';

import 'package:prestige_vente_app/ordonnances/banc_essai/score_banc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Version de l'application (identique à `version:` de pubspec.yaml, vérifié par les tests).
const String versionAppli = '1.2.0';

/// Une ligne de l'historique : un passage d'un pipeline sur un lot d'images.
class EntreeHistorique {
  final DateTime date;
  final String version;
  final String pipeline;
  final int images;
  final int comptees;
  final int correctes;
  final int attendus;
  final int trouves;
  final int fauxPositifs;

  const EntreeHistorique({
    required this.date,
    required this.version,
    required this.pipeline,
    required this.images,
    required this.comptees,
    required this.correctes,
    required this.attendus,
    required this.trouves,
    required this.fauxPositifs,
  });

  factory EntreeHistorique.depuis(ScoreGlobal s, {required String pipeline, DateTime? date, String version = versionAppli}) =>
      EntreeHistorique(
        date: date ?? DateTime.now(),
        version: version,
        pipeline: pipeline,
        images: s.ordonnances.length,
        comptees: s.nbComptees,
        correctes: s.nbCorrectes,
        attendus: s.nbAttendus,
        trouves: s.nbTrouves,
        fauxPositifs: s.nbFauxPositifs,
      );

  double get rappel => attendus == 0 ? 0 : trouves / attendus;
  double get precision => trouves + fauxPositifs == 0 ? 1 : trouves / (trouves + fauxPositifs);

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'version': version,
        'pipeline': pipeline,
        'images': images,
        'comptees': comptees,
        'correctes': correctes,
        'attendus': attendus,
        'trouves': trouves,
        'fauxPositifs': fauxPositifs,
      };

  factory EntreeHistorique.fromJson(Map<String, dynamic> j) => EntreeHistorique(
        date: DateTime.parse(j['date'] as String),
        version: j['version'] as String? ?? '?',
        pipeline: j['pipeline'] as String? ?? '?',
        images: (j['images'] as num?)?.toInt() ?? 0,
        comptees: (j['comptees'] as num?)?.toInt() ?? 0,
        correctes: (j['correctes'] as num?)?.toInt() ?? 0,
        attendus: (j['attendus'] as num?)?.toInt() ?? 0,
        trouves: (j['trouves'] as num?)?.toInt() ?? 0,
        fauxPositifs: (j['fauxPositifs'] as num?)?.toInt() ?? 0,
      );
}

/// Historique local (SharedPreferences), le plus récent en premier, limité à [maxEntrees].
class HistoriqueBanc {
  static const _cle = 'banc_ordonnances_historique_v1';
  static const maxEntrees = 100;

  static Future<List<EntreeHistorique>> charger() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_cle);
      if (raw == null) return [];
      return [for (final e in jsonDecode(raw) as List) EntreeHistorique.fromJson(e as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  static Future<List<EntreeHistorique>> ajouter(EntreeHistorique e) async {
    final liste = [e, ...await charger()].take(maxEntrees).toList();
    final p = await SharedPreferences.getInstance();
    await p.setString(_cle, jsonEncode([for (final x in liste) x.toJson()]));
    return liste;
  }

  static Future<void> vider() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_cle);
  }
}

/// Rapports exportables : uniquement fichiers, produits attendus / proposés et scores.
class RapportBanc {
  RapportBanc._();

  static String _pct(double v) => ScoreGlobal.pourcent(v);

  static String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String resume(ScoreGlobal s) =>
      '${s.correctes} ordonnances entièrement correctes · rappel ${_pct(s.rappel)} · précision ${_pct(s.precision)} '
      '(${s.nbTrouves}/${s.nbAttendus} produits trouvés, ${s.nbFauxPositifs} faux positifs)';

  static String texte(Map<String, ScoreGlobal> parPipeline, {DateTime? date, String version = versionAppli}) {
    final b = StringBuffer()
      ..writeln('Banc d\'essai ordonnances — Prestige Mobile $version — ${_d(date ?? DateTime.now())}')
      ..writeln('(Rapport sans texte reconnu : seulement les produits attendus et proposés.)');
    for (final e in parPipeline.entries) {
      b
        ..writeln()
        ..writeln('== ${e.key} ==')
        ..writeln(resume(e.value));
      for (final o in e.value.ordonnances) {
        b.writeln('- ${o.fichier} : ${o.statut}');
        for (final t in o.trouves) {
          b.writeln('    trouvé   : ${t.$1.nom}  →  ${t.$2}');
        }
        for (final m in o.manques) {
          b.writeln('    manqué   : ${m.nom}');
        }
        for (final f in o.fauxPositifs) {
          b.writeln('    en trop  : $f');
        }
        if (!o.compte && o.proposes.isNotEmpty) b.writeln('    proposés : ${o.proposes.join(' ; ')}');
        if (o.erreur != null) b.writeln('    erreur   : ${o.erreur}');
      }
    }
    return b.toString();
  }

  static String _csv(String v) => '"${v.replaceAll('"', '""')}"';

  /// CSV (séparateur « ; », Excel français) : une ligne par produit attendu / proposé.
  static String csv(Map<String, ScoreGlobal> parPipeline) {
    final b = StringBuffer()..writeln('pipeline;fichier;statut;resultat;attendu;propose');
    for (final e in parPipeline.entries) {
      for (final o in e.value.ordonnances) {
        void row(String res, String att, String prop) =>
            b.writeln([e.key, o.fichier, o.statut, res, att, prop].map(_csv).join(';'));
        for (final t in o.trouves) {
          row('trouve', t.$1.nom, t.$2);
        }
        for (final m in o.manques) {
          row('manque', m.nom, '');
        }
        for (final f in o.fauxPositifs) {
          row('faux_positif', '', f);
        }
        if (!o.compte) {
          for (final p in o.proposes) {
            row('sans_verite', '', p);
          }
        }
        if (o.erreur != null) row('erreur', '', o.erreur!);
      }
    }
    return b.toString();
  }
}
