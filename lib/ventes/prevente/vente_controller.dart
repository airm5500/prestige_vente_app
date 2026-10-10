// lib/ventes/prevente/vente_controller.dart
// Vente en cours du menu Pré-vente / Vente (nouvelle version) : copie fiabilisée de SaleProvider.
// Toutes les écritures passent par la file de la vente (une à la fois) ; rien n'est annoncé
// avant la réponse du serveur ; une réponse perdue est vérifiée en relisant le panier.
// La vente est créée en prévente (statut pending) ; le choix se fait à la fin :
// « Enregistrer en prévente » (terminerprevente) ou « Encaisser » (cloturer/vno).
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/ventes/core/pending_sale_store.dart';
import 'package:prestige_vente_app/ventes/core/sale_op_queue.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Résultat de l'encaissement : [dejaCloturee] = le serveur indique une vente déjà clôturée.
typedef ClotureOk = ({bool dejaCloturee});

class VenteController extends ChangeNotifier {
  final VenteGateway gateway;
  VenteController({required this.gateway});

  SaleOpQueue _queue = SaleOpQueue();
  int _working = 0;
  bool _disposed = false;

  String? _venteId;
  List<SaleItemDetail> _items = const [];
  SaleSummary _summary = SaleSummary();
  String? _cartError;
  String? _netError;
  int _changes = 0;
  int _netAt = -1;
  bool _finished = false;
  int _epoch = 0;
  List<PaymentMethodQr> _qr = const [];

  String? get venteId => _venteId;
  List<SaleItemDetail> get items => _items;
  SaleSummary get summary => _summary;

  /// Relecture du panier échouée : l'ancien panier reste affiché, encaissement bloqué.
  String? get cartError => _cartError;

  /// Calcul du net échoué : encaissement bloqué (jamais l'ancien net envoyé).
  String? get netError => _netError;

  /// Une opération est en cours ou en attente.
  bool get busy => _working > 0;
  bool get hasCart => _venteId != null && _items.isNotEmpty;

  /// Net calculé APRÈS la dernière modification.
  bool get netUpToDate => _venteId != null && _netAt == _changes && _netError == null;

  /// Numéro de la dernière modification (pour vérifier que le panier n'a pas changé entre-temps).
  int get changes => _changes;

  /// Pourquoi la vente ne peut pas être terminée (null = possible).
  String? get finishBlockedReason {
    if (_venteId == null || _items.isEmpty) return 'Le panier est vide.';
    if (busy) return 'Envoi en cours, patientez…';
    if (_cartError != null) return 'Panier non relu : touchez « Réessayer » avant de terminer.';
    if (!netUpToDate) return 'Net à payer non calculé : touchez « Réessayer » avant de terminer.';
    return null;
  }

  bool get canFinish => finishBlockedReason == null;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _run<T>(Future<T> Function() op) async {
    _working++;
    _notify();
    try {
      return await _queue.run(op);
    } finally {
      _working--;
      _notify();
    }
  }

  /// Attend la fin des opérations en cours.
  Future<void> idle() => _queue.idle();

  // ---------------------------------------------------------------------------
  // Vente
  // ---------------------------------------------------------------------------

  /// Nouvelle vente (le panier précédent reste sur le serveur).
  void reset() {
    _epoch++;
    _queue = SaleOpQueue();
    _venteId = null;
    _items = const [];
    _summary = SaleSummary();
    _cartError = null;
    _netError = null;
    _changes = 0;
    _netAt = -1;
    _finished = false;
    _notify();
  }

  /// Affiche une vente existante (prévente de la liste, reprise, ordonnance).
  Future<void> loadVente(String id) {
    reset();
    _venteId = id;
    _changes = 1;
    return _run(() async {
      await _reload();
      await _remember();
    });
  }

  /// Relit le panier et recalcule le net (bouton « Réessayer »).
  Future<void> reload() => _run(_reload);

  Future<void> _reload() async {
    final id = _venteId;
    if (id == null) return;
    final at = _changes;
    final results = await Future.wait([gateway.saleDetails(id), gateway.netVno(id)]);
    final details = results[0] as VenteResult<List<SaleItemDetail>>;
    final net = results[1] as VenteResult<SaleSummary>;
    if (id != _venteId) return;
    if (details case VenteOk(:final value)) {
      _items = value;
      _cartError = null;
    } else {
      _cartError = details.message ?? 'Panier non relu.';
    }
    if (net case VenteOk(:final value)) {
      _summary = value;
      _netError = null;
      _netAt = at;
    } else {
      _netError = net.message ?? 'Net non calculé.';
    }
    _notify();
  }

