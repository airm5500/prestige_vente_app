// lib/serveur/adresse_serveur.dart
// Adresse du serveur Prestige (4.1.0) : http ou https, même principe que Prestige Pharmacien et Prestige Inventaire.
//
// - Saisie acceptée : « 192.168.1.50 », « pharmacie.example.com », avec le protocole « https://pharmacie.example.com »
//   ou « http://… », et un port explicite « https://pharmacie.example.com:8443 ».
// - Sans protocole : HTTP (réseau local, comportement d'origine inchangé). HTTPS n'est jamais imposé.
// - Forme enregistrée (mêmes clés local_ip / remote_ip) : sans protocole pour HTTP (identique aux anciens réglages,
//   donc aucune migration), « https://hôte[:port] » pour HTTPS.
// - Port : un port écrit dans l'adresse est prioritaire ; sinon le champ « Port » s'applique au serveur principal
//   (adresse locale) et au serveur distant s'il utilise le même protocole ; sinon le port par défaut du protocole
//   (443 en https, 8080 en http).
// - Les certificats ne sont JAMAIS contournés : seuls ceux reconnus par l'appareil sont acceptés. Un échec TLS est
//   distingué d'un serveur injoignable ([ErreurTls]).
import 'dart:io';

import 'package:dio/dio.dart';

/// Adresse analysée : protocole (« http » / « https »), hôte, port écrit dans l'adresse (ou null).
class AdresseAnalysee {
  final String protocole;
  final String hote;
  final String? port;
  const AdresseAnalysee(this.protocole, this.hote, this.port);
  bool get https => protocole == AdresseServeur.https;
}

class AdresseServeur {
  AdresseServeur._();

  static const http = 'http';
  static const https = 'https';
  static const portHttpParDefaut = '8080';
  static const portHttpsParDefaut = '443';

