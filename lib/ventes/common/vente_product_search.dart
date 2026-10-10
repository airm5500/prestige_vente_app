// lib/ventes/common/vente_product_search.dart
// Recherche / scan produit commun aux ventes : douchette (clavier) ou saisie, délai de frappe,
// mode scan rapide mémorisé, recherche à partir de 3 caractères (indiqué), panne ≠ introuvable,
// scans à la suite mis en file (aucun scan perdu), « scan répété » → fenêtre de quantité.
import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/ventes/common/product_list_modal.dart';
import 'package:prestige_vente_app/ventes/common/quantity_dialog.dart';
import 'package:prestige_vente_app/ventes/common/vente_dialogs.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mode scan rapide mémorisé sur l'appareil (même clé que l'ancienne version).
class QuickScanPrefs {
  QuickScanPrefs._();
  static const key = 'isQuickScanMode';

  static Future<bool> load() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> save(bool value) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(key, value);
    } catch (_) {}
  }
}

/// Barre de recherche/scan ; [addProduct] ajoute au panier et renvoie true si le serveur a confirmé.
class VenteProductSearch extends StatefulWidget {
  final Future<VenteResult<List<ProductSearchResult>>> Function(String query) search;
  final Future<bool> Function(ProductSearchResult product, int qty) addProduct;

  /// false : saisie bloquée (ex. encaissement en cours).
  final bool enabled;

  /// Délai de frappe avant la recherche en saisie manuelle.
  final Duration debounce;

  const VenteProductSearch({
    super.key,
    required this.search,
    required this.addProduct,
    this.enabled = true,
    this.debounce = const Duration(milliseconds: 500),
  });

  @override
  State<VenteProductSearch> createState() => VenteProductSearchState();
}

class VenteProductSearchState extends State<VenteProductSearch> {
  final _ctrl = TextEditingController();
  final _fieldFocus = FocusNode();
  final _keyFocus = FocusNode();
  final Queue<String> _pendingScans = Queue<String>();
  Timer? _debounce;
  String _scanBuffer = '';
  bool _quick = false;
  bool _searching = false;
  bool _loading = false; // attente de la réponse du serveur (indicateur)
  bool _popupOpen = false;
  bool _draining = false;
  String? _hint;

  // Scan répété du même produit
  String? _lastCip;
  int _repeat = 0;

  bool get quickScan => _quick;
  bool get popupOpen => _popupOpen;

  @override
  void initState() {
    super.initState();
    QuickScanPrefs.load().then((v) {
      if (mounted) setState(() => _quick = v);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _fieldFocus.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  /// Remet le curseur dans le champ de recherche (si aucune fenêtre ouverte).
  void requestFocus() {
    if (mounted && !_popupOpen && widget.enabled) _fieldFocus.requestFocus();
  }

  Future<void> _toggleQuick() async {
    setState(() {
      _quick = !_quick;
      _hint = null;
    });
    await QuickScanPrefs.save(_quick);
    requestFocus();
  }

  void _resetRepeat() {
    _lastCip = null;
    _repeat = 0;
  }

  // --- Douchette : caractères reçus hors du champ, validés par Entrée ---
  void _onKey(KeyEvent event) {
    if (!_quick || _popupOpen || !widget.enabled) return;
    if (_fieldFocus.hasFocus && _ctrl.text.isNotEmpty) {
      _scanBuffer = '';
      return;
    }
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_scanBuffer.isNotEmpty) {
          final code = _scanBuffer;
          _scanBuffer = '';
          _submit(code, scan: true);
        }
      } else if (event.character != null) {
        _scanBuffer += event.character!;
      }
    }
  }

  void _onChanged(String val) {
    if (_quick) return;
    _debounce?.cancel();
    final q = VenteInput.cleanQuery(val);
    if (q.isEmpty) {
      _resetRepeat();
      setState(() => _hint = null);
      return;
    }
    if (q.length < VenteInput.minQueryLength) {
      setState(() => _hint = 'Saisissez au moins ${VenteInput.minQueryLength} caractères');
      return;
    }
    if (_hint != null) setState(() => _hint = null);
    _debounce = Timer(widget.debounce, () {
      if (mounted && !_popupOpen) _submit(q, scan: false);
    });
  }

  /// Lance une recherche ; en scan, les codes reçus pendant une recherche attendent leur tour.
  void _submit(String raw, {required bool scan}) {
    _debounce?.cancel();
    final q = VenteInput.cleanQuery(raw);
    if (q.isEmpty || !widget.enabled) return;
    if (scan) {
      if (_popupOpen) return;
      _ctrl.clear(); // le code suivant de la douchette ne s'ajoute pas à celui-ci
      _pendingScans.add(q);
      if (!_draining && !_searching) _drainScans();
      return;
    }
    if (_searching || _popupOpen) return;
    _search(q, scan: false);
  }

  Future<void> _drainScans() async {
    _draining = true;
    try {
      while (_pendingScans.isNotEmpty && mounted && !_popupOpen) {
        await _search(_pendingScans.removeFirst(), scan: true);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _search(String q, {required bool scan}) async {
    if (q.length < VenteInput.minQueryLength) {
      if (scan) _ctrl.clear();
      setState(() => _hint = 'Saisissez au moins ${VenteInput.minQueryLength} caractères');
      return;
    }
    setState(() {
      _searching = true;
      _loading = true;
      _hint = null;
    });
    try {
      final r = await widget.search(q);
      if (!mounted) return;
      setState(() => _loading = false);
      switch (r) {
        case VenteOk(:final value):
          await _handleResults(q, value, scan: scan);
        default:
          // Panne ou refus : jamais « introuvable ».
          if (scan) _ctrl.clear();
          showVenteSnack(context, 'Recherche impossible : ${venteMessage(r.message)}',
              error: true, onRetry: () => _submit(q, scan: scan));
      }
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
          _loading = false;
        });
        requestFocus();
        if (!_draining && _pendingScans.isNotEmpty) scheduleMicrotask(_drainScans);
      }
    }
  }

