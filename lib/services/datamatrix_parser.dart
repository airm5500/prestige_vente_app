// lib/services/datamatrix_parser.dart
// Analyse du contenu d'un code DataMatrix lu par la douchette (émulation clavier).
//
// Formats reconnus :
//  - GS1 brut        : 0103400930000001172710311012345  (séparateur GS = ASCII 29 facultatif)
//  - GS1 lisible     : (01)03400930000001(17)271031(10)12345
//  - ASC MH10.8.2    : [)>RS06GS9N...GS1TLOTGSD271031...RS EOT (format PPN / IFA)
//  - Champs nommés   : EAN=3400930000001;LOT=ABC;EXP=2027-10-31
//
// Principe : on n'invente jamais une valeur. Lorsqu'un code GS1 sans séparateur
// peut être découpé de plusieurs façons, les valeurs possibles sont renvoyées
// comme candidats (non certaines) afin que l'opérateur choisisse.

const String _gs = '\u001d'; // Group Separator (FNC1)
const String _rs = '\u001e'; // Record Separator
const String _eot = '\u0004'; // End Of Transmission

enum DataMatrixFormat { gs1, asc, namedFields }

class DataMatrixData {
  /// Contenu brut tel que reçu.
  final String raw;
  final DataMatrixFormat format;

  /// GTIN sur 14 chiffres (clé de contrôle vérifiée).
  final String? gtin;

  /// Référence produit non GTIN (format à champs nommés uniquement).
  final String? productCode;

  /// Numéros de lot possibles. Un seul élément et [lotCertain] = lot fiable.
  final List<String> lotCandidates;
  final bool lotCertain;

  /// Dates de péremption possibles. Un seul élément et [expiryCertain] = date fiable.
  final List<DateTime> expiryCandidates;
  final bool expiryCertain;

  /// Une date de péremption est présente dans le code mais elle est impossible.
  final bool invalidExpiry;

  const DataMatrixData({
    required this.raw,
    required this.format,
    this.gtin,
    this.productCode,
    this.lotCandidates = const [],
    this.lotCertain = false,
    this.expiryCandidates = const [],
    this.expiryCertain = false,
    this.invalidExpiry = false,
  });

  String? get lot => lotCertain && lotCandidates.length == 1 ? lotCandidates.first : null;
  DateTime? get expiry => expiryCertain && expiryCandidates.length == 1 ? expiryCandidates.first : null;

  bool get isLotAmbiguous => lot == null && lotCandidates.isNotEmpty;
  bool get isExpiryAmbiguous => expiry == null && expiryCandidates.isNotEmpty;

  /// EAN-13 déduit du GTIN (GTIN commençant par 0).
  String? get ean13 => gtin != null && gtin!.startsWith('0') ? gtin!.substring(1) : null;

  /// Requêtes de recherche produit, par ordre de priorité :
  /// EAN-13, puis CIP7 extrait d'un CIP13 (34009 + CIP7 + clé), puis UPC-A.
  List<String> get productSearchQueries {
    final queries = <String>[];
    final g = gtin;
    if (g != null) {
      if (g.startsWith('0')) {
        final ean = g.substring(1);
        queries.add(ean);
        if (ean.startsWith('34009')) queries.add(ean.substring(5, 12));
        if (g.startsWith('00')) queries.add(g.substring(2));
      } else {
        queries.add(g);
      }
    } else if (productCode != null && productCode!.isNotEmpty) {
      queries.add(productCode!);
    }
    return queries.toSet().toList();
  }

  bool get hasUsefulData =>
      gtin != null || (productCode?.isNotEmpty ?? false) || lotCandidates.isNotEmpty || expiryCandidates.isNotEmpty;
}

class _AiSpec {
  final int? fixed;
  final int max;
  final bool numeric;
  final bool date;
  final bool checkDigit;

  const _AiSpec.fixed(int length, {this.date = false, this.checkDigit = false})
      : fixed = length,
        max = length,
        numeric = true;

  const _AiSpec.variable(this.max, {this.numeric = false})
      : fixed = null,
        date = false,
        checkDigit = false;
}

