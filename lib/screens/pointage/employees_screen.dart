// lib/screens/pointage/employees_screen.dart
// Employés du pointage (données de test locales, en attendant la configuration côté serveur).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/pointage/pointage_logic.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/screens/common/camera_scan_screen.dart';
import 'package:prestige_vente_app/services/fingerprint_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

class EmployeesScreen extends StatefulWidget {
  final PointageRepository repository;
  final DeviceCapability? capability;
  const EmployeesScreen({super.key, required this.repository, this.capability});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Employee> _employees = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await widget.repository.loadEmployees();
    if (mounted) setState(() => _employees = list);
  }

  Future<void> _edit([Employee? e]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => EmployeeEditScreen(repository: widget.repository, employee: e, capability: widget.capability),
    ));
    if (saved == true) await _reload();
  }

  static const _dayNames = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Employés')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('Ajouter'),
        onPressed: () => _edit(),
      ),
      body: _employees.isEmpty
          ? const Center(child: Text('Aucun employé. Touchez « Ajouter ».'))
          : ListView(
              padding: const EdgeInsets.only(bottom: 80),
              children: [
                for (final e in _employees)
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.person, color: e.active ? AppColors.primary : Colors.grey),
                      title: Text(e.name + (e.active ? '' : ' (inactif)')),
                      subtitle: Text([
                        if (e.matricule.isNotEmpty) 'Mat. ${e.matricule}',
                        '${e.scheduleStart}–${e.scheduleEnd}',
                        e.workdays.map((d) => _dayNames[d - 1]).join(''),
                        if (e.hasPin) 'PIN',
                        if (e.hasBadge) 'Badge',
                        if (e.fingerprintTemplates.isNotEmpty) '${e.fingerprintTemplates.length} empreinte(s)',
                      ].join(' · ')),
                      onTap: () => _edit(e),
                    ),
                  ),
              ],
            ),
    );
  }
}

class EmployeeEditScreen extends StatefulWidget {
  final PointageRepository repository;
  final Employee? employee;
  final DeviceCapability? capability;

  /// Lecture du badge par la caméra (remplaçable pour les tests).
  final Future<String?> Function(BuildContext context)? badgeCamera;
  const EmployeeEditScreen({super.key, required this.repository, this.employee, this.capability, this.badgeCamera});

  @override
  State<EmployeeEditScreen> createState() => _EmployeeEditScreenState();
}

