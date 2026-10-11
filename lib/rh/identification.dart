// lib/rh/identification.dart
// Voie B — identification de l'employé sur le terminal de pointage (cible : SUNMI V3H), dans l'ordre :
//   1. EMPREINTE (lecteur capacitif optionnel du V3H, service d'empreinte Sunmi : identification 1:N) ;
//   2. SCAN du badge (lecteur 2D intégré Sunmi, qui « tape » le code comme un clavier + Entrée ; lecteur USB /
//      Bluetooth ; ou caméra) ;
//   3. badge NFC sans contact (UID de la carte, hexadécimal MAJUSCULE sans séparateur, ex. « 04A1B2C3D4E5F6 »,
//      comparé au champ `badge` de l'employé dans Prestige) ;
//   4. saisie au clavier (code du badge / matricule), toujours possible.
//
// EMPREINTE : l'API Android standard (BiometricPrompt) ne sait PAS dire QUI pose le doigt (elle ne vérifie que
// le propriétaire de l'appareil) : elle est inutilisable ici. On utilise le SDK du service d'empreinte Sunmi
// (android/app/libs/libsunmifingeprint_v1.0.0.aar, déjà intégré pour le pointage local), via le pont natif
// existant SunmiFingerprintBridge (canal `prestige/fingerprint` : enroll → modèle, identify(modèles) → index).
// Service absent (terminal sans lecteur, autre marque) : « indisponible » proprement → repli badge / NFC.
//
// Les MODÈLES d'empreinte restent UNIQUEMENT sur le terminal : stockage sécurisé (Keystore, exclu des
// sauvegardes Android), associés à l'employeId, jamais envoyés au serveur (qui n'a pas de stockage
// d'empreintes). Ceux d'un employé devenu INACTIF sont supprimés à la mise à jour de la liste des employés.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/services/fingerprint_service.dart';
import 'package:prestige_vente_app/services/nfc_service.dart';

/// Moyens d'identification, dans l'ordre de préférence.
enum MoyenIdentification { empreinte, scan, nfc, clavier }

extension MoyenIdentificationInfo on MoyenIdentification {
  String get label => switch (this) {
        MoyenIdentification.empreinte => 'Empreinte',
        MoyenIdentification.scan => 'Scan du badge',
        MoyenIdentification.nfc => 'Badge NFC',
        MoyenIdentification.clavier => 'Saisie au clavier',
      };

  /// Motif envoyé à Prestige : « <Moyen> terminal <nom du terminal> ».
  String motif(String nomTerminal) {
    final n = nomTerminal.trim().isEmpty ? 'Prestige Mobile' : nomTerminal.trim();
    final m = '${this == MoyenIdentification.empreinte ? 'Empreinte' : 'Badge'} terminal $n';
    return m.length > 250 ? m.substring(0, 250) : m;
  }
}

/// UID NFC lu → format à saisir dans Prestige (hexadécimal majuscule, sans espace ni « : »).
String normaliserUidNfc(String uid) => uid.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();

// ---------------------------------------------------------------------------
// Fournisseur d'empreinte
// ---------------------------------------------------------------------------

class EmpreinteIndisponible implements Exception {
  final String message;
  const EmpreinteIndisponible([this.message = 'Lecteur d\'empreinte indisponible sur ce terminal.']);
  @override
  String toString() => message;
}

/// Lecteur d'empreinte capable d'IDENTIFIER (1:N) — remplaçable pour les tests.
abstract class FournisseurEmpreinte {
  /// Lecteur et service présents (SDK Sunmi installé) ?
  Future<bool> disponible();

  /// Capture du doigt posé → modèle (gabarit) à garder sur le terminal.
  Future<Uint8List> enroler();

  /// Doigt posé comparé aux [modeles] : position du modèle reconnu, null si aucun.
  Future<int?> identifier(List<Uint8List> modeles);
  Future<void> annuler();
}

/// Service d'empreinte Sunmi (SDK intégré, pont SunmiFingerprintBridge). Toute absence → indisponible.
class SunmiEmpreinte implements FournisseurEmpreinte {
  const SunmiEmpreinte();

