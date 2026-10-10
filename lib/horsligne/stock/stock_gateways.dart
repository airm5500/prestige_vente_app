// lib/horsligne/stock/stock_gateways.dart
// Réception BL et retours fournisseurs : passerelles qui, HORS LIGNE, lisent la copie locale et
// enregistrent les saisies dans la file des opérations ; EN LIGNE, elles appellent la passerelle
// d'origine sans rien changer.
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_horsligne.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/retour/retour_gateway.dart';
import 'package:prestige_vente_app/retour/retour_models.dart';

bool _lineMatches(Map<String, dynamic> l, String query) {
  final q = foldText(query.trim());
  if (q.isEmpty) return true;
  return foldText('${l['lg_FAMILLE_NAME'] ?? ''}').contains(q) ||
      '${l['lg_FAMILLE_CIP'] ?? ''}'.startsWith(q) ||
      '${l['str_CODE_ARTICLE'] ?? ''}'.startsWith(q) ||
      '${l['int_EAN13'] ?? l['codeEanFabriquant'] ?? ''}'.startsWith(q);
}

final _fr = DateFormat('dd/MM/yyyy');

class OfflineReceptionGateway implements ReceptionGateway {
  final ReceptionGateway online;
  final StockHorsLigne? _stock;
  OfflineReceptionGateway(this.online, {StockHorsLigne? stock}) : _stock = stock;

  StockHorsLigne get stock => _stock ?? StockHorsLigne.instance;
  bool get _off => stock.offline;

  @override
  Future<List<ReceptionBl>> bls({String query = ''}) async {
    if (!_off) return online.bls(query: query);
    return [
      for (final r in await stock.rows(StockRef.blsAEntrer))
        if (query.isEmpty || '${r['str_REF_LIVRAISON']}'.toUpperCase().startsWith(query.toUpperCase())) ReceptionBl.fromJson(r),
    ];
  }

  @override
  Future<List<ReceptionOrder>> orders() async {
    if (!_off) return online.orders();
    final all = await stock.rows(StockRef.commandes);
    return [
      for (final r in all) if (r['_hl_passee'] == true) ReceptionOrder.fromJson(r),
      for (final r in all) if (r['_hl_passee'] != true) ReceptionOrder.fromJson(r),
    ];
  }

  /// Lignes de la copie + lots saisis hors ligne (quantités, lots et dates ajoutés).
  Future<List<Map<String, dynamic>>> _linesJson(String blId) async {
    final lines = await stock.rows(StockRef.lignesBl, parent: blId);
    if (lines.isEmpty) throw const StockHorsLigneException('Hors ligne : les lignes de ce BL ne sont pas sur cet appareil.');
    final pending = stock.queue.pendingLines(StockOpType.reception, refId: blId);
    for (final l in lines) {
      final mine = pending.where((p) => '${p.data['detailId']}' == '${l['lg_BON_LIVRAISON_DETAIL']}');
      for (final p in mine) {
        final qty = (p.data['qty'] as num).toInt();
        final ug = (p.data['ug'] as num? ?? 0).toInt();
        l['quantiteSaisie'] = ((l['quantiteSaisie'] as num?)?.toInt() ?? 0) + qty + ug;
        l['freeQty'] = ((l['freeQty'] as num?)?.toInt() ?? 0) + ug;
        l['lots'] = [...splitPipes('${l['lots'] ?? ''}'), '${p.data['numLot']}'].join(' | ');
        final exp = DateTime.tryParse('${p.data['expiry'] ?? ''}');
        if (exp != null) l['datePeremption'] = [...splitPipes('${l['datePeremption'] ?? ''}'), _fr.format(exp)].join(' | ');
        l['_hl_lots'] = ((l['_hl_lots'] as int?) ?? 0) + 1;
      }
    }
    return lines;
  }

  @override
  Future<List<ReceptionLine>> lines(String blId, {String query = ''}) async {
    if (!_off) return online.lines(blId, query: query);
    return [for (final l in await _linesJson(blId)) if (_lineMatches(l, query)) ReceptionLine.fromJson(l)];
  }

  @override
  Future<ReceptionResult> createBl({required String orderId, required String ref, required DateTime date, required int amountHt, required int tva}) async {
    if (!_off) return online.createBl(orderId: orderId, ref: ref, date: date, amountHt: amountHt, tva: tva);
    return const ReceptionResult(false, 'Création du BL : $kEnLigneUniquement (le n° de BL doit être vérifié par Prestige).');
  }

