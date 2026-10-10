// lib/ventes/carnet/carnet_history.dart
// Historique des ventes carnet : vraie date, « Reprendre la prévente » et « Réimprimer »
// (ticket avec la vraie référence, nombre de copies du réglage). Panne ≠ « aucune vente ».
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_controller.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart' show preventeDateLabel;
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

/// Données d'un ticket de réimpression (prévente carnet).
typedef CarnetReprint = ({AssuranceSaleSummary summary, ClientAssurance client, AyantDroit ayantDroit, List<SaleItemDetail> items});

/// Construit le ticket à partir de /ventestats/{id} : la référence est portée par la ligne
/// transmise au ticket (le ticket la lit sur la 1ʳᵉ ligne), d'où le défaut n°9 corrigé.
CarnetReprint? buildCarnetReprint(PreventeListItem item, Map<String, dynamic> data) {
  final cj = data['client'];
  final client = (cj is Map ? CarnetController.parseClient(Map<String, dynamic>.from(cj)) : null) ??
      ClientAssurance(lgCLIENTID: '', fullName: '', strFIRSTNAME: '', strLASTNAME: '', strNUMEROSECURITESOCIAL: '', tiersPayants: [], ayantDroits: []);
  final aj = data['ayantDroit'];
  final ad = (aj is Map ? CarnetController.parseAyantDroit(Map<String, dynamic>.from(aj)) : null) ?? CarnetController.selfAyantDroit(client);
  int toInt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  final tps = <TiersPayantSummary>[
    if (data['tierspayants'] is List)
      for (final t in data['tierspayants'] as List)
        if (t is Map) TiersPayantSummary(numBon: '${t['numBon'] ?? ''}', taux: toInt(t['taux']), compteTp: '${t['compteTp'] ?? ''}', tpnet: toInt(t['tpnet'])),
  ];
  final total = toInt(data['intPRICE'] ?? item.intPRICE);
  final totalTp = tps.fold<int>(0, (s, t) => s + t.tpnet);
  final ref = '${data['strREF'] ?? ''}'.trim().isNotEmpty ? '${data['strREF']}'.trim() : item.strREF;
  if (ref.isEmpty) return null;
  final id = '${data['lgPREENREGISTREMENTID'] ?? ''}'.isNotEmpty ? '${data['lgPREENREGISTREMENTID']}' : item.lgPREENREGISTREMENTID;
  return (
    summary: AssuranceSaleSummary(montant: total, montantTp: totalTp, montantNet: total - totalTp, reference: ref, venteId: id, tierspayants: tps),
    client: client,
    ayantDroit: ad,
    items: [
      SaleItemDetail(lgPREENREGISTREMENTDETAILID: '', lgFAMILLEID: '', strNAME: '', intCIP: '', intQUANTITY: 0, intPRICEUNITAIR: 0, intPRICE: 0, strREF: ref),
    ],
  );
}

/// Ouvre l'historique ; renvoie la vente à reprendre (ou null).
Future<PreventeListItem?> showCarnetHistory(BuildContext context, CarnetController c) =>
    showDialog<PreventeListItem>(context: context, builder: (_) => _CarnetHistoryDialog(controller: c));

class _CarnetHistoryDialog extends StatefulWidget {
  final CarnetController controller;
  const _CarnetHistoryDialog({required this.controller});

  @override
  State<_CarnetHistoryDialog> createState() => _CarnetHistoryDialogState();
}

class _CarnetHistoryDialogState extends State<_CarnetHistoryDialog> {
  List<PreventeListItem>? _list;
  String? _error;
  bool _loading = false;
  String? _printing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await widget.controller.history();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r case VenteOk(:final value)) {
        _list = value;
        _error = null;
      } else {
        _error = venteMessage(r.message);
      }
    });
  }

  Future<void> _reprint(PreventeListItem item) async {
    if (_printing != null) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final officine = auth.officine, user = auth.user;
    if (officine == null || user == null) {
      showVenteSnack(context, 'Données officine/utilisateur manquantes : ticket non imprimé.', error: true);
      return;
    }
    setState(() => _printing = item.lgPREENREGISTREMENTID);
    try {
      final r = await widget.controller.gateway.fullSale(item.lgPREENREGISTREMENTID);
      if (!mounted) return;
      if (r is! VenteOk<Map<String, dynamic>>) {
        showVenteFailure(context, r, onRetry: () => _reprint(item));
        return;
      }
      final t = buildCarnetReprint(item, r.value);
      if (t == null) {
        showVenteSnack(context, 'Référence de la vente introuvable : ticket non imprimé.', error: true);
        return;
      }
      await ReceiptService().printAssurancePreventeTicket(
        context: context,
        officine: officine,
        saleSummary: t.summary,
        items: t.items,
        client: t.client,
        ayantDroit: t.ayantDroit,
        currentUser: user,
        isTestMode: settings.isTestPrintMode,
        paperWidth: settings.paperWidth,
        ticketCodeType: settings.ticketCodeType,
        numberOfCopies: settings.numberOfTicketsAssurance,
      );
    } finally {
      if (mounted) setState(() => _printing = null);
    }
  }

  Widget _row(PreventeListItem item) {
    final printing = _printing == item.lgPREENREGISTREMENTID;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(item.strREF, style: const TextStyle(fontWeight: FontWeight.bold))),
          Text('${Constants.formatNumber(item.intPRICE)} F', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
        ]),
        Text('${preventeDateLabel(item)}${item.userFullName.isEmpty ? '' : ' · ${item.userFullName}'}',
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
        Wrap(spacing: 8, children: [
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(context).pop(item),
            icon: const Icon(Icons.play_arrow, size: 20),
            label: const Text('Reprendre la prévente'),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: _printing != null ? null : () => _reprint(item),
            icon: printing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.print, size: 20),
            label: const Text('Réimprimer'),
          ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    Widget body;
    if (list == null && _error != null) {
      body = LoadErrorView(message: _error!, onRetry: _load);
    } else if (list == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (list.isEmpty) {
      body = const Center(child: Text('Aucune vente carnet récente'));
    } else {
      body = ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => _row(list[i]),
      );
    }
    return AlertDialog(
      title: const Text('Historique carnet'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(children: [
          if (list != null && _error != null) LoadErrorBanner(message: 'Liste non actualisée : $_error', onRetry: _load),
          if (_loading && list != null) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: body),
        ]),
      ),
      actions: [
        TextButton(style: TextButton.styleFrom(minimumSize: const Size(88, 44)), onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer'))
      ],
    );
  }
}
