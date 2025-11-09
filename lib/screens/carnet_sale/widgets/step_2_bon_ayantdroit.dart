// lib/screens/carnet_sale/widgets/step_2_bon_ayantdroit.dart
// 09/11/2025 19:30 (Correction Ayant Droit)
import 'package:flutter/material.dart';
//import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/providers/carnet_sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';
// import 'create_ayant_droit_dialog.dart'; // Plus nécessaire pour l'UI

class Step2BonAyantDroitWidget extends StatefulWidget {
  const Step2BonAyantDroitWidget({super.key});

  @override
  State<Step2BonAyantDroitWidget> createState() =>
      _Step2BonAyantDroitWidgetState();
}

class _Step2BonAyantDroitWidgetState extends State<Step2BonAyantDroitWidget> {
  final Map<String, TextEditingController> _bonControllers = {};
  final Map<String, FocusNode> _bonFocusNodes = {};
  FocusNode? _firstActiveFocusNode;

  @override
  void initState() {
    super.initState();
    final provider =
    Provider.of<CarnetSaleProvider>(context, listen: false);
    _initializeControllers(provider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if(mounted) {
        provider.clearError();
        if (_firstActiveFocusNode != null) {
          FocusScope.of(context).requestFocus(_firstActiveFocusNode);
        }
      }
    });
  }

  void _initializeControllers(CarnetSaleProvider provider) {
    if (provider.selectedClient == null) return;

    _firstActiveFocusNode = null;

    for (var tp in provider.selectedClient!.tiersPayants) {
      if (!_bonControllers.containsKey(tp.compteTp)) {
        _bonControllers[tp.compteTp] = TextEditingController(
            text: provider.bonNumbers[tp.compteTp] ?? ""
        );
      }
      if (!_bonFocusNodes.containsKey(tp.compteTp)) {
        _bonFocusNodes[tp.compteTp] = FocusNode();
      }
      bool isActive = provider.activeTiersPayants.any((atp) => atp.compteTp == tp.compteTp);
      if (_firstActiveFocusNode == null && isActive) {
        _firstActiveFocusNode = _bonFocusNodes[tp.compteTp];
      }
    }
  }


  @override
  void dispose() {
    _bonControllers.forEach((_, controller) => controller.dispose());
    _bonFocusNodes.forEach((_, node) => node.dispose());
    super.dispose();
  }

  Future<void> _confirmReturnToClientSearch(BuildContext context) async {
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);
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

  // Cette fonction n'est plus appelée par l'UI
  /*
  void _showCreateAyantDroitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const CreateAyantDroitDialog(),
    );
  }
  */

  void _validateAndProceed() {
    final provider = Provider.of<CarnetSaleProvider>(context, listen: false);
    provider.clearError();

    if (provider.activeTiersPayants.isEmpty) {
      Constants.showSnackBar(context, "Erreur: Aucun carnet n'est actif pour ce client.", isError: true);
      return;
    }

    _bonControllers.forEach((compteTp, controller) {
      if (provider.activeTiersPayants.any((atp) => atp.compteTp == compteTp)) {
        provider.updateBonNumber(compteTp, controller.text.trim());
      }
    });

    for (var tp in provider.activeTiersPayants) {
      if (provider.bonNumbers[tp.compteTp]?.isEmpty ?? true) {
        Constants.showSnackBar(context, "Le N° de bon pour ${tp.tpFullName} est requis.", isError: true);
        final focusNode = _bonFocusNodes[tp.compteTp];
        if (focusNode != null) {
          FocusScope.of(context).requestFocus(focusNode);
        }
        return;
      }
    }

    provider.validateBonsAndProceed();
  }


  @override
  Widget build(BuildContext context) {
    return Consumer<CarnetSaleProvider>(
        builder: (context, provider, child) {

          final client = provider.selectedClient;

          if (client == null) {
            return const Center(
                child: Text("Aucun client sélectionné. Veuillez recommencer."));
          }

          _initializeControllers(provider);

          // Le carnet n'a qu'un seul TP, on le grise.
          final bool canToggleTiersPayant = client.tiersPayants.length > 1;

          // MODIFICATION : La logique de sélection de l'ayant droit est automatique
          // AyantDroit? validSelectedAyantDroit = provider.selectedAyantDroit;
          // ...

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

                // MODIFICATION : Section Ayant Droit masquée
                // const SizedBox(height: 16),
                // Text('1. Sélectionner un Ayant Droit (Patient)', ...),
                // const SizedBox(height: 8),
                // Row(...),

                const SizedBox(height: 24),

                Text('Saisir le N° de Bon (Ref.Bon)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),

                ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: client.tiersPayants.length,
                    itemBuilder: (context, index) {
                      final tp = client.tiersPayants[index];

                      final activeTp = provider.activeTiersPayants.firstWhere(
                              (atp) => atp.originalData.compteTp == tp.compteTp,
                          orElse: () => ActiveTiersPayant(originalData: tp, taux: tp.taux)
                      );
                      final bool isActive = provider.activeTiersPayants.indexWhere((atp) => atp.originalData.compteTp == tp.compteTp) != -1;

                      final controller = _bonControllers[tp.compteTp];
                      final focusNode = _bonFocusNodes[tp.compteTp];

                      if (controller == null || focusNode == null) {
                        return Card(
                            color: Colors.red.shade100,
                            child: Text("Erreur d'initialisation: ${tp.tpFullName}")
                        );
                      }

                      return Card(
                        color: isActive ? Colors.white : (canToggleTiersPayant ? Colors.grey[200] : Colors.grey[50]),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          children: [
                            CheckboxListTile(
                              title: Text('${tp.tpFullName} (${isActive ? activeTp.taux : tp.taux}%)', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('Matricule: ${tp.numSecurity}'),
                              value: isActive,
                              onChanged: canToggleTiersPayant
                                  ? (bool? value) {
                                provider.toggleTiersPayant(tp, value ?? false);
                              }
                                  : null,
                              secondary: null,
                            ),
                            if (isActive)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: TextFormField(
                                  focusNode: focusNode,
                                  controller: controller,
                                  decoration: InputDecoration(
                                    labelText: 'N° Bon pour ${tp.tpFullName} *',
                                    border: const OutlineInputBorder(),
                                  ),
                                  textInputAction: TextInputAction.next,
                                  onFieldSubmitted: (_) => _validateAndProceed(),
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