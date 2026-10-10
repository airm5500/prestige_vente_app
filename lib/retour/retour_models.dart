// lib/retour/retour_models.dart
// Retour fournisseur depuis le mobile : motifs, lignes du retour en préparation.
String _str(dynamic v) => v == null ? '' : '$v';
int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

class MotifRetour {
  final String id;
  final String code;
  final String label;
  const MotifRetour({required this.id, this.code = '', required this.label});

  factory MotifRetour.fromJson(Map<String, dynamic> j) => MotifRetour(
        id: _str(j['lgMOTIFRETOUR']),
        code: _str(j['strCODE']),
        label: _str(j['strLIBELLE']).isEmpty ? _str(j['lgMOTIFRETOUR']) : _str(j['strLIBELLE']),
      );
}

/// Ligne d'un retour (un produit par ligne : Prestige cumule les quantités d'un même produit).
class RetourLine {
  final String id;
  final String produitId;
  final String name;
  final String cip;
  final String motif;
  final int quantity;

  const RetourLine({
    required this.id,
    required this.produitId,
    required this.name,
    this.cip = '',
    this.motif = '',
    required this.quantity,
  });

  factory RetourLine.fromJson(Map<String, dynamic> j) => RetourLine(
        id: _str(j['lgRETOURFRSDETAIL']),
        produitId: _str(j['produitId']),
        name: _str(j['strNAME']),
        cip: _str(j['intCIP']),
        motif: _str(j['motif']),
        quantity: _int(j['intNUMBERRETURN']),
      );
}

class RetourCreated {
  final String id;
  final String ref;
  const RetourCreated(this.id, this.ref);
}
