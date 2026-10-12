// lib/screens/analysis/article_analysis_widgets.dart
// Éléments de l'analyse article partagés par la fenêtre « Détails de l'Article » (menu Analyse article)
// et la fiche produit de l'accueil (scan, recherche globale) : mêmes libellés, mêmes valeurs,
// même graphique bicolore des ventes mensuelles (année précédente en rouge, année en cours en vert).
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/article_analysis_model.dart';

/// Informations de l'analyse article, dans l'ordre de la fenêtre « Détails de l'Article ».
List<(String, String)> articleInfos(ArticleAnalysis a) => [
      ("Prix d'achat", "${a.prixAchat} FCFA"),
      ("Prix de vente", "${a.prixVente} FCFA"),
      ("Grossiste", a.grossiste.isEmpty ? "N/A" : a.grossiste),
      ("Moyenne sur 3 derniers mois", a.moyenne.toStringAsFixed(2)),
      ("Emplacement", a.emplacement.isEmpty ? "N/A" : a.emplacement),
      ("Qté totale vendue 6 derniers mois", "${a.quantiteVendue}"),
    ];

/// Ventes mensuelles triées chronologiquement (mois > mois courant = année précédente) et
/// index du premier mois de l'année en cours (-1 : tout est de l'année précédente).
({List<SalesPoint> points, int split}) ventesChronologiques(ArticleAnalysis article, {int? moisCourant}) {
  final rawData = article.getChartData();
  final currentMonth = moisCourant ?? DateTime.now().month;
  rawData.sort((a, b) {
    // Année 0 si mois > mois actuel (année dernière), Année 1 sinon
    final yearA = (a.month > currentMonth) ? 0 : 1;
    final yearB = (b.month > currentMonth) ? 0 : 1;
    if (yearA != yearB) return yearA.compareTo(yearB);
    return a.month.compareTo(b.month);
  });
  return (points: rawData, split: rawData.indexWhere((p) => p.month <= currentMonth));
}

/// « Évolution des ventes mensuelles » : légende (si deux années) + graphique bicolore.
class ArticleVentesChart extends StatelessWidget {
  final ArticleAnalysis article;
  final double height;

  /// Titre « Évolution des ventes mensuelles: » au-dessus du graphique.
  final bool titre;
  const ArticleVentesChart({super.key, required this.article, this.height = 150, this.titre = true});

  @override
  Widget build(BuildContext context) {
    final v = ventesChronologiques(article);
    final rawData = v.points;
    final splitIndex = v.split;
    final lines = <LineChartBarData>[];
    if (rawData.isNotEmpty) {
      if (splitIndex == -1) {
        // Tout est de l'année dernière -> Tout Rouge
        lines.add(_createLineData(rawData, 0, Colors.red));
      } else if (splitIndex == 0) {
        // Tout est de l'année en cours -> Tout Vert
        lines.add(_createLineData(rawData, 0, Colors.green));
      } else {
        // Données à cheval : rouge jusqu'au dernier mois N-1, vert à partir de ce point (continuité).
        final redSpots = rawData.sublist(0, splitIndex);
        if (redSpots.isNotEmpty) lines.add(_createLineData(redSpots, 0, Colors.red));
        lines.add(_createLineData(rawData.sublist(splitIndex - 1), splitIndex - 1, Colors.green));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      // Légende des couleurs rouge et vert
      if (splitIndex > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 10.0),
          child: Row(children: [
            _legendItem(Colors.red, "Année précédente"),
            const SizedBox(width: 15),
            _legendItem(Colors.green, "Année en cours"),
          ]),
        ),
      if (titre) ...[
        const Text("Évolution des ventes mensuelles:", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
      ],
      SizedBox(
        height: height,
        child: rawData.isEmpty
            ? const Center(child: Text("Pas d'historique de vente", style: TextStyle(color: Colors.grey)))
            : LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: const TextStyle(fontSize: 10)))),
                    bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (val, meta) {
                              final index = val.toInt();
                              if (index >= 0 && index < rawData.length) {
                                // Couleur du mois selon l'année : avant le split => Rouge, sinon Vert
                                var monthColor = Colors.black;
                                if (splitIndex > 0) monthColor = index < splitIndex ? Colors.red : Colors.green;
                                return Text(nomMois(rawData[index].month),
                                    style: TextStyle(fontSize: 10, color: monthColor, fontWeight: FontWeight.bold));
                              }
                              return const Text("");
                            })),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade200)),
                  lineBarsData: lines,
                ),
              ),
      ),
    ]);
  }

  LineChartBarData _createLineData(List<SalesPoint> points, int startIndexOffset, Color color) => LineChartBarData(
        // L'offset place la ligne au bon endroit sur l'axe X global
        spots: points.asMap().entries.map((e) => FlSpot((e.key + startIndexOffset).toDouble(), e.value.qty)).toList(),
        isCurved: true,
        color: color,
        barWidth: 3,
        dotData: const FlDotData(show: true),
        belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.1)),
      );

  Widget _legendItem(Color color, String label) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]);
}

/// « Jan », « Fév »… (vide hors 1..12).
String nomMois(int monthIndex) {
  const months = ["", "Jan", "Fév", "Mar", "Avr", "Mai", "Juin", "Juil", "Août", "Sep", "Oct", "Nov", "Déc"];
  if (monthIndex >= 1 && monthIndex <= 12) return months[monthIndex];
  return "";
}
