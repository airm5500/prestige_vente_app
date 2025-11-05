// lib/screens/assurance_sale/widgets/step_1_client.dart
// 02/11/2025 15:35
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:provider/provider.dart';
import 'create_client_dialog.dart'; // Le dialogue que nous créons à l'étape 3

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
      Provider.of<AssuranceSaleProvider>(context, listen: false)
          .searchClient(_searchController.text);
    });
  }

  void _showCreateClientDialog() {
    showDialog(
      context: context,
      // Utilise le dialogue que nous allons créer
      builder: (ctx) => const CreateClientDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AssuranceSaleProvider>(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              labelText: 'Rechercher Client (Nom ou Matricule)',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  provider.clearClientSearch();
                },
              )
                  : null,
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              // Affiche les résultats de la recherche
              ListView.builder(
                itemCount: provider.clientSearchResults.length,
                itemBuilder: (context, index) {
                  final client = provider.clientSearchResults[index];
                  // Affiche les infos du client et de ses tiers payants
                  return Card(
                    margin:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      title: Text(client.fullName,
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
                        // Sélectionne le client et passe à l'étape suivante
                        provider.selectClient(client);
                      },
                    ),
                  );
                },
              ),

              // Si la recherche ne donne rien, affiche le bouton "Créer"
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
                        label: const Text('Créer un nouveau client'),
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