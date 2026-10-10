// lib/screens/pointage/pointage_kiosk_screen.dart
// Écran de pointage. Selon l'appareil :
// - Sunmi avec service d'identification : l'employé pose son doigt, il est reconnu ;
// - lecteur Android : l'employé choisit son nom puis confirme avec son empreinte ;
// - sans lecteur : l'employé choisit son nom puis saisit son code PIN.
// Option badge (réglage administrateur) : l'employé scanne son badge (scanner Sunmi ou caméra),
// seul ou en complément de l'empreinte / du PIN, avec si besoin le code PIN après le badge.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/pointage/pointage_logic.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/screens/common/camera_scan_screen.dart';
import 'package:prestige_vente_app/services/fingerprint_service.dart';
import 'package:prestige_vente_app/services/nfc_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:uuid/uuid.dart';

/// Vérifications remplaçables pour les tests.
class PointageVerifier {
  /// Confirmation par empreinte Android. true = reconnue, false = annulée ; exception = indisponible.
  final Future<bool> Function(Employee e) confirmFingerprint;

  /// Identification Sunmi : renvoie l'employé dont l'empreinte correspond, ou null.
  final Future<Employee?> Function(List<Employee> candidates) identify;

  const PointageVerifier({required this.confirmFingerprint, required this.identify});

  static final device = PointageVerifier(
    confirmFingerprint: (e) => FingerprintService.authenticate(title: 'Pointage', subtitle: e.name),
    identify: (candidates) async {
      final templates = <Uint8List>[];
      final owners = <Employee>[];
      for (final e in candidates) {
        for (final t in e.fingerprintTemplates) {
          templates.add(base64Decode(t));
          owners.add(e);
        }
      }
      if (templates.isEmpty) throw const FingerprintException('NO_TEMPLATE', 'Aucune empreinte enregistrée pour les employés.');
      await FingerprintService.connect();
      await FingerprintService.engage();
      final m = await FingerprintService.identify(templates);
      return m.found ? owners[m.index] : null;
    },
  );
}

class PointageKioskScreen extends StatefulWidget {
  final PointageRepository repository;
  final DeviceCapability capability;
  final PointageSettings settings;
  final PointageVerifier? verifier;
  final DateTime Function()? clock;

  /// Lecture du badge par la caméra (remplaçable pour les tests).
  final Future<String?> Function(BuildContext context)? badgeCamera;

  /// Lecteur de badges NFC (remplaçable pour les tests).
  final NfcReader nfc;

  /// Présentation (A, B, C) ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;

  const PointageKioskScreen({
    super.key,
    required this.repository,
    required this.capability,
    this.settings = const PointageSettings(),
    this.verifier,
    this.clock,
    this.badgeCamera,
    this.nfc = const DeviceNfcReader(),
    this.presentation,
  });

  @override
  State<PointageKioskScreen> createState() => _PointageKioskScreenState();
}

