// lib/screens/reception_bl/reception_bl_screen.dart
// Saisie d'un BL par scan : produit -> lot / péremption (DataMatrix ou photo guidée) -> quantité -> ligne suivante.
// Chaque lot est enregistré tout de suite sur Prestige (le stock ne bouge qu'à l'entrée en stock) :
// plusieurs employés peuvent travailler sur le même BL.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/screens/common/camera_scan_screen.dart';
import 'package:prestige_vente_app/screens/common/guided_capture_screen.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_summary_screen.dart';
import 'package:prestige_vente_app/services/datamatrix_parser.dart';
import 'package:prestige_vente_app/services/label_text_parser.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Lecture d'un code par la caméra (remplaçable pour les tests).
typedef CodeCamera = Future<String?> Function(BuildContext context, {bool dataMatrixOnly});

/// Photo guidée de l'étiquette -> lignes de texte (remplaçable pour les tests).
typedef LabelCamera = Future<List<String>?> Function(BuildContext context);

enum _Filter { todo, partial, done, all }

class ReceptionBlScreen extends StatefulWidget {
  final ReceptionBl bl;
  final ReceptionGateway gateway;
  final ReceptionSettings settings;
  final CodeCamera? codeCamera;
  final LabelCamera? labelCamera;
  final DateTime Function()? clock;

  /// Présentation (A, B, C) ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;

  const ReceptionBlScreen({
    super.key,
    required this.bl,
    required this.gateway,
    required this.settings,
    this.codeCamera,
    this.labelCamera,
    this.clock,
    this.presentation,
  });

  @override
  State<ReceptionBlScreen> createState() => _ReceptionBlScreenState();
}

