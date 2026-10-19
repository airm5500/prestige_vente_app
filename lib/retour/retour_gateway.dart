// lib/retour/retour_gateway.dart
// Retour fournisseur : fonctions existantes de Prestige. Le retour est créé « en préparation » ;
// sa validation (sortie de stock) reste faite sur Prestige par une personne habilitée.
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/retour/retour_models.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';

abstract class RetourGateway {
  /// BL entrés en stock entre [from] et [to] inclus (date d'entrée en stock), les plus récents d'abord.
  /// [query] : début du n° de BL.
  Future<List<ReceptionBl>> bls({String query = '', required DateTime from, required DateTime to});

  /// Lignes du BL. [query] : CIP, EAN ou début du nom.
  Future<List<ReceptionLine>> blLines(String blId, {String query = ''});
  Future<List<MotifRetour>> motifs();

  /// Crée le retour avec sa première ligne. [blRef] : n° du BL (pas son identifiant).
  /// 4.6.1 (décision 17 D8) : [blId] (identifiant du BL) désigne le BL exact quand deux grossistes ont le même
  /// numéro ; vide = comme avant (numéro seul, le BL le plus récent).
  Future<({bool success, String message, RetourCreated? retour})> create({
    required String blRef,
    required String produitId,
    required String motifId,
    required int quantity,
    String comment = '',
    String blId = '',
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
  DioRetourGateway(this.dio);

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
      final panne = panneDe(e);
      if (panne != null) return MessagesServeur.message(panne);
      if (r?.data is Map && (r!.data as Map)['msg'] != null) return '${(r.data as Map)['msg']}';
      if (r != null) return 'Erreur du serveur (${r.statusCode}). Le produit appartient-il bien à ce BL ?';
      return MessagesServeur.injoignable;
    }
    return '$e';
  }

  @override
  Future<List<ReceptionBl>> bls({String query = '', required DateTime from, required DateTime to}) async {
    final r = await dio.get('/commande/list-bons', queryParameters: {
      'query': query,
      'start': 0,
      'limit': 200,
      'statut': 'is_Closed',
      'dtStart': _iso.format(from),
      'dtEnd': _iso.format(to),
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
    String blId = '',
  }) async {
    try {
      final corps = corpsNouveauRetour(
          blRef: blRef,
          comment: comment.length > 50 ? comment.substring(0, 50) : comment,
          item: {'produitId': produitId, 'lgMOTIFRETOUR': motifId, 'intNUMBERRETURN': quantity},
          blId: blId);
      Response r;
      try {
        r = await dio.post('/retourfournisseur/new', data: corps);
      } on DioException catch (e) {
        // Serveur qui refuserait le champ inconnu `blId` (400 avant toute écriture) : même retour, sans blId.
        if (e.response?.statusCode != 400 || !corps.containsKey('blId')) rethrow;
        r = await dio.post('/retourfournisseur/new', data: Map.of(corps)..remove('blId'));
      }
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
      // 4.6.0 (décision 17 D7) : même produit avec un autre motif = nouvelle ligne, avec un message du serveur.
      final avis = ok ? avisAjoutRetour(r.data) : null;
      return (success: ok, message: ok ? (avis ?? messageProduitAjoute) : '${(r.data is Map ? (r.data as Map)['msg'] : null) ?? _failure}');
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

/// Message par défaut d'un produit ajouté au retour.
const String messageProduitAjoute = 'Produit ajouté';

/// 4.6.0 (décision 17 D7) : `data.message` de `retourfournisseur/add-item` (« Vous avez ajouté ce produit avec un
/// motif différent »), ou null (serveur ancien, ajout simple).
String? avisAjoutRetour(Object? corps) {
  if (corps is! Map) return null;
  final d = corps['data'];
  final m = d is Map ? '${d['message'] ?? ''}'.trim() : '';
  return m.isEmpty ? null : m;
}

/// 4.6.1 (décision 17 D8) : corps de `retourfournisseur/new`. `blId` (identifiant du BL) vise le BL exact sur un
/// serveur à jour ; un serveur ancien ignore ce champ inconnu (JSON-B) et prend le numéro seul, le BL le plus récent
/// (comme avant). Pas de `lgGROSSISTEID` : l'identifiant suffit. Un identifiant vide ou égal au numéro (BL non
/// retrouvé hors ligne) n'est pas envoyé.
Map<String, dynamic> corpsNouveauRetour({
  required String blRef,
  required String comment,
  required Map<String, dynamic> item,
  String blId = '',
}) {
  final id = blId.trim();
  return {
    'lgBONLIVRAISONID': blRef,
    if (id.isNotEmpty && id != blRef) 'blId': id,
    'strCOMMENTAIRE': comment,
    'items': [item],
  };
}
