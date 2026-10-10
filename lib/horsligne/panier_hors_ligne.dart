// lib/horsligne/panier_hors_ligne.dart
// Panier d'une vente saisie hors ligne (étape H2) : aucun appel serveur, totaux calculés sur l'appareil.
// Les lignes sont présentées comme celles du serveur (SaleItemDetail) : le panier des écrans de vente
// s'affiche à l'identique. Une vente commencée en ligne garde ses lignes serveur (non modifiables
// hors ligne) : à l'envoi, seuls les articles manquants seront ajoutés.
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

class PanierHorsLigne {
  /// Numéro réservé (HL-0007).
  final int numero;

  /// Vente serveur déjà créée (vente commencée en ligne), sinon null.
  final String? venteId;

  /// Référence serveur de la vente commencée en ligne.
  final String reference;
  final List<LigneHL> _lignes = [];
  int _seq = 0;

  PanierHorsLigne({required this.numero, this.venteId, this.reference = ''});

  /// Vente commencée en ligne : ses lignes (déjà sur le serveur) sont reprises telles quelles.
  factory PanierHorsLigne.depuisServeur({required int numero, required String venteId, String reference = '', required List<SaleItemDetail> items}) {
    final p = PanierHorsLigne(numero: numero, venteId: venteId, reference: reference);
    for (final i in items) {
      p._lignes.add(LigneHL(
        cle: i.lgPREENREGISTREMENTDETAILID,
        produitId: i.lgFAMILLEID,
        nom: i.strNAME,
        cip: i.intCIP,
        qte: i.intQUANTITY,
        prix: i.intPRICEUNITAIR,
        serveur: true,
      ));
    }
    return p;
  }

  String get label => numeroHL(numero);
  List<LigneHL> get lignes => List.unmodifiable(_lignes);
  bool get isEmpty => _lignes.isEmpty;
  int get total => _lignes.fold(0, (s, l) => s + l.total);

  /// Lignes au format du panier serveur (affichage).
  List<SaleItemDetail> get items => [
        for (final l in _lignes)
          SaleItemDetail(
            lgPREENREGISTREMENTDETAILID: l.cle,
            lgFAMILLEID: l.produitId,
            strNAME: l.nom,
            intCIP: l.cip,
            intQUANTITY: l.qte,
            intPRICEUNITAIR: l.prix,
            intPRICE: l.total,
            strREF: label,
          ),
      ];

  /// Ajout local : même produit au même prix → quantité cumulée (ligne locale seulement).
  VenteResult<void> ajouter(ProductSearchResult p, int qty) {
    if (qty < 1 || qty > VenteInput.maxQuantity) return const VenteRefused('Quantité invalide (1 à 9 999).');
    final i = _lignes.indexWhere((l) => !l.serveur && l.produitId == p.lgFAMILLEID && l.prix == p.intPRICE);
    if (i >= 0) {
      final q = _lignes[i].qte + qty;
      if (q > VenteInput.maxQuantity) return const VenteRefused('Quantité invalide (1 à 9 999).');
      _lignes[i] = _lignes[i].copyWith(qte: q);
      return const VenteOk(null);
    }
    _lignes.add(LigneHL(
      cle: 'hl-${++_seq}',
      produitId: p.lgFAMILLEID,
      nom: p.strNAME,
      cip: p.intCIP,
      qte: qty,
      prix: p.intPRICE,
      stockConnu: p.intNUMBERAVAILABLE,
    ));
    return const VenteOk(null);
  }

  static const _ligneServeur = 'Ligne déjà enregistrée sur le serveur : modification possible au retour du serveur.';

  VenteResult<void> modifier(String cle, int qty, int prix) {
    final i = _lignes.indexWhere((l) => l.cle == cle);
    if (i < 0) return const VenteRefused('Ligne introuvable.');
    if (_lignes[i].serveur) return const VenteRefused(_ligneServeur);
    if (qty < 1 || qty > VenteInput.maxQuantity) return const VenteRefused('Quantité invalide (1 à 9 999).');
    if (prix < 0 || prix > VenteInput.maxPrice) return const VenteRefused('Prix invalide.');
    _lignes[i] = _lignes[i].copyWith(qte: qty, prix: prix);
    return const VenteOk(null);
  }

  VenteResult<void> retirer(String cle) {
    final i = _lignes.indexWhere((l) => l.cle == cle);
    if (i < 0) return const VenteOk(null);
    if (_lignes[i].serveur) return const VenteRefused(_ligneServeur);
    _lignes.removeAt(i);
    return const VenteOk(null);
  }
}

/// Répartition estimée sur l'appareil (assurance / carnet) : chaque tiers payant prend son taux
/// du total (arrondi), dans la limite du total ; la part client est le reste.
/// Le net définitif est celui du serveur (plafonds, remises).
AssuranceSaleSummary estimerAssurance(int montant, List<TpHL> tps, {String reference = ''}) {
  var reste = montant;
  final parts = <TiersPayantSummary>[];
  for (final tp in tps) {
    final part = ((montant * tp.taux) / 100).round().clamp(0, reste);
    reste -= part;
    parts.add(TiersPayantSummary(numBon: tp.numBon, taux: tp.taux, compteTp: tp.compteTp, tpnet: part));
  }
  return AssuranceSaleSummary(
    montant: montant,
    montantNet: reste,
    montantTp: montant - reste,
    tierspayants: parts,
    reference: reference,
  );
}
