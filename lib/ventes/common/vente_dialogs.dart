// lib/ventes/common/vente_dialogs.dart
// Dialogues communs des ventes (Pré-vente, Assurance, Carnet) : génériques, sans provider.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/common/quantity_dialog.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';

const Size _btn = Size(88, 44);

/// Stock insuffisant : « Forcer l'ajout de [qty] ? » (true = forcer).
Future<bool> showForceStockDialog(BuildContext context, {required int stock, required int qty}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Stock insuffisant', style: TextStyle(color: Colors.red)),
      content: Text('Stock dispo : $stock.\nForcer l\'ajout de $qty ?'),
      actions: [
        TextButton(style: TextButton.styleFrom(minimumSize: _btn), child: const Text('Non'), onPressed: () => Navigator.pop(ctx, false)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, minimumSize: _btn),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Forcer'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Modification d'une ligne du panier : quantité (1-9 999) et prix (libre, 0-999 999 999, 0 confirmé).
/// Renvoie null si annulé ou inchangé.
Future<({int qty, int price})?> showEditLineDialog(BuildContext context,
    {required String name, required int qty, required int price, bool priceEditable = true}) {
  return showDialog<({int qty, int price})>(
    context: context,
    builder: (_) => _EditLineDialog(name: name, qty: qty, price: price, priceEditable: priceEditable),
  );
}

class _EditLineDialog extends StatefulWidget {
  final String name;
  final int qty;
  final int price;
  final bool priceEditable;
  const _EditLineDialog({required this.name, required this.qty, required this.price, required this.priceEditable});

  @override
  State<_EditLineDialog> createState() => _EditLineDialogState();
}

class _EditLineDialogState extends State<_EditLineDialog> {
  final _form = GlobalKey<FormState>();
  late final _qte = TextEditingController(text: '${widget.qty}');
  late final _price = TextEditingController(text: '${widget.price}');
  bool _busy = false;

  @override
  void dispose() {
    _qte.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final q = VenteInput.parseQuantity(_qte.text);
    final p = widget.priceEditable ? VenteInput.parsePrice(_price.text) : widget.price;
    if (q == null || p == null) return;
    if (q == widget.qty && p == widget.price) {
      Navigator.of(context).pop();
      return;
    }
    _busy = true;
    if (q > VenteInput.confirmQuantityAbove && q != widget.qty) {
      final ok = await confirmLargeQuantity(context, q);
      if (!mounted) return;
      if (!ok) {
        _busy = false;
        return;
      }
    }
    if (p == 0 && widget.price != 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Prix à 0 F'),
          content: Text('Vendre « ${widget.name} » gratuitement (0 F) ?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Non')),
            ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Oui, 0 F')),
          ],
        ),
      );
      if (!mounted) return;
      if (ok != true) {
        _busy = false;
        return;
      }
    }
    Navigator.of(context).pop((qty: q, price: p));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _qte,
              decoration: const InputDecoration(labelText: 'Quantité (1 à ${VenteInput.maxQuantity})'),
              keyboardType: TextInputType.number,
              inputFormatters: VenteInput.quantityFormatters,
              validator: VenteInput.quantityError,
              autofocus: true,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _price,
              enabled: widget.priceEditable,
              decoration: const InputDecoration(labelText: 'Prix unitaire (F)'),
              keyboardType: TextInputType.number,
              inputFormatters: VenteInput.priceFormatters,
              validator: widget.priceEditable ? VenteInput.priceError : null,
              onFieldSubmitted: (_) => _submit(),
            ),
          ]),
        ),
        actions: [
          TextButton(style: TextButton.styleFrom(minimumSize: _btn), onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: _btn), onPressed: _submit, child: const Text('Valider')),
        ],
      );
}

/// Confirmation avant de retirer [name] du panier.
Future<bool> confirmDeleteLine(BuildContext context, String name) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Supprimer ?'),
      content: Text('Retirer $name du panier ?'),
      actions: [
        TextButton(style: TextButton.styleFrom(minimumSize: _btn), onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, minimumSize: _btn),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Choix du mode de règlement ; liste vide → message clair (activer des modes dans Réglages).
Future<PaymentMethod?> showPaymentMethodPicker(BuildContext context, List<PaymentMethod> methods) {
  return showDialog<PaymentMethod>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Mode de règlement'),
      content: methods.isEmpty
          ? const Text(
              'Aucun mode de règlement n\'est activé sur cet appareil.\n\n'
              'Activez-en au moins un dans Réglages › Modes de paiement, puis réessayez.',
            )
          : SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: methods.length,
                itemBuilder: (_, i) => ListTile(
                  minTileHeight: 48,
                  leading: Icon(methods[i].id == '1' ? Icons.payments_outlined : Icons.account_balance_wallet_outlined),
                  title: Text(methods[i].name),
                  onTap: () => Navigator.of(ctx).pop(methods[i]),
                ),
              ),
            ),
      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(methods.isEmpty ? 'Fermer' : 'Annuler'))],
    ),
  );
}

