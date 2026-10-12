// lib/api/models/article_analysis_model.dart

class ArticleAnalysis {
  final String produitId;
  final String codeCip;
  final String libelle;
  final String emplacement;
  final String grossiste;
  final double moyenne;
  final int prixAchat;
  final int prixVente;
  final int quantiteVendue; // Total vendue
  final int stock; // Ajouté pour correspondre à la maquette (valeur par défaut 0 si absent du JSON)
  final String quantiteMoisBrut; // La chaine "1:2,1:6..."

  ArticleAnalysis({
    required this.produitId,
    required this.codeCip,
    required this.libelle,
    required this.emplacement,
    required this.grossiste,
    required this.moyenne,
    required this.prixAchat,
    required this.prixVente,
    required this.quantiteVendue,
    required this.stock,
    required this.quantiteMoisBrut,
  });

  factory ArticleAnalysis.fromJson(Map<String, dynamic> json) {
    // Valeurs lues sans échec : texte (ou nombre rendu en texte), nombre (ou texte numérique).
    String str(dynamic v) => v == null ? '' : '$v';
    num? n(dynamic v) => v is num ? v : (v is String ? num.tryParse(v.trim()) : null);
    return ArticleAnalysis(
      produitId: str(json['produitId']),
      codeCip: str(json['codeCip']),
      libelle: str(json['libelle']),
      emplacement: str(json['emplacement']),
      grossiste: str(json['grossiste']),
      moyenne: n(json['moyenne'])?.toDouble() ?? 0.0,
      prixAchat: n(json['prixAchat'])?.toInt() ?? 0,
      prixVente: n(json['prixVente'])?.toInt() ?? 0,
      quantiteVendue: n(json['quantiteVendue'])?.toInt() ?? 0,
      // Si l'API renvoie "stock" ou "intNUMBERAVAILABLE"
      stock: n(json['stock'] ?? json['intNUMBERAVAILABLE'])?.toInt() ?? 0,
      quantiteMoisBrut: str(json['quantiteMois']),
    );
  }

  // Helper pour convertir "1:2,1:6" en liste de points pour le graphique
  // Format attendu : "Qte:Mois"
  List<SalesPoint> getChartData() {
    if (quantiteMoisBrut.isEmpty) return [];

    List<SalesPoint> points = [];
    final parts = quantiteMoisBrut.split(',');

    for (var part in parts) {
      final subParts = part.split(':');
      if (subParts.length == 2) {
        final qte = double.tryParse(subParts[0]) ?? 0;
        final mois = int.tryParse(subParts[1]) ?? 0;
        if (mois > 0) {
          points.add(SalesPoint(mois, qte));
        }
      }
    }
    // On trie par mois pour avoir une courbe chronologique
    points.sort((a, b) => a.month.compareTo(b.month));
    return points;
  }
}

class SalesPoint {
  final int month;
  final double qty;
  SalesPoint(this.month, this.qty);
}