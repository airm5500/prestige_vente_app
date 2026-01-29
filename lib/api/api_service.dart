// lib/api/api_service.dart
// 10/11/2025 09:00 (Ajout updateClientAssurance)
import 'package:dio/dio.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
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
import 'package:prestige_vente_app/api/models/depot_model.dart'; // Pour DepotSaleListItem

class ApiService {
  late Dio _dio;

  ApiService({required String baseUrl}) {
    _dio = DioClient.getClient(baseUrl);
  }

  // ... (Toutes les méthodes existantes restent inchangées) ...
  Future<User?> login(String login, String password) async { try { final response = await _dio.post( '/user/auth', data: {'login': login, 'password': password}); if (response.statusCode == 200 && response.data['success'] == true) { return User.fromJson(response.data); } return null; } on DioException catch (e) { print("Error logging in: $e"); return null; } }
  Future<void> logout() async { try { await _dio.post('/user/logout'); } catch (e) { print("Error logging out: $e"); } }
  Future<Officine?> fetchOfficineInfo() async { try { final response = await _dio.get('/officine'); if (response.statusCode == 200 && response.data is List && response.data.isNotEmpty) { return Officine.fromJson(response.data[0]); } return null; } catch (e) { print("Error fetching officine info: $e"); return null; } }
  Future<List<ProductSearchResult>> searchProducts(String query) async { try { final response = await _dio.get( '/vente/search', queryParameters: {'query': query, 'page': 1, 'start': 0, 'limit': 20}, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List) .map((item) => ProductSearchResult.fromJson(item)) .toList(); } return []; } catch (e) { print("Error searching products: $e"); return []; } }
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
  Future<ProductInfo?> getProductInfo(String codeCip) async { try { final response = await _dio.get( '/info', queryParameters: {'search': codeCip}); if (response.statusCode == 200 && response.data is List && response.data.isNotEmpty) { return ProductInfo.fromJson(response.data[0]); } return null; } catch (e) { print("Error fetching product info: $e"); return null; } }
  Future<bool> addLot({ required String produitId, required String datePeremption, required String numLot, required int quantity, }) async { try { final response = await _dio.post( '/fichearticle/add-lot', data: { "produitId": produitId, "datePeremption": datePeremption, "numLot": numLot, "quantity": quantity }, ); return response.statusCode == 202; } catch (e) { print("Error adding lot: $e"); return false; } }
  Future<List<Commande>> getCommandes() async { try { final response = await _dio.get( '/commande/list', queryParameters: { 'page': 1, 'start': 0, 'limit': 100 }, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List) .map((c) => Commande.fromJson(c)) .toList(); } return []; } catch (e) { print("Error fetching commandes: $e"); return []; } }
  Future<List<CommandeItem>> getCommandeItems(String orderId) async { try { final response = await _dio.get( '/commande/commande-en-cours-items', queryParameters: { 'orderId': orderId, 'page': 1, 'start': 0, 'limit': 9999 }, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List).map((i) => CommandeItem.fromJson(i)).toList(); } return []; } catch (e) { print("Error fetching commande items: $e"); return []; } }
  Future<bool> postCheckedQuantity({ required String detailId, required int quantity, }) async { try { final response = await _dio.post( '/commande/item/checked-quantities', data: { "id": detailId, "checked": true, "checkedQuantity": quantity}, ); return response.statusCode == 200; } catch (e) { print("Error posting checked quantity: $e"); return false; } }
  Future<List<BonLivraison>> getBonsLivraison({ String query = '', String? dtStart, String? dtEnd, }) async { try { var queryParameters = { 'query': query, 'page': 1, 'start': 0, 'limit': 9999, 'sort': '[{"property":"dt_DATE_LIVRAISON","direction":"ASC"}]', 'statut': 'is_Closed' }; if (dtStart != null && dtStart.isNotEmpty) { queryParameters['dtStart'] = dtStart; } if (dtEnd != null && dtEnd.isNotEmpty) { queryParameters['dtEnd'] = dtEnd; } final response = await _dio.get( '/commande/list-bons', queryParameters: queryParameters, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List).map((bl) => BonLivraison.fromJson(bl)).toList(); } return []; } catch (e) { print("Error fetching bons livraison: $e"); return []; } }
  Future<List<BonLivraisonItem>> getBonLivraisonItems(String blId) async { try { final response = await _dio.get( '/commande/bon/items/$blId', queryParameters: {'page': 1, 'start': 0, 'limit': 9999}, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List).map((i) => BonLivraisonItem.fromJson(i)).toList(); } return []; } catch (e) { print("Error fetching BL items: $e"); return []; } }
  Future<bool> postBonItemCheckedQuantity({ required String detailId, required int quantity, }) async { try { final response = await _dio.post( '/commande/bon/items/checked-quantities', data: { "id": detailId, "checked": true, "checkedQuantity": quantity}, ); return response.statusCode == 200 || response.statusCode == 202; } catch (e) { print("Error posting BL checked quantity: $e"); return false; } }
  Future<List<Rayon>> getRayons() async { try { final response = await _dio.get( '/common/rayons', queryParameters: { 'query': '', 'page': 1, 'start': 0, 'limit': 9999 }, ); if (response.statusCode == 200 && response.data['data'] is List) { return (response.data['data'] as List).map((r) => Rayon.fromJson(r)).toList(); } return []; } catch (e) { print("Error fetching rayons: $e"); return []; } }
  Future<bool> updateLiteInfo(Map<String, dynamic> data) async { try { final response = await _dio.post( '/fichearticle/produit/update-lite-info', data: data, ); if (response.statusCode == 202) { return true; } if (response.statusCode == 200 && response.data['success'] == true) { return true; } return false; } on DioException catch (e) { if (e.response?.statusCode == 202) return true; print("Error in updateLiteInfo: $e"); return false; } catch (e) { print("Error in updateLiteInfo: $e"); return false; } }
  Future<List<PaymentMethodQr>> getPaymentMethodsWithQr() async { try { final response = await _dio.get( '/modereglement/all', queryParameters: { 'page': 1, 'start': 0, 'limit': 20 }, ); if (response.statusCode == 200 && response.data['data'] is List) { final List data = response.data['data']; final List<PaymentMethodQr> methods = []; for (var item in data) { if (item is Map<String, dynamic>) { methods.add(PaymentMethodQr.fromJson(item)); } } return methods; } return []; } catch (e) { print("Error fetching payment methods with QR: $e"); return []; } }
  Future<ProductInfo?> getProductInfoForStats(String codeCip) async { try { final response = await _dio.get('/info', queryParameters: { 'search': codeCip }); if (response.statusCode == 200 && response.data is List && response.data.isNotEmpty) { return ProductInfo.fromJson(response.data[0]); } return null; } catch (e) { print("Error fetching product info for stats: $e"); return null; } }
  Future<List<ProductInfo>> searchProductInfoForSearch(String query) async { try { final response = await _dio.get( '/info', queryParameters: { 'search': query }, ); if (response.statusCode == 200 && response.data is List) { return (response.data as List) .map((item) => ProductInfo.fromJson(item)) .toList(); } return []; } catch (e) { print("Error in searchProductInfoForSearch: $e"); return []; } }
  Future<ProductDetails?> getProductDetailsForSearch(String codeCip) async { try { final response = await _dio.get( '/produit-search/fiche', queryParameters: { 'search_value': codeCip, 'page': 1, 'start': 0, 'limit': 1 }, ); if (response.statusCode == 200 && response.data['results'] is List) { final results = response.data['results'] as List; if (results.isNotEmpty) { return ProductDetails.fromJson(results.first); } } return null; } catch (e) { print("Error in getProductDetailsForSearch: $e"); return null; } }

  Future<List<Grossiste>> getGrossistes() async {
    try {
      final response = await _dio.get(
        '/common/grossiste',
        queryParameters: {'query': '', 'page': 1, 'start': 0, 'limit': 9999},
      );
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List).map((g) => Grossiste.fromJson(g)).toList();
      }
      return [];
    } catch (e) {
      print("Error fetching grossistes: $e");
      return [];
    }
  }

  Future<Map<String, dynamic>> getStockReport({
    String query = '',
    String codeRayon = '',
    String codeGrossiste = '',
    String filtreStock = '', // EQUAL, GREATER, etc.
    String stockValue = '',  // La valeur numérique (ex: 10)
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _dio.get(
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
      );

      if (response.statusCode == 200 && response.data['data'] is List) {
        final List<StockReportItem> items = (response.data['data'] as List)
            .map((item) => StockReportItem.fromJson(item))
            .toList();
        return {
          'data': items,
          'total': response.data['total'] ?? 0,
        };
      }
      return {'data': <StockReportItem>[], 'total': 0};
    } catch (e) {
      print("Error fetching stock report: $e");
      return {'data': <StockReportItem>[], 'total': 0};
    }
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

  // NOUVEAU : Récupération des bons de réception avec détails inclus
  Future<List<ReceptionBon>> getReceptionBons({
    String query = '',
    String? dtStart,
    String? dtEnd,
  }) async {
    try {
      var queryParameters = {
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

      final response = await _dio.get(
        '/etat-control-bon/list',
        queryParameters: queryParameters,
      );

      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List)
            .map((item) => ReceptionBon.fromJson(item))
            .toList();
      }
      return [];
    } catch (e) {
      print("Error fetching reception bons: $e");
      return [];
    }
  }

  // --- GESTION LICENCE (AJOUT) ---

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

  // 1. Liste des ventes dépôts
  Future<List<DepotSaleListItem>> fetchDepotSales({
    String query = '',
    String statut = 'is_Process',
    int start = 0,
    int limit = 15
  }) async {
    try {
      final response = await _dio.get('/ventestats/preventes-depot', queryParameters: {
        'statut': statut,
        'query': query,
        'start': start,
        'limit': limit
      });
      if (response.statusCode == 200 && response.data['data'] != null) {
        return (response.data['data'] as List)
            .map((e) => DepotSaleListItem.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      print("Erreur fetchDepotSales: $e");
      return [];
    }
  }

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

  // 3. Liste des dépôts disponibles (Choix Client/Emplacement)
  Future<List<DepotModel>> fetchDepots({String query = ''}) async {
    try {
      final response = await _dio.get('/magasin/find-depots', queryParameters: {
        'query': query,
        'limit': 50
      });
      if (response.statusCode == 200 && response.data['data'] != null) {
        return (response.data['data'] as List)
            .map((e) => DepotModel.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      print("Erreur fetchDepots: $e");
      return [];
    }
  }

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



}