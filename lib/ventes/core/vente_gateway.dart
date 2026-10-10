// lib/ventes/core/vente_gateway.dart
// Accès serveur des trois ventes (Pré-vente, Assurance, Carnet), version fiable :
// mêmes URL et mêmes données que lib/api/api_service.dart (copiées à l'identique),
// mais chaque appel renvoie un VenteResult : le message du serveur n'est jamais perdu
// et une panne n'est jamais confondue avec « aucun résultat ».
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

/// Tiers payant d'une vente (forme attendue par le serveur).
typedef VenteTp = ({String compteTp, String numBon, int taux});

abstract class VenteGateway {
  // --- Produits / panier (commun) ---
  Future<VenteResult<List<ProductSearchResult>>> searchProducts(String query);
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId);
  Future<VenteResult<void>> removeItem(String itemId);
  Future<VenteResult<void>> updateItem({required String itemId, required String produitId, required int qte, required int itemPu});
  Future<VenteResult<void>> terminerPrevente(String venteId);

  // --- Vente comptant (VNO) ---
  /// Renvoie l'identifiant de la vente (créée au 1er article).
  Future<VenteResult<String>> addItemVno({required String produitId, required int qte, required int itemPu, String? venteId, required bool prevente});
  Future<VenteResult<SaleSummary>> netVno(String venteId);
  Future<VenteResult<void>> updateClient(String venteId, String clientId);
  Future<VenteResult<Map<String, dynamic>>> cloturerVno({
    required String venteId,
    required SaleSummary summary,
    required String typeReglementId,
    required String clientId,
    required String userVendeurId,
    int? montantRecu,
    int? montantRemis,
  });
  Future<VenteResult<List<PaymentMethod>>> paymentMethods();
  Future<VenteResult<List<PaymentMethodQr>>> paymentMethodsWithQr();

  /// Préventes à encaisser (statut is_Process), comme getPreventes.
  Future<VenteResult<List<PreventeListItem>>> preventes();

  /// Historique 50 dernières ventes d'un type ('1' VNO, '2' assurance, '3' carnet), comme fetchPreventesByType.
  Future<VenteResult<List<PreventeListItem>>> ventesByType(String typeVenteId);

  /// Détail complet d'une vente (/ventestats/{id}).
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId);

  // --- Assurance / carnet ---
  Future<VenteResult<List<ClientAssurance>>> searchClients(String query, {required String typeClientId});
  Future<VenteResult<List<TiersPayantAssurance>>> searchTiersPayants(String query, {required bool carnet});
  Future<VenteResult<List<AyantDroit>>> ayantDroits(String clientId);
  Future<VenteResult<AyantDroit>> createAyantDroit({required String clientId, required String firstName, required String lastName, required String numSecu});
  Future<VenteResult<ClientAssurance>> createClientAssurance({
    required String firstName,
    required String lastName,
    required String numSecu,
    required String tiersPayantId,
    required int pourcentage,
  });
  Future<VenteResult<ClientAssurance>> createClientCarnet({required String firstName, required String lastName, required String numSecu, required String tiersPayantId});
  Future<VenteResult<ClientAssurance>> addTiersPayantToClient({required ClientAssurance client, required Map<String, dynamic> newTiersPayantPayload});
  Future<VenteResult<ClientAssurance>> updateClientAssurance({required ClientAssurance client, required List<Map<String, dynamic>> tiersPayantsPayload});

  /// Ajout d'un article à une vente assurance ('2') ou carnet ('3'). Renvoie l'identifiant de la vente.
  Future<VenteResult<String>> addItemAssurance({
    required String produitId,
    required int qte,
    required int itemPu,
    required String clientId,
    required String ayantDroitId,
    required String natureVenteId,
    required String typeVenteId,
    required String? userVendeurId,
    required List<VenteTp> tierspayants,
    String? venteId,
  });
  Future<VenteResult<AssuranceSaleSummary>> netAssurance({required String venteId, required List<VenteTp> tierspayants});
  Future<VenteResult<Map<String, dynamic>>> cloturerAssurance({
    required String venteId,
    required String clientId,
    required String ayantDroitId,
    required String natureVenteId,
    required String typeVenteId,
    required String? userVendeurId,
    required AssuranceSaleSummary summary,
    required String typeReglementId,
    required List<VenteTp> tierspayants,
    int? montantRecu,
    int? montantRemis,
  });
}

