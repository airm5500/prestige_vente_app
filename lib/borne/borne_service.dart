// lib/borne/borne_service.dart
// Accès serveur de la borne, par le VenteGateway existant (mêmes routes que la Pré-vente) :
// - recherche par pages (ProductPager, « commence par » / « contient » du réglage) ;
// - vérification du panier AVANT la création (prix et stock relus sur le serveur, écarts listés) ;
// - création d'une PRÉVENTE comptant : 1ᵉʳ article avec X-Client-Ref si le serveur le gère (H4),
//   articles suivants, net, « terminer la prévente » — une seule opération à la fois (SaleOpQueue).
// Aucune prévente hors ligne à la borne (B1) : serveur injoignable = borne indisponible.
import 'dart:math';

import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/borne/borne_panier.dart';
import 'package:prestige_vente_app/borne/borne_produit.dart';
import 'package:prestige_vente_app/horsligne/client_ref.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/sale_op_queue.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

/// Écart constaté entre le panier de la borne et le serveur.
class BorneEcart {
  final String nom;
  final int? ancienPrix;
  final int? nouveauPrix;
  final int ancienneQte;
  final int nouvelleQte;
  const BorneEcart({required this.nom, this.ancienPrix, this.nouveauPrix, required this.ancienneQte, required this.nouvelleQte});

  bool get retire => nouvelleQte == 0;
  bool get prixChange => ancienPrix != null && nouveauPrix != null && ancienPrix != nouveauPrix;

  String get texte {
    if (retire) return '$nom : plus disponible, retiré du panier.';
    final parts = <String>[];
    if (prixChange) parts.add('prix ${_f(ancienPrix!)} F → ${_f(nouveauPrix!)} F');
    if (nouvelleQte != ancienneQte) parts.add('quantité ramenée à $nouvelleQte (stock)');
    return '$nom : ${parts.join(', ')}.';
  }

  static String _f(int v) => Constants.formatNumber(v);
}

/// Résultat de la vérification : lignes à jour + écarts (vide = rien n'a changé).
class BorneVerification {
  final List<BorneLigne> lignes;
  final List<BorneEcart> ecarts;
  const BorneVerification(this.lignes, this.ecarts);
  int get total => lignes.fold(0, (s, l) => s + l.total);
}

/// Prévente créée par la borne.
class BornePrevente {
  final String venteId;
  final String reference;
  final int total;
  final List<SaleItemDetail> lignes;
  final DateTime at;
  const BornePrevente({required this.venteId, required this.reference, required this.total, required this.lignes, required this.at});

  /// Numéro affiché en GRAND : la fin de la référence (ex. « 0042 » de « 20261011000042 »), sinon la référence.
  String get numero {
    final r = reference.trim();
    final d = RegExp(r'(\d+)$').firstMatch(r)?.group(1);
    if (d == null) return r.isEmpty ? venteId : r;
    return d.length > 4 ? d.substring(d.length - 4) : d;
  }
}

class BorneService {
  final VenteGateway gateway;

  /// Clé client de la prévente (H4) ; remplaçable dans les tests.
  final String Function() nouvelleCle;
  final SaleOpQueue _queue = SaleOpQueue();

  BorneService(this.gateway, {String Function()? nouvelleCle}) : nouvelleCle = nouvelleCle ?? _cle;

  static final Random _rnd = Random.secure();
  static String _cle() {
    final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final r = List.generate(10, (_) => _rnd.nextInt(36).toRadixString(36)).join();
    return 'BORNE-$t-$r';
  }

  bool get occupe => _queue.busy;

  // ---------------------------------------------------------------------------
  // Recherche
  // ---------------------------------------------------------------------------

