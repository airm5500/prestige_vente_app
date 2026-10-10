// lib/ventes/carnet/carnet_controller.dart
// Vente Carnet (nouvelle version) : copie fiabilisée de CarnetSaleProvider.
// Parcours conservé : Client → Bon & ayant droit → Produits. Mêmes appels serveur
// (typeVenteId '3', natureVenteId '1', clients typeClientId '2', tiers payants carnet).
// Toutes les écritures de la vente passent par sa file (une à la fois) ; rien n'est annoncé
// avant la réponse du serveur ; le net est recalculé automatiquement après chaque changement.
//
// Nom / prénom : partout dans l'application le client s'affiche « strFIRSTNAME strLASTNAME »
// (« NOM Prénom ») et la création de client envoie Nom → strFIRSTNAME, Prénom → strLASTNAME.
// L'ancienne création d'ayant droit carnet envoyait l'inverse (défaut n°12) : ici, client et
// ayant droit suivent la même règle (Nom → strFIRSTNAME, Prénom → strLASTNAME).
import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/ventes/core/pending_sale_store.dart';
import 'package:prestige_vente_app/ventes/core/sale_op_queue.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CarnetStep { clientSearch, bonAndAyantDroit, productSearch }

/// Résultat de la validation : [dejaCloturee] = le serveur indique une vente déjà clôturée.
typedef CarnetClotureOk = ({bool dejaCloturee});

/// Vente reconstituée (reprise depuis la mémoire ou l'historique).
class CarnetRestore {
  final String venteId;
  final ClientAssurance client;
  final AyantDroit ayantDroit;
  final List<String> activeCompteTps;
  final Map<String, String> bons;
  const CarnetRestore({required this.venteId, required this.client, required this.ayantDroit, required this.activeCompteTps, required this.bons});
}

class CarnetController extends ChangeNotifier {
  static const String natureVenteId = '1'; // PRESCRIPTION
  static const String typeVenteId = '3'; // CARNET
  static const String typeClientId = '2'; // client carnet

  final VenteGateway gateway;
  final String userId;
  CarnetController({required this.gateway, required this.userId});

  SaleOpQueue _queue = SaleOpQueue();
  int _working = 0;
  bool _disposed = false;
  int _epoch = 0;

  CarnetStep _step = CarnetStep.clientSearch;
  ClientAssurance? _client;
  List<AyantDroit> _ayantDroits = const [];
  AyantDroit? _ayantDroit;
  bool _ayantDroitsLoading = false;
  String? _ayantDroitsError;
  List<ClientTiersPayant> _activeTps = const [];
  Map<String, String> _bons = {};

  String? _venteId;
  List<SaleItemDetail> _items = const [];
  AssuranceSaleSummary? _summary;
  String? _cartError;
  String? _netError;
  int _changes = 0;
  int _netAt = -1;
  bool _finished = false;

  CarnetStep get step => _step;
  ClientAssurance? get client => _client;
  List<AyantDroit> get ayantDroits => _ayantDroits;
  AyantDroit? get ayantDroit => _ayantDroit;
  bool get ayantDroitsLoading => _ayantDroitsLoading;
  String? get ayantDroitsError => _ayantDroitsError;
  List<ClientTiersPayant> get activeTps => _activeTps;
  Map<String, String> get bons => Map.unmodifiable(_bons);

  String? get venteId => _venteId;
  List<SaleItemDetail> get items => _items;
  AssuranceSaleSummary? get summary => _summary;
  String? get cartError => _cartError;
  String? get netError => _netError;
  int get changes => _changes;
  bool get finished => _finished;

  /// Une opération est en cours ou en attente.
  bool get busy => _working > 0;
  bool get hasCart => _venteId != null && _items.isNotEmpty;

  /// L'ayant droit est fixé dès que la vente existe sur le serveur.
  bool get ayantDroitLocked => _venteId != null;

