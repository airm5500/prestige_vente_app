// lib/services/label_text_parser.dart
// Lecture du lot et de la date de péremption imprimés en clair sur une boîte
// (texte reconnu par OCR sur une photo de l'étiquette).
//
// Précision avant tout : seules les valeurs précédées d'un libellé explicite
// (LOT, EXP, PER...) ou d'un identifiant GS1 imprimé ((10), (17)) sont retenues
// comme fiables. Le reste n'est proposé qu'en candidat, et l'opérateur confirme
// toujours avant enregistrement.
import 'package:prestige_vente_app/services/datamatrix_parser.dart';

class LabelData {
  final List<String> rawLines;
  final String? gtin;
  final List<String> lotCandidates;
  final bool lotFromLabel; // lot trouvé derrière un libellé explicite
  final List<DateTime> expiryCandidates;
  final bool expiryFromLabel; // date trouvée derrière un libellé explicite

  const LabelData({
    required this.rawLines,
    this.gtin,
    this.lotCandidates = const [],
    this.lotFromLabel = false,
    this.expiryCandidates = const [],
    this.expiryFromLabel = false,
  });

  bool get isEmpty => gtin == null && lotCandidates.isEmpty && expiryCandidates.isEmpty;
}

class LabelTextParser {
  LabelTextParser._();

  static const _months = <String, int>{
    'JAN': 1, 'JANV': 1, 'JANVIER': 1, 'JANUARY': 1,
    'FEB': 2, 'FEV': 2, 'FEVR': 2, 'FEVRIER': 2, 'FEBRUARY': 2,
    'MAR': 3, 'MARS': 3, 'MARCH': 3,
    'APR': 4, 'AVR': 4, 'AVRIL': 4, 'APRIL': 4,
    'MAY': 5, 'MAI': 5,
    'JUN': 6, 'JUIN': 6, 'JUNE': 6,
    'JUL': 7, 'JUIL': 7, 'JUILLET': 7, 'JULY': 7,
    'AUG': 8, 'AOU': 8, 'AOUT': 8, 'AUGUST': 8,
    'SEP': 9, 'SEPT': 9, 'SEPTEMBRE': 9, 'SEPTEMBER': 9,
    'OCT': 10, 'OCTOBRE': 10, 'OCTOBER': 10,
    'NOV': 11, 'NOVEMBRE': 11, 'NOVEMBER': 11,
    'DEC': 12, 'DECEMBRE': 12, 'DECEMBER': 12,
  };

  static final _lotLabel = RegExp(
    r'(?:N[°O]\s*DE\s*LOT|LOT\s*N[°O]?|LOT|BATCH\s*(?:NO|N[°O]|NUMBER)?|\bB\s?\.?\s?N(?:O|°)?\b\.*|\bCH\.?-?B\b)\s*[:.#/]*\s*',
  );
  static final _expLabel = RegExp(
    r'(?:EXPIRY\s*DATE|EXP(?:IRY|IRATION)?\.?\s*(?:DATE)?|DATE\s*(?:DE\s*)?(?:PER(?:EMPTION)?|EXP)\.?|PER(?:EMPTION)?\.?|UTILISER\s*AVANT|USE\s*BY|DLU|DLC|\bVAL\.?)\s*[:./]*\s*',
  );
  static final _mfgLabel = RegExp(r'(?:MFG|MFD|MANUF\w*|FAB(?:RICATION)?\.?|PROD(?:UCTION)?|DOM|DATE\s*(?:DE\s*)?FAB)');

  static String _norm(String s) {
    const from = 'àâäáçéèêëíìîïóòôöúùûüÀÂÄÁÇÉÈÊËÍÌÎÏÓÒÔÖÚÙÛÜ';
    const to = 'aaaaceeeeiiiioooouuuuAAAACEEEEIIIIOOOOUUUU';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString().toUpperCase().replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }

