// lib/ventes/assurance/assurance_controller.dart
// Vente assurance en cours (nouvelle version) : copie fiabilisée d'AssuranceSaleProvider.
// Le contrôleur appartient à l'écran (plus de vente perdue en pleine saisie).
// Toutes les écritures passent par la file de la vente ; rien n'est annoncé avant la réponse
// du serveur ; une réponse perdue est vérifiée en relisant le panier ; le net est recalculé
// automatiquement après chaque changement (panier, tiers payants, taux, bons).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/ventes/core/paiement_multiple.dart';
import 'package:prestige_vente_app/ventes/core/pending_sale_store.dart';
import 'package:prestige_vente_app/ventes/core/sale_op_queue.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart' show VenteController;
import 'package:shared_preferences/shared_preferences.dart';

enum AssuranceStep { clientSearch, bonAndAyantDroit, productSearch }

/// Tiers payant utilisé pour la vente (taux modifiable pour cette vente).
class ActiveTiersPayant {
  final ClientTiersPayant originalData;
  int taux;
  ActiveTiersPayant({required this.originalData, required this.taux});

  String get compteTp => originalData.compteTp;
  String get tpFullName => originalData.tpFullName;
  String get numSecurity => originalData.numSecurity;
}

/// Résultat de la validation : [dejaCloturee] = le serveur indique une vente déjà clôturée.
typedef AssuranceClotureOk = ({bool dejaCloturee});

/// Reprise d'une prévente : ce qui n'a pas pu être retrouvé (vide = tout retrouvé).
typedef AssuranceResume = ({List<String> missing});

class AssuranceController extends ChangeNotifier {
  final VenteGateway gateway;

  /// Vendeur (comme l'original : identifiant de l'utilisateur connecté, '' si inconnu).
  final String userId;

  AssuranceController({required this.gateway, this.userId = ''});

  static const String natureVenteId = '1';
  static const String typeVenteId = '2';

  SaleOpQueue _queue = SaleOpQueue();
  int _working = 0;
  bool _disposed = false;
  int _epoch = 0;

  AssuranceStep _step = AssuranceStep.clientSearch;
  ClientAssurance? _client;
  List<AyantDroit> _ayantDroits = const [];
  AyantDroit? _ayantDroit;
  String? _ayantDroitsError;
  List<ActiveTiersPayant> _activeTps = [];
  Map<String, String> _bons = {};

  String? _venteId;
  String _reference = '';
  List<SaleItemDetail> _items = const [];
  AssuranceSaleSummary? _summary;
  String? _cartError;
  String? _netError;
  int _changes = 0;
  int _netAt = -1;
  bool _finished = false;
  List<PaymentMethodQr> _qr = const [];
  String? _couvertureMessage;

  AssuranceStep get step => _step;
  ClientAssurance? get client => _client;
  List<AyantDroit> get ayantDroits => _ayantDroits;
  AyantDroit? get ayantDroit => _ayantDroit;
  String? get ayantDroitsError => _ayantDroitsError;
  List<ActiveTiersPayant> get activeTiersPayants => List.unmodifiable(_activeTps);
  Map<String, String> get bonNumbers => Map.unmodifiable(_bons);
  String? get venteId => _venteId;
  String get reference => _reference;
  List<SaleItemDetail> get items => _items;
  AssuranceSaleSummary? get summary => _summary;
  String? get cartError => _cartError;
  String? get netError => _netError;
  bool get busy => _working > 0;

  /// Message du serveur à afficher à l'étape des bons (ex. bon déjà utilisé).
  String? get couvertureMessage => _couvertureMessage;
  bool get finished => _finished;
  bool get hasCart => _venteId != null && _items.isNotEmpty;
  int get changes => _changes;

  /// Net calculé APRÈS la dernière modification (panier, TP, taux, bons).
  bool get netUpToDate => _venteId != null && _summary != null && _netAt == _changes && _netError == null;

