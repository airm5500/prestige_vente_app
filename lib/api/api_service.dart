// lib/api/api_service.dart
// 28/09/2025 20:33
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

class ApiService {
  late Dio _dio;

  ApiService({required String baseUrl}) {
    _dio = DioClient.getClient(baseUrl);
  }

  Future<User?> login(String login, String password) async {
    try {
      final response = await _dio.post(
          '/user/auth', data: {'login': login, 'password': password});
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

  Future<Officine?> fetchOfficineInfo() async {
    try {
      final response = await _dio.get('/officine');
      if (response.statusCode == 200 && response.data is List &&
          response.data.isNotEmpty) {
        return Officine.fromJson(response.data[0]);
      }
      return null;
    } catch (e) {
      print("Error fetching officine info: $e");
      return null;
    }
  }

  Future<List<ProductSearchResult>> searchProducts(String query) async {
    try {
      final response = await _dio.get(
        '/vente/search',
        queryParameters: {'query': query, 'page': 1, 'start': 0, 'limit': 10},
      );
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List)
            .map((item) => ProductSearchResult.fromJson(item))
            .toList();
      }
      return [];
    } catch (e) {
      print("Error searching products: $e");
      return [];
    }
  }

  Future<String?> addItemToSale({
    required String produitId,
    required int qte,
    required int itemPu,
    String? venteId,
    bool isPrevente = false,
  }) async {
    try {
      const typeVenteId = "1";
      const natureVenteId = "1";

      final bool isFirstItem = venteId == null;
      final String endpoint = isFirstItem
          ? '/vente/add/vno'
          : '/vente/add/item';

      final Map<String, dynamic> data = {
        "typeVenteId": typeVenteId,
        "natureVenteId": natureVenteId,
        "produitId": produitId,
        "itemPu": itemPu,
        "qte": qte,
        "qteServie": qte,
        "devis": false,
        "venteId": venteId,
        "prevente": isPrevente,
        "remiseId": null,
        "userVendeurId": null
      };

      final response = await _dio.post(endpoint, data: data);

      if (response.statusCode == 200 && response.data['success'] == true) {
        return isFirstItem
            ? response.data['data']['lgPREENREGISTREMENTID']
            : venteId;
      }
      return null;
    } catch (e) {
      print("Error adding item to sale: $e");
      return null;
    }
  }

