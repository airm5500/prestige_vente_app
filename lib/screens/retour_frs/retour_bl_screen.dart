// lib/screens/retour_frs/retour_bl_screen.dart
// Retour fournisseur sur un BL entré en stock : scanner ou chercher le produit -> quantité -> motif ->
// produit suivant. Le retour est créé « en préparation » dans Prestige ; la sortie de stock se fait
// lors de sa validation sur Prestige par une personne habilitée.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/retour/retour_gateway.dart';
import 'package:prestige_vente_app/retour/retour_models.dart';
import 'package:prestige_vente_app/screens/common/camera_scan_screen.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_bl_screen.dart' show CodeCamera;
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RetourBlScreen extends StatefulWidget {
  final ReceptionBl bl;
  final RetourGateway gateway;
  final CodeCamera? codeCamera;

  const RetourBlScreen({super.key, required this.bl, required this.gateway, this.codeCamera});

  @override
  State<RetourBlScreen> createState() => _RetourBlScreenState();
}

class _RetourBlScreenState extends State<RetourBlScreen> {
  static const _lastMotifKey = 'retour_dernier_motif';

  List<MotifRetour> _motifs = [];
  String? _motifId;
  RetourCreated? _retour;
  List<RetourLine> _items = [];
  bool _busy = false;
  String? _error;

  final _scan = TextEditingController();
  final _scanFocus = FocusNode();
  bool _scanKeyboard = false;
  Timer? _scanDebounce;