class _Field {
  final String ai;
  final String value;
  const _Field(this.ai, this.value);
}

class DataMatrixParser {
  DataMatrixParser._();

  static const int _maxInterpretations = 64;
  static const int _maxSteps = 20000;

  static final Map<String, _AiSpec> _specs = _buildSpecs();

  static Map<String, _AiSpec> _buildSpecs() {
    final specs = <String, _AiSpec>{
      '00': const _AiSpec.fixed(18, checkDigit: true), // SSCC
      '01': const _AiSpec.fixed(14, checkDigit: true), // GTIN
      '02': const _AiSpec.fixed(14, checkDigit: true), // GTIN contenu
      '03': const _AiSpec.fixed(14, checkDigit: true),
      '10': const _AiSpec.variable(20), // Lot
      '11': const _AiSpec.fixed(6, date: true), // Date de fabrication
      '12': const _AiSpec.fixed(6, date: true),
      '13': const _AiSpec.fixed(6, date: true),
      '15': const _AiSpec.fixed(6, date: true),
      '16': const _AiSpec.fixed(6, date: true),
      '17': const _AiSpec.fixed(6, date: true), // Date de péremption
      '20': const _AiSpec.fixed(2),
      '21': const _AiSpec.variable(20), // Numéro de série
      '22': const _AiSpec.variable(20),
      '235': const _AiSpec.variable(28),
      '240': const _AiSpec.variable(30),
      '241': const _AiSpec.variable(30),
      '242': const _AiSpec.variable(6, numeric: true),
      '243': const _AiSpec.variable(20),
      '250': const _AiSpec.variable(30),
      '251': const _AiSpec.variable(30),
      '254': const _AiSpec.variable(20),
      '30': const _AiSpec.variable(8, numeric: true), // Quantité
      '37': const _AiSpec.variable(8, numeric: true),
      '400': const _AiSpec.variable(30),
      '401': const _AiSpec.variable(30),
      '403': const _AiSpec.variable(30),
      '7003': const _AiSpec.fixed(10),
      // Numéros nationaux de remboursement (santé)
      '710': const _AiSpec.variable(20),
      '711': const _AiSpec.variable(20),
      '712': const _AiSpec.variable(20),
      '713': const _AiSpec.variable(20),
      '714': const _AiSpec.variable(20),
      '715': const _AiSpec.variable(20),
      '716': const _AiSpec.variable(20),
    };
    // Mesures (310n à 369n) : 6 chiffres
    for (var p = 31; p <= 36; p++) {
      for (var n = 0; n <= 99; n++) {
        specs['$p${n.toString().padLeft(2, '0')}'] = const _AiSpec.fixed(6);
      }
    }
    // Numéros de localisation (410 à 417) : 13 chiffres
    for (var n = 410; n <= 417; n++) {
      specs['$n'] = const _AiSpec.fixed(13, checkDigit: true);
    }
    return specs;
  }

  /// Analyse [input]. Renvoie `null` si le texte ne ressemble pas à un DataMatrix
  /// (ex. une recherche par nom, un CIP ou un EAN tapé normalement).
  static DataMatrixData? parse(String input, {DateTime? now}) {
    final today = now ?? DateTime.now();
    var s = _normalize(input);
    if (s.isEmpty) return null;

    var gs1Hint = false;
    final symbology = RegExp(r'^\][A-Za-z][0-9]').firstMatch(s);
    if (symbology != null) {
      const gs1Ids = {']d2', ']C1', ']Q3', ']e0', ']J1'};
      gs1Hint = gs1Ids.contains(symbology.group(0));
      s = s.substring(3);
    }

    if (s.startsWith('[)>')) return _parseAsc(s, input, today);

    while (s.startsWith(_gs)) {
      s = s.substring(1);
      gs1Hint = true;
    }
    if (s.isEmpty) return null;

    if (s.startsWith('(')) {
      final result = _parseBracketed(s, input, today);
      if (result != null) return result;
    }

    final named = _parseNamed(s, input, today);
    if (named != null) return named;

    final hasGs = s.contains(_gs);
    if (!gs1Hint && !hasGs && !s.startsWith('01')) return null;
    if (!RegExp(r'^[\x1d\x21-\x7e]+$').hasMatch(s)) return null;

    final result = _parseElementString(s, input, today, hasGs);
    if (result == null) return null;
    // Sans indice explicite (préfixe ]d2 ou séparateur GS), un GTIN valide est exigé
    // pour ne pas confondre une saisie numérique ordinaire avec un DataMatrix.
    if (!gs1Hint && !hasGs && result.gtin == null) return null;
    return result.hasUsefulData ? result : null;
  }