  Future<List<SaleItemDetail>> getSaleDetails(String venteId) async {
    try {
      final response = await _dio.get(
        '/vente/deatails',
        queryParameters: {
          'venteId': venteId,
          'page': 1,
          'start': 0,
          'limit': 100
        },
      );
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List).map((item) =>
            SaleItemDetail.fromJson(item)).toList();
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

  Future<bool> updateSaleItem({
    required String itemId,
    required String produitId,
    required int qte,
    required int itemPu,
  }) async {
    try {
      final response = await _dio.post('/vente/update/item/vno', data: {
        "itemId": itemId,
        "produitId": produitId,
        "qte": qte,
        "qteServie": qte,
        "itemPu": itemPu,
      });
      return response.statusCode == 200 && response.data['success'] == true;
    } catch (e) {
      print("Error updating item: $e");
      return false;
    }
  }

  Future<SaleSummary?> calculateNet(String venteId) async {
    try {
      final response = await _dio.post(
          '/vente/net/vno', data: {"venteId": venteId, "checkUg": false});
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
      final response = await _dio.get('/common/reglement',
          queryParameters: {'page': 1, 'start': 0, 'limit': 25}
      );
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List).map((e) =>
            PaymentMethod.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print("Error fetching payment methods: $e");
      return [];
    }
  }

  Future<bool> updateClientForSale(String venteId, String clientId) async {
    try {
      final response = await _dio.post(
        '/vente/update/client',
        data: {"clientId": clientId, "venteId": venteId},
      );
      return response.statusCode == 200 && response.data['success'] == true;
    } catch (e) {
      print("Error updating client for sale: $e");
      return false;
    }
  }

  Future<bool> cloturerVente({
    required String venteId,
    required SaleSummary summary,
    required String typeReglementId,
    required String clientId,
    required String userVendeurId,
  }) async {
    try {
      final response = await _dio.post('/vente/cloturer/vno', data: {
        "banque": "",
        "clientId": clientId,
        "commentaire": "",
        "data": summary.toJson(),
        "devis": false,
        "lieux": "",
        "marge": summary.marge,
        "medecinId": null,
        "montantPaye": summary.montantNet,
        "montantRecu": summary.montantNet,
        "montantRemis": 0,
        "natureVenteId": "1",
        "nom": "",
        "partTP": 0,
        "reglements": [
          {
            "montant": summary.montantNet,
            "montantAttentu": summary.montantNet,
            "typeReglement": typeReglementId
          }
        ],
        "remiseId": null,
        "totalRecap": summary.montantNet,
        "typeRegleId": typeReglementId,
        "typeVenteId": "1",
        "userVendeurId": userVendeurId,
        "venteId": venteId
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
      final response = await _dio.get(
          '/ventestats/preventes', queryParameters: {
        'statut': 'is_Process',
        'limit': 9999,
        'sort': '[{"property":"heure","direction":"DESC"}]',
        'page': 1,
        'start': 0,
      });
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List).map((item) =>
            PreventeListItem.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      print("Error fetching preventes: $e");
      return [];
    }
  }

  Future<List<ProductAnnualSale>> getAnnualSales(String query, int year) async {
    try {
      final response = await _dio.get('/produit/stats/vente-annuelle',
          queryParameters: {'search': query, 'year': year});
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List).map((item) =>
            ProductAnnualSale.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      print("Error fetching annual sales: $e");
      return [];
    }
  }

  Future<List<ProductDetails>> searchProductFiche(String query) async {
    try {
      final response = await _dio.get(
        '/produit-search/fiche',
        queryParameters: {
          'search_value': query,
          'page': 1,
          'start': 0,
          'limit': 20
        },
      );
      if (response.statusCode == 200 && response.data['results'] is List) {
        return (response.data['results'] as List).map((item) =>
            ProductDetails.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      print("Error in searchProductFiche: $e");
      return [];
    }
  }

  Future<List<ProductOrderHistory>> getProductOrderHistory(String productId,
      String dtStart, String dtEnd) async {
    try {
      final response = await _dio.get(
        '/commande/produit/commande/$productId',
        queryParameters: {
          'dtStart': dtStart,
          'dtEnd': dtEnd,
          'page': 1,
          'start': 0,
          'limit': 9999
        },
      );
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List).map((item) =>
            ProductOrderHistory.fromJson(item)).toList();
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

  Future<ProductInfo?> getProductInfo(String codeCip) async {
    try {
      final response = await _dio.get(
          '/info', queryParameters: {'search': codeCip});

      if (response.statusCode == 200 && response.data is List &&
          response.data.isNotEmpty) {
        return ProductInfo.fromJson(response.data[0]);
      }
      return null;
    } catch (e) {
      print("Error fetching product info: $e");
      return null;
    }
  }

  Future<bool> addLot({
    required String produitId,
    required String datePeremption,
    required String numLot,
    required int quantity,
  }) async {
    try {
      final response = await _dio.post(
        '/fichearticle/add-lot',
        data: {
          "produitId": produitId,
          "datePeremption": datePeremption,
          "numLot": numLot,
          "quantity": quantity
        },
      );
      // CORRECTION : Si le code de statut est 202, c'est un succès.
      return response.statusCode == 202;
    } catch (e) {
      print("Error adding lot: $e");
      return false;
    }
  }

  Future<List<Commande>> getCommandes() async {
    try {
      final response = await _dio.get(
        '/commande/list',
        queryParameters: {
          'page': 1,
          'start': 0,
          'limit': 100
        }, // On charge une grande liste
      );
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List)
            .map((c) => Commande.fromJson(c))
            .toList();
      }
      return [];
    } catch (e) {
      print("Error fetching commandes: $e");
      return [];
    }
  }

  Future<List<CommandeItem>> getCommandeItems(String orderId) async {
    try {
      final response = await _dio.get(
        '/commande/commande-en-cours-items',
        queryParameters: {
          'orderId': orderId,
          'page': 1,
          'start': 0,
          'limit': 9999
        },
      );
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List).map((i) =>
            CommandeItem.fromJson(i)).toList();
      }
      return [];
    } catch (e) {
      print("Error fetching commande items: $e");
      return [];
    }
  }

  Future<bool> postCheckedQuantity({
    required String detailId,
    required int quantity,
  }) async {
    try {
      final response = await _dio.post(
        '/commande/item/checked-quantities',
        data: {"id": detailId, "checked": true, "checkedQuantity": quantity},
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Error posting checked quantity: $e");
      return false;
    }
  }


}