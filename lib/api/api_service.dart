// lib/api/api_service.dart
// 10/11/2025 09:00 (Ajout updateClientAssurance)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/serveur/adresse_serveur.dart';
import 'package:prestige_vente_app/api/models/article_analysis_model.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/proforma_models.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/product_stats.dart';
import 'package:prestige_vente_app/api/models/product_search_result.dart';
import 'package:prestige_vente_app/api/models/commande.dart';
import 'package:prestige_vente_app/api/models/commande_item.dart';
import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/api/models/bon_livraison_item.dart';
import 'package:prestige_vente_app/api/models/rayon.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/api/models/product_info.dart';
import 'package:prestige_vente_app/services/classement_code.dart';

import 'package:prestige_vente_app/api/models/nature_vente.dart';
import 'package:prestige_vente_app/api/models/type_vente.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/caisse_models.dart';
import 'package:prestige_vente_app/api/models/perime_models.dart';

import 'package:prestige_vente_app/api/models/stock_report_models.dart';
import 'package:prestige_vente_app/api/models/reception_model.dart';

import 'package:prestige_vente_app/api/models/licence_model.dart';
import 'package:prestige_vente_app/api/models/licence_lookup.dart';
import 'package:prestige_vente_app/api/models/depot_model.dart'; // Pour DepotSaleListItem
import 'package:prestige_vente_app/api/models/ajustement.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart' show ProductPage;

/// Cause d'un échec de connexion ([ApiService.login]).
class EchecConnexion {
  static const refusee = 'refusee';
  static const reseau = 'reseau';

  /// 4.3.2 : Prestige absent ou en cours de (re)démarrage (404 sur la connexion, 502 / 503 / 504, connexion refusée
  /// par le poste serveur) : ce n'est jamais un mot de passe faux.
  static const indisponible = 'indisponible';

  /// Message affiché pendant un redéploiement de Prestige (les deux interfaces, la borne).
  static const messageIndisponible = 'Serveur indisponible, veuillez réessayer.';

  final String type;
  final String message;
  const EchecConnexion(this.type, this.message);
  bool get estRefus => type == refusee;

  /// Codes HTTP d'un serveur Prestige indisponible (application non déployée ou en redémarrage, proxy) : 404 sur
  /// une route de connexion, 502, 503, 504.
  static bool codeIndisponible(int? code) => code == 404 || code == 502 || code == 503 || code == 504;

  /// Échec d'une requête de connexion qui vient du serveur indisponible (code ci-dessus, connexion refusée ou
  /// coupée) — jamais des identifiants.
  static bool serveurIndisponible(DioException e) {
    final code = e.response?.statusCode;
    if (code != null) return codeIndisponible(code);
    return e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout || e.error is SocketException;
  }
}

/// Échec de chargement d'une liste (à distinguer d'une liste vide).
class ApiLoadException implements Exception {
  final String message;
  const ApiLoadException(this.message);

  @override
  String toString() => message;
}

class ApiService {
  late Dio _dio;

  ApiService({required String baseUrl}) {
    _dio = DioClient.getClient(baseUrl);
  }

  /// Client HTTP partagé (utilisé par la passerelle des ventes, qui gère ses propres erreurs).
  Dio get dio => _dio;

  // ... (Toutes les méthodes existantes restent inchangées) ...
  /// Connexion. Le serveur renouvelle l'identifiant de session (JSESSIONID) à chaque connexion : on repart d'un
  /// pot à cookies vide pour que seul le cookie de la RÉPONSE de connexion soit envoyé ensuite (un ancien cookie,
  /// par ex. reçu à la lecture de la licence, provoquerait des 401 sur toutes les routes de données).
  Future<User?> login(String login, String password) async {
    dernierEchecConnexion = null;
    try {
      await DioClient.cookieJar.deleteAll();
      final response = await _dio.post('/user/auth', data: {'login': login, 'password': password});
      if (response.statusCode == 200 && response.data is Map && response.data['success'] == true) {
        return User.fromJson(response.data);
      }
      final msg = response.data is Map ? '${response.data['msg'] ?? ''}'.trim() : '';
      dernierEchecConnexion = EchecConnexion(EchecConnexion.refusee, msg.isEmpty ? 'Identifiants refusés par le serveur.' : msg);
      return null;
    } on DioException catch (e) {
      print("Error logging in: $e");
      final code = e.response?.statusCode;
      final tls = ErreurTls.de(e);
      // 4.3.2 : Prestige en cours de redéploiement (404 HTML de Payara, 502/503, connexion refusée) → « Serveur
      // indisponible, veuillez réessayer » ; jamais « mot de passe incorrect » ni « erreur 404 ».
      dernierEchecConnexion = tls != null
          ? EchecConnexion(EchecConnexion.reseau, tls.message)
          : EchecConnexion.serveurIndisponible(e)
              ? const EchecConnexion(EchecConnexion.indisponible, EchecConnexion.messageIndisponible)
              : code != null
                  ? EchecConnexion(EchecConnexion.refusee, 'Le serveur a répondu HTTP $code.')
                  : const EchecConnexion(EchecConnexion.reseau,
                      'Serveur injoignable : vérifiez le Wi-Fi et l\'adresse du serveur (Réglages › Connexion).');
      return null;
    }
  }

