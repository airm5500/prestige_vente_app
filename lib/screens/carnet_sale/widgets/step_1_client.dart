// lib/screens/carnet_sale/widgets/step_1_client.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/carnet_sale_provider.dart';
//import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/prevente_list_dialog.dart'; // NOUVEL IMPORT
import 'package:provider/provider.dart';
import 'create_client_carnet_dialog.dart';

class Step1ClientWidget extends StatefulWidget {
  const Step1ClientWidget({super.key});

  @override
  State<Step1ClientWidget> createState() => _Step1ClientWidgetState();
}

class _Step1ClientWidgetState extends State<Step1ClientWidget> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final query = _searchController.text.trim();
      if (query.isNotEmpty) {
        Provider.of<CarnetSaleProvider>(context, listen: false)
            .searchClient(query);
      } else {
        Provider.of<CarnetSaleProvider>(context, listen: false)
            .clearClientSearch();
      }
    });
  }

  void _showCreateClientDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const CreateClientCarnetDialog(),
    );
  }

  // --- NOUVELLE MÉTHODE : POPUP LISTE CARNET ---
  void _showPreventeList() {
    showDialog(
      context: context,
      builder: (ctx) => const PreventeListDialog(
        typeVenteId: "3", // 3 = CARNET
        title: "Préventes Carnet",
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CarnetSaleProvider>(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              // CHAMP DE RECHERCHE EXISTANT
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    labelText: 'Rechercher Client Carnet',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        provider.clearClientSearch();
                        FocusScope.of(context).requestFocus(_searchFocusNode);
                      },
                    )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // --- NOUVEAU BOUTON : HISTORIQUE PRÉVENTES CARNET (BLEU) ---
              InkWell(
                onTap: _showPreventeList,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: const Icon(Icons.history, color: Colors.blue, size: 28),
                ),
              ),
            ],
          ),
        ),

        // LISTE DES RÉSULTATS (Code existant conservé)
        Expanded(
          child: Stack(
            children: [
              if (provider.isLoading)
                const Center(child: CircularProgressIndicator()),
              ListView.separated(
                itemCount: provider.clientSearchResults.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final client = provider.clientSearchResults[index];
                  return Card(
                    margin:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(client.strFIRSTNAME.isNotEmpty
                            ? client.strFIRSTNAME[0]
                            : '?'),
                      ),
                      title: Text(
                          '${client.strFIRSTNAME} ${client.strLASTNAME}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Matricule: ${client.strNUMEROSECURITESOCIAL}'),
                          ...client.tiersPayants.map((tp) => Text(
                            '${tp.tpFullName} (${tp.taux}%)',
                            style:
                            const TextStyle(fontStyle: FontStyle.italic),
                          )),
                        ],
                      ),
                      onTap: () {
                        provider.selectClient(client);
                        _searchController.clear();
                      },
                    ),
                  );
                },
              ),
              if (!provider.isLoading &&
                  _searchController.text.isNotEmpty &&
                  provider.clientSearchResults.isEmpty)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Ce client est introuvable.'),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Créer un nouveau client carnet'),
                        onPressed: _showCreateClientDialog,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}