class _PointageKioskScreenState extends State<PointageKioskScreen> with WidgetsBindingObserver, PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  List<Employee> _employees = [];
  List<PointageRecord> _today = [];
  String _filter = '';
  bool _busy = false;
  String? _lastMessage;

  // Badge : le scanner Sunmi "tape" le code dans ce champ (sans afficher le clavier).
  final _badgeController = TextEditingController();
  final _badgeFocus = FocusNode();
  Timer? _badgeDebounce;
  bool _badgeKeyboard = false;

  // Badge NFC
  NfcAvailability? _nfcState;
  StreamSubscription<String>? _nfcSub;

  /// Un badge est en cours de traitement (PIN, choix de l'action) : les lectures suivantes sont ignorées.
  bool _badgeFlow = false;

  PointageVerifier get _verifier => widget.verifier ?? PointageVerifier.device;
  DateTime _now() => (widget.clock ?? DateTime.now)();
  static final _hm = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _reload();
    if (widget.settings.badgeEnabled) {
      WidgetsBinding.instance.addObserver(this);
      _initNfc();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour des réglages Android (NFC activé ?) : on revérifie.
    if (state == AppLifecycleState.resumed && _nfcState != NfcAvailability.ready) _initNfc();
  }

  Future<void> _initNfc() async {
    final state = await widget.nfc.availability();
    if (!mounted) return;
    setState(() => _nfcState = state);
    if (state != NfcAvailability.ready) return;
    _nfcSub ??= widget.nfc.tags.listen(_onNfc);
    await widget.nfc.start();
  }

  @override
  void dispose() {
    if (widget.settings.badgeEnabled) {
      WidgetsBinding.instance.removeObserver(this);
      _nfcSub?.cancel();
      widget.nfc.stop();
    }
    _badgeDebounce?.cancel();
    _badgeController.dispose();
    _badgeFocus.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final now = _now();
    final start = DateTime(now.year, now.month, now.day);
    final emps = (await widget.repository.loadEmployees()).where((e) => e.active).toList();
    final recs = await widget.repository.loadRecords(from: start, to: start.add(const Duration(days: 1)));
    if (mounted) {
      setState(() {
        _employees = emps;
        _today = recs;
      });
    }
  }

  List<PointageRecord> _todayOf(Employee e) => _today.where((r) => r.employeeId == e.id).toList();

  // ---------------------------------------------------------------------------
  // Identification de l'employé
  // ---------------------------------------------------------------------------
  Future<void> _identifyBySunmi() async {
    setState(() => _busy = true);
    try {
      final e = await _verifier.identify(_employees);
      if (!mounted) return;
      setState(() => _busy = false);
      if (e == null) {
        _toast('Empreinte non reconnue. Réessayez ou demandez l\'enregistrement de votre empreinte.', error: true);
      } else {
        await _chooseAction(e, PointageMethod.sunmiFingerprint);
      }
    } catch (e) {
      if (mounted) _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onEmployeeTap(Employee e) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      PointageMethod? method;
      if (widget.capability.mode == PointageMode.androidBiometric) {
        try {
          final ok = await _verifier.confirmFingerprint(e);
          if (mounted) setState(() => _busy = false);
          if (!ok) return; // annulé
          method = PointageMethod.androidBiometric;
        } on FingerprintException catch (err) {
          if (mounted) setState(() => _busy = false);
          // Lecteur indisponible (bloqué, aucune empreinte...) : repli sur le code PIN.
          if (!e.hasPin) {
            _toast('Empreinte indisponible (${err.message}) et aucun code PIN défini pour ${e.name}.', error: true);
            return;
          }
          if (!await _askPin(e)) return;
          method = PointageMethod.pin;
        }
      } else if (e.hasPin) {
        setState(() => _busy = false);
        if (!await _askPin(e)) return;
        method = PointageMethod.pin;
      } else {
        method = PointageMethod.manual;
      }
      if (mounted) setState(() => _busy = false);
      if (mounted) await _chooseAction(e, method);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Badge
  // ---------------------------------------------------------------------------
  void _onBadgeChanged(String value) {
    _badgeDebounce?.cancel();
    // Saisie au clavier : on attend "Entrée". Scanner : le code arrive d'un coup, on valide après une courte pause.
    if (_badgeKeyboard || value.trim().isEmpty) return;
    _badgeDebounce = Timer(const Duration(milliseconds: 300), () => _onBadge(_badgeController.text));
  }

  Future<void> _scanBadgeWithCamera() async {
    final value = await (widget.badgeCamera ?? (ctx) => CameraScanScreen.open(ctx, title: 'Scanner votre badge'))(context);
    if (value != null && mounted) await _onBadge(value);
  }

  Future<void> _onBadge(String raw) async {
    _badgeDebounce?.cancel();
    _badgeController.clear();
    final code = normalizeBadge(raw);
    if (code.isEmpty) return;
    await _identifiedByBadge(_employees.where((e) => e.hasBadge && normalizeBadge(e.badgeCode) == code).toList());
  }

  Future<void> _onNfc(String uid) async {
    final code = normalizeBadge(uid);
    if (code.isEmpty) return;
    await _identifiedByBadge(_employees.where((e) => e.hasNfc && normalizeBadge(e.nfcUid) == code).toList());
  }

  Future<void> _identifiedByBadge(List<Employee> matches) async {
    if (_busy || _badgeFlow) return;
    _badgeFlow = true;
    try {
      if (matches.isEmpty) {
        _toast('Badge non reconnu. Demandez à l\'administrateur de l\'associer à votre fiche.', error: true);
        return;
      }
      final e = matches.first;
      var method = PointageMethod.badge;
      if (widget.settings.pinAfterBadge) {
        if (!e.hasPin) {
          _toast('Code PIN demandé après le badge, mais aucun PIN n\'est défini pour ${e.name}.', error: true);
          return;
        }
        if (!await _askPin(e)) return;
        method = PointageMethod.badgePin;
      }
      if (mounted) await _chooseAction(e, method);
    } finally {
      _badgeFlow = false;
      _refocusBadge();
    }
  }

  void _refocusBadge() {
    if (mounted && widget.settings.badgeEnabled) _badgeFocus.requestFocus();
  }

  Future<bool> _askPin(Employee e) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Code PIN — ${e.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Code PIN'),
          onSubmitted: (_) => Navigator.of(ctx).pop(controller.text == e.pin),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(controller.text == e.pin), child: const Text('Valider')),
        ],
      ),
    );
    if (ok != true && controller.text.isNotEmpty && mounted) _toast('Code PIN incorrect.', error: true);
    return ok == true;
  }

  // ---------------------------------------------------------------------------
  // Choix du pointage et enregistrement
  // ---------------------------------------------------------------------------
  Future<void> _chooseAction(Employee e, PointageMethod method) async {
    final now = _now();
    final mine = _todayOf(e);
    final allowed = PointageLogic.allowedNext(mine);
    final suggested = PointageLogic.suggested(e, mine, now);
    final type = await showDialog<PointageType>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_hm.format(now)} · ${method.label}', style: TextStyle(color: Colors.grey.shade700)),
            if (mine.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Aujourd\'hui : ${mine.map((r) => '${r.type.label} ${_hm.format(r.time)}').join(' · ')}',
                  style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 16),
            for (final t in allowed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: t == suggested
                      ? ElevatedButton(onPressed: () => Navigator.of(ctx).pop(t), child: Text(t.label, style: const TextStyle(fontSize: 18)))
                      : OutlinedButton(onPressed: () => Navigator.of(ctx).pop(t), child: Text(t.label, style: const TextStyle(fontSize: 18))),
                ),
              ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler'))],
      ),
    );
    if (type == null || !mounted) return;
    final record = PointageRecord(
      id: const Uuid().v4(),
      employeeId: e.id,
      type: type,
      time: _now(),
      method: method,
      device: widget.capability.device,
    );
    await widget.repository.addRecord(record);
    await _reload();
    if (!mounted) return;
    final greet = type == PointageType.arrivee ? 'Bonjour' : (type == PointageType.depart ? 'Au revoir' : '');
    _toast('${type.label} enregistrée à ${_hm.format(record.time)}${greet.isEmpty ? '' : ' — $greet ${e.name}'}');
  }

  void _toast(String message, {bool error = false}) {
    setState(() => _lastMessage = message);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontSize: 16)),
      backgroundColor: error ? AppColors.error : Colors.green.shade700,
      duration: const Duration(seconds: 4),
    ));
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final byId = {for (final e in _employees) e.id: e};
    final present = _employees.where((e) {
      final mine = _todayOf(e);
      return mine.isNotEmpty && mine.last.type != PointageType.depart;
    }).length;
    return PresentationScaffold(
      style: style,
      title: 'Pointage',
      subtitle: widget.settings.badgeMode == BadgeMode.only ? 'Badge' : widget.capability.modeLabel,
      actions: (_) => const [],
      steps: StepsBar(active: 0, steps: const [
        (title: 'S\'identifier', detail: 'badge, doigt, nom', onTap: null),
        (title: 'Choisir', detail: 'arrivée, pause...', onTap: null),
        (title: 'Enregistré', detail: 'heure exacte', onTap: null),
      ]),
      header: [
        if (style == ListPresentation.dashboard)
          Row(children: [
            Expanded(child: KpiTile('$present', 'présent(s)')),
            const SizedBox(width: 8),
            Expanded(child: KpiTile('${_today.length}', 'pointage(s) du jour')),
            const SizedBox(width: 8),
            Expanded(child: KpiTile('${_employees.length}', 'employé(s)', highlight: true)),
          ]),
      ],
      compactHeader: const [],
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (widget.settings.badgeMode == BadgeMode.both) _buildBadgeZone(compact: true),
          Expanded(
            child: switch (widget.settings.badgeMode) {
              BadgeMode.only => _buildBadgeZone(compact: false),
              _ => widget.capability.mode == PointageMode.sunmiIdentify ? _buildSunmi() : _buildEmployeeList(),
            },
          ),
          if (_today.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Pal.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.history, size: 18, color: Pal.navy),
                    SizedBox(width: 6),
                    Text('Derniers pointages', style: TextStyle(fontWeight: FontWeight.bold, color: Pal.ink)),
                  ]),
                  const SizedBox(height: 4),
                  for (final r in _today.reversed.take(4))
                    Text('${_hm.format(r.time)}  ${byId[r.employeeId]?.name ?? '?'} — ${r.type.label}',
                        style: const TextStyle(color: Pal.muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _fieldDeco(String label, IconData icon, {Widget? suffix}) => InputDecoration(
        prefixIcon: Icon(icon),
        labelText: label,
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC5D0DE))),
      );

  Widget _bigIcon(IconData icon) => Container(
        width: 120,
        height: 120,
        decoration: const BoxDecoration(color: Color(0xFFE3ECF7), shape: BoxShape.circle),
        child: Icon(icon, size: 64, color: Pal.navy),
      );

  Widget _buildBadgeZone({required bool compact}) {
    final field = TextField(
      controller: _badgeController,
      focusNode: _badgeFocus,
      autofocus: true,
      // Sans clavier à l'écran : le scanner Sunmi saisit le code directement.
      keyboardType: _badgeKeyboard ? TextInputType.text : TextInputType.none,
      decoration: _fieldDeco(
        'Scannez votre badge',
        Icons.badge,
        suffix: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.photo_camera),
              tooltip: 'Scanner le badge (caméra)',
              onPressed: _busy ? null : _scanBadgeWithCamera,
            ),
            IconButton(
              icon: Icon(_badgeKeyboard ? Icons.keyboard_hide : Icons.keyboard),
              tooltip: 'Saisir le code du badge',
              onPressed: () {
                setState(() => _badgeKeyboard = !_badgeKeyboard);
                _badgeFocus.unfocus();
                Future.microtask(() => _badgeFocus.requestFocus());
              },
            ),
          ],
        ),
      ),
      onChanged: _onBadgeChanged,
      onSubmitted: _onBadge,
    );
    final nfcLine = _nfcLine();
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(mainAxisSize: MainAxisSize.min, children: [field, if (nfcLine != null) nfcLine]),
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bigIcon(Icons.badge),
            const SizedBox(height: 16),
            const Text('Présentez votre badge au scanner\nou touchez l\'appareil photo',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Pal.ink), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            field,
            if (nfcLine != null) nfcLine,
            if (_lastMessage != null) ...[
              const SizedBox(height: 16),
              Text(_lastMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted)),
            ],
          ],
        ),
      ),
    );
  }

  /// État du NFC sous le champ badge (rien si l'appareil n'a pas de NFC).
  Widget? _nfcLine() => switch (_nfcState) {
        NfcAvailability.ready => const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.nfc, color: AppColors.primary),
                SizedBox(width: 8),
                Flexible(child: Text('Badge NFC : approchez-le du dos de l\'appareil')),
              ],
            ),
          ),
        NfcAvailability.disabled => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.nfc, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                const Flexible(child: Text('NFC désactivé')),
                TextButton(onPressed: widget.nfc.openSettings, child: const Text('Activer')),
              ],
            ),
          ),
        _ => null,
      };

  Widget _buildSunmi() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bigIcon(Icons.fingerprint),
            const SizedBox(height: 16),
            const Text('Posez votre doigt sur le lecteur',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Pal.ink), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                style: style == ListPresentation.guided ? amberButton : navyButton,
                icon: const Icon(Icons.touch_app, size: 28),
                label: const Text('Pointer', style: TextStyle(fontSize: 20)),
                onPressed: _busy ? null : _identifyBySunmi,
              ),
            ),
            if (_lastMessage != null) ...[
              const SizedBox(height: 16),
              Text(_lastMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeList() {
    if (_employees.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucun employé. Ajoutez-les dans « Employés » (accès administrateur).', textAlign: TextAlign.center),
        ),
      );
    }
    final f = _filter.toLowerCase();
    final list = _employees.where((e) => f.isEmpty || e.name.toLowerCase().contains(f) || e.matricule.toLowerCase().contains(f)).toList();
    final compact = style == ListPresentation.compact;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            decoration: _fieldDeco('Votre nom ou matricule', Icons.search),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(compact ? 0 : 12, 6, compact ? 0 : 12, 12),
            itemCount: list.length,
            separatorBuilder: (_, __) => SizedBox(height: compact ? 0 : 8),
            itemBuilder: (_, i) {
              final e = list[i];
              final mine = _todayOf(e);
              final status = mine.isEmpty ? 'Pas encore pointé' : '${mine.last.type.label} à ${_hm.format(mine.last.time)}';
              final inside = mine.isNotEmpty && mine.last.type != PointageType.depart;
              final row = Row(children: [
                Stack(clipBehavior: Clip.none, children: [
                  GrossisteAvatar(e.name.isEmpty ? '?' : e.name),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: inside ? Pal.green : const Color(0xFFB8C2D0),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Pal.ink)),
                    Text(status, style: TextStyle(fontSize: 13, color: inside ? Colors.green.shade800 : Pal.muted)),
                  ]),
                ),
                Icon(widget.capability.mode == PointageMode.androidBiometric ? Icons.fingerprint : Icons.pin, color: Pal.navy),
              ]);
              if (compact) {
                return InkWell(
                  onTap: _busy ? null : () => _onEmployeeTap(e),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
                    child: row,
                  ),
                );
              }
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _busy ? null : () => _onEmployeeTap(e),
                child: SoftCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: row),
              );
            },
          ),
        ),
      ],
    );
  }
}
