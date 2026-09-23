// lib/screens/pointage/fingerprint_diagnostic_screen.dart
// Diagnostic du lecteur d'empreinte Sunmi : vérifie sur le terminal que le service répond,
// que le capteur s'active, puis teste un enregistrement et une reconnaissance.
// Aucune donnée n'est envoyée ni conservée : les empreintes de test restent en mémoire.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/services/fingerprint_service.dart';

enum _Step { service, connect, sensor, enroll, identify }

enum _State { todo, running, ok, failed }

class FingerprintDiagnosticScreen extends StatefulWidget {
  const FingerprintDiagnosticScreen({super.key});

  @override
  State<FingerprintDiagnosticScreen> createState() => _FingerprintDiagnosticScreenState();
}

class _FingerprintDiagnosticScreenState extends State<FingerprintDiagnosticScreen> {
  final Map<_Step, _State> _states = {for (final s in _Step.values) s: _State.todo};
  final Map<_Step, String> _details = {};
  final List<Uint8List> _testTemplates = [];
  String? _hint;
  bool _busy = false;
  StreamSubscription<String>? _hintSub;

  static const _labels = {
    _Step.service: 'Service d\'empreinte Sunmi présent',
    _Step.connect: 'Connexion au service',
    _Step.sensor: 'Activation du capteur',
    _Step.enroll: 'Test d\'enregistrement',
    _Step.identify: 'Test de reconnaissance',
  };

  @override
  void initState() {
    super.initState();
    try {
      _hintSub = FingerprintService.hints.listen((h) {
        if (!mounted) return;
        setState(() => _hint = switch (h) {
              'press' => 'Posez le doigt sur le capteur',
              'raise' => 'Retirez le doigt',
              'disconnected' => 'Service déconnecté',
              _ => h,
            });
      }, onError: (_) {});
    } catch (_) {}
    WidgetsBinding.instance.addPostFrameCallback((_) => _runChecks());
  }

  @override
  void dispose() {
    _hintSub?.cancel();
    FingerprintService.release().catchError((_) {});
    super.dispose();
  }

  void _set(_Step s, _State st, [String? detail]) {
    if (!mounted) return;
    setState(() {
      _states[s] = st;
      if (detail != null) _details[s] = detail;
    });
  }

  Future<bool> _step(_Step s, Future<String?> Function() action) async {
    _set(s, _State.running);
    try {
      final detail = await action();
      _set(s, _State.ok, detail ?? '');
      return true;
    } catch (e) {
      _set(s, _State.failed, e.toString());
      return false;
    }
  }

  /// Étapes automatiques : service, connexion, capteur.
  Future<void> _runChecks() async {
    setState(() => _busy = true);
    final installed = await _step(_Step.service, () async {
      if (!await FingerprintService.isServiceInstalled()) {
        throw const FingerprintException('NO_SERVICE',
            'Service absent : ce terminal n\'a pas de lecteur d\'empreinte Sunmi compatible (version V3H "fingerprint" requise).');
      }
      return 'com.sunmi.fingerprintservice';
    });
    if (installed && await _step(_Step.connect, () async {
      await FingerprintService.connect();
      return 'Connecté';
    })) {
      await _step(_Step.sensor, () async {
        await FingerprintService.engage();
        final info = await FingerprintService.deviceInfo();
        final cap = await FingerprintService.capacity().then((c) => c, onError: (_) => (capacity: -1, enrolled: -1));
        final parts = [
          if (info['device_manufacturer'] != null) info['device_manufacturer'],
          if (info['device_model'] != null) info['device_model'],
          if (info['device_firmware_version'] != null) 'firmware ${info['device_firmware_version']}',
          if (info['device_serialnumber'] != null) 'n° ${info['device_serialnumber']}',
          if (cap.capacity >= 0) 'capacité ${cap.capacity}',
        ];
        return parts.isEmpty ? 'Capteur actif' : parts.join(' · ');
      });
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _testEnroll() async {
    setState(() {
      _busy = true;
      _hint = 'Posez le doigt sur le capteur';
    });
    await _step(_Step.enroll, () async {
      final t = await FingerprintService.enroll();
      _testTemplates.add(t);
      return 'Empreinte n°${_testTemplates.length} enregistrée (gabarit ${t.length} octets)';
    });
    if (mounted) {
      setState(() {
        _busy = false;
        _hint = null;
      });
    }
  }

  Future<void> _testIdentify() async {
    setState(() {
      _busy = true;
      _hint = 'Posez le doigt sur le capteur';
    });
    await _step(_Step.identify, () async {
      final m = await FingerprintService.identify(_testTemplates);
      return m.found ? 'Reconnue : empreinte n°${m.index + 1} (score ${m.score})' : 'Non reconnue parmi les ${_testTemplates.length} empreinte(s) de test';
    });
    if (mounted) {
      setState(() {
        _busy = false;
        _hint = null;
      });
    }
  }

  String _report() => [
        'Diagnostic empreinte Sunmi',
        for (final s in _Step.values) '${_labels[s]} : ${_states[s]!.name}${_details[s] == null || _details[s]!.isEmpty ? '' : ' — ${_details[s]}'}',
      ].join('\n');

  @override
  Widget build(BuildContext context) {
    final ready = _states[_Step.sensor] == _State.ok;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Empreinte : diagnostic'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copier le rapport',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _report()));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rapport copié')));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Ce test vérifie le lecteur d\'empreinte du terminal. Les empreintes de test restent en mémoire '
            'et sont effacées à la fermeture de l\'écran.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          for (final s in _Step.values) _tile(s),
          if (_hint != null)
            Card(
              color: Colors.blue.shade50,
              child: ListTile(
                leading: const Icon(Icons.fingerprint, size: 36, color: Colors.blue),
                title: Text(_hint!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.fingerprint),
            label: Text(_testTemplates.isEmpty ? 'Tester l\'enregistrement' : 'Enregistrer une autre empreinte'),
            onPressed: ready && !_busy ? _testEnroll : null,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.how_to_reg),
            label: const Text('Tester la reconnaissance'),
            onPressed: ready && !_busy && _testTemplates.isNotEmpty ? _testIdentify : null,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Relancer le diagnostic'),
            onPressed: _busy ? null : _runChecks,
          ),
        ],
      ),
    );
  }

  Widget _tile(_Step s) {
    final st = _states[s]!;
    final (IconData icon, Color color) = switch (st) {
      _State.todo => (Icons.radio_button_unchecked, Colors.grey),
      _State.running => (Icons.hourglass_top, Colors.blue),
      _State.ok => (Icons.check_circle, Colors.green.shade700),
      _State.failed => (Icons.error, Colors.red.shade700),
    };
    final detail = _details[s];
    return Card(
      child: ListTile(
        leading: st == _State.running
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, color: color),
        title: Text(_labels[s]!),
        subtitle: detail == null || detail.isEmpty ? null : Text(detail),
      ),
    );
  }
}
