// lib/pointage/pointage_models.dart
// Pointage de présence : employés et enregistrements.

enum PointageType { arrivee, debutPause, finPause, depart }

extension PointageTypeLabel on PointageType {
  String get label => switch (this) {
        PointageType.arrivee => 'Arrivée',
        PointageType.debutPause => 'Début pause',
        PointageType.finPause => 'Fin pause',
        PointageType.depart => 'Départ',
      };
}

/// Comment l'employé a été reconnu.
enum PointageMethod {
  /// Empreinte identifiée par le service Sunmi (la personne est reconnue par son doigt).
  sunmiFingerprint,

  /// Nom choisi + empreinte confirmée par Android (confirme "une empreinte enregistrée").
  androidBiometric,

  /// Nom choisi + code PIN.
  pin,

  /// Nom choisi sans vérification (appareil sans lecteur, employé sans PIN).
  manual,
}

extension PointageMethodLabel on PointageMethod {
  String get label => switch (this) {
        PointageMethod.sunmiFingerprint => 'Empreinte (identifiée)',
        PointageMethod.androidBiometric => 'Nom + empreinte',
        PointageMethod.pin => 'Nom + PIN',
        PointageMethod.manual => 'Nom seul',
      };
}

class Employee {
  final String id;
  final String name;
  final String matricule;
  final String? pin;

  /// Horaires prévus "HH:mm".
  final String scheduleStart;
  final String scheduleEnd;

  /// Jours travaillés : 1 = lundi ... 7 = dimanche.
  final List<int> workdays;

  /// Tolérance de retard en minutes.
  final int toleranceMinutes;

  /// Gabarits d'empreinte Sunmi (base64), si enregistrés sur un terminal compatible.
  final List<String> fingerprintTemplates;
  final bool active;

  const Employee({
    required this.id,
    required this.name,
    this.matricule = '',
    this.pin,
    this.scheduleStart = '08:00',
    this.scheduleEnd = '17:00',
    this.workdays = const [1, 2, 3, 4, 5, 6],
    this.toleranceMinutes = 10,
    this.fingerprintTemplates = const [],
    this.active = true,
  });

  bool get hasPin => pin != null && pin!.isNotEmpty;

  /// Minutes depuis minuit pour "HH:mm".
  static int minutesOf(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + (p.length > 1 ? int.parse(p[1]) : 0);
  }

  int get startMinutes => minutesOf(scheduleStart);
  int get endMinutes => minutesOf(scheduleEnd);

  Employee copyWith({
    String? name,
    String? matricule,
    String? pin,
    bool clearPin = false,
    String? scheduleStart,
    String? scheduleEnd,
    List<int>? workdays,
    int? toleranceMinutes,
    List<String>? fingerprintTemplates,
    bool? active,
  }) =>
      Employee(
        id: id,
        name: name ?? this.name,
        matricule: matricule ?? this.matricule,
        pin: clearPin ? null : (pin ?? this.pin),
        scheduleStart: scheduleStart ?? this.scheduleStart,
        scheduleEnd: scheduleEnd ?? this.scheduleEnd,
        workdays: workdays ?? this.workdays,
        toleranceMinutes: toleranceMinutes ?? this.toleranceMinutes,
        fingerprintTemplates: fingerprintTemplates ?? this.fingerprintTemplates,
        active: active ?? this.active,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'matricule': matricule,
        'pin': pin,
        'scheduleStart': scheduleStart,
        'scheduleEnd': scheduleEnd,
        'workdays': workdays,
        'toleranceMinutes': toleranceMinutes,
        'fingerprintTemplates': fingerprintTemplates,
        'active': active,
      };

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        matricule: j['matricule'] as String? ?? '',
        pin: j['pin'] as String?,
        scheduleStart: j['scheduleStart'] as String? ?? '08:00',
        scheduleEnd: j['scheduleEnd'] as String? ?? '17:00',
        workdays: (j['workdays'] as List?)?.map((e) => e as int).toList() ?? const [1, 2, 3, 4, 5, 6],
        toleranceMinutes: j['toleranceMinutes'] as int? ?? 10,
        fingerprintTemplates: (j['fingerprintTemplates'] as List?)?.map((e) => e as String).toList() ?? const [],
        active: j['active'] as bool? ?? true,
      );
}

class PointageRecord {
  final String id;
  final String employeeId;
  final PointageType type;
  final DateTime time;
  final PointageMethod method;
  final String device;

  /// Envoyé au serveur Prestige (synchronisation à venir).
  final bool synced;

  const PointageRecord({
    required this.id,
    required this.employeeId,
    required this.type,
    required this.time,
    required this.method,
    this.device = '',
    this.synced = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'type': type.name,
        'time': time.toIso8601String(),
        'method': method.name,
        'device': device,
        'synced': synced,
      };

  factory PointageRecord.fromJson(Map<String, dynamic> j) => PointageRecord(
        id: j['id'] as String,
        employeeId: j['employeeId'] as String,
        type: PointageType.values.byName(j['type'] as String),
        time: DateTime.parse(j['time'] as String),
        method: PointageMethod.values.byName(j['method'] as String),
        device: j['device'] as String? ?? '',
        synced: j['synced'] as bool? ?? false,
      );
}
