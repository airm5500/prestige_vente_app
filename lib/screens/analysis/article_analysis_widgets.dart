// lib/screens/analysis/article_analysis_widgets.dart
// Éléments de l'analyse article partagés par la fenêtre « Détails de l'Article » (menu Analyse article)
// et la fiche produit de l'accueil (scan, recherche globale) : mêmes libellés, mêmes valeurs,
// même graphique bicolore des ventes mensuelles (année précédente en rouge, année en cours en vert).
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/article_analysis_model.dart';
import 'package:prestige_vente_app/api/models/stock_reserve.dart';

/// Informations de l'analyse article, dans l'ordre de la fenêtre « Détails de l'Article ».
List<(String, String)> articleInfos(ArticleAnalysis a) => [
      ("Prix d'achat", "${a.prixAchat} FCFA"),
      ("Prix de vente", "${a.prixVente} FCFA"),
      ("Grossiste", a.grossiste.isEmpty ? "N/A" : a.grossiste),
      ("Moyenne sur 3 derniers mois", a.moyenne.toStringAsFixed(2)),
      ("Emplacement", a.emplacement.isEmpty ? "N/A" : a.emplacement),
      ("Qté totale vendue 6 derniers mois", "${a.quantiteVendue}"),
    ];

/// Stock rayon / réserve (GET /info, GET /checkproduit) : « Stock rayon », « Stock réserve » (« — » si le produit
/// n'est pas géré en réserve), seuils s'ils sont renseignés (> 0), « Total rayon + réserve » (produit géré en
/// réserve). [avecRayon] faux : la ligne « Stock rayon » est omise (l'écran affiche déjà le stock).
List<(String, String)> stockReserveInfos(int rayon, StockReserve r, {bool avecRayon = true}) => [
      if (avecRayon) ('Stock rayon', '$rayon'),
      ('Stock réserve', r.geree ? '${r.stockReserve}' : '—'),
      if (r.seuilReserveRenseigne != null) ('Seuil réserve', '${r.seuilReserveRenseigne}'),
      if (r.seuilMiniRayonRenseigne != null) ('Seuil mini rayon', '${r.seuilMiniRayonRenseigne}'),
      if (r.geree) ('Total rayon + réserve', '${r.total(rayon)}'),
    ];

/// Pastille orange douce « À réapprovisionner » : rayon ≤ seuil mini rayon ou réserve ≤ seuil réserve
/// (rien sinon). Couleurs fixes (fond clair, texte foncé) : lisible en thème clair comme sombre.
class PastilleReappro extends StatelessWidget {
  final StockReserve reserve;
  final int rayon;
  const PastilleReappro({super.key, required this.reserve, required this.rayon});

  String get raison => [
        if (reserve.rayonBas(rayon)) 'rayon au seuil mini ou en dessous',
        if (reserve.reserveBasse) 'réserve au seuil ou en dessous',
      ].join(' ; ');

  @override
  Widget build(BuildContext context) {
    if (!reserve.aReapprovisionner(rayon)) return const SizedBox.shrink();
    return Tooltip(
      message: 'À réapprovisionner : $raison',
      child: Container(
        key: const ValueKey('pastille-reappro'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEDD5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF59E0B)),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inventory_2_outlined, size: 13, color: Color(0xFF9A3412)),
          SizedBox(width: 4),
          Flexible(
            child: Text('À réapprovisionner',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF9A3412))),
          ),
        ]),
      ),
    );
  }
}

/// Ligne courte des listes : « Réserve : Y · Total : X+Y » + pastille ; rien si le produit n'est pas géré en réserve.
class StockReserveResume extends StatelessWidget {
  final StockReserve reserve;
  final int rayon;
  final Color couleur;
  const StockReserveResume({super.key, required this.reserve, required this.rayon, this.couleur = const Color(0xFF5B6B82)});

  @override
  Widget build(BuildContext context) {
    if (!reserve.geree) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text('Réserve : ${reserve.stockReserve} · Total : ${reserve.total(rayon)}', style: TextStyle(fontSize: 13, color: couleur)),
      PastilleReappro(reserve: reserve, rayon: rayon),
    ]);
  }
}

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
