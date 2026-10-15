// lib/reception/reception_gateway.dart
// Appels au serveur Prestige pour la réception des BL. Fonctions existantes de Prestige (écran
// « gestion des lots » du BL) : aucune modification du serveur n'est nécessaire.
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';

abstract class ReceptionGateway {
  Future<List<ReceptionBl>> bls({String query = ''});
  Future<List<ReceptionOrder>> orders();

  /// « Créer BL » depuis une commande (n° de BL refusé s'il existe déjà chez ce grossiste).
  Future<ReceptionResult> createBl({
    required String orderId,
    required String ref,
    required DateTime date,
    required int amountHt,
    required int tva,
  });

  /// Lignes du BL. [query] : CIP, EAN ou début du nom (recherche du serveur).
  Future<List<ReceptionLine>> lines(String blId, {String query = ''});

  /// [serie] / [gtin] (4.3.1, D18) : numéro de série et GTIN du DataMatrix de la boîte scannée ; un serveur à
  /// jour refuse une boîte déjà scannée (`code:"SERIE_DEJA_CONSOMMEE"`), un ancien serveur les ignore.
  Future<ReceptionResult> addLot({
    required String detailId,
    required int quantity,
    required int freeQty,
    required String numLot,
    DateTime? expiry,
    String? serie,
    String? gtin,
  });

  /// Efface tous les lots saisis sur la ligne (pour ressaisir).
  Future<ReceptionResult> clearLots(ReceptionLine line);

  /// Quantité contrôlée (information de pointage, utilisée par « Pointage BL Stock »).
  Future<void> markChecked(String detailId, int quantity);

  /// Droit « entrée en stock » de l'utilisateur connecté.
  Future<bool> canValidate();

  Future<ReceptionResult> validate(String blId);
}

class DioReceptionGateway implements ReceptionGateway {
  final Dio dio;
  DioReceptionGateway(this.dio);

  static final _iso = DateFormat('yyyy-MM-dd');

