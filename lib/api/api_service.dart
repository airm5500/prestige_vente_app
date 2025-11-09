// lib/api/api_service.dart
// 09/11/2025 00:30 (Gestion Erreur N° Bon)
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

// NOUVEAUX IMPORTS POUR L'ASSURANCE
import 'package:prestige_vente_app/api/models/nature_vente.dart';
import 'package:prestige_vente_app/api/models/type_vente.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';

class ApiService {
  late Dio _dio;

  ApiService({required String baseUrl}) {
    _dio = DioClient.getClient(baseUrl);
  }

  // --- AUTHENTIFICATION (Inchangé) ---
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

  // --- VENTE COMPTANT / PREVENTE (Inchangé) ---
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

  // --- MODULE RECHERCHE / STATS (Inchangé) ---
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
      return response.statusCode == 202;
    } catch (e) {
      print("Error adding lot: $e");
      return false;
    }
  }

  // --- MODULE GESTION DE STOCK (Inchangé) ---
  Future<List<Commande>> getCommandes() async {
    try {
      final response = await _dio.get(
        '/commande/list',
        queryParameters: {
          'page': 1,
          'start': 0,
          'limit': 100
        },
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

  Future<List<BonLivraison>> getBonsLivraison({
    String query = '',
    String? dtStart,
    String? dtEnd,
  }) async {
    try {
      var queryParameters = {
        'query': query,
        'page': 1,
        'start': 0,
        'limit': 9999,
        'sort': '[{"property":"dt_DATE_LIVRAISON","direction":"ASC"}]',
        'statut': 'is_Closed'
      };

      if (dtStart != null && dtStart.isNotEmpty) {
        queryParameters['dtStart'] = dtStart;
      }
      if (dtEnd != null && dtEnd.isNotEmpty) {
        queryParameters['dtEnd'] = dtEnd;
      }

      final response = await _dio.get(
        '/commande/list-bons',
        queryParameters: queryParameters,
      );
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List).map((bl) => BonLivraison.fromJson(bl)).toList();
      }
      return [];
    } catch (e) {
      print("Error fetching bons livraison: $e");
      return [];
    }
  }

  Future<List<BonLivraisonItem>> getBonLivraisonItems(String blId) async {
    try {
      final response = await _dio.get(
        '/commande/bon/items/$blId',
        queryParameters: {'page': 1, 'start': 0, 'limit': 9999},
      );
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List).map((i) => BonLivraisonItem.fromJson(i)).toList();
      }
      return [];
    } catch (e) {
      print("Error fetching BL items: $e");
      return [];
    }
  }

  Future<bool> postBonItemCheckedQuantity({
    required String detailId,
    required int quantity,
  }) async {
    try {
      final response = await _dio.post(
        '/commande/bon/items/checked-quantities',
        data: {"id": detailId, "checked": true, "checkedQuantity": quantity},
      );
      return response.statusCode == 200 || response.statusCode == 202;
    } catch (e) {
      print("Error posting BL checked quantity: $e");
      return false;
    }
  }

  // --- MODULE FICHE ARTICLE (Inchangé) ---
  Future<List<Rayon>> getRayons() async {
    try {
      final response = await _dio.get(
        '/common/rayons',
        queryParameters: {'query': '', 'page': 1, 'start': 0, 'limit': 9999},
      );
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List).map((r) => Rayon.fromJson(r)).toList();
      }
      return [];
    } catch (e) {
      print("Error fetching rayons: $e");
      return [];
    }
  }

  Future<bool> updateLiteInfo(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(
        '/fichearticle/produit/update-lite-info',
        data: data,
      );

      if (response.statusCode == 202) {
        return true;
      }
      if (response.statusCode == 200 && response.data['success'] == true) {
        return true;
      }
      return false;

    } on DioException catch (e) {
      if (e.response?.statusCode == 202) return true;
      print("Error in updateLiteInfo: $e");
      return false;
    } catch (e) {
      print("Error in updateLiteInfo: $e");
      return false;
    }
  }

  Future<List<PaymentMethodQr>> getPaymentMethodsWithQr() async {
    try {
      final response = await _dio.get(
        '/modereglement/all',
        queryParameters: {'page': 1, 'start': 0, 'limit': 20},
      );
      if (response.statusCode == 200 && response.data['data'] is List) {
        final List data = response.data['data'];
        final List<PaymentMethodQr> methods = [];

        for (var item in data) {
          if (item is Map<String, dynamic>) {
            methods.add(PaymentMethodQr.fromJson(item));
          }
        }
        return methods;
      }
      return [];
    } catch (e) {
      print("Error fetching payment methods with QR: $e");
      return [];
    }
  }

  Future<ProductInfo?> getProductInfoForStats(String codeCip) async {
    try {
      final response = await _dio.get('/info', queryParameters: {'search': codeCip});
      if (response.statusCode == 200 && response.data is List && response.data.isNotEmpty) {
        return ProductInfo.fromJson(response.data[0]);
      }
      return null;
    } catch (e) {
      print("Error fetching product info for stats: $e");
      return null;
    }
  }

  Future<List<ProductInfo>> searchProductInfoForSearch(String query) async {
    try {
      final response = await _dio.get(
        '/info',
        queryParameters: {'search': query},
      );
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((item) => ProductInfo.fromJson(item))
            .toList();
      }
      return [];
    } catch (e) {
      print("Error in searchProductInfoForSearch: $e");
      return [];
    }
  }

  Future<ProductDetails?> getProductDetailsForSearch(String codeCip) async {
    try {
      final response = await _dio.get(
        '/produit-search/fiche',
        queryParameters: {'search_value': codeCip, 'page': 1, 'start': 0, 'limit': 1},
      );
      if (response.statusCode == 200 && response.data['results'] is List) {
        final results = response.data['results'] as List;
        if (results.isNotEmpty) {
          return ProductDetails.fromJson(results.first);
        }
      }
      return null;
    } catch (e) {
      print("Error in getProductDetailsForSearch: $e");
      return null;
    }
  }

  // ======================================================
  // NOUVELLES MÉTHODES POUR VENTE ASSURANCE
  // ======================================================

  Future<List<NatureVente>> getNaturesVente() async {
    try {
      final response = await _dio.get(
        '/common/natures',
        queryParameters: {'page': 1, 'start': 0, 'limit': 25},
      );
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List)
            .map((e) => NatureVente.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      print("Error fetching natures vente: $e");
      return [];
    }
  }

  Future<List<TypeVente>> getTypeVentes() async {
    try {
      final response = await _dio.get(
        '/common/typeventes',
        queryParameters: {'page': 1, 'start': 0, 'limit': 25},
      );
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List)
            .map((e) => TypeVente.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      print("Error fetching type ventes: $e");
      return [];
    }
  }

  Future<List<ClientAssurance>> searchClientAssurance(String query) async {
    try {
      final response = await _dio.get(
        '/client/all',
        queryParameters: {
          'query': query,
          'typeClientId': '1', // 1 = Client Assurance
          'page': 1,
          'start': 0,
          'limit': 25
        },
      );
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List)
            .map((e) => ClientAssurance.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      print("Error searching client assurance: $e");
      return [];
    }
  }

  Future<List<TiersPayantAssurance>> searchTiersPayantsAssurance(String query) async {
    try {
      final response = await _dio.get(
        '/client/tiers-payants/assurance',
        queryParameters: {'query': query, 'page': 1, 'start': 0, 'limit': 25},
      );
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List)
            .map((e) => TiersPayantAssurance.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      print("Error searching tiers payants assurance: $e");
      return [];
    }
  }

  Future<ClientAssurance?> createClientAssurance({
    required String firstName,
    required String lastName,
    required String numSecu,
    required String tiersPayantId,
    required int pourcentage,
  }) async {
    try {
      final response = await _dio.post(
        '/client/add/assurance',
        data: {
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
          "tiersPayants": []
        },
      );
      if (response.statusCode == 200 && response.data['success'] == true) {
        return ClientAssurance.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      print("Error creating client assurance: $e");
      return null;
    }
  }

  // MODIFICATION (Correction Ajout TP multiple)
  Future<ClientAssurance?> addTiersPayantToClient({
    required ClientAssurance existingClient,
    required Map<String, dynamic> newTiersPayantPayload,
  }) async {
    try {
      // 1. Récupère le tiers payant principal
      final mainTp = existingClient.tiersPayants.firstWhere(
              (tp) => tp.principal || tp.order == 1,
          orElse: () => existingClient.tiersPayants.first
      );

      // 2. Construit le payload principal
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
          // 3. Envoie SEULEMENT LE NOUVEAU TP dans la liste
          "tiersPayants": [
            newTiersPayantPayload
          ]
        },
      );
      if (response.statusCode == 200 && response.data['success'] == true) {
        return ClientAssurance.fromJson(response.data['data']);
      }
      print("Error adding tiers payant (API): ${response.data['msg']}");
      return null;
    } catch (e) {
      print("Error adding tiers payant to client: $e");
      return null;
    }
  }


  Future<List<AyantDroit>> getAyantDroits(String clientId) async {
    try {
      final response = await _dio.get(
        '/client/ayant-droits',
        queryParameters: {'clientId': clientId},
      );
      if (response.statusCode == 200 && response.data['data'] is List) {
        return (response.data['data'] as List)
            .map((e) => AyantDroit.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      print("Error fetching ayant droits: $e");
      return [];
    }
  }

  Future<AyantDroit?> createAyantDroit({
    required String clientId,
    required String firstName,
    required String lastName,
    required String numSecu,
    String? dtNaissance,
  }) async {
    try {
      final response = await _dio.post(
        '/client/ayant-droits/$clientId',
        data: {
          "dtNAISSANCE": dtNaissance ?? "",
          "lgVILLEID": "",
          "strFIRSTNAME": firstName,
          "strLASTNAME": lastName,
          "strNUMEROSECURITESOCIAL": numSecu
        },
      );
      if (response.statusCode == 200 && response.data['success'] == true) {
        return AyantDroit.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      print("Error creating ayant droit: $e");
      return null;
    }
  }

  Map<String, dynamic> _buildAssuranceSalePayload({
    required String produitId,
    required int qte,
    required int itemPu,
    required String clientId,
    required String ayantDroitId,
    required String natureVenteId,
    required String typeVenteId,
    required String? userVendeurId,
    required List<Map<String, dynamic>> tierspayants,
    String? venteId,
  }) {
    return {
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
      "tierspayants": tierspayants.map((tp) => {
        "cmu": "false",
        "compteTp": tp['compteTp'],
        "numBon": tp['numBon'],
        "taux": tp['taux']
      }).toList(),
      "typeVenteId": typeVenteId,
      "userVendeurId": userVendeurId,
      "venteId": venteId
    };
  }

  Future<String?> addAssuranceSaleItem({
    required String produitId,
    required int qte,
    required int itemPu,
    required String clientId,
    required String ayantDroitId,
    required String natureVenteId, // "1"
    required String typeVenteId,   // "2"
    required String? userVendeurId,
    required List<Map<String, dynamic>> tierspayants,
    String? venteId,
  }) async {
    try {
      final bool isFirstItem = venteId == null;
      final String endpoint = isFirstItem
          ? '/vente/add/assurance'
          : '/vente/add/item';

      final payload = _buildAssuranceSalePayload(
        produitId: produitId,
        qte: qte,
        itemPu: itemPu,
        clientId: clientId,
        ayantDroitId: ayantDroitId,
        natureVenteId: natureVenteId,
        typeVenteId: typeVenteId,
        userVendeurId: userVendeurId,
        tierspayants: tierspayants,
        venteId: venteId,
      );

      final response = await _dio.post(endpoint, data: payload);

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data']['lgPREENREGISTREMENTID'] ?? venteId;
      }
      return null;
    } catch (e) {
      print("Error adding assurance sale item: $e");
      return null;
    }
  }

  Future<AssuranceSaleSummary?> calculateNetAssurance({
    required String venteId,
    required List<Map<String, dynamic>> tierspayants,
  }) async {
    try {
      final response = await _dio.post(
        '/vente/net/assurance',
        data: {
          "remiseId": null,
          "tierspayants": tierspayants.map((tp) => {
            "cmu": "false",
            "compteTp": tp['compteTp'],
            "numBon": tp['numBon'],
            "taux": tp['taux']
          }).toList(),
          "venteId": venteId
        },
      );
      if (response.statusCode == 200 && response.data['success'] == true) {
        return AssuranceSaleSummary.fromNetResponse(response.data);
      }
      return null;
    } catch (e) {
      print("Error calculating net assurance: $e");
      return null;
    }
  }

  // MODIFICATION (Gestion Erreur N° Bon)
  // Renvoie maintenant une Map<String, dynamic>
  Future<Map<String, dynamic>> cloturerVenteAssurance({
    required String venteId,
    required String clientId,
    required String ayantDroitId,
    required String natureVenteId, // "1"
    required String typeVenteId,   // "2"
    required String? userVendeurId,
    required AssuranceSaleSummary summary,
    required String typeReglementId,
    required List<Map<String, dynamic>> tierspayants,
  }) async {
    try {
      final response = await _dio.post(
        '/vente/cloturer/assurance',
        data: {
          "ayantDroitId": ayantDroitId,
          "banque": "",
          "clientId": clientId,
          "commentaire": "",
          "devis": false,
          "lieux": "",
          "marge": summary.marge,
          "medecinId": null,
          "montantPaye": summary.montantNet,
          "montantRecu": summary.montantNet,
          "montantRemis": 0,
          "natureVenteId": natureVenteId,
          "nom": "",
          "partTP": summary.montantTp.toString(),
          "reglements": [
            {
              "montant": summary.montantNet,
              "montantAttentu": summary.montantNet,
              "typeReglement": typeReglementId
            }
          ],
          "remiseId": null,
          "sansBon": false,
          "tierspayants": tierspayants.map((tp) => {
            "activeTiersPayant": false,
            "cmu": false,
            "compteTp": tp['compteTp'],
            "dblPLAFOND": 0,
            "dblQUOTACONSOMENSUELLE": 0,
            "dbPLAFONDENCOURS": 0,
            "discount": 0,
            "enabled": false,
            "numBon": tp['numBon'],
            "numSecurity": "",
            "order": 0,
            "principal": false,
            "taux": tp['taux'],
            "tpnet": summary.tierspayants.firstWhere((ts) => ts.compteTp == tp['compteTp'], orElse: () => TiersPayantSummary(numBon: '', taux: 0, compteTp: '', tpnet: 0)).tpnet
          }).toList(),
          "totalRecap": summary.montant,
          "typeRegleId": typeReglementId,
          "typeVenteId": typeVenteId,
          "userVendeurId": userVendeurId,
          "venteId": venteId
        },
      );
      // Renvoie la réponse JSON complète (ex: {"success": true} ou {"success": false, "msg": "..."})
      return response.data;
    } catch (e) {
      print("Error closing assurance sale: $e");
      return {"success": false, "msg": "Erreur de connexion: $e"};
    }
  }

}