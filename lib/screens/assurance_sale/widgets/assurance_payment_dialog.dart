// lib/screens/assurance_sale/widgets/assurance_payment_dialog.dart
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/assurance_sale_provider.dart';
//import 'package:prestige_vente_app/utils/constants.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/widgets/cash_payment_dialog.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';

class AssurancePaymentDialog extends StatefulWidget {
  const AssurancePaymentDialog({super.key});

  @override
  State<AssurancePaymentDialog> createState() => _AssurancePaymentDialogState();
}

class _AssurancePaymentDialogState extends State<AssurancePaymentDialog> {
  late Future<List<PaymentMethod>> _paymentMethodsFuture;

  @override
  void initState() {
    super.initState();
    _paymentMethodsFuture = _loadAndFilterMethods();
  }

  Future<List<PaymentMethod>> _loadAndFilterMethods() async {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final allMethods = await provider.getFilteredPaymentMethods();
    final allowedIds = settings.enabledPaymentMethodIds;
    return allMethods.where((m) => allowedIds.contains(m.id)).toList();
  }

  // MODIFICATION CRITIQUE : Plus d'appel API ici. Juste de la saisie.
  Future<void> _handleCashPayment(PaymentMethod method) async {
    final provider = Provider.of<AssuranceSaleProvider>(context, listen: false);

    // 1. Saisie des montants
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) => CashPaymentDialog(
        montantNet: provider.saleSummary!.montantNet,
      ),
    );

    // 2. Si validé, on renvoie les infos au parent (Footer) qui gèrera l'API
    if (result != null) {
      Navigator.of(context).pop({
        'method': method,
        'verse': result['verse'],
        'monnaie': result['monnaie']
      });
    }
  }

  // MODIFICATION CRITIQUE : Plus d'appel API ici non plus.
  void _handleOtherPayment(PaymentMethod method) {
    // On renvoie juste le mode choisi
    Navigator.of(context).pop({'method': method});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choisir un mode de règlement'),
      content: SizedBox(
        width: double.maxFinite,
        child: FutureBuilder<List<PaymentMethod>>(
          future: _paymentMethodsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text("Erreur de chargement."));
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text("Aucun mode activé.", textAlign: TextAlign.center));
            }

            final methods = snapshot.data!;
            return ListView.separated(
              shrinkWrap: true,
              itemCount: methods.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final method = methods[index];
                return ListTile(
                  title: Text(method.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    if (method.id == '1') { // ESPECES
                      _handleCashPayment(method);
                    } else {
                      _handleOtherPayment(method);
                    }
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}