/// Confirmation de paiement : mode, montant net et QR éventuel (true = VALIDER).
Future<bool> showPaymentConfirmDialog(BuildContext context, {required String methodName, required int montantNet, Uint8List? qrCode}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirmation de paiement'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Mode : $methodName', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Montant net : ${Constants.formatNumber(montantNet)} F',
              style: const TextStyle(fontSize: 18, color: Colors.blue, fontWeight: FontWeight.bold)),
          const Divider(height: 30),
          if (qrCode != null) ...[
            const Text('Scanner pour payer :'),
            const SizedBox(height: 10),
            SizedBox(width: 180, height: 180, child: Image.memory(qrCode, fit: BoxFit.contain)),
          ] else
            const Text('Veuillez confirmer l\'encaissement.'),
        ]),
      ),
      actions: [
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.of(ctx).pop(false),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('RETOUR'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.check_circle, size: 18),
              label: const Text('VALIDER'),
            ),
          ),
        ]),
      ],
    ),
  );
  return ok == true;
}

/// Paiement en espèces : montant versé, monnaie rendue. Renvoie (verse, monnaie) ou null.
Future<({int verse, int monnaie})?> showCashDialog(BuildContext context, {required int montantNet}) =>
    showDialog<({int verse, int monnaie})>(context: context, builder: (_) => VenteCashDialog(montantNet: montantNet));

/// Espèces : même règle qu'aujourd'hui (montant ≥ net, monnaie > 500 000 F refusée : erreur de scan).
class VenteCashDialog extends StatefulWidget {
  final int montantNet;
  const VenteCashDialog({super.key, required this.montantNet});

  @override
  State<VenteCashDialog> createState() => _VenteCashDialogState();
}

class _VenteCashDialogState extends State<VenteCashDialog> {
  final _ctrl = TextEditingController();
  int _monnaie = 0;
  bool _ok = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _changed(String text) {
    final v = int.tryParse(text.trim());
    setState(() {
      _monnaie = 0;
      _ok = false;
      _error = null;
      if (text.trim().isEmpty) return;
      if (v == null) {
        _error = 'Valeur invalide';
      } else if (v - widget.montantNet > 500000) {
        _error = 'Montant aberrant (erreur de scan ?)';
        _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
      } else if (v >= widget.montantNet) {
        _monnaie = v - widget.montantNet;
        _ok = true;
      }
    });
  }

  void _submit() {
    if (!_ok) return;
    Navigator.of(context).pop((verse: int.tryParse(_ctrl.text.trim()) ?? 0, monnaie: _monnaie));
  }

  Widget _quick(String label, int value) => OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 10)),
        onPressed: () {
          _ctrl.text = '$value';
          _changed(_ctrl.text);
        },
        child: Text(label),
      );

  @override
  Widget build(BuildContext context) {
    final net = widget.montantNet;
    final rounded = <int>{for (final step in [1000, 5000, 10000]) ((net + step - 1) ~/ step) * step}.where((v) => v > net).take(2);
    return AlertDialog(
      title: const Text('Paiement en espèces'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Net à payer : ${Constants.formatNumber(net)} F',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Montant versé *', prefixIcon: const Icon(Icons.money), errorText: _error),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            textInputAction: TextInputAction.done,
            onChanged: _changed,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _quick('Exact', net),
            for (final v in rounded) _quick(Constants.formatNumber(v), v),
          ]),
          const SizedBox(height: 12),
          Text(
            'Monnaie à rendre : ${Constants.formatNumber(_monnaie)} F',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _ok ? Colors.red.shade700 : Colors.grey),
          ),
        ]),
      ),
      actions: [
        TextButton(style: TextButton.styleFrom(minimumSize: _btn), onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: _btn), onPressed: _ok ? _submit : null, child: const Text('Valider')),
      ],
    );
  }
}

/// « Reprendre la vente ? » (true = Reprendre, false = Plus tard).
Future<bool> showResumeSaleDialog(BuildContext context, {required String reference, required int itemCount, required int total, DateTime? savedAt}) async {
  final when = savedAt == null ? '' : ' (${DateFormat('dd/MM/yyyy HH:mm').format(savedAt)})';
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Reprendre la vente ?'),
      content: Text(
        'Une vente n\'a pas été terminée$when :\n'
        '${reference.isEmpty ? 'Vente en cours' : 'Réf. $reference'} · $itemCount article${itemCount > 1 ? 's' : ''}'
        '${total > 0 ? ' · ${Constants.formatNumber(total)} F' : ''}',
      ),
      actions: [
        TextButton(style: TextButton.styleFrom(minimumSize: _btn), onPressed: () => Navigator.pop(ctx, false), child: const Text('Plus tard')),
        ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: _btn), onPressed: () => Navigator.pop(ctx, true), child: const Text('Reprendre')),
      ],
    ),
  );
  return ok == true;
}

/// Confirmation générique à deux boutons libellés (true = [confirm]).
Future<bool> confirmVenteAction(BuildContext context,
    {required String title, required String message, required String confirm, String cancel = 'Annuler', bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(style: TextButton.styleFrom(minimumSize: _btn), onPressed: () => Navigator.pop(ctx, false), child: Text(cancel)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: _btn,
            backgroundColor: danger ? Colors.red : null,
            foregroundColor: danger ? Colors.white : null,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok == true;
}
