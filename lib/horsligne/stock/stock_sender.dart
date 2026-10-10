// lib/horsligne/stock/stock_sender.dart
// Envoi d'UNE opération stock saisie hors ligne, avec les MÊMES routes que les écrans en ligne.
//
// Idempotence (aucun doublon même si l'envoi est coupé au milieu) :
//  - chaque ligne passe « sending » (enregistré sur le téléphone) AVANT l'appel, avec la valeur relevée
//    sur le serveur juste avant ([StockOpLine.avant]) ; si la réponse n'est jamais arrivée, l'envoi
//    suivant RELIT le serveur et marque « déjà appliqué » au lieu de renvoyer ;
//  - pointages (BL, commande) et emplacements : valeur posée (pas cumulée) → renvoi sans risque ;
//  - retour fournisseur : le commentaire porte la clé de l'opération ([HL:…]) pour retrouver un retour
//    déjà créé (/produit/retours-data, qui ne liste que les retours validés) ; si la réponse de la
//    création est perdue et le retour introuvable, AUCUN renvoi : anomalie « vérifier sur Prestige ».
//    Les produits suivants (add-item) sont relus dans /retourfournisseur/retours-items.
//    H4 (serveur avec le patch docs/serveur/H4_client_ref.patch) : la création porte la clé client
//    `X-Client-Ref` (clé de l'opération HL3-…) ; le serveur ne crée jamais deux fois et, si la réponse est
//    perdue, le retour est relu par sa clé (GET /mobile/client-ref/{ref}) : reprise sans anomalie.
// Les refus du serveur (BL clôturé, ligne déjà pointée, produit inconnu…) donnent une ligne « rejected »
// avec le motif ; une panne réseau ou une session expirée interrompt l'envoi ([StockStopException]).
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/client_ref.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';

/// Réponse brute du serveur (code HTTP + corps).
class StockHttp {
  final int status;
  final dynamic body;
  const StockHttp(this.status, this.body);
  bool get ok => status >= 200 && status < 300;
  Map<String, dynamic> get map => body is Map ? Map<String, dynamic>.from(body as Map) : const {};

  /// Liste `data` (ou `results`) d'une réponse de liste.
  List<Map<String, dynamic>> get list {
    final d = map['data'] ?? map['results'];
    return d is List ? [for (final e in d) if (e is Map) Map<String, dynamic>.from(e)] : const [];
  }

