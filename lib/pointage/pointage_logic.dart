// lib/pointage/pointage_logic.dart
// Choix du mode de pointage selon l'appareil, et enchaînement des pointages d'une journée.
import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:prestige_vente_app/services/fingerprint_service.dart';

enum PointageMode {
  /// Terminal Sunmi avec service d'identification : le doigt désigne l'employé.
  sunmiIdentify,

  /// Lecteur Android standard : l'employé choisit son nom puis confirme avec son empreinte.
  androidBiometric,

  /// Pas de lecteur utilisable : nom + code PIN.
  pinOrName,
}

class DeviceCapability {
  final PointageMode mode;
  final String device;
  final bool isSunmi;
  final bool hasReader;

  /// Au moins une empreinte enregistrée dans les Paramètres Android.
  final bool readerReady;
  final bool sunmiService;

  const DeviceCapability({
    required this.mode,
    this.device = '',
    this.isSunmi = false,
    this.hasReader = false,
    this.readerReady = false,
    this.sunmiService = false,
  });

  String get modeLabel => switch (mode) {
        PointageMode.sunmiIdentify => 'Empreinte identifiée (Sunmi)',
        PointageMode.androidBiometric => 'Nom + empreinte',
        PointageMode.pinOrName => 'Nom + code PIN',
      };

  String get explanation => switch (mode) {
        PointageMode.sunmiIdentify => 'L\'employé pose son doigt : le terminal le reconnaît.',
        PointageMode.androidBiometric => 'L\'employé choisit son nom, puis confirme avec l\'empreinte '
            'enregistrée dans les Paramètres de l\'appareil.',
        PointageMode.pinOrName => hasReader
            ? 'Lecteur présent mais aucune empreinte enregistrée dans les Paramètres : pointage par nom + code PIN.'
            : 'Aucun lecteur d\'empreinte : pointage par nom + code PIN.',
      };

  /// Analyse de l'appareil (lecteur Android, service Sunmi).
  static Future<DeviceCapability> detect() async {
    Map<String, Object?> hw = const {};
    try {
      hw = await FingerprintService.hardwareInfo();
    } catch (_) {}
    final manufacturer = '${hw['manufacturer'] ?? ''}';
    final device = '$manufacturer ${hw['model'] ?? ''}'.trim();
    final isSunmi = manufacturer.toUpperCase().contains('SUNMI');
    final hasReader = hw['featureFingerprint'] == true;
    final readerReady = hasReader && hw['biometricStatus'] == 0;
    final services = (hw['sunmiServices'] as List?) ?? const [];
    final sunmiService = services.isNotEmpty || await FingerprintService.isServiceInstalled();

    final mode = sunmiService
        ? PointageMode.sunmiIdentify
        : readerReady
            ? PointageMode.androidBiometric
            : PointageMode.pinOrName;
    return DeviceCapability(
      mode: mode,
      device: device,
      isSunmi: isSunmi,
      hasReader: hasReader,
      readerReady: readerReady,
      sunmiService: sunmiService,
    );
  }
}

class PointageLogic {
  PointageLogic._();

  static bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Pointages autorisés après le dernier pointage de la journée, le premier étant le plus probable.
  static List<PointageType> allowedNext(List<PointageRecord> dayRecordsOfEmployee) {
    if (dayRecordsOfEmployee.isEmpty) return const [PointageType.arrivee];
    final last = (List.of(dayRecordsOfEmployee)..sort((a, b) => a.time.compareTo(b.time))).last.type;
    return switch (last) {
      PointageType.arrivee || PointageType.finPause => const [PointageType.depart, PointageType.debutPause],
      PointageType.debutPause => const [PointageType.finPause],
      PointageType.depart => const [PointageType.arrivee],
    };
  }

  /// Pointage proposé selon l'état de la journée et l'heure : en journée après une arrivée,
  /// on propose le départ seulement à partir de l'heure de fin prévue moins 1 h, sinon la pause.
  static PointageType suggested(Employee e, List<PointageRecord> dayRecords, DateTime now) {
    final allowed = allowedNext(dayRecords);
    if (allowed.length == 1) return allowed.first;
    final minutes = now.hour * 60 + now.minute;
    return minutes >= e.endMinutes - 60 ? PointageType.depart : PointageType.debutPause;
  }
}
