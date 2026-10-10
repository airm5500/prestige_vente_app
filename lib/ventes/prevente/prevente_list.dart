// lib/ventes/prevente/prevente_list.dart
// « Préventes à encaisser » (A/B/C) : vraie date + heure, montant, vendeur, badge « À encaisser »,
// recherche par référence ou vendeur, réimpression ; panne affichée comme une panne (« Réessayer »).
// Toucher une prévente : [onSelect] confirme (panier en cours) puis la page se ferme en la renvoyant.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

class PreventeListScreen extends StatefulWidget {
  /// Chargement de la liste (préventes comptant, sans doublon, plus récentes d'abord).
  final Future<VenteResult<List<PreventeListItem>>> Function() load;

  /// Confirmation avant d'ouvrir (panier en cours) : true = ouvrir, null = revenir au panier, false = rester.
  final Future<bool?> Function(PreventeListItem item) onSelect;

  /// Présentation (celle de l'appareil si non précisée).
  final ListPresentation? presentation;

  const PreventeListScreen({super.key, required this.load, required this.onSelect, this.presentation});

  @override
  State<PreventeListScreen> createState() => _PreventeListScreenState();
}

class _PreventeListScreenState extends State<PreventeListScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  final _search = TextEditingController();
  bool _loading = false;
  bool _opening = false;
  String? _error;
  List<PreventeListItem>? _list;

  @override
  void initState() {
    super.initState();
    loadPresentation();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading || !mounted) return;
    setState(() => _loading = true);
    final r = await widget.load();
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

  Future<void> _open(PreventeListItem item) async {
    if (_opening) return;
    _opening = true;
    try {
      final ok = await widget.onSelect(item);
      if (!mounted || ok == false) return;
      Navigator.of(context).pop(ok == true ? item : null);
    } finally {
      _opening = false;
    }
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

  List<PreventeListItem> get _filtered {
    final q = VenteInput.cleanQuery(_search.text).toLowerCase();
    final all = _list ?? const <PreventeListItem>[];
    if (q.isEmpty) return all;
    return all.where((p) => p.strREF.toLowerCase().contains(q) || p.userFullName.toLowerCase().contains(q)).toList();
  }

  Widget _searchField({required bool dark}) => TextField(
        key: const ValueKey('preventes-recherche'),
        controller: _search,
        inputFormatters: VenteInput.queryFormatters,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Référence ou vendeur',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Effacer',
                  onPressed: () {
                    _search.clear();
                    setState(() {});
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: dark ? Colors.white : Pal.page,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final all = _list ?? const <PreventeListItem>[];
    final total = all.fold<int>(0, (s, p) => s + p.intPRICE);
    final q = _search.text.trim();

    Widget body;
    if (_list == null && _error != null) {
      body = LoadErrorView(message: _error!, onRetry: _refresh);
    } else if (_list == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final compact = style == ListPresentation.compact;
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: list.isEmpty
            ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(children: [
                    const Icon(Icons.inbox_outlined, size: 56, color: Color(0xFF9AA8BC)),
                    const SizedBox(height: 10),
                    Text(q.isEmpty ? 'Aucune prévente à encaisser' : 'Aucune prévente pour « $q »',
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: Pal.ink)),
                  ]),
                ),
              ])
            : AdaptiveCardList(
                // Cartes (A, C) : 2 colonnes sur tablette portrait, 3 en paysage ; lignes (B) : une colonne.
                columns: compact ? 1 : Responsive.columns(context),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: compact ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 10, 12, 16),
                itemCount: list.length,
                separatorBuilder: (_, __) => compact ? const Divider(height: 1, color: Color(0xFFEEF1F5)) : const SizedBox(height: 9),
                itemBuilder: (context, i) => _PreventeTile(
                  sale: list[i],
                  style: style,
                  onTap: () => _open(list[i]),
                  onReprint: () => _reprint(list[i]),
                ),
              ),
      );
    }

    final count = all.length;
    return PresentationScaffold(
      style: style,
      wide: style != ListPresentation.compact,
      title: 'Préventes à encaisser',
      subtitle: _list == null ? null : '$count prévente${count > 1 ? 's' : ''} · ${Constants.formatNumber(total)} F',
      actions: (col) => [
        IconButton(icon: Icon(Icons.refresh, color: col), tooltip: 'Actualiser', onPressed: _loading ? null : _refresh),
      ],
      steps: const StepsBar(active: 0, steps: [
        (title: 'Choisir', detail: 'la prévente', onTap: null),
        (title: 'Vérifier', detail: 'le panier', onTap: null),
        (title: 'Encaisser', detail: 'paiement', onTap: null),
      ]),
      header: [_searchField(dark: true)],
      compactHeader: [_searchField(dark: false)],
      body: Column(children: [
        if (_list != null && _error != null) LoadErrorBanner(message: 'Liste non actualisée : $_error', onRetry: _refresh),
        if (_loading && _list != null) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: body),
      ]),
    );
  }
}

class _PreventeTile extends StatelessWidget {
  final PreventeListItem sale;
  final ListPresentation style;
  final VoidCallback onTap;
  final VoidCallback onReprint;
  const _PreventeTile({required this.sale, required this.style, required this.onTap, required this.onReprint});

  static const _badge = StatusBadge('À encaisser', fg: Color(0xFF9A3412), bg: Color(0xFFFFF4E0));

  @override
  Widget build(BuildContext context) {
    final vendeur = sale.userFullName.trim().isEmpty ? '—' : sale.userFullName.trim();
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(sale.strREF.isEmpty ? '—' : sale.strREF,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink)),
        const Text('  ·  ', style: TextStyle(color: Pal.muted)),
        Text('${Constants.formatNumber(sale.intPRICE)} F',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.navy)),
      ]),
      const SizedBox(height: 2),
      Text(preventeDateLabel(sale), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
      Text('Vendeur : $vendeur', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
    ]);
    final reprint = IconButton(
      icon: const Icon(Icons.print_outlined, color: Pal.muted),
      tooltip: 'Réimprimer le ticket',
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      onPressed: onReprint,
    );
    final row = Row(children: [
      Expanded(child: info),
      const SizedBox(width: 6),
      Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [_badge, reprint]),
    ]);

    if (style == ListPresentation.compact) {
      return Material(
        color: Colors.white,
        child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.fromLTRB(14, 6, 6, 4), child: row)),
      );
    }
    final guided = style == ListPresentation.guided;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      elevation: 0.6,
      shadowColor: const Color(0x3314213D),
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (guided) Container(width: 5, color: Pal.amber),
            Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 10, 6, 6), child: row)),
          ]),
        ),
      ),
    );
  }
}
