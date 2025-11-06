// lib/screens/assurance_sale/widgets/step_2_bon_ayantdroit.dart
// 06/11/2025 00:00 (Correction Focus/Curseur)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';
import 'add_tiers_payant_dialog.dart';
import 'create_ayant_droit_dialog.dart';

class Step2BonAyantDroitWidget extends StatefulWidget {
  const Step2BonAyantDroitWidget({super.key});

  @override
  State<Step2BonAyantDroitWidget> createState() =>
      _Step2BonAyantDroitWidgetState();
}

class _Step2BonAyantDroitWidgetState extends State<Step2BonAyantDroitWidget> {
  // MODIFICATION : Les controllers et focus nodes sont initialisés ici
  final Map<String, TextEditingController> _bonControllers = {};
  final Map<String, FocusNode> _bonFocusNodes = {};

  @override
  void initState() {
    super.initState();
    final provider =
    Provider.of<AssuranceSaleProvider>(context, listen: false);

    // MODIFICATION : On crée TOUS les controllers et focus nodes UNE SEULE FOIS.
    if (provider.selectedClient != null) {
      FocusNode? firstActiveFocusNode;

      for (var tp in provider.selectedClient!.tiersPayants) {
        // Crée un controller pour chaque TP
        _bonControllers[tp.compteTp] = TextEditingController(
            text: provider.bonNumbers[tp.compteTp] ?? ""
        );

        // Crée un focus node pour chaque TP
        final focusNode = FocusNode();
        _bonFocusNodes[tp.compteTp] = focusNode;

        // On garde en mémoire le premier focus node qui est ACTIF
        if (firstActiveFocusNode == null &&
            provider.activeTiersPayants.any((atp) => atp.compteTp == tp.compteTp)) {
          firstActiveFocusNode = focusNode;
        }
      }

      // Met le focus sur le premier champ actif
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if(mounted) {
          provider.clearError(); // Efface les anciennes erreurs
          if (firstActiveFocusNode != null) {
            FocusScope.of(context).requestFocus(firstActiveFocusNode);
          }
        }
      });
    }
  }

  // MODIFICATION : Plus besoin de _updateControllers ou didChangeDependencies

  @override
  void dispose() {
    // MODIFICATION : On nettoie tous les controllers et focus nodes
    _bonControllers.forEach((_, controller) => controller.dispose());
    _bonFocusNodes.forEach((_, node) => node.dispose());
    super.dispose();
  }

  Future<void> _confirmReturnToClientSearch(BuildContext context) async {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

    // Vérifie si un bon est saisi OU si le panier n'est pas vide
    bool hasData = provider.cartItems.isNotEmpty || _bonControllers.values.any((c) => c.text.isNotEmpty);

    if (!hasData) {
      provider.returnToClientSearch();
      return;
    }

    final bool? quit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter la vente ?'),
        content: const Text('Toute votre saisie (bons, panier) sera perdue. Voulez-vous continuer ?'),
        actions: [
          TextButton(
            child: const Text('Non'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ElevatedButton(
            child: const Text('Oui, quitter'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (quit == true) {
      provider.returnToClientSearch();
    }
  }

  void _showCreateAyantDroitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const CreateAyantDroitDialog(),
    );
  }

  void _showAddTiersPayantDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const AddTiersPayantDialog(),
    );
  }

  void _showEditTauxDialog(ActiveTiersPayant activeTp) {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    final tauxController = TextEditingController(text: activeTp.taux.toString());

    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Modifier Taux: ${activeTp.tpFullName}'),
          content: TextFormField(
            controller: tauxController,
            decoration: const InputDecoration(labelText: 'Nouveau Taux %'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofocus: true,
          ),
          actions: [
            TextButton(
              child: const Text('Annuler'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            ElevatedButton(
              child: const Text('Valider'),
              onPressed: () {
                final int? newTaux = int.tryParse(tauxController.text);
                if (newTaux != null && newTaux >= 0 && newTaux <= 100) {
                  provider.updateTiersPayantTaux(activeTp.compteTp, newTaux);
                  Navigator.of(ctx).pop();
                } else {
                  // Utilise le context du dialogue
                  Constants.showSnackBar(ctx, "Taux invalide (0-100)", isError: true);
                }
              },
            )
          ],
        )
    );
  }

  void _validateAndProceed() {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    provider.clearError(); // Efface les anciennes erreurs du provider

    if (provider.activeTiersPayants.isEmpty) {
      Constants.showSnackBar(context, "Veuillez activer au moins un tiers payant pour cette vente.", isError: true);
      return;
    }

    // 1. Mettre à jour le provider avec les valeurs des controllers
    _bonControllers.forEach((compteTp, controller) {
      // Met à jour le provider uniquement si le TP est actif
      if (provider.activeTiersPayants.any((atp) => atp.compteTp == compteTp)) {
        provider.updateBonNumber(compteTp, controller.text.trim());
      }
    });

    // 2. Valider les données (qui sont maintenant dans le provider)
    for (var tp in provider.activeTiersPayants) {
      if (provider.bonNumbers[tp.compteTp]?.isEmpty ?? true) {
        Constants.showSnackBar(context, "Le N° de bon pour ${tp.tpFullName} est requis.", isError: true);

        // Met le focus sur le champ vide
        final focusNode = _bonFocusNodes[tp.compteTp];
        if (focusNode != null) {
          FocusScope.of(context).requestFocus(focusNode);
        }
        return; // Arrête la validation
      }
    }

    // 3. Si tout est bon, on continue
    provider.validateBonsAndProceed();
  }


  @override
  Widget build(BuildContext context) {
    // On utilise Consumer pour reconstruire l'interface si nécessaire
    return Consumer<AssuranceSaleProvider>(
        builder: (context, provider, child) {

          final settings = Provider.of<SettingsProvider>(context, listen: false);
          final client = provider.selectedClient;

          if (client == null) {
            return const Center(
                child: Text("Aucun client sélectionné. Veuillez recommencer."));
          }

          final bool canAddTiersPayant = client.tiersPayants.length < settings.maxTiersPayants;

          AyantDroit? validSelectedAyantDroit = provider.selectedAyantDroit;
          if (validSelectedAyantDroit != null && !provider.ayantDroitList.contains(validSelectedAyantDroit)) {
            validSelectedAyantDroit = null;
          }
          if (validSelectedAyantDroit == null && provider.ayantDroitList.isNotEmpty) {
            validSelectedAyantDroit = provider.ayantDroitList.first;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if(mounted) {
                provider.selectAyantDroit(validSelectedAyantDroit);
              }
            });
          }


          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 2,
                  child: ListTile(
                    leading: const Icon(Icons.person, color: AppColors.primary),
                    title: Text(client.fullName,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Matricule: ${client.strNUMEROSECURITESOCIAL}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Changer de client',
                      onPressed: () => _confirmReturnToClientSearch(context),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Text('1. Sélectionner un Ayant Droit (Patient)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<AyantDroit>(
                        value: validSelectedAyantDroit,
                        decoration: const InputDecoration(
                          labelText: 'Ayant Droit',
                          border: OutlineInputBorder(),
                        ),
                        items: provider.ayantDroitList.map((AyantDroit ad) {
                          return DropdownMenuItem<AyantDroit>(
                            value: ad,
                            child: Text(
                                '${ad.fullName} (${ad.strNUMEROSECURITESOCIAL})'),
                          );
                        }).toList(),
                        onChanged: (AyantDroit? newValue) {
                          if (newValue != null) {
                            provider.selectAyantDroit(newValue);
                          }
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: AppColors.secondary),
                      tooltip: 'Créer un nouvel ayant droit',
                      onPressed: _showCreateAyantDroitDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Text('2. Gérer les Tiers Payants et N° de Bon',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),

                ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: client.tiersPayants.length,
                    itemBuilder: (context, index) {
                      final tp = client.tiersPayants[index];

                      // On cherche l'état "actif"
                      final activeTp = provider.activeTiersPayants.firstWhere(
                              (atp) => atp.originalData.compteTp == tp.compteTp,
                          // Si pas trouvé, on crée un "factice" pour lire le taux
                          orElse: () => ActiveTiersPayant(originalData: tp, taux: tp.taux)
                      );
                      final bool isActive = provider.activeTiersPayants.indexWhere((atp) => atp.originalData.compteTp == tp.compteTp) != -1;

                      // MODIFICATION : On récupère le bon controller et focus node
                      final controller = _bonControllers[tp.compteTp];
                      final focusNode = _bonFocusNodes[tp.compteTp];

                      // Si le controller ou le focus node n'existent pas (ne devrait pas arriver)
                      if (controller == null || focusNode == null) {
                        return Card(child: Text("Erreur: ${tp.tpFullName}"));
                      }

                      return Card(
                        color: isActive ? Colors.white : Colors.grey[200],
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          children: [
                            CheckboxListTile(
                              title: Text('${tp.tpFullName} (${isActive ? activeTp.taux : tp.taux}%)', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('Matricule: ${tp.numSecurity}'),
                              value: isActive,
                              onChanged: (bool? value) {
                                // C'est ici que le provider notifie et le widget reconstruit
                                provider.toggleTiersPayant(tp, value ?? false);
                              },
                              secondary: isActive ? IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blueAccent),
                                tooltip: 'Modifier le taux pour cette vente',
                                onPressed: () => _showEditTauxDialog(activeTp),
                              ) : null,
                            ),
                            // On affiche le champ SI le TP est actif
                            if (isActive)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: TextFormField(
                                  // On utilise les instances persistantes
                                  focusNode: focusNode,
                                  controller: controller,
                                  decoration: InputDecoration(
                                    labelText: 'N° Bon pour ${tp.tpFullName}',
                                    border: const OutlineInputBorder(),
                                  ),
                                  textInputAction: TextInputAction.next,
                                  // On met à jour le provider uniquement quand l'utilisateur change de champ
                                  onFieldSubmitted: (_) {
                                    // Trouve le *prochain* focus node actif
                                    final activeNodes = _bonFocusNodes.entries
                                        .where((entry) => provider.activeTiersPayants.any((atp) => atp.compteTp == entry.key))
                                        .map((entry) => entry.value)
                                        .toList();

                                    final currentIndex = activeNodes.indexOf(focusNode);
                                    if (currentIndex != -1 && currentIndex < activeNodes.length - 1) {
                                      FocusScope.of(context).requestFocus(activeNodes[currentIndex + 1]);
                                    } else {
                                      // Si c'est le dernier, on valide
                                      _validateAndProceed();
                                    }
                                  },
                                  // On met aussi à jour en perdant le focus
                                  onTapOutside: (_) {
                                    provider.updateBonNumber(tp.compteTp, controller.text.trim());
                                  },
                                ),
                              ),
                          ],
                        ),
                      );
                    }
                ),

                TextButton.icon(
                  icon: const Icon(Icons.add_card),
                  label: const Text('Ajouter un Tiers Payant au client'),
                  onPressed: canAddTiersPayant ? _showAddTiersPayantDialog : null,
                ),
                if (!canAddTiersPayant)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      'Nombre maximum de tiers payants (${settings.maxTiersPayants}) atteint.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),

                const SizedBox(height: 24),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () {
                    _validateAndProceed();
                  },
                  child: const Text('Continuer vers la saisie des produits'),
                ),
              ],
            ),
          );
        });
  }
}