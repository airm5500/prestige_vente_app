// Certificat TLS de TEST (4.1.0) : auto-signé, pour 127.0.0.1 / localhost, créé à la volée (openssl) dans un dossier
// temporaire — aucune clé privée dans le dépôt. Sert au faux serveur HTTPS (`ServeurJsonLocal.contexteTls`,
// `HttpServer.bindSecure`).
//
// La confiance est ajoutée UNIQUEMENT dans le test, par [avecConfianceTest] (HttpOverrides : contexte de sécurité
// du client HTTP qui approuve ce seul certificat). Le code de l'application n'est pas modifié : aucun
// `badCertificateCallback`, la vérification des certificats reste entière. Sans [avecConfianceTest], le certificat
// est refusé comme sur un téléphone (« certificat du serveur refusé »).
import 'dart:io';

class CertificatTest {
  final String certificatPem;
  final String clePem;
  CertificatTest._(this.certificatPem, this.clePem);

  static CertificatTest? _cache;

  /// Certificat créé une fois par exécution des tests.
  static Future<CertificatTest> creer() async {
    final c = _cache;
    if (c != null) return c;
    final dossier = await Directory.systemTemp.createTemp('prestige_tls_test');
    final cle = '${dossier.path}/serveur.key', cert = '${dossier.path}/serveur.crt';
    final r = await Process.run('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', cle, '-out', cert, '-days', '2', //
      '-subj', '/CN=localhost/O=Prestige Mobile tests (fictif)', //
      '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1', //
      '-addext', 'basicConstraints=critical,CA:TRUE',
    ]);
    if (r.exitCode != 0) throw StateError('openssl indisponible pour créer le certificat de test : ${r.stderr}');
    final t = CertificatTest._(await File(cert).readAsString(), await File(cle).readAsString());
    await dossier.delete(recursive: true);
    return _cache = t;
  }

  /// Contexte du serveur HTTPS de test.
  SecurityContext get contexteServeur => SecurityContext()
    ..useCertificateChainBytes(certificatPem.codeUnits)
    ..usePrivateKeyBytes(clePem.codeUnits);

  /// Contexte d'un client qui n'approuve QUE ce certificat (pas les autorités du système).
  SecurityContext get contexteClient => SecurityContext(withTrustedRoots: false)..setTrustedCertificatesBytes(certificatPem.codeUnits);
}

/// Vrai réseau, et le certificat de test approuvé par les clients HTTP créés pendant [corps] (Dio de l'application
/// compris : `HttpClient()` passe par HttpOverrides).
Future<T> avecConfianceTest<T>(CertificatTest c, Future<T> Function() corps) =>
    HttpOverrides.runWithHttpOverrides(corps, _Confiance(c));

class _Confiance extends HttpOverrides {
  final CertificatTest c;
  _Confiance(this.c);
  @override
  HttpClient createHttpClient(SecurityContext? context) => super.createHttpClient(context ?? c.contexteClient);
}
