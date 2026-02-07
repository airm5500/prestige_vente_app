// lib/api/models/assurance_sale_summary.dart
class TiersPayantSummary {
  final String numBon;
  final int taux;
  final String compteTp;
  final int tpnet;

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
  final int montant;
  final int remise;
  final int montantNet;
  final int montantTp;
  final int marge;
  final List<TiersPayantSummary> tierspayants;

  // AJOUTS POUR L'IMPRESSION
  final String reference;
  final String venteId;

  AssuranceSaleSummary({
    this.montant = 0,
    this.remise = 0,
    this.montantNet = 0,
    this.montantTp = 0,
    this.marge = 0,
    this.tierspayants = const [],
    this.reference = '',
    this.venteId = '',
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
      // Ces champs ne viennent pas forcément du calcul NET, on les met par défaut
      reference: '',
      venteId: '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'montant': montant,
      'remise': remise,
      'montantNet': montantNet,
      'montantTp': montantTp,
      'marge': marge,
      'tierspayants': tierspayants.map((tp) => tp.toJson()).toList(),
      'reference': reference,
      'venteId': venteId,
    };
  }
}