  @override
  Future<ReceptionResult> addLot({required String detailId, required int quantity, required int freeQty, required String numLot, DateTime? expiry}) async {
    if (!_off) return online.addLot(detailId: detailId, quantity: quantity, freeQty: freeQty, numLot: numLot, expiry: expiry);
    try {
      final raw = await stock.store.ref(StockRef.lignesBl, detailId);
      if (raw == null) return const ReceptionResult(false, 'Hors ligne : ligne de BL absente de la copie locale.');
      final blId = '${raw['_parent']}';
      final line = (await _linesJson(blId)).where((l) => '${l['lg_BON_LIVRAISON_DETAIL']}' == detailId).first;
      final parsed = ReceptionLine.fromJson(line);
      // Même contrôle que Prestige (quantité reçue ≤ commandée).
      if (parsed.entered + quantity > parsed.ordered) {
        return const ReceptionResult(false, 'La quantité réçue est supérieure à la quantité commantée.');
      }
      final bl = await stock.store.ref(StockRef.blsAEntrer, blId) ?? const {};
      await stock.queue.addReceptionLot(
        blId: blId,
        blRef: '${bl['str_REF_LIVRAISON'] ?? raw['str_REF_LIVRAISON'] ?? ''}',
        grossiste: '${bl['str_GROSSISTE_LIBELLE'] ?? ''}',
        detailId: detailId,
        produitId: parsed.produitId,
        produit: parsed.name,
        qty: quantity,
        ug: freeQty,
        numLot: numLot,
        expiry: expiry,
      );
      return const ReceptionResult(true, 'Lot enregistré hors ligne : il sera envoyé au retour du serveur.');
    } on StockHorsLigneException catch (e) {
      return ReceptionResult(false, e.message);
    } catch (e) {
      return ReceptionResult(false, 'Hors ligne : lot non enregistré sur l\'appareil ($e).');
    }
  }

  @override
  Future<ReceptionResult> clearLots(ReceptionLine line) async {
    if (!_off) return online.clearLots(line);
    final raw = await stock.store.ref(StockRef.lignesBl, line.detailId);
    final blId = '${raw?['_parent'] ?? ''}';
    final removed = await stock.queue.removeReceptionLots(blId, line.detailId);
    final serveur = (raw?['quantiteSaisie'] as num?)?.toInt() ?? 0;
    if (serveur > 0) {
      return ReceptionResult(removed > 0, [
        if (removed > 0) '$removed lot(s) saisi(s) hors ligne effacé(s).',
        'Lots déjà enregistrés sur le serveur — effacement : $kEnLigneUniquement.',
      ].join(' '));
    }
    return ReceptionResult(true, removed > 0 ? '$removed lot(s) saisi(s) hors ligne effacé(s).' : 'Aucun lot à effacer.');
  }

  @override
  Future<void> markChecked(String detailId, int quantity) async {
    if (!_off) return online.markChecked(detailId, quantity);
    // Hors ligne : le pointage est envoyé avec le lot (voir StockSender).
  }

  @override
  Future<bool> canValidate() async => _off ? false : await online.canValidate();

  @override
  Future<ReceptionResult> validate(String blId) async {
    if (!_off) return online.validate(blId);
    return const ReceptionResult(false, 'Entrée en stock : $kEnLigneUniquement.');
  }
}

class OfflineRetourGateway implements RetourGateway {
  final RetourGateway online;
  final StockHorsLigne? _stock;
  OfflineRetourGateway(this.online, {StockHorsLigne? stock}) : _stock = stock;

  StockHorsLigne get stock => _stock ?? StockHorsLigne.instance;
  bool get _off => stock.offline;

  @override
  Future<List<ReceptionBl>> bls({String query = '', required DateTime from, required DateTime to}) async {
    if (!_off) return online.bls(query: query, from: from, to: to);
    final iso = DateFormat('yyyy-MM-dd');
    final bls = await stock.blsClotures(query: query, dtStart: iso.format(from), dtEnd: iso.format(to));
    final ids = {for (final b in bls) b.id};
    return [for (final r in await stock.rows(StockRef.blsClotures)) if (ids.contains('${r['lg_BON_LIVRAISON_ID']}')) ReceptionBl.fromJson(r)];
  }

