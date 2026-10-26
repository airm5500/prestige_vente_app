// lib/prestigepointage/signature_borne.dart
// Prestige Pointage (demande 57, serveur 31622a33) : signature des appels de la borne, octet pour octet comme
// util.borne.ProtectionBorne du serveur :
//   CHAINE    = méthode \n chemin?paramètres \n date \n empreinte \n sha256hex(corps)
//   signature = base64url sans remplissage (HMAC-SHA256(secret décodé (32 octets), CHAINE en UTF-8))
// - chemin?paramètres : getRequestURI() + « ? » + getQueryString() du serveur, c'est-à-dire le chemin et les paramètres
//   TELS QU'ENVOYÉS (encodés), contexte compris (« /prestige/api/v1/borne-pointage/employes?query=ko ») ;
// - corps : les octets bruts envoyés (JSON, multipart) ; vide → SHA-256 de rien ;
// - date : ISO 8601 UTC à la milliseconde (« 2026-10-26T08:15:30.123Z »), 300 s d'écart toléré par le serveur.
// Le secret ne circule jamais et n'est jamais journalisé ni affiché.
import 'dart:convert';

import 'package:crypto/crypto.dart';

class SignatureBorne {
  SignatureBorne._();

  /// Chaîne signée (même construction que ProtectionBorne.chaine).
  static String chaine(String methode, String cheminEtParametres, String date, String empreinte, List<int> corps) =>
      '$methode\n$cheminEtParametres\n$date\n$empreinte\n${sha256Hex(corps)}';

  static String sha256Hex(List<int> octets) => sha256.convert(octets).toString();

  /// base64url sans remplissage de HMAC-SHA256(secret, chaîne).
  static String signer(List<int> secret, String chaine) =>
      base64Url.encode(Hmac(sha256, secret).convert(utf8.encode(chaine)).bytes).replaceAll('=', '');

  /// Secret rendu par l'enrôlement (base64url sans remplissage, « = » toléré) → 32 octets ; null s'il est illisible.
  static List<int>? decoderSecret(String? s) {
    final v = (s ?? '').trim().replaceAll('=', '');
    if (v.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(v)) return null;
    try {
      final b = base64Url.decode(base64Url.normalize(v));
      return b.length == 32 ? b : null;
    } catch (_) {
      return null;
    }
  }

  /// Date de l'en-tête X-Borne-Date : UTC, millisecondes, « Z ».
  static String date(DateTime t) => DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch, isUtc: true).toIso8601String();

  /// Chemin et paramètres d'une adresse, tels qu'ils partent sur le réseau (ce que le serveur relit).
  static String cheminEtParametres(Uri u) => u.hasQuery ? '${u.path}?${u.query}' : u.path;
}