class DioVenteGateway implements VenteGateway {
  final ApiService _api;
  DioVenteGateway(this._api);

  Dio get _dio => _api.dio;

  // ---------------------------------------------------------------------------
  // Exécution commune
  // ---------------------------------------------------------------------------

  /// Exécute la requête. `write` : opération qui modifie le serveur (délai de réponse dépassé = peut-être appliquée).
  Future<VenteResult<dynamic>> _call(Future<Response<dynamic>> Function() request, {required String what, bool write = false}) async {
    try {
      final r = await request();
      final code = r.statusCode ?? 0;
      if (code != 200 && code != 202) {
        return VenteFailed('Erreur du serveur (code $code) : $what.', maybeApplied: write);
      }
      final body = r.data;
      if (body is Map && body['success'] == false) {
        final msg = '${body['msg'] ?? body['message'] ?? ''}'.trim();
        return VenteRefused(msg.isEmpty ? 'Le serveur a refusé : $what.' : msg, code: body['codeError']?.toString());
      }
      if (body is String && body.trim().startsWith('<')) {
        return VenteFailed('Réponse inattendue du serveur ($what). La session a peut-être expiré : reconnectez-vous.');
      }
      return VenteOk(body);
    } on DioException catch (e) {
      return VenteFailed(_networkMessage(e, what), maybeApplied: write && _mayHaveReached(e));
    } catch (e) {
      return VenteFailed('Impossible de $what : $e', maybeApplied: write);
    }
  }

  static bool _mayHaveReached(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout => false,
        DioExceptionType.sendTimeout => false,
        DioExceptionType.cancel => false,
        DioExceptionType.connectionError => false,
        DioExceptionType.badCertificate => false,
        // Délai de réponse dépassé, erreur serveur, connexion coupée en cours : la requête a pu être traitée.
        _ => true,
      };

