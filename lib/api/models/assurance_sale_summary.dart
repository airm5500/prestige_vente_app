// lib/api/models/assurance_sale_summary.dart
// 10/11/2025 10:00 (Correction: Ajout toJson)

// Modèle pour POST /vente/net/assurance
class TiersPayantSummary {
  final String numBon;
  final int taux;
  final String compteTp;
  final int tpnet; // Part du tiers payant

  TiersPayantSummary({
    required this.numBon,
    required this.taux,
    required this.compteTp,
    required this.tpnet,
  });

  factory TiersPayantSummary.fromJson(Map<String, dynamic> json) {
    return TiersPayantSummary(
      numBon: json['numBon'] ?? '',
      taux: json['taux'] ?? 0,
      compteTp: json['compteTp'] ?? '',
      tpnet: json['tpnet'] ?? 0,
    );
  }

  // MODIFICATION : Ajout de la méthode toJson
  Map<String, dynamic> toJson() {
    return {
      'numBon': numBon,
      'taux': taux,
      'compteTp': compteTp,
      'tpnet': tpnet,
    };
  }
}

class AssuranceSaleSummary {
  final int montant; // Montant total brut
  final int remise;
  final int montantNet; // Part Client
  final int montantTp; // Part totale Tiers Payants
  final int marge;
  final List<TiersPayantSummary> tierspayants;

  AssuranceSaleSummary({
    this.montant = 0,
    this.remise = 0,
    this.montantNet = 0,
    this.montantTp = 0,
    this.marge = 0,
    this.tierspayants = const [],
  });

  factory AssuranceSaleSummary.fromNetResponse(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};

    var tpList = <TiersPayantSummary>[];
    if (data['tierspayants'] is List) {
      tpList = (data['tierspayants'] as List)
          .map((tp) => TiersPayantSummary.fromJson(tp))
          .toList();
    }

    return AssuranceSaleSummary(
      montant: data['montant'] ?? 0,
      remise: data['remise'] ?? 0,
      montantNet: data['montantNet'] ?? 0,
      montantTp: data['montantTp'] ?? 0,
      marge: data['marge'] ?? 0,
      tierspayants: tpList,
    );
  }

  // MODIFICATION : Ajout de la méthode toJson
  Map<String, dynamic> toJson() {
    return {
      'montant': montant,
      'remise': remise,
      'montantNet': montantNet,
      'montantTp': montantTp,
      'marge': marge,
      'tierspayants': tierspayants.map((tp) => tp.toJson()).toList(),
    };
  }
}