  /// Net calculé APRÈS la dernière modification (panier, bons, tiers payants).
  bool get netUpToDate => _venteId != null && _summary != null && _netAt == _changes && _netError == null;

  /// Pourquoi la vente ne peut pas être terminée (null = possible).
  String? get finishBlockedReason {
    if (_client == null || _ayantDroit == null) return 'Client ou ayant droit manquant.';
    if (_venteId == null || _items.isEmpty) return 'Le panier est vide.';
    if (busy) return 'Envoi en cours, patientez…';
    if (_cartError != null) return 'Panier non relu : touchez « Réessayer » avant de valider.';
    if (!netUpToDate) return 'Net à payer non calculé : touchez « Réessayer » avant de valider.';
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
  // Nouvelle vente
  // ---------------------------------------------------------------------------

  /// Nouvelle vente : retour à la recherche client (une vente en cours reste sur le serveur).
  void startNew() {
    _epoch++;
    _queue = SaleOpQueue();
    _step = CarnetStep.clientSearch;
    _client = null;
    _ayantDroits = const [];
    _ayantDroit = null;
    _ayantDroitsLoading = false;
    _ayantDroitsError = null;
    _activeTps = const [];
    _bons = {};
    _venteId = null;
    _items = const [];
    _summary = null;
    _cartError = null;
    _netError = null;
    _changes = 0;
    _netAt = -1;
    _finished = false;
    _notify();
  }

  // ---------------------------------------------------------------------------
  // Étape 1 : client
  // ---------------------------------------------------------------------------

  /// Recherche client carnet (≥ 2 caractères, comme avant).
  Future<VenteResult<List<ClientAssurance>>> searchClients(String query) {
    final q = VenteInput.cleanQuery(query);
    if (q.length < 2) return Future.value(const VenteOk([]));
    return gateway.searchClients(q, typeClientId: typeClientId);
  }

  /// Recherche de carnet (tiers payant) pour la création d'un client (≥ 3 caractères).
  Future<VenteResult<List<TiersPayantAssurance>>> searchCarnets(String query) {
    final q = VenteInput.cleanQuery(query);
    if (q.length < 3) return Future.value(const VenteOk([]));
    return gateway.searchTiersPayants(q, carnet: true);
  }

  /// L'ayant droit « client lui-même » (identifiant du client), comme l'original.
  static AyantDroit selfAyantDroit(ClientAssurance c) => AyantDroit(
        lgAYANTSDROITSID: c.lgCLIENTID,
        lgCLIENTID: c.lgCLIENTID,
        fullName: c.fullName.isNotEmpty ? c.fullName : '${c.strFIRSTNAME} ${c.strLASTNAME}'.trim(),
        strFIRSTNAME: c.strFIRSTNAME,
        strLASTNAME: c.strLASTNAME,
        strNUMEROSECURITESOCIAL: c.strNUMEROSECURITESOCIAL,
        strSEXE: '',
      );

  /// Liste d'ayants droit avec le client lui-même toujours présent (en tête).
  static List<AyantDroit> _withSelf(ClientAssurance c, List<AyantDroit> list) {
    final valid = list.where((a) => a.lgAYANTSDROITSID.isNotEmpty).toList();
    final self = valid.where((a) => a.lgAYANTSDROITSID == c.lgCLIENTID).firstOrNull ?? selfAyantDroit(c);
    return [self, ...valid.where((a) => a.lgAYANTSDROITSID != c.lgCLIENTID)];
  }

  /// Client choisi : tous ses carnets actifs, bons vides, ayant droit = le client lui-même.
  void selectClient(ClientAssurance c) {
    startNew();
    _client = c;
    _activeTps = List.of(c.tiersPayants);
    _bons = {for (final tp in c.tiersPayants) tp.compteTp: ''};
    _ayantDroits = _withSelf(c, c.ayantDroits);
    _ayantDroit = _ayantDroits.first;
    _step = CarnetStep.bonAndAyantDroit;
    _notify();
    loadAyantDroits();
  }

  /// Ayants droit du client (pour en choisir un autre). Échec : le client reste son propre ayant droit.
  Future<void> loadAyantDroits() async {
    final c = _client;
    if (c == null) return;
    final epoch = _epoch;
    _ayantDroitsLoading = true;
    _notify();
    final r = await gateway.ayantDroits(c.lgCLIENTID);
    if (epoch != _epoch) return;
    _ayantDroitsLoading = false;
    if (r case VenteOk(:final value)) {
      _ayantDroitsError = null;
      _ayantDroits = _withSelf(c, value);
      final current = _ayantDroit;
      _ayantDroit = _ayantDroits.where((a) => a.lgAYANTSDROITSID == current?.lgAYANTSDROITSID).firstOrNull ?? current ?? _ayantDroits.first;
      if (!_ayantDroits.contains(_ayantDroit)) _ayantDroits = [..._ayantDroits, _ayantDroit!];
    } else {
      _ayantDroitsError = r.message ?? 'Ayants droit non chargés.';
    }
    _notify();
  }

  /// Création d'un client carnet (Nom → strFIRSTNAME, Prénom → strLASTNAME), puis sélection.
  Future<VenteResult<ClientAssurance>> createClient({
    required String nom,
    required String prenom,
    required String matricule,
    required TiersPayantAssurance carnet,
  }) async {
    final n = VenteInput.cleanName(nom), p = VenteInput.cleanName(prenom), m = VenteInput.cleanName(matricule);
    if (n.isEmpty) return const VenteRefused('Le nom est obligatoire.');
    final r = await gateway.createClientCarnet(firstName: n, lastName: p, numSecu: m, tiersPayantId: carnet.lgTIERSPAYANTID);
    if (r case VenteOk(:final value)) {
      selectClient(value);
      return r;
    }
    if (r.uncertain) {
      return VenteFailed('${r.message ?? ''} Le client a peut-être été créé : recherchez-le avant de le recréer.'.trim());
    }
    return r;
  }

  // ---------------------------------------------------------------------------
  // Étape 2 : bons et ayant droit
  // ---------------------------------------------------------------------------

  void selectAyantDroit(AyantDroit a) {
    if (ayantDroitLocked) return;
    _ayantDroit = a;
    _notify();
  }

  /// Nouvel ayant droit du client (Nom → strFIRSTNAME, Prénom → strLASTNAME), sélectionné ensuite.
  Future<VenteResult<AyantDroit>> createAyantDroit({required String nom, required String prenom, required String matricule}) async {
    final c = _client;
    if (c == null) return const VenteRefused('Aucun client sélectionné.');
    if (ayantDroitLocked) return const VenteRefused('Ayant droit fixé : la vente est déjà créée.');
    final n = VenteInput.cleanName(nom), p = VenteInput.cleanName(prenom), m = VenteInput.cleanName(matricule);
    if (n.isEmpty) return const VenteRefused('Le nom est obligatoire.');
    final epoch = _epoch;
    final r = await gateway.createAyantDroit(clientId: c.lgCLIENTID, firstName: n, lastName: p, numSecu: m);
    if (epoch != _epoch) return r;
    if (r case VenteOk(:final value)) {
      await loadAyantDroits();
      if (epoch != _epoch) return r;
      final created = _ayantDroits.where((a) => a.lgAYANTSDROITSID == value.lgAYANTSDROITSID).firstOrNull;
      if (created != null) {
        _ayantDroit = created;
      } else if (value.lgAYANTSDROITSID.isNotEmpty) {
        _ayantDroits = [..._ayantDroits, value];
        _ayantDroit = value;
      }
      _notify();
      return r;
    }
    if (r.uncertain) {
      await loadAyantDroits();
      return VenteFailed('${r.message ?? ''} L\'ayant droit a peut-être été créé : vérifiez la liste avant de le recréer.'.trim());
    }
    return r;
  }

  /// Coche / décoche un carnet (jamais le dernier).
  void toggleTp(ClientTiersPayant tp, bool active) {
    final list = List.of(_activeTps);
    if (active) {
      if (list.any((a) => a.compteTp == tp.compteTp)) return;
      list.add(tp);
      _bons[tp.compteTp] = _bons[tp.compteTp] ?? '';
    } else {
      if (list.length <= 1) return;
      list.removeWhere((a) => a.compteTp == tp.compteTp);
    }
    _activeTps = list;
    _invalidateNet();
  }

  bool isActive(ClientTiersPayant tp) => _activeTps.any((a) => a.compteTp == tp.compteTp);

  /// Contrôle des bons (obligatoires, nettoyés, sans doublon) puis passage aux produits.
  /// Renvoie le compte du tiers payant en défaut avec le message, ou null si tout va bien.
  ({String? compteTp, String message})? validateBons(Map<String, String> saisis) {
    final c = _client;
    final ad = _ayantDroit;
    if (c == null) return (compteTp: null, message: 'Aucun client sélectionné.');
    if (ad == null || ad.lgAYANTSDROITSID.isEmpty) return (compteTp: null, message: 'Choisissez l\'ayant droit (patient).');
    if (_activeTps.isEmpty) return (compteTp: null, message: 'Aucun carnet n\'est actif pour ce client.');
    final cleaned = <String, String>{};
    for (final tp in _activeTps) {
      final b = VenteInput.cleanBon(saisis[tp.compteTp] ?? _bons[tp.compteTp]);
      if (b.isEmpty) return (compteTp: tp.compteTp, message: 'Le N° de bon pour ${tp.tpFullName} est requis.');
      cleaned[tp.compteTp] = b;
    }
    if (VenteInput.hasDuplicateBons(cleaned)) return (compteTp: null, message: 'Le même N° de bon est saisi deux fois.');
    final changed = _activeTps.any((tp) => _bons[tp.compteTp] != cleaned[tp.compteTp]);
    _bons = {..._bons, ...cleaned};
    _step = CarnetStep.productSearch;
    if (changed || !netUpToDate) {
      _invalidateNet();
      if (_venteId != null) reload();
    } else {
      _notify();
    }
    return null;
  }

  void goToBonStep() {
    if (_client == null) return;
    _step = CarnetStep.bonAndAyantDroit;
    _notify();
  }

  void _invalidateNet() {
    _changes++;
    _notify();
  }

  List<VenteTp> _tps() => [for (final tp in _activeTps) (compteTp: tp.compteTp, numBon: _bons[tp.compteTp] ?? '', taux: tp.taux)];

  // ---------------------------------------------------------------------------
  // Étape 3 : produits / panier
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

  /// Relit le panier et recalcule le net (bouton « Réessayer »).
  Future<void> reload() => _run(_reload);

  Future<void> _reload() async {
    final id = _venteId;
    if (id == null) return;
    final at = _changes;
    final tps = _tps();
    final results = await Future.wait([gateway.saleDetails(id), gateway.netAssurance(venteId: id, tierspayants: tps)]);
    if (id != _venteId) return;
    final details = results[0] as VenteResult<List<SaleItemDetail>>;
    final net = results[1] as VenteResult<AssuranceSaleSummary>;
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
    } else if (_cartError == null && _items.isEmpty) {
      _summary = null;
      _netError = null;
    } else {
      _netError = net.message ?? 'Net non calculé.';
    }
    _notify();
  }

