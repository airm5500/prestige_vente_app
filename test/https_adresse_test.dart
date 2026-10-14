// 4.1.0 — HTTPS pour l'accès au serveur par Internet (UNITAIRES) : construction de l'adresse du serveur.
//   - http / https, ports par défaut (8080 / 443), port écrit dans l'adresse prioritaire ;
//   - adresse saisie avec son protocole (« https://… », « HTTP://… ») ;
//   - serveur distant : même protocole que le local → champ « Port », sinon port par défaut de son protocole ;
//   - migration des anciens réglages : adresse SANS protocole = HTTP, adresse d'API identique à l'ancienne ;
//   - échecs TLS : certificat refusé ≠ port non HTTPS ≠ serveur injoignable.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/parametres/parametres_logic.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/serveur/adresse_serveur.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ancienne construction (jusqu'à 4.0.3), pour la non-régression.
String _ancienne(String ip, String port, String app) => 'http://${ip.isEmpty ? 'localhost' : ip}:$port/$app/api/v1';

Future<SettingsProvider> _reglages(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final s = SettingsProvider();
  await s.loadSettings();
  return s;
}

void main() {
  group('AdresseServeur', () {
    test('analyse : protocole, hôte, port écrit', () {
      var a = AdresseServeur.analyser('192.168.1.50');
      expect((a.protocole, a.hote, a.port), ('http', '192.168.1.50', null));
      a = AdresseServeur.analyser(' https://Pharmacie.example.com/ ');
      expect((a.protocole, a.hote, a.port), ('https', 'Pharmacie.example.com', null));
      a = AdresseServeur.analyser('HTTPS://pharmacie.example.com:8443');
      expect((a.protocole, a.hote, a.port), ('https', 'pharmacie.example.com', '8443'));
      a = AdresseServeur.analyser('http://10.0.0.2:8081');
      expect((a.protocole, a.hote, a.port), ('http', '10.0.0.2', '8081'));
    });

    test('forme enregistrée : HTTP sans protocole (comme avant), HTTPS avec « https:// »', () {
      expect(AdresseServeur.normaliser('192.168.1.50'), '192.168.1.50');
      expect(AdresseServeur.normaliser('http://192.168.1.50/'), '192.168.1.50');
      expect(AdresseServeur.normaliser('HTTPS://nom.example.com/'), 'https://nom.example.com');
      expect(AdresseServeur.normaliser(''), '');
      expect(AdresseServeur.composer('https', 'nom.example.com'), 'https://nom.example.com');
      expect(AdresseServeur.composer('http', 'nom.example.com'), 'nom.example.com');
      expect(AdresseServeur.composer('http', 'https://nom.example.com'), 'https://nom.example.com', reason: 'le protocole écrit l\'emporte');
      expect(AdresseServeur.composer('https', '  '), '');
    });

    test('ports : 8080 en http, 443 en https, port écrit prioritaire', () {
      expect(AdresseServeur.racineApi('192.168.1.50', '8080', 'prestige'), 'http://192.168.1.50:8080/prestige/api/v1');
      expect(AdresseServeur.racineApi('192.168.1.50', '', 'prestige'), 'http://192.168.1.50:8080/prestige/api/v1');
      expect(AdresseServeur.racineApi('https://nom.example.com', '', 'prestige'), 'https://nom.example.com:443/prestige/api/v1');
      expect(AdresseServeur.racineApi('https://nom.example.com:8443', '443', 'prestige'), 'https://nom.example.com:8443/prestige/api/v1');
      expect(AdresseServeur.racineApi('10.0.0.2:9090', '8080', 'prestige'), 'http://10.0.0.2:9090/prestige/api/v1');
      expect(AdresseServeur.racineApi('', '8080', 'prestige'), 'http://localhost:8080/prestige/api/v1');

      // Port effectif : champ « Port » pour le protocole du serveur principal, sinon défaut du protocole.
      expect(AdresseServeur.portEffectif('https://nom', portChamp: '8080', protocolePrincipal: 'http'), '443');
      expect(AdresseServeur.portEffectif('https://nom', portChamp: '8443', protocolePrincipal: 'https'), '8443');
      expect(AdresseServeur.portEffectif('https://nom:9443', portChamp: '8443', protocolePrincipal: 'https'), '9443');
      expect(AdresseServeur.portEffectif('41.207.10.9', portChamp: '8080', protocolePrincipal: 'http'), '8080');
      expect(AdresseServeur.portEffectif('41.207.10.9', portChamp: '443', protocolePrincipal: 'https'), '8080');
      expect(AdresseServeur.portEffectif('41.207.10.9:8081', portChamp: '443', protocolePrincipal: 'https'), '8081');
    });

    test('affichage : « ip:port » en http (inchangé), « https://nom » en https', () {
      expect(AdresseServeur.affichage('192.168.1.50', '8080'), '192.168.1.50:8080');
      expect(AdresseServeur.affichage('https://nom.example.com', '443'), 'https://nom.example.com');
      expect(AdresseServeur.affichage('https://nom.example.com', '8443'), 'https://nom.example.com:8443');
    });

    test('contrôle de saisie : protocole et port facultatifs, le reste refusé', () {
      for (final ok in ['192.168.1.20', 'pharmacie.ddns.net', 'https://pharmacie.ddns.net', 'http://192.168.1.20',
        'https://pharmacie.ddns.net:8443', '192.168.1.20:8080']) {
        expect(ParametresChecks.host(ok, required: true), isNull, reason: ok);
      }
      expect(ParametresChecks.host('', required: true), 'Ce champ est requis');
      expect(ParametresChecks.host('192.168.1', required: true), 'Format invalide (ex. 192.168.1.20)');
      expect(ParametresChecks.host('41.207.300.9', required: true), isNotNull);
      expect(ParametresChecks.host('ftp://nom.example.com', required: true), 'Seuls http:// et https:// sont acceptés');
      expect(ParametresChecks.host('https://nom.example.com/prestige', required: true), contains('sans chemin'));
      expect(ParametresChecks.host('https://nom.example.com:99999', required: true), 'Port de 1 à 65535');
      expect(ParametresChecks.host('mauvais nom', required: false), isNotNull);
    });
  });

  group('Réglages enregistrés', () {
    test('anciens réglages (sans protocole) : HTTP, adresse d\'API IDENTIQUE à 4.0.3', () async {
      for (final (ip, port) in const [('192.168.1.50', '8080'), ('10.0.0.12', '8181'), ('pharmacie.ddns.net', '8080')]) {
        final s = await _reglages({'local_ip': ip, 'remote_ip': '41.207.10.9', 'port': port, 'app_name': 'prestige'});
        expect(s.baseUrl, _ancienne(ip, port, 'prestige'));
        expect(s.localIp, ip, reason: 'valeur enregistrée inchangée');
        expect(s.protocole(false), 'http');
        expect(s.adresseAffichee(false), '$ip:$port');
        await s.setConnectionMode(true);
        expect(s.baseUrl, _ancienne('41.207.10.9', port, 'prestige'), reason: 'distant en http : même port qu\'avant');
      }
      // Appareil neuf : défaut inchangé.
      final neuf = await _reglages({});
      expect(neuf.baseUrl, 'http://192.168.1.50:8080/prestige/api/v1');
    });

    test('adresse enregistrée avec « http:// » : normalisée, même adresse d\'API', () async {
      final s = await _reglages({'local_ip': 'HTTP://192.168.1.50/', 'port': '8080'});
      expect(s.localIp, '192.168.1.50');
      expect(s.baseUrl, 'http://192.168.1.50:8080/prestige/api/v1');
    });

    test('local en http, distant en https : 443 par défaut pour le distant, 8080 pour le local', () async {
      final s = await _reglages({'local_ip': '192.168.1.50', 'remote_ip': 'https://prestige.ma-pharmacie.ci', 'port': '8080'});
      expect(s.baseUrl, 'http://192.168.1.50:8080/prestige/api/v1');
      expect(s.urlServeur(true), 'https://prestige.ma-pharmacie.ci:443/prestige/api/v1');
      expect(s.adresseAffichee(true), 'https://prestige.ma-pharmacie.ci');
      await s.setConnectionMode(true);
      expect(s.baseUrl, 'https://prestige.ma-pharmacie.ci:443/prestige/api/v1');
      expect(s.portPour(s.remoteIp), '443');
    });

    test('serveur principal en https : le champ « Port » s\'applique (443, ou un autre port choisi)', () async {
      var s = await _reglages({'local_ip': 'https://prestige.ma-pharmacie.ci', 'port': '443'});
      expect(s.baseUrl, 'https://prestige.ma-pharmacie.ci:443/prestige/api/v1');
      s = await _reglages({'local_ip': 'https://prestige.ma-pharmacie.ci', 'port': '8443'});
      expect(s.baseUrl, 'https://prestige.ma-pharmacie.ci:8443/prestige/api/v1');
      expect(s.adresseAffichee(false), 'https://prestige.ma-pharmacie.ci:8443');
      // Distant en http avec un local en https : port HTTP par défaut, sauf port écrit.
      s = await _reglages({'local_ip': 'https://nom.example.com', 'remote_ip': '41.207.10.9', 'port': '443'});
      expect(s.urlServeur(true), 'http://41.207.10.9:8080/prestige/api/v1');
      s = await _reglages({'local_ip': 'https://nom.example.com', 'remote_ip': '41.207.10.9:8081', 'port': '443'});
      expect(s.urlServeur(true), 'http://41.207.10.9:8081/prestige/api/v1');
    });

    test('enregistrement : forme normalisée, test du serveur à l\'adresse https', () async {
      SharedPreferences.setMockInitialValues({});
      final s = _SondeSettings();
      await s.loadSettings();
      expect(await s.saveSettings(localIp: 'HTTPS://prestige.ma-pharmacie.ci/', remoteIp: 'http://41.207.10.9', appName: 'prestige', port: '443'),
          isTrue);
      expect(s.sondes, ['https://prestige.ma-pharmacie.ci|443']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('local_ip'), 'https://prestige.ma-pharmacie.ci');
      expect(prefs.getString('remote_ip'), '41.207.10.9');
      expect(s.baseUrl, 'https://prestige.ma-pharmacie.ci:443/prestige/api/v1');
    });
  });

  group('Échecs TLS', () {
    RequestOptions ro() => RequestOptions(path: '/x');
    test('certificat refusé, port non HTTPS, et le reste n\'est pas un échec TLS', () {
      const cert = HandshakeException('Handshake error in client', OSError('CERTIFICATE_VERIFY_FAILED: self signed certificate', 1));
      const version = HandshakeException('Handshake error in client', OSError('WRONG_VERSION_NUMBER', 1));
      expect(ErreurTls.de(cert), ErreurTls.certificat);
      expect(ErreurTls.de(DioException(requestOptions: ro(), error: cert)), ErreurTls.certificat);
      expect(ErreurTls.de(DioException.badCertificate(requestOptions: ro())), ErreurTls.certificat);
      expect(ErreurTls.de(DioException(requestOptions: ro(), error: version)), ErreurTls.protocole);
      expect(ErreurTls.de(DioException.connectionError(requestOptions: ro(), reason: 'refused', error: const SocketException('x'))), isNull);
      expect(ErreurTls.de(const SocketException('x')), isNull);
      expect(ErreurTls.certificat.message, 'Connexion sécurisée (HTTPS) impossible : certificat du serveur refusé.');
      expect(ErreurTls.certificat.titre, 'Certificat du serveur refusé');
    });
  });
}

class _SondeSettings extends SettingsProvider {
  final sondes = <String>[];
  @override
  Future<bool> ping(String ip, String port, String appName) async {
    sondes.add('$ip|$port');
    return true;
  }
}