  List<Map<String, dynamic>> _list(dynamic data) {
    final list = data is Map ? data['data'] : null;
    if (list is! List) return const [];
    return [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)];
  }

  ReceptionResult _result(dynamic data, {String ok = 'Opération effectuée'}) {
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final success = m['success'] != false;
      return ReceptionResult(success, '${m['msg'] ?? (success ? ok : 'Échec de l\'opération')}', m);
    }
    return ReceptionResult(true, ok);
  }

  ReceptionResult _error(Object e) {
    if (e is DioException) {
      final r = e.response;
      if (r?.data is Map && (r!.data as Map)['msg'] != null) return ReceptionResult(false, '${(r.data as Map)['msg']}');
      if (r != null) return ReceptionResult(false, 'Erreur du serveur (${r.statusCode}).');
      return const ReceptionResult(false, 'Serveur injoignable. Vérifiez le réseau.');
    }
    return ReceptionResult(false, '$e');
  }

  @override
  Future<List<ReceptionBl>> bls({String query = ''}) async {
    final r = await dio.get('/commande/list-bons', queryParameters: {
      'query': query,
      'start': 0,
      'limit': 200,
      'statut': 'enable',
    });
    return _list(r.data).map(ReceptionBl.fromJson).toList();
  }

  @override
  Future<List<ReceptionOrder>> orders() async {
    final params = {'start': 0, 'limit': 200, 'query': ''};
    final encours = await dio.get('/commande/list', queryParameters: params);
    final passees = await dio.get('/commande/list/passees', queryParameters: params);
    return [
      ..._list(passees.data).map(ReceptionOrder.fromJson),
      ..._list(encours.data).map(ReceptionOrder.fromJson),
    ];
  }

  @override
  Future<ReceptionResult> createBl({
    required String orderId,
    required String ref,
    required DateTime date,
    required int amountHt,
    required int tva,
  }) async {
    try {
      final r = await dio.post('/commande/creerbl', data: {
        'refParent': orderId,
        'ref': ref,
        'dtStart': _iso.format(date),
        'value': amountHt,
        'valueTwo': tva,
      });
      return _result(r.data, ok: 'BL créé');
    } catch (e) {
      return _error(e);
    }
  }

  @override
  Future<List<ReceptionLine>> lines(String blId, {String query = ''}) async {
    final r = await dio.get('/commande/bon/items/$blId', queryParameters: {
      'start': 0,
      'limit': 9999,
      'query': query,
      'filtre': 'ALL',
    });
    return _list(r.data).map(ReceptionLine.fromJson).toList();
  }

  @override
  Future<ReceptionResult> addLot({
    required String detailId,
    required int quantity,
    required int freeQty,
    required String numLot,
    DateTime? expiry,
    String? serie,
    String? gtin,
  }) async {
    Map<String, dynamic> corps({required bool avecSerie}) => {
          'idBonDetail': detailId,
          'qty': quantity,
          'freeQty': freeQty,
          'numLot': numLot,
          'datePeremption': expiry == null ? '' : _iso.format(expiry),
          // Toujours un nouveau lot (le mode « import direct » remplacerait le lot existant).
          'directImport': false,
          ...champsSerie(serie, gtin, avecSerie: avecSerie),
        };
    try {
      final r = await dio.post('/commande/add-lot', data: corps(avecSerie: true));
      return resultatAjoutLot(_result(r.data, ok: 'Lot enregistré'));
    } on DioException catch (e) {
      // Serveur qui refuserait des champs inconnus (400 avant toute écriture) : même lot, sans série.
      if (e.response?.statusCode == 400 && champsSerie(serie, gtin).isNotEmpty) {
        try {
          final r = await dio.post('/commande/add-lot', data: corps(avecSerie: false));
          return resultatAjoutLot(_result(r.data, ok: 'Lot enregistré'));
        } catch (e2) {
          return _error(e2);
        }
      }
      return _error(e);
    } catch (e) {
      return _error(e);
    }
  }

  @override
  Future<ReceptionResult> clearLots(ReceptionLine line) async {
    try {
      await dio.put('/commande/remove-lots', data: {
        // removeLot=false : uniquement les lots de CE produit sur CE BL.
        'removeLot': false,
        'idProduit': line.produitId,
        'refBon': line.blRef,
        'idBonDetail': line.detailId,
      });
      return const ReceptionResult(true, 'Lots de la ligne effacés');
    } catch (e) {
      return _error(e);
    }
  }

  @override
  Future<void> markChecked(String detailId, int quantity) async {
    try {
      await dio.post('/commande/bon/items/checked-quantities', data: {'id': detailId, 'checked': true, 'checkedQuantity': quantity});
    } catch (_) {
      // Information secondaire : sans effet sur la réception.
    }
  }

  @override
  Future<bool> canValidate() async {
    try {
      final r = await dio.get('/commande/entree-stock/autorisation');
      return r.data is Map && (r.data as Map)['authorize'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ReceptionResult> validate(String blId) async {
    try {
      final r = await dio.put('/commande/validerbl/$blId');
      return _result(r.data, ok: 'Entrée en stock effectuée');
    } catch (e) {
      return _error(e);
    }
  }
}

/// D18 (4.3.1) : refus d'une boîte déjà scannée par le serveur.
const String codeSerieDejaConsommee = 'SERIE_DEJA_CONSOMMEE';

/// Message affiché pour une boîte déjà scannée.
const String messageBoiteDejaScannee = 'Boîte déjà scannée';

/// Champs `serie` / `gtin` du corps de `commande/add-lot` (vides si absents ; [avecSerie] faux : aucun).
Map<String, dynamic> champsSerie(String? serie, String? gtin, {bool avecSerie = true}) {
  final s = (serie ?? '').trim();
  if (!avecSerie || s.isEmpty) return const {};
  final g = (gtin ?? '').trim();
  return {'serie': s, if (g.isNotEmpty) 'gtin': g};
}

/// Réponse de `commande/add-lot` : le refus « boîte déjà scannée » reçoit son message clair et son code.
ReceptionResult resultatAjoutLot(ReceptionResult r) {
  if (r.success) return r;
  if ('${r.data['code'] ?? ''}' == codeSerieDejaConsommee) {
    return ReceptionResult(false, '$messageBoiteDejaScannee : cette boîte a déjà été enregistrée. Aucune quantité ajoutée ; scannez la boîte suivante.', r.data);
  }
  return r;
}
