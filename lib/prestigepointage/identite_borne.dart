// lib/prestigepointage/identite_borne.dart
// Prestige Pointage (demande 57) : identité de la borne remise par l'enrôlement (POST v1/rh/bornes) — identifiant,
// secret (32 octets), empreinte de l'appareil, nom, adresse du serveur. Gardée UNIQUEMENT dans le stockage sécurisé
// (Keystore Android, EncryptedSharedPreferences « FlutterSecureStorage », exclu des sauvegardes : voir
// android/app/src/main/res/xml/regles_sauvegarde.xml et regles_extraction.xml). Jamais dans les préférences, un
// journal, un message ou l'écran : [toString] masque le secret.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:prestige_vente_app/prestigepointage/signature_borne.dart';

class IdentiteBorne {
  final String borneId;

  /// Secret décodé (32 octets).
  final List<int> secret;

  /// Empreinte de l'appareil (demande 56), en minuscules.
  final String empreinte;
  final String nom;

  /// Adresse du serveur au moment de l'enrôlement (ex. http://192.168.1.50:8080/prestige/api/v1).
  final String serveur;
  final DateTime? creeLe;

  IdentiteBorne({required this.borneId, required this.secret, required String empreinte, required this.nom, required this.serveur, this.creeLe})
      : empreinte = empreinte.toLowerCase();

  /// Réponse de l'enrôlement → identité ; null si elle est incomplète (secret illisible, identifiant absent).
  static IdentiteBorne? depuisEnrolement(Map<String, dynamic>? b, {required String empreinte, required String nom, required String serveur}) {
    if (b == null || b['success'] != true) return null;
    final id = '${b['borneId'] ?? ''}'.trim();
    final s = SignatureBorne.decoderSecret('${b['secret'] ?? ''}');
    if (id.isEmpty || s == null) return null;
    return IdentiteBorne(
        borneId: id, secret: s, empreinte: empreinte, nom: nom, serveur: serveur, creeLe: DateTime.tryParse('${b['creeLe'] ?? ''}'));
  }

  Map<String, dynamic> _json() => {
        'v': 1,
        'borneId': borneId,
        'secret': base64Url.encode(secret).replaceAll('=', ''),
        'empreinte': empreinte,
        'nom': nom,
        'serveur': serveur,
        if (creeLe != null) 'creeLe': creeLe!.toIso8601String(),
      };

  static IdentiteBorne? _lire(String? brut) {
    if (brut == null || brut.isEmpty) return null;
    try {
      final j = jsonDecode(brut);
      if (j is! Map) return null;
      final s = SignatureBorne.decoderSecret('${j['secret'] ?? ''}');
      final id = '${j['borneId'] ?? ''}';
      if (s == null || id.isEmpty) return null;
      return IdentiteBorne(
        borneId: id,
        secret: s,
        empreinte: '${j['empreinte'] ?? ''}',
        nom: '${j['nom'] ?? ''}',
        serveur: '${j['serveur'] ?? ''}',
        creeLe: DateTime.tryParse('${j['creeLe'] ?? ''}'),
      );
    } catch (_) {
      return null;
    }
  }

  /// Jamais le secret.
  @override
  String toString() => 'IdentiteBorne($nom, ${borneId.length > 8 ? borneId.substring(0, 8) : borneId}…)';
}

/// Coffre de l'identité de la borne.
abstract class CoffreBorne {
  Future<IdentiteBorne?> lire();
  Future<void> ecrire(IdentiteBorne identite);
  Future<void> effacer();
}

class CoffreBorneSecurise implements CoffreBorne {
  static const cle = 'prestigepointage_borne_v1';
  final FlutterSecureStorage _s;
  const CoffreBorneSecurise([this._s = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true))]);

  @override
  Future<IdentiteBorne?> lire() async {
    try {
      return IdentiteBorne._lire(await _s.read(key: cle));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> ecrire(IdentiteBorne identite) => _s.write(key: cle, value: jsonEncode(identite._json()));

  @override
  Future<void> effacer() async {
    try {
      await _s.delete(key: cle);
    } catch (_) {}
  }
}

class CoffreBorneMemoire implements CoffreBorne {
  IdentiteBorne? valeur;
  CoffreBorneMemoire([this.valeur]);
  @override
  Future<IdentiteBorne?> lire() async => valeur;
  @override
  Future<void> ecrire(IdentiteBorne identite) async => valeur = IdentiteBorne._lire(jsonEncode(identite._json()));
  @override
  Future<void> effacer() async => valeur = null;
}
