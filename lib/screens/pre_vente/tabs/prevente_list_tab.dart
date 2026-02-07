// lib/screens/pre_vente/tabs/prevente_list_tab.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/sale.dart'; // Contient PreventeListItem et SaleSummary
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';

// IMPORTS POUR L'IMPRESSION
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';

class PreventeListTab extends StatefulWidget {
  // CORRECTION : Suppression du paramètre tabController inutile ici
  const PreventeListTab({super.key});

  @override
  State<PreventeListTab> createState() => _PreventeListTabState();
}

class _PreventeListTabState extends State<PreventeListTab> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  // Instance du service d'impression
  final ReceiptService _receiptService = ReceiptService();

  @override
  void initState() {
    super.initState();
    // CORRECTION : Suppression de la pagination (loadMore) non gérée par le provider actuel
    // _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SaleProvider>(context, listen: false).fetchPreventes();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // CORRECTION : Changement du type Sale -> PreventeListItem
  Future<void> _reprintTicket(PreventeListItem sale) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    if (authProvider.officine == null || authProvider.user == null) {
      Constants.showSnackBar(context, "Données officine/utilisateur manquantes", isError: true);
      return;
    }

    // CORRECTION : Création d'un SaleSummary compatible avec votre modèle actuel
    // On ne met que les champs existants dans lib/api/models/sale.dart
    final saleSummary = SaleSummary(
      montant: sale.intPRICE,
      montantNet: sale.intPRICE,
      // montantTp, montantRemise, date, tierspayants SUPPRIMÉS car inexistants dans votre modèle SaleSummary
      reference: sale.strREF,
      venteId: sale.lgPREENREGISTREMENTID,
    );

    await _receiptService.printPreventeTicket(
      context: context,
      officine: authProvider.officine!,
      saleSummary: saleSummary,
      currentUser: authProvider.user!,
      isTestMode: settings.isTestPrintMode,
      paperWidth: settings.paperWidth,
      ticketCodeType: settings.ticketCodeType,
    );
  }

  @override
  Widget build(BuildContext context) {
    final saleProvider = Provider.of<SaleProvider>(context);

    // CORRECTION : Filtrage local car fetchPreventes(query:) n'existe pas
    final allPreventes = saleProvider.preventes;
    final searchQuery = _searchController.text.toLowerCase();
    final filteredPreventes = searchQuery.isEmpty
        ? allPreventes
        : allPreventes.where((p) => p.strREF.toLowerCase().contains(searchQuery)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Rechercher (Réf)',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  setState(() {}); // Rafraîchissement local
                },
              ),
            ),
            onChanged: (val) => setState(() {}), // Filtrage en temps réel
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => await saleProvider.fetchPreventes(),
            child: saleProvider.isLoadingPreventes
                ? const Center(child: CircularProgressIndicator())
                : filteredPreventes.isEmpty
                ? const Center(child: Text("Aucune prévente trouvée"))
                : ListView.builder(
              controller: _scrollController,
              itemCount: filteredPreventes.length,
              itemBuilder: (context, index) {
                final sale = filteredPreventes[index];

                // Gestion sécurisée de la date
                DateTime? dateUpdate;
                try {
                  // Format probable: yyyy-MM-dd
                  dateUpdate = DateTime.parse(sale.dtUPDATED);
                } catch (e) {
                  dateUpdate = DateTime.now();
                }

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.orange,
                      child: Icon(Icons.shopping_bag, color: Colors.white),
                    ),
                    title: Text(sale.strREF, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      // CORRECTION : Utilisation de userFullName et formatage date sécurisé
                      "${DateFormat('dd/MM/yyyy').format(dateUpdate)} ${sale.heure}\n${sale.userFullName}",
                      style: const TextStyle(fontSize: 12),
                    ),

                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "${Constants.formatNumber(sale.intPRICE)} F",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.print, color: Colors.grey),
                          tooltip: "Réimprimer le ticket",
                          onPressed: () => _reprintTicket(sale),
                        ),
                      ],
                    ),

                    onTap: () {
                      // CORRECTION : Utilisation de loadPrevente (méthode existante)
                      saleProvider.loadPrevente(sale.lgPREENREGISTREMENTID);
                      // Basculer vers l'onglet Vente (Index 1)
                      DefaultTabController.of(context).animateTo(1);
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}