class _ReceptionBlScreenState extends State<ReceptionBlScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  static final _fmt = DateFormat('dd/MM/yyyy');

  List<ReceptionLine> _lines = [];
  bool _loading = true;
  bool _busy = false;
  String? _loadError;
  _Filter _filter = _Filter.todo;

  // Scan (le scanner Sunmi « tape » dans ce champ, sans clavier à l'écran).
  final _scan = TextEditingController();
  final _scanFocus = FocusNode();
  bool _scanKeyboard = false;
  Timer? _scanDebounce;

  // Ligne en cours
  ReceptionLine? _current;
  final _lot = TextEditingController();
  final _date = TextEditingController();
  final _qty = TextEditingController();
  final _ug = TextEditingController(text: '0');
  final _qtyFocus = FocusNode();
  final _lotFocus = FocusNode();
  final _dateFocus = FocusNode();
  String? _source; // d'où viennent le lot et la date
  List<String> _lotChoices = const [];
  List<DateTime> _dateChoices = const [];

  DateTime _now() => (widget.clock ?? DateTime.now)();
  bool get _peremptionRequired => !widget.bl.peremptionOptional;

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _load();
  }

  @override
  void dispose() {
    _scanDebounce?.cancel();
    for (final c in [_scan, _lot, _date, _qty, _ug]) {
      c.dispose();
    }
    for (final f in [_scanFocus, _qtyFocus, _lotFocus, _dateFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final lines = await widget.gateway.lines(widget.bl.id);
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _loading = false;
        if (_current != null) {
          _current = lines.where((l) => l.detailId == _current!.detailId).firstOrNull ?? _current;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Lignes du BL non chargées. Vérifiez la connexion au serveur.';
        });
      }
    }
  }

  void _replaceLine(ReceptionLine l) {
    final i = _lines.indexWhere((x) => x.detailId == l.detailId);
    if (i >= 0) _lines[i] = l;
  }

  // ---------------------------------------------------------------------------
  // Scan
  // ---------------------------------------------------------------------------
  void _onScanChanged(String v) {
    _scanDebounce?.cancel();
    if (_scanKeyboard || v.trim().isEmpty) return;
    _scanDebounce = Timer(const Duration(milliseconds: 350), () => _submitScan(_scan.text));
  }

  void _submitScan(String v) {
    _scanDebounce?.cancel();
    _scan.clear();
    if (v.trim().isNotEmpty) _onScan(v);
  }

  /// Un DataMatrix tapé par le scanner dans le champ lot ou date est repris comme un scan.
  void _interceptFieldScan(TextEditingController c, String v) {
    if (v.length < 16) return;
    final dm = DataMatrixParser.parse(v);
    if (dm == null || !dm.hasUsefulData) return;
    c.clear();
    _onScan(v);
  }

  Future<void> _cameraScan({bool dataMatrixOnly = false}) async {
    final camera = widget.codeCamera ??
        (BuildContext ctx, {bool dataMatrixOnly = false}) => CameraScanScreen.open(
              ctx,
              title: dataMatrixOnly ? 'Scanner le DataMatrix (lot / date)' : 'Scanner le produit',
              dataMatrixOnly: dataMatrixOnly,
            );
    final value = await camera(context, dataMatrixOnly: dataMatrixOnly);
    if (value != null && mounted) await _onScan(value);
  }

  /// Cherche les lignes du BL correspondant aux codes (données à jour : saisies des collègues comprises).
  Future<List<ReceptionLine>> _find(List<String> queries) async {
    for (final q in queries) {
      final found = await widget.gateway.lines(widget.bl.id, query: q);
      if (found.isNotEmpty) return found;
    }
    return const [];
  }

  Future<void> _onScan(String raw) async {
    if (_busy) return;
    final (:queries, :dataMatrix) = scanQueries(raw);
    final dm = dataMatrix;

    // DataMatrix sans code produit (lot / date seuls) : complète la ligne en cours.
    if (dm != null && dm.gtin == null && dm.hasUsefulData && _current != null) {
      _applyLotDate(dm.lotCandidates, dm.expiryCandidates, dm.lot, dm.expiry, 'DataMatrix');
      return;
    }
    if (queries.isEmpty) return;

    setState(() => _busy = true);
    List<ReceptionLine> found;
    try {
      found = await _find(queries);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _alert('Serveur injoignable', 'Le produit n\'a pas pu être recherché. Vérifiez la connexion.');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    for (final l in found) {
      _replaceLine(l);
    }

    if (found.isEmpty) {
      HapticFeedback.heavyImpact();
      await _alert(
        'Produit absent de ce BL',
        'Le code ${queries.first} ne correspond à aucune ligne du BL ${widget.bl.ref}.\n'
            'Mettez le produit de côté : il sera signalé au fournisseur.',
        blocking: true,
      );
      return;
    }
    ReceptionLine? line = found.length == 1 ? found.single : await _choose(found);
    if (line == null || !mounted) return;

    final current = _current;
    if (current != null && line.detailId != current.detailId && dm != null && dm.hasUsefulData) {
      // DataMatrix d'un autre produit que la ligne ouverte : bloquant.
      HapticFeedback.heavyImpact();
      final switchTo = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.block, color: Colors.red, size: 40),
          title: const Text('Autre produit'),
          content: Text('Ce DataMatrix appartient à :\n${line.name}\n\nLigne ouverte :\n${current.name}'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('Rester sur ${_short(current.name)}')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('Passer à ${_short(line.name)}')),
          ],
        ),
      );
      if (switchTo != true) return;
    }

    if (line.detailId == current?.detailId) {
      // Même produit : on garde ce qui est déjà saisi, la ligne est simplement mise à jour.
      setState(() => _current = line);
    } else {
      _openLine(line);
    }
    if (dm != null && dm.hasUsefulData) {
      _applyLotDate(dm.lotCandidates, dm.expiryCandidates, dm.lot, dm.expiry, 'DataMatrix');
    }
  }

  String _short(String s) => s.length > 18 ? '${s.substring(0, 18)}…' : s;

  Future<ReceptionLine?> _choose(List<ReceptionLine> lines) => showDialog<ReceptionLine>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Plusieurs produits correspondent'),
          children: [
            for (final l in lines)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(l),
                child: Text('${l.name}\n${l.code} · ${l.entered}/${l.ordered}'),
              ),
          ],
        ),
      );

  // ---------------------------------------------------------------------------
  // Ligne en cours
  // ---------------------------------------------------------------------------
  void _openLine(ReceptionLine line) {
    setState(() {
      _current = line;
      _lot.clear();
      _date.clear();
      _ug.text = '0';
      _qty.text = line.remaining > 0 ? '${line.remaining}' : '';
      _source = null;
      _lotChoices = const [];
      _dateChoices = const [];
    });
    _focusNext();
  }

  void _closeLine() {
    setState(() => _current = null);
    _scanFocus.requestFocus();
  }

  void _applyLotDate(List<String> lots, List<DateTime> dates, String? lot, DateTime? date, String source) {
    setState(() {
      if (lot != null) {
        _lot.text = lot;
      } else if (lots.isNotEmpty && _lot.text.isEmpty) {
        _lot.text = lots.first;
      }
      if (date != null) {
        _date.text = _fmt.format(date);
      } else if (dates.isNotEmpty && _date.text.isEmpty) {
        _date.text = _fmt.format(dates.first);
      }
      _lotChoices = lots.length > 1 ? lots : const [];
      _dateChoices = dates.length > 1 ? dates : const [];
      _source = source;
    });
    _focusNext();
  }

  /// Lot et date connus -> quantité ; sinon on attend le DataMatrix (champ de scan).
  void _focusNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _current == null) return;
      if (_lot.text.isNotEmpty && (_date.text.isNotEmpty || !_peremptionRequired)) {
        _qtyFocus.requestFocus();
        _qty.selection = TextSelection(baseOffset: 0, extentOffset: _qty.text.length);
      } else {
        _scanFocus.requestFocus();
      }
    });
  }

  Future<void> _photoLabel() async {
    final reader = widget.labelCamera ?? (ctx) => GuidedCaptureScreen.open(ctx);
    final lines = await reader(context);
    if (lines == null || !mounted) return;
    final label = LabelTextParser.parse(lines);
    if (label.lotCandidates.isEmpty && label.expiryCandidates.isEmpty) {
      Constants.showSnackBar(context, 'Ni lot ni date lisibles. Cadrez uniquement LOT et EXP.', isError: true);
      return;
    }
    // Code produit imprimé sur l'étiquette : il doit correspondre à la ligne ouverte.
    final current = _current;
    if (label.gtin != null && current != null) {
      final queries = DataMatrixData(raw: '', format: DataMatrixFormat.ocrLabel, gtin: label.gtin).productSearchQueries;
      try {
        final found = await _find(queries);
        if (!mounted) return;
        if (found.isNotEmpty && found.every((l) => l.detailId != current.detailId)) {
          await _alert('Autre produit', 'L\'étiquette photographiée appartient à ${found.first.name}, pas à ${current.name}.',
              blocking: true);
          return;
        }
      } catch (_) {
        // Vérification impossible hors connexion : l'opérateur confirme de toute façon les valeurs.
      }
    }
    _applyLotDate(
      label.lotCandidates,
      label.expiryCandidates,
      label.lotCandidates.length == 1 ? label.lotCandidates.first : null,
      label.expiryCandidates.length == 1 ? label.expiryCandidates.first : null,
      'Photo (vérifiez avec la boîte)',
    );
  }

  Future<void> _submit() async {
    final line = _current;
    if (line == null || _busy) return;
    final qty = int.tryParse(_qty.text.trim()) ?? 0;
    final ug = int.tryParse(_ug.text.trim()) ?? 0;
    final lot = _lot.text.trim().toUpperCase();
    final dateText = _date.text.trim();
    final expiry = dateText.isEmpty ? null : parseExpiryInput(dateText);
    if (dateText.isNotEmpty && expiry == null) {
      await _alert('Date illisible', 'Format attendu : JJ/MM/AAAA ou MM/AAAA.', blocking: true);
      _dateFocus.requestFocus();
      return;
    }

    final issues = checkLotEntry(
      line: line,
      lot: lot,
      expiry: expiry,
      quantity: qty,
      freeQty: ug,
      now: _now(),
      shortExpiryMonths: widget.settings.shortExpiryMonths,
      peremptionRequired: _peremptionRequired,
    );
    final blocking = issues.where((i) => i.blocking).toList();
    if (blocking.isNotEmpty) {
      HapticFeedback.heavyImpact();
      await _alert('Saisie refusée', blocking.map((i) => i.message).join('\n'), blocking: true);
      return;
    }
    final toConfirm = issues.where((i) => !i.blocking).toList();
    if (toConfirm.isNotEmpty) {
      final short = toConfirm.any((i) => i.kind == LotIssueKind.shortExpiry);
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.warning_amber, color: Colors.orange.shade800, size: 40),
          title: const Text('À confirmer'),
          content: Text('${toConfirm.map((i) => i.message).join('\n\n')}\n\n${line.name}\nLot $lot · $qty boîte(s)'
              '${expiry == null ? '' : ' · exp. ${_fmt.format(expiry)}'}'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(short ? 'Refuser / corriger' : 'Corriger')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(short ? 'Accepter' : 'Confirmer')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy = true);
    final result = await widget.gateway.addLot(detailId: line.detailId, quantity: qty, freeQty: ug, numLot: lot, expiry: expiry);
    if (!mounted) return;
    if (!result.success) {
      setState(() => _busy = false);
      await _alert('Lot non enregistré', result.message, blocking: true);
      await _load();
      return;
    }
    HapticFeedback.lightImpact();
    widget.gateway.markChecked(line.detailId, line.entered + qty + ug);
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✓ $qty × ${line.name} — lot $lot'),
      backgroundColor: Colors.green.shade700,
      duration: const Duration(seconds: 2),
    ));
    final updated = _lines.where((l) => l.detailId == line.detailId).firstOrNull;
    if (updated != null && !updated.isComplete) {
      // Reste à saisir (autre lot du même produit) : la ligne reste ouverte.
      _openLine(updated);
    } else {
      _closeLine();
    }
  }

  Future<void> _clearLots(ReceptionLine line) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Effacer les lots de la ligne ?'),
        content: Text('${line.name}\nLots : ${line.lots.join(', ')} (${line.entered} boîte(s)).\n'
            'Les lots saisis par tous les appareils pour ce produit sur ce BL seront effacés.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Effacer')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final r = await widget.gateway.clearLots(line);
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    Constants.showSnackBar(context, r.message, isError: !r.success);
    final updated = _lines.where((l) => l.detailId == line.detailId).firstOrNull;
    if (updated != null && _current?.detailId == line.detailId) _openLine(updated);
  }

  Future<void> _alert(String title, String message, {bool blocking = false}) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: blocking ? const Icon(Icons.block, color: Colors.red, size: 40) : null,
          title: Text(title),
          content: Text(message),
          actions: [ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );

  Future<void> _finish() async {
    final validated = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ReceptionSummaryScreen(
        bl: widget.bl,
        gateway: widget.gateway,
        settings: widget.settings,
        lines: _lines,
        clock: widget.clock,
        presentation: style,
      ),
    ));
    if (!mounted) return;
    if (validated == true) {
      Navigator.of(context).pop(true);
    } else {
      _load();
    }
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final summary = ReceptionSummary.of(_lines, now: _now(), shortExpiryMonths: widget.settings.shortExpiryMonths);
    return PresentationScaffold(
      style: style,
      title: 'BL ${widget.bl.ref}',
      subtitle: widget.bl.grossiste,
      actions: (c) => [IconButton(icon: Icon(Icons.refresh, color: c), tooltip: 'Actualiser', onPressed: _load)],
      steps: StepsBar(active: 1, steps: const [
        (title: 'Commande', detail: 'BL créé', onTap: null),
        (title: 'Saisie BL', detail: 'lots, quantités', onTap: null),
        (title: 'Stock', detail: 'validation', onTap: null),
      ]),
      header: [
        // Ligne ouverte : en-tête allégé pour laisser la place à la saisie.
        if (style == ListPresentation.dashboard && _current == null) _headerFigures(summary),
        _buildProgress(summary, dark: true),
        _buildScanBar(dark: true),
      ],
      compactHeader: [_buildProgress(summary, dark: false), _buildScanBar(dark: false)],
      body: Column(children: [
        if (_loading || _busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _current != null ? _buildEntry(_current!) : _buildLines()),
      ]),
      // Action principale toujours visible : « Confirmer » pendant la saisie d'une ligne, sinon « Terminer ».
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: SizedBox(
            height: 54,
            child: _current != null && !_current!.isComplete
                ? ElevatedButton.icon(
                    style: style == ListPresentation.guided ? amberButton : navyButton,
                    icon: const Icon(Icons.check),
                    label: Text(
                      (int.tryParse(_qty.text) ?? 0) > 0 ? 'Confirmer ${int.tryParse(_qty.text)}' : 'Confirmer',
                      style: const TextStyle(fontSize: 18),
                    ),
                    onPressed: _busy ? null : _submit,
                  )
                : ElevatedButton.icon(
                    style: navyButton,
                    icon: const Icon(Icons.fact_check),
                    label: const Text('Terminer et vérifier'),
                    onPressed: _loading || _lines.isEmpty ? null : _finish,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _headerFigures(ReceptionSummary s) => Row(children: [
        Expanded(child: KpiTile('${s.complete.length}/${_lines.length}', 'lignes complètes')),
        const SizedBox(width: 8),
        Expanded(child: KpiTile('${s.enteredBoxes}/${s.orderedBoxes}', 'boîtes saisies')),
        const SizedBox(width: 8),
        Expanded(child: KpiTile('${_lines.length - s.complete.length}', 'lignes à saisir', highlight: true)),
      ]);

  Widget _buildProgress(ReceptionSummary s, {required bool dark}) {
    final total = _lines.length;
    final done = s.complete.length;
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : done / total,
            minHeight: 8,
            backgroundColor: dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFE6EBF2),
            color: dark ? Pal.amber : Pal.green,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Text('$done/$total lignes · ${s.enteredBoxes}/${s.orderedBoxes} boîtes',
          style: TextStyle(fontSize: 12, color: dark ? Colors.white : Pal.ink, fontWeight: FontWeight.w500)),
    ]);
  }

  Widget _buildScanBar({required bool dark}) {
    return TextField(
      controller: _scan,
      focusNode: _scanFocus,
      autofocus: true,
      keyboardType: _scanKeyboard ? TextInputType.text : TextInputType.none,
      decoration: InputDecoration(
        labelText: _current == null ? 'Scannez un produit du BL' : 'Scannez le DataMatrix ou un autre produit',
        floatingLabelBehavior: FloatingLabelBehavior.never,
        prefixIcon: const Icon(Icons.qr_code_scanner),
        filled: true,
        fillColor: dark ? Colors.white : Pal.page,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.photo_camera),
              tooltip: 'Scanner (caméra)',
              onPressed: _busy ? null : () => _cameraScan(),
            ),
            IconButton(
              icon: Icon(_scanKeyboard ? Icons.keyboard_hide : Icons.keyboard),
              tooltip: 'Saisir un code ou un nom',
              onPressed: () {
                setState(() => _scanKeyboard = !_scanKeyboard);
                _scanFocus.unfocus();
                Future.microtask(_scanFocus.requestFocus);
              },
            ),
          ],
        ),
      ),
      onChanged: _onScanChanged,
      onSubmitted: _submitScan,
    );
  }

  Widget _buildLines() {
    if (_loadError != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_loadError!, textAlign: TextAlign.center),
          TextButton(onPressed: _load, child: const Text('Réessayer')),
        ]),
      );
    }
    final list = switch (_filter) {
      _Filter.todo => _lines.where((l) => l.isEmpty).toList(),
      _Filter.partial => _lines.where((l) => l.isPartial).toList(),
      _Filter.done => _lines.where((l) => l.isComplete).toList(),
      _Filter.all => _lines,
    };
    String label(_Filter f) => switch (f) {
          _Filter.todo => 'À saisir (${_lines.where((l) => l.isEmpty).length})',
          _Filter.partial => 'Incomplètes (${_lines.where((l) => l.isPartial).length})',
          _Filter.done => 'Complètes (${_lines.where((l) => l.isComplete).length})',
          _Filter.all => 'Toutes',
        };
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(children: [
            for (final f in _Filter.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(label(f)), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
              ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: list.isEmpty
                ? ListView(children: const [
                    Padding(padding: EdgeInsets.all(32), child: Text('Aucune ligne dans ce filtre.', textAlign: TextAlign.center)),
                  ])
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(style == ListPresentation.compact ? 0 : 12, 6, style == ListPresentation.compact ? 0 : 12, 16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => SizedBox(height: style == ListPresentation.compact ? 0 : 8),
                    itemBuilder: (_, i) => _lineTile(list[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _lineTile(ReceptionLine l) {
    final color = l.isComplete ? Pal.green : (l.isPartial ? const Color(0xFFB45309) : const Color(0xFF6B7A90));
    final row = Row(children: [
      Icon(l.isComplete ? Icons.check_circle : (l.isPartial ? Icons.timelapse : Icons.radio_button_unchecked), color: color),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
          Text(
            [
              l.code,
              if (l.lots.isNotEmpty) 'Lot ${l.lots.join(', ')}',
              if (l.expiries.isNotEmpty) 'exp. ${l.expiries.map(_fmt.format).join(', ')}',
            ].join(' · '),
            style: const TextStyle(fontSize: 13, color: Pal.muted),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      Text('${l.entered}/${l.ordered}', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
    ]);
    if (style == ListPresentation.compact) {
      return InkWell(
        onTap: _busy ? null : () => _openLine(l),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
          child: row,
        ),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _busy ? null : () => _openLine(l),
      child: SoftCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: row),
    );
  }

  InputDecoration _field(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC5D0DE))),
      );

  Widget _buildEntry(ReceptionLine l) {
    final remainingColor = l.remaining == 0 ? Pal.green : const Color(0xFFB45309);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SoftCard(
          band: style == ListPresentation.guided ? Pal.navy : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text(l.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.ink))),
                IconButton(icon: const Icon(Icons.close), tooltip: 'Fermer', onPressed: _closeLine),
              ]),
              Text('${l.code}${l.location.isEmpty ? '' : ' · ${l.location}'}', style: const TextStyle(color: Pal.muted)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _figure('BL', '${l.ordered}')),
                const SizedBox(width: 8),
                Expanded(child: _figure('Saisi', '${l.entered}')),
                const SizedBox(width: 8),
                Expanded(child: _figure('Reste', '${l.remaining}', color: remainingColor)),
              ]),
              if (l.lots.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Déjà saisi : lot ${l.lots.join(', ')}'
                    '${l.expiries.isEmpty ? '' : ' (exp. ${l.expiries.map(_fmt.format).join(', ')})'}',
                    style: const TextStyle(color: Pal.ink)),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFB91C1C)),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Effacer les lots de la ligne'),
                    onPressed: _busy ? null : () => _clearLots(l),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (l.isComplete)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              const Icon(Icons.check_circle, color: Pal.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Ligne complète. Scannez le produit suivant.',
                    style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w600)),
              ),
            ]),
          )
        else ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  style: outlineButton,
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('DataMatrix'),
                  onPressed: _busy ? null : () => _cameraScan(dataMatrixOnly: true),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  style: outlineButton,
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Photo LOT/EXP'),
                  onPressed: _busy ? null : _photoLabel,
                ),
              ),
            ),
          ]),
          if (_source != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Icon(_source!.startsWith('Photo') ? Icons.visibility : Icons.verified,
                    size: 16, color: _source!.startsWith('Photo') ? Colors.orange.shade900 : Colors.green.shade800),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Lot et date : $_source',
                      style: TextStyle(color: _source!.startsWith('Photo') ? Colors.orange.shade900 : Colors.green.shade800, fontSize: 12)),
                ),
              ]),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _lot,
            focusNode: _lotFocus,
            textCapitalization: TextCapitalization.characters,
            decoration: _field('N° de lot'),
            onChanged: (v) => _interceptFieldScan(_lot, v),
          ),
          if (_lotChoices.isNotEmpty)
            Wrap(spacing: 6, children: [
              for (final c in _lotChoices) ActionChip(label: Text(c), onPressed: () => setState(() => _lot.text = c)),
            ]),
          const SizedBox(height: 12),
          TextField(
            controller: _date,
            focusNode: _dateFocus,
            keyboardType: TextInputType.datetime,
            decoration: _field('Péremption (JJ/MM/AAAA ou MM/AAAA)${_peremptionRequired ? ' *' : ''}'),
            onChanged: (v) => _interceptFieldScan(_date, v),
          ),
          if (_dateChoices.isNotEmpty)
            Wrap(spacing: 6, children: [
              for (final d in _dateChoices) ActionChip(label: Text(_fmt.format(d)), onPressed: () => setState(() => _date.text = _fmt.format(d))),
            ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _qty,
                focusNode: _qtyFocus,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                decoration: _field('Quantité (boîtes)'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _ug,
                keyboardType: TextInputType.number,
                decoration: _field('UG'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _figure(String label, String value, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: Pal.page, borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color ?? Pal.ink)),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF4A5A70))),
        ]),
      );
}