  /// Message d'erreur du serveur (sans HTML).
  String? get msg {
    final m = map['msg'] ?? map['message'];
    return m == null ? null : '$m'.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

/// Envoi interrompu : serveur injoignable ou session expirée. Rien n'est marqué refusé.
class StockStopException implements Exception {
  final String message;
  const StockStopException(this.message);
  @override
  String toString() => message;
}

/// Accès HTTP au serveur Prestige (remplaçable dans les tests).
abstract class StockServer {
  /// Lève [StockStopException] si le serveur ne répond pas. [headers] : en-têtes en plus (H4 : X-Client-Ref).
  Future<StockHttp> call(String method, String path, {Map<String, dynamic>? query, Object? data, Map<String, String>? headers});
}

class DioStockServer implements StockServer {
  final Dio dio;
  DioStockServer(this.dio);

  @override
  Future<StockHttp> call(String method, String path, {Map<String, dynamic>? query, Object? data, Map<String, String>? headers}) async {
    try {
      final r = await dio.request(path,
          queryParameters: query, data: data, options: Options(method: method, headers: headers, validateStatus: (_) => true));
      return StockHttp(r.statusCode ?? 0, r.data);
    } on DioException catch (e) {
      if (e.response != null) return StockHttp(e.response!.statusCode ?? 0, e.response!.data);
      throw const StockStopException('Serveur injoignable : envoi interrompu. Les opérations restantes sont gardées.');
    }
  }
}

class StockSender {
  final StockServer server;
  final DateTime Function() clock;

  /// Appelé après chaque changement d'état d'une ligne (persistance immédiate).
  final Future<void> Function(StockOp op) persist;

  StockSender(this.server, {required this.persist, DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  static final _iso = DateFormat('yyyy-MM-dd');
  static final _fr = DateFormat('dd/MM/yyyy');
  static int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  Future<StockHttp> _call(String method, String path, {Map<String, dynamic>? query, Object? data, Map<String, String>? headers}) async {
    final r = await server.call(method, path, query: query, data: data, headers: headers);
    if (r.status == 401 || r.status == 403) {
      throw const StockStopException('Session expirée : reconnectez-vous puis relancez l\'envoi.');
    }
    if (r.map['success'] == false && '${r.map['msg'] ?? ''}'.contains('Veuillez vous connecter')) {
      throw const StockStopException('Session expirée : reconnectez-vous puis relancez l\'envoi.');
    }
    return r;
  }

  Future<List<Map<String, dynamic>>> _list(String path, Map<String, dynamic> query) async {
    final r = await _call('GET', path, query: query);
    if (!r.ok) throw StockStopException('Le serveur n\'a pas pu relire les données ($path, code ${r.status}) : envoi interrompu.');
    return r.list;
  }

  Future<void> _set(StockOp op, StockOpLine l, StockLineEtat etat, [String? motif]) async {
    l.etat = etat;
    l.motif = motif;
    op.updatedAt = clock();
    await persist(op);
  }

  Future<void> _rejectAll(StockOp op, String motif) async {
    for (final l in op.toSend) {
      l.etat = StockLineEtat.rejected;
      l.motif = motif;
    }
    op.updatedAt = clock();
    await persist(op);
  }

  bool? _clientRef;

  /// H4 : le serveur gère la clé client (lu une fois par envoi ; cache commun par adresse de serveur).
  Future<bool> clientRefSupporte() async => _clientRef ??= await CapaciteClientRef.verifier(
        server is DioStockServer ? (server as DioStockServer).dio.options.baseUrl : 'stock-${identityHashCode(server)}',
        () async {
          final r = await server.call('GET', '/mobile/capacites');
          return CapaciteClientRef.depuisReponse(r.status, r.body);
        },
      );

  /// Envoie les lignes restantes de [op] (états mis à jour dans [op]).
  Future<void> apply(StockOp op) async {
    if (op.toSend.isEmpty) return;
    switch (op.type) {
      case StockOpType.reception:
        await _reception(op);
      case StockOpType.pointageBl:
        await _pointage(op, commande: false);
      case StockOpType.pointageCommande:
        await _pointage(op, commande: true);
      case StockOpType.peremption:
        await _peremption(op);
      case StockOpType.perime:
        await _perime(op);
      case StockOpType.retour:
        await _retour(op);
      case StockOpType.emplacement:
        await _emplacement(op);
    }
  }

  // --- Réception BL : lots (/commande/add-lot) -------------------------------------------------
  Future<void> _reception(StockOp op) async {
    final items = await _list('/commande/bon/items/${op.refId}', {'page': 1, 'start': 0, 'limit': 9999, 'query': '', 'filtre': 'ALL'});
    if (items.isEmpty) return _rejectAll(op, 'BL introuvable sur le serveur (supprimé ?) : lots non envoyés.');
    if (items.any((l) => l['str_STATUT'] == 'is_Closed')) {
      return _rejectAll(op, 'BL déjà clôturé (entré en stock) sur le serveur : lots non envoyés.');
    }
    final byDetail = {for (final l in items) '${l['lg_BON_LIVRAISON_DETAIL']}': l};
    for (final l in op.toSend) {
      final d = l.data;
      final srv = byDetail['${d['detailId']}'];
      if (srv == null) {
        await _set(op, l, StockLineEtat.rejected, 'Ligne absente du BL sur le serveur (produit retiré ?).');
        continue;
      }
      final qty = _int(d['qty']);
      final ug = _int(d['ug']);
      final entered = _int(srv['quantiteSaisie']);
      final lots = '${srv['lots'] ?? ''}'.split('|').map((e) => e.trim()).toSet();
      final numLot = '${d['numLot'] ?? ''}';
      if (l.etat == StockLineEtat.sending && l.avant != null && entered >= l.avant! + qty + ug && (numLot.isEmpty || lots.contains(numLot))) {
        await _set(op, l, StockLineEtat.dejaApplique, 'Déjà enregistré sur le serveur (envoi précédent).');
        continue;
      }
      l.avant = entered;
      await _set(op, l, StockLineEtat.sending);
      final r = await _call('POST', '/commande/add-lot', data: {
        'idBonDetail': d['detailId'],
        'qty': qty,
        'freeQty': ug,
        'numLot': numLot,
        'datePeremption': '${d['expiry'] ?? ''}',
        'directImport': false,
      });
      if (r.ok && r.map['success'] != false) {
        srv['quantiteSaisie'] = entered + qty + ug;
        srv['lots'] = [...lots.where((e) => e.isNotEmpty), numLot].join(' | ');
        await _set(op, l, StockLineEtat.applied);
        // Information de pointage (comme l'écran en ligne) ; sans effet sur la réception.
        try {
          await server.call('POST', '/commande/bon/items/checked-quantities',
              data: {'id': d['detailId'], 'checked': true, 'checkedQuantity': entered + qty + ug});
        } catch (_) {}
      } else {
        await _set(op, l, StockLineEtat.rejected, r.msg ?? 'Lot refusé par le serveur (code ${r.status}).');
      }
    }
  }

  // --- Pointage BL / contrôle commande (quantités contrôlées) ------------------------------------
  Future<void> _pointage(StockOp op, {required bool commande}) async {
    final List<Map<String, dynamic>> items;
    if (commande) {
      final encours = await _list('/commande/list', {'page': 1, 'start': 0, 'limit': 9999, 'query': ''});
      if (!encours.any((c) => '${c['lg_ORDER_ID']}' == op.refId)) {
        return _rejectAll(op, 'Commande plus en cours sur le serveur (déjà transformée en BL ?) : contrôle non envoyé.');
      }
      items = await _list('/commande/commande-en-cours-items', {'orderId': op.refId, 'page': 1, 'start': 0, 'limit': 9999});
    } else {
      items = await _list('/commande/bon/items/${op.refId}', {'page': 1, 'start': 0, 'limit': 9999});
    }
    if (items.isEmpty) return _rejectAll(op, commande ? 'Commande introuvable sur le serveur.' : 'BL introuvable sur le serveur (supprimé ?).');
    final idKey = commande ? 'lg_ORDERDETAIL_ID' : 'lg_BON_LIVRAISON_DETAIL';
    final byDetail = {for (final l in items) '${l[idKey]}': l};
    for (final l in op.toSend) {
      final d = l.data;
      final srv = byDetail['${d['detailId']}'];
      if (srv == null) {
        await _set(op, l, StockLineEtat.rejected, 'Ligne absente sur le serveur (produit retiré ?).');
        continue;
      }
      final qty = _int(d['qty']);
      final checked = srv['checked'] == true;
      final srvQty = _int(srv['checkedQuantity']);
      if (checked && srvQty == qty) {
        await _set(op, l, StockLineEtat.dejaApplique, 'Même quantité déjà pointée sur le serveur.');
        continue;
      }
      final base = d['base'] == null ? null : _int(d['base']);
      if (checked && srvQty != base) {
        await _set(op, l, StockLineEtat.rejected, 'Déjà pointée sur le serveur ($srvQty) : quantité $qty non envoyée.');
        continue;
      }
      await _set(op, l, StockLineEtat.sending);
      final r = await _call('POST', commande ? '/commande/item/checked-quantities' : '/commande/bon/items/checked-quantities',
          data: {'id': d['detailId'], 'checked': true, 'checkedQuantity': qty});
      if (r.ok && r.map['success'] != false) {
        await _set(op, l, StockLineEtat.applied);
      } else {
        await _set(op, l, StockLineEtat.rejected, r.msg ?? 'Quantité refusée par le serveur (code ${r.status}).');
      }
    }
  }

  // --- Dates de péremption (/fichearticle/add-lot) ---------------------------------------------
  Future<void> _peremption(StockOp op) async {
    for (final l in op.toSend) {
      final d = l.data;
      final qty = _int(d['qty']);
      final date = '${d['date']}'; // yyyy-MM-dd
      if (l.etat == StockLineEtat.sending) {
        final day = DateTime.tryParse('${d['sentDay'] ?? ''}') ?? clock();
        final lots = await _list('/lot/listlot', {
          'start': 0,
          'limit': 500,
          'dtStart': _iso.format(day),
          'dtEnd': _iso.format(clock()),
          'search_value': '${d['cip'] ?? ''}',
        });
        final dateFr = DateTime.tryParse(date) == null ? date : _fr.format(DateTime.parse(date));
        final found = lots.any((x) =>
            '${x['NUMLOT']}' == '${d['numLot']}' && '${x['DATEPEREMPTION']}' == dateFr && _int(x['NUMBER']) + _int(x['NUMBERGT']) == qty);
        if (found) {
          await _set(op, l, StockLineEtat.dejaApplique, 'Lot déjà enregistré sur le serveur (envoi précédent).');
          continue;
        }
      }
      d['sentDay'] = _iso.format(clock());
      await _set(op, l, StockLineEtat.sending);
      final r = await _call('POST', '/fichearticle/add-lot',
          data: {'produitId': d['produitId'], 'datePeremption': date, 'numLot': d['numLot'], 'quantity': qty});
      if (r.ok) {
        await _set(op, l, StockLineEtat.applied);
      } else {
        await _set(op, l, StockLineEtat.rejected,
            r.msg ?? (r.status >= 500 ? 'Refusé par le serveur (produit inconnu ?) — code ${r.status}.' : 'Refusé par le serveur (code ${r.status}).'));
      }
    }
  }

  // --- Saisie des périmés (/gestionperime/add) --------------------------------------------------
  Future<void> _perime(StockOp op) async {
    final encours = await _list('/gestionperime/saisie-encours', {'page': 1, 'start': 0, 'limit': 999});
    int srvQty(Map<String, dynamic> d) => encours
        .where((e) => '${e['produitId']}' == '${d['produitId']}' && '${e['lot']}' == '${d['lot']}')
        .fold(0, (s, e) => s + _int(e['quantity']));
    for (final l in op.toSend) {
      final d = l.data;
      final qty = _int(d['qty']);
      final now = srvQty(d);
      if (l.etat == StockLineEtat.sending && l.avant != null && now >= l.avant! + qty) {
        await _set(op, l, StockLineEtat.dejaApplique, 'Déjà enregistré sur le serveur (envoi précédent).');
        continue;
      }
      l.avant = now;
      await _set(op, l, StockLineEtat.sending);
      final r = await _call('POST', '/gestionperime/add', data: {'ref': d['produitId'], 'refParent': d['date'], 'refTwo': d['lot'], 'value': qty});
      if (r.ok && r.map['success'] == true) {
        encours.add({'produitId': d['produitId'], 'lot': d['lot'], 'quantity': qty});
        await _set(op, l, StockLineEtat.applied);
      } else {
        await _set(op, l, StockLineEtat.rejected, r.msg ?? 'Refusé par le serveur (code ${r.status}).');
      }
    }
  }

  // --- Retour fournisseur (/retourfournisseur/new puis add-item) --------------------------------
  Future<void> _retour(StockOp op) async {
    final marker = '${op.meta['marker']}';
    var retourId = op.meta['retourId'] as String?;
    Map<String, dynamic> item(StockOpLine l) =>
        {'produitId': l.data['produitId'], 'lgMOTIFRETOUR': l.data['motifId'], 'intNUMBERRETURN': _int(l.data['qty'])};

    // H4 : retour relu par la clé de l'opération ; true = trouvé (enregistré), false = jamais créé.
    Future<bool> relire(StockOpLine first) async {
      final r = await server.call('GET', '/mobile/client-ref/${Uri.encodeComponent(op.id)}');
      final lu = clientRefDepuisReponse(r.status, r.body);
      if (lu is! VenteOk<ClientRefInfo?>) {
        throw StockStopException('${lu.message ?? 'Relecture du retour impossible.'} Envoi interrompu, rien n\'est perdu.');
      }
      final info = lu.value;
      if (info == null) return false;
      retourId = info.id;
      op.meta['retourId'] = info.id;
      op.meta['retourRef'] = info.reference ?? '';
      await _set(op, first, StockLineEtat.dejaApplique, 'Retour déjà créé sur le serveur (envoi précédent, relu par sa clé).');
      return true;
    }

    while (retourId == null && op.toSend.isNotEmpty) {
      final first = op.toSend.first;
      if (first.etat == StockLineEtat.sending && op.meta['clientRef'] == true && await clientRefSupporte()) {
        // H4 : création envoyée avec la clé → relue ; clé inconnue = jamais créé, renvoi sans risque (même clé).
        if (await relire(first)) break;
      } else if (first.etat == StockLineEtat.sending) {
        // Création peut-être déjà faite : on cherche le retour par sa clé dans le commentaire.
        final from = op.sentAt ?? op.createdAt;
        final retours = await _list('/produit/retours-data', {
          'dtStart': _iso.format(from),
          'dtEnd': _iso.format(clock()),
          'start': 0,
          'limit': 500,
          'query': '',
          'filtre': '',
        });
        final found = retours.where((r) => '${r['str_COMMENTAIRE'] ?? ''}'.contains(marker)).firstOrNull;
        if (found != null) {
          retourId = '${found['lg_RETOUR_FRS_ID']}';
          op.meta['retourId'] = retourId;
          op.meta['retourRef'] = '${found['str_REF_RETOUR_FRS'] ?? ''}';
          await _set(op, first, StockLineEtat.dejaApplique, 'Retour déjà créé sur le serveur (envoi précédent).');
          break;
        }
        // Prestige ne liste pas les retours « en préparation » (vérifié sur le serveur de test) :
        // impossible de savoir si la création a eu lieu → pas de renvoi (risque de doublon), anomalie.
        return _rejectAll(op,
            'Réponse perdue pendant la création du retour : vérifiez sur Prestige les retours en préparation (commentaire $marker) avant de le ressaisir.');
      }
      final h4 = await clientRefSupporte();
      op.meta['clientRef'] = h4;
      await _set(op, first, StockLineEtat.sending);
      final StockHttp r;
      try {
        r = await _call('POST', '/retourfournisseur/new',
            data: {
              'lgBONLIVRAISONID': op.meta['blRef'],
              'strCOMMENTAIRE': op.meta['comment'] ?? marker,
              'items': [item(first)],
            },
            headers: h4 ? {enteteClientRef: op.id} : null);
      } on StockStopException {
        // H4 : réponse perdue → relecture immédiate par la clé (sinon : relue au prochain envoi).
        var repris = false;
        if (h4) {
          try {
            repris = await relire(first);
          } on StockStopException {
            repris = false;
          }
        }
        if (repris) break;
        rethrow;
      }
      final data = r.map['data'];
      if (r.ok && r.map['success'] == true && data is Map) {
        retourId = '${data['lgRETOURFRSID']}';
        op.meta['retourId'] = retourId;
        op.meta['retourRef'] = '${data['strREFRETOURFRS'] ?? ''}';
        await _set(op, first, StockLineEtat.applied);
      } else {
        await _set(op, first, StockLineEtat.rejected, r.msg ?? 'Retour refusé par le serveur (quantité, stock ou produit absent du BL).');
      }
    }
    if (retourId == null) return;
    var srvItems = <Map<String, dynamic>>[];
    if (op.toSend.isNotEmpty) srvItems = await _list('/retourfournisseur/retours-items', {'retourId': retourId});
    int srvQty(String produitId) => srvItems.where((e) => '${e['produitId']}' == produitId).fold(0, (s, e) => s + _int(e['intNUMBERRETURN']));
    for (final l in op.toSend) {
      final produitId = '${l.data['produitId']}';
      final qty = _int(l.data['qty']);
      final now = srvQty(produitId);
      if (l.etat == StockLineEtat.sending && l.avant != null && now >= l.avant! + qty) {
        await _set(op, l, StockLineEtat.dejaApplique, 'Déjà ajouté au retour sur le serveur (envoi précédent).');
        continue;
      }
      l.avant = now;
      await _set(op, l, StockLineEtat.sending);
      final r = await _call('POST', '/retourfournisseur/add-item', data: {'lgRETOURFRSID': retourId, ...item(l)});
      if (r.ok && r.map['success'] == true) {
        srvItems.add({'produitId': produitId, 'intNUMBERRETURN': qty});
        await _set(op, l, StockLineEtat.applied);
      } else {
        await _set(op, l, StockLineEtat.rejected, r.msg ?? 'Produit refusé par le serveur (quantité ou stock).');
      }
    }
  }

  // --- Emplacements (/fichearticle/produit/update-lite-info) ------------------------------------
  Future<void> _emplacement(StockOp op) async {
    for (final l in op.toSend) {
      await _set(op, l, StockLineEtat.sending);
      final r = await _call('POST', '/fichearticle/produit/update-lite-info', data: {'id': l.data['produitId'], 'rayonId': l.data['rayonId']});
      if (r.ok && r.map['success'] != false) {
        await _set(op, l, StockLineEtat.applied);
      } else {
        await _set(op, l, StockLineEtat.rejected, r.msg ?? 'Refusé par le serveur (produit ou emplacement inconnu) — code ${r.status}.');
      }
    }
  }
}
