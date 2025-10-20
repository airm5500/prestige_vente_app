// lib/screens/auth/qr_code_preview_screen.dart
// 20/10/2025 02:40
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';

class QrCodePreviewScreen extends StatelessWidget {
  const QrCodePreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // On récupère la liste complète
    final allPaymentMethods = Provider.of<SaleProvider>(context, listen: false).paymentMethodsWithQr;

    // MODIFICATION : On définit les noms autorisés
    const allowedNames = {'ORANGE', 'WAVE', 'MTN', 'MOOV', 'Carte Bancaire'};

    // MODIFICATION : On filtre la liste
    final filteredMethods = allPaymentMethods
        .where((method) => allowedNames.contains(method.name))
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