  static LabelData parse(List<String> lines, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final norm = lines.map(_norm).where((l) => l.isNotEmpty).toList();

    final lots = <String>[];
    final expiries = <DateTime>[];
    var lotFromLabel = false;
    var expiryFromLabel = false;
    String? gtin;

    void addLot(String v) {
      if (!lots.contains(v)) lots.add(v);
    }

    void addExp(DateTime d) {
      if (!expiries.contains(d)) expiries.add(d);
    }

    // 1. Mentions GS1 imprimées en clair : (01)... (17)... (10)...
    final joined = norm.join(' ');
    for (final m in RegExp(r'\((\d{2})\)\s*([0-9A-Z\-/.]+)').allMatches(joined)) {
      final ai = m.group(1)!;
      final v = m.group(2)!;
      if (ai == '01' && v.length >= 14) {
        final g = v.substring(0, 14);
        if (DataMatrixParser.isValidGs1CheckDigit(g)) gtin = g;
      } else if (ai == '10' && v.length <= 20) {
        addLot(v);
        lotFromLabel = true;
      } else if (ai == '17' && v.length >= 6) {
        final d = DataMatrixParser.gs1Date(v.substring(0, 6), now: today);
        if (d != null) {
          addExp(d);
          expiryFromLabel = true;
        }
      }
    }

    // 2. Libellés explicites : LOT / BATCH, EXP / PER...
    for (var i = 0; i < norm.length; i++) {
      final line = norm[i];
      final next = i + 1 < norm.length ? norm[i + 1] : '';

      final lotMatch = _lotLabel.firstMatch(line);
      if (lotMatch != null && !_isInsideWord(line, lotMatch.start)) {
        var rest = _stripLotLabels(line.substring(lotMatch.end));
        if (rest.isEmpty) rest = _stripLotLabels(next); // valeur imprimée sur la ligne suivante
        final v = _firstToken(rest);
        if (v != null && _looksLikeLot(v)) {
          addLot(v);
          lotFromLabel = true;
        }
      }

      final expMatch = _expLabel.firstMatch(line);
      // Libellé de fabrication collé juste avant (ex. "FAB./PER.") : ce n'est pas une péremption.
      if (expMatch != null &&
          !_isInsideWord(line, expMatch.start) &&
          !_mfgLabel.hasMatch(line.substring((expMatch.start - 6).clamp(0, line.length), expMatch.start))) {
        var rest = line.substring(expMatch.end).trim();
        var dates = _datesIn(rest, today);
        if (dates.isEmpty && rest.isEmpty) dates = _datesIn(next, today);
        for (final d in dates.take(1)) {
          addExp(d);
          expiryFromLabel = true;
        }
      }
    }

    // 3. GTIN libellé ("GTIN : 08901296107140"), sinon EAN-13 imprimé sous le code-barres
    for (final line in norm) {
      if (gtin != null) break;
      final m = RegExp(r'\b(?:GTIN|EAN)\s*[:.]*\s*(\d{13,14})(?![0-9])').firstMatch(line);
      if (m != null) {
        final g = m.group(1)!.padLeft(14, '0');
        if (DataMatrixParser.isValidGs1CheckDigit(g)) gtin = g;
      }
    }
    gtin ??= _findEan13(norm);

    // 4. Sans libellé de péremption : dates proposées (hors fabrication), la plus tardive d'abord.
    if (expiries.isEmpty) {
      final found = <DateTime>[];
      for (final line in norm) {
        // Sur une ligne fusionnée "MFG 09/2024  EXP ...", seules les parties hors fabrication comptent.
        for (final part in line.split(RegExp(r'\s{2,}'))) {
        if (_mfgLabel.hasMatch(part)) continue;
        for (final d in _datesIn(part, today)) {
          if (!found.contains(d)) found.add(d);
        }
        }
      }
      found.sort((a, b) => b.compareTo(a));
      expiries.addAll(found);
    }

    return LabelData(
      rawLines: lines,
      gtin: gtin,
      lotCandidates: lots,
      lotFromLabel: lotFromLabel,
      expiryCandidates: expiries,
      expiryFromLabel: expiryFromLabel,
    );
  }

  /// Retire les libellés enchaînés : "LOT/BATCH :", "BATCH NO./ N° DE LOT :"...
  static String _stripLotLabels(String s) => s
      .replaceFirst(RegExp(r'^(?:[\s:./#\-]|LOT\b|BATCH\b|NO\b|N°|N\b|NUMBER\b|DE\b)+'), '')
      .trim();

