// lib/widgets/prevente_list_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';

class PreventeListDialog extends StatefulWidget {
  final String typeVenteId; // "2" pour Assurance, "3" pour Carnet
  final String title;

  const PreventeListDialog({super.key, required this.typeVenteId, required this.title});

  @override
  State<PreventeListDialog> createState() => _PreventeListDialogState();
}

class _PreventeListDialogState extends State<PreventeListDialog> {
  bool _isLoading = true;
  List<PreventeListItem> _list = [];
  final ReceiptService _receiptService = ReceiptService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final provider = Provider.of<SaleProvider>(context, listen: false);
    final data = await provider.fetchPreventesByType(widget.typeVenteId);
    if (mounted) {
      setState(() {
        _list = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _printTicket(PreventeListItem item) async {
    final scaffold = ScaffoldMessenger.of(context);
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));

    try {
      final data = await saleProvider.fetchFullSaleDetails(item.lgPREENREGISTREMENTID);

      if (mounted) Navigator.of(context).pop();

      if (data == null) {
        if (mounted) scaffold.showSnackBar(const SnackBar(content: Text("Détails introuvables"), backgroundColor: Colors.red));
        return;
      }

      final clientData = data['client'] ?? {};
      final adData = data['ayantDroit'];
      final tpDataList = data['tierspayants'] as List?;
      final tpClientDataList = clientData['tiersPayants'] as List?;

      // Construction du Client
      final List<ClientTiersPayant> clientTps = [];
      if (tpClientDataList != null) {
        for (var tp in tpClientDataList) {
          clientTps.add(ClientTiersPayant(
            lgTIERSPAYANTID: tp['lgTIERSPAYANTID'] ?? '',
            tpFullName: tp['tpFullName'] ?? '',
            taux: int.tryParse(tp['taux']?.toString() ?? '0') ?? 0,
            numSecurity: tp['numSecurity'] ?? '',
            compteTp: tp['compteTp'] ?? '',
            order: tp['order'] ?? 0,
            principal: tp['principal'] ?? false,
          ));
        }
      }

      final client = ClientAssurance(
        lgCLIENTID: clientData['lgCLIENTID'] ?? '',
        fullName: clientData['fullName'] ?? '${clientData['strFIRSTNAME']} ${clientData['strLASTNAME']}',
        strFIRSTNAME: clientData['strFIRSTNAME'] ?? '',
        strLASTNAME: clientData['strLASTNAME'] ?? '',
        strNUMEROSECURITESOCIAL: clientData['strNUMEROSECURITESOCIAL'] ?? '',
        tiersPayants: clientTps,
        ayantDroits: [], // CORRECTION : Paramètre requis ajouté
      );

      // Ayant Droit
      AyantDroit ayantDroit;
      if (adData != null) {
        ayantDroit = AyantDroit(
          lgAYANTSDROITSID: adData['lgAYANTSDROITSID'] ?? '',
          lgCLIENTID: adData['lgCLIENTID'] ?? '',
          fullName: adData['fullName'] ?? '${adData['strFIRSTNAME']} ${adData['strLASTNAME']}',
          strFIRSTNAME: adData['strFIRSTNAME'] ?? '',
          strLASTNAME: adData['strLASTNAME'] ?? '',
          strNUMEROSECURITESOCIAL: adData['strNUMEROSECURITESOCIAL'] ?? '',
          strSEXE: adData['strSEXE'] ?? '',
        );
      } else {
        ayantDroit = AyantDroit(
          lgAYANTSDROITSID: client.lgCLIENTID,
          lgCLIENTID: client.lgCLIENTID,
          fullName: client.fullName,
          strFIRSTNAME: client.strFIRSTNAME,
          strLASTNAME: client.strLASTNAME,
          strNUMEROSECURITESOCIAL: client.strNUMEROSECURITESOCIAL,
          strSEXE: '',
        );
      }

      // Tiers Payants
      List<TiersPayantSummary> usedTps = [];
      if (tpDataList != null) {
        for (var tp in tpDataList) {
          usedTps.add(TiersPayantSummary(
            numBon: tp['numBon'] ?? '',
            taux: int.tryParse(tp['taux']?.toString() ?? '0') ?? 0,
            compteTp: tp['compteTp'] ?? '',
            tpnet: int.tryParse(tp['tpnet']?.toString() ?? '0') ?? 0,
          ));
        }
      }

      final int totalVente = int.tryParse(data['intPRICE']?.toString() ?? '0') ?? 0;
      final int totalTp = usedTps.fold<int>(0, (sum, tp) => sum + tp.tpnet);

      final summary = AssuranceSaleSummary(
        montant: totalVente,
        montantTp: totalTp,
        montantNet: totalVente - totalTp,
        reference: data['strREF'] ?? item.strREF,
        venteId: data['lgPREENREGISTREMENTID'] ?? item.lgPREENREGISTREMENTID,
        tierspayants: usedTps,
      );

      await _receiptService.printAssurancePreventeTicket(
        context: context,
        officine: authProvider.officine!,
        saleSummary: summary,
        items: [],
        client: client,
        ayantDroit: ayantDroit,
        currentUser: authProvider.user!,
        isTestMode: settings.isTestPrintMode,
        paperWidth: settings.paperWidth,
        ticketCodeType: settings.ticketCodeType,
      );

    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.of(context).pop();
      if (mounted) scaffold.showSnackBar(SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _list.isEmpty
            ? const Center(child: Text("Aucune prévente trouvée"))
            : ListView.separated(
          itemCount: _list.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (ctx, index) {
            final item = _list[index];
            return ListTile(
              dense: true,
              leading: const Icon(Icons.receipt_long, color: Colors.grey),
              title: Text(item.strREF, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("${item.dtUPDATED} à ${item.heure}\n${Constants.formatNumber(item.intPRICE)} F"),
              trailing: IconButton(
                icon: const Icon(Icons.print, color: Colors.blue),
                onPressed: () => _printTicket(item),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fermer"))
      ],
    );
  }
}