  /// Remplace les représentations textuelles du séparateur GS et retire les
  /// espaces / retours chariot ajoutés en fin de lecture par certaines douchettes.
  static String _normalize(String input) {
    var s = input
        .replaceAll('␝', _gs) // symbole ␝
        .replaceAll('<GS>', _gs)
        .replaceAll('[GS]', _gs)
        .replaceAll('{GS}', _gs)
        .replaceAll('␞', _rs)
        .replaceAll('<RS>', _rs)
        .replaceAll('<EOT>', _eot);
    s = s.replaceAll(RegExp(r'^[ \t\r\n]+|[ \t\r\n]+$'), '');
    while (s.endsWith(_gs) || s.endsWith(_eot)) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  // ---------------------------------------------------------------------------
  // GS1 lisible : (01)...(17)...(10)...
  // ---------------------------------------------------------------------------
  static DataMatrixData? _parseBracketed(String s, String raw, DateTime now) {
    final matches = RegExp(r'\((\d{2,4})\)([^()]*)').allMatches(s).toList();
    if (matches.isEmpty) return null;
    final consumed = matches.map((m) => m.group(0)!).join();
    if (consumed.replaceAll(RegExp(r'\s'), '') != s.replaceAll(RegExp(r'\s'), '')) return null;

    final fields = <_Field>[];
    var invalidExpiry = false;
    for (final m in matches) {
      final ai = m.group(1)!;
      final value = m.group(2)!.trim();
      final spec = _specs[ai];
      if (spec == null) continue; // AI inconnu : ignoré
      if (_accepts(spec, value, now)) {
        fields.add(_Field(ai, value));
      } else if (ai == '17') {
        invalidExpiry = true;
      }
    }
    final result = _fromInterpretations(raw, [fields], now, invalidExpiry: invalidExpiry);
    return result.hasUsefulData || invalidExpiry ? result : null;
  }

  // ---------------------------------------------------------------------------
  // GS1 brut
  // ---------------------------------------------------------------------------
  static DataMatrixData? _parseElementString(String s, String raw, DateTime now, bool hasGs) {
    final interpretations = <List<_Field>>[];
    final steps = [0];
    _explore(s, 0, <_Field>[], interpretations, hasGs, now, steps);

    if (interpretations.isNotEmpty && steps[0] < _maxSteps) {
      return _fromInterpretations(raw, interpretations, now);
    }

    // Aucun découpage complet : on ne conserve que le préfixe certain
    // (champs de longueur fixe en tête, ex. GTIN puis date).
    final prefix = <_Field>[];
    var invalidExpiry = false;
    var pos = 0;
    while (pos < s.length) {
      if (s[pos] == _gs) {
        pos++;
        continue;
      }
      final ai = _matchAi(s, pos);
      if (ai == null) break;
      final spec = _specs[ai]!;
      if (spec.fixed == null) break;
      final end = pos + ai.length + spec.fixed!;
      if (end > s.length) break;
      final value = s.substring(pos + ai.length, end);
      if (!_accepts(spec, value, now)) {
        if (ai == '17') invalidExpiry = true;
        break;
      }
      prefix.add(_Field(ai, value));
      pos = end;
    }
    if (prefix.isEmpty && !invalidExpiry) return null;
    return _fromInterpretations(raw, [prefix], now, invalidExpiry: invalidExpiry);
  }

  static void _explore(
    String s,
    int pos,
    List<_Field> acc,
    List<List<_Field>> out,
    bool hasGs,
    DateTime now,
    List<int> steps,
  ) {
    if (out.length >= _maxInterpretations || ++steps[0] > _maxSteps) return;
    if (pos == s.length) {
      out.add(List.of(acc));
      return;
    }
    if (s[pos] == _gs) {
      if (acc.isEmpty) return;
      _explore(s, pos + 1, acc, out, hasGs, now, steps);
      return;
    }
    final ai = _matchAi(s, pos);
    if (ai == null) return;
    final spec = _specs[ai]!;
    final start = pos + ai.length;

    if (spec.fixed != null) {
      final end = start + spec.fixed!;
      if (end > s.length) return;
      final value = s.substring(start, end);
      if (!_accepts(spec, value, now)) return;
      acc.add(_Field(ai, value));
      _explore(s, end, acc, out, hasGs, now, steps);
      acc.removeLast();
      return;
    }

    if (hasGs) {
      // Le lecteur transmet les séparateurs : le champ variable s'arrête au GS.
      final nextGs = s.indexOf(_gs, start);
      final end = nextGs == -1 ? s.length : nextGs;
      final value = s.substring(start, end);
      if (!_accepts(spec, value, now)) return;
      acc.add(_Field(ai, value));
      _explore(s, end, acc, out, hasGs, now, steps);
      acc.removeLast();
      return;
    }

    // Pas de séparateur : on essaie chaque longueur possible du champ variable.
    final maxEnd = start + spec.max < s.length ? start + spec.max : s.length;
    for (var end = start + 1; end <= maxEnd; end++) {
      if (end < s.length && _matchAi(s, end) == null) continue;
      final value = s.substring(start, end);
      if (!_accepts(spec, value, now)) continue;
      acc.add(_Field(ai, value));
      _explore(s, end, acc, out, hasGs, now, steps);
      acc.removeLast();
      if (out.length >= _maxInterpretations) return;
    }
  }

  static String? _matchAi(String s, int pos) {
    for (var len = 2; len <= 4; len++) {
      if (pos + len > s.length) return null;
      final candidate = s.substring(pos, pos + len);
      if (_specs.containsKey(candidate)) return candidate;
    }
    return null;
  }

  static bool _accepts(_AiSpec spec, String value, DateTime now) {
    if (value.isEmpty) return false;
    if (spec.fixed != null && value.length != spec.fixed) return false;
    if (value.length > spec.max) return false;
    if (!RegExp(r'^[\x21-\x7e]+$').hasMatch(value)) return false;
    if (spec.numeric && !RegExp(r'^\d+$').hasMatch(value)) return false;
    if (spec.checkDigit && !isValidGs1CheckDigit(value)) return false;
    if (spec.date && gs1Date(value, now: now) == null) return false;
    return true;
  }

  static DataMatrixData _fromInterpretations(
    String raw,
    List<List<_Field>> interpretations,
    DateTime now, {
    bool invalidExpiry = false,
  }) {
    final gtins = <String>{};
    final lots = <String>[];
    final expiries = <DateTime>[];
    var lotCertain = true;
    var expiryCertain = true;

    for (final fields in interpretations) {
      final gtin = _first(fields, '01');
      if (gtin != null) gtins.add(gtin);

      final lot = _first(fields, '10');
      if (lot == null) {
        lotCertain = false;
      } else if (!lots.contains(lot)) {
        lots.add(lot);
      }

      final exp = _first(fields, '17');
      final date = exp == null ? null : gs1Date(exp, now: now);
      if (date == null) {
        expiryCertain = false;
      } else if (!expiries.contains(date)) {
        expiries.add(date);
      }
    }

    return DataMatrixData(
      raw: raw,
      format: DataMatrixFormat.gs1,
      gtin: gtins.length == 1 ? gtins.first : null,
      lotCandidates: lots,
      lotCertain: lotCertain && lots.length == 1,
      expiryCandidates: expiries,
      expiryCertain: expiryCertain && expiries.length == 1,
      invalidExpiry: invalidExpiry,
    );
  }

  static String? _first(List<_Field> fields, String ai) {
    for (final f in fields) {
      if (f.ai == ai) return f.value;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // ASC MH10.8.2 (PPN / IFA) : [)> RS 06 GS 9N... GS 1T<lot> GS D<AAMMJJ> ... RS EOT
  // ---------------------------------------------------------------------------
  static DataMatrixData? _parseAsc(String s, String raw, DateTime now) {
    final segments = s.substring(3).replaceAll(_eot, '').split(RegExp('[$_rs$_gs]')).where((e) => e.isNotEmpty).toList();
    if (segments.length < 2 || segments.first != '06') return null;

    String? gtin;
    String? lot;
    DateTime? expiry;
    var invalidExpiry = false;
    for (final segment in segments.skip(1)) {
      final m = RegExp(r'^(\d{0,3}[A-Z])(.+)$').firstMatch(segment);
      if (m == null) continue;
      final di = m.group(1)!;
      final value = m.group(2)!;
      switch (di) {
        case '8P':
          final digits = value.length == 13 ? '0$value' : value;
          if (digits.length == 14 && RegExp(r'^\d+$').hasMatch(digits) && isValidGs1CheckDigit(digits)) gtin = digits;
          break;
        case '1T':
          lot = value;
          break;
        case 'D':
          expiry = gs1Date(value, now: now);
          invalidExpiry = expiry == null;
          break;
      }
    }
    final result = DataMatrixData(
      raw: raw,
      format: DataMatrixFormat.asc,
      gtin: gtin,
      lotCandidates: lot == null ? const [] : [lot],
      lotCertain: lot != null,
      expiryCandidates: expiry == null ? const [] : [expiry],
      expiryCertain: expiry != null,
      invalidExpiry: invalidExpiry,
    );
    return result.hasUsefulData || invalidExpiry ? result : null;
  }

  // ---------------------------------------------------------------------------
  // Champs nommés : EAN=...;LOT=...;EXP=...  (séparateurs ; | retour ligne)
  // ---------------------------------------------------------------------------
  static const _productKeys = {'GTIN', 'EAN', 'CIP', 'PRODUCT', 'PRODUIT'};
  static const _lotKeys = {'LOT', 'BATCH'};
  static const _expiryKeys = {'EXP', 'EXPIRY', 'EXPIRATION', 'DLC'};

  static DataMatrixData? _parseNamed(String s, String raw, DateTime now) {
    if (!s.contains('=') && !s.contains(':')) return null;
    String? gtin;
    String? productCode;
    String? lot;
    var expiries = <DateTime>[];
    var invalidExpiry = false;
    var known = 0;

    for (final part in s.split(RegExp('[;|\\r\\n$_gs]+'))) {
      final m = RegExp(r'^\s*([A-Za-z][A-Za-z ._\-]*?)\s*[=:]\s*(.*?)\s*$').firstMatch(part);
      if (m == null) continue;
      final key = m.group(1)!.toUpperCase().replaceAll(RegExp(r'[ ._\-]'), '');
      final value = m.group(2)!;
      if (value.isEmpty) continue;
      if (_productKeys.contains(key)) {
        known++;
        final digits = value.length >= 8 && value.length <= 14 && RegExp(r'^\d+$').hasMatch(value) ? value.padLeft(14, '0') : null;
        if (digits != null && isValidGs1CheckDigit(digits)) {
          gtin = digits;
        } else {
          productCode = value;
        }
      } else if (_lotKeys.contains(key)) {
        known++;
        lot = value;
      } else if (_expiryKeys.contains(key)) {
        known++;
        expiries = looseDateCandidates(value, now: now);
        invalidExpiry = expiries.isEmpty;
      }
    }
    if (known == 0) return null;

    return DataMatrixData(
      raw: raw,
      format: DataMatrixFormat.namedFields,
      gtin: gtin,
      productCode: gtin == null ? productCode : null,
      lotCandidates: lot == null ? const [] : [lot],
      lotCertain: lot != null,
      expiryCandidates: expiries,
      expiryCertain: expiries.length == 1,
      invalidExpiry: invalidExpiry,
    );
  }

  // ---------------------------------------------------------------------------
  // Outils
  // ---------------------------------------------------------------------------

  /// Clé de contrôle GS1 (modulo 10) d'un GTIN / SSCC / GLN.
  static bool isValidGs1CheckDigit(String digits) {
    if (digits.length < 2 || !RegExp(r'^\d+$').hasMatch(digits)) return false;
    var sum = 0;
    for (var i = digits.length - 2, weight = 3; i >= 0; i--, weight = weight == 3 ? 1 : 3) {
      sum += int.parse(digits[i]) * weight;
    }
    final check = (10 - sum % 10) % 10;
    return check == int.parse(digits[digits.length - 1]);
  }

  /// Date GS1 AAMMJJ. Un jour `00` désigne le dernier jour du mois.
  /// Siècle déterminé selon la règle GS1 (fenêtre glissante de 50 ans).
  static DateTime? gs1Date(String value, {DateTime? now}) {
    if (!RegExp(r'^\d{6}$').hasMatch(value)) return null;
    final yy = int.parse(value.substring(0, 2));
    final mm = int.parse(value.substring(2, 4));
    final dd = int.parse(value.substring(4, 6));
    final current = (now ?? DateTime.now()).year;
    final currentYy = current % 100;
    var century = current - currentYy;
    final diff = yy - currentYy;
    if (diff >= 51) century -= 100;
    if (diff <= -50) century += 100;
    return _validDate(century + yy, mm, dd, zeroDayIsLastDay: true);
  }

  /// Dates possibles pour une valeur libre (format à champs nommés) :
  /// AAAA-MM-JJ, JJ-MM-AAAA, AAAAMMJJ, JJMMAAAA, AAMMJJ, MM/AAAA.
  /// Si deux lectures sont valides (ex. 27/10/31), les deux sont renvoyées.
  static List<DateTime> looseDateCandidates(String value, {DateTime? now}) {
    final v = value.trim();
    final groups = v.split(RegExp(r'[\-/.\s]+')).where((g) => g.isNotEmpty).toList();
    if (groups.isEmpty || groups.any((g) => !RegExp(r'^\d+$').hasMatch(g))) return const [];
    final results = <DateTime>[];
    void add(DateTime? d) {
      if (d != null && !results.contains(d)) results.add(d);
    }

    int n(String x) => int.parse(x);
    if (groups.length == 3) {
      final a = groups[0], b = groups[1], c = groups[2];
      if (a.length == 4) {
        add(_validDate(n(a), n(b), n(c)));
      } else if (c.length == 4) {
        add(_validDate(n(c), n(b), n(a)));
      } else if (a.length <= 2 && b.length <= 2 && c.length <= 2) {
        add(gs1Date('${a.padLeft(2, '0')}${b.padLeft(2, '0')}${c.padLeft(2, '0')}', now: now));
        add(gs1Date('${c.padLeft(2, '0')}${b.padLeft(2, '0')}${a.padLeft(2, '0')}', now: now));
      }
    } else if (groups.length == 2) {
      final m = groups[0], y = groups[1];
      if (m.length <= 2 && (y.length == 4 || y.length == 2)) {
        final year = y.length == 4 ? n(y) : (gs1Date('${y}0101', now: now)?.year);
        if (year != null) add(_validDate(year, n(m), 0, zeroDayIsLastDay: true));
      }
    } else {
      final d = groups[0];
      if (d.length == 8) {
        add(_validDate(n(d.substring(0, 4)), n(d.substring(4, 6)), n(d.substring(6, 8))));
        add(_validDate(n(d.substring(4, 8)), n(d.substring(2, 4)), n(d.substring(0, 2))));
      } else if (d.length == 6) {
        add(gs1Date(d, now: now));
        add(gs1Date('${d.substring(4, 6)}${d.substring(2, 4)}${d.substring(0, 2)}', now: now));
      }
    }
    return results;
  }

  static DateTime? _validDate(int year, int month, int day, {bool zeroDayIsLastDay = false}) {
    if (year < 1900 || year > 2199 || month < 1 || month > 12) return null;
    final lastDay = DateTime(year, month + 1, 0).day;
    if (day == 0 && zeroDayIsLastDay) return DateTime(year, month, lastDay);
    if (day < 1 || day > lastDay) return null;
    return DateTime(year, month, day);
  }
}