  static final RegExp _protocole = RegExp(r'^(https?)://', caseSensitive: false);
  static final RegExp _autreProtocole = RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false);
  static final RegExp _portFinal = RegExp(r':(\d{1,5})$');
  static final RegExp _nomHote =
      RegExp(r'^(?=.{1,253}$)[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$');

  /// Port par défaut d'un protocole.
  static String portParDefaut(String protocole) => protocole == https ? portHttpsParDefaut : portHttpParDefaut;

  /// Protocole (en minuscules) écrit au début de la saisie, ou null.
  static String? protocoleEcrit(String? saisie) => _protocole.firstMatch((saisie ?? '').trim())?.group(1)!.toLowerCase();

  /// Saisie sans protocole ni « / » final (« hôte » ou « hôte:port »).
  static String sansProtocole(String? saisie) {
    var t = (saisie ?? '').trim().replaceFirst(_protocole, '');
    while (t.endsWith('/')) {
      t = t.substring(0, t.length - 1);
    }
    return t;
  }

  /// Protocole de la saisie (HTTP sans protocole écrit).
  static String protocole(String? saisie) => protocoleEcrit(saisie) ?? http;

  /// Analyse tolérante (jamais d'exception) : une saisie invalide reste utilisée telle quelle en HTTP
  /// (comportement d'origine), la requête échouera avec un message clair.
  static AdresseAnalysee analyser(String? saisie) {
    final p = protocole(saisie);
    var reste = sansProtocole(saisie);
    String? port;
    final m = _portFinal.firstMatch(reste);
    if (m != null && !reste.substring(0, m.start).contains(':')) {
      port = m.group(1);
      reste = reste.substring(0, m.start);
    }
    return AdresseAnalysee(p, reste, port);
  }

  /// Forme enregistrée : HTTP sans protocole (identique aux anciens réglages), HTTPS avec « https:// ».
  static String normaliser(String? saisie) {
    final t = (saisie ?? '').trim();
    if (t.isEmpty) return '';
    final reste = sansProtocole(t);
    return protocole(t) == https ? 'https://$reste' : reste;
  }

  /// Compose l'adresse enregistrée à partir du choix de protocole et du champ (qui peut déjà contenir un protocole :
  /// celui écrit l'emporte).
  static String composer(String protocoleChoisi, String champ) {
    final t = champ.trim();
    if (t.isEmpty) return '';
    final ecrit = protocoleEcrit(t);
    return normaliser('${ecrit ?? protocoleChoisi}://${sansProtocole(t)}');
  }

  /// Port utilisé pour [saisie] : port écrit dans l'adresse, sinon [portChamp] si le protocole est celui du serveur
  /// principal ([protocolePrincipal]), sinon le port par défaut du protocole.
  static String portEffectif(String? saisie, {required String portChamp, String protocolePrincipal = http}) {
    final a = analyser(saisie);
    if (a.port != null) return a.port!;
    if (a.protocole == protocolePrincipal && portChamp.trim().isNotEmpty) return portChamp.trim();
    return portParDefaut(a.protocole);
  }

  /// Racine de l'API : « http(s)://hôte:port/application/api/v1 ». En HTTP, identique à l'adresse d'origine
  /// `http://$ip:$port/$appName/api/v1`.
  static String racineApi(String saisie, String port, String application) {
    final a = analyser(saisie.trim().isEmpty ? 'localhost' : saisie);
    final p = a.port ?? (port.trim().isEmpty ? portParDefaut(a.protocole) : port.trim());
    return '${a.protocole}://${a.hote}:$p/$application/api/v1';
  }

  /// Adresse lisible : « 192.168.1.50:8080 » en HTTP (comme avant), « https://nom » (port 443 sous-entendu) ou
  /// « https://nom:8443 » en HTTPS.
  static String affichage(String saisie, String port) {
    final a = analyser(saisie);
    final p = a.port ?? (port.trim().isEmpty ? portParDefaut(a.protocole) : port.trim());
    if (!a.https) return '${a.hote}:$p';
    return p == portHttpsParDefaut ? 'https://${a.hote}' : 'https://${a.hote}:$p';
  }

  static bool estIpv4(String v) {
    final parts = v.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      if (p.isEmpty || p.length > 3 || !RegExp(r'^\d+$').hasMatch(p)) return false;
      final n = int.tryParse(p);
      if (n == null || n > 255) return false;
    }
    return true;
  }

  /// Motif de refus de la saisie, ou null si elle est acceptée ([requis] : champ obligatoire).
  static String? erreur(String? saisie, {required bool requis}) {
    final t = (saisie ?? '').trim();
    if (t.isEmpty) return requis ? 'Ce champ est requis' : null;
    if (t.length > 270) return 'Adresse trop longue';
    if (_autreProtocole.hasMatch(t) && !_protocole.hasMatch(t)) return 'Seuls http:// et https:// sont acceptés';
    final reste = sansProtocole(t);
    if (reste.isEmpty) return 'Format invalide (ex. 192.168.1.20)';
    if (reste.contains('/')) return 'Indiquez seulement l\'adresse, sans chemin';
    final a = analyser(t);
    if (a.port != null) {
      final n = int.tryParse(a.port!);
      if (n == null || n < 1 || n > 65535) return 'Port de 1 à 65535';
    } else if (reste.contains(':')) {
      return 'Format invalide (ex. 192.168.1.20 ou https://pharmacie.example.com)';
    }
    final h = a.hote;
    if (RegExp(r'^[0-9.]+$').hasMatch(h)) return estIpv4(h) ? null : 'Format invalide (ex. 192.168.1.20)';
    return _nomHote.hasMatch(h) ? null : 'Format invalide (ex. 192.168.1.20)';
  }
}

/// Échec de la connexion sécurisée (HTTPS), distinct d'un serveur injoignable et d'un problème de licence.
enum ErreurTls {
  /// Certificat non reconnu par l'appareil (auto-signé, expiré, mauvais nom, date de l'appareil fausse).
  certificat,

  /// Le serveur ne parle pas HTTPS sur ce port (https choisi vers le port HTTP 8080 de Payara, par exemple).
  protocole;

  static const messageCertificat = 'Connexion sécurisée (HTTPS) impossible : certificat du serveur refusé.';
  static const conseilCertificat = 'Le serveur doit présenter un certificat reconnu (Let\'s Encrypt par exemple) ; '
      'vérifiez aussi la date et l\'heure de l\'appareil.';
  static const messageProtocole = 'Connexion sécurisée (HTTPS) impossible : le serveur ne répond pas en HTTPS sur ce port '
      '(choisissez http, ou le port HTTPS du serveur).';

  String get message => this == certificat ? messageCertificat : messageProtocole;

  /// Message complet à afficher (avec le conseil).
  String get explication => this == certificat ? '$messageCertificat $conseilCertificat' : messageProtocole;

  /// Titre court.
  String get titre => this == certificat ? 'Certificat du serveur refusé' : 'Connexion sécurisée impossible';

  /// Nature de l'échec TLS dans [e] (DioException, HandshakeException…), ou null si ce n'est pas un échec TLS.
  static ErreurTls? de(Object? e) {
    if (e is DioException) {
      if (e.type == DioExceptionType.badCertificate) return certificat;
      return de(e.error);
    }
    if (e is TlsException) {
      final texte = e.toString().toUpperCase();
      return texte.contains('CERTIFICATE') || e is CertificateException ? certificat : protocole;
    }
    return null;
  }
}
