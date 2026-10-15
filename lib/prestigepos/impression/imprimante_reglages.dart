// lib/prestigepos/impression/imprimante_reglages.dart
// PrestigePOS — réglages de l'imprimante de ticket de CET appareil (SharedPreferences, aucun secret) :
// type (automatique : Sunmi intégrée détectée, Bluetooth, USB, réseau, aucune), papier 58 / 80 mm,
// appareil choisi, appareils Bluetooth mémorisés (« Ajouter »), QR natif ou image, jeu de caractères, coupe.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/prestigepos/impression/escpos.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TypeImprimante { automatique, sunmi, bluetooth, usb, reseau, aucune }

extension TypeImprimanteInfo on TypeImprimante {
  String get label => switch (this) {
        TypeImprimante.automatique => 'Automatique (Sunmi intégrée si présente)',
        TypeImprimante.sunmi => 'Imprimante intégrée Sunmi',
        TypeImprimante.bluetooth => 'Bluetooth',
        TypeImprimante.usb => 'USB (câble OTG)',
        TypeImprimante.reseau => 'Réseau (Wi-Fi / Ethernet)',
        TypeImprimante.aucune => 'Aucune (ticket affiché à l\'écran)',
      };

  /// Imprimante ESC/POS externe (Bluetooth, USB, réseau).
  bool get externe => this == TypeImprimante.bluetooth || this == TypeImprimante.usb || this == TypeImprimante.reseau;
}

/// Appareil (imprimante Bluetooth ou USB) trouvé ou mémorisé.
@immutable
class AppareilImprimante {
  final String nom;

  /// Bluetooth : adresse MAC (« 00:11:22:AA:BB:CC ») ; USB : « vendorId:productId » (décimal).
  final String adresse;

  /// Appairé dans Android (Bluetooth) ; classe « imprimante » annoncée par l'appareil.
  final bool appaire;
  final bool imprimante;
  const AppareilImprimante({required this.nom, required this.adresse, this.appaire = false, this.imprimante = false});

  String get libelle => nom.trim().isEmpty ? adresse : nom.trim();

  /// USB : identifiants (vendorId, productId) ; null si l'adresse n'est pas « v:p ».
  (int, int)? get usbIds {
    final p = adresse.split(':');
    if (p.length != 2) return null;
    final v = int.tryParse(p[0]), pr = int.tryParse(p[1]);
    return v == null || pr == null ? null : (v, pr);
  }

  static final _mac = RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$');

  /// Adresse Bluetooth valide (format MAC, majuscules).
  static bool adresseBluetoothValide(String a) => _mac.hasMatch(a.trim().toUpperCase());

  Map<String, dynamic> toJson() => {'nom': nom, 'adresse': adresse, 'appaire': appaire, 'imprimante': imprimante};

  static AppareilImprimante? fromJson(Object? j) {
    if (j is! Map) return null;
    final a = '${j['adresse'] ?? ''}'.trim();
    if (a.isEmpty) return null;
    final nom = '${j['nom'] ?? ''}'.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    return AppareilImprimante(
        nom: nom.length > 40 ? nom.substring(0, 40) : nom, adresse: a, appaire: j['appaire'] == true, imprimante: j['imprimante'] == true);
  }

  @override
  bool operator ==(Object other) => other is AppareilImprimante && other.adresse.toUpperCase() == adresse.toUpperCase();
  @override
  int get hashCode => adresse.toUpperCase().hashCode;

  @override
  String toString() => '$libelle ($adresse)';
}

@immutable
class ImprimanteConfig {
  final TypeImprimante type;

  /// Largeur du papier : 58 ou 80 mm.
  final int papier;

  /// Imprimante Bluetooth choisie (null : aucune).
  final AppareilImprimante? bluetooth;

  /// Imprimantes Bluetooth mémorisées (« Ajouter »), la choisie comprise.
  final List<AppareilImprimante> memorisees;

  /// Imprimante USB choisie (« vendorId:productId »).
  final AppareilImprimante? usb;

  /// Imprimante réseau : adresse IP (ou nom) et port (9100 par défaut, « RAW »).
  final String hote;
  final int port;

  final ModeQr qr;
  final JeuCaracteres jeu;

  /// Coupe du papier en fin de ticket (imprimantes à couteau).
  final bool coupe;

  static const int portDefaut = 9100;
  static const int maxMemorisees = 8;

  const ImprimanteConfig({
    this.type = TypeImprimante.automatique,
    this.papier = 58,
    this.bluetooth,
    this.memorisees = const [],
    this.usb,
    this.hote = '',
    this.port = portDefaut,
    this.qr = ModeQr.natif,
    this.jeu = JeuCaracteres.ascii,
    this.coupe = true,
  });

  /// Imprimante choisie complète (Bluetooth avec appareil, USB avec appareil, réseau avec adresse).
  bool get complete => switch (type) {
        TypeImprimante.bluetooth => bluetooth != null && AppareilImprimante.adresseBluetoothValide(bluetooth!.adresse),
        TypeImprimante.usb => usb?.usbIds != null,
        TypeImprimante.reseau => hote.trim().isNotEmpty && port > 0 && port < 65536,
        _ => true,
      };

  /// Résumé affiché (« Bluetooth · MTP-II · 58 mm »).
  String get resume => switch (type) {
        TypeImprimante.bluetooth => 'Bluetooth · ${bluetooth?.libelle ?? 'à choisir'} · $papier mm',
        TypeImprimante.usb => 'USB · ${usb?.libelle ?? 'à choisir'} · $papier mm',
        TypeImprimante.reseau => 'Réseau · ${hote.isEmpty ? 'adresse à saisir' : '$hote:$port'} · $papier mm',
        TypeImprimante.sunmi => 'Sunmi intégrée',
        TypeImprimante.automatique => 'Automatique (Sunmi intégrée si présente)',
        TypeImprimante.aucune => 'Aucune : ticket à l\'écran',
      };