  @override
  Future<bool> disponible() async {
    try {
      return await FingerprintService.isServiceInstalled();
    } catch (_) {
      return false;
    }
  }

  Future<void> _pret() async {
    try {
      await FingerprintService.connect();
      await FingerprintService.engage();
    } on FingerprintException catch (e) {
      throw EmpreinteIndisponible(e.message);
    }
  }

  @override
  Future<Uint8List> enroler() async {
    await _pret();
    try {
      return await FingerprintService.enroll();
    } on FingerprintException catch (e) {
      throw EmpreinteIndisponible(e.message);
    }
  }

  @override
  Future<int?> identifier(List<Uint8List> modeles) async {
    if (modeles.isEmpty) return null;
    await _pret();
    try {
      final m = await FingerprintService.identify(modeles);
      return m.found ? m.index : null;
    } on FingerprintException catch (e) {
      throw EmpreinteIndisponible(e.message);
    }
  }

  @override
  Future<void> annuler() async {
    try {
      await FingerprintService.cancel();
    } catch (_) {}
  }
}

/// Pas de lecteur (tests, appareils sans service Sunmi).
class AucuneEmpreinte implements FournisseurEmpreinte {
  const AucuneEmpreinte();
  @override
  Future<bool> disponible() async => false;
  @override
  Future<Uint8List> enroler() => throw const EmpreinteIndisponible();
  @override
  Future<int?> identifier(List<Uint8List> modeles) => throw const EmpreinteIndisponible();
  @override
  Future<void> annuler() async {}
}

// ---------------------------------------------------------------------------
// Coffre des modèles d'empreinte (terminal uniquement)
// ---------------------------------------------------------------------------

/// Empreintes enregistrées d'un employé, avec la trace du consentement.
class EmpreintesEmploye {
  final String employeId;
  final String employeNom;
  final List<Uint8List> modeles;
  final DateTime consentementLe;

  /// Qui a recueilli le consentement (compte connecté), pour la trace.
  final String recueilliPar;
  const EmpreintesEmploye({
    required this.employeId,
    this.employeNom = '',
    required this.modeles,
    required this.consentementLe,
    this.recueilliPar = '',
  });

  Map<String, dynamic> toJson() => {
        'employeId': employeId,
        'employeNom': employeNom,
        'modeles': [for (final m in modeles) base64Encode(m)],
        'consentementLe': consentementLe.toIso8601String(),
        'recueilliPar': recueilliPar,
      };