  void _changed() {
    _changes++;
    _notify();
  }

  int _qtyOf(String produitId) => _items.where((i) => i.lgFAMILLEID == produitId).fold(0, (s, i) => s + i.intQUANTITY);

  /// Vente en cours mémorisée (reprise après fermeture) ; effacée si le panier est vide.
  Future<void> _remember() async {
    final id = _venteId;
    if (id == null || _finished) return;
    if (_items.isEmpty && _cartError == null) {
      await PendingSaleStore.clear(VenteMenu.prevente);
      return;
    }
    await PendingSaleStore.save(
      VenteMenu.prevente,
      PendingSale(venteId: id, reference: _summary.reference, itemCount: _items.length, total: _summary.montantNet, savedAt: DateTime.now()),
    );
  }

  // ---------------------------------------------------------------------------
  // Recherche
  // ---------------------------------------------------------------------------

  /// Recherche produit (≥ 3 caractères) ; produits « RV » masqués selon le réglage, comme avant.
  bool _hideRv = true;
  bool _rvLoaded = false;

  /// Recherche par pages (total du serveur) : utilisée par la barre de recherche pour les codes exacts
  /// et les longues listes. Le réglage « masquer RV » est lu une fois.
  Future<VenteResult<ProductPage>> searchPage(String query, int start, int limit) async {
    if (!_rvLoaded) {
      try {
        _hideRv = (await SharedPreferences.getInstance()).getBool('hide_rv_products') ?? true;
      } catch (_) {}
      _rvLoaded = true;
    }
    return gateway.searchProductsPage(query, start, limit);
  }

  /// Produit affiché dans les résultats (produits « RV » masqués selon le réglage).
  bool visibleProduct(ProductSearchResult p) => !_hideRv || !p.strNAME.toUpperCase().startsWith('RV ');

  Future<VenteResult<List<ProductSearchResult>>> search(String query) async {
    final r = await gateway.searchProducts(query);
    if (r is! VenteOk<List<ProductSearchResult>>) return r;
    var hideRv = true;
    try {
      hideRv = (await SharedPreferences.getInstance()).getBool('hide_rv_products') ?? true;
    } catch (_) {}
    if (!hideRv) return r;
    return VenteOk(r.value.where((p) => !p.strNAME.toUpperCase().startsWith('RV ')).toList());
  }

  // ---------------------------------------------------------------------------
  // Panier
  // ---------------------------------------------------------------------------

  /// Ajoute [qty] unités. Le 1ᵉʳ ajout crée la vente (en prévente) ; les ajouts suivants attendent son identifiant.
  Future<VenteResult<void>> addProduct(ProductSearchResult p, int qty) => _run(() async {
        if (_finished) return const VenteRefused('Vente déjà terminée : commencez une nouvelle vente.');
        if (qty < 1 || qty > 9999) return const VenteRefused('Quantité invalide (1 à 9 999).');
        final id = _venteId;
        final epoch = _epoch;
        final before = _qtyOf(p.lgFAMILLEID);
        final r = await gateway.addItemVno(produitId: p.lgFAMILLEID, qte: qty, itemPu: p.intPRICE, venteId: id, prevente: true);
        if (epoch != _epoch) return const VenteRefused('Vente abandonnée : produit non ajouté au nouveau panier.');
        if (r case VenteOk(:final value)) {
          _venteId = value;
          _changed();
          await _reload();
          await _remember();
          return const VenteOk(null);
        }
        if (r.uncertain && id != null) {
          // Réponse perdue : relire le panier avant toute nouvelle tentative.
          _changed();
          await _reload();
          if (_cartError == null && _qtyOf(p.lgFAMILLEID) >= before + qty) {
            await _remember();
            return const VenteOk(null);
          }
          return VenteFailed('${r.message ?? ''} Produit non ajouté : vérifiez le panier puis réessayez.'.trim());
        }
        if (r.uncertain) {
          return VenteFailed('${r.message ?? ''} La vente a peut-être été créée sans réponse du serveur : '
                  'vérifiez avant de recommencer.'
              .trim());
        }
        return r.map((_) {});
      });

