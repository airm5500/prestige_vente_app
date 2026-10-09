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
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';

class PointageHomeScreen extends StatefulWidget {
  /// Remplaçables pour les tests.
  final PointageRepository? repository;
  final Future<DeviceCapability> Function()? detectCapability;
  final Future<bool> Function(BuildContext)? adminCheck;

  const PointageHomeScreen({super.key, this.repository, this.detectCapability, this.adminCheck});

  @override
  State<PointageHomeScreen> createState() => _PointageHomeScreenState();
}

class _PointageHomeScreenState extends State<PointageHomeScreen> {
  late final PointageRepository _repo = widget.repository ?? LocalPointageRepository();
  DeviceCapability? _capability;
  PointageSettings _settings = const PointageSettings();

  @override
  void initState() {
    super.initState();
    _detect();
    _loadSettings();
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
  }

  @override
  Widget build(BuildContext context) {
    final c = _capability;
    return Scaffold(
      appBar: AppBar(title: const Text('Pointage')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                c?.mode == PointageMode.pinOrName ? Icons.pin : Icons.fingerprint,
                size: 36,
                color: AppColors.primary,
              ),
              title: Text(c == null ? 'Analyse de l\'appareil...' : 'Mode : ${c.modeLabel}'),
              subtitle: c == null ? const LinearProgressIndicator() : Text('${c.device.isEmpty ? '' : '${c.device}\n'}${c.explanation}'),
              isThreeLine: c != null,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 72,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.how_to_reg, size: 32),
              label: const Text('POINTER', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              onPressed: c == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PointageKioskScreen(repository: _repo, capability: c, settings: _settings),
                      )),
            ),
          ),
          const SizedBox(height: 16),
          _tile(Icons.tune, 'Méthode de pointage', _methodSummary, _editSettings),
          _tile(Icons.people, 'Employés', 'Ajouter, horaires, code PIN, badge (code-barres, QR, NFC), empreinte',
              () => _admin(EmployeesScreen(repository: _repo, capability: c))),
          _tile(Icons.insights, 'Rapport et analyse', 'Présence, retards, heures, comportement',
              () => _admin(PointageReportScreen(repository: _repo))),
          _tile(Icons.fingerprint, 'Diagnostic du lecteur', 'Vérifier le lecteur de cet appareil',
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FingerprintDiagnosticScreen())),
              locked: false),
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

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap, {bool locked = true}) => Card(
        child: ListTile(
          leading: Icon(icon, color: AppColors.primary),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: locked ? const Icon(Icons.lock_outline, size: 18) : null,
          onTap: onTap,
        ),
      );
}