  /// Cause du dernier échec de [login] (null : réussi ou jamais tenté) — borne (4.1.2) : « connexion refusée »
  /// ≠ « serveur injoignable ».
  EchecConnexion? dernierEchecConnexion;
  Future<void> logout() async { try { await _dio.post('/user/logout'); } catch (e) { print("Error logging out: $e"); } }
  Future<Officine?> fetchOfficineInfo() async { try { final response = await _dio.get('/officine'); if (response.statusCode == 200 && response.data is List && response.data.isNotEmpty) { return Officine.fromJson(response.data[0]); } return null; } catch (e) { print("Error fetching officine info: $e"); return null; } }
  Future<List<ProductSearchResult>> searchProducts(String query) async { try { final response = await _dio.get( '/vente/search', queryParameters: {'query': query, 'page': 1, 'start': 0, 'limit': 30}, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List) .map((item) => ProductSearchResult.fromJson(item)) .toList(); } return []; } catch (e) { print("Error searching products: $e"); return []; } }
  Future<String?> addItemToSale({ required String produitId, required int qte, required int itemPu, String? venteId, bool isPrevente = false, }) async { try { const typeVenteId = "1"; const natureVenteId = "1"; final bool isFirstItem = venteId == null; final String endpoint = isFirstItem ? '/vente/add/vno' : '/vente/add/item'; final Map<String, dynamic> data = { "typeVenteId": typeVenteId, "natureVenteId": natureVenteId, "produitId": produitId, "itemPu": itemPu, "qte": qte, "qteServie": qte, "devis": false, "venteId": venteId, "prevente": isPrevente, "remiseId": null, "userVendeurId": null }; final response = await _dio.post(endpoint, data: data); if (response.statusCode == 200 && response.data['success'] == true) { return isFirstItem ? response.data['data']['lgPREENREGISTREMENTID'] : venteId; } return null; } catch (e) { print("Error adding item to sale: $e"); return null; } }
  Future<List<SaleItemDetail>> getSaleDetails(String venteId) async { try { final response = await _dio.get( '/vente/deatails', queryParameters: { 'venteId': venteId, 'page': 1, 'start': 0, 'limit': 100 }, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List).map((item) => SaleItemDetail.fromJson(item)).toList(); } return []; } catch (e) { print("Error getting sale details: $e"); return []; } }
  Future<bool> removeItemFromSale(String itemId) async { try { final response = await _dio.post('/vente/remove/vno/item/$itemId'); return response.statusCode == 200 && response.data['success'] == true; } catch (e) { print("Error removing item: $e"); return false; } }
  Future<bool> updateSaleItem({ required String itemId, required String produitId, required int qte, required int itemPu, }) async { try { final response = await _dio.post('/vente/update/item/vno', data: { "itemId": itemId, "produitId": produitId, "qte": qte, "qteServie": qte, "itemPu": itemPu, }); return response.statusCode == 200 && response.data['success'] == true; } catch (e) { print("Error updating item: $e"); return false; } }
  Future<SaleSummary?> calculateNet(String venteId) async { try { final response = await _dio.post( '/vente/net/vno', data: {"venteId": venteId, "checkUg": false}); if (response.statusCode == 200 && response.data['success'] == true) { return SaleSummary.fromNetResponse(response.data); } return null; } catch (e) { print("Error calculating net: $e"); return null; } }
  Future<List<PaymentMethod>> getPaymentMethods() async { try { final response = await _dio.get('/common/reglement', queryParameters: {'page': 1, 'start': 0, 'limit': 25} ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List).map((e) => PaymentMethod.fromJson(e)).toList(); } return []; } catch (e) { print("Error fetching payment methods: $e"); return []; } }
  Future<bool> updateClientForSale(String venteId, String clientId) async { try { final response = await _dio.post( '/vente/update/client', data: {"clientId": clientId, "venteId": venteId}, ); return response.statusCode == 200 && response.data['success'] == true; } catch (e) { print("Error updating client for sale: $e"); return false; } }
  Future<Map<String, dynamic>> cloturerVente({ required String venteId, required SaleSummary summary, required String typeReglementId, required String clientId, required String userVendeurId, int? montantRecu, int? montantRemis, }) async { try { final response = await _dio.post('/vente/cloturer/vno', data: { "banque": "", "clientId": clientId, "commentaire": "", "data": summary.toJson(), "devis": false, "lieux": "", "marge": summary.marge, "medecinId": null, "montantPaye": summary.montantNet, "montantRecu": montantRecu ?? summary.montantNet, "montantRemis": montantRemis ?? 0, "natureVenteId": "1", "nom": "", "partTP": 0, "reglements": [ { "montant": summary.montantNet, "montantAttentu": summary.montantNet, "typeReglement": typeReglementId } ], "remiseId": null, "totalRecap": summary.montantNet, "typeRegleId": typeReglementId, "typeVenteId": "1", "userVendeurId": userVendeurId, "venteId": venteId }); return response.data; } catch (e) { print("Error closing sale: $e"); return {"success": false, "msg": "Erreur de connexion: $e"}; } }
  Future<bool> terminerPrevente(String venteId) async { try { final response = await _dio.put('/vente/terminerprevente/$venteId'); return response.statusCode == 200 && response.data['success'] == true; } catch (e) { print("Error terminating prevente: $e"); return false; } }
  Future<List<PreventeListItem>> getPreventes() async { try { final response = await _dio.get( '/ventestats/preventes', queryParameters: { 'statut': 'is_Process', 'limit': 9999, 'sort': '[{"property":"heure","direction":"DESC"}]', 'page': 1, 'start': 0, }); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List).map((item) => PreventeListItem.fromJson(item)).toList(); } return []; } catch (e) { print("Error fetching preventes: $e"); return []; } }
  Future<List<ProductAnnualSale>> getAnnualSales(String query, int year) async { try { final response = await _dio.get('/produit/stats/vente-annuelle', queryParameters: {'search': query, 'year': year}); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List).map((item) => ProductAnnualSale.fromJson(item)).toList(); } return []; } catch (e) { print("Error fetching annual sales: $e"); return []; } }
  Future<List<ProductDetails>> searchProductFiche(String query) async { try { final response = await _dio.get( '/produit-search/fiche', queryParameters: { 'search_value': query, 'page': 1, 'start': 0, 'limit': 20 }, ); if (response.statusCode == 200 && response.data['results'] is List) { return (response.data['results'] as List).map((item) => ProductDetails.fromJson(item)).toList(); } return []; } catch (e) { print("Error in searchProductFiche: $e"); return []; } }
  Future<List<ProductOrderHistory>> getProductOrderHistory(String productId, String dtStart, String dtEnd) async { try { final response = await _dio.get( '/commande/produit/commande/$productId', queryParameters: { 'dtStart': dtStart, 'dtEnd': dtEnd, 'page': 1, 'start': 0, 'limit': 9999 }, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List).map((item) => ProductOrderHistory.fromJson(item)).toList(); } return []; } catch (e) { print("Error fetching order history: $e"); return []; } }
  Future<bool> updateExpirationDate(String productId, String newDate) async { print('Mise à jour de la date de péremption pour $productId à $newDate'); await Future.delayed(const Duration(seconds: 1)); return true; }
  Future<ProductInfo?> getProductInfo(String codeCip) async { try { final response = await _dio.get( '/info', queryParameters: {'search': codeCip}, options: optionsInfo()); final lignes = response.statusCode == 200 ? lignesInfo(response.data) : null; if (lignes != null && lignes.isNotEmpty) { return ProductInfo.fromJson(ligneInfoDuCip(lignes, codeCip)!); } return null; } catch (e) { print("Error fetching product info: $e"); return null; } }
  /// Même requête que [getProductInfo], annulable (fiche produit quittée avant la réponse).
  Future<ProductInfo?> getProductInfoAnnulable(String codeCip, CancelToken cancelToken) async {
    try {
      final response = await _dio.get('/info', queryParameters: {'search': codeCip}, cancelToken: cancelToken, options: optionsInfo());
      final lignes = response.statusCode == 200 ? lignesInfo(response.data) : null;
      if (lignes != null && lignes.isNotEmpty) return ProductInfo.fromJson(ligneInfoDuCip(lignes, codeCip)!);
      return null;
    } catch (_) {
      return null;
    }
  }
  Future<bool> addLot({ required String produitId, required String datePeremption, required String numLot, required int quantity, }) async { try { final response = await _dio.post( '/fichearticle/add-lot', data: { "produitId": produitId, "datePeremption": datePeremption, "numLot": numLot, "quantity": quantity }, ); return response.statusCode == 202; } catch (e) { print("Error adding lot: $e"); return false; } }
  Future<List<Commande>> getCommandes() => _loadList(
        'commandes',
        () => _dio.get('/commande/list', queryParameters: {'page': 1, 'start': 0, 'limit': 100}),
        Commande.fromJson,
      );
  Future<List<CommandeItem>> getCommandeItems(String orderId) => _loadList(
        'produits de la commande',
        () => _dio.get('/commande/commande-en-cours-items', queryParameters: {'orderId': orderId, 'page': 1, 'start': 0, 'limit': 9999}),
        CommandeItem.fromJson,
      );
  Future<bool> postCheckedQuantity({ required String detailId, required int quantity, }) async { try { final response = await _dio.post( '/commande/item/checked-quantities', data: { "id": detailId, "checked": true, "checkedQuantity": quantity}, ); return response.statusCode == 200; } catch (e) { print("Error posting checked quantity: $e"); return false; } }
  Future<List<BonLivraison>> getBonsLivraison({String query = '', String? dtStart, String? dtEnd}) {
    final queryParameters = <String, dynamic>{
      'query': query,
      'page': 1,
      'start': 0,
      'limit': 9999,
      'sort': '[{"property":"dt_DATE_LIVRAISON","direction":"ASC"}]',
      'statut': 'is_Closed',
    };
    if (dtStart != null && dtStart.isNotEmpty) queryParameters['dtStart'] = dtStart;
    if (dtEnd != null && dtEnd.isNotEmpty) queryParameters['dtEnd'] = dtEnd;
    return _loadList('bons de livraison', () => _dio.get('/commande/list-bons', queryParameters: queryParameters), BonLivraison.fromJson);
  }
  Future<List<BonLivraisonItem>> getBonLivraisonItems(String blId) => _loadList(
        'lignes du BL',
        () => _dio.get('/commande/bon/items/$blId', queryParameters: {'page': 1, 'start': 0, 'limit': 9999}),
        BonLivraisonItem.fromJson,
      );
  Future<bool> postBonItemCheckedQuantity({ required String detailId, required int quantity, }) async { try { final response = await _dio.post( '/commande/bon/items/checked-quantities', data: { "id": detailId, "checked": true, "checkedQuantity": quantity}, ); return response.statusCode == 200 || response.statusCode == 202; } catch (e) { print("Error posting BL checked quantity: $e"); return false; } }
  Future<List<Rayon>> getRayons() async { try { final response = await _dio.get( '/common/rayons', queryParameters: { 'query': '', 'page': 1, 'start': 0, 'limit': 9999 }, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List).map((r) => Rayon.fromJson(r)).toList(); } return []; } catch (e) { print("Error fetching rayons: $e"); return []; } }
  Future<bool> updateLiteInfo(Map<String, dynamic> data) async { try { final response = await _dio.post( '/fichearticle/produit/update-lite-info', data: data, ); if (response.statusCode == 202) { return true; } if (response.statusCode == 200 && response.data['success'] == true) { return true; } return false; } on DioException catch (e) { if (e.response?.statusCode == 202) return true; print("Error in updateLiteInfo: $e"); return false; } catch (e) { print("Error in updateLiteInfo: $e"); return false; } }
  Future<List<PaymentMethodQr>> getPaymentMethodsWithQr() async { try { final response = await _dio.get( '/modereglement/all', queryParameters: { 'page': 1, 'start': 0, 'limit': 20 }, ); if (response.statusCode == 200 && response.data['data'] is List) { final List data = response.data['data']; final List<PaymentMethodQr> methods = []; for (var item in data) { if (item is Map<String, dynamic>) { methods.add(PaymentMethodQr.fromJson(item)); } } return methods; } return []; } catch (e) { print("Error fetching payment methods with QR: $e"); return []; } }
  Future<ProductInfo?> getProductInfoForStats(String codeCip) async { try { final response = await _dio.get('/info', queryParameters: { 'search': codeCip }, options: optionsInfo()); final lignes = response.statusCode == 200 ? lignesInfo(response.data) : null; if (lignes != null && lignes.isNotEmpty) { return ProductInfo.fromJson(ligneInfoDuCip(lignes, codeCip)!); } return null; } catch (e) { print("Error fetching product info for stats: $e"); return null; } }
  Future<List<ProductInfo>> searchProductInfoForSearch(String query) async { try { final response = await _dio.get( '/info', queryParameters: { 'search': query }, options: optionsInfo()); final lignes = response.statusCode == 200 ? lignesInfo(response.data) : null; if (lignes != null) { return lignes.map(ProductInfo.fromJson).toList(); } return []; } catch (e) { print("Error in searchProductInfoForSearch: $e"); return []; } }
  Future<ProductDetails?> getProductDetailsForSearch(String codeCip) async { try { final response = await _dio.get( '/produit-search/fiche', queryParameters: { 'search_value': codeCip, 'page': 1, 'start': 0, 'limit': 1 }, ); if (response.statusCode == 200 && response.data['results'] is List) { final results = response.data['results'] as List; if (results.isNotEmpty) { return ProductDetails.fromJson(results.first); } } return null; } catch (e) { print("Error in getProductDetailsForSearch: $e"); return null; } }

  // --- État de Stock : un échec de chargement lève [ApiLoadException] (≠ liste vide) ---
  Future<List<Grossiste>> getGrossistes() => _loadList(
        'grossistes',
        () => _dio.get('/common/grossiste', queryParameters: {'query': '', 'page': 1, 'start': 0, 'limit': 9999}),
        Grossiste.fromJson,
      );

  /// Emplacements pour les filtres (même requête que [getRayons], mais l'échec est signalé).
  Future<List<Rayon>> getRayonsForFilters() => _loadList(
        'emplacements',
        () => _dio.get('/common/rayons', queryParameters: {'query': '', 'page': 1, 'start': 0, 'limit': 9999}),
        Rayon.fromJson,
      );

  Future<Map<String, dynamic>> getStockReport({
    String query = '',
    String codeRayon = '',
    String codeGrossiste = '',
    String filtreStock = '', // EQUAL, GREATER, etc.
    String stockValue = '',  // La valeur numérique (ex: 10)
    int page = 1,
    int limit = 20,
  }) async {
    Response<dynamic>? raw;
    final items = await _loadList(
      'articles',
      () async => raw = await _dio.get(
        '/fichearticle/comparaison',
        queryParameters: {
          'query': query,
          'codeRayon': codeRayon,
          'codeGrossiste': codeGrossiste,
          'filtreStock': filtreStock,
          'stock': stockValue,
          'seuil': '',
          'filtreSeuil': '',
          'codeFamile': '',
          'page': page,
          'start': (page - 1) * limit,
          'limit': limit
        },
        // 4.1.2 : annulable (recherche remplacée par la frappe suivante, ApiService.avecJeton) et délai de
        // réception de 30 s au lieu des 10 s du client : le serveur relit pour CHAQUE ligne la date du dernier
        // bon, de la dernière entrée, du dernier inventaire et de la dernière vente (docs/serveur/DEMANDE_PERFORMANCE_INFO.md).
        cancelToken: jetonDeLaZone(),
        options: Options(receiveTimeout: delaiInfo),
      ),
      StockReportItem.fromJson,
    );
    final body = raw?.data;
    final total = body is Map ? body['total'] : null;
    return {
      'data': items,
      'total': total is num ? total.toInt() : (int.tryParse('${total ?? ''}') ?? items.length),
    };
  }

  // --- VENTE ASSURANCE / CARNET ---
  Future<List<NatureVente>> getNaturesVente() async { try { final response = await _dio.get( '/common/natures', queryParameters: { 'page': 1, 'start': 0, 'limit': 25 }, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List) .map((e) => NatureVente.fromJson(e)) .toList(); } return []; } catch (e) { print("Error fetching natures vente: $e"); return []; } }
  Future<List<TypeVente>> getTypeVentes() async { try { final response = await _dio.get( '/common/typeventes', queryParameters: { 'page': 1, 'start': 0, 'limit': 25 }, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List) .map((e) => TypeVente.fromJson(e)) .toList(); } return []; } catch (e) { print("Error fetching type ventes: $e"); return []; } }
  Future<List<ClientAssurance>> searchClientAssurance(String query) async { try { final response = await _dio.get( '/client/all', queryParameters: { 'query': query, 'typeClientId': '1', 'page': 1, 'start': 0, 'limit': 25 }, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List) .map((e) => ClientAssurance.fromJson(e)) .toList(); } return []; } catch (e) { print("Error searching client assurance: $e"); return []; } }
  Future<List<TiersPayantAssurance>> searchTiersPayantsAssurance(String query) async { try { final response = await _dio.get( '/client/tiers-payants/assurance', queryParameters: { 'query': query, 'page': 1, 'start': 0, 'limit': 25 }, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List) .map((e) => TiersPayantAssurance.fromJson(e)) .toList(); } return []; } catch (e) { print("Error searching tiers payants assurance: $e"); return []; } }
  Future<ClientAssurance?> createClientAssurance({ required String firstName, required String lastName, required String numSecu, required String tiersPayantId, required int pourcentage, }) async { try { final response = await _dio.post( '/client/add/assurance', data: { "bIsAbsolute": false, "compteTp": "", "dblQUOTACONSOMENSUELLE": 0, "dbPLAFONDENCOURS": 0, "dtNAISSANCE": "", "intPOURCENTAGE": pourcentage, "intPRIORITY": 1, "lgCATEGORIEAYANTDROITID": "", "lgCLIENTID": "", "lgCOMPANYID": "", "lgRISQUEID": "", "lgTIERSPAYANTID": tiersPayantId, "lgTYPECLIENTID": "1", "lgVILLEID": "", "strADRESSE": "", "strCODEPOSTAL": "", "strFIRSTNAME": firstName, "strLASTNAME": lastName, "strNUMEROSECURITESOCIAL": numSecu, "strSEXE": "", "tiersPayants": [] }, ); if (response.statusCode == 200 && response.data['success'] == true) { return ClientAssurance.fromJson(response.data['data']); } return null; } catch (e) { print("Error creating client assurance: $e"); return null; } }
  Future<ClientAssurance?> addTiersPayantToClient({ required ClientAssurance existingClient, required Map<String, dynamic> newTiersPayantPayload, }) async { try { final mainTp = existingClient.tiersPayants.firstWhere( (tp) => tp.principal || tp.order == 1, orElse: () => existingClient.tiersPayants.first ); final response = await _dio.post( '/client/add/assurance', data: { "bIsAbsolute": false, "compteTp": mainTp.compteTp, "dblQUOTACONSOMENSUELLE": 0, "dbPLAFONDENCOURS": 0, "dtNAISSANCE": "", "intPOURCENTAGE": mainTp.taux, "intPRIORITY": mainTp.order, "lgCATEGORIEAYANTDROITID": "", "lgCLIENTID": existingClient.lgCLIENTID, "lgCOMPANYID": "", "lgRISQUEID": "", "lgTIERSPAYANTID": mainTp.lgTIERSPAYANTID, "lgTYPECLIENTID": "1", "lgVILLEID": "", "strADRESSE": "", "strCODEPOSTAL": "", "strFIRSTNAME": existingClient.strFIRSTNAME, "strLASTNAME": existingClient.strLASTNAME, "strNUMEROSECURITESOCIAL": mainTp.numSecurity, "strSEXE": "", "tiersPayants": [ newTiersPayantPayload ] }, ); if (response.statusCode == 200 && response.data['success'] == true) { return ClientAssurance.fromJson(response.data['data']); } print("Error adding tiers payant (API): ${response.data['msg']}"); return null; } catch (e) { print("Error adding tiers payant to client: $e"); return null; } }
  Future<List<AyantDroit>> getAyantDroits(String clientId) async { try { final response = await _dio.get( '/client/ayant-droits', queryParameters: { 'clientId': clientId }, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List) .map((e) => AyantDroit.fromJson(e)) .toList(); } return []; } catch (e) { print("Error fetching ayant droits: $e"); return []; } }
  Future<AyantDroit?> createAyantDroit({ required String clientId, required String firstName, required String lastName, required String numSecu, String? dtNaissance, }) async { try { final response = await _dio.post( '/client/ayant-droits/$clientId', data: { "dtNAISSANCE": dtNaissance ?? "", "lgVILLEID": "", "strFIRSTNAME": firstName, "strLASTNAME": lastName, "strNUMEROSECURITESOCIAL": numSecu }, ); if (response.statusCode == 200 && response.data['success'] == true) { return AyantDroit.fromJson(response.data['data']); } return null; } catch (e) { print("Error creating ayant droit: $e"); return null; } }
  Map<String, dynamic> _buildAssuranceSalePayload({ required String produitId, required int qte, required int itemPu, required String clientId, required String ayantDroitId, required String natureVenteId, required String typeVenteId, required String? userVendeurId, required List<Map<String, dynamic>> tierspayants, String? venteId, }) { return { "ayantDroitId": ayantDroitId, "clientId": clientId, "devis": false, "itemPu": itemPu, "natureVenteId": natureVenteId, "prevente": true, "produitId": produitId, "qte": qte, "qteServie": qte, "remiseId": null, "tierspayants": tierspayants.map((tp) => { "cmu": "false", "compteTp": tp['compteTp'], "numBon": tp['numBon'], "taux": tp['taux'] }).toList(), "typeVenteId": typeVenteId, "userVendeurId": userVendeurId, "venteId": venteId }; }
  Future<String?> addAssuranceSaleItem({ required String produitId, required int qte, required int itemPu, required String clientId, required String ayantDroitId, required String natureVenteId, required String typeVenteId, required String? userVendeurId, required List<Map<String, dynamic>> tierspayants, String? venteId, }) async { try { final bool isFirstItem = venteId == null; final String endpoint = isFirstItem ? '/vente/add/assurance' : '/vente/add/item'; final payload = _buildAssuranceSalePayload( produitId: produitId, qte: qte, itemPu: itemPu, clientId: clientId, ayantDroitId: ayantDroitId, natureVenteId: natureVenteId, typeVenteId: typeVenteId, userVendeurId: userVendeurId, tierspayants: tierspayants, venteId: venteId, ); final response = await _dio.post(endpoint, data: payload); if (response.statusCode == 200 && response.data['success'] == true) { return response.data['data']['lgPREENREGISTREMENTID'] ?? venteId; } return null; } catch (e) { print("Error adding assurance sale item: $e"); return null; } }
  Future<AssuranceSaleSummary?> calculateNetAssurance({ required String venteId, required List<Map<String, dynamic>> tierspayants, }) async { try { final response = await _dio.post( '/vente/net/assurance', data: { "remiseId": null, "tierspayants": tierspayants.map((tp) => { "cmu": "false", "compteTp": tp['compteTp'], "numBon": tp['numBon'], "taux": tp['taux'] }).toList(), "venteId": venteId }, ); if (response.statusCode == 200 && response.data['success'] == true) { return AssuranceSaleSummary.fromNetResponse(response.data); } return null; } catch (e) { print("Error calculating net assurance: $e"); return null; } }
  Future<Map<String, dynamic>> cloturerVenteAssurance({ required String venteId, required String clientId, required String ayantDroitId, required String natureVenteId, required String typeVenteId, required String? userVendeurId, required AssuranceSaleSummary summary, required String typeReglementId, required List<Map<String, dynamic>> tierspayants, int? montantRecu, int? montantRemis, }) async { try { final response = await _dio.post( '/vente/cloturer/assurance', data: { "ayantDroitId": ayantDroitId, "banque": "", "clientId": clientId, "commentaire": "", "data": summary.toJson(), "devis": false, "lieux": "", "marge": summary.marge, "medecinId": null, "montantPaye": summary.montantNet, "montantRecu": montantRecu ?? summary.montantNet, "montantRemis": montantRemis ?? 0, "natureVenteId": natureVenteId, "nom": "", "partTP": summary.montantTp.toString(), "reglements": [ { "montant": summary.montantNet, "montantAttentu": summary.montantNet, "typeReglement": typeReglementId } ], "remiseId": null, "sansBon": false, "tierspayants": tierspayants.map((tp) => { "activeTiersPayant": false, "cmu": false, "compteTp": tp['compteTp'], "dblPLAFOND": 0, "dblQUOTACONSOMENSUELLE": 0, "dbPLAFONDENCOURS": 0, "discount": 0, "enabled": false, "numBon": tp['numBon'], "numSecurity": "", "order": 0, "principal": false, "taux": tp['taux'], "tpnet": summary.tierspayants.firstWhere((ts) => ts.compteTp == tp['compteTp'], orElse: () => TiersPayantSummary(numBon: '', taux: 0, compteTp: '', tpnet: 0)).tpnet }).toList(), "totalRecap": summary.montant, "typeRegleId": typeReglementId, "typeVenteId": typeVenteId, "userVendeurId": userVendeurId, "venteId": venteId }, ); return response.data; } catch (e) { print("Error closing assurance sale: $e"); return { "success": false, "msg": "Erreur de connexion: $e" }; } }
  Future<OuvertureData?> getOuvertureData() async { try { final response = await _dio.get('/billetage/ouventure-data'); if (response.statusCode == 200 && response.data['data'] != null) { return OuvertureData.fromJson(response.data['data']); } return null; } catch (e) { print("Error fetching ouverture data: $e"); return null; } }
  Future<bool> ouvrirCaisse() async { try { final response = await _dio.post( '/caisse/ouvrir-caisse', data: { "amount": "0", "id": "" }, ); return response.statusCode == 200 && response.data['mvtId'] != null; } catch (e) { print("Error opening caisse: $e"); return false; } }
  Future<ClotureData?> getClotureData() async { try { final response = await _dio.get('/billetage/cloture-data'); if (response.statusCode == 200 && response.data['data'] != null) { return ClotureData.fromJson(response.data['data']); } return null; } catch (e) { print("Error fetching cloture data: $e"); return null; } }
  Future<bool> cloturerCaisse({ required String resumeCaisseId, required Map<String, int> billetage, }) async { try { final payload = { ...billetage, "resumeCaisseId": resumeCaisseId, }; final response = await _dio.post( '/billetage/cloture', data: payload, ); return response.statusCode == 200 && response.data['success'] == true; } catch (e) { print("Error closing caisse: $e"); return false; } }
  Future<Map<String, dynamic>> getProduitsPerimes(int nbreMois) async { try { final response = await _dio.get( '/fichearticle/perimes', queryParameters: { 'nbreMois': nbreMois, 'page': 1, 'start': 0, 'limit': 9999 }, ); if (response.statusCode == 200 && response.data['data'] is List) { final data = (response.data['data'] as List).map((item) => ProduitPerime.fromJson(item)).toList(); final metaData = PerimeMetaData.fromJson(response.data['metaData'] ?? {}); return { 'data': data, 'metaData': metaData }; } return { 'data': <ProduitPerime>[], 'metaData': null }; } catch (e) { print("Error fetching produits perimes: $e"); return { 'data': <ProduitPerime>[], 'metaData': null }; } }
  Future<List<SaisiePerimeItem>> getSaisiePerimesHistory({ String? dtStart, String? dtEnd }) async { try { final params = <String, dynamic>{ 'page': 1, 'start': 0, 'limit': 100, }; if (dtStart != null) params['dtStart'] = dtStart; if (dtEnd != null) params['dtEnd'] = dtEnd; final response = await _dio.get( '/fichearticle/saisieperimes', queryParameters: params, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List).map((item) => SaisiePerimeItem.fromJson(item)).toList(); } return []; } catch (e) { print("Error fetching saisie perimes history: $e"); return []; } }
  Future<List<SaisieEnCoursItem>> getSaisiePerimesEnCours() async { try { final response = await _dio.get( '/gestionperime/saisie-encours', queryParameters: { 'page': 1, 'start': 0, 'limit': 20 }, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List).map((item) => SaisieEnCoursItem.fromJson(item)).toList(); } return []; } catch (e) { print("Error fetching saisie en cours: $e"); return []; } }
  Future<Map<String, dynamic>> addPerimeItem({ required String produitId, required String datePeremption, required String lot, required int quantite, }) async { try { final response = await _dio.post( '/gestionperime/add', data: { "ref": produitId, "refParent": datePeremption, "refTwo": lot, "value": quantite }, ); return response.data; } catch (e) { print("Error adding perime item: $e"); return { "success": false, "message": "Erreur de connexion" }; } }
  Future<bool> deletePerimeItem(String itemId) async { try { final response = await _dio.delete('/gestionperime/$itemId'); return response.statusCode == 200 || response.statusCode == 204; } catch (e) { print("Error deleting perime item: $e"); return false; } }
  Future<bool> closeSaisiePerimes(String batchId) async { try { final response = await _dio.put('/gestionperime/close/$batchId'); return response.statusCode == 200 && response.data['success'] == true; } catch (e) { print("Error closing saisie perimes: $e"); return false; } }
  Future<List<ClientAssurance>> searchClientCarnet(String query) async { try { final response = await _dio.get( '/client/all', queryParameters: { 'query': query, 'typeClientId': '2', 'page': 1, 'start': 0, 'limit': 25 }, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List).map((e) => ClientAssurance.fromJson(e)).toList(); } return []; } catch (e) { print("Error searching client carnet: $e"); return []; } }
  Future<List<TiersPayantAssurance>> searchTiersPayantCarnet(String query) async { try { final response = await _dio.get( '/client/tiers-payants/carnet', queryParameters: { 'query': query, 'page': 1, 'start': 0, 'limit': 25 }, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List).map((e) => TiersPayantAssurance.fromJson(e)).toList(); } return []; } catch (e) { print("Error searching tiers payants carnet: $e"); return []; } }
  Future<ClientAssurance?> createClientCarnet({ required String firstName, required String lastName, required String numSecu, required String tiersPayantId, }) async { try { final response = await _dio.post( '/client/add/carnet', data: { "bIsAbsolute": false, "compteTp": "", "dblQUOTACONSOMENSUELLE": 0, "dbPLAFONDENCOURS": 0, "dtNAISSANCE": "", "intPOURCENTAGE": 100, "intPRIORITY": 1, "lgCATEGORIEAYANTDROITID": "", "lgCLIENTID": "", "lgCOMPANYID": "", "lgRISQUEID": "", "lgTIERSPAYANTID": tiersPayantId, "lgTYPECLIENTID": "2", "lgVILLEID": "", "remiseId": "", "strADRESSE": "", "strCODEPOSTAL": "", "strFIRSTNAME": firstName, "strLASTNAME": lastName, "strNUMEROSECURITESOCIAL": numSecu, "strSEXE": "" }, ); if (response.statusCode == 200 && response.data['success'] == true) { return ClientAssurance.fromJson(response.data['data']); } return null; } catch (e) { print("Error creating client carnet: $e"); return null; } }

  // MODIFICATION : Nouvelle méthode pour mettre à jour tout le client (dont la liste des TPs)
  Future<ClientAssurance?> updateClientAssurance({
    required ClientAssurance existingClient,
    required List<Map<String, dynamic>> tiersPayantsPayload,
  }) async {
    try {
      final mainTp = existingClient.tiersPayants.firstWhere(
              (tp) => tp.principal || tp.order == 1,
          orElse: () => existingClient.tiersPayants.first
      );

      final response = await _dio.post(
        '/client/add/assurance',
        data: {
          "bIsAbsolute": false,
          "compteTp": mainTp.compteTp,
          "dblQUOTACONSOMENSUELLE": 0,
          "dbPLAFONDENCOURS": 0,
          "dtNAISSANCE": "",
          "intPOURCENTAGE": mainTp.taux,
          "intPRIORITY": mainTp.order,
          "lgCATEGORIEAYANTDROITID": "",
          "lgCLIENTID": existingClient.lgCLIENTID,
          "lgCOMPANYID": "",
          "lgRISQUEID": "",
          "lgTIERSPAYANTID": mainTp.lgTIERSPAYANTID,
          "lgTYPECLIENTID": "1",
          "lgVILLEID": "",
          "strADRESSE": "",
          "strCODEPOSTAL": "",
          "strFIRSTNAME": existingClient.strFIRSTNAME,
          "strLASTNAME": existingClient.strLASTNAME,
          "strNUMEROSECURITESOCIAL": mainTp.numSecurity,
          "strSEXE": "",
          // On envoie la LISTE COMPLETE des TPs
          "tiersPayants": tiersPayantsPayload
        },
      );
      if (response.statusCode == 200 && response.data['success'] == true) {
        return ClientAssurance.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      print("Error updating client tiers payants: $e");
      return null;
    }
  }

  // DANS lib/api/api_service.dart

  /// Supprime une vente globale (Dépôt ou autre) via son ID
  Future<bool> deleteSale(String saleId) async {
    try {
      // Adaptez l'URL si besoin, c'est celle que vous m'avez donnée
      final response = await _dio.post('/ventestats/remove/$saleId');
      return response.data == true;
    } catch (e) {
      print("Erreur suppression vente globale: $e");
      return false;
    }
  }

  // NOUVEAU : Récupération des bons de réception avec détails inclus
  Future<List<ReceptionBon>> getReceptionBons({
    String query = '',
    String? dtStart,
    String? dtEnd,
  }) {
    final queryParameters = <String, dynamic>{
      'search': query,
      'grossisteId': '',
      'page': 1,
      'start': 0,
      'limit': 9999,
      // Les paramètres de tri/groupe du JSON fourni
      'group': '[{"property":"fournisseurId","direction":"ASC"}]',
      'sort': '[{"property":"fournisseurId","direction":"ASC"}]',
    };
    if (dtStart != null) queryParameters['dtStart'] = dtStart;
    if (dtEnd != null) queryParameters['dtEnd'] = dtEnd;
    return _loadList(
      'bons de réception',
      () => _dio.get('/etat-control-bon/list', queryParameters: queryParameters),
      ReceptionBon.fromJson,
    );
  }

  /// Charge une liste `{data: [...]}`. Une liste vide n'est renvoyée que si le serveur
  /// a bien répondu ; un échec (réseau, session, erreur serveur, réponse illisible)
  /// lève [ApiLoadException] avec un message clair, pour ne pas le confondre avec « aucun résultat ».
  Future<List<T>> _loadList<T>(String what, Future<Response<dynamic>> Function() request, T Function(Map<String, dynamic>) parse) async =>
      (await _loadListWithBody(what, request, parse)).$1;

  /// Comme [_loadList], mais renvoie aussi le corps de la réponse (pour lire `total`).
  Future<(List<T>, Map)> _loadListWithBody<T>(
      String what, Future<Response<dynamic>> Function() request, T Function(Map<String, dynamic>) parse) async {
    final Response<dynamic> response;
    try {
      response = await request();
    } on DioException catch (e) {
      // Requête remplacée par une plus récente (recherche à chaque frappe) : l'appelant l'ignore.
      if (e.type == DioExceptionType.cancel) rethrow;
      throw ApiLoadException(_networkMessage(e, what));
    } catch (e) {
      throw ApiLoadException('Impossible de charger les $what : $e');
    }
    final code = response.statusCode ?? 0;
    if (code != 200) throw ApiLoadException('Le serveur a refusé le chargement des $what (code $code).');
    final body = response.data;
    if (body is! Map) {
      throw ApiLoadException('Réponse inattendue du serveur pour les $what. La session a peut-être expiré : reconnectez-vous.');
    }
    final data = body['data'];
    if (data == null) return (<T>[], body);
    if (data is! List) throw ApiLoadException('Réponse inattendue du serveur pour les $what.');
    try {
      return ([for (final item in data) parse(Map<String, dynamic>.from(item as Map))], body);
    } catch (e) {
      throw ApiLoadException('Données des $what illisibles : $e');
    }
  }

  static String _networkMessage(DioException e, String what) {
    final tls = ErreurTls.de(e);
    if (tls != null) return '${tls.message} ($what non chargés)';
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Le serveur met trop de temps à répondre ($what non chargés). Vérifiez le réseau puis réessayez.';
      case DioExceptionType.connectionError:
        return 'Serveur injoignable ($what non chargés). Vérifiez le Wi-Fi ou les données mobiles puis réessayez.';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        if (code == 401 || code == 403) return 'Session expirée ou accès refusé ($what). Reconnectez-vous.';
        return 'Erreur du serveur (code $code) lors du chargement des $what.';
      default:
        if (e.error is SocketException) {
          return 'Serveur injoignable ($what non chargés). Vérifiez le Wi-Fi ou les données mobiles puis réessayez.';
        }
        return 'Impossible de charger les $what : ${e.message ?? e.type.name}.';
    }
  }

  // --- Ajustement de stock : un échec de chargement lève [ApiLoadException] (≠ liste vide) ---
  Future<List<TypeAjustement>> getTypesAjustement() => _loadList(
        'motifs d\'ajustement',
        () => _dio.get('/common/type-ajustements', queryParameters: {'limit': 9999}),
        TypeAjustement.fromJson,
      );

  /// Recherche produit PAR PAGES (même URL que [searchProducts]) : renvoie aussi le `total` du serveur,
  /// pour afficher « 50 sur 120 » et charger la suite. Un échec lève [ApiLoadException] (≠ produit introuvable).
  Future<ProductPage> searchProductsPageOrFail(String query, int start, int limit) async {
    final (items, body) = await _loadListWithBody(
      'produits',
      () => _dio.get('/vente/search',
          queryParameters: {'query': query, 'page': start ~/ limit + 1, 'start': start, 'limit': limit}, cancelToken: jetonDeLaZone()),
      ProductSearchResult.fromJson,
    );
    final total = int.tryParse('${body['total'] ?? ''}');
    return ProductPage(items, total ?? items.length);
  }

  /// Même recherche que [searchProducts], mais un échec lève [ApiLoadException] (≠ produit introuvable).
  Future<List<ProductSearchResult>> searchProductsOrFail(String query) => _loadList(
        'produits',
        () => _dio.get('/vente/search', queryParameters: {'query': query, 'page': 1, 'start': 0, 'limit': 30}),
        ProductSearchResult.fromJson,
      );

  Future<List<AjustementItem>> getAjustementItems(String ajustementId) => _loadList(
        'lignes d\'ajustement',
        () => _dio.get('/ajustement/items', queryParameters: {
          'ajustementId': ajustementId,
          'limit': 100,
          'start': 0,
          'page': 1,
          // Anti-cache : timestamp pour forcer une réponse fraîche
          '_dc': DateTime.now().millisecondsSinceEpoch.toString(),
        }),
        AjustementItem.fromJson,
      );

  // --- GESTION LICENCE (AJOUT) ---

  /// 4.3.0 (demande 11, option A) : enregistrement de la licence avec la cause d'un refus. `GET v1/licence/save`
  /// exige une session : sans connexion le serveur répond 401 (ou 403 « Veuillez vous connecter ») →
  /// [sessionRequise] (« Activez la licence après connexion d'un administrateur »).
  Future<({bool ok, bool sessionRequise})> enregistrerLicence(String key) async {
    try {
      final response = await _dio.get('/licence/save/$key'); // même adresse qu'avant (clé telle quelle)
      return (ok: response.statusCode == 200, sessionRequise: false);
    } on DioException catch (e) {
      final r = e.response;
      final code = r?.statusCode;
      final texte = r?.data is String ? (r!.data as String).toLowerCase() : '';
      final session = code == 401 || (code == 403 && texte.contains('vous connecter'));
      return (ok: false, sessionRequise: session);
    } catch (_) {
      return (ok: false, sessionRequise: false);
    }
  }

  Future<bool> saveLicence(String key) async {
    try {
      // L'URL demandée est /licence/save/{key}
      final response = await _dio.get('/licence/save/$key');
      // On suppose que le backend renvoie 200 OK si l'enregistrement est réussi
      // Adaptez la vérification selon le retour exact de votre API (ex: response.data['success'])
      if (response.statusCode == 200) {
        return true;
      }
      return false;
    } catch (e) {
      print("Error saving licence: $e");
      return false;
    }
  }

  /// Vérification de licence qui distingue la cause d'un échec :
  /// serveur injoignable, application Prestige absente à cette adresse,
  /// erreur du serveur, ou réponse normale (licence présente / absente).
  Future<LicenceLookup> lookupLicence() async {
    try {
      final response = await _dio.get('/licence/find');
      final data = response.data;
      if (data == null || (data is String && data.trim().isEmpty)) {
        return const LicenceLookup.noLicence();
      }
      if (data is! Map) {
        return LicenceLookup.failure(LicenceIssue.unexpectedResponse, 'Réponse inattendue du serveur (${response.statusCode}).');
      }
      return LicenceLookup.found(LicenceModel.fromJson(Map<String, dynamic>.from(data)));
    } on DioException catch (e) {
      // HTTPS : certificat refusé (jamais contourné) ≠ serveur injoignable ≠ licence.
      final tls = ErreurTls.de(e);
      if (tls != null) {
        return LicenceLookup.failure(tls == ErreurTls.certificat ? LicenceIssue.certificate : LicenceIssue.notHttps, e.error?.toString() ?? e.message);
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return LicenceLookup.failure(LicenceIssue.unreachable, e.message ?? e.type.name);
        case DioExceptionType.badResponse:
          final code = e.response?.statusCode ?? 0;
          if (code == 404) {
            // 404 : soit l'application Prestige n'est pas déployée à cette adresse,
            // soit elle l'est et n'a simplement pas de licence enregistrée.
            return await _prestigeAppResponds()
                ? const LicenceLookup.noLicence()
                : LicenceLookup.failure(LicenceIssue.appNotFound, 'HTTP 404 sur ${e.requestOptions.uri}');
          }
          // 4.3.2 : 502 / 503 / 504 : Prestige (ou son proxy) en redémarrage → serveur indisponible, pas une erreur.
          if (EchecConnexion.codeIndisponible(code)) return LicenceLookup.failure(LicenceIssue.unreachable, 'HTTP $code');
          return LicenceLookup.failure(LicenceIssue.serverError, 'HTTP $code');
        default:
          if (e.error is SocketException) {
            return LicenceLookup.failure(LicenceIssue.unreachable, e.error.toString());
          }
          return LicenceLookup.failure(LicenceIssue.unreachable, e.message ?? e.toString());
      }
    } on SocketException catch (e) {
      return LicenceLookup.failure(LicenceIssue.unreachable, e.message);
    } on TlsException catch (e) {
      return LicenceLookup.failure(ErreurTls.de(e) == ErreurTls.certificat ? LicenceIssue.certificate : LicenceIssue.notHttps, e.toString());
    } catch (e) {
      return LicenceLookup.failure(LicenceIssue.unexpectedResponse, e.toString());
    }
  }

  /// L'application Prestige est-elle déployée à cette adresse ?
  /// On interroge une route REST connue (/user/auth, sans identifiants) : si l'application
  /// est déployée elle répond (400/401/500...), sinon Payara répond 404.
  Future<bool> _prestigeAppResponds() async {
    try {
      final r = await _dio.post('/user/auth',
          data: const {}, options: Options(validateStatus: (_) => true, responseType: ResponseType.plain));
      return (r.statusCode ?? 404) != 404;
    } catch (_) {
      return false;
    }
  }

  Future<LicenceModel?> findLicence() async {
    try {
      final response = await _dio.get('/licence/find');
      if (response.statusCode == 200 && response.data != null) {
        return LicenceModel.fromJson(response.data);
      }
      return null;
    } catch (e) {
      // Si 404 ou autre erreur, on considère qu'il n'y a pas de licence valide
      print("Error finding licence: $e");
      return null;
    }
  }

  // --- GESTION VENTE DEPOT ---

  // 1. Liste des ventes dépôts (un échec lève [ApiLoadException], ≠ liste vide)
  Future<List<DepotSaleListItem>> fetchDepotSales({
    String query = '',
    String statut = 'is_Process',
    int start = 0,
    int limit = 15
  }) => _loadList(
        'ventes dépôt',
        () => _dio.get('/ventestats/preventes-depot', queryParameters: {
          'statut': statut,
          'query': query,
          'start': start,
          'limit': limit
        }),
        DepotSaleListItem.fromJson,
      );

  // 2. Charger une vente dépôt existante (Reprise)
  Future<Map<String, dynamic>?> getDepotSaleDetails(String saleId) async {
    try {
      final response = await _dio.get('/ventestats/depot/$saleId');
      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'];
      }
      return null;
    } catch (e) {
      print("Erreur getDepotSaleDetails: $e");
      return null;
    }
  }

  // 3. Liste des dépôts disponibles (Choix Client/Emplacement) ; un échec lève [ApiLoadException]
  Future<List<DepotModel>> fetchDepots({String query = ''}) => _loadList(
        'dépôts',
        () => _dio.get('/magasin/find-depots', queryParameters: {
          'query': query,
          'limit': 50
        }),
        DepotModel.fromJson,
      );

  // 3 bis. Recherche produit pour la vente dépôt (même appel que [searchProducts]) ;
  // un échec lève [ApiLoadException] au lieu de « produit introuvable ».
  Future<List<ProductSearchResult>> searchDepotProducts(String query) => _loadList(
        'produits',
        () => _dio.get('/vente/search', queryParameters: {'query': query, 'page': 1, 'start': 0, 'limit': 30}),
        ProductSearchResult.fromJson,
      );

  // 3 ter. Lignes d'une vente dépôt (même appel que [fetchSaleItems]) ;
  // un échec lève [ApiLoadException] au lieu d'un panier vide.
  Future<List<SaleLine>> fetchDepotSaleItems(String venteId) => _loadList(
        'lignes de la vente',
        () => _dio.get('/vente/deatails', queryParameters: {
          'venteId': venteId,
          'start': 0,
          'limit': 100
        }),
        SaleLine.fromJson,
      );

  // 4. Créer vente dépôt (Ajout 1er article)
  Future<Map<String, dynamic>?> addFirstDepotItem({
    required String clientId,
    required String emplacementId,
    required String typeDepotId,
    required String produitId,
    required int itemPu,
    required int qte,
  }) async {
    try {
      final data = {
        "clientId": clientId,
        "depot": true,
        "devis": false,
        "emplacementId": emplacementId,
        "itemPu": itemPu,
        "natureVenteId": "3", // Fixe selon vos logs
        "produitId": produitId,
        "qte": qte,
        "qteServie": qte,
        "remiseDepot": 0,
        "typeDepoId": typeDepotId,
        "userVendeurId": null,
        "venteId": null
      };

      final response = await _dio.post('/vente/add/depot', data: data);
      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data']; // Retourne {lgPREENREGISTREMENTID: "...", ...}
      }
      return null;
    } catch (e) {
      print("Erreur addFirstDepotItem: $e");
      return null;
    }
  }

  // 5. Ajouter items suivants
  Future<bool> addNextDepotItem({
    required String venteId,
    required String clientId,
    required String emplacementId,
    required String typeDepotId,
    required String produitId,
    required int itemPu,
    required int qte,
  }) async {
    try {
      final data = {
        "clientId": clientId,
        "depot": true,
        "devis": false,
        "emplacementId": emplacementId,
        "itemPu": itemPu,
        "natureVenteId": "3",
        "produitId": produitId,
        "qte": qte,
        "qteServie": qte,
        "remiseDepot": 0,
        "typeDepoId": typeDepotId,
        "userVendeurId": null,
        "venteId": venteId
      };
      final response = await _dio.post('/vente/add/item', data: data);
      return response.statusCode == 200 && response.data['success'] == true;
    } catch (e) {
      print("Erreur addNextDepotItem: $e");
      return false;
    }
  }

  // 6. Mise à jour Quantité/Prix (Endpoint spécifique VNO)
  Future<bool> updateDepotItem({
    required String itemId,
    required String produitId,
    required int itemPu,
    required int qte,
  }) async {
    try {
      final data = {
        "itemId": itemId,
        "itemPu": itemPu,
        "produitId": produitId,
        "qte": qte,
        "qteServie": qte
      };
      final response = await _dio.post('/vente/update/item/vno', data: data);
      return response.statusCode == 200 && response.data['success'] == true;
    } catch (e) {
      print("Erreur updateDepotItem: $e");
      return false;
    }
  }

  // 7. Suppression Item (Endpoint spécifique VNO)
  Future<bool> removeDepotItem(String itemId) async {
    try {
      final response = await _dio.post('/vente/remove/vno/item/$itemId');
      return response.statusCode == 200 && response.data['success'] == true;
    } catch (e) {
      print("Erreur removeDepotItem: $e");
      return false;
    }
  }

  // 8. Clôturer Vente Dépôt
  Future<bool> closeDepotSale({
    required String venteId,
    required String clientId,
  }) async {
    try {
      final data = {
        "banque": "",
        "clientId": clientId,
        "commentaire": "",
        "lieux": "lieux",
        "natureVenteId": "3",
        "nom": "",
        "typeRegleId": "1",
        "userVendeurId": null,
        "venteId": venteId
      };
      final response = await _dio.post('/vente/clotureVenteDepot', data: data);
      return response.statusCode == 200 && response.data['success'] == true;
    } catch (e) {
      print("Erreur closeDepotSale: $e");
      return false;
    }
  }

  // AJOUTEZ UNIQUEMENT CELLE-CI SI ELLE MANQUE (Ne touchez pas à searchProducts existant)
  Future<List<SaleLine>> fetchSaleItems(String venteId) async {
    try {
      final response = await _dio.get('/vente/deatails', queryParameters: {
        'venteId': venteId,
        'start': 0,
        'limit': 100
      });

      if (response.statusCode == 200 && response.data['data'] != null) {
        return (response.data['data'] as List)
            .map((e) => SaleLine.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      print("Erreur fetchSaleItems: $e");
      return [];
    }
  }

// --- GESTION PROFORMA / DEVIS ---

  // Liste des proformas
  Future<List<ProformaListItem>> fetchProformas({
    String query = '',
    String dtStart = '',
    String dtEnd = ''
  }) async {
    try {
      final response = await _dio.get('/ventestats/devis', queryParameters: {
        'statut': 'devis',
        'query': query,
        'dtStart': dtStart,
        'dtEnd': dtEnd,
        'limit': 50
      });
      if (response.statusCode == 200 && response.data['data'] != null) {
        return (response.data['data'] as List).map((e) => ProformaListItem.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print("Erreur fetchProformas: $e");
      return [];
    }
  }

  // Types de devis (Comptant / Carnet)
  Future<List<TypeDevis>> fetchTypeDevis() async {
    try {
      final response = await _dio.get('/common/typedevis');
      if (response.statusCode == 200 && response.data['data'] != null) {
        return (response.data['data'] as List).map((e) => TypeDevis.fromJson(e)).toList();
      }
      return [];
    } catch (e) { return []; }
  }

  // Recherche Clients CARNET (Assurance/Carnet)
  // Endpoint : /client/all?typeClientId=2
  Future<List<ClientCarnetModel>> searchClientsCarnet(String query) async {
    try {
      final response = await _dio.get('/client/all', queryParameters: {
        'query': query,
        'typeClientId': '2', // Filtre CARNET strict
        'limit': 25
      });
      if (response.statusCode == 200 && response.data['data'] != null) {
        return (response.data['data'] as List)
            .map((e) => ClientCarnetModel.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      print("Erreur searchClientsCarnet: $e");
      return [];
    }
  }

  // Recherche Clients COMPTANT (Lambda/Standard)
  // Endpoint : /client/lambda
  Future<List<ClientComptantModel>> searchClientsComptant(String query) async {
    try {
      final response = await _dio.get('/client/lambda', queryParameters: {
        'query': query,
        'limit': 25
      });
      if (response.statusCode == 200 && response.data['data'] != null) {
        return (response.data['data'] as List)
            .map((e) => ClientComptantModel.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      print("Erreur searchClientsComptant: $e");
      return [];
    }
  }

  // NOTE: L'ancienne méthode searchClients générique est supprimée pour éviter les erreurs.
  // Utilisez searchClientsCarnet ou searchClientsComptant selon le contexte.

  Future<List<RemiseModel>> fetchRemises() async {
    try {
      final response = await _dio.get('/common/typeremises');

      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> allTypes = response.data['data'];

        // 1. On cherche le Type de Remise spécifique (Produit)
        final targetType = allTypes.firstWhere(
                (element) => element['lgTYPEREMISEID'] == "54291528198233221411",
            orElse: () => null
        );

        // 2. Si on l'a trouvé, on retourne sa liste interne 'remises'
        if (targetType != null && targetType['remises'] != null) {
          return (targetType['remises'] as List)
              .map((e) => RemiseModel.fromJson(e))
              .toList();
        }
      }
      return [];
    } catch (e) {
      print("Erreur fetchRemises: $e");
      return [];
    }
  }

  // Appliquer Remise
  Future<bool> applyRemise({required String venteId, required String remiseId}) async {
    try {
      final response = await _dio.post('/vente/remise', data: {'venteId': venteId, 'remiseId': remiseId});
      return response.statusCode == 200 && response.data['success'] == true;
    } catch (e) { return false; }
  }

  // --- AJOUT DANS API SERVICE (SANS TOUCHER A L'EXISTANT) ---

  // On nomme la méthode différemment pour ne pas casser "calculateNet" existant
  // Endpoint : /vente/net/vno (Spécifique aux devis/proforma selon vos logs)
  Future<Map<String, dynamic>?> calculateNetProforma({required String venteId, required String remiseId}) async {
    try {
      final response = await _dio.post('/vente/net/vno', data: {
        'venteId': venteId,
        'remiseId': remiseId
      });

      if(response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'];
      }
      return null;
    } catch (e) {
      print("Erreur calculateNetProforma: $e");
      return null;
    }
  }

  // 1. Pour la création initiale du devis
  Future<Map<String, dynamic>?> addFirstDevisItem({
    required String clientId,
    required String typeVenteId,
    required String produitId,
    required int itemPu,
    required int qte,
    List<Map<String, dynamic>>? tiersPayants, // Requis pour le mode carnet
  }) async {
    try {
      final response = await _dio.post('/vente/devis', data: {
        "bonRef": "",
        "clientId": clientId,
        "devis": true,
        "itemPu": itemPu,
        "natureVenteId": 1,
        "produitId": produitId,
        "qte": qte,
        "qteServie": qte,
        "remiseId": null,
        "tierspayants": tiersPayants ?? [], // Envoi des assurances
        "typeVenteId": typeVenteId,
        "userVendeurId": null,
        "venteId": null
      });
      return response.statusCode == 200 ? response.data : null;
    } catch (e) {
      debugPrint("Erreur addFirstDevisItem: $e");
      return null;
    }
  }

// 2. Pour l'ajout d'articles (Proforma existante ou suite de saisie)
  Future<bool> addNextDevisItem({
    required String venteId,
    required String clientId,
    required String typeVenteId,
    required String produitId,
    required int itemPu,
    required int qte,
    List<Map<String, dynamic>>? tiersPayants,
  }) async {
    try {
      final response = await _dio.post('/vente/add/item', data: {
        "venteId": venteId,
        "clientId": clientId,
        "typeVenteId": typeVenteId,
        "produitId": produitId,
        "itemPu": itemPu,
        "qte": qte,
        "devis": true,
        "tierspayants": tiersPayants ?? [],
      });
      return response.statusCode == 200 && response.data['success'] == true;
    } catch (e) {
      debugPrint("Erreur addNextDevisItem: $e");
      return false;
    }
  }

  // Récupérer le client lié à une vente spécifique (Logique rappel Proforma)
  Future<ClientModel?> getClientForSale(String clientId, String venteId) async {
    try {
      // Endpoint existant inchangé, mais on wrap le résultat dans un ClientModel générique
      // (Idéalement il faudrait savoir quel type de client c'est, mais pour la reprise de vente
      // on peut instancier un modèle simple puisque l'édition des infos client n'est pas le but premier)
      final response = await _dio.get('/client/client-assurance/$clientId/$venteId');
      if (response.statusCode == 200 && response.data['success'] == true && response.data['data'] != null) {
        // On suppose ici un format générique compatible, ou on adapte le JSON.
        // Si le JSON contient 'tiersPayants', on tente ClientCarnetModel, sinon ClientComptantModel
        final json = response.data['data'];
        if (json['tiersPayants'] != null && (json['tiersPayants'] as List).isNotEmpty) {
          return ClientCarnetModel.fromJson(json);
        } else {
          return ClientComptantModel.fromJson(json);
        }
      }
      return null;
    } catch (e) {
      print("Erreur getClientForSale: $e");
      return null;
    }
  }

  // Dans lib/api/api_service.dart

  // Analyse Article
  /// Lignes de GET /info (menu Analyse article). Un échec lève [ApiLoadException] avec sa cause précise
  /// (l'ancienne version renvoyait une liste vide : l'écran n'affichait alors RIEN, sans erreur).
  /// Requête annulable par le jeton de la zone ([avecJeton]) : la recherche d'une frappe plus récente
  /// remplace celle-ci.
  Future<List<ArticleAnalysis>> fetchArticleAnalysis(String query) => fetchArticleAnalysisOrFail(query, cancelToken: jetonDeLaZone());

  /// Délai maximal d'une lecture de GET /info, quoi qu'il arrive (au-delà : erreur affichée, jamais un
  /// squelette ou une roue sans fin). Remplaçable dans les tests.
  static Duration delaiInfo = const Duration(seconds: 30);

  /// Options des lectures de GET /info : délai de réception [delaiInfo] (30 s) au lieu des 10 s du client
  /// partagé (DioClient) — le serveur calcule les ventes de 6 mois à chaque appel ; avant la 4.1.2, le client
  /// abandonnait au bout de 10 s et l'écran affichait « Délai dépassé … en 10 s » alors que [delaiInfo] annonçait
  /// 30 s. [texte] : corps lu en texte (décodé par [lignesInfo]).
  static Options optionsInfo({bool texte = false}) =>
      Options(receiveTimeout: delaiInfo, responseType: texte ? ResponseType.plain : null);

  /// Clé de zone du jeton d'annulation des recherches (voir [avecJeton]).
  static const Symbol cleJeton = #prestigeJetonAnnulation;

  /// Exécute [f] avec [jeton] : les requêtes de recherche lancées dedans ([searchProductsPageOrFail],
  /// [fetchArticleAnalysis]) sont abandonnées quand le jeton est annulé (frappe suivante).
  static Future<T> avecJeton<T>(CancelToken jeton, Future<T> Function() f) => runZoned(f, zoneValues: {cleJeton: jeton});

  /// Jeton d'annulation posé par [avecJeton] (null : requête non annulable).
  static CancelToken? jetonDeLaZone() {
    final j = Zone.current[cleJeton];
    return j is CancelToken ? j : null;
  }

  /// Ligne de GET /info?search=<CIP> du produit de ce CIP (4.0.3, F3) : le serveur cherche « commence par » et
  /// trie par nom, la 1re ligne peut être celle d'un autre produit (« 8423349D » pour « 8423349 », CIP13 qui
  /// commence par ces chiffres…) → même `codeCip`, sinon la ligne la mieux classée ([ligneDuCode]).
  static Map<String, dynamic>? ligneInfoDuCip(List<Map<String, dynamic>> lignes, String codeCip) =>
      ligneDuCode(lignes, codeCip, (l) => '${l['codeCip'] ?? ''}');

  /// Lignes de GET /info quelle que soit la forme de la réponse : liste directe (forme actuelle du serveur),
  /// objet paginé `{data: […]}` (ou `results`, `items`, `rows`, `content`), texte JSON non décodé.
  /// Les éléments qui ne sont pas des objets sont ignorés. null : réponse illisible (texte, HTML, objet sans liste).
  static List<Map<String, dynamic>>? lignesInfo(dynamic data) {
    var d = data;
    if (d == null) return const [];
    if (d is String) {
      final t = d.trim();
      if (t.isEmpty) return const [];
      try {
        d = jsonDecode(t);
      } catch (_) {
        return null;
      }
    }
    if (d is Map) {
      final liste = d['data'] ?? d['results'] ?? d['items'] ?? d['rows'] ?? d['content'];
      if (liste == null) {
        // {total: 0} / {success: true, data: null} : aucune ligne.
        final total = d['total'];
        if ((total is num && total == 0) || (d.containsKey('data') && d['success'] != false)) return const [];
        return null;
      }
      d = liste;
    }
    if (d is! List) return null;
    return [for (final e in d) if (e is Map) Map<String, dynamic>.from(e)];
  }

  /// Corps d'une réponse qui ressemble au message / à la page de connexion du serveur
  /// (« Veuillez vous connecter », page HTML de connexion) : session expirée.
  static bool ressembleSessionExpiree(dynamic data) {
    if (data is! String) return false;
    final t = data.toLowerCase();
    return t.contains('vous connecter') || (t.contains('<html') && (t.contains('login') || t.contains('connexion')));
  }

  /// Même requête et même lecture que [fetchArticleAnalysis] (GET /info?search=…, menu Analyse article),
  /// mais un échec lève [ApiLoadException] avec sa cause précise (code HTTP, délai, réseau, session expirée,
  /// réponse illisible) au lieu d'une liste vide ; une requête annulée ([cancelToken]) relance l'exception Dio
  /// d'annulation. Lecture tolérante : liste directe ou objet `{data: […]}` ([lignesInfo]).
  /// Délai maximal [delaiInfo] : jamais d'attente sans fin.
  Future<List<ArticleAnalysis>> fetchArticleAnalysisOrFail(String query, {CancelToken? cancelToken}) async {
    final Response<dynamic> response;
    final jeton = cancelToken ?? CancelToken();
    final delai = delaiInfo;
    try {
      // Corps lu en TEXTE puis décodé ici ([lignesInfo]) : un corps qui n'est pas du JSON (« Veuillez vous
      // connecter » d'un 401, page HTML) donne un message précis au lieu d'une erreur de décodage Dio.
      response = await _dio
          .get('/info', queryParameters: {'search': query}, cancelToken: jeton, options: optionsInfo(texte: true))
          .timeout(delai, onTimeout: () {
        jeton.cancel('Délai dépassé (GET /info)');
        throw ApiLoadException('Délai dépassé : pas de réponse du serveur en ${delai.inSeconds} s (GET /info). Réessayez.');
      });
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw ApiLoadException(analyseErreurMessage(e));
    }
    final code = response.statusCode ?? 0;
    if (code != 200) throw ApiLoadException('Le serveur a répondu HTTP $code (GET /info).');
    final data = response.data;
    final lignes = lignesInfo(data);
    if (lignes == null) {
      if (ressembleSessionExpiree(data)) throw ApiLoadException('Session expirée — reconnectez-vous (GET /info, HTTP $code).');
      throw ApiLoadException('Réponse illisible du serveur (GET /info, HTTP $code) : ni liste de produits ni objet {data: […]}.');
    }
    try {
      return [for (final e in lignes) ArticleAnalysis.fromJson(e)];
    } catch (e) {
      throw ApiLoadException('Données illisibles (GET /info) : $e');
    }
  }

  /// Message précis d'un échec de GET /info : délai (avec sa durée), code HTTP, réseau.
  static String messageErreurInfo(Object e) {
    if (e is ApiLoadException) return e.message;
    if (e is DioException) return analyseErreurMessage(e);
    if (e is TimeoutException) return 'Délai dépassé : pas de réponse du serveur (GET /info). Réessayez.';
    return 'Analyse indisponible : $e';
  }

  static String analyseErreurMessage(DioException e) {
    String secondes(Duration? d) => d == null ? '' : ' en ${d.inSeconds} s';
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Délai dépassé : serveur non joint${secondes(e.requestOptions.connectTimeout)} (GET /info).';
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Délai dépassé : pas de réponse du serveur${secondes(e.requestOptions.receiveTimeout)} (GET /info).';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        if (code == 401 || (code == 403 && ressembleSessionExpiree(e.response?.data))) {
          return 'Session expirée — reconnectez-vous (HTTP $code, GET /info).';
        }
        if (code == 403) return 'Accès refusé (HTTP 403, GET /info).';
        return 'Le serveur a répondu HTTP $code (GET /info).';
      case DioExceptionType.connectionError:
        return 'Serveur injoignable (GET /info). Vérifiez le Wi-Fi ou les données mobiles.';
      case DioExceptionType.badCertificate:
        return '${ErreurTls.messageCertificat} (GET /info)';
      default:
        if (e.error is SocketException) return 'Serveur injoignable (GET /info). Vérifiez le Wi-Fi ou les données mobiles.';
        final tls = ErreurTls.de(e);
        if (tls != null) return '${tls.message} (GET /info)';
        if (e.error is FormatException) {
          final code = e.response?.statusCode;
          if (code == 401 || ressembleSessionExpiree(e.response?.data)) return 'Session expirée — reconnectez-vous (GET /info).';
          return 'Réponse illisible du serveur (GET /info${code == null ? '' : ', HTTP $code'}).';
        }
        return 'Échec de GET /info : ${e.message ?? e.type.name}.';
    }
  }

  // Ajoutez ceci dans lib/api/api_service.dart

  /// Méthode générique pour effectuer des requêtes HTTP (GET, POST, etc.)
  Future<dynamic> request({
    required String method,
    required String url,
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.request(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method),
      );
      return response.data;
    } catch (e) {
      print("Erreur ApiService.request ($url): $e");
      return null;
    }
  }

}