  static String _networkMessage(DioException e, String what) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return 'Le serveur ne répond pas ($what). Vérifiez le réseau puis réessayez.';
      case DioExceptionType.receiveTimeout:
        return 'Le serveur met trop de temps à répondre ($what). Vérification nécessaire avant de réessayer.';
      case DioExceptionType.connectionError:
        return 'Serveur injoignable ($what). Vérifiez le Wi-Fi ou les données mobiles puis réessayez.';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        if (code == 401 || code == 403) return 'Session expirée ou accès refusé ($what). Reconnectez-vous.';
        final data = e.response?.data;
        if (data is Map && (data['msg'] ?? data['message']) != null) return '${data['msg'] ?? data['message']}';
        return 'Erreur du serveur (code $code) : $what.';
      default:
        if (e.error is SocketException) return 'Serveur injoignable ($what). Vérifiez le Wi-Fi ou les données mobiles puis réessayez.';
        return 'Impossible de $what : ${e.message ?? e.type.name}.';
    }
  }

  /// Liste `data: [...]` → objets ; réponse illisible = échec (jamais une liste vide).
  VenteResult<List<T>> _list<T>(VenteResult<dynamic> r, String what, T Function(Map<String, dynamic>) parse) {
    if (r is! VenteOk) return r.map((_) => <T>[]);
    final body = r.value;
    if (body is! Map) return VenteFailed('Réponse inattendue du serveur ($what).');
    final data = body['data'];
    if (data == null) return const VenteOk([]);
    if (data is! List) return VenteFailed('Réponse inattendue du serveur ($what).');
    try {
      return VenteOk([for (final e in data) if (e is Map) parse(Map<String, dynamic>.from(e))]);
    } catch (e) {
      return VenteFailed('Données illisibles ($what) : $e');
    }
  }

  VenteResult<T> _object<T>(VenteResult<dynamic> r, String what, T Function(Map<String, dynamic>) parse) {
    if (r is! VenteOk) return r.map((_) => throw StateError('inutilisé'));
    final body = r.value;
    try {
      final data = body is Map ? body['data'] : null;
      if (data is! Map) return VenteFailed('Réponse inattendue du serveur ($what).');
      return VenteOk(parse(Map<String, dynamic>.from(data)));
    } catch (e) {
      return VenteFailed('Données illisibles ($what) : $e');
    }
  }

  VenteResult<void> _void(VenteResult<dynamic> r, {bool requireSuccess = true}) {
    if (r is! VenteOk) return r.map((_) {});
    final body = r.value;
    if (requireSuccess && !(body is Map && body['success'] == true)) {
      return const VenteRefused('Le serveur n\'a pas confirmé l\'opération.');
    }
    return const VenteOk(null);
  }

  static List<Map<String, dynamic>> _tp(List<VenteTp> tps) =>
      [for (final tp in tps) {"cmu": "false", "compteTp": tp.compteTp, "numBon": tp.numBon, "taux": tp.taux}];

  // ---------------------------------------------------------------------------
  // Produits / panier
  // ---------------------------------------------------------------------------

  @override
  Future<VenteResult<List<ProductSearchResult>>> searchProducts(String query) async => _list(
        await _call(() => _dio.get('/vente/search', queryParameters: {'query': query, 'page': 1, 'start': 0, 'limit': 30}),
            what: 'rechercher le produit'),
        'recherche produit',
        ProductSearchResult.fromJson,
      );

  /// Recherche par pages avec le total du serveur (« 50 sur 252 »), pour ne plus couper la liste.
  Future<VenteResult<ProductPage>> searchProductsPage(String query, int start, int limit) async {
    final r = await _call(
      () => _dio.get('/vente/search', queryParameters: {'query': query, 'page': start ~/ limit + 1, 'start': start, 'limit': limit}),
      what: 'rechercher le produit',
    );
    final list = _list(r, 'recherche produit', ProductSearchResult.fromJson);
    if (list is! VenteOk<List<ProductSearchResult>>) return list.map((_) => const ProductPage([], 0));
    final body = (r as VenteOk).value;
    final total = body is Map ? int.tryParse('${body['total'] ?? ''}') : null;
    return VenteOk(ProductPage(list.value, total ?? list.value.length));
  }

  @override
  Future<VenteResult<List<SaleItemDetail>>> saleDetails(String venteId) async => _list(
        await _call(() => _dio.get('/vente/deatails', queryParameters: {'venteId': venteId, 'page': 1, 'start': 0, 'limit': 100}),
            what: 'relire le panier'),
        'panier',
        SaleItemDetail.fromJson,
      );

  @override
  Future<VenteResult<void>> removeItem(String itemId) async =>
      _void(await _call(() => _dio.post('/vente/remove/vno/item/$itemId'), what: 'supprimer la ligne', write: true));

  @override
  Future<VenteResult<void>> updateItem({required String itemId, required String produitId, required int qte, required int itemPu}) async => _void(
        await _call(
          () => _dio.post('/vente/update/item/vno', data: {"itemId": itemId, "produitId": produitId, "qte": qte, "qteServie": qte, "itemPu": itemPu}),
          what: 'modifier la ligne',
          write: true,
        ),
      );

  @override
  Future<VenteResult<void>> terminerPrevente(String venteId) async =>
      _void(await _call(() => _dio.put('/vente/terminerprevente/$venteId'), what: 'enregistrer la prévente', write: true));

  // ---------------------------------------------------------------------------
  // Vente comptant
  // ---------------------------------------------------------------------------

  @override
  Future<VenteResult<String>> addItemVno({required String produitId, required int qte, required int itemPu, String? venteId, required bool prevente}) async {
    final first = venteId == null;
    final r = await _call(
      () => _dio.post(first ? '/vente/add/vno' : '/vente/add/item', data: {
        "typeVenteId": "1",
        "natureVenteId": "1",
        "produitId": produitId,
        "itemPu": itemPu,
        "qte": qte,
        "qteServie": qte,
        "devis": false,
        "venteId": venteId,
        "prevente": prevente,
        "remiseId": null,
        "userVendeurId": null,
      }),
      what: 'ajouter le produit',
      write: true,
    );
    // Comme addItemToSale : l'identifiant renvoyé n'est lu qu'au 1er article.
    return _saleId(r, venteId, readResponseId: first);
  }

  VenteResult<String> _saleId(VenteResult<dynamic> r, String? venteId, {bool readResponseId = true}) {
    if (r is! VenteOk) return r.map((_) => '');
    final body = r.value;
    if (!(body is Map && body['success'] == true)) return const VenteRefused('Le serveur n\'a pas confirmé l\'ajout.');
    final data = body['data'];
    final id = readResponseId && data is Map ? data['lgPREENREGISTREMENTID']?.toString() : null;
    final result = (id != null && id.isNotEmpty) ? id : venteId;
    if (result == null || result.isEmpty) {
      return const VenteFailed('Vente créée sans identifiant renvoyé : vérifiez la liste des préventes.', maybeApplied: true);
    }
    return VenteOk(result);
  }

  @override
  Future<VenteResult<SaleSummary>> netVno(String venteId) async {
    final r = await _call(() => _dio.post('/vente/net/vno', data: {"venteId": venteId, "checkUg": false}), what: 'calculer le net');
    if (r is! VenteOk) return r.map((_) => throw StateError('inutilisé'));
    try {
      return VenteOk(SaleSummary.fromNetResponse(Map<String, dynamic>.from(r.value as Map)));
    } catch (e) {
      return VenteFailed('Net illisible : $e');
    }
  }

  @override
  Future<VenteResult<void>> updateClient(String venteId, String clientId) async => _void(await _call(
        () => _dio.post('/vente/update/client', data: {"clientId": clientId, "venteId": venteId}),
        what: 'associer le client',
        write: true,
      ));

  @override
  Future<VenteResult<Map<String, dynamic>>> cloturerVno({
    required String venteId,
    required SaleSummary summary,
    required String typeReglementId,
    required String clientId,
    required String userVendeurId,
    int? montantRecu,
    int? montantRemis,
  }) async {
    final r = await _call(
      () => _dio.post('/vente/cloturer/vno', data: {
        "banque": "",
        "clientId": clientId,
        "commentaire": "",
        "data": summary.toJson(),
        "devis": false,
        "lieux": "",
        "marge": summary.marge,
        "medecinId": null,
        "montantPaye": summary.montantNet,
        "montantRecu": montantRecu ?? summary.montantNet,
        "montantRemis": montantRemis ?? 0,
        "natureVenteId": "1",
        "nom": "",
        "partTP": 0,
        "reglements": [
          {"montant": summary.montantNet, "montantAttentu": summary.montantNet, "typeReglement": typeReglementId}
        ],
        "remiseId": null,
        "totalRecap": summary.montantNet,
        "typeRegleId": typeReglementId,
        "typeVenteId": "1",
        "userVendeurId": userVendeurId,
        "venteId": venteId,
      }),
      what: 'encaisser la vente',
      write: true,
    );
    return _closeResult(r);
  }

  VenteResult<Map<String, dynamic>> _closeResult(VenteResult<dynamic> r) {
    if (r is! VenteOk) return r.map((_) => <String, dynamic>{});
    final body = r.value;
    if (body is! Map) return const VenteFailed('Réponse inattendue du serveur à la clôture : vérifiez la vente.', maybeApplied: true);
    if (body['success'] != true) return const VenteRefused('Le serveur n\'a pas confirmé la clôture.');
    return VenteOk(Map<String, dynamic>.from(body));
  }

  @override
  Future<VenteResult<List<PaymentMethod>>> paymentMethods() async => _list(
        await _call(() => _dio.get('/common/reglement', queryParameters: {'page': 1, 'start': 0, 'limit': 25}), what: 'charger les modes de paiement'),
        'modes de paiement',
        PaymentMethod.fromJson,
      );

  @override
  Future<VenteResult<List<PaymentMethodQr>>> paymentMethodsWithQr() async => _list(
        await _call(() => _dio.get('/modereglement/all', queryParameters: {'page': 1, 'start': 0, 'limit': 20}), what: 'charger les QR de paiement'),
        'QR de paiement',
        PaymentMethodQr.fromJson,
      );

  @override
  Future<VenteResult<List<PreventeListItem>>> preventes() async => _list(
        await _call(
          () => _dio.get('/ventestats/preventes', queryParameters: {
            'statut': 'is_Process',
            'limit': 9999,
            'sort': '[{"property":"heure","direction":"DESC"}]',
            'page': 1,
            'start': 0,
          }),
          what: 'charger les préventes',
        ),
        'préventes',
        PreventeListItem.fromJson,
      );

  @override
  Future<VenteResult<List<PreventeListItem>>> ventesByType(String typeVenteId) async {
    final r = await _call(
      () => _dio.get('/ventestats/preventes', queryParameters: {'statut': 'ALL', 'limit': 50, 'page': 1, 'start': 0, 'query': ''}),
      what: 'charger l\'historique',
    );
    if (r is! VenteOk) return r.map((_) => <PreventeListItem>[]);
    final body = r.value;
    final data = body is Map ? body['data'] : null;
    final rows = data is List ? data : (data is Map ? data.values.toList() : const []);
    try {
      return VenteOk([
        for (final item in rows)
          if (item is Map && item['lgTYPEVENTEID'].toString() == typeVenteId) PreventeListItem.fromJson(Map<String, dynamic>.from(item)),
      ]);
    } catch (e) {
      return VenteFailed('Historique illisible : $e');
    }
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> fullSale(String venteId) async {
    final r = await _call(() => _dio.get('/ventestats/$venteId'), what: 'charger la vente');
    if (r is! VenteOk) return r.map((_) => <String, dynamic>{});
    final body = r.value;
    final data = body is Map ? body['data'] : null;
    if (data is! Map) return const VenteFailed('Vente introuvable ou réponse illisible.');
    return VenteOk(Map<String, dynamic>.from(data));
  }

  // ---------------------------------------------------------------------------
  // Assurance / carnet
  // ---------------------------------------------------------------------------

  @override
  Future<VenteResult<List<ClientAssurance>>> searchClients(String query, {required String typeClientId}) async => _list(
        await _call(
          () => _dio.get('/client/all', queryParameters: {'query': query, 'typeClientId': typeClientId, 'page': 1, 'start': 0, 'limit': 25}),
          what: 'rechercher le client',
        ),
        'clients',
        ClientAssurance.fromJson,
      );

  @override
  Future<VenteResult<List<TiersPayantAssurance>>> searchTiersPayants(String query, {required bool carnet}) async => _list(
        await _call(
          () => _dio.get(carnet ? '/client/tiers-payants/carnet' : '/client/tiers-payants/assurance',
              queryParameters: {'query': query, 'page': 1, 'start': 0, 'limit': 25}),
          what: carnet ? 'rechercher le carnet' : 'rechercher l\'assurance',
        ),
        'tiers payants',
        TiersPayantAssurance.fromJson,
      );

  @override
  Future<VenteResult<List<AyantDroit>>> ayantDroits(String clientId) async => _list(
        await _call(() => _dio.get('/client/ayant-droits', queryParameters: {'clientId': clientId}), what: 'charger les ayants droit'),
        'ayants droit',
        AyantDroit.fromJson,
      );

  @override
  Future<VenteResult<AyantDroit>> createAyantDroit({required String clientId, required String firstName, required String lastName, required String numSecu}) async =>
      _object(
        await _call(
          () => _dio.post('/client/ayant-droits/$clientId', data: {
            "dtNAISSANCE": "",
            "lgVILLEID": "",
            "strFIRSTNAME": firstName,
            "strLASTNAME": lastName,
            "strNUMEROSECURITESOCIAL": numSecu,
          }),
          what: 'créer l\'ayant droit',
          write: true,
        ),
        'ayant droit',
        AyantDroit.fromJson,
      );

  @override
  Future<VenteResult<ClientAssurance>> createClientAssurance({
    required String firstName,
    required String lastName,
    required String numSecu,
    required String tiersPayantId,
    required int pourcentage,
  }) async =>
      _object(
        await _call(
          () => _dio.post('/client/add/assurance', data: {
            "bIsAbsolute": false,
            "compteTp": "",
            "dblQUOTACONSOMENSUELLE": 0,
            "dbPLAFONDENCOURS": 0,
            "dtNAISSANCE": "",
            "intPOURCENTAGE": pourcentage,
            "intPRIORITY": 1,
            "lgCATEGORIEAYANTDROITID": "",
            "lgCLIENTID": "",
            "lgCOMPANYID": "",
            "lgRISQUEID": "",
            "lgTIERSPAYANTID": tiersPayantId,
            "lgTYPECLIENTID": "1",
            "lgVILLEID": "",
            "strADRESSE": "",
            "strCODEPOSTAL": "",
            "strFIRSTNAME": firstName,
            "strLASTNAME": lastName,
            "strNUMEROSECURITESOCIAL": numSecu,
            "strSEXE": "",
            "tiersPayants": [],
          }),
          what: 'créer le client',
          write: true,
        ),
        'client',
        ClientAssurance.fromJson,
      );

  @override
  Future<VenteResult<ClientAssurance>> createClientCarnet({required String firstName, required String lastName, required String numSecu, required String tiersPayantId}) async =>
      _object(
        await _call(
          () => _dio.post('/client/add/carnet', data: {
            "bIsAbsolute": false,
            "compteTp": "",
            "dblQUOTACONSOMENSUELLE": 0,
            "dbPLAFONDENCOURS": 0,
            "dtNAISSANCE": "",
            "intPOURCENTAGE": 100,
            "intPRIORITY": 1,
            "lgCATEGORIEAYANTDROITID": "",
            "lgCLIENTID": "",
            "lgCOMPANYID": "",
            "lgRISQUEID": "",
            "lgTIERSPAYANTID": tiersPayantId,
            "lgTYPECLIENTID": "2",
            "lgVILLEID": "",
            "remiseId": "",
            "strADRESSE": "",
            "strCODEPOSTAL": "",
            "strFIRSTNAME": firstName,
            "strLASTNAME": lastName,
            "strNUMEROSECURITESOCIAL": numSecu,
            "strSEXE": "",
          }),
          what: 'créer le client carnet',
          write: true,
        ),
        'client',
        ClientAssurance.fromJson,
      );

  Map<String, dynamic> _clientBase(ClientAssurance client) {
    final mainTp = client.tiersPayants.firstWhere((tp) => tp.principal || tp.order == 1, orElse: () => client.tiersPayants.first);
    return {
      "bIsAbsolute": false,
      "compteTp": mainTp.compteTp,
      "dblQUOTACONSOMENSUELLE": 0,
      "dbPLAFONDENCOURS": 0,
      "dtNAISSANCE": "",
      "intPOURCENTAGE": mainTp.taux,
      "intPRIORITY": mainTp.order,
      "lgCATEGORIEAYANTDROITID": "",
      "lgCLIENTID": client.lgCLIENTID,
      "lgCOMPANYID": "",
      "lgRISQUEID": "",
      "lgTIERSPAYANTID": mainTp.lgTIERSPAYANTID,
      "lgTYPECLIENTID": "1",
      "lgVILLEID": "",
      "strADRESSE": "",
      "strCODEPOSTAL": "",
      "strFIRSTNAME": client.strFIRSTNAME,
      "strLASTNAME": client.strLASTNAME,
      "strNUMEROSECURITESOCIAL": mainTp.numSecurity,
      "strSEXE": "",
    };
  }

  @override
  Future<VenteResult<ClientAssurance>> addTiersPayantToClient({required ClientAssurance client, required Map<String, dynamic> newTiersPayantPayload}) async {
    if (client.tiersPayants.isEmpty) return const VenteRefused('Ce client n\'a aucun tiers payant principal.');
    return _object(
      await _call(
        () => _dio.post('/client/add/assurance', data: {..._clientBase(client), "tiersPayants": [newTiersPayantPayload]}),
        what: 'ajouter le tiers payant',
        write: true,
      ),
      'client',
      ClientAssurance.fromJson,
    );
  }

  @override
  Future<VenteResult<ClientAssurance>> updateClientAssurance({required ClientAssurance client, required List<Map<String, dynamic>> tiersPayantsPayload}) async {
    if (client.tiersPayants.isEmpty) return const VenteRefused('Ce client n\'a aucun tiers payant principal.');
    return _object(
      await _call(
        () => _dio.post('/client/add/assurance', data: {..._clientBase(client), "tiersPayants": tiersPayantsPayload}),
        what: 'mettre à jour les tiers payants',
        write: true,
      ),
      'client',
      ClientAssurance.fromJson,
    );
  }

  @override
  Future<VenteResult<String>> addItemAssurance({
    required String produitId,
    required int qte,
    required int itemPu,
    required String clientId,
    required String ayantDroitId,
    required String natureVenteId,
    required String typeVenteId,
    required String? userVendeurId,
    required List<VenteTp> tierspayants,
    String? venteId,
  }) async {
    final first = venteId == null;
    final r = await _call(
      () => _dio.post(first ? '/vente/add/assurance' : '/vente/add/item', data: {
        "ayantDroitId": ayantDroitId,
        "clientId": clientId,
        "devis": false,
        "itemPu": itemPu,
        "natureVenteId": natureVenteId,
        "prevente": true,
        "produitId": produitId,
        "qte": qte,
        "qteServie": qte,
        "remiseId": null,
        "tierspayants": _tp(tierspayants),
        "typeVenteId": typeVenteId,
        "userVendeurId": userVendeurId,
        "venteId": venteId,
      }),
      what: 'ajouter le produit',
      write: true,
    );
    return _saleId(r, venteId);
  }

  @override
  Future<VenteResult<AssuranceSaleSummary>> netAssurance({required String venteId, required List<VenteTp> tierspayants}) async {
    final r = await _call(
      () => _dio.post('/vente/net/assurance', data: {"remiseId": null, "tierspayants": _tp(tierspayants), "venteId": venteId}),
      what: 'calculer le net',
    );
    if (r is! VenteOk) return r.map((_) => throw StateError('inutilisé'));
    try {
      return VenteOk(AssuranceSaleSummary.fromNetResponse(Map<String, dynamic>.from(r.value as Map)));
    } catch (e) {
      return VenteFailed('Net illisible : $e');
    }
  }

  @override
  Future<VenteResult<Map<String, dynamic>>> cloturerAssurance({
    required String venteId,
    required String clientId,
    required String ayantDroitId,
    required String natureVenteId,
    required String typeVenteId,
    required String? userVendeurId,
    required AssuranceSaleSummary summary,
    required String typeReglementId,
    required List<VenteTp> tierspayants,
    int? montantRecu,
    int? montantRemis,
  }) async {
    final r = await _call(
      () => _dio.post('/vente/cloturer/assurance', data: {
        "ayantDroitId": ayantDroitId,
        "banque": "",
        "clientId": clientId,
        "commentaire": "",
        "data": summary.toJson(),
        "devis": false,
        "lieux": "",
        "marge": summary.marge,
        "medecinId": null,
        "montantPaye": summary.montantNet,
        "montantRecu": montantRecu ?? summary.montantNet,
        "montantRemis": montantRemis ?? 0,
        "natureVenteId": natureVenteId,
        "nom": "",
        "partTP": summary.montantTp.toString(),
        "reglements": [
          {"montant": summary.montantNet, "montantAttentu": summary.montantNet, "typeReglement": typeReglementId}
        ],
        "remiseId": null,
        "sansBon": false,
        "tierspayants": [
          for (final tp in tierspayants)
            {
              "activeTiersPayant": false,
              "cmu": false,
              "compteTp": tp.compteTp,
              "dblPLAFOND": 0,
              "dblQUOTACONSOMENSUELLE": 0,
              "dbPLAFONDENCOURS": 0,
              "discount": 0,
              "enabled": false,
              "numBon": tp.numBon,
              "numSecurity": "",
              "order": 0,
              "principal": false,
              "taux": tp.taux,
              "tpnet": summary.tierspayants
                  .firstWhere((ts) => ts.compteTp == tp.compteTp,
                      orElse: () => TiersPayantSummary(numBon: '', taux: 0, compteTp: '', tpnet: 0))
                  .tpnet,
            }
        ],
        "totalRecap": summary.montant,
        "typeRegleId": typeReglementId,
        "typeVenteId": typeVenteId,
        "userVendeurId": userVendeurId,
        "venteId": venteId,
      }),
      what: 'valider la vente',
      write: true,
    );
    return _closeResult(r);
  }
}
