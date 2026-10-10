// lib/retour/retour_gateway.dart
// Retour fournisseur : fonctions existantes de Prestige. Le retour est créé « en préparation » ;
// sa validation (sortie de stock) reste faite sur Prestige par une personne habilitée.
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/retour/retour_models.dart';

abstract class RetourGateway {
  /// BL déjà entrés en stock (les plus récents d'abord). [query] : début du n° de BL.
  Future<List<ReceptionBl>> bls({String query = ''});

  /// Lignes du BL. [query] : CIP, EAN ou début du nom.
  Future<List<ReceptionLine>> blLines(String blId, {String query = ''});
  Future<List<MotifRetour>> motifs();

  /// Crée le retour avec sa première ligne. [blRef] : n° du BL (pas son identifiant).
  Future<({bool success, String message, RetourCreated? retour})> create({
    required String blRef,
    required String produitId,
    required String motifId,
    required int quantity,
    String comment = '',
  });

  /// Ajoute un produit (si déjà présent, Prestige cumule la quantité).
  Future<({bool success, String message})> addItem({
    required String retourId,
    required String produitId,
    required String motifId,
    required int quantity,
  });
  Future<({bool success, String message})> updateItem(String lineId, int quantity);
  Future<bool> removeItem(String lineId);
  Future<List<RetourLine>> items(String retourId);
}

class DioRetourGateway implements RetourGateway {
  final Dio dio;
  final DateTime Function() clock;
  DioRetourGateway(this.dio, {this.clock = DateTime.now});

  static final _iso = DateFormat('yyyy-MM-dd');
  static const _failure = 'Opération refusée par Prestige. Vérifiez la quantité à retourner.';

  List<Map<String, dynamic>> _list(dynamic data) {
    final list = data is Map ? data['data'] : null;
    if (list is! List) return const [];
    return [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)];
  }

  String _message(Object e) {
    if (e is DioException) {
      final r = e.response;
      if (r?.data is Map && (r!.data as Map)['msg'] != null) return '${(r.data as Map)['msg']}';
      if (r != null) return 'Erreur du serveur (${r.statusCode}). Le produit appartient-il bien à ce BL ?';
      return 'Serveur injoignable. Vérifiez le réseau.';
    }
    return '$e';
  }

  @override
  Future<List<ReceptionBl>> bls({String query = ''}) async {
    final now = clock();
    final r = await dio.get('/commande/list-bons', queryParameters: {
      'query': query,
      'start': 0,
      'limit': 200,
      'statut': 'is_Closed',
      // Sans n° recherché : les entrées en stock des 6 derniers mois.
      if (query.isEmpty) 'dtStart': _iso.format(now.subtract(const Duration(days: 183))),
      if (query.isEmpty) 'dtEnd': _iso.format(now),
    });
    return _list(r.data).map(ReceptionBl.fromJson).toList();
  }

  @override
  Future<List<ReceptionLine>> blLines(String blId, {String query = ''}) async {
    final r = await dio.get('/commande/bon/items/$blId', queryParameters: {'start': 0, 'limit': 9999, 'query': query, 'filtre': 'ALL'});
    return _list(r.data).map(ReceptionLine.fromJson).toList();
  }

  @override
  Future<List<MotifRetour>> motifs() async {
    final r = await dio.get('/common/motifs-retour');
    return _list(r.data).map(MotifRetour.fromJson).toList();
  }

  @override
  Future<({bool success, String message, RetourCreated? retour})> create({
    required String blRef,
    required String produitId,
    required String motifId,
    required int quantity,
    String comment = '',
  }) async {
    try {
      final r = await dio.post('/retourfournisseur/new', data: {
        'lgBONLIVRAISONID': blRef,
        'strCOMMENTAIRE': comment.length > 50 ? comment.substring(0, 50) : comment,
        'items': [
          {'produitId': produitId, 'lgMOTIFRETOUR': motifId, 'intNUMBERRETURN': quantity},
        ],
      });
      final m = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : <String, dynamic>{};
      final d = m['data'];
      if (m['success'] == true && d is Map) {
        return (
          success: true,
          message: 'Retour créé',
          retour: RetourCreated('${d['lgRETOURFRSID']}', '${d['strREFRETOURFRS'] ?? ''}'),
        );
      }
      return (success: false, message: '${m['msg'] ?? _failure}', retour: null);
    } catch (e) {
      return (success: false, message: _message(e), retour: null);
    }
  }

  @override
  Future<({bool success, String message})> addItem({
    required String retourId,
    required String produitId,
    required String motifId,
    required int quantity,
  }) async {
    try {
      final r = await dio.post('/retourfournisseur/add-item', data: {
        'lgRETOURFRSID': retourId,
        'produitId': produitId,
        'lgMOTIFRETOUR': motifId,
        'intNUMBERRETURN': quantity,
      });
      final ok = r.data is Map && (r.data as Map)['success'] == true;
      return (success: ok, message: ok ? 'Produit ajouté' : '${(r.data is Map ? (r.data as Map)['msg'] : null) ?? _failure}');
    } catch (e) {
      return (success: false, message: _message(e));
    }
  }

  @override
  Future<({bool success, String message})> updateItem(String lineId, int quantity) async {
    try {
      final r = await dio.post('/retourfournisseur/update-item', data: {'lgRETOURFRSDETAIL': lineId, 'intNUMBERRETURN': quantity});
      final ok = r.data is Map && (r.data as Map)['success'] == true;
      return (success: ok, message: ok ? 'Quantité modifiée' : '${(r.data is Map ? (r.data as Map)['msg'] : null) ?? _failure}');
    } catch (e) {
      return (success: false, message: _message(e));
    }
  }

  @override
  Future<bool> removeItem(String lineId) async {
    try {
      await dio.delete('/retourfournisseur/remove-item/$lineId');
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<RetourLine>> items(String retourId) async {
    final r = await dio.get('/retourfournisseur/retours-items', queryParameters: {'retourId': retourId});
    return _list(r.data).map(RetourLine.fromJson).toList();
  }
}

/// Contrôle de la quantité à retourner : pas plus que reçu sur le BL, ni que le stock actuel
/// (quantité déjà mise dans ce retour comprise).
String? checkReturnQuantity({required ReceptionLine line, required int alreadyInReturn, required int quantity}) {
  if (quantity <= 0) return 'Quantité nulle ou négative.';
  final total = alreadyInReturn + quantity;
  if (line.received > 0 && total > line.received) {
    return 'Quantité supérieure à la quantité reçue sur ce BL (${line.received}'
        '${alreadyInReturn > 0 ? ', dont $alreadyInReturn déjà dans ce retour' : ''}).';
  }
  if (total > line.stock) {
    return 'Stock insuffisant : ${line.stock} en stock'
        '${alreadyInReturn > 0 ? ' ($alreadyInReturn déjà dans ce retour)' : ''}.';
  }
  return null;
}
