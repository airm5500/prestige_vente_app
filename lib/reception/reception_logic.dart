// lib/reception/reception_logic.dart
// Règles de la réception mobile : contrôles d'une saisie de lot, bilan avant validation, réglages.
import 'dart:convert';

import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/services/datamatrix_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReceptionSettings {
  /// Péremption courte en dessous de ce nombre de mois.
  final int shortExpiryMonths;

  /// Ce terminal peut valider l'entrée en stock (le serveur vérifie en plus le droit de l'utilisateur).
  final bool terminalValidation;

  const ReceptionSettings({this.shortExpiryMonths = 6, this.terminalValidation = false});

  static const _key = 'reception_bl_settings_v1';

  ReceptionSettings copyWith({int? shortExpiryMonths, bool? terminalValidation}) => ReceptionSettings(
        shortExpiryMonths: shortExpiryMonths ?? this.shortExpiryMonths,
        terminalValidation: terminalValidation ?? this.terminalValidation,
      );

  static Future<ReceptionSettings> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return const ReceptionSettings();
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return ReceptionSettings(
        shortExpiryMonths: (j['shortExpiryMonths'] as num?)?.toInt() ?? 6,
        terminalValidation: j['terminalValidation'] == true,
      );
    } catch (_) {
      return const ReceptionSettings();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({'shortExpiryMonths': shortExpiryMonths, 'terminalValidation': terminalValidation}));
  }
}

/// Codes à chercher dans le BL pour un scan : DataMatrix -> EAN-13 puis CIP7 ; sinon le code lu tel quel.
({List<String> queries, DataMatrixData? dataMatrix}) scanQueries(String raw) {
  final value = raw.trim();
  final dm = DataMatrixParser.parse(value);
  if (dm != null && dm.productSearchQueries.isNotEmpty) {
    return (queries: dm.productSearchQueries, dataMatrix: dm);
  }
  final cleaned = value.replaceAll(RegExp(r'[\x00-\x1F]'), '');
  return (queries: cleaned.isEmpty ? const <String>[] : [cleaned], dataMatrix: dm);
}

