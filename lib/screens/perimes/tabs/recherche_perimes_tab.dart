// lib/screens/perimes/tabs/recherche_perimes_tab.dart
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/perime_models.dart';
import 'package:prestige_vente_app/providers/perime_provider.dart';
import 'package:prestige_vente_app/services/pdf_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class RecherchePerimesTab extends StatefulWidget {
  const RecherchePerimesTab({super.key});

  @override
  State<RecherchePerimesTab> createState() => _RecherchePerimesTabState();
}

class _RecherchePerimesTabState extends State<RecherchePerimesTab> {
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PerimeProvider>(context, listen: false).loadProduitsPerimes();
    });
  }

  Future<void> _handlePrint() async {
    final provider = Provider.of<PerimeProvider>(context, listen: false);
    if (provider.produitsPerimesList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Aucune donnée à imprimer")));
      return;
    }

    setState(() => _isPrinting = true);

    try {
      // 1. Déterminer le texte du filtre
      final int nbreMois = provider.nbreMoisFilter;
      final String filterText = nbreMois == 0
          ? "Produits déjà périmés"
          : "Périmés dans les $nbreMois mois";

      // 2. Récupérer les totaux (avec sécurité null)
      final int totalAchat = provider.metaData?.totalValeurAchat ?? 0;
      final int totalVente = provider.metaData?.totalValeurVente ?? 0;

      // 3. Appel de la méthode mise à jour
      await PdfService().generateAndPrintPerimesReport(
        provider.produitsPerimesList,
        filterText,
        totalAchat: totalAchat,
        totalVente: totalVente,
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur impression: $e")));
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  void _showDetailDialog(ProduitPerime produit) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(produit.libelle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('CIP:', produit.codeCip),
              _buildDetailRow('N° Lot:', produit.numLot),
              _buildDetailRow('Date Péremption:', produit.datePerement),
              _buildDetailRow('Statut:', produit.statut),
              const Divider(),
              _buildDetailRow('Quantité:', produit.quantiteLot.toString()),
              _buildDetailRow('Valeur Vente:', Constants.formatNumber(produit.valeurVente)),
              _buildDetailRow('Valeur Achat:', Constants.formatNumber(produit.valeurAchat)),
              const Divider(),
              _buildDetailRow('Rayon:', produit.libelleRayon),
              _buildDetailRow('Famille:', produit.libelleFamille),
              _buildDetailRow('Grossiste:', produit.libelleGrossiste),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Fermer'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PerimeProvider>(
      builder: (context, provider, child) {
        final meta = provider.metaData;

        if (provider.isLoading) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Chargement des produits périmés..."),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Barre d'outils
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  const Text('Périmés dans :', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: provider.nbreMoisFilter,
                    items: [0, 1, 2, 3, 6, 12]
                        .map((mois) => DropdownMenuItem(
                      value: mois,
                      child: Text(mois == 0 ? 'Déjà périmés' : '$mois mois'),
                    ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        provider.setNbreMois(value);
                      }
                    },
                  ),
                  const Spacer(),
                  _isPrinting
                      ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2)
                  )
                      : ElevatedButton.icon(
                    onPressed: _handlePrint,
                    icon: const Icon(Icons.print, size: 18),
                    label: const Text("Imprimer"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),

            // Résumé
            if (meta != null && provider.produitsPerimesList.isNotEmpty)
              Card(
                color: Colors.blue.shade50,
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMetaStat('Qté Totale', meta.totalQuantiteLot),
                      _buildMetaStat('Val. Achat', meta.totalValeurAchat),
                      _buildMetaStat('Val. Vente', meta.totalValeurVente),
                    ],
                  ),
                ),
              ),

            // Liste
            Expanded(
              child: provider.produitsPerimesList.isEmpty
                  ? const Center(child: Text("Aucun produit trouvé."))
                  : RefreshIndicator(
                onRefresh: () => provider.loadProduitsPerimes(),
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: provider.produitsPerimesList.length,
                  itemBuilder: (context, index) {
                    final produit = provider.produitsPerimesList[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: produit.statut.contains('Périmé il y a') ? Colors.red.shade50 : null,
                      child: ListTile(
                        title: Text(produit.libelle, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          'CIP: ${produit.codeCip} | Lot: ${produit.numLot}\nDate: ${produit.datePerement} (Qté: ${produit.quantiteLot})',
                        ),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              produit.statut,
                              style: TextStyle(
                                color: produit.statut.contains('Périmé il y a') ? AppColors.error : Colors.orange.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        onTap: () => _showDetailDialog(produit),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetaStat(String label, int value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        Text(
          Constants.formatNumber(value),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }
}