  /// Texte de recherche nettoyé et borné ; null s'il est trop court (rien n'est envoyé sous 3 caractères).
  static String? texteRecherche(String? brut) {
    final t = VenteInput.cleanQuery(brut).replaceAll(RegExp(r'[%_]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length < VenteInput.minQueryLength ? null : t;
  }

  /// Liste paginée (mode « commence par » / « contient » du réglage de l'appareil).
  ProductPager pager(String texte, {SearchMode? mode}) =>
      ProductPager(gateway.searchProductsPage, texte, mode: modeFor(texte, mode));

  /// Produit exact par code (scan) ; null si introuvable.
  Future<VenteResult<ProductSearchResult?>> parCode(String code) async {
    final r = await ProductLookup.byCode(code, gateway.searchProductsPage);
    return r.map((c) => c.exact);
  }

  // ---------------------------------------------------------------------------
  // Vérification
  // ---------------------------------------------------------------------------

  /// Relit chaque produit sur le serveur (prix et stock du moment).
  Future<VenteResult<BorneVerification>> verifier(List<BorneLigne> lignes) => _queue.run(() async {
        final out = <BorneLigne>[];
        final ecarts = <BorneEcart>[];
        for (final l in lignes) {
          final r = await _relire(l.produit);
          if (r is! VenteOk<ProductSearchResult?>) return r.map((_) => const BorneVerification([], []));
          final p = r.value;
          if (p == null) {
            ecarts.add(BorneEcart(nom: l.produit.nom, ancienneQte: l.qte, nouvelleQte: 0));
            continue;
          }
          final np = BorneProduit(p, image: l.produit.image);
          final qte = np.disponible ? min(l.qte, np.stock) : 0;
          if (qte != l.qte || np.prix != l.produit.prix) {
            ecarts.add(BorneEcart(nom: l.produit.nom, ancienPrix: l.produit.prix, nouveauPrix: np.prix, ancienneQte: l.qte, nouvelleQte: qte));
          }
          if (qte > 0) out.add(BorneLigne(np, qte));
        }
        return VenteOk(BorneVerification(out, ecarts));
      });

  Future<VenteResult<ProductSearchResult?>> _relire(BorneProduit p) async {
    // Par code d'abord (exact), sinon par le nom ; on ne garde que le MÊME produit (même identifiant).
    final requetes = <String>[if (p.code.length >= 3) p.code, p.nom.length > VenteInput.maxQueryLength ? p.nom.substring(0, VenteInput.maxQueryLength) : p.nom];
    VenteResult<ProductPage>? echec;
    for (final q in requetes) {
      final r = await gateway.searchProductsPage(q, 0, ProductLookup.pageSize);
      if (r is! VenteOk<ProductPage>) {
        echec = r;
        continue;
      }
      final m = r.value.items.where((x) => x.lgFAMILLEID == p.id).firstOrNull;
      if (m != null) return VenteOk(m);
    }
    if (echec != null) return echec.map((_) => null);
    return const VenteOk(null);
  }

  // ---------------------------------------------------------------------------
  // Création de la prévente
  // ---------------------------------------------------------------------------

  /// Crée la prévente (lignes déjà vérifiées et acceptées par le client).
  Future<VenteResult<BornePrevente>> creerPrevente(List<BorneLigne> lignes, {String utilisateur = ''}) => _queue.run(() async {
        if (lignes.isEmpty) return const VenteRefused('Le panier est vide.');
        final cle = nouvelleCle();
        var gw = gateway;
        final refGw = gateway is ClientRefGateway ? gateway as ClientRefGateway : null;
        final h4 = refGw != null && await refGw.clientRefSupporte();
        if (h4) gw = refGw.avecClientRef(cle);
        String? venteId;
        for (final l in lignes) {
          final r = await (venteId == null ? gw : gateway)
              .addItemVno(produitId: l.produit.id, qte: l.qte, itemPu: l.produit.prix, venteId: venteId, prevente: true);
          if (r case VenteOk(:final value)) {
            venteId = value;
            continue;
          }
          // 1ʳᵉ ligne sans réponse : la clé client permet de savoir si la prévente a été créée.
          if (venteId == null && r.uncertain && h4) {
            final info = await refGw.lireClientRef(cle);
            if (info case VenteOk(value: final i?) when i.existe) {
              venteId = i.id;
              continue;
            }
          }
          await _abandonner(venteId);
          _journal(lignes, null, ResultatJournal.refus, motif: r.message ?? '', cle: cle, reseau: r is VenteFailed);
          return r.map((_) => throw StateError('inutilisé'));
        }
        final id = venteId!;
        final net = await gateway.netVno(id);
        final fin = await gateway.terminerPrevente(id);
        if (!fin.isOk && !fin.uncertain) {
          await _abandonner(id);
          _journal(lignes, null, ResultatJournal.refus, motif: fin.message ?? '', cle: cle);
          return fin.map((_) => throw StateError('inutilisé'));
        }
        final details = await gateway.saleDetails(id);
        final summary = net.valueOrNull;
        final items = details.valueOrNull ?? const <SaleItemDetail>[];
        var reference = summary?.reference ?? '';
        if (reference.isEmpty) reference = items.where((i) => i.strREF.isNotEmpty).firstOrNull?.strREF ?? '';
        if (reference.isEmpty) {
          final full = await gateway.fullSale(id);
          reference = '${full.valueOrNull?['strREF'] ?? ''}';
        }
        final total = summary?.montantNet ?? lignes.fold<int>(0, (s, l) => s + l.total);
        final p = BornePrevente(
          venteId: id,
          reference: reference.isEmpty ? id : reference,
          total: total,
          lignes: items.isNotEmpty
              ? items
              : [
                  for (final l in lignes)
                    SaleItemDetail(
                        lgPREENREGISTREMENTDETAILID: '',
                        lgFAMILLEID: l.produit.id,
                        strNAME: l.produit.nom,
                        intCIP: l.produit.code,
                        intQUANTITY: l.qte,
                        intPRICEUNITAIR: l.produit.prix,
                        intPRICE: l.total,
                        strREF: reference),
                ],
          at: DateTime.now(),
        );
        _journal(lignes, p, ResultatJournal.ok, cle: cle);
        return VenteOk(p);
      });

  /// Échec en cours de création : les lignes déjà ajoutées sont retirées (la vente vide reste « en cours »
  /// sur le serveur, hors de la liste des préventes à encaisser).
  Future<void> _abandonner(String? venteId) async {
    if (venteId == null) return;
    final d = await gateway.saleDetails(venteId);
    for (final i in d.valueOrNull ?? const <SaleItemDetail>[]) {
      await gateway.removeItem(i.lgPREENREGISTREMENTDETAILID);
    }
  }

  void _journal(List<BorneLigne> lignes, BornePrevente? p, ResultatJournal res, {String motif = '', required String cle, bool reseau = false}) {
    JournalTerminal.instance.noter(
      type: TypeJournal.prevente,
      action: p != null ? 'Prévente borne créée' : 'Prévente borne non créée',
      refLocale: cle,
      refServeur: p?.reference ?? '',
      montant: p?.total ?? lignes.fold<int>(0, (s, l) => s + l.total),
      produits: [for (final l in lignes) JournalProduit(id: l.produit.id, nom: l.produit.nom, qte: l.qte)],
      resultat: reseau ? ResultatJournal.echecReseau : res,
      motif: motif,
    );
  }
}
