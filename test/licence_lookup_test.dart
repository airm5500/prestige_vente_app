import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/models/licence_lookup.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';

/// Faux serveur : répond selon le chemin demandé.
class _FakeAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions o) handler;
  _FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) => handler(o);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? body, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );

ResponseBody _html404() => ResponseBody.fromString(
      '<html><body><h1>HTTP Status 404 - Not Found</h1></body></html>',
      404,
      headers: {Headers.contentTypeHeader: ['text/html']},
    );

void main() {
  const base = 'http://192.168.1.50:8080/prestige/api/v1';
  late ApiService api;

  void serve(Future<ResponseBody> Function(RequestOptions o) handler) {
    api = ApiService(baseUrl: base);
    DioClient.getClient(base).httpClientAdapter = _FakeAdapter(handler);
  }

  test('licence présente', () async {
    serve((o) async => _json({'id': 'a2e6', 'dateStart': '2026-02-02', 'dateEnd': '2027-02-01', 'typeLicence': '1'}));
    final r = await api.lookupLicence();
    expect(r.issue, isNull);
    expect(r.licence!.dateEnd, '2027-02-01');
  });

  test('serveur injoignable : problème de connexion, pas de licence', () async {
    serve((o) async => throw DioException.connectionError(
          requestOptions: o,
          reason: 'Connection refused',
          error: const SocketException('Connection refused'),
        ));
    final r = await api.lookupLicence();
    expect(r.issue, LicenceIssue.unreachable);
  });

  test('délai dépassé : problème de connexion', () async {
    serve((o) async => throw DioException.connectionTimeout(requestOptions: o, timeout: const Duration(seconds: 10)));
    expect((await api.lookupLicence()).issue, LicenceIssue.unreachable);
  });

  test('404 Payara et application absente (votre cas) : application introuvable, pas "pas de licence"', () async {
    serve((o) async => _html404());
    final r = await api.lookupLicence();
    expect(r.issue, LicenceIssue.appNotFound);
    expect(r.licence, isNull);
  });

  test('404 sur la licence mais application Prestige présente : pas de licence enregistrée', () async {
    serve((o) async => o.uri.path.endsWith('/licence/find') ? _html404() : ResponseBody.fromString('ok', 200));
    final r = await api.lookupLicence();
    expect(r.issue, isNull);
    expect(r.licence, isNull);
  });

  test('200 vide : pas de licence enregistrée', () async {
    serve((o) async => ResponseBody.fromString('', 200));
    final r = await api.lookupLicence();
    expect(r.issue, isNull);
    expect(r.licence, isNull);
  });

  test('erreur 500 : erreur du serveur Prestige', () async {
    serve((o) async => _json({'error': 'boom'}, 500));
    expect((await api.lookupLicence()).issue, LicenceIssue.serverError);
  });

  test('provider : statut "error" + message dédié, jamais "none" pour un problème réseau', () async {
    serve((o) async => _html404());
    final p = LicenceProvider(api);
    expect(await p.checkLicence(), LicenceStatus.error);
    expect(p.issue, LicenceIssue.appNotFound);
    expect(p.errorTitle, 'Application Prestige introuvable');
    expect(p.errorMessage, contains('nom de l\'application'));

    serve((o) async => ResponseBody.fromString('', 200));
    final p2 = LicenceProvider(api);
    expect(await p2.checkLicence(), LicenceStatus.none);
  });
}