  ReceptionLine? _current;
  final _qty = TextEditingController(text: '1');
  final _qtyFocus = FocusNode();
  final _comment = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMotifs();
  }

  @override
  void dispose() {
    _scanDebounce?.cancel();
    for (final c in [_scan, _qty, _comment]) {
      c.dispose();
    }
    _scanFocus.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  Future<void> _loadMotifs() async {
    try {
      final motifs = await widget.gateway.motifs();
      String? last;
      try {
        last = (await SharedPreferences.getInstance()).getString(_lastMotifKey);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _motifs = motifs;
        _motifId = motifs.any((m) => m.id == last) ? last : null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Motifs de retour non chargés. Vérifiez la connexion.');
    }
  }

  int _alreadyInReturn(String produitId) =>
      _items.where((i) => i.produitId == produitId).fold(0, (s, i) => s + i.quantity);

  // ---------------------------------------------------------------------------
  // Recherche du produit dans le BL
  // ---------------------------------------------------------------------------
  void _onScanChanged(String v) {
    _scanDebounce?.cancel();
    if (_scanKeyboard || v.trim().isEmpty) return;
    _scanDebounce = Timer(const Duration(milliseconds: 350), () => _submitScan(_scan.text));
  }

  void _submitScan(String v) {
    _scanDebounce?.cancel();
    _scan.clear();
    if (v.trim().isNotEmpty) _find(v);
  }

  Future<void> _camera() async {
    final camera = widget.codeCamera ??
        (BuildContext ctx, {bool dataMatrixOnly = false}) => CameraScanScreen.open(ctx, title: 'Scanner le produit à retourner');
    final value = await camera(context);
    if (value != null && mounted) await _find(value);
  }

  Future<void> _find(String raw) async {
    if (_busy) return;
    final (:queries, dataMatrix: _) = scanQueries(raw);
    if (queries.isEmpty) return;
    setState(() => _busy = true);
    List<ReceptionLine> found = const [];
    try {
      for (final q in queries) {
        found = await widget.gateway.blLines(widget.bl.id, query: q);
        if (found.isNotEmpty) break;
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _alert('Serveur injoignable', 'Le produit n\'a pas pu être recherché.');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (found.isEmpty) {
      HapticFeedback.heavyImpact();
      await _alert('Produit absent de ce BL', '« ${raw.trim()} » ne correspond à aucun produit du BL ${widget.bl.ref}.');
      _scanFocus.requestFocus();
      return;
    }
    final line = found.length == 1
        ? found.single
        : await showDialog<ReceptionLine>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('Choisissez le produit'),
              children: [
                for (final l in found)
                  SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop(l), child: Text('${l.name}\n${l.code}')),
              ],
            ),
          );
    if (line == null || !mounted) return;
    setState(() {
      _current = line;
      _qty.text = '1';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _qtyFocus.requestFocus();
      _qty.selection = TextSelection(baseOffset: 0, extentOffset: _qty.text.length);
    });
  }

  // ---------------------------------------------------------------------------
  // Ajout au retour
  // ---------------------------------------------------------------------------
  Future<void> _add() async {
    final line = _current;
    if (line == null || _busy) return;
    final qty = int.tryParse(_qty.text.trim()) ?? 0;
    final problem = checkReturnQuantity(line: line, alreadyInReturn: _alreadyInReturn(line.produitId), quantity: qty);
    if (problem != null) {
      HapticFeedback.heavyImpact();
      await _alert('Quantité refusée', problem);
      return;
    }
    final motifId = _motifId;
    if (motifId == null) {
      await _alert('Motif obligatoire', 'Choisissez le motif du retour.');
      return;
    }
    final existing = _items.where((i) => i.produitId == line.produitId).firstOrNull;
    final motif = _motifs.where((m) => m.id == motifId).firstOrNull;
    if (existing != null && motif != null && existing.motif.isNotEmpty && existing.motif != motif.label) {
      // Prestige garde un seul motif par produit : on prévient avant de cumuler.
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Produit déjà dans le retour'),
          content: Text('${line.name} est déjà retourné (${existing.quantity}, motif « ${existing.motif} »).\n'
              'La quantité sera ajoutée avec le motif « ${existing.motif} ».'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Ajouter')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy = true);
    String message;
    bool success;
    if (_retour == null) {
      final r = await widget.gateway.create(
        blRef: widget.bl.ref,
        produitId: line.produitId,
        motifId: motifId,
        quantity: qty,
        comment: _comment.text.trim(),
      );
      success = r.success;
      message = r.message;
      if (r.retour != null) _retour = r.retour;
    } else {
      final r = await widget.gateway.addItem(retourId: _retour!.id, produitId: line.produitId, motifId: motifId, quantity: qty);
      success = r.success;
      message = r.message;
    }
    if (!mounted) return;
    if (!success) {
      setState(() => _busy = false);
      await _alert('Produit non ajouté', message);
      return;
    }
    try {
      (await SharedPreferences.getInstance()).setString(_lastMotifKey, motifId);
    } catch (_) {}
    await _reloadItems();
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() {
      _busy = false;
      _current = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✓ $qty × ${line.name} — ${motif?.label ?? ''}'),
      backgroundColor: Colors.green.shade700,
      duration: const Duration(seconds: 2),
    ));
    _scanFocus.requestFocus();
  }

  Future<void> _reloadItems() async {
    final r = _retour;
    if (r == null) return;
    try {
      final items = await widget.gateway.items(r.id);
      if (mounted) setState(() => _items = items);
    } catch (_) {}
  }

  Future<void> _editItem(RetourLine item) async {
    final result = await showDialog<({String action, int qty})>(
      context: context,
      builder: (_) => _EditQuantityDialog(item: item),
    );
    if (result == null || !mounted) return;
    final action = result.action;
    final qty = result.qty;
    setState(() => _busy = true);
    if (action == 'delete' || qty <= 0) {
      final ok = await widget.gateway.removeItem(item.id);
      if (mounted && !ok) Constants.showSnackBar(context, 'Ligne non retirée.', isError: true);
    } else {
      final r = await widget.gateway.updateItem(item.id, qty);
      if (mounted && !r.success) await _alert('Quantité refusée', r.message);
    }
    await _reloadItems();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _finish() async {
    final r = _retour;
    if (r == null) {
      Navigator.of(context).pop();
      return;
    }
    final total = _items.fold(0, (s, i) => s + i.quantity);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.assignment_return, color: Colors.green.shade700, size: 40),
        title: const Text('Retour en préparation'),
        content: Text('Retour ${r.ref} — BL ${widget.bl.ref} (${widget.bl.grossiste})\n'
            '${_items.length} produit(s), $total boîte(s).\n\n'
            'Il sera validé sur Prestige par une personne habilitée : le stock ne diminue qu\'à ce moment-là.'),
        actions: [ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _alert(String title, String message) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.block, color: Colors.red, size: 40),
          title: Text(title),
          content: Text(message),
          actions: [ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final total = _items.fold(0, (s, i) => s + i.quantity);
    return PopScope(
      canPop: _retour == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_retour == null ? 'Retour — BL ${widget.bl.ref}' : 'Retour ${_retour!.ref} — BL ${widget.bl.ref}'),
            Text(widget.bl.grossiste, style: const TextStyle(fontSize: 12)),
          ]),
        ),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: Colors.red.shade700))),
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: _scan,
                focusNode: _scanFocus,
                autofocus: true,
                keyboardType: _scanKeyboard ? TextInputType.text : TextInputType.none,
                decoration: InputDecoration(
                  labelText: 'Scannez ou cherchez (CIP, nom) le produit',
                  prefixIcon: const Icon(Icons.qr_code_scanner),
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.photo_camera), tooltip: 'Scanner (caméra)', onPressed: _busy ? null : _camera),
                    IconButton(
                      icon: Icon(_scanKeyboard ? Icons.keyboard_hide : Icons.keyboard),
                      tooltip: 'Chercher au clavier',
                      onPressed: () {
                        setState(() => _scanKeyboard = !_scanKeyboard);
                        _scanFocus.unfocus();
                        Future.microtask(_scanFocus.requestFocus);
                      },
                    ),
                  ]),
                ),
                onChanged: _onScanChanged,
                onSubmitted: _submitScan,
              ),
            ),
            if (_retour == null && _current == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextField(
                  controller: _comment,
                  maxLength: 50,
                  decoration: const InputDecoration(labelText: 'Commentaire du retour (facultatif)', isDense: true),
                ),
              ),
            Expanded(child: _current != null ? _buildProduct(_current!) : _buildItems()),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.assignment_turned_in),
              label: Text(_retour == null ? 'Fermer' : 'Terminer : retour en préparation ($total)'),
              onPressed: _busy ? null : _finish,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProduct(ReceptionLine l) {
    final already = _alreadyInReturn(l.produitId);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: Colors.blueGrey.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(l.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Fermer',
                  onPressed: () {
                    setState(() => _current = null);
                    _scanFocus.requestFocus();
                  },
                ),
              ]),
              Text(l.code),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _figure('Reçu (BL)', '${l.received}'),
                _figure('En stock', '${l.stock}'),
                _figure('Dans ce retour', '$already'),
              ]),
              if (l.lots.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Lot(s) reçu(s) : ${l.lots.join(', ')}')),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _qty,
          focusNode: _qtyFocus,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(labelText: 'Quantité à retourner', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        const Text('Motif', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (_motifs.isEmpty) const Text('Aucun motif chargé.'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in _motifs)
            ChoiceChip(
              label: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(m.label)),
              selected: _motifId == m.id,
              onSelected: (_) => setState(() => _motifId = m.id),
            ),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Ajouter au retour', style: TextStyle(fontSize: 18)),
            onPressed: _busy ? null : _add,
          ),
        ),
      ],
    );
  }

  Widget _buildItems() {
    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Scannez le premier produit à retourner.\nLe retour est créé dans Prestige au premier ajout.', textAlign: TextAlign.center),
        ),
      );
    }
    return ListView(
      children: [
        for (final i in _items)
          Card(
            child: ListTile(
              title: Text(i.name),
              subtitle: Text('${i.cip} · ${i.motif}'),
              trailing: Text('${i.quantity}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              onTap: _busy ? null : () => _editItem(i),
            ),
          ),
      ],
    );
  }

  Widget _figure(String label, String value) => Column(children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);
}

/// Modification de la quantité d'une ligne du retour (le champ vit avec la fenêtre).
class _EditQuantityDialog extends StatefulWidget {
  final RetourLine item;
  const _EditQuantityDialog({required this.item});

  @override
  State<_EditQuantityDialog> createState() => _EditQuantityDialogState();
}

class _EditQuantityDialogState extends State<_EditQuantityDialog> {
  late final _qty = TextEditingController(text: '${widget.item.quantity}');

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  void _close(String action) => Navigator.of(context).pop((action: action, qty: int.tryParse(_qty.text.trim()) ?? 0));

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.item.name),
        content: TextField(
          controller: _qty,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Quantité à retourner'),
        ),
        actions: [
          TextButton(onPressed: () => _close('delete'), child: const Text('Retirer du retour')),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => _close('save'), child: const Text('Enregistrer')),
        ],
      );
}