class _EmployeeEditScreenState extends State<EmployeeEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.employee?.name ?? '');
  late final _matricule = TextEditingController(text: widget.employee?.matricule ?? '');
  late final _pin = TextEditingController(text: widget.employee?.pin ?? '');
  late final _start = TextEditingController(text: widget.employee?.scheduleStart ?? '08:00');
  late final _end = TextEditingController(text: widget.employee?.scheduleEnd ?? '17:00');
  late final _tolerance = TextEditingController(text: '${widget.employee?.toleranceMinutes ?? 10}');
  late final _badge = TextEditingController(text: widget.employee?.badgeCode ?? '');
  late final Set<int> _days = {...(widget.employee?.workdays ?? const [1, 2, 3, 4, 5, 6])};
  late bool _active = widget.employee?.active ?? true;
  late List<String> _templates = List.of(widget.employee?.fingerprintTemplates ?? const []);
  bool _enrolling = false;

  static const _dayNames = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  static final _hhmm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  @override
  void dispose() {
    for (final c in [_name, _matricule, _pin, _start, _end, _tolerance, _badge]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_days.isEmpty) {
      Constants.showSnackBar(context, 'Choisissez au moins un jour travaillé.', isError: true);
      return;
    }
    final base = widget.employee ?? Employee(id: const Uuid().v4(), name: '');
    final badge = _badge.text.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    if (badge.isNotEmpty) {
      final others = await widget.repository.loadEmployees();
      final owner = others.where((o) => o.id != base.id && o.hasBadge && normalizeBadge(o.badgeCode) == normalizeBadge(badge));
      if (owner.isNotEmpty) {
        if (mounted) Constants.showSnackBar(context, 'Ce badge est déjà attribué à ${owner.first.name}.', isError: true);
        return;
      }
    }
    final e = base.copyWith(
      name: _name.text.trim(),
      matricule: _matricule.text.trim(),
      pin: _pin.text.trim(),
      clearPin: _pin.text.trim().isEmpty,
      scheduleStart: _start.text.trim(),
      scheduleEnd: _end.text.trim(),
      toleranceMinutes: int.parse(_tolerance.text.trim()),
      workdays: (_days.toList()..sort()),
      active: _active,
      fingerprintTemplates: _templates,
      badgeCode: badge,
    );
    await widget.repository.saveEmployee(e);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer l\'employé ?'),
        content: const Text('Ses pointages restent dans l\'historique.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) {
      await widget.repository.deleteEmployee(widget.employee!.id);
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  Future<void> _enroll() async {
    setState(() => _enrolling = true);
    try {
      await FingerprintService.connect();
      await FingerprintService.engage();
      final t = await FingerprintService.enroll();
      setState(() => _templates = [..._templates, base64Encode(t)]);
      if (mounted) Constants.showSnackBar(context, 'Empreinte enregistrée. Pensez à Enregistrer la fiche.');
    } catch (e) {
      if (mounted) Constants.showSnackBar(context, '$e', isError: true);
    } finally {
      if (mounted) setState(() => _enrolling = false);
    }
  }

  Future<void> _scanBadge() async {
    final value = await (widget.badgeCamera ?? (ctx) => CameraScanScreen.open(ctx, title: 'Scanner le badge'))(context);
    if (value != null && mounted) setState(() => _badge.text = value.trim());
  }

  void _generateBadge() {
    setState(() => _badge.text = 'PV${const Uuid().v4().replaceAll('-', '').substring(0, 8).toUpperCase()}');
  }

  void _showBadgeQr() {
    final code = _badge.text.trim();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_name.text.trim().isEmpty ? 'Badge' : _name.text.trim()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 220,
              height: 220,
              child: QrImageView(data: code, version: QrVersions.auto, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(code, style: const TextStyle(fontSize: 18, letterSpacing: 2)),
            const SizedBox(height: 8),
            const Text('Imprimez ce QR code ou faites une capture d\'écran pour l\'employé.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer'))],
      ),
    );
  }

  String? _timeValidator(String? v) => _hhmm.hasMatch(v?.trim() ?? '') ? null : 'Format HH:mm';

  @override
  Widget build(BuildContext context) {
    final sunmi = widget.capability?.mode == PointageMode.sunmiIdentify;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.employee == null ? 'Nouvel employé' : 'Modifier l\'employé'),
        actions: [
          if (widget.employee != null) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom et prénom *'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Nom obligatoire' : null,
            ),
            TextFormField(controller: _matricule, decoration: const InputDecoration(labelText: 'Matricule')),
            TextFormField(
              controller: _pin,
              decoration: const InputDecoration(labelText: 'Code PIN (4 à 6 chiffres, facultatif)'),
              keyboardType: TextInputType.number,
              obscureText: true,
              validator: (v) {
                final t = (v ?? '').trim();
                return t.isEmpty || RegExp(r'^\d{4,6}$').hasMatch(t) ? null : '4 à 6 chiffres';
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TextFormField(controller: _start, decoration: const InputDecoration(labelText: 'Début (HH:mm)'), validator: _timeValidator)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _end,
                    decoration: const InputDecoration(labelText: 'Fin (HH:mm)'),
                    validator: (v) {
                      final err = _timeValidator(v);
                      if (err != null) return err;
                      if (_hhmm.hasMatch(_start.text.trim()) && Employee.minutesOf(v!.trim()) <= Employee.minutesOf(_start.text.trim())) {
                        return 'Après le début';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            TextFormField(
              controller: _tolerance,
              decoration: const InputDecoration(labelText: 'Tolérance de retard (minutes)'),
              keyboardType: TextInputType.number,
              validator: (v) => int.tryParse((v ?? '').trim()) == null ? 'Nombre de minutes' : null,
            ),
            const SizedBox(height: 12),
            const Text('Jours travaillés'),
            Wrap(
              spacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(_dayNames[d - 1]),
                    selected: _days.contains(d),
                    onSelected: (s) => setState(() => s ? _days.add(d) : _days.remove(d)),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Actif'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            const Divider(),
            TextFormField(
              controller: _badge,
              decoration: InputDecoration(
                labelText: 'Badge (code-barres ou QR)',
                helperText: 'Scannez le badge existant ou générez un code.',
                prefixIcon: const Icon(Icons.badge),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.photo_camera),
                  tooltip: 'Scanner le badge (caméra)',
                  onPressed: _scanBadge,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(icon: const Icon(Icons.auto_awesome), label: const Text('Générer un code'), onPressed: _generateBadge),
                if (_badge.text.trim().isNotEmpty) ...[
                  TextButton.icon(icon: const Icon(Icons.qr_code_2), label: const Text('Afficher le QR'), onPressed: _showBadgeQr),
                  TextButton(onPressed: () => setState(_badge.clear), child: const Text('Retirer')),
                ],
              ],
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.fingerprint),
              title: Text('Empreintes (terminal Sunmi) : ${_templates.length}'),
              subtitle: Text(sunmi
                  ? 'Enregistrez 1 ou 2 doigts pour être reconnu au pointage.'
                  : 'Disponible sur un terminal Sunmi avec service d\'identification. '
                      'Sur cet appareil, l\'employé pointe avec son nom puis l\'empreinte ou le PIN.'),
            ),
            if (sunmi)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: _enrolling
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.fingerprint),
                      label: const Text('Enregistrer une empreinte'),
                      onPressed: _enrolling ? null : _enroll,
                    ),
                  ),
                  if (_templates.isNotEmpty)
                    TextButton(onPressed: () => setState(() => _templates = []), child: const Text('Effacer')),
                ],
              ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _save, child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
  }
}