  @override
  Future<List<ReceptionLine>> blLines(String blId, {String query = ''}) async {
    if (!_off) return online.blLines(blId, query: query);
    final lines = await stock.rows(StockRef.lignesBl, parent: blId);
    if (lines.isEmpty) throw const StockHorsLigneException('Hors ligne : les lignes de ce BL ne sont pas sur cet appareil.');
    return [for (final l in lines) if (_lineMatches(l, query)) ReceptionLine.fromJson(l)];
  }

  @override
  Future<List<MotifRetour>> motifs() async {
    if (!_off) return online.motifs();
    return (await stock.rows(StockRef.motifsRetour)).map(MotifRetour.fromJson).toList();
  }

  Future<String> _motifLabel(String id) async =>
      '${(await stock.store.ref(StockRef.motifsRetour, id))?['strLIBELLE'] ?? id}';

  Future<String> _produit(String produitId, String blRef) async {
    for (final l in await stock.store.refs(StockRef.lignesBl)) {
      if ('${l['lg_FAMILLE_ID']}' == produitId) return '${l['lg_FAMILLE_NAME']}';
    }
    return produitId;
  }

  @override
  Future<({bool success, String message, RetourCreated? retour})> create({
    required String blRef,
    required String produitId,
    required String motifId,
    required int quantity,
    String comment = '',
  }) async {
    if (!_off) return online.create(blRef: blRef, produitId: produitId, motifId: motifId, quantity: quantity, comment: comment);
    final bl = (await stock.rows(StockRef.blsClotures)).where((r) => '${r['str_REF_LIVRAISON']}' == blRef).firstOrNull ?? const {};
    final op = await stock.queue.createRetour(
        blId: '${bl['lg_BON_LIVRAISON_ID'] ?? blRef}', blRef: blRef, grossiste: '${bl['str_GROSSISTE_LIBELLE'] ?? ''}', comment: comment);
    await stock.queue.addRetourLine(op,
        produitId: produitId, produit: await _produit(produitId, blRef), motifId: motifId, motif: await _motifLabel(motifId), qty: quantity);
    return (
      success: true,
      message: 'Retour enregistré hors ligne : il sera créé sur Prestige au retour du serveur.',
      retour: RetourCreated(op.id, 'hors ligne'),
    );
  }

  @override
  Future<({bool success, String message})> addItem({required String retourId, required String produitId, required String motifId, required int quantity}) async {
    if (!retourId.startsWith('HL3-')) {
      if (_off) return (success: false, message: 'Ajout à un retour déjà créé sur Prestige : $kEnLigneUniquement.');
      return online.addItem(retourId: retourId, produitId: produitId, motifId: motifId, quantity: quantity);
    }
    final op = stock.queue.byId(retourId);
    if (op == null || !op.pending) return (success: false, message: 'Retour hors ligne introuvable ou déjà envoyé.');
    await stock.queue.addRetourLine(op, produitId: produitId, produit: await _produit(produitId, ''), motifId: motifId, motif: await _motifLabel(motifId), qty: quantity);
    return (success: true, message: 'Produit ajouté (hors ligne)');
  }

  @override
  Future<({bool success, String message})> updateItem(String lineId, int quantity) async {
    if (!lineId.startsWith('HL3-')) {
      if (_off) return (success: false, message: 'Modification d\'un retour créé sur Prestige : $kEnLigneUniquement.');
      return online.updateItem(lineId, quantity);
    }
    final ok = await stock.queue.updateLineQty(lineId, quantity);
    return (success: ok, message: ok ? 'Quantité modifiée (hors ligne)' : 'Ligne déjà envoyée : modification $kEnLigneUniquement.');
  }

  @override
  Future<bool> removeItem(String lineId) async {
    if (!lineId.startsWith('HL3-')) return _off ? false : await online.removeItem(lineId);
    return stock.queue.removeLine(lineId);
  }

  @override
  Future<List<RetourLine>> items(String retourId) async {
    if (!retourId.startsWith('HL3-')) {
      if (_off) throw const StockHorsLigneException('Hors ligne : le détail d\'un retour créé sur Prestige n\'est pas disponible.');
      return online.items(retourId);
    }
    final op = stock.queue.byId(retourId);
    return [
      for (final l in op?.lines ?? const <StockOpLine>[])
        RetourLine(
          id: l.key,
          produitId: '${l.data['produitId']}',
          name: l.label,
          cip: '${l.data['cip'] ?? ''}',
          motif: '${l.data['motif'] ?? ''}',
          quantity: (l.data['qty'] as num).toInt(),
        ),
    ];
  }
}