  /// Pourquoi la vente ne peut pas être terminée (null = possible).
  String? get finishBlockedReason {
    if (_client == null || _ayantDroit == null) return 'Client ou ayant droit manquant.';
    if (_activeTps.isEmpty) return 'Aucun tiers payant actif.';
    if (_venteId == null || _items.isEmpty) return 'Le panier est vide.';
    if (busy) return 'Calcul en cours, patientez…';
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

  /// Nouvelle vente (une vente commencée reste sur le serveur, en prévente).
  void reset() {
    _epoch++;
    _queue = SaleOpQueue();
    _step = AssuranceStep.clientSearch;
    _client = null;
    _ayantDroits = const [];
    _ayantDroit = null;
    _ayantDroitsError = null;
    _activeTps = [];
    _bons = {};
    _venteId = null;
    _reference = '';
    _items = const [];
    _summary = null;
    _cartError = null;
    _netError = null;
    _changes = 0;
    _netAt = -1;
    _finished = false;
    _couvertureMessage = null;
    _notify();
  }

  void _changed() {
    _changes++;
    _notify();
  }

  List<VenteTp> get _tpPayload =>
      [for (final tp in _activeTps) (compteTp: tp.compteTp, numBon: VenteInput.cleanBon(_bons[tp.compteTp]), taux: tp.taux)];

  /// Relit le panier et recalcule le net (bouton « Réessayer »).
  Future<void> reload() => _run(_reload);

  Future<void> _reload() async {
    final id = _venteId;
    if (id == null) return;
    final at = _changes;
    final results = await Future.wait([gateway.saleDetails(id), gateway.netAssurance(venteId: id, tierspayants: _tpPayload)]);
    final details = results[0] as VenteResult<List<SaleItemDetail>>;
    final net = results[1] as VenteResult<AssuranceSaleSummary>;
    if (id != _venteId) return;
    if (details case VenteOk(:final value)) {
      _items = value;
      _cartError = null;
      final ref = value.where((i) => i.strREF.isNotEmpty).firstOrNull?.strREF;
      if (ref != null) _reference = ref;
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

  /// Net recalculé automatiquement (décision n°4) après un changement des TP / taux / bons.
  Future<void> _autoNet() async {
    if (_venteId == null) return;
    await _run(_reload);
    await _remember();
  }

  Future<void> _remember() async {
    final id = _venteId;
    if (id == null || _finished) return;
    if (_items.isEmpty && _cartError == null) {
      await PendingSaleStore.clear(VenteMenu.assurance);
      return;
    }
    await PendingSaleStore.save(
      VenteMenu.assurance,
      PendingSale(
        venteId: id,
        reference: _reference,
        itemCount: _items.length,
        total: _summary?.montantNet ?? 0,
        savedAt: DateTime.now(),
        extra: {'client': _client?.fullName ?? ''},
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Étape 1 : client
  // ---------------------------------------------------------------------------

  /// Recherche client (≥ 2 caractères, comme avant). Une panne reste une panne (jamais « introuvable »).
  /// Le texte suit le réglage « Commence par » / « Contient ».
  Future<VenteResult<List<ClientAssurance>>> searchClients(String query) {
    final q = serverQuery(query, modeFor(query));
    if (q.isEmpty) return Future.value(const VenteOk([]));
    return gateway.searchClients(q, typeClientId: '1');
  }

  Future<VenteResult<List<TiersPayantAssurance>>> searchTiersPayants(String query) {
    final q = serverQuery(query, modeFor(query));
    if (q.isEmpty) return Future.value(const VenteOk([]));
    return gateway.searchTiersPayants(q, carnet: false);
  }

  /// Client choisi : tous ses TP actifs, bons vides, ayant droit = le client s'il figure dans la liste.
  Future<void> selectClient(ClientAssurance client) async {
    _client = client;
    _activeTps = [for (final tp in client.tiersPayants) ActiveTiersPayant(originalData: tp, taux: tp.taux)];
    _bons = {for (final tp in _activeTps) tp.compteTp: ''};
    _ayantDroits = client.ayantDroits;
    _ayantDroit = client.ayantDroits.where((ad) => ad.lgAYANTSDROITSID == client.lgCLIENTID).firstOrNull ??
        client.ayantDroits.firstOrNull;
    _ayantDroitsError = null;
    _step = AssuranceStep.bonAndAyantDroit;
    _changed();
    if (_ayantDroits.isEmpty) await loadAyantDroits();
  }

  /// Création du client : Nom → strFIRSTNAME, Prénom(s) → strLASTNAME (sens de la fiche Prestige).
  Future<VenteResult<ClientAssurance>> createClient({
    required String nom,
    required String prenom,
    required String matricule,
    required TiersPayantAssurance tiersPayant,
    required int taux,
  }) async {
    final n = VenteInput.cleanName(nom), p = VenteInput.cleanName(prenom), m = VenteInput.cleanName(matricule);
    if (n.isEmpty || m.isEmpty) return const VenteRefused('Nom et matricule obligatoires.');
    if (taux < 1 || taux > 100) return const VenteRefused('Taux invalide (1 à 100).');
    final r = await _run(() => gateway.createClientAssurance(
          firstName: n,
          lastName: p,
          numSecu: m,
          tiersPayantId: tiersPayant.lgTIERSPAYANTID,
          pourcentage: taux,
        ));
    if (r case VenteOk(:final value)) await selectClient(value);
    if (r.uncertain) {
      return VenteFailed('${r.message ?? ''} Le client a peut-être été créé : recherchez-le avant de recommencer.'.trim());
    }
    return r;
  }

  // ---------------------------------------------------------------------------
  // Étape 2 : ayant droit, tiers payants, bons
  // ---------------------------------------------------------------------------

  Future<void> loadAyantDroits() => _run(() async {
        final c = _client;
        if (c == null) return;
        final r = await gateway.ayantDroits(c.lgCLIENTID);
        if (_client != c) return;
        if (r case VenteOk(:final value)) {
          _ayantDroits = value;
          _ayantDroitsError = null;
          final current = _ayantDroit;
          if (current == null || !value.contains(current)) {
            _ayantDroit = value.where((ad) => ad.lgAYANTSDROITSID == c.lgCLIENTID).firstOrNull ?? value.firstOrNull;
          }
        } else {
          _ayantDroitsError = r.message ?? 'Ayants droit non chargés.';
        }
        _notify();
      });

  void selectAyantDroit(AyantDroit? ad) {
    if (ad == null || ad == _ayantDroit) return;
    _ayantDroit = ad;
    _notify();
  }

  /// Création d'un ayant droit : Nom → strFIRSTNAME, Prénom(s) → strLASTNAME (même sens que le client ;
  /// l'ancienne version inversait les deux, défaut n°12).
  Future<VenteResult<AyantDroit>> createAyantDroit({required String nom, required String prenom, required String matricule}) async {
    final c = _client;
    if (c == null) return const VenteRefused('Aucun client sélectionné.');
    final n = VenteInput.cleanName(nom), p = VenteInput.cleanName(prenom), m = VenteInput.cleanName(matricule);
    if (n.isEmpty || m.isEmpty) return const VenteRefused('Nom et matricule obligatoires.');
    final r = await _run(() => gateway.createAyantDroit(clientId: c.lgCLIENTID, firstName: n, lastName: p, numSecu: m));
    if (r case VenteOk(:final value)) {
      await loadAyantDroits();
      _ayantDroit = _ayantDroits.where((ad) => ad.lgAYANTSDROITSID == value.lgAYANTSDROITSID).firstOrNull ?? value;
      if (!_ayantDroits.contains(_ayantDroit)) _ayantDroits = [..._ayantDroits, value];
      _notify();
    }
    if (r.uncertain) {
      await loadAyantDroits();
      return VenteFailed('${r.message ?? ''} L\'ayant droit a peut-être été créé : vérifiez la liste avant de recommencer.'.trim());
    }
    return r;
  }

  bool isActive(String compteTp) => _activeTps.any((t) => t.compteTp == compteTp);

  void toggleTiersPayant(ClientTiersPayant tp, bool active) {
    if (active) {
      if (isActive(tp.compteTp)) return;
      _activeTps.add(ActiveTiersPayant(originalData: tp, taux: tp.taux));
      _bons[tp.compteTp] = '';
    } else {
      if (_activeTps.length <= 1) return; // au moins un TP actif
      _activeTps.removeWhere((t) => t.compteTp == tp.compteTp);
      _bons.remove(tp.compteTp);
    }
    _changed();
    unawaited(_autoNet());
  }

  /// Taux de couverture pour cette vente (0 à 100).
  VenteResult<void> updateTaux(String compteTp, int taux) {
    if (taux < 0 || taux > 100) return const VenteRefused('Taux invalide (0 à 100).');
    final tp = _activeTps.where((t) => t.compteTp == compteTp).firstOrNull;
    if (tp == null || tp.taux == taux) return const VenteOk(null);
    tp.taux = taux;
    _changed();
    unawaited(_autoNet());
    return const VenteOk(null);
  }

  /// Bons saisis : obligatoires, nettoyés, sans doublon. Renvoie le message d'erreur (null si valides).
  String? checkBons(Map<String, String> bons) {
    if (_activeTps.isEmpty) return 'Veuillez activer au moins un tiers payant pour cette vente.';
    for (final tp in _activeTps) {
      if (VenteInput.cleanBon(bons[tp.compteTp]).isEmpty) return 'Le N° de bon pour ${tp.tpFullName} est requis.';
    }
    final used = {for (final tp in _activeTps) tp.compteTp: bons[tp.compteTp] ?? ''};
    if (VenteInput.hasDuplicateBons(used)) return 'Le même N° de bon est saisi pour deux tiers payants.';
    return null;
  }

  /// Fin de l'étape 2 : ayant droit obligatoire (défaut n°11), bons valides ; net recalculé si le panier existe.
  String? validateCouverture(Map<String, String> bons) {
    if (_client == null) return 'Aucun client sélectionné.';
    if (_ayantDroit == null) {
      return _ayantDroitsError != null
          ? 'Ayants droit non chargés : touchez « Réessayer ».'
          : 'Choisissez ou créez un ayant droit (patient) avant de continuer.';
    }
    final err = checkBons(bons);
    if (err != null) return err;
    var changed = false;
    for (final tp in _activeTps) {
      final b = VenteInput.cleanBon(bons[tp.compteTp]);
      if (_bons[tp.compteTp] != b) {
        _bons[tp.compteTp] = b;
        changed = true;
      }
    }
    _step = AssuranceStep.productSearch;
    _couvertureMessage = null;
    if (changed) _changes++;
    _notify();
    if (changed || (_venteId != null && !netUpToDate)) unawaited(_autoNet());
    return null;
  }

  void returnToCouverture() {
    _step = AssuranceStep.bonAndAyantDroit;
    _notify();
  }

  /// Ajoute un tiers payant à la fiche du client (serveur), comme avant.
  Future<VenteResult<ClientAssurance>> addTiersPayantToClient(TiersPayantAssurance tp, {required String matricule, required int taux}) async {
    final c = _client;
    if (c == null) return const VenteRefused('Aucun client sélectionné.');
    if (c.tiersPayants.any((t) => t.lgTIERSPAYANTID == tp.lgTIERSPAYANTID)) {
      return VenteRefused('${tp.strNAME.isEmpty ? tp.strFULLNAME : tp.strNAME} est déjà associé à ce client.');
    }
    if (taux < 1 || taux > 100) return const VenteRefused('Taux invalide (1 à 100).');
    final m = VenteInput.cleanName(matricule);
    if (m.isEmpty) return const VenteRefused('Matricule obligatoire.');
    final payload = {
      "bIsAbsolute": false,
      "compteTp": "",
      "dbPLAFONDENCOURS": 0,
      "lgTIERSPAYANTID": tp.lgTIERSPAYANTID,
      "numSecurity": m,
      "order": c.tiersPayants.length + 1,
      "taux": taux,
      "tpFullName": tp.strFULLNAME,
    };
    final r = await _run(() => gateway.addTiersPayantToClient(client: c, newTiersPayantPayload: payload));
    if (r case VenteOk(:final value)) {
      _applyUpdatedClient(value, keepActive: {for (final t in _activeTps) t.originalData.lgTIERSPAYANTID}, activate: tp.lgTIERSPAYANTID);
    }
    if (r.uncertain) {
      return VenteFailed('${r.message ?? ''} Le tiers payant a peut-être été ajouté : resélectionnez le client pour vérifier.'.trim());
    }
    return r;
  }

  /// « Changer l'assurance » (décision n°5 : fonctionnement actuel conservé) : met à jour la fiche client
  /// sur le serveur — le nouveau TP passe en 1er, les anciens suivent.
  Future<VenteResult<ClientAssurance>> replaceTiersPayant(ActiveTiersPayant activeTp, TiersPayantAssurance newTp, int taux) async {
    final c = _client;
    if (c == null) return const VenteRefused('Aucun client sélectionné.');
    if (taux < 0 || taux > 100) return const VenteRefused('Taux invalide (0 à 100).');
    final payload = <Map<String, dynamic>>[
      {
        "bIsAbsolute": false,
        "compteTp": "",
        "dbPLAFONDENCOURS": 0,
        "lgTIERSPAYANTID": newTp.lgTIERSPAYANTID,
        "numSecurity": activeTp.numSecurity,
        "order": 1,
        "taux": taux,
        "tpFullName": newTp.strFULLNAME,
      },
    ];
    var order = 2;
    for (final tp in c.tiersPayants) {
      payload.add({
        "bIsAbsolute": false,
        "compteTp": tp.compteTp,
        "dbPLAFONDENCOURS": 0,
        "lgTIERSPAYANTID": tp.lgTIERSPAYANTID,
        "numSecurity": tp.numSecurity,
        "order": order++,
        "taux": tp.taux,
        "tpFullName": tp.tpFullName,
      });
    }
    final r = await _run(() => gateway.updateClientAssurance(client: c, tiersPayantsPayload: payload));
    if (r case VenteOk(:final value)) {
      final keep = {for (final t in _activeTps) if (t.compteTp != activeTp.compteTp) t.originalData.lgTIERSPAYANTID};
      _applyUpdatedClient(value, keepActive: keep, activateFirst: newTp.lgTIERSPAYANTID);
    }
    if (r.uncertain) {
      return VenteFailed('${r.message ?? ''} La fiche client a peut-être été modifiée : resélectionnez le client pour vérifier.'.trim());
    }
    return r;
  }

  /// Fiche client mise à jour : TP actifs conservés (bons déjà saisis gardés), net recalculé.
  void _applyUpdatedClient(ClientAssurance updated, {required Set<String> keepActive, String? activate, String? activateFirst}) {
    final oldBons = {for (final t in _activeTps) t.originalData.lgTIERSPAYANTID: _bons[t.compteTp] ?? ''};
    final oldTaux = {for (final t in _activeTps) t.originalData.lgTIERSPAYANTID: t.taux};
    _client = ClientAssurance(
      lgCLIENTID: updated.lgCLIENTID,
      fullName: updated.fullName,
      strFIRSTNAME: updated.strFIRSTNAME,
      strLASTNAME: updated.strLASTNAME,
      strNUMEROSECURITESOCIAL: updated.strNUMEROSECURITESOCIAL,
      tiersPayants: updated.tiersPayants,
      ayantDroits: updated.ayantDroits.isNotEmpty ? updated.ayantDroits : _ayantDroits,
    );
    _activeTps = [];
    _bons = {};
    for (final tp in updated.tiersPayants) {
      final id = tp.lgTIERSPAYANTID;
      final isNewFirst = activateFirst != null && tp.order == 1 && id == activateFirst;
      if (isNewFirst || id == activate || keepActive.contains(id)) {
        final keep = keepActive.contains(id) && !isNewFirst;
        _activeTps.add(ActiveTiersPayant(originalData: tp, taux: keep ? (oldTaux[id] ?? tp.taux) : tp.taux));
        _bons[tp.compteTp] = keep ? (oldBons[id] ?? '') : '';
      }
    }
    _changed();
    unawaited(_autoNet());
  }

  // ---------------------------------------------------------------------------
  // Étape 3 : panier
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

  Future<VenteResult<List<ProductSearchResult>>> searchProducts(String query) async {
    final r = await gateway.searchProducts(query);
    if (r is! VenteOk<List<ProductSearchResult>>) return r;
    var hideRv = true;
    try {
      hideRv = (await SharedPreferences.getInstance()).getBool('hide_rv_products') ?? true;
    } catch (_) {}
    if (!hideRv) return r;
    return VenteOk(r.value.where((p) => !p.strNAME.toUpperCase().startsWith('RV ')).toList());
  }

  int _qtyOf(String produitId) => _items.where((i) => i.lgFAMILLEID == produitId).fold(0, (s, i) => s + i.intQUANTITY);

  /// Ajoute [qty] unités. Le 1ᵉʳ ajout crée la vente ; les ajouts suivants attendent son identifiant.
  Future<VenteResult<void>> addProduct(ProductSearchResult p, int qty) => _run(() async {
        if (_finished) return const VenteRefused('Vente déjà terminée : commencez une nouvelle vente.');
        final c = _client, ad = _ayantDroit;
        if (c == null || ad == null) return const VenteRefused('Aucun client ou ayant droit sélectionné.');
        if (_activeTps.isEmpty) return const VenteRefused('Aucun tiers payant actif.');
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
          tierspayants: _tpPayload,
          venteId: id,
        );
        if (epoch != _epoch) return const VenteRefused('Vente abandonnée : produit non ajouté au nouveau panier.');
        if (r case VenteOk(:final value)) {
          _venteId = value;
          _changed();
          await _reload();
          await _remember();
          return const VenteOk(null);
        }
        if (r.uncertain && id != null) {
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
                  'vérifiez l\'historique du client avant de recommencer.'
              .trim());
        }
        return r.map((_) {});
      });

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

  Future<String?> _statut(String id) async {
    final r = await gateway.fullSale(id);
    return r is VenteOk<Map<String, dynamic>> ? VenteController.statutOf(r.value) : null;
  }

  /// Vente déjà clôturée sur le serveur ; null si inconnu.
  Future<bool?> isClosedOnServer(String id) async {
    final s = await _statut(id);
    return s == null ? null : s == 'is_Closed';
  }

  /// « Prévente » : la vente passe dans la liste des préventes à encaisser.
  Future<VenteResult<void>> terminerPrevente({required int expectedChanges}) => _run(() async {
        final id = _venteId;
        if (id == null || _items.isEmpty) return const VenteRefused('Le panier est vide.');
        if (_finished) return const VenteOk(null);
        if (expectedChanges != _changes) return const VenteRefused('La vente a changé : vérifiez le net puis recommencez.');
        if (_cartError != null || !netUpToDate) return const VenteRefused('Net à payer non à jour : touchez « Réessayer ».');
        final r = await gateway.terminerPrevente(id);
        if (r.isOk) return _finish();
        if (r.uncertain) {
          final s = await _statut(id);
          if (s == 'is_Process' || s == 'is_Closed') return _finish();
          return VenteFailed('${r.message ?? ''} Enregistrement non confirmé : vérifiez l\'historique du client puis réessayez.'.trim());
        }
        return r;
      });

  /// Validation (clôture) avec le net calculé après la dernière modification. [method] null = part client 0
  /// (même règle qu'avant : ESPECES).
  Future<VenteResult<AssuranceClotureOk>> cloturer({
    PaymentMethod? method,
    required int expectedChanges,
    int? montantRecu,
    int? montantRemis,
  }) =>
      _cloturer(
        expectedChanges: expectedChanges,
        close: (id, c, ad, s) => gateway.cloturerAssurance(
          venteId: id,
          clientId: c.lgCLIENTID,
          ayantDroitId: ad.lgAYANTSDROITSID,
          natureVenteId: natureVenteId,
          typeVenteId: typeVenteId,
          userVendeurId: userId,
          summary: s,
          typeReglementId: (method ?? PaymentMethod(id: '1', name: 'ESPECES')).id,
          tierspayants: _tpPayload,
          montantRecu: montantRecu,
          montantRemis: montantRemis,
        ),
      );

  /// Part client en plusieurs modes (2 maximum) : une seule clôture avec la liste des règlements ;
  /// la somme doit être exactement la part client.
  Future<VenteResult<AssuranceClotureOk>> cloturerReglements({
    required List<ReglementLigne> lignes,
    required int expectedChanges,
    required int montantRecu,
    required int montantRemis,
  }) {
    final reglements = reglementsDe(lignes);
    final net = _summary?.montantNet;
    final invalid = net == null ? null : reglementsInvalides(reglements, net);
    if (invalid != null) return Future.value(VenteRefused(invalid));
    return _cloturer(
      expectedChanges: expectedChanges,
      close: (id, c, ad, s) => gateway.cloturerAssuranceReglements(
        venteId: id,
        clientId: c.lgCLIENTID,
        ayantDroitId: ad.lgAYANTSDROITSID,
        natureVenteId: natureVenteId,
        typeVenteId: typeVenteId,
        userVendeurId: userId,
        summary: s,
        reglements: reglements,
        tierspayants: _tpPayload,
        montantRecu: montantRecu,
        montantRemis: montantRemis,
      ),
    );
  }

  /// Clôture (un ou plusieurs modes) ; réponse perdue → relecture de la vente.
  Future<VenteResult<AssuranceClotureOk>> _cloturer({
    required int expectedChanges,
    required Future<VenteResult<Map<String, dynamic>>> Function(String id, ClientAssurance c, AyantDroit ad, AssuranceSaleSummary s) close,
  }) =>
      _run(() async {
        final id = _venteId, c = _client, ad = _ayantDroit, s = _summary;
        if (id == null || _items.isEmpty) return const VenteRefused('Le panier est vide.');
        if (_finished) return const VenteOk((dejaCloturee: true));
        if (c == null || ad == null) return const VenteRefused('Données de vente incomplètes.');
        if (expectedChanges != _changes) return const VenteRefused('La vente a changé : vérifiez le net puis validez à nouveau.');
        if (s == null || _cartError != null || !netUpToDate) return const VenteRefused('Net à payer non à jour : touchez « Réessayer » puis validez.');
        final r = await close(id, c, ad, s);
        if (r.isOk) {
          await _finish();
          return const VenteOk((dejaCloturee: false));
        }
        if (r is VenteRefused<Map<String, dynamic>> && r.dejaCloturee) {
          await _finish();
          return const VenteOk((dejaCloturee: true));
        }
        if (r is VenteRefused<Map<String, dynamic>> && r.message.contains('est déjà utilisé')) {
          // Bon déjà utilisé : retour à l'étape des bons, comme avant.
          _step = AssuranceStep.bonAndAyantDroit;
          _couvertureMessage = r.message;
          _netError = null;
          _changed();
          return r.map((_) => (dejaCloturee: false));
        }
        if (r.uncertain) {
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
    await PendingSaleStore.clear(VenteMenu.assurance);
    _notify();
    return const VenteOk(null);
  }

  // ---------------------------------------------------------------------------
  // Modes de paiement
  // ---------------------------------------------------------------------------

  Future<VenteResult<List<PaymentMethod>>> paymentMethods() => gateway.paymentMethods();

  Future<void> loadQrMethods() async {
    if (_qr.isNotEmpty) return;
    final r = await gateway.paymentMethodsWithQr();
    if (r case VenteOk(:final value)) _qr = value;
  }

  PaymentMethodQr? qrFor(String methodId) => _qr.where((m) => m.id == methodId).firstOrNull;

  // ---------------------------------------------------------------------------
  // Historique : reprise d'une prévente (décision n°7) et réimpression
  // ---------------------------------------------------------------------------

  /// Historique des ventes assurance (50 dernières, type '2').
  Future<VenteResult<List<PreventeListItem>>> history() => gateway.ventesByType(typeVenteId);

  /// Recharge une prévente : client, ayant droit, TP/bons, panier, net. Renvoie ce qui manque.
  Future<VenteResult<AssuranceResume>> resumeSale(String venteId) async {
    final full = await gateway.fullSale(venteId);
    if (full is! VenteOk<Map<String, dynamic>>) return full.map((_) => (missing: const <String>[]));
    final data = full.value;
    if (VenteController.statutOf(data) == 'is_Closed') {
      return const VenteRefused('Cette vente est déjà clôturée : elle ne peut pas être reprise (réimpression seulement).');
    }
    final parsed = AssuranceSaleData.parse(data, venteId: venteId);
    final client = parsed.client;
    if (client == null) return const VenteRefused('Client introuvable dans cette vente : reprise impossible.');

    reset();
    final missing = <String>[];
    _client = client;
    _venteId = venteId;
    _reference = parsed.reference;
    _ayantDroits = client.ayantDroits;
    // TP de la vente (compte, bon, taux) rapprochés de la fiche client.
    for (final tp in parsed.tiersPayants) {
      final info = client.tiersPayants.where((c) => c.compteTp == tp.compteTp).firstOrNull ??
          ClientTiersPayant(lgTIERSPAYANTID: '', tpFullName: tp.compteTp, taux: tp.taux, numSecurity: '', compteTp: tp.compteTp, order: 0, principal: false);
      _activeTps.add(ActiveTiersPayant(originalData: info, taux: tp.taux));
      _bons[tp.compteTp] = VenteInput.cleanBon(tp.numBon);
    }
    if (_activeTps.isEmpty) missing.add('tiers payants et bons');
    if (_activeTps.any((t) => (_bons[t.compteTp] ?? '').isEmpty)) missing.add('n° de bon');
    _changes = 1;
    _step = AssuranceStep.bonAndAyantDroit;
    _notify();
    await _run(_reload);
    if (_ayantDroits.isEmpty) await loadAyantDroits();
    // Ayant droit de la vente (jamais remplacé en silence par un autre).
    var ad = parsed.ayantDroit;
    final wantedId = parsed.ayantDroitId;
    if (ad == null && wantedId != null) ad = _ayantDroits.where((a) => a.lgAYANTSDROITSID == wantedId).firstOrNull;
    if (ad != null && !_ayantDroits.contains(ad)) _ayantDroits = [..._ayantDroits, ad];
    _ayantDroit = ad;
    if (ad == null) missing.insert(0, 'ayant droit');
    _step = missing.isEmpty ? AssuranceStep.productSearch : AssuranceStep.bonAndAyantDroit;
    await _remember();
    _notify();
    return VenteOk((missing: missing));
  }

  /// Données complètes d'une vente pour la réimpression (vraie référence, panier).
  Future<VenteResult<({AssuranceSaleData data, List<SaleItemDetail> items})>> loadForPrint(PreventeListItem item) async {
    final full = await gateway.fullSale(item.lgPREENREGISTREMENTID);
    if (full is! VenteOk<Map<String, dynamic>>) return full.map((_) => throw StateError('inutilisé'));
    final data = AssuranceSaleData.parse(full.value, venteId: item.lgPREENREGISTREMENTID, fallbackRef: item.strREF);
    final details = await gateway.saleDetails(item.lgPREENREGISTREMENTID);
    // Panier illisible : impression possible quand même (ticket de prévente sans articles), référence du serveur.
    final items = details.valueOrNull ?? const <SaleItemDetail>[];
    return VenteOk((data: data, items: items));
  }
}

/// Lecture de /ventestats/{id} pour une vente assurance (formats souples : nombres en texte acceptés).
class AssuranceSaleData {
  final ClientAssurance? client;
  final AyantDroit? ayantDroit;
  final String? ayantDroitId;
  final List<TiersPayantSummary> tiersPayants;
  final String reference;
  final String venteId;
  final int total;

  const AssuranceSaleData({
    required this.client,
    required this.ayantDroit,
    required this.ayantDroitId,
    required this.tiersPayants,
    required this.reference,
    required this.venteId,
    required this.total,
  });

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim()) ?? 0;
  static String _str(Object? v) => v == null ? '' : '$v';
  static bool _bool(Object? v) => v == true || '$v'.toLowerCase() == 'true';

  static AssuranceSaleData parse(Map<String, dynamic> data, {required String venteId, String fallbackRef = ''}) {
    ClientAssurance? client;
    final c = data['client'];
    if (c is Map && _str(c['lgCLIENTID']).isNotEmpty) {
      final tps = <ClientTiersPayant>[
        if (c['tiersPayants'] is List)
          for (final tp in c['tiersPayants'] as List)
            if (tp is Map)
              ClientTiersPayant(
                lgTIERSPAYANTID: _str(tp['lgTIERSPAYANTID']),
                tpFullName: _str(tp['tpFullName']),
                taux: _int(tp['taux']),
                numSecurity: _str(tp['numSecurity'] ?? tp['strNUMEROSECURITESOCIAL']),
                compteTp: _str(tp['compteTp']),
                order: _int(tp['order']),
                principal: _bool(tp['principal']),
              ),
      ];
      final ads = <AyantDroit>[
        if (c['ayantDroits'] is List)
          for (final a in c['ayantDroits'] as List)
            if (a is Map) _ad(Map<String, dynamic>.from(a)),
      ];
      final first = _str(c['strFIRSTNAME']), last = _str(c['strLASTNAME']);
      client = ClientAssurance(
        lgCLIENTID: _str(c['lgCLIENTID']),
        fullName: _str(c['fullName']).isNotEmpty ? _str(c['fullName']) : '$first $last'.trim(),
        strFIRSTNAME: first,
        strLASTNAME: last,
        strNUMEROSECURITESOCIAL: _str(c['strNUMEROSECURITESOCIAL']),
        tiersPayants: tps,
        ayantDroits: ads,
      );
    }
    final a = data['ayantDroit'];
    final ad = a is Map && _str(a['lgAYANTSDROITSID']).isNotEmpty ? _ad(Map<String, dynamic>.from(a)) : null;
    final adId = ad?.lgAYANTSDROITSID ?? (_str(data['ayantDroitId']).isNotEmpty ? _str(data['ayantDroitId']) : null);
    final tps = <TiersPayantSummary>[
      if (data['tierspayants'] is List)
        for (final tp in data['tierspayants'] as List)
          if (tp is Map && _str(tp['compteTp']).isNotEmpty)
            TiersPayantSummary(numBon: _str(tp['numBon']), taux: _int(tp['taux']), compteTp: _str(tp['compteTp']), tpnet: _int(tp['tpnet'])),
    ];
    final ref = _str(data['strREF']);
    return AssuranceSaleData(
      client: client,
      ayantDroit: ad,
      ayantDroitId: adId,
      tiersPayants: tps,
      reference: ref.isNotEmpty ? ref : fallbackRef,
      venteId: _str(data['lgPREENREGISTREMENTID']).isNotEmpty ? _str(data['lgPREENREGISTREMENTID']) : venteId,
      total: _int(data['intPRICE']),
    );
  }

  static AyantDroit _ad(Map<String, dynamic> a) {
    final first = _str(a['strFIRSTNAME']), last = _str(a['strLASTNAME']);
    return AyantDroit(
      lgAYANTSDROITSID: _str(a['lgAYANTSDROITSID']),
      lgCLIENTID: _str(a['lgCLIENTID']),
      fullName: _str(a['fullName']).isNotEmpty ? _str(a['fullName']) : '$first $last'.trim(),
      strFIRSTNAME: first,
      strLASTNAME: last,
      strNUMEROSECURITESOCIAL: _str(a['strNUMEROSECURITESOCIAL']),
      strSEXE: _str(a['strSEXE']),
    );
  }

  /// Résumé pour le ticket de réimpression (même calcul que l'ancienne réimpression).
  AssuranceSaleSummary get summary {
    final tp = tiersPayants.fold<int>(0, (s, t) => s + t.tpnet);
    return AssuranceSaleSummary(montant: total, montantTp: tp, montantNet: total - tp, reference: reference, venteId: venteId, tierspayants: tiersPayants);
  }

  /// Ayant droit du ticket : celui de la vente, sinon le client lui-même (comme l'ancienne réimpression).
  AyantDroit? get ticketAyantDroit {
    final c = client;
    if (ayantDroit != null) return ayantDroit;
    if (c == null) return null;
    return AyantDroit(
      lgAYANTSDROITSID: c.lgCLIENTID,
      lgCLIENTID: c.lgCLIENTID,
      fullName: c.fullName,
      strFIRSTNAME: c.strFIRSTNAME,
      strLASTNAME: c.strLASTNAME,
      strNUMEROSECURITESOCIAL: c.strNUMEROSECURITESOCIAL,
      strSEXE: '',
    );
  }
}