  /// Modifie quantité et prix d'une ligne.
  Future<VenteResult<void>> updateLine(SaleItemDetail item, int qty, int price) => _run(() async {
        if (_finished) return const VenteRefused('Vente déjà terminée.');
        final r = await gateway.updateItem(itemId: item.lgPREENREGISTREMENTDETAILID, produitId: item.lgFAMILLEID, qte: qty, itemPu: price);
        if (r.isOk || r.uncertain) {
          _changed();
          await _reload();
          await _remember();
        }
        if (r.isOk) return const VenteOk(null);
        if (r.uncertain) {
          final line = _items.where((i) => i.lgPREENREGISTREMENTDETAILID == item.lgPREENREGISTREMENTDETAILID).firstOrNull;
          if (_cartError == null && line != null && line.intQUANTITY == qty && line.intPRICEUNITAIR == price) return const VenteOk(null);
          return VenteFailed('${r.message ?? ''} Modification non confirmée : vérifiez la ligne.'.trim());
        }
        return r;
      });

  /// Retire une ligne.
  Future<VenteResult<void>> removeLine(SaleItemDetail item) => _run(() async {
        if (_finished) return const VenteRefused('Vente déjà terminée.');
        final r = await gateway.removeItem(item.lgPREENREGISTREMENTDETAILID);
        if (r.isOk || r.uncertain) {
          _changed();
          await _reload();
          await _remember();
        }
        if (r.isOk) return const VenteOk(null);
        if (r.uncertain) {
          final still = _items.any((i) => i.lgPREENREGISTREMENTDETAILID == item.lgPREENREGISTREMENTDETAILID);
          if (_cartError == null && !still) return const VenteOk(null);
          return VenteFailed('${r.message ?? ''} Suppression non confirmée : vérifiez le panier.'.trim());
        }
        return r;
      });

  // ---------------------------------------------------------------------------
  // Fin de vente
  // ---------------------------------------------------------------------------

