// lib/ventes/assurance/assurance_history.dart
// Historique des ventes assurance (50 dernières) : « Reprendre » (décision n°7) et « Réimprimer »
// (vraie référence, nombre de copies). Panne affichée comme une panne, jamais « aucune prévente ».
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart' show preventeDateLabel;
import 'package:prestige_vente_app/widgets/sync_status.dart';

enum AssuranceHistoryAction { resume, reprint }

typedef AssuranceHistoryChoice = ({AssuranceHistoryAction action, PreventeListItem item});

/// Ouvre l'historique ; renvoie l'action choisie (null si fermé).
Future<AssuranceHistoryChoice?> showAssuranceHistory(BuildContext context, Future<VenteResult<List<PreventeListItem>>> Function() load) =>
    showDialog<AssuranceHistoryChoice>(context: context, builder: (_) => _HistoryDialog(load: load));

class _HistoryDialog extends StatefulWidget {
  final Future<VenteResult<List<PreventeListItem>>> Function() load;
  const _HistoryDialog({required this.load});

  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  final _search = TextEditingController();
  List<PreventeListItem>? _list;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    final r = await widget.load();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r case VenteOk(:final value)) {
        final unique = <String, PreventeListItem>{};
        for (final p in value) {
          unique.putIfAbsent(p.lgPREENREGISTREMENTID, () => p);
        }
        _list = unique.values.toList();
        _error = null;
      } else {
        _error = venteMessage(r.message);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.toLowerCase().trim();
    final all = _list ?? const <PreventeListItem>[];
    final list = q.isEmpty ? all : all.where((p) => p.strREF.toLowerCase().contains(q) || p.userFullName.toLowerCase().contains(q)).toList();

    Widget body;
    if (_list == null && _error != null) {
      body = LoadErrorView(message: _error!, onRetry: _refresh);
    } else if (_list == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (list.isEmpty) {
      body = Center(child: Text(q.isEmpty ? 'Aucune vente assurance récente' : 'Aucune vente pour « $q »', textAlign: TextAlign.center));
    } else {
      body = ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final item = list[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(item.strREF, style: const TextStyle(fontWeight: FontWeight.bold))),
                Text('${Constants.formatNumber(item.intPRICE)} F', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
              ]),
              Text('${preventeDateLabel(item)}${item.userFullName.isEmpty ? '' : ' · ${item.userFullName}'}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 4, children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => Navigator.of(context).pop((action: AssuranceHistoryAction.resume, item: item)),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Reprendre'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => Navigator.of(context).pop((action: AssuranceHistoryAction.reprint, item: item)),
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text('Réimprimer'),
                ),
              ]),
            ]),
          );
        },
      );
    }

    return AlertDialog(
      title: const Text('Préventes Assurance'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(children: [
          TextField(
            controller: _search,
            decoration: const InputDecoration(labelText: 'Rechercher (réf. ou vendeur)', prefixIcon: Icon(Icons.search), isDense: true),
            onChanged: (_) => setState(() {}),
          ),
          if (_list != null && _error != null) LoadErrorBanner(message: 'Liste non actualisée : $_error', onRetry: _refresh),
          if (_loading && _list != null) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 4),
          Expanded(child: body),
        ]),
      ),
      actions: [TextButton(style: TextButton.styleFrom(minimumSize: const Size(64, 44)), onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
    );
  }
}
