// lib/screens/reception_bl/reception_home_screen.dart
// Réception BL : bons à entrer en stock, et commandes (en cours / passées) à transformer en BL.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/screens/reception_bl/reception_bl_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:provider/provider.dart';

class ReceptionHomeScreen extends StatefulWidget {
  /// Remplaçables pour les tests.
  final ReceptionGateway? gateway;
  final ReceptionSettings? settings;
  final Future<bool> Function(BuildContext)? adminCheck;
  final CodeCamera? codeCamera;
  final LabelCamera? labelCamera;
  final DateTime Function()? clock;

  const ReceptionHomeScreen({
    super.key,
    this.gateway,
    this.settings,
    this.adminCheck,
    this.codeCamera,
    this.labelCamera,
    this.clock,
  });

  @override
  State<ReceptionHomeScreen> createState() => _ReceptionHomeScreenState();
}

class _ReceptionHomeScreenState extends State<ReceptionHomeScreen> {
  static final _money = NumberFormat.decimalPattern('fr_FR');

  late final ReceptionGateway _gateway =
      widget.gateway ?? DioReceptionGateway(DioClient.getClient(context.read<SettingsProvider>().baseUrl));
  ReceptionSettings _settings = const ReceptionSettings();
  List<ReceptionBl> _bls = [];
  List<ReceptionOrder> _orders = [];
  bool _loading = true;
  String? _error;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _settings = widget.settings ?? await ReceptionSettings.load();
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bls = await _gateway.bls();
      final orders = await _gateway.orders();
      if (!mounted) return;
      setState(() {
        _bls = bls;
        _orders = orders;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Liste non chargée. Vérifiez la connexion au serveur.';
        });
      }
    }
  }

  bool _match(String s) => _filter.isEmpty || s.toLowerCase().contains(_filter.toLowerCase());

  Future<void> _openBl(ReceptionBl bl) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReceptionBlScreen(
        bl: bl,
        gateway: _gateway,
        settings: _settings,
        codeCamera: widget.codeCamera,
        labelCamera: widget.labelCamera,
        clock: widget.clock,
      ),
    ));
    if (mounted) _load();
  }

  Future<void> _createBl(ReceptionOrder order) async {
    final input = await showDialog<({String ref, DateTime date, int ht, int tva})>(
      context: context,
      builder: (_) => _CreateBlDialog(order: order, today: (widget.clock ?? DateTime.now)()),
    );
    if (input == null || !mounted) return;
    setState(() => _loading = true);
    final r = await _gateway.createBl(orderId: order.id, ref: input.ref, date: input.date, amountHt: input.ht, tva: input.tva);
    if (!mounted) return;
    setState(() => _loading = false);
    if (!r.success) {
      await _info('BL non créé', r.message, error: true);
      return;
    }
    final missing = (r.data['data'] is List) ? (r.data['data'] as List).map((e) => '$e').toList() : const <String>[];
    if (missing.isNotEmpty) {
      await _info(
        'BL créé avec réserves',
        '${missing.length} produit(s) sans stock à votre emplacement n\'ont pas été repris dans le BL :\n${missing.join(', ')}',
      );
    }
    await _load();
    if (!mounted) return;
    final created = _bls.where((b) => b.ref == input.ref).firstOrNull;
    if (created != null) {
      await _openBl(created);
    } else {
      Constants.showSnackBar(context, 'BL ${input.ref} créé.');
    }
  }

  Future<void> _info(String title, String message, {bool error = false}) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: error ? const Icon(Icons.error_outline, color: Colors.red, size: 40) : null,
          title: Text(title),
          content: Text(message),
          actions: [ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );

  Future<void> _editSettings() async {
    if (!await (widget.adminCheck ?? PinCodeDialog.show)(context) || !mounted) return;
    var draft = _settings;
    final saved = await showDialog<ReceptionSettings>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Réglages de la réception'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Péremption courte en dessous de :'),
              Wrap(spacing: 6, children: [
                for (final m in const [3, 6, 9, 12])
                  ChoiceChip(
                    label: Text('$m mois'),
                    selected: draft.shortExpiryMonths == m,
                    onSelected: (_) => setLocal(() => draft = draft.copyWith(shortExpiryMonths: m)),
                  ),
              ]),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Valider l\'entrée en stock sur ce terminal'),
                subtitle: const Text('Le droit « Entrée en stock » de l\'utilisateur est aussi vérifié par Prestige.'),
                value: draft.terminalValidation,
                onChanged: (v) => setLocal(() => draft = draft.copyWith(terminalValidation: v)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(draft), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (saved == null) return;
    if (widget.settings == null) await saved.save();
    if (mounted) setState(() => _settings = saved);
  }

  @override
  Widget build(BuildContext context) {
    final bls = _bls.where((b) => _match('${b.ref} ${b.grossiste} ${b.orderRef}')).toList();
    final orders = _orders.where((o) => _match('${o.ref} ${o.grossiste}')).toList();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Réception BL'),
          actions: [
            IconButton(icon: const Icon(Icons.tune), tooltip: 'Réglages', onPressed: _editSettings),
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Actualiser', onPressed: _load),
          ],
          bottom: TabBar(tabs: [
            Tab(text: 'BL à entrer (${_bls.length})'),
            Tab(text: 'Commandes (${_orders.length})'),
          ]),
        ),
        body: Column(
          children: [
            if (_loading) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'N° de BL, commande ou grossiste',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _filter = v.trim()),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text(_error!, textAlign: TextAlign.center),
                  TextButton(onPressed: _load, child: const Text('Réessayer')),
                ]),
              ),
            Expanded(
              child: TabBarView(children: [
                RefreshIndicator(
                  onRefresh: _load,
                  child: bls.isEmpty && !_loading
                      ? ListView(children: const [
                          Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Aucun BL à entrer en stock.\nCréez-le depuis l\'onglet « Commandes ».', textAlign: TextAlign.center),
                          ),
                        ])
                      : ListView.builder(itemCount: bls.length, itemBuilder: (_, i) => _blTile(bls[i])),
                ),
                RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(itemCount: orders.length, itemBuilder: (_, i) => _orderTile(orders[i])),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blTile(ReceptionBl b) => Card(
        child: ListTile(
          leading: const Icon(Icons.local_shipping, color: AppColors.primary),
          title: Text('BL ${b.ref} — ${b.grossiste}'),
          subtitle: Text('${b.date} · ${b.lines} ligne(s) · ${b.boxes} boîte(s)'
              '${b.orderRef.isEmpty ? '' : ' · Cde ${b.orderRef}'}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openBl(b),
        ),
      );

  Widget _orderTile(ReceptionOrder o) => Card(
        child: ListTile(
          leading: Icon(o.passed ? Icons.assignment_turned_in : Icons.assignment, color: Colors.blueGrey),
          title: Text('${o.ref} — ${o.grossiste}'),
          subtitle: Text('${o.statutLabel} · ${o.date} · ${o.products} produit(s) · ${_money.format(o.amount)} F'),
          trailing: TextButton(onPressed: () => _createBl(o), child: const Text('Créer BL')),
        ),
      );
}

class _CreateBlDialog extends StatefulWidget {
  final ReceptionOrder order;
  final DateTime today;
  const _CreateBlDialog({required this.order, required this.today});

  @override
  State<_CreateBlDialog> createState() => _CreateBlDialogState();
}

class _CreateBlDialogState extends State<_CreateBlDialog> {
  static final _fmt = DateFormat('dd/MM/yyyy');
  final _form = GlobalKey<FormState>();
  final _ref = TextEditingController();
  late final _date = TextEditingController(text: _fmt.format(widget.today));
  late final _ht = TextEditingController(text: '${widget.order.amount}');
  final _tva = TextEditingController(text: '0');

  @override
  void dispose() {
    for (final c in [_ref, _date, _ht, _tva]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime? _parseDate(String v) {
    try {
      return _fmt.parseStrict(v.trim());
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Créer le BL — ${widget.order.grossiste}'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Commande ${widget.order.ref} (${widget.order.products} produit(s))', style: const TextStyle(fontSize: 13)),
              TextFormField(
                controller: _ref,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'N° du BL *'),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'N° de BL obligatoire';
                  if (t.length > 20) return '20 caractères au plus';
                  return null;
                },
              ),
              TextFormField(
                controller: _date,
                decoration: const InputDecoration(labelText: 'Date du BL (JJ/MM/AAAA)'),
                validator: (v) => _parseDate(v ?? '') == null ? 'Date invalide' : null,
              ),
              TextFormField(
                controller: _ht,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Montant HT'),
                validator: (v) => int.tryParse((v ?? '').trim()) == null ? 'Montant invalide' : null,
              ),
              TextFormField(
                controller: _tva,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'TVA'),
                validator: (v) => int.tryParse((v ?? '').trim()) == null ? 'Montant invalide' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.of(context).pop((
              ref: _ref.text.trim(),
              date: _parseDate(_date.text)!,
              ht: int.parse(_ht.text.trim()),
              tva: int.parse(_tva.text.trim()),
            ));
          },
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