  factory EmpreintesEmploye.fromJson(Map<String, dynamic> j) => EmpreintesEmploye(
        employeId: '${j['employeId'] ?? ''}',
        employeNom: '${j['employeNom'] ?? ''}',
        modeles: [for (final m in (j['modeles'] as List? ?? const [])) base64Decode('$m')],
        consentementLe: DateTime.tryParse('${j['consentementLe']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        recueilliPar: '${j['recueilliPar'] ?? ''}',
      );
}

abstract class CoffreEmpreintes {
  Future<Map<String, EmpreintesEmploye>> lire();
  Future<void> ecrire(Map<String, EmpreintesEmploye> tout);
}

/// Stockage sécurisé (Keystore Android, EncryptedSharedPreferences, exclu des sauvegardes : voir
/// android/app/src/main/res/xml/regles_sauvegarde*.xml).
class CoffreEmpreintesSecurise implements CoffreEmpreintes {
  static const _cle = 'prestige_rh_empreintes_v1';
  final FlutterSecureStorage _s;
  const CoffreEmpreintesSecurise([this._s = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true))]);

  @override
  Future<Map<String, EmpreintesEmploye>> lire() async {
    try {
      final v = await _s.read(key: _cle);
      if (v == null || v.isEmpty) return {};
      final j = jsonDecode(v) as Map;
      return {
        for (final e in j.entries) '${e.key}': EmpreintesEmploye.fromJson(Map<String, dynamic>.from(e.value as Map)),
      };
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> ecrire(Map<String, EmpreintesEmploye> tout) =>
      _s.write(key: _cle, value: jsonEncode({for (final e in tout.entries) e.key: e.value.toJson()}));
}

class CoffreEmpreintesMemoire implements CoffreEmpreintes {
  Map<String, EmpreintesEmploye> donnees = {};
  @override
  Future<Map<String, EmpreintesEmploye>> lire() async => Map.of(donnees);
  @override
  Future<void> ecrire(Map<String, EmpreintesEmploye> tout) async => donnees = Map.of(tout);
}

// ---------------------------------------------------------------------------
// Capacités du terminal et identification
// ---------------------------------------------------------------------------

class CapacitesTerminal {
  final bool empreinte;
  final NfcAvailability nfc;

  /// Le scanner 2D intégré (Sunmi) et les lecteurs USB / Bluetooth arrivent par la saisie clavier :
  /// toujours possibles ; la caméra aussi.
  final bool camera;
  const CapacitesTerminal({this.empreinte = false, this.nfc = NfcAvailability.absent, this.camera = true});

  /// Moyens proposés, dans l'ordre : empreinte, scan, NFC, clavier.
  List<MoyenIdentification> get ordre => [
        if (empreinte) MoyenIdentification.empreinte,
        MoyenIdentification.scan,
        if (nfc == NfcAvailability.ready) MoyenIdentification.nfc,
        MoyenIdentification.clavier,
      ];
}

/// Point unique d'identification de l'employé : fournisseurs (empreinte, NFC ; le scan et le clavier passent
/// par le champ de saisie de l'écran) et coffre des empreintes.
class IdentificationEmploye {
  final FournisseurEmpreinte empreinte;
  final NfcReader nfc;
  final CoffreEmpreintes coffre;

  IdentificationEmploye({
    this.empreinte = const SunmiEmpreinte(),
    this.nfc = const DeviceNfcReader(),
    CoffreEmpreintes? coffre,
  }) : coffre = coffre ?? const CoffreEmpreintesSecurise();

  Future<CapacitesTerminal> detecter() async {
    var e = false;
    var n = NfcAvailability.absent;
    try {
      e = await empreinte.disponible();
    } catch (_) {}
    try {
      n = await nfc.availability();
    } catch (_) {}
    return CapacitesTerminal(empreinte: e, nfc: n);
  }

  /// Employés ayant des empreintes enregistrées sur ce terminal.
  Future<Map<String, EmpreintesEmploye>> enroles() => coffre.lire();

  /// Enregistre les modèles d'un employé (après consentement explicite). Remplace les précédents.
  Future<void> enregistrer(EmpreintesEmploye e) async {
    if (e.modeles.isEmpty) throw ArgumentError('Aucune empreinte capturée.');
    final t = await coffre.lire();
    t[e.employeId] = e;
    await coffre.ecrire(t);
  }

  Future<void> supprimer(String employeId) async {
    final t = await coffre.lire();
    if (t.remove(employeId) != null) await coffre.ecrire(t);
  }

  /// Supprime les empreintes des employés absents de la liste des ACTIFS (devenus inactifs ou supprimés).
  /// Renvoie le nombre d'employés concernés.
  Future<int> purgerInactifs(Iterable<EmployeRh> actifs) async {
    final ids = {for (final e in actifs) if (e.actif) e.id};
    final t = await coffre.lire();
    final avant = t.length;
    t.removeWhere((id, _) => !ids.contains(id));
    if (t.length != avant) await coffre.ecrire(t);
    return avant - t.length;
  }

  /// Identification 1:N parmi les employés actifs enrôlés : employé reconnu, ou null.
  Future<EmployeRh?> parEmpreinte(List<EmployeRh> employes) async {
    final actifs = {for (final e in employes) if (e.actif) e.id: e};
    final modeles = <Uint8List>[];
    final proprietaires = <EmployeRh>[];
    for (final x in (await coffre.lire()).values) {
      final e = actifs[x.employeId];
      if (e == null) continue;
      for (final m in x.modeles) {
        modeles.add(m);
        proprietaires.add(e);
      }
    }
    if (modeles.isEmpty) throw const EmpreinteIndisponible('Aucune empreinte enregistrée sur ce terminal.');
    final i = await empreinte.identifier(modeles);
    return i == null || i < 0 || i >= proprietaires.length ? null : proprietaires[i];
  }
}