  /// Valeurs bornées (une valeur absurde enregistrée ne casse jamais l'impression).
  ImprimanteConfig normalisee() {
    final vus = <String>{};
    final mem = <AppareilImprimante>[
      for (final a in memorisees)
        if (AppareilImprimante.adresseBluetoothValide(a.adresse) && vus.add(a.adresse.toUpperCase()))
          AppareilImprimante(nom: a.nom, adresse: a.adresse.toUpperCase(), appaire: a.appaire, imprimante: a.imprimante)
    ];
    final h = hote.trim().replaceAll(RegExp(r'^[a-zA-Z]+://'), '').replaceAll(RegExp(r'[/\s].*$'), '');
    return ImprimanteConfig(
      type: type,
      papier: papier == 80 ? 80 : 58,
      bluetooth: bluetooth == null || !AppareilImprimante.adresseBluetoothValide(bluetooth!.adresse)
          ? null
          : AppareilImprimante(nom: bluetooth!.nom, adresse: bluetooth!.adresse.toUpperCase(), appaire: bluetooth!.appaire, imprimante: bluetooth!.imprimante),
      memorisees: mem.length > maxMemorisees ? mem.sublist(mem.length - maxMemorisees) : mem,
      usb: usb?.usbIds == null ? null : usb,
      hote: h.length > 120 ? h.substring(0, 120) : h,
      port: port > 0 && port < 65536 ? port : portDefaut,
      qr: qr,
      jeu: jeu,
      coupe: coupe,
    );
  }

  /// « Ajouter » : l'appareil devient l'imprimante Bluetooth choisie et rejoint les mémorisées.
  ImprimanteConfig ajouterBluetooth(AppareilImprimante a) => copyWith(
        type: TypeImprimante.bluetooth,
        bluetooth: a,
        memorisees: [...memorisees.where((m) => m != a), a],
      ).normalisee();

  /// Oublie une imprimante mémorisée (et la choisie si c'est elle).
  ImprimanteConfig oublierBluetooth(AppareilImprimante a) => ImprimanteConfig(
        type: type,
        papier: papier,
        bluetooth: bluetooth == a ? null : bluetooth,
        memorisees: memorisees.where((m) => m != a).toList(),
        usb: usb,
        hote: hote,
        port: port,
        qr: qr,
        jeu: jeu,
        coupe: coupe,
      );

  ImprimanteConfig copyWith({
    TypeImprimante? type,
    int? papier,
    AppareilImprimante? bluetooth,
    List<AppareilImprimante>? memorisees,
    AppareilImprimante? usb,
    String? hote,
    int? port,
    ModeQr? qr,
    JeuCaracteres? jeu,
    bool? coupe,
  }) =>
      ImprimanteConfig(
        type: type ?? this.type,
        papier: papier ?? this.papier,
        bluetooth: bluetooth ?? this.bluetooth,
        memorisees: memorisees ?? this.memorisees,
        usb: usb ?? this.usb,
        hote: hote ?? this.hote,
        port: port ?? this.port,
        qr: qr ?? this.qr,
        jeu: jeu ?? this.jeu,
        coupe: coupe ?? this.coupe,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'papier': papier,
        if (bluetooth != null) 'bluetooth': bluetooth!.toJson(),
        'memorisees': [for (final m in memorisees) m.toJson()],
        if (usb != null) 'usb': usb!.toJson(),
        'hote': hote,
        'port': port,
        'qr': qr.name,
        'jeu': jeu.name,
        'coupe': coupe,
      };

  static ImprimanteConfig fromJson(Map<String, dynamic> j) {
    int i(Object? v, int d) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;
    final mem = j['memorisees'];
    return ImprimanteConfig(
      type: TypeImprimante.values.asNameMap()['${j['type']}'] ?? TypeImprimante.automatique,
      papier: i(j['papier'], 58),
      bluetooth: AppareilImprimante.fromJson(j['bluetooth']),
      memorisees: mem is List ? mem.map(AppareilImprimante.fromJson).whereType<AppareilImprimante>().toList() : const [],
      usb: AppareilImprimante.fromJson(j['usb']),
      hote: '${j['hote'] ?? ''}',
      port: i(j['port'], portDefaut),
      qr: ModeQr.values.asNameMap()['${j['qr']}'] ?? ModeQr.natif,
      jeu: JeuCaracteres.values.asNameMap()['${j['jeu']}'] ?? JeuCaracteres.ascii,
      coupe: j['coupe'] != false,
    ).normalisee();
  }
}

/// Réglages de l'imprimante de cet appareil.
class ImprimanteReglages {
  ImprimanteReglages._();
  static const cle = 'prestigepos_imprimante_v1';

  static final ValueNotifier<ImprimanteConfig> courant = ValueNotifier(const ImprimanteConfig());

  static Future<ImprimanteConfig> charger() async {
    try {
      final s = (await SharedPreferences.getInstance()).getString(cle);
      courant.value = s == null ? const ImprimanteConfig() : ImprimanteConfig.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
    } catch (_) {
      courant.value = const ImprimanteConfig();
    }
    return courant.value;
  }

  static Future<void> enregistrer(ImprimanteConfig c) async {
    final n = c.normalisee();
    courant.value = n;
    try {
      await (await SharedPreferences.getInstance()).setString(cle, jsonEncode(n.toJson()));
    } catch (_) {}
  }
}
