// lib/screens/auth/qr_code_preview_screen.dart
// 30/10/2025 01:30
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart'; // MODIFICATION
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class QrCodePreviewScreen extends StatelessWidget {
  const QrCodePreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // On récupère la liste complète
    final allPaymentMethods = Provider.of<SaleProvider>(context, listen: false).paymentMethodsWithQr;

    // MODIFICATION (Point 1) : On récupère les IDs activés dans les settings
    final enabledIds = Provider.of<SettingsProvider>(context).enabledPaymentMethodIds;

    // MODIFICATION : On filtre la liste basée sur les IDs activés
    final filteredMethods = allPaymentMethods
        .where((method) => enabledIds.contains(method.id))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Aperçu des QR Codes"),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(8.0),
        // On utilise la liste filtrée
        itemCount: filteredMethods.length,
        itemBuilder: (context, index) {
          final method = filteredMethods[index];

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Text(
                    method.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  if (method.qrCode != null && method.qrCode!.isNotEmpty)
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: Image.memory(
                        method.qrCode!,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Text(
                              "Erreur: Données QR invalides",
                              style: TextStyle(color: AppColors.error),
                            ),
                          );
                        },
                      ),
                    )
                  else
                    Container(
                      height: 200,
                      width: 200,
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: Text("Pas de QR Code"),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}