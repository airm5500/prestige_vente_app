// lib/screens/caisse/caisse_screen.dart
// 09/11/2025 02:00 (Correction Erreur 'userFullName')
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/caisse_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';
import 'widgets/billetage_dialog.dart';

class CaisseScreen extends StatefulWidget {
  const CaisseScreen({super.key});

  @override
  State<CaisseScreen> createState() => _CaisseScreenState();
}

class _CaisseScreenState extends State<CaisseScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CaisseProvider>(context, listen: false).loadData();
    });
  }

  Future<void> _ouvrirCaisse(CaisseProvider provider) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer l\'ouverture'),
        content: Text('Ouvrir la caisse pour ${provider.ouvertureData?.userFullName ?? '...'} avec un fond de caisse de 0 ?'),
        actions: [
          TextButton(
            child: const Text('Annuler'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ElevatedButton(
            child: const Text('Ouvrir'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await provider.ouvrirCaisse();
      if (mounted && success) {
        Constants.showSnackBar(context, 'Caisse ouverte avec succès.');
      }
    }
  }

  Future<void> _cloturerCaisse(CaisseProvider provider) async {
    // 1. Recharge les dernières données de clôture
    final success = await provider.prepareCloture();

    // 2. Si succès, montre le dialogue de billetage
    if (mounted && success) {
      final clotureData = provider.clotureData;
      if (clotureData != null) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => BilletageDialog(clotureData: clotureData),
        ).then((_) {
          // Après la fermeture du dialogue de billetage, vérifie si l'erreur vient de là
          if (provider.errorMessage != null && provider.errorMessage!.contains("clôture")) {
            Constants.showSnackBar(context, provider.errorMessage!, isError: true);
          } else if (provider.errorMessage == null && !provider.isCaisseOuverte) {
            Constants.showSnackBar(context, 'Caisse clôturée avec succès.');
          }
        });
      }
    } else if (mounted) {
      Constants.showSnackBar(context, provider.errorMessage ?? 'Erreur inconnue', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestion de Caisse')),
      body: RefreshIndicator(
        onRefresh: () =>
            Provider.of<CaisseProvider>(context, listen: false).loadData(),
        child: Consumer<CaisseProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading && provider.ouvertureData == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (provider.ouvertureData == null) {
              return const Center(child: Text("Impossible de charger les données."));
            }

            final bool caisseOuverte = provider.isCaisseOuverte;

            // MODIFICATION : Correction du bug 'Object'
            // On récupère les infos depuis le bon objet en fonction de l'état
            final String userName = (caisseOuverte
                ? provider.clotureData?.userFullName
                : provider.ouvertureData?.userFullName) ?? '...';

            final String dateText = (caisseOuverte
                ? 'Ouverte le ${provider.clotureData?.createAt ?? '...'}'
                : 'Dernière ouverture le ${provider.ouvertureData?.createAt ?? '...'}');
            // FIN MODIFICATION

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    Text(
                      // MODIFICATION : Utilisation de la variable corrigée
                      'Utilisateur: $userName',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Icon(
                      caisseOuverte ? Icons.lock_open : Icons.lock,
                      color: caisseOuverte ? AppColors.success : AppColors.error,
                      size: 80,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      caisseOuverte ? 'CAISSE OUVERTE' : 'CAISSE FERMÉE',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: caisseOuverte ? AppColors.success : AppColors.error,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      // MODIFICATION : Utilisation de la variable corrigée
                      dateText,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const Divider(height: 40),

                    _buildInfoCard(
                      'Fond de Caisse',
                      Constants.formatNumber(caisseOuverte ? (provider.clotureData?.cashFund ?? 0) : (provider.ouvertureData?.amount ?? 0)),
                      Icons.wallet,
                    ),

                    if (caisseOuverte && provider.clotureData != null)
                      _buildInfoCard(
                        'Solde Théorique Actuel',
                        Constants.formatNumber(provider.clotureData!.solde),
                        Icons.calculate,
                      ),

                    const SizedBox(height: 40),

                    SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Ouvrir la Caisse'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                        ),
                        // Actif seulement si la caisse est fermée
                        onPressed: caisseOuverte || provider.isLoading
                            ? null
                            : () => _ouvrirCaisse(provider),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.lock),
                        label: const Text('Clôturer la Caisse'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                        ),
                        // Actif seulement si la caisse est ouverte
                        onPressed: !caisseOuverte || provider.isLoading
                            ? null
                            : () => _cloturerCaisse(provider),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary, size: 30),
        title: Text(title, style: const TextStyle(color: Colors.black54)),
        trailing: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
    );
  }
}