  int _qtyOf(String produitId) => _items.where((i) => i.lgFAMILLEID == produitId).fold(0, (s, i) => s + i.intQUANTITY);

  /// Ajoute [qty] unités. Le 1ᵉʳ ajout crée la vente ; les ajouts suivants attendent son identifiant.
  Future<VenteResult<void>> addProduct(ProductSearchResult p, int qty) => _run(() async {
        if (_finished) return const VenteRefused('Vente déjà terminée : commencez une nouvelle vente.');
        final c = _client, ad = _ayantDroit;
        if (c == null) return const VenteRefused('Aucun client sélectionné.');
        if (ad == null || ad.lgAYANTSDROITSID.isEmpty) return const VenteRefused('Ayant droit non défini : revenez à l\'étape des bons.');
        if (qty < 1 || qty > VenteInput.maxQuantity) return const VenteRefused('Quantité invalide (1 à 9 999).');
        final id = _venteId;
        final epoch = _epoch;
        final before = _qtyOf(p.lgFAMILLEID);
        final r = await gateway.addItemAssurance(
          produitId: p.lgFAMILLEID,
          qte: qty,
          itemPu: p.intPRICE,
          clientId: c.lgCLIENTID,
          ayantDroitId: ad.lgAYANTSDROITSID,
          natureVenteId: natureVenteId,
          typeVenteId: typeVenteId,
          userVendeurId: userId,
          tierspayants: _tps(),
          venteId: id,
        );
        if (epoch != _epoch) return const VenteRefused('Vente abandonnée : produit non ajouté au nouveau panier.');
        if (r case VenteOk(:final value)) {
          _venteId = value;
          _changes++;
          await _reload();
          await _remember();
          return const VenteOk(null);
        }
        if (r.uncertain && id != null) {
          // Réponse perdue : relire le panier avant toute nouvelle tentative.
          _changes++;
          await _reload();
          if (_cartError == null && _qtyOf(p.lgFAMILLEID) >= before + qty) {
            await _remember();
            return const VenteOk(null);
          }
          return VenteFailed('${r.message ?? ''} Produit non ajouté : vérifiez le panier puis réessayez.'.trim());
        }
        if (r.uncertain) {
          return VenteFailed('${r.message ?? ''} La vente a peut-être été créée sans réponse du serveur : '
                  'vérifiez l\'historique du client avant de recommencer.'
              .trim());
        }
        return r.map((_) {});
      });

  /// Modifie quantité et prix d'une ligne.
  Future<VenteResult<void>> updateLine(SaleItemDetail item, int qty, int price) => _run(() async {
        if (_finished) return const VenteRefused('Vente déjà terminée.');
        final r = await gateway.updateItem(itemId: item.lgPREENREGISTREMENTDETAILID, produitId: item.lgFAMILLEID, qte: qty, itemPu: price);
        if (r.isOk || r.uncertain) {
          _changes++;
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
          _changes++;
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

  /// Vente déjà clôturée sur le serveur ; null si inconnu.
  Future<bool?> isClosedOnServer(String id) async {
    final s = await _statut(id);
    return s == null ? null : s == 'is_Closed';
  }

  /// « Enregistrer en prévente » (terminerprevente), comme le bouton « Prévente » d'origine.
  Future<VenteResult<void>> terminerPrevente({required int expectedChanges}) => _run(() async {
        final id = _venteId;
        if (id == null || _items.isEmpty) return const VenteRefused('Le panier est vide.');
        if (_finished) return const VenteOk(null);
        if (expectedChanges != _changes || !netUpToDate || _cartError != null) {
          return const VenteRefused('Net à payer non à jour : touchez « Réessayer » puis validez.');
        }
        final r = await gateway.terminerPrevente(id);
        if (r.isOk) return _finish();
        if (r.uncertain) {
          final s = await _statut(id);
          if (s == 'is_Process' || s == 'is_Closed') return _finish();
          return VenteFailed('${r.message ?? ''} Enregistrement non confirmé : vérifiez l\'historique puis réessayez.'.trim());
        }
        return r;
      });

  /// « Valider » : clôture carnet, comme l'original (espèces id '1', montant reçu = net, sans dialogue de paiement).
  Future<VenteResult<CarnetClotureOk>> valider({required int expectedChanges}) => _run(() async {
        final id = _venteId, c = _client, ad = _ayantDroit, s = _summary;
        if (id == null || _items.isEmpty) return const VenteRefused('Le panier est vide.');
        if (c == null || ad == null) return const VenteRefused('Client ou ayant droit manquant.');
        if (_finished) return const VenteOk((dejaCloturee: true));
        if (expectedChanges != _changes) return const VenteRefused('Le panier a changé : vérifiez le net puis validez à nouveau.');
        if (s == null || _cartError != null || !netUpToDate) return const VenteRefused('Net à payer non à jour : touchez « Réessayer » puis validez.');
        final r = await gateway.cloturerAssurance(
          venteId: id,
          clientId: c.lgCLIENTID,
          ayantDroitId: ad.lgAYANTSDROITSID,
          natureVenteId: natureVenteId,
          typeVenteId: typeVenteId,
          userVendeurId: userId,
          summary: s,
          typeReglementId: '1',
          tierspayants: _tps(),
        );
        if (r.isOk) {
          await _finish();
          return const VenteOk((dejaCloturee: false));
        }
        if (r is VenteRefused<Map<String, dynamic>>) {
          if (r.dejaCloturee) {
            await _finish();
            return const VenteOk((dejaCloturee: true));
          }
          if (r.message.contains('est déjà utilisé')) {
            // Bon déjà utilisé : retour à l'étape des bons (comme l'original), net à recalculer.
            _step = CarnetStep.bonAndAyantDroit;
            _changes++;
          }
        }
        if (r.uncertain) {
          // Réponse perdue : relire la vente, jamais de seconde clôture à l'aveugle.
          if (await _statut(id) == 'is_Closed') {
            await _finish();
            return const VenteOk((dejaCloturee: false));
          }
          return VenteFailed('${r.message ?? ''} Validation non confirmée : vérifiez la vente. '
                  'Valider à nouveau est sans risque (le serveur refuse une double clôture).'
              .trim());
        }
        return r.map((_) => (dejaCloturee: false));
      });

  Future<VenteResult<void>> _finish() async {
    _finished = true;
    await PendingSaleStore.clear(VenteMenu.carnet);
    _notify();
    return const VenteOk(null);
  }

  // ---------------------------------------------------------------------------
  // Mémoire de la vente en cours / reprise
  // ---------------------------------------------------------------------------

  Future<void> _remember() async {
    final id = _venteId, c = _client, ad = _ayantDroit;
    if (id == null || c == null || ad == null || _finished) return;
    if (_items.isEmpty && _cartError == null) {
      await PendingSaleStore.clear(VenteMenu.carnet);
      return;
    }
    await PendingSaleStore.save(
      VenteMenu.carnet,
      PendingSale(
        venteId: id,
        reference: _items.isNotEmpty ? _items.first.strREF : '',
        itemCount: _items.length,
        total: _summary?.montantNet ?? 0,
        savedAt: DateTime.now(),
        extra: {
          'client': clientToJson(c),
          'ayantDroit': ayantDroitToJson(ad),
          'tps': [for (final tp in _activeTps) tp.compteTp],
          'bons': Map<String, String>.from(_bons),
        },
      ),
    );
  }

  /// Vente mémorisée → données pour la reprendre (null si illisible).
  static CarnetRestore? restoreFromPending(PendingSale p) {
    try {
      final cj = p.extra['client'];
      final aj = p.extra['ayantDroit'];
      if (cj is! Map || aj is! Map) return null;
      final client = parseClient(Map<String, dynamic>.from(cj));
      final ad = parseAyantDroit(Map<String, dynamic>.from(aj));
      if (client == null || ad == null) return null;
      final tps = p.extra['tps'] is List ? [for (final t in p.extra['tps'] as List) '$t'] : <String>[];
      final bons = p.extra['bons'] is Map ? {for (final e in (p.extra['bons'] as Map).entries) '${e.key}': '${e.value}'} : <String, String>{};
      return CarnetRestore(venteId: p.venteId, client: client, ayantDroit: ad, activeCompteTps: tps, bons: bons);
    } catch (_) {
      return null;
    }
  }

  /// Vente lue sur le serveur (/ventestats/{id}) → données pour la reprendre (null si illisible).
  static CarnetRestore? restoreFromServer(String venteId, Map<String, dynamic> data) {
    final cj = data['client'];
    if (cj is! Map) return null;
    final client = parseClient(Map<String, dynamic>.from(cj));
    if (client == null) return null;
    final aj = data['ayantDroit'];
    final ad = (aj is Map ? parseAyantDroit(Map<String, dynamic>.from(aj)) : null) ?? selfAyantDroit(client);
    final tps = <String>[];
    final bons = <String, String>{};
    var tpClient = client;
    final used = data['tierspayants'];
    if (used is List) {
      final extra = <ClientTiersPayant>[];
      for (final t in used) {
        if (t is! Map) continue;
        final compte = '${t['compteTp'] ?? ''}';
        if (compte.isEmpty) continue;
        tps.add(compte);
        bons[compte] = '${t['numBon'] ?? ''}';
        if (!client.tiersPayants.any((c) => c.compteTp == compte)) {
          extra.add(ClientTiersPayant(
            lgTIERSPAYANTID: '${t['lgTIERSPAYANTID'] ?? ''}',
            tpFullName: '${t['tpFullName'] ?? t['strNAME'] ?? compte}',
            taux: _int(t['taux']),
            numSecurity: '${t['numSecurity'] ?? ''}',
            compteTp: compte,
            order: 1,
            principal: false,
          ));
        }
      }
      if (extra.isNotEmpty) {
        tpClient = ClientAssurance(
          lgCLIENTID: client.lgCLIENTID,
          fullName: client.fullName,
          strFIRSTNAME: client.strFIRSTNAME,
          strLASTNAME: client.strLASTNAME,
          strNUMEROSECURITESOCIAL: client.strNUMEROSECURITESOCIAL,
          tiersPayants: [...client.tiersPayants, ...extra],
          ayantDroits: client.ayantDroits,
        );
      }
    }
    return CarnetRestore(venteId: venteId, client: tpClient, ayantDroit: ad, activeCompteTps: tps, bons: bons);
  }

  /// Reprend une vente existante (mémorisée ou depuis l'historique) : client, ayant droit, bons, panier, net.
  Future<void> restore(CarnetRestore r) {
    startNew();
    final c = r.client;
    _client = c;
    final active = c.tiersPayants.where((tp) => r.activeCompteTps.contains(tp.compteTp)).toList();
    _activeTps = active.isEmpty ? List.of(c.tiersPayants) : active;
    _bons = {for (final tp in c.tiersPayants) tp.compteTp: VenteInput.cleanBon(r.bons[tp.compteTp])};
    _ayantDroits = _withSelf(c, [...c.ayantDroits, r.ayantDroit]);
    _ayantDroit = _ayantDroits.where((a) => a.lgAYANTSDROITSID == r.ayantDroit.lgAYANTSDROITSID).firstOrNull ?? _ayantDroits.first;
    _venteId = r.venteId;
    _changes = 1;
    final bonsOk = _activeTps.every((tp) => (_bons[tp.compteTp] ?? '').isNotEmpty);
    _step = bonsOk ? CarnetStep.productSearch : CarnetStep.bonAndAyantDroit;
    _notify();
    return _run(() async {
      await _reload();
      await _remember();
    });
  }

  // ---------------------------------------------------------------------------
  // Historique
  // ---------------------------------------------------------------------------

  /// Historique des ventes carnet (50 dernières), sans doublon, les plus récentes d'abord.
  Future<VenteResult<List<PreventeListItem>>> history() async {
    final r = await gateway.ventesByType(typeVenteId);
    if (r is! VenteOk<List<PreventeListItem>>) return r;
    final unique = <String, PreventeListItem>{};
    for (final p in r.value) {
      unique.putIfAbsent(p.lgPREENREGISTREMENTID, () => p);
    }
    return VenteOk(unique.values.toList());
  }

  // ---------------------------------------------------------------------------
  // Lecture tolérante des données serveur
  // ---------------------------------------------------------------------------

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  static String _str(Object? v) => v == null ? '' : '$v';

  static ClientAssurance? parseClient(Map<String, dynamic> j) {
    final id = _str(j['lgCLIENTID']);
    if (id.isEmpty) return null;
    final tps = <ClientTiersPayant>[];
    if (j['tiersPayants'] is List) {
      for (final t in j['tiersPayants'] as List) {
        if (t is! Map) continue;
        tps.add(ClientTiersPayant(
          lgTIERSPAYANTID: _str(t['lgTIERSPAYANTID']),
          tpFullName: _str(t['tpFullName']),
          taux: _int(t['taux']),
          numSecurity: _str(t['numSecurity'] ?? t['strNUMEROSECURITESOCIAL']),
          compteTp: _str(t['compteTp']),
          order: t['order'] == null ? 1 : _int(t['order']),
          principal: t['principal'] == true,
        ));
      }
    }
    final first = _str(j['strFIRSTNAME']), last = _str(j['strLASTNAME']);
    final full = _str(j['fullName']);
    return ClientAssurance(
      lgCLIENTID: id,
      fullName: full.isNotEmpty ? full : '$first $last'.trim(),
      strFIRSTNAME: first,
      strLASTNAME: last,
      strNUMEROSECURITESOCIAL: _str(j['strNUMEROSECURITESOCIAL']),
      tiersPayants: tps,
      ayantDroits: [
        if (j['ayantDroits'] is List)
          for (final a in j['ayantDroits'] as List)
            if (a is Map) parseAyantDroit(Map<String, dynamic>.from(a)),
      ].whereType<AyantDroit>().toList(),
    );
  }

  static AyantDroit? parseAyantDroit(Map<String, dynamic> j) {
    final id = _str(j['lgAYANTSDROITSID']);
    if (id.isEmpty) return null;
    final first = _str(j['strFIRSTNAME']), last = _str(j['strLASTNAME']);
    final full = _str(j['fullName']);
    return AyantDroit(
      lgAYANTSDROITSID: id,
      lgCLIENTID: _str(j['lgCLIENTID']),
      fullName: full.isNotEmpty ? full : '$first $last'.trim(),
      strFIRSTNAME: first,
      strLASTNAME: last,
      strNUMEROSECURITESOCIAL: _str(j['strNUMEROSECURITESOCIAL']),
      strSEXE: _str(j['strSEXE']),
    );
  }

  static Map<String, dynamic> clientToJson(ClientAssurance c) => {
        'lgCLIENTID': c.lgCLIENTID,
        'fullName': c.fullName,
        'strFIRSTNAME': c.strFIRSTNAME,
        'strLASTNAME': c.strLASTNAME,
        'strNUMEROSECURITESOCIAL': c.strNUMEROSECURITESOCIAL,
        'tiersPayants': [
          for (final t in c.tiersPayants)
            {
              'lgTIERSPAYANTID': t.lgTIERSPAYANTID,
              'tpFullName': t.tpFullName,
              'taux': t.taux,
              'numSecurity': t.numSecurity,
              'compteTp': t.compteTp,
              'order': t.order,
              'principal': t.principal,
            }
        ],
      };

  static Map<String, dynamic> ayantDroitToJson(AyantDroit a) => {
        'lgAYANTSDROITSID': a.lgAYANTSDROITSID,
        'lgCLIENTID': a.lgCLIENTID,
        'fullName': a.fullName,
        'strFIRSTNAME': a.strFIRSTNAME,
        'strLASTNAME': a.strLASTNAME,
        'strNUMEROSECURITESOCIAL': a.strNUMEROSECURITESOCIAL,
        'strSEXE': a.strSEXE,
      };
}