  /// Statut lu sur /ventestats/{id} (null si illisible).
  static String? statutOf(Map<String, dynamic> data) {
    for (final k in const ['strSTATUT', 'statut', 'str_STATUT', 'status']) {
      final v = data[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  Future<String?> _statut(String id) async {
    final r = await gateway.fullSale(id);
    return r is VenteOk<Map<String, dynamic>> ? statutOf(r.value) : null;
  }

  /// Vente déjà clôturée sur le serveur (ex. encaissée par un caissier) ; null si inconnu.
  Future<bool?> isClosedOnServer(String id) async {
    final s = await _statut(id);
    return s == null ? null : s == 'is_Closed';
  }

  /// « Enregistrer en prévente » : la vente passe dans la liste des préventes à encaisser.
  Future<VenteResult<void>> terminerPrevente() => _run(() async {
        final id = _venteId;
        if (id == null || _items.isEmpty) return const VenteRefused('Le panier est vide.');
        if (_finished) return const VenteOk(null);
        final r = await gateway.terminerPrevente(id);
        if (r.isOk) return _finish();
        if (r.uncertain) {
          final s = await _statut(id);
          if (s == 'is_Process' || s == 'is_Closed') return _finish();
          return VenteFailed('${r.message ?? ''} Enregistrement non confirmé : vérifiez la liste des préventes puis réessayez.'.trim());
        }
        return r;
      });

  /// « Encaisser » : même enchaînement qu'avant (client = mode de règlement, puis clôture).
  /// [expectedChanges] : le panier confirmé par le vendeur ne doit pas avoir changé.
  Future<VenteResult<ClotureOk>> encaisser({
    required PaymentMethod method,
    required String userId,
    required int expectedChanges,
    int? montantRecu,
    int? montantRemis,
  }) =>
      _run(() async {
        final id = _venteId;
        if (id == null || _items.isEmpty) return const VenteRefused('Le panier est vide.');
        if (_finished) return const VenteOk((dejaCloturee: true));
        if (expectedChanges != _changes) return const VenteRefused('Le panier a changé : vérifiez le total puis encaissez à nouveau.');
        if (_cartError != null || !netUpToDate) return const VenteRefused('Net à payer non à jour : touchez « Réessayer » puis encaissez.');
        final clientId = method.name.toLowerCase().replaceAll(' ', '').replaceAll('é', 'e');
        // Comme l'original : le résultat de l'association du client n'est pas bloquant.
        await gateway.updateClient(id, clientId);
        final r = await gateway.cloturerVno(
          venteId: id,
          summary: _summary,
          typeReglementId: method.id,
          clientId: clientId,
          userVendeurId: userId,
          montantRecu: montantRecu,
          montantRemis: montantRemis,
        );
        if (r.isOk) {
          await _finish();
          return const VenteOk((dejaCloturee: false));
        }
        if (r is VenteRefused<Map<String, dynamic>> && r.dejaCloturee) {
          await _finish();
          return const VenteOk((dejaCloturee: true));
        }
        if (r.uncertain) {
          // Réponse perdue : relire la vente, jamais de seconde clôture à l'aveugle.
          if (await _statut(id) == 'is_Closed') {
            await _finish();
            return const VenteOk((dejaCloturee: false));
          }
          return VenteFailed('${r.message ?? ''} Encaissement non confirmé : vérifiez la vente. '
                  'Encaisser à nouveau est sans risque (le serveur refuse une double clôture).'
              .trim());
        }
        return r.map((_) => (dejaCloturee: false));
      });

  Future<VenteResult<void>> _finish() async {
    _finished = true;
    await PendingSaleStore.clear(VenteMenu.prevente);
    _notify();
    return const VenteOk(null);
  }

  bool get finished => _finished;

  // ---------------------------------------------------------------------------
  // Modes de paiement / liste
  // ---------------------------------------------------------------------------

  Future<VenteResult<List<PaymentMethod>>> paymentMethods() => gateway.paymentMethods();

  /// QR des modes de paiement (échec sans gravité : pas de QR affiché, comme avant).
  Future<void> loadQrMethods() async {
    if (_qr.isNotEmpty) return;
    final r = await gateway.paymentMethodsWithQr();
    if (r case VenteOk(:final value)) _qr = value;
  }

  PaymentMethodQr? qrFor(String methodId) => _qr.where((m) => m.id == methodId).firstOrNull;

  /// Préventes comptant à encaisser, sans doublon, les plus récentes d'abord.
  Future<VenteResult<List<PreventeListItem>>> preventes() async {
    final r = await gateway.preventes();
    if (r is! VenteOk<List<PreventeListItem>>) return r;
    final unique = <String, PreventeListItem>{};
    for (final p in r.value.where((p) => p.lgTYPEVENTEID == '1')) {
      unique.putIfAbsent(p.lgPREENREGISTREMENTID, () => p);
    }
    final list = unique.values.toList();
    list.sort((a, b) {
      final da = preventeDateTime(a), db = preventeDateTime(b);
      if (da == null || db == null) return 0;
      return db.compareTo(da);
    });
    return VenteOk(list);
  }
}

/// Date/heure d'une prévente (le serveur envoie « dd/MM/yyyy » + « HH:mm:ss » ; ISO accepté).
DateTime? preventeDateTime(PreventeListItem p) {
  final d = p.dtUPDATED.trim();
  DateTime? day;
  try {
    day = DateFormat('dd/MM/yyyy').parseStrict(d);
  } catch (_) {
    day = DateTime.tryParse(d);
  }
  if (day == null) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(p.heure.trim());
  if (m == null || d.contains('T')) return day;
  return DateTime(day.year, day.month, day.day, int.parse(m.group(1)!), int.parse(m.group(2)!), int.tryParse(m.group(3) ?? '') ?? 0);
}

/// Date affichée dans la liste : « dd/MM/yyyy HH:mm » (texte du serveur tel quel s'il est illisible).
String preventeDateLabel(PreventeListItem p) {
  final dt = preventeDateTime(p);
  if (dt == null) return '${p.dtUPDATED} ${p.heure}'.trim();
  final hasTime = RegExp(r'^\d{1,2}:\d{2}').hasMatch(p.heure.trim()) || p.dtUPDATED.contains('T');
  return hasTime ? DateFormat('dd/MM/yyyy HH:mm').format(dt) : DateFormat('dd/MM/yyyy').format(dt);
}
