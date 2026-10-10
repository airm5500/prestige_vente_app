// lib/screens/pointage/employees_screen.dart
// Employés du pointage (données de test locales, en attendant la configuration côté serveur).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/pointage/pointage_logic.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/screens/common/camera_scan_screen.dart';
import 'package:prestige_vente_app/services/fingerprint_service.dart';
import 'package:prestige_vente_app/services/nfc_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

class EmployeesScreen extends StatefulWidget {
  final PointageRepository repository;
  final DeviceCapability? capability;

  /// Présentation (A, B, C) ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;
  const EmployeesScreen({super.key, required this.repository, this.capability, this.presentation});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  List<Employee> _employees = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _reload();
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  Future<void> _reload() async {
    final list = await widget.repository.loadEmployees();
    if (mounted) setState(() => _employees = list);
  }

  Future<void> _edit([Employee? e]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => EmployeeEditScreen(repository: widget.repository, employee: e, capability: widget.capability, presentation: style),
    ));
    if (saved == true) await _reload();
  }

  static const _dayNames = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  String _details(Employee e) => [
        if (e.matricule.isNotEmpty) 'Mat. ${e.matricule}',
        '${e.scheduleStart}–${e.scheduleEnd}',
        e.workdays.map((d) => _dayNames[d - 1]).join(''),
        if (e.hasPin) 'PIN',
        if (e.hasBadge) 'Badge',
        if (e.hasNfc) 'NFC',
        if (e.fingerprintTemplates.isNotEmpty) '${e.fingerprintTemplates.length} empreinte(s)',
      ].join(' · ');

  Widget _chip(String label, bool on) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFE3ECF7) : const Color(0xFFF1F3F6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: on ? Pal.navy : Colors.grey.shade500)),
      );

  Widget _employeeTile(Employee e) {
    final name = Text(e.name + (e.active ? '' : ' (inactif)'),
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: e.active ? Pal.ink : Pal.muted));
    if (style == ListPresentation.compact) {
      return InkWell(
        onTap: () => _edit(e),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
          child: Row(children: [
            Icon(Icons.person, color: e.active ? Pal.navy : Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                name,
                Text(_details(e), style: const TextStyle(fontSize: 12, color: Pal.muted)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Pal.muted),
          ]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _edit(e),
        child: SoftCard(
          band: style == ListPresentation.guided ? (e.active ? Pal.navy : Colors.grey) : null,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Opacity(opacity: e.active ? 1 : 0.5, child: GrossisteAvatar(e.name)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                name,
                const SizedBox(height: 2),
                Text(_details(e), style: const TextStyle(fontSize: 12, color: Pal.muted)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  _chip('PIN', e.hasPin),
                  _chip('Badge', e.hasBadge),
                  _chip('NFC', e.hasNfc),
                  _chip('Empreinte', e.fingerprintTemplates.isNotEmpty),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Pal.muted),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? _employees
        : _employees.where((e) => e.name.toLowerCase().contains(q) || e.matricule.toLowerCase().contains(q)).toList();
    final active = _employees.where((e) => e.active).length;
    final withBadge = _employees.where((e) => e.hasBadge || e.hasNfc).length;
    final search = TextField(
      decoration: InputDecoration(
        hintText: 'Rechercher (nom, matricule)',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      onChanged: (v) => setState(() => _query = v),
    );
    return PresentationScaffold(
      style: style,
      title: 'Employés',
      subtitle: '${_employees.length} fiche(s)',
      actions: (col) => [PresentationMenuButton(value: style, onChanged: _setStyle, color: col)],
      steps: const StepsBar(active: 0, steps: [
        (title: 'Fiche', detail: 'nom, horaires', onTap: null),
        (title: 'Identification', detail: 'PIN, badge, NFC', onTap: null),
        (title: 'Pointer', detail: 'au kiosque', onTap: null),
      ]),
      header: [
        if (style == ListPresentation.dashboard) ...[
          Row(children: [
            Expanded(child: KpiTile('$active', 'actif(s)')),
            const SizedBox(width: 8),
            Expanded(child: KpiTile('${_employees.length - active}', 'inactif(s)')),
            const SizedBox(width: 8),
            Expanded(child: KpiTile('$withBadge', 'avec badge', highlight: true)),
          ]),
          const SizedBox(height: 10),
        ],
        if (_employees.isNotEmpty) search,
      ],
      compactHeader: [
        if (_employees.isNotEmpty)
          Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.line)),
            child: search,
          ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: style == ListPresentation.guided ? Pal.amber : Pal.navy,
        foregroundColor: style == ListPresentation.guided ? Pal.onAmber : Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('Ajouter'),
        onPressed: () => _edit(),
      ),
      body: _employees.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.groups_outlined, size: 56, color: Pal.muted),
                  SizedBox(height: 8),
                  Text('Aucun employé. Touchez « Ajouter ».', textAlign: TextAlign.center, style: TextStyle(color: Pal.muted)),
                ]),
              ),
            )
          : ListView(
              padding: style == ListPresentation.compact
                  ? const EdgeInsets.only(bottom: 80)
                  : const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                if (shown.isEmpty)
                  const Padding(padding: EdgeInsets.all(24), child: Text('Aucun employé ne correspond.', textAlign: TextAlign.center)),
                for (final e in shown) _employeeTile(e),
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

  /// Lecteur de badges NFC (remplaçable pour les tests).
  final NfcReader nfc;

  /// Présentation (A, B, C) ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;
  const EmployeeEditScreen({
    super.key,
    required this.repository,
    this.employee,
    this.capability,
    this.badgeCamera,
    this.nfc = const DeviceNfcReader(),
    this.presentation,
  });

  @override
  State<EmployeeEditScreen> createState() => _EmployeeEditScreenState();
}

class _EmployeeEditScreenState extends State<EmployeeEditScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  @override
  void initState() {
    super.initState();
    loadPresentation();
  }

  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.employee?.name ?? '');
  late final _matricule = TextEditingController(text: widget.employee?.matricule ?? '');
  late final _pin = TextEditingController(text: widget.employee?.pin ?? '');
  late final _start = TextEditingController(text: widget.employee?.scheduleStart ?? '08:00');
  late final _end = TextEditingController(text: widget.employee?.scheduleEnd ?? '17:00');
  late final _tolerance = TextEditingController(text: '${widget.employee?.toleranceMinutes ?? 10}');
  late final _badge = TextEditingController(text: widget.employee?.badgeCode ?? '');
  late String _nfcUid = widget.employee?.nfcUid ?? '';
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
    if (badge.isNotEmpty || _nfcUid.isNotEmpty) {
      final others = (await widget.repository.loadEmployees()).where((o) => o.id != base.id);
      final badgeOwner = badge.isEmpty ? null : others.where((o) => o.hasBadge && normalizeBadge(o.badgeCode) == normalizeBadge(badge)).firstOrNull;
      final nfcOwner = _nfcUid.isEmpty ? null : others.where((o) => o.hasNfc && normalizeBadge(o.nfcUid) == normalizeBadge(_nfcUid)).firstOrNull;
      if (badgeOwner != null || nfcOwner != null) {
        if (mounted) {
          Constants.showSnackBar(
            context,
            badgeOwner != null
                ? 'Ce badge est déjà attribué à ${badgeOwner.name}.'
                : 'Ce badge NFC est déjà attribué à ${nfcOwner!.name}.',
            isError: true,
          );
        }
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
      nfcUid: _nfcUid,
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

  Future<void> _readNfc() async {
    final state = await widget.nfc.availability();
    if (!mounted) return;
    if (state == NfcAvailability.absent) {
      Constants.showSnackBar(context, 'Cet appareil n\'a pas de lecteur NFC.', isError: true);
      return;
    }
    if (state == NfcAvailability.disabled) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('NFC désactivé'),
          content: const Text('Activez le NFC dans les réglages Android, puis revenez lire le badge.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer')),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                widget.nfc.openSettings();
              },
              child: const Text('Activer'),
            ),
          ],
        ),
      );
      return;
    }
    BuildContext? dialogCtx;
    final sub = widget.nfc.tags.listen((uid) {
      final c = dialogCtx;
      if (c != null && c.mounted) {
        dialogCtx = null;
        Navigator.of(c).pop(uid);
      }
    });
    final read = showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogCtx = ctx;
        return AlertDialog(
          title: const Text('Badge NFC'),
          content: const Row(
            children: [
              Icon(Icons.nfc, size: 48, color: AppColors.primary),
              SizedBox(width: 12),
              Expanded(child: Text('Approchez le badge du dos de l\'appareil...')),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler'))],
        );
      },
    );
    await widget.nfc.start();
    final uid = await read;
    unawaited(sub.cancel());
    await widget.nfc.stop();
    if (uid != null && mounted) setState(() => _nfcUid = normalizeBadge(uid));
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

  InputDecoration _deco(String label, {IconData? icon, String? helper, Widget? suffix}) => InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: icon == null ? null : Icon(icon),
        suffixIcon: suffix,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC5D0DE))),
      );

  /// Section de la fiche : carte (A, C) ou bloc séparé par un titre (B).
  Widget _section(IconData icon, String title, List<Widget> children) {
    final head = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, size: 20, color: Pal.navy),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Pal.ink))),
      ]),
    );
    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, ...children]);
    if (style == ListPresentation.compact) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Pal.line))),
        child: content,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(band: style == ListPresentation.guided ? Pal.navy : null, child: content),
    );
  }

  static const _gap = SizedBox(height: 10);

  @override
  Widget build(BuildContext context) {
    final sunmi = widget.capability?.mode == PointageMode.sunmiIdentify;
    final hasBadge = _badge.text.trim().isNotEmpty;
    return PresentationScaffold(
      style: style,
      title: widget.employee == null ? 'Nouvel employé' : 'Modifier l\'employé',
      subtitle: widget.employee?.name,
      actions: (col) => [
        if (widget.employee != null)
          IconButton(icon: Icon(Icons.delete_outline, color: col), tooltip: 'Supprimer', onPressed: _delete),
      ],
      steps: const StepsBar(active: 0, steps: [
        (title: 'Fiche', detail: 'nom, PIN', onTap: null),
        (title: 'Planning', detail: 'jours, retard', onTap: null),
        (title: 'Badges', detail: 'QR, NFC, empreinte', onTap: null),
      ]),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Pal.line))),
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              style: style == ListPresentation.guided ? amberButton : navyButton,
              icon: const Icon(Icons.check),
              label: const Text('Enregistrer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: _save,
            ),
          ),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, style == ListPresentation.compact ? 0 : 16, 16, 16),
          children: [
            _section(Icons.person_outline, 'Identité', [
              TextFormField(
                controller: _name,
                decoration: _deco('Nom et prénom *'),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Nom obligatoire' : null,
              ),
              _gap,
              TextFormField(controller: _matricule, decoration: _deco('Matricule')),
              _gap,
              TextFormField(
                controller: _pin,
                decoration: _deco('Code PIN (4 à 6 chiffres, facultatif)'),
                keyboardType: TextInputType.number,
                obscureText: true,
                validator: (v) {
                  final t = (v ?? '').trim();
                  return t.isEmpty || RegExp(r'^\d{4,6}$').hasMatch(t) ? null : '4 à 6 chiffres';
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Actif'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ]),
            _section(Icons.schedule, 'Horaires', [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: TextFormField(controller: _start, decoration: _deco('Début (HH:mm)'), validator: _timeValidator)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _end,
                      decoration: _deco('Fin (HH:mm)'),
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
              _gap,
              TextFormField(
                controller: _tolerance,
                decoration: _deco('Tolérance de retard (minutes)'),
                keyboardType: TextInputType.number,
                validator: (v) => int.tryParse((v ?? '').trim()) == null ? 'Nombre de minutes' : null,
              ),
              _gap,
              const Text('Jours travaillés', style: TextStyle(color: Pal.muted)),
              Wrap(
                spacing: 6,
                children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(_dayNames[d - 1]),
                      selected: _days.contains(d),
                      selectedColor: const Color(0xFFE3ECF7),
                      checkmarkColor: Pal.navy,
                      onSelected: (s) => setState(() => s ? _days.add(d) : _days.remove(d)),
                    ),
                ],
              ),
            ]),
            _section(Icons.badge_outlined, 'Badge code-barres / QR', [
              TextFormField(
                controller: _badge,
                decoration: _deco(
                  'Badge (code-barres ou QR)',
                  icon: Icons.badge,
                  helper: 'Scannez le badge existant ou générez un code.',
                  suffix: IconButton(
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
                  if (hasBadge) ...[
                    TextButton.icon(icon: const Icon(Icons.qr_code_2), label: const Text('Afficher le QR'), onPressed: _showBadgeQr),
                    TextButton(onPressed: () => setState(_badge.clear), child: const Text('Retirer')),
                  ],
                ],
              ),
            ]),
            _section(Icons.nfc, 'Badge NFC', [
              Text(_nfcUid.isEmpty ? 'Badge NFC : aucun' : 'Badge NFC : $_nfcUid',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
              const Text('Carte sans contact approchée du dos de l\'appareil.', style: TextStyle(fontSize: 13, color: Pal.muted)),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(icon: const Icon(Icons.contactless), label: const Text('Lire le badge NFC'), onPressed: _readNfc),
                  if (_nfcUid.isNotEmpty)
                    TextButton(onPressed: () => setState(() => _nfcUid = ''), child: const Text('Retirer le NFC')),
                ],
              ),
            ]),
            _section(Icons.fingerprint, 'Empreintes', [
              Text('Empreintes (terminal Sunmi) : ${_templates.length}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
              Text(
                sunmi
                    ? 'Enregistrez 1 ou 2 doigts pour être reconnu au pointage.'
                    : 'Disponible sur un terminal Sunmi avec service d\'identification. '
                        'Sur cet appareil, l\'employé pointe avec son nom puis l\'empreinte ou le PIN.',
                style: const TextStyle(fontSize: 13, color: Pal.muted),
              ),
              if (sunmi) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: outlineButton,
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
              ],
            ]),
          ],
        ),
      ),
    );
  }
}