/// Date saisie à la main : JJ/MM/AAAA, JJ/MM/AA, JJMMAA, MM/AAAA ou MM/AA (fin du mois).
DateTime? parseExpiryInput(String input) {
  final t = input.trim().replaceAll(RegExp(r'[.\-\s]'), '/');
  int year(String y) => y.length == 2 ? 2000 + int.parse(y) : int.parse(y);
  DateTime? valid(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1) return null;
    final date = DateTime(y, m, d);
    return date.month == m ? date : null;
  }

  var m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2}|\d{4})$').firstMatch(t);
  if (m != null) return valid(year(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  m = RegExp(r'^(\d{2})(\d{2})(\d{2})$').firstMatch(t);
  if (m != null) return valid(year(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  m = RegExp(r'^(\d{1,2})/(\d{2}|\d{4})$').firstMatch(t);
  if (m != null) {
    final y = year(m[2]!), mo = int.parse(m[1]!);
    if (mo < 1 || mo > 12) return null;
    return DateTime(y, mo + 1, 0); // dernier jour du mois
  }
  return null;
}

enum LotIssueKind {
  // Bloquants
  quantityInvalid,
  quantityTooHigh,
  lotMissing,
  expiryMissing,
  expired,
  expiryIncoherent,
  // À confirmer
  shortExpiry,
  lotAlreadyEntered,
  expiryMissingOptional,
}

class LotIssue {
  final LotIssueKind kind;
  final String message;
  const LotIssue(this.kind, this.message);

  bool get blocking => kind.index <= LotIssueKind.expiryIncoherent.index;
}

/// Contrôle une saisie avant l'envoi. Les problèmes bloquants empêchent l'envoi ;
/// les autres demandent une confirmation.
List<LotIssue> checkLotEntry({
  required ReceptionLine line,
  required String lot,
  required DateTime? expiry,
  required int quantity,
  required int freeQty,
  required DateTime now,
  required int shortExpiryMonths,
  required bool peremptionRequired,
}) {
  final issues = <LotIssue>[];
  final today = DateTime(now.year, now.month, now.day);
  if (quantity <= 0 || freeQty < 0) {
    issues.add(const LotIssue(LotIssueKind.quantityInvalid, 'Quantité nulle ou négative.'));
  } else if (quantity > line.remaining) {
    issues.add(LotIssue(
      LotIssueKind.quantityTooHigh,
      line.remaining == 0
          ? 'Ligne déjà complète (${line.entered}/${line.ordered}). Effacez ses lots pour ressaisir.'
          : 'Quantité supérieure au reste à saisir (${line.remaining}).',
    ));
  }
  if (lot.trim().isEmpty) issues.add(const LotIssue(LotIssueKind.lotMissing, 'Numéro de lot obligatoire.'));
  if (expiry == null) {
    issues.add(peremptionRequired
        ? const LotIssue(LotIssueKind.expiryMissing, 'Date de péremption obligatoire.')
        : const LotIssue(LotIssueKind.expiryMissingOptional, 'Pas de date de péremption.'));
  } else if (!expiry.isAfter(today)) {
    issues.add(const LotIssue(LotIssueKind.expired, 'LOT PÉRIMÉ : réception refusée.'));
  } else if (expiry.isAfter(DateTime(now.year + 15, now.month, now.day))) {
    issues.add(const LotIssue(LotIssueKind.expiryIncoherent, 'Année de péremption incohérente.'));
  } else {
    final limit = DateTime(now.year, now.month + shortExpiryMonths, now.day);
    if (expiry.isBefore(limit)) {
      final days = expiry.difference(today).inDays;
      issues.add(LotIssue(LotIssueKind.shortExpiry, 'PÉREMPTION COURTE : ce lot expire dans $days jours.'));
    }
  }
  final norm = lot.trim().toUpperCase();
  if (norm.isNotEmpty && line.lots.any((l) => l.toUpperCase() == norm)) {
    issues.add(LotIssue(
      LotIssueKind.lotAlreadyEntered,
      'DÉJÀ SAISI : le lot $norm est déjà enregistré sur cette ligne (${line.entered} boîte(s) saisie(s) au total).',
    ));
  }
  return issues;
}

/// Bilan d'un BL avant validation.
class ReceptionSummary {
  final List<ReceptionLine> lines;
  final List<ReceptionLine> notEntered;
  final List<ReceptionLine> partial;
  final List<ReceptionLine> complete;
  final List<ReceptionLine> missingExpiry;
  final List<({ReceptionLine line, DateTime expiry})> shortExpiries;

  ReceptionSummary._(this.lines, this.notEntered, this.partial, this.complete, this.missingExpiry, this.shortExpiries);

  factory ReceptionSummary.of(List<ReceptionLine> lines, {required DateTime now, required int shortExpiryMonths}) {
    final limit = DateTime(now.year, now.month + shortExpiryMonths, now.day);
    return ReceptionSummary._(
      lines,
      lines.where((l) => l.isEmpty).toList(),
      lines.where((l) => l.isPartial).toList(),
      lines.where((l) => l.isComplete).toList(),
      lines.where((l) => !l.isEmpty && l.expiries.isEmpty).toList(),
      [
        for (final l in lines)
          for (final e in l.expiries)
            if (e.isBefore(limit)) (line: l, expiry: e),
      ],
    );
  }

  int get orderedBoxes => lines.fold(0, (s, l) => s + l.ordered);
  int get enteredBoxes => lines.fold(0, (s, l) => s + l.entered);

  /// Prestige refuse l'entrée en stock tant qu'une ligne commencée n'est pas complète.
  bool get serverWillRefuse => partial.isNotEmpty;
}
