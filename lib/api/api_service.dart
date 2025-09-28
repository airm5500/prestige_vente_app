// lib/api/api_service.dart
// 28/09/2025 02:38
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/product_stats.dart';
import 'package:prestige_vente_app/api/models/product_search_result.dart';


class ApiService {
  final Dio _dio;
  final String baseUrl;

  ApiService({required this.baseUrl})
      : _dio = Dio(BaseOptions(baseUrl: baseUrl)) {
    _dio.interceptors.add(CookieManager(CookieJar()));
    _dio.interceptors.add(LogInterceptor(responseBody: true, requestBody: true));
  }

  // --- Authentification ---

  Future<User?> login(String login, String password) async {
    try {
      final response = await _dio.post(
        '/user/auth',
        data: {'login': login, 'password': password},
      );
      if (response.statusCode == 200 && response.data['success'] == true) {
        return User.fromJson(response.data);
      }
      return null;
    } on DioException catch (e) {
      print("Error logging in: $e");
      return null;
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post('/user/logout');
    } catch (e) {
      print("Error logging out: $e");
    }
  }

  // --- Officine ---

  Future<Officine?> fetchOfficineInfo() async {
    try {
      final response = await _dio.get('/officine');
      if (response.statusCode == 200 && response.data is List && response.data.isNotEmpty) {
        return Officine.fromJson(response.data[0]);
      }
      return null;
    } catch (e) {
      print("Error fetching officine info: $e");
      return null;
    }
  }

  // --- Vente / Prévente ---

  Future<List<ProductSearchResult>> searchProducts(String query) async {
    try {
      final response = await _dio.get('/vente/search', queryParameters: {'query': query, 'limit': 10});
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List).map((item) => ProductSearchResult.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      print("Error searching products: $e");
      return [];
    }
  }

  Future<String?> addItemToSale({
    required String produitId, required int qte, required int itemPu, String? venteId, bool isPrevente = false,
  }) async {
    try {
      final response = await _dio.post('/vente/add/vno', data: {
        "typeVenteId": "1", "natureVenteId": "1", "produitId": produitId, "itemPu": itemPu,
        "qte": qte, "qteServie": qte, "devis": false, "venteId": venteId, "prevente": isPrevente,
      });
      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data']['lgPREENREGISTREMENTID'];
      }
      return null;
    } catch (e) {
      print("Error adding item to sale: $e");
      return null;
    }
  }

  Future<List<SaleItemDetail>> getSaleDetails(String venteId) async {
    try {
      final response = await _dio.get('/vente/deatails', queryParameters: {'venteId': venteId, 'limit': 100});
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List).map((item) => SaleItemDetail.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      print("Error getting sale details: $e");
      return [];
    }
  }

  Future<bool> removeItemFromSale(String itemId) async {
    try {
      final response = await _dio.post('/vente/remove/vno/item/$itemId');
      return response.statusCode == 200 && response.data['success'] == true;
    } catch (e) {
      print("Error removing item: $e");
      return false;
    }
  }

  Future<bool> updateSaleItem({required String itemId, required String produitId, required int qte, required int itemPu}) async {
    try {
      final response = await _dio.post('/vente/update/item/vno', data: {
        "itemId": itemId, "produitId": produitId, "qte": qte, "qteServie": qte, "itemPu": itemPu,
      });
      return response.statusCode == 200 && response.data['success'] == true;
    } catch (e) {
      print("Error updating item: $e");
      return false;
    }
  }

  Future<SaleSummary?> calculateNet(String venteId) async {
    try {
      final response = await _dio.post('/vente/net/vno', data: {"venteId": venteId, "checkUg": false});
      if (response.statusCode == 200 && response.data['success'] == true) {
        return SaleSummary.fromNetResponse(response.data);
      }
      return null;
    } catch (e) {
      print("Error calculating net: $e");
      return null;
    }
  }

  Future<List<PaymentMethod>> getPaymentMethods() async {
    try {
      final response = await _dio.get('/common/reglement');
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List).map((e) => PaymentMethod.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print("Error fetching payment methods: $e");
      return [];
    }
  }

  Future<bool> cloturerVente({required String venteId, required SaleSummary summary, required String typeReglementId, required String clientId}) async {
    try {
      final response = await _dio.post('/vente/cloturer/vno', data: {
        "venteId": venteId, "data": { "montant": summary.montant, "remise": summary.remise, "montantNet": summary.montantNet,
          "marge": 0, "montantTva": 0, "tierspayants": [],
        },
        "clientId": clientId, "montantRecu": summary.montantNet, "montantPaye": summary.montantNet,
        "typeVenteId": "1", "natureVenteId": "1", "reglements": [{"typeReglement": typeReglementId, "montant": summary.montantNet}],
      });
      return response.statusCode == 200 && response.data['success'] == true;
    } catch (e) {
      print("Error closing sale: $e");
      return false;
    }
  }

  Future<bool> terminerPrevente(String venteId) async {
    try {
      final response = await _dio.put('/vente/terminerprevente/$venteId');
      return response.statusCode == 200 && response.data['success'] == true;
    } catch (e) {
      print("Error terminating prevente: $e");
      return false;
    }
  }

  Future<List<PreventeListItem>> getPreventes() async {
    try {
      final response = await _dio.get('/ventestats/preventes', queryParameters: {
        'statut': 'is_Process', 'limit': 9999, 'sort': '[{"property":"heure","direction":"DESC"}]',
      });
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List).map((item) => PreventeListItem.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      print("Error fetching preventes: $e");
      return [];
    }
  }

  // --- Évaluation Article ---

  Future<List<ProductAnnualSale>> getAnnualSales(String query, int year) async {
    try {
      final response = await _dio.get('/produit/stats/vente-annuelle', queryParameters: {'search': query, 'year': year});
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List).map((item) => ProductAnnualSale.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      print("Error fetching annual sales: $e");
      return [];
    }
  }

  Future<ProductInfo?> getProductInfo(String codeCip) async {
    try {
      final response = await _dio.get('/info', queryParameters: {'search': codeCip});
      if (response.statusCode == 200 && response.data != null) {
        return ProductInfo.fromJson(response.data);
      }
      return null;
    } catch (e) {
      print("Error fetching product info: $e");
      return null;
    }
  }

  // --- Recherche Article ---

  Future<List<ProductDetails>> searchProductFiche(String query) async {
    try {
      final response = await _dio.get('/produit-search/fiche', queryParameters: {'search_value': query, 'limit': 20});
      if (response.statusCode == 200 && response.data['results'] is List) {
        return (response.data['results'] as List).map((item) => ProductDetails.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      print("Error in searchProductFiche: $e");
      return [];
    }
  }

  Future<List<ProductOrderHistory>> getProductOrderHistory(String productId, String dtStart, String dtEnd) async {
    try {
      final response = await _dio.get('/commande/produit/commande/$productId', queryParameters: {
        'dtStart': dtStart, 'dtEnd': dtEnd, 'limit': 9999
      });
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List).map((item) => ProductOrderHistory.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      print("Error fetching order history: $e");
      return [];
    }
  }

  Future<bool> updateExpirationDate(String productId, String newDate) async {
    print('Mise à jour de la date de péremption pour $productId à $newDate');
    await Future.delayed(const Duration(seconds: 1));
    return true;
  }
}