// Prestige Pointage — signature des appels de la borne (demande 57) : VECTEURS calculés par le code Java du serveur
// (util.borne.ProtectionBorne, commit 31622a33, compilé et exécuté le 26/10/2026 : scratchpad java57/Vecteurs.java).
// Secret = octets 0..31, empreinte = « ab12cd34 » × 8, date = 2026-10-26T08:15:30.123Z.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/prestigepointage/signature_borne.dart';

void main() {
  final secret = List<int>.generate(32, (i) => i);
  final emp = 'ab12cd34' * 8;
  const date = '2026-10-26T08:15:30.123Z';
  String sig(String m, String c, List<int> corps) => SignatureBorne.signer(secret, SignatureBorne.chaine(m, c, date, emp, corps));

  test('secret : base64url sans remplissage, décodé en 32 octets (« = » toléré), illisible → null', () {
    const b64 = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';
    expect(SignatureBorne.decoderSecret(b64), secret);
    expect(SignatureBorne.decoderSecret('$b64='), secret);
    expect(SignatureBorne.decoderSecret(' $b64 '), secret);
    expect(SignatureBorne.decoderSecret('AAEC'), isNull, reason: 'pas 32 octets');
    expect(SignatureBorne.decoderSecret('pas+du/base64url'), isNull);
    expect(SignatureBorne.decoderSecret(null), isNull);
  });

  test('vecteurs du serveur : GET sans corps (moi, employes?query, empreintes?format&depuis encodé)', () {
    const vide = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    expect(SignatureBorne.sha256Hex(const []), vide);
    expect(sig('GET', '/prestige/api/v1/borne-pointage/moi', const []), 'jrQYGrRFRNpW-XUQ0GF1J0yzXY_ob7rleJ-WRdLkqDw');
    expect(sig('GET', '/prestige/api/v1/borne-pointage/employes?query=ko', const []), 'i55tPGU_UO-7aYpbmSbTPYc2n2-4sv1Wrh5weMN4glc');
    expect(sig('GET', '/prestige/api/v1/borne-pointage/empreintes?format=SUNMI_A400_RAW&depuis=2026-10-26T08%3A00%3A00', const []),
        'FL15JvWO-Ko8ICr25S_bhrjGL8Cuw2xIuYqfW5pgwVg');
  });

  test('vecteur du serveur : POST JSON avec accent (octets UTF-8)', () {
    const corps =
        '{"id":"0f8b2c1e-7d4a-4b9e-9c3f-2a1b3c4d5e6f","employeId":"E1","jour":"2026-10-26","heure":"08:15","sens":"ENTREE","motif":"Badge terminal Borne entrée"}';
    final b = utf8.encode(corps);
    expect(SignatureBorne.sha256Hex(b), 'ea16f800871c4c9f2e60e7188f066777f22200585a2fb186bf99fe049fab7d66');
    expect(sig('POST', '/prestige/api/v1/borne-pointage/pointages', b), 'buRuZO2VnUi6fR5qiUAu78JrKVh_Ms7sFc7lHGWvjEw');
  });

  test('vecteur du serveur : corps binaire (multipart) haché tel quel', () {
    final mp = List<int>.generate(300, (i) => (i * 7) & 0xff);
    expect(SignatureBorne.sha256Hex(mp), '9a76b8af8f16f19d60de2b3999c22f9d10be4395c90ea3bfc5eb6cd6254243af');
    expect(sig('POST', '/prestige/api/v1/borne-pointage/pointages/P-1/photo', mp), '39gRtGUcqki1vkLjbpfvkd6-1CfDTrdFEx5VStVS1jw');
  });

  test('signature sans remplissage ; moindre changement (méthode, chemin, date, empreinte, corps) → autre signature', () {
    final s = sig('GET', '/prestige/api/v1/borne-pointage/moi', const []);
    expect(s, isNot(contains('=')));
    expect(s.length, 43);
    final autres = {
      SignatureBorne.signer(secret, SignatureBorne.chaine('POST', '/prestige/api/v1/borne-pointage/moi', date, emp, const [])),
      SignatureBorne.signer(secret, SignatureBorne.chaine('GET', '/prestige/api/v1/borne-pointage/moi?x=1', date, emp, const [])),
      SignatureBorne.signer(secret, SignatureBorne.chaine('GET', '/prestige/api/v1/borne-pointage/moi', '2026-10-26T08:15:30.124Z', emp, const [])),
      SignatureBorne.signer(secret, SignatureBorne.chaine('GET', '/prestige/api/v1/borne-pointage/moi', date, emp.toUpperCase(), const [])),
      SignatureBorne.signer(secret, SignatureBorne.chaine('GET', '/prestige/api/v1/borne-pointage/moi', date, emp, const [0])),
    };
    expect(autres, hasLength(5));
    expect(autres, isNot(contains(s)));
  });

  test('date : UTC, millisecondes, « Z » ; chemin et paramètres tels qu\'envoyés', () {
    expect(SignatureBorne.date(DateTime.utc(2026, 10, 26, 8, 15, 30, 123, 456)), '2026-10-26T08:15:30.123Z');
    expect(SignatureBorne.date(DateTime.utc(2026, 10, 26, 8, 15, 30)), '2026-10-26T08:15:30.000Z');
    final u = Uri.parse('http://192.168.1.50:8080/prestige/api/v1/borne-pointage/empreintes')
        .replace(queryParameters: {'format': 'SUNMI_A400_RAW', 'depuis': '2026-10-26T08:00:00'});
    expect(SignatureBorne.cheminEtParametres(u), '/prestige/api/v1/borne-pointage/empreintes?format=SUNMI_A400_RAW&depuis=2026-10-26T08%3A00%3A00');
    expect(SignatureBorne.cheminEtParametres(Uri.parse('http://h/prestige/api/v1/borne-pointage/moi')), '/prestige/api/v1/borne-pointage/moi');
  });
}
