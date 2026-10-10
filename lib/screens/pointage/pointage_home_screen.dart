// lib/screens/pointage/pointage_home_screen.dart
// Accueil du pointage : mode adapté à l'appareil, accès au pointage, aux employés et au rapport.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/pointage/pointage_logic.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/screens/pointage/employees_screen.dart';
import 'package:prestige_vente_app/screens/pointage/fingerprint_diagnostic_screen.dart';
import 'package:prestige_vente_app/screens/pointage/pointage_kiosk_screen.dart';
import 'package:prestige_vente_app/screens/pointage/pointage_report_screen.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

class PointageHomeScreen extends StatefulWidget {
  /// Remplaçables pour les tests.
  final PointageRepository? repository;
  final Future<DeviceCapability> Function()? detectCapability;
  final Future<bool> Function(BuildContext)? adminCheck;

  /// Présentation (A, B, C) ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;

  const PointageHomeScreen({super.key, this.repository, this.detectCapability, this.adminCheck, this.presentation});

  @override
  State<PointageHomeScreen> createState() => _PointageHomeScreenState();
}

class _PointageHomeScreenState extends State<PointageHomeScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  late final PointageRepository _repo = widget.repository ?? LocalPointageRepository();
  DeviceCapability? _capability;
  PointageSettings _settings = const PointageSettings();

  // Chiffres du jour (en-tête).
  int _employeesCount = 0;
  int _presentCount = 0;
  int _todayCount = 0;

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _detect();
    _loadSettings();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final employees = (await _repo.loadEmployees()).where((e) => e.active).toList();
      final records = await _repo.loadRecords(from: start, to: start.add(const Duration(days: 1)));
      var present = 0;
      for (final e in employees) {
        final mine = records.where((r) => r.employeeId == e.id).toList();
        if (mine.isNotEmpty && mine.last.type != PointageType.depart) present++;
      }
      if (!mounted) return;
      setState(() {
        _employeesCount = employees.length;
        _presentCount = present;
        _todayCount = records.length;
      });
    } catch (_) {}
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  Future<void> _loadSettings() async {
    final s = await _repo.loadSettings();
    if (mounted) setState(() => _settings = s);
  }

  Future<void> _editSettings() async {
    if (!await (widget.adminCheck ?? PinCodeDialog.show)(context) || !mounted) return;
    var draft = _settings;
    final saved = await showDialog<PointageSettings>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Méthode de pointage'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in BadgeMode.values)
                  RadioListTile<BadgeMode>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(m.label),
                    value: m,
                    groupValue: draft.badgeMode,
                    onChanged: (v) => setLocal(() => draft = draft.copyWith(badgeMode: v)),
                  ),
                if (draft.badgeEnabled)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Code PIN après le badge'),
                    subtitle: const Text('Empêche de pointer avec le badge d\'un collègue.'),
                    value: draft.pinAfterBadge,
                    onChanged: (v) => setLocal(() => draft = draft.copyWith(pinAfterBadge: v ?? false)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(draft), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (saved == null) return;
    await _repo.saveSettings(saved);
    if (mounted) setState(() => _settings = saved);
  }

  String get _methodSummary => switch (_settings.badgeMode) {
        BadgeMode.off => 'Empreinte / PIN selon l\'appareil',
        BadgeMode.only => 'Badge uniquement',
        BadgeMode.both => 'Badge ou ${_capability?.modeLabel ?? 'empreinte / PIN'}',
      } +
      (_settings.badgeEnabled && _settings.pinAfterBadge ? ' · PIN après le badge' : '');

  Future<void> _detect() async {
    final c = await (widget.detectCapability ?? DeviceCapability.detect)();
    if (mounted) setState(() => _capability = c);
  }

  Future<void> _admin(Widget screen) async {
    final ok = await (widget.adminCheck ?? PinCodeDialog.show)(context);
    if (ok && mounted) await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _loadStats();
  }

  Future<void> _openKiosk(DeviceCapability c) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PointageKioskScreen(repository: _repo, capability: c, settings: _settings, presentation: style),
    ));
    if (mounted) _loadStats();
  }

  @override
  Widget build(BuildContext context) {
    final c = _capability;
    final compact = style == ListPresentation.compact;
    final modeCard = SoftCard(
      band: style == ListPresentation.guided ? Pal.navy : null,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: const Color(0xFFE3ECF7), borderRadius: BorderRadius.circular(12)),
          child: Icon(c?.mode == PointageMode.pinOrName ? Icons.pin : Icons.fingerprint, size: 30, color: Pal.navy),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c == null ? 'Analyse de l\'appareil...' : 'Mode : ${c.modeLabel}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Pal.ink)),
            const SizedBox(height: 4),
            if (c == null)
              const LinearProgressIndicator()
            else
              Text('${c.device.isEmpty ? '' : '${c.device}\n'}${c.explanation}', style: const TextStyle(fontSize: 13, color: Pal.muted)),
          ]),
        ),
      ]),
    );
    final pointer = SizedBox(
      height: 72,
      child: ElevatedButton.icon(
        style: (style == ListPresentation.guided ? amberButton : navyButton).copyWith(
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        ),
        icon: const Icon(Icons.how_to_reg, size: 32),
        label: const Text('POINTER', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        onPressed: c == null ? null : () => _openKiosk(c),
      ),
    );
    final tiles = [
      _tile(Icons.tune, 'Méthode de pointage', _methodSummary, _editSettings),
      _tile(Icons.people, 'Employés', 'Ajouter, horaires, code PIN, badge (code-barres, QR, NFC), empreinte',
          () => _admin(EmployeesScreen(repository: _repo, capability: c, presentation: style))),
      _tile(Icons.insights, 'Rapport et analyse', 'Présence, retards, heures, comportement',
          () => _admin(PointageReportScreen(repository: _repo, presentation: style))),
      _tile(Icons.fingerprint, 'Diagnostic du lecteur', 'Vérifier le lecteur de cet appareil',
          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FingerprintDiagnosticScreen(presentation: style))),
          locked: false),
    ];
    return PresentationScaffold(
      style: style,
      title: 'Pointage',
      subtitle: style == ListPresentation.dashboard ? 'Présence des employés' : null,
      actions: (col) => [PresentationMenuButton(value: style, onChanged: _setStyle, color: col)],
      steps: const StepsBar(active: 1, steps: [
        (title: 'Configurer', detail: 'méthode, employés', onTap: null),
        (title: 'Pointer', detail: 'arrivée, départ', onTap: null),
        (title: 'Analyser', detail: 'rapport', onTap: null),
      ]),
      header: [
        if (style == ListPresentation.dashboard)
          Row(children: [
            Expanded(child: KpiTile('$_presentCount', 'présent(s)')),
            const SizedBox(width: 8),
            Expanded(child: KpiTile('$_todayCount', 'pointage(s) du jour')),
            const SizedBox(width: 8),
            Expanded(child: KpiTile('$_employeesCount', 'employé(s)', highlight: true)),
          ]),
      ],
      compactHeader: [
        LightFigures([
          ('$_presentCount', 'Présents', Colors.green.shade700),
          ('$_todayCount', 'Pointages du jour', Pal.navy),
          ('$_employeesCount', 'Effectif', Pal.navy),
        ]),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          modeCard,
          const SizedBox(height: 16),
          pointer,
          const SizedBox(height: 16),
          if (compact)
            Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.line)),
              child: Column(children: tiles),
            )
          else
            for (final t in tiles) Padding(padding: const EdgeInsets.only(bottom: 10), child: t),
          const SizedBox(height: 12),
          Text(
            'Données de test enregistrées sur cet appareil. La synchronisation avec le serveur Prestige '
            'viendra avec la configuration des employés.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap, {bool locked = true}) {
    final row = Row(children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: const Color(0xFFE3ECF7), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: Pal.navy),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: Pal.muted)),
        ]),
      ),
      Icon(locked ? Icons.lock_outline : Icons.chevron_right, size: 18, color: Pal.muted),
    ]);
    if (style == ListPresentation.compact) {
      return InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
          child: row,
        ),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: SoftCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: row),
    );
  }
}
