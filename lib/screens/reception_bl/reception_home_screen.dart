// lib/screens/reception_bl/reception_home_screen.dart
// Réception BL : bons à entrer en stock, et commandes (en cours / passées) à transformer en BL.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _ReceptionHomeScreenState extends State<ReceptionHomeScreen> with SingleTickerProviderStateMixin {
  // Onglet 0 : commandes (point de départ) ; onglet 1 : BL à entrer en stock.
  late final TabController _tabs = TabController(length: 2, vsync: this);
  String? _justCreated;

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

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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
    ReceptionResult? result;
    String? ref;
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _CreateBlScreen(
        order: order,
        today: (widget.clock ?? DateTime.now)(),
        onCreate: (input) async {
          final r = await _gateway.createBl(orderId: order.id, ref: input.ref, date: input.date, amountHt: input.ht, tva: input.tva);
          result = r;
          ref = input.ref;
          return r;
        },
      ),
    ));
    if (created != true || !mounted) return;
    final data = result?.data['data'];
    final missing = data is List ? data.map((e) => '$e').toList() : const <String>[];
    if (missing.isNotEmpty) {
      await _info(
        'BL créé avec réserves',
        '${missing.length} produit(s) sans stock à votre emplacement n\'ont pas été repris dans le BL :\n${missing.join(', ')}',
      );
    }
    await _load();
    if (!mounted) return;
    // Le BL créé apparaît dans l'onglet « BL à entrer », mis en évidence.
    setState(() => _justCreated = ref);
    _tabs.animateTo(1);
    Constants.showSnackBar(context, 'BL $ref créé : touchez-le pour commencer la saisie.');
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
    return Scaffold(
        appBar: AppBar(
          title: const Text('Réception BL'),
          actions: [
            IconButton(icon: const Icon(Icons.tune), tooltip: 'Réglages', onPressed: _editSettings),
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Actualiser', onPressed: _load),
          ],
          bottom: TabBar(
            controller: _tabs,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.amber,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            unselectedLabelStyle: const TextStyle(fontSize: 15),
            tabs: [
              Tab(text: 'Commandes (${_orders.length})'),
              Tab(text: 'BL à entrer (${_bls.length})'),
            ],
          ),
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
              child: TabBarView(controller: _tabs, children: [
                RefreshIndicator(
                  onRefresh: _load,
                  child: orders.isEmpty && !_loading
                      ? ListView(children: const [
                          Padding(padding: EdgeInsets.all(24), child: Text('Aucune commande en cours ou passée.', textAlign: TextAlign.center)),
                        ])
                      : ListView.builder(itemCount: orders.length, itemBuilder: (_, i) => _orderTile(orders[i])),
                ),
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
              ]),
            ),
          ],
        ),
    );
  }

  Widget _blTile(ReceptionBl b) => Card(
        shape: b.ref == _justCreated
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.green.shade600, width: 2))
            : null,
        child: ListTile(
          leading: Icon(b.ref == _justCreated ? Icons.fiber_new : Icons.local_shipping,
              color: b.ref == _justCreated ? Colors.green.shade700 : AppColors.primary),
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

typedef _BlInput = ({String ref, DateTime date, int ht, int tva});

/// Création d'un BL depuis une commande : page entière, champs espacés, date au calendrier.
/// En cas de refus (n° déjà utilisé…), le message s'affiche ici et la saisie est conservée.
class _CreateBlScreen extends StatefulWidget {
  final ReceptionOrder order;
  final DateTime today;
  final Future<ReceptionResult> Function(_BlInput input) onCreate;
  const _CreateBlScreen({required this.order, required this.today, required this.onCreate});

  @override
  State<_CreateBlScreen> createState() => _CreateBlScreenState();
}

class _CreateBlScreenState extends State<_CreateBlScreen> {
  static final _fmt = DateFormat('dd/MM/yyyy');
  static final _money = NumberFormat.decimalPattern('fr_FR');
  final _form = GlobalKey<FormState>();
  final _ref = TextEditingController();
  late final _ht = TextEditingController(text: '${widget.order.amount}');
  final _tva = TextEditingController(text: '0');
  late DateTime _date = DateTime(widget.today.year, widget.today.month, widget.today.day);
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ht.addListener(() => setState(() {}));
    _tva.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_ref, _ht, _tva]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _date.subtract(const Duration(days: 365)),
      lastDate: widget.today.add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await widget.onCreate((
      ref: _ref.text.trim(),
      date: _date,
      ht: int.parse(_ht.text.trim()),
      tva: int.parse(_tva.text.trim()),
    ));
    if (!mounted) return;
    if (r.success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = r.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final total = (int.tryParse(_ht.text.trim()) ?? 0) + (int.tryParse(_tva.text.trim()) ?? 0);
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau BL')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Card(
              margin: EdgeInsets.zero,
              color: Colors.blueGrey.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.grossiste, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Commande ${o.ref} · ${o.statutLabel}'),
                  Text('${o.products} produit(s) · ${_money.format(o.amount)} F'),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _ref,
              autofocus: true,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                labelText: 'N° du BL *',
                helperText: 'Tel qu\'imprimé sur le bon du grossiste',
                prefixIcon: Icon(Icons.receipt_long),
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'N° de BL obligatoire';
                if (t.length > 20) return '20 caractères au plus';
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date du BL', prefixIcon: Icon(Icons.event)),
                child: Row(children: [
                  Expanded(child: Text(_fmt.format(_date), style: const TextStyle(fontSize: 16))),
                  const Text('Modifier', style: TextStyle(color: AppColors.primary)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextFormField(
                  controller: _ht,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Montant HT'),
                  validator: (v) => int.tryParse((v ?? '').trim()) == null ? 'Montant' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _tva,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'TVA'),
                  validator: (v) => int.tryParse((v ?? '').trim()) == null ? 'Montant' : null,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text('Total TTC : ${_money.format(total)} F', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
                child: Row(children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade900))),
                ]),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                icon: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check),
                label: const Text('Créer le BL', style: TextStyle(fontSize: 17)),
                onPressed: _saving ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