  /// EAN-13 à clé valide formé de groupes de chiffres séparés par des espaces.
  static String? _findEan13(List<String> lines) {
    for (final line in lines) {
      final groups = RegExp(r'\d+').allMatches(line).toList();
      for (var i = 0; i < groups.length; i++) {
        var digits = '';
        for (var j = i; j < groups.length; j++) {
          if (j > i && line.substring(groups[j - 1].end, groups[j].start) != ' ') break;
          digits += groups[j].group(0)!;
          if (digits.length > 13) break;
          if (digits.length == 13 && DataMatrixParser.isValidGs1CheckDigit(digits)) return '0$digits';
        }
      }
    }
    return null;
  }

  static bool _isInsideWord(String line, int start) =>
      start > 0 && RegExp(r'[A-Z0-9]').hasMatch(line[start - 1]);

  static String? _firstToken(String s) {
    final m = RegExp(r'^[A-Z0-9][A-Z0-9\-/.]*').firstMatch(s.trim());
    if (m == null) return null;
    return m.group(0)!.replaceAll(RegExp(r'[.\-/]+$'), '');
  }

  static bool _looksLikeLot(String v) {
    if (v.length < 2 || v.length > 20) return false;
    if (_expLabel.hasMatch(v) && RegExp(r'^(EXP|PER|DLU|DLC|VAL)').hasMatch(v)) return false;
    return RegExp(r'\d').hasMatch(v) || v.length >= 4;
  }

  /// Dates reconnues dans un texte, dans l'ordre d'apparition.
  /// Mois seul (10/2027, OCT 2027) = dernier jour du mois.
  static List<DateTime> _datesIn(String s, DateTime now) {
    final out = <DateTime>[];
    void add(DateTime? d) {
      if (d != null && !out.contains(d)) out.add(d);
    }

    int year(String y) {
      if (y.length == 4) return int.parse(y);
      return DataMatrixParser.gs1Date('${y.padLeft(2, '0')}0101', now: now)?.year ?? 2000 + int.parse(y);
    }

    DateTime? ymd(int y, int m, int d) {
      if (m < 1 || m > 12 || y < 2000 || y > 2099) return null;
      final last = DateTime(y, m + 1, 0).day;
      if (d == 0) return DateTime(y, m, last);
      if (d < 1 || d > last) return null;
      return DateTime(y, m, d);
    }

    var rest = s;
    // JJ/MM/AAAA ou JJ.MM.AA
    for (final m in RegExp(r'(?<![0-9])(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4}|\d{2})(?![0-9])').allMatches(rest)) {
      add(ymd(year(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!)));
    }
    rest = rest.replaceAll(RegExp(r'(?<![0-9])\d{1,2}[/.\-]\d{1,2}[/.\-](\d{4}|\d{2})(?![0-9])'), ' ');
    // AAAA-MM-JJ / AAAA-MM
    for (final m in RegExp(r'(?<![0-9])(20\d{2})[/.\-](\d{1,2})(?:[/.\-](\d{1,2}))?(?![0-9])').allMatches(rest)) {
      add(ymd(int.parse(m.group(1)!), int.parse(m.group(2)!), m.group(3) == null ? 0 : int.parse(m.group(3)!)));
    }
    rest = rest.replaceAll(RegExp(r'(?<![0-9])20\d{2}[/.\-]\d{1,2}([/.\-]\d{1,2})?(?![0-9])'), ' ');
    // MM/AAAA ou MM/AA
    for (final m in RegExp(r'(?<![0-9])(\d{1,2})[/.\-](\d{4}|\d{2})(?![0-9])').allMatches(rest)) {
      add(ymd(year(m.group(2)!), int.parse(m.group(1)!), 0));
    }
    // MOIS AAAA (OCT 2027, OCT.27, 31 OCT 2027)
    for (final m in RegExp(r'(?:(\d{1,2})\s*)?\b([A-Z]{3,9})\.?\s*[\-/.]?\s*(\d{4}|\d{2})(?![0-9])').allMatches(s)) {
      final month = _months[m.group(2)!];
      if (month == null) continue;
      add(ymd(year(m.group(3)!), month, m.group(1) == null ? 0 : int.parse(m.group(1)!)));
    }
    return out;
  }
}
