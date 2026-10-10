// lib/ventes/prevente/prevente_list.dart
// Liste des préventes à encaisser : vraie date (dd/MM/yyyy HH:mm), recherche par référence ou vendeur,
// panne affichée comme une panne (« Réessayer »), jamais « aucune prévente ».
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

class PreventeList extends StatefulWidget {
  /// Ouverture d'une prévente (la confirmation éventuelle est faite par l'écran).
  final Future<void> Function(PreventeListItem item) onOpen;
  const PreventeList({super.key, required this.onOpen});

  @override
  State<PreventeList> createState() => PreventeListState();
}

class PreventeListState extends State<PreventeList> {
  final _search = TextEditingController();
  bool _loading = false;
  String? _error;
  List<PreventeListItem>? _list;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (_loading || !mounted) return;
    setState(() => _loading = true);
    final r = await context.read<VenteController>().preventes();
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

  Future<void> _reprint(PreventeListItem sale) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final officine = auth.officine, user = auth.user;
    if (officine == null || user == null) {
      Constants.showSnackBar(context, 'Données officine/utilisateur manquantes', isError: true);
      return;
    }
    await ReceiptService().printPreventeTicket(
      context: context,
      officine: officine,
      saleSummary: SaleSummary(montant: sale.intPRICE, montantNet: sale.intPRICE, reference: sale.strREF, venteId: sale.lgPREENREGISTREMENTID),
      currentUser: user,
      isTestMode: settings.isTestPrintMode,
      paperWidth: settings.paperWidth,
      ticketCodeType: settings.ticketCodeType,
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.toLowerCase().trim();
    final all = _list ?? const <PreventeListItem>[];
    final list = q.isEmpty
        ? all
        : all.where((p) => p.strREF.toLowerCase().contains(q) || p.userFullName.toLowerCase().contains(q)).toList();

    Widget body;
    if (_list == null && _error != null) {
      body = LoadErrorView(message: _error!, onRetry: refresh);
    } else if (_list == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = RefreshIndicator(
        onRefresh: refresh,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: list.isEmpty ? 1 : list.length,
          itemBuilder: (context, i) {
            if (list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Center(child: Text(q.isEmpty ? 'Aucune prévente à encaisser' : 'Aucune prévente pour « $q »')),
              );
            }
            final sale = list[i];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.shopping_bag, color: Colors.white)),
                title: Text(sale.strREF, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${preventeDateLabel(sale)}\n${sale.userFullName}', style: const TextStyle(fontSize: 12)),
                isThreeLine: true,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${Constants.formatNumber(sale.intPRICE)} F',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary)),
                  IconButton(icon: const Icon(Icons.print, color: Colors.grey), tooltip: 'Réimprimer le ticket', onPressed: () => _reprint(sale)),
                ]),
                onTap: () => widget.onOpen(sale),
              ),
            );
          },
        ),
      );
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: TextField(
          controller: _search,
          decoration: InputDecoration(
            labelText: 'Rechercher (réf. ou vendeur)',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Effacer',
              onPressed: () {
                _search.clear();
                setState(() {});
              },
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
      if (_list != null && _error != null) LoadErrorBanner(message: 'Liste non actualisée : $_error', onRetry: refresh),
      if (_loading && _list != null) const LinearProgressIndicator(minHeight: 2),
      Expanded(child: body),
    ]);
  }
}