  Future<void> _handleResults(String q, List<ProductSearchResult> results, {required bool scan}) async {
    if (results.isEmpty) {
      if (scan) {
        _ctrl.clear();
        showVenteSnack(context, 'Produit introuvable ($q)', color: Colors.orange.shade800);
      } else {
        setState(() => _hint = 'Aucun produit trouvé pour « $q »');
      }
      return;
    }
    if (results.length == 1) {
      final p = results.first;
      _ctrl.clear();
      if (scan) {
        if (_lastCip == p.intCIP.toString()) {
          _repeat++;
          if (_repeat >= 3) {
            await _repeatedScan(p);
            return;
          }
        } else {
          _lastCip = p.intCIP.toString();
          _repeat = 1;
        }
        await _addOne(p);
      } else {
        _resetRepeat();
        await _askQuantity(p);
      }
      return;
    }
    final chosen = await _popup(() => showProductListModal(context, results, initialQuery: q));
    if (!mounted || chosen == null) return;
    _ctrl.clear();
    _resetRepeat();
    await _askQuantity(chosen);
  }

  Future<T?> _popup<T>(Future<T?> Function() open) async {
    setState(() => _popupOpen = true);
    try {
      return await open();
    } finally {
      if (mounted) setState(() => _popupOpen = false);
    }
  }

  /// Scan simple : +1 (stock vide → « forcer ? »). L'ajout n'est pas attendu : les scans suivants continuent.
  Future<void> _addOne(ProductSearchResult p) async {
    if (p.intNUMBERAVAILABLE <= 0) {
      final force = await _popup(() => showForceStockDialog(context, stock: p.intNUMBERAVAILABLE, qty: 1));
      if (force != true || !mounted) return;
    }
    unawaited(_add(p, 1, announce: true));
  }

  /// 3ᵉ scan du même produit : « Combien en reste-t-il ? ». Annuler n'ajoute rien.
  Future<void> _repeatedScan(ProductSearchResult p) async {
    final qty = await _popup(() => showDialog<int>(
          context: context,
          barrierDismissible: false,
          builder: (_) => QuantityDialog(product: p, isSmartMode: true),
        ));
    if (!mounted) return;
    if (qty == null) {
      showVenteSnack(context, 'Rien ajouté pour ${p.strNAME}.');
      return;
    }
    if (qty > 1) _resetRepeat();
    await _checkStockAndAdd(p, qty);
  }

  Future<void> _askQuantity(ProductSearchResult p) async {
    final qty = await _popup(() => showDialog<int>(context: context, barrierDismissible: false, builder: (_) => QuantityDialog(product: p)));
    if (!mounted || qty == null) return;
    await _checkStockAndAdd(p, qty);
  }

  Future<void> _checkStockAndAdd(ProductSearchResult p, int qty) async {
    if (qty > p.intNUMBERAVAILABLE) {
      final force = await _popup(() => showForceStockDialog(context, stock: p.intNUMBERAVAILABLE, qty: qty));
      if (force != true || !mounted) return;
    }
    await _add(p, qty, announce: false);
  }

  Future<void> _add(ProductSearchResult p, int qty, {required bool announce}) async {
    final ok = await widget.addProduct(p, qty);
    if (ok && announce && mounted) {
      showVenteSnack(context, '${p.strNAME} ajouté (+$qty)', color: Colors.green.shade700);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _quick;
    return KeyboardListener(
      focusNode: _keyFocus,
      onKeyEvent: _onKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('vente-recherche'),
                controller: _ctrl,
                focusNode: _fieldFocus,
                enabled: widget.enabled,
                onChanged: _onChanged,
                inputFormatters: VenteInput.queryFormatters,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) => _submit(v, scan: active),
                decoration: InputDecoration(
                  hintText: active ? 'SCAN RAPIDE ACTIF' : 'Rechercher (nom / CIP, 3 car. min.)',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  prefixIcon: _loading
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                      : Icon(active ? Icons.bolt : Icons.search, color: active ? Colors.green : null),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Effacer',
                    onPressed: () {
                      _ctrl.clear();
                      _resetRepeat();
                      setState(() => _hint = null);
                      requestFocus();
                    },
                  ),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: active ? Colors.green : Colors.grey, width: active ? 2.5 : 1)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: active ? Colors.green : Theme.of(context).primaryColor, width: active ? 2.5 : 2)),
                  filled: true,
                  fillColor: active ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.05),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: active ? 'Désactiver le scan rapide' : 'Activer le scan rapide',
              child: OutlinedButton.icon(
                key: const ValueKey('vente-scan-rapide'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  backgroundColor: active ? Colors.green : Colors.grey.shade200,
                  foregroundColor: active ? Colors.white : Colors.grey.shade800,
                  side: BorderSide(color: active ? Colors.green.shade700 : Colors.grey),
                ),
                onPressed: _toggleQuick,
                icon: Icon(active ? Icons.flash_on : Icons.flash_off, size: 20),
                label: const Text('Scan\nrapide', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, height: 1.1)),
              ),
            ),
          ]),
          if (_hint != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Text(_hint!, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ),
        ]),
      ),
    );
  }
}
