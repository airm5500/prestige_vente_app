// lib/screens/perimes/tabs/recherche_perimes_tab.dart
// 09/11/2025 17:30
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/perime_models.dart';
import 'package:prestige_vente_app/providers/perime_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class RecherchePerimesTab extends StatefulWidget {
  const RecherchePerimesTab({super.key});

  @override
  State<RecherchePerimesTab> createState() => _RecherchePerimesTabState();
}

class _RecherchePerimesTabState extends State<RecherchePerimesTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PerimeProvider>(context, listen: false).loadProduitsPerimes();
    });
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
        return Column(
          children: [
            // Filtre Nbre Mois
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  const Text('Afficher les produits périmés dans :'),
                  const SizedBox(width: 10),
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
                ],
              ),
            ),

            // Résumé (MetaData)
            if (meta != null && provider.produitsPerimesList.isNotEmpty)
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMetaStat('Qté Totale', meta.totalQuantiteLot),
                      _buildMetaStat('Valeur Achat', meta.totalValeurAchat),
                      _buildMetaStat('Valeur Vente', meta.totalValeurVente),
                    ],
                  ),
                ),
              ),

            // Liste
            Expanded(
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                onRefresh: () => provider.loadProduitsPerimes(),
                child: ListView.builder(
                  itemCount: provider.produitsPerimesList.length,
                  itemBuilder: (context, index) {
                    final produit = provider.produitsPerimesList[index];
                    return Card(
                      color: produit.statut.contains('Périmé il y a') ? Colors.red.shade50 : null,
                      child: ListTile(
                        title: Text(produit.libelle, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          'CIP: ${produit.codeCip} | Lot: ${produit.numLot}\nDate: ${produit.datePerement} (Qté: ${produit.quantiteLot})',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          produit.statut,
                          style: TextStyle(
                            color: produit.statut.contains('Périmé il y a') ? AppColors.error : Colors.orange.shade700,
                            fontWeight: FontWeight.bold,
                          ),
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