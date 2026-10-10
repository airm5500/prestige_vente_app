// lib/screens/delivery_control/delivery_list_screen.dart
// 18/10/2025 14:40
// 10/10/2026 : présentations A/B/C, période, chiffres clés, progression, recherche.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/commande.dart';
import 'package:prestige_vente_app/providers/delivery_control_provider.dart';
import 'package:prestige_vente_app/screens/delivery_control/delivery_detail_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

class DeliveryListScreen extends StatefulWidget {
  /// Présentation imposée (tests) ; sinon celle choisie sur l'appareil (A par défaut).
  final ListPresentation? presentation;

  /// Horloge remplaçable (tests).
  final DateTime Function()? clock;

  const DeliveryListScreen({super.key, this.presentation, this.clock});

  @override
  State<DeliveryListScreen> createState() => _DeliveryListScreenState();
}

enum _Period { all, today, week, month }

enum _Status { all, todo, progress, done }

/// Date de la commande lue côté serveur (aaaa-mm-jj… ou jj/mm/aaaa…) ; null si illisible.
DateTime? parseCommandeDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s.length >= 19 ? s.substring(0, 19) : s) ?? DateTime.tryParse(s.split(' ').first);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(s);
  if (m == null) return null;
  final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(y, mo, d);
}

class _DeliveryListScreenState extends State<DeliveryListScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  _Period _period = _Period.all;
  _Status _status = _Status.all;
  String _query = '';
  bool _opening = false;
  final _searchController = TextEditingController();
  static final _fmt = DateFormat('dd/MM/yyyy');

  static const _periodLabels = {
    _Period.all: 'Toutes',
    _Period.today: 'Aujourd\'hui',
    _Period.week: '7 jours',
    _Period.month: '30 jours',
  };
  static const _statusLabels = {
    _Status.all: 'Toutes',
    _Status.todo: 'À contrôler',
    _Status.progress: 'En cours',
    _Status.done: 'Terminées',
  };

  @override
  void initState() {
    super.initState();
    loadPresentation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  Future<void> _refresh() async {
    try {
      await Provider.of<DeliveryControlProvider>(context, listen: false).fetchCommandes();
    } catch (_) {
      if (mounted) Constants.showSnackBar(context, 'Liste des commandes non chargée. Vérifiez la connexion au serveur.', isError: true);
    }
  }

  DateTime get _today {
    final n = (widget.clock ?? DateTime.now)();
    return DateTime(n.year, n.month, n.day);
  }

  bool _inPeriod(Commande c) {
    if (_period == _Period.all) return true;
    final d = parseCommandeDate(c.date);
    // Date illisible : on garde la commande (mieux vaut trop que rien).
    if (d == null) return true;
    final from = switch (_period) {
      _Period.today => _today,
      _Period.week => _today.subtract(const Duration(days: 6)),
      _ => _today.subtract(const Duration(days: 29)),
    };
    return !d.isBefore(from) && !d.isAfter(_today);
  }

  _Status _statusOf(DeliveryControlProvider p, Commande c) {
    if (p.isOrderCompleted(c.id)) return _Status.done;
    if (p.isOrderInProgress(c.id)) return _Status.progress;
    return _Status.todo;
  }

  bool _matches(Commande c) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return c.ref.toLowerCase().contains(q) || c.grossiste.toLowerCase().contains(q);
  }

  // --- Ouverture d'une commande (logique d'origine, protégée contre le double tap) ---
  Future<void> _open(DeliveryControlProvider provider, Commande commande) async {
    if (_opening) return;
    _opening = true;
    showDialog(
      context: context,
      barrierDismissible: false, // Empêche de cliquer à côté pour fermer
      builder: (BuildContext dialogContext) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Flexible(child: Text("Ouverture de la commande...")),
              ],
            ),
          ),
        );
      },
    );

    try {
      // Téléchargement des données de la commande
      await provider.selectCommande(commande);
    } catch (e) {
      // En cas d'erreur (ex: problème réseau)
      _opening = false;
      if (mounted) {
        Navigator.of(context).pop(); // Ferme le popup
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur lors de l'ouverture de la commande."), backgroundColor: Colors.red),
        );
      }
      return;
    }
    _opening = false;
    if (!mounted) return;
    Navigator.of(context).pop(); // Fermeture du popup de chargement

    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeliveryDetailScreen(presentation: style)));
    // Une fois de retour, on rafraîchit la liste.
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DeliveryControlProvider>(builder: (context, provider, _) {
      final inPeriod = provider.commandes.where(_inPeriod).toList();
      final counts = {for (final s in _Status.values) s: 0};
      for (final c in inPeriod) {
        counts[_statusOf(provider, c)] = counts[_statusOf(provider, c)]! + 1;
      }
      final visible = inPeriod.where((c) => _matches(c) && (_status == _Status.all || _statusOf(provider, c) == _status)).toList();
      final total = inPeriod.length;
      final done = counts[_Status.done]!;
      final compact = style == ListPresentation.compact;
      final guided = style == ListPresentation.guided;

      final figures = [
        ('${counts[_Status.todo]}', 'à contrôler'),
        ('${counts[_Status.progress]}', 'en cours'),
        ('$done', 'terminée(s)'),
      ];

      return PresentationScaffold(
        style: style,
        title: 'Contrôle Livraison',
        subtitle: compact ? null : 'Liste des Commandes · $total commande(s)',
        actions: (col) => [
          IconButton(icon: Icon(Icons.refresh, color: col), tooltip: 'Actualiser', onPressed: _refresh),
          PresentationMenuButton(value: style, onChanged: _setStyle, color: col),
        ],
        steps: const StepsBar(active: 0, steps: [
          (title: 'Commande', detail: 'à contrôler', onTap: null),
          (title: 'Contrôle', detail: 'quantités reçues', onTap: null),
          (title: 'Rapport', detail: 'écarts', onTap: null),
        ]),
        header: [
          if (!guided)
            Row(children: [
              for (final (i, f) in figures.indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: KpiTile(f.$1, f.$2, highlight: i == 0)),
              ],
            ]),
          if (!guided)
            SegmentedPills(
              labels: [for (final p in _Period.values) _periodLabels[p]!],
              selected: _period.index,
              onSelected: (i) => setState(() => _period = _Period.values[i]),
            ),
          _search(dark: true),
        ],
        compactHeader: [
          _search(dark: false),
          _periodChips(),
          LightFigures([
            ('${counts[_Status.todo]}', 'À contrôler', Pal.navy),
            ('${counts[_Status.progress]}', 'En cours', Pal.amber),
            ('$done', 'Terminées', Pal.green),
          ]),
        ],
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: EdgeInsets.fromLTRB(compact ? 0 : 12, 8, compact ? 0 : 12, 24),
            children: [
              if (guided) _periodChips(),
              _statusChips(counts),
              Padding(
                padding: EdgeInsets.fromLTRB(compact ? 16 : 4, 6, compact ? 16 : 4, 8),
                child: ThinProgress(
                  value: total == 0 ? 0 : done / total,
                  left: 'Contrôle terminé',
                  right: '$done / $total',
                  color: done == total && total > 0 ? Pal.green : Pal.blue,
                ),
              ),
              if (provider.isLoading) const LinearProgressIndicator(minHeight: 2),
              if (provider.isLoading && provider.commandes.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (visible.isEmpty)
                _empty(provider)
              else
                for (final c in visible) _row(provider, c),
            ],
          ),
        ),
      );
    });
  }

  Widget _search({required bool dark}) => TextField(
        controller: _searchController,
        inputFormatters: [LengthLimitingTextInputFormatter(40)],
        decoration: InputDecoration(
          hintText: 'N° de commande ou grossiste',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Effacer',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: dark ? Colors.white : Pal.page,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        onChanged: (v) => setState(() => _query = v.trim()),
      );

  Widget _periodChips() => SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(top: 4), children: [
          for (final p in _Period.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text(_periodLabels[p]!), selected: _period == p, onSelected: (_) => setState(() => _period = p)),
            ),
        ]),
      );

  Widget _statusChips(Map<_Status, int> counts) => SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: style == ListPresentation.compact ? 16 : 4),
          children: [
            for (final s in _Status.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(s == _Status.all ? _statusLabels[s]! : '${_statusLabels[s]} (${counts[s]})'),
                  selected: _status == s,
                  onSelected: (_) => setState(() => _status = s),
                ),
              ),
          ],
        ),
      );

  Widget _empty(DeliveryControlProvider provider) {
    final filtered = provider.commandes.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text(
          filtered ? 'Aucune commande pour ces critères.' : 'Aucune commande en cours.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: Pal.ink),
        ),
        const SizedBox(height: 8),
        if (filtered)
          OutlinedButton(
            style: outlineButton,
            onPressed: () {
              _searchController.clear();
              setState(() {
                _query = '';
                _period = _Period.all;
                _status = _Status.all;
              });
            },
            child: const Text('Voir toutes les commandes'),
          )
        else
          OutlinedButton.icon(style: outlineButton, onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Actualiser')),
      ]),
    );
  }

  static StatusBadge _badge(_Status s) => switch (s) {
        _Status.done => const StatusBadge('Terminée', fg: Color(0xFF0B6B45), bg: Color(0xFFDCF5E7)),
        _Status.progress => StatusBadge.enCours(),
        _ => StatusBadge.aCommencer(),
      };

  static Color _color(_Status s) => switch (s) {
        _Status.done => AppColors.success,
        _Status.progress => Colors.orange,
        _ => Pal.navy,
      };

  String _dateText(Commande c) {
    final d = parseCommandeDate(c.date);
    if (d != null) return _fmt.format(d);
    return c.date.trim().isEmpty ? '—' : c.date;
  }

  Widget _row(DeliveryControlProvider provider, Commande c) {
    final s = _statusOf(provider, c);
    final ref = c.ref.trim().isEmpty ? '—' : c.ref;
    final grossiste = c.grossiste.trim().isEmpty ? '—' : c.grossiste;
    void open() => _open(provider, c);
    final amount = Text(
      Constants.formatNumber(c.prixAchatTotal),
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.secondary),
    );

    switch (style) {
      case ListPresentation.compact:
        return InkWell(
          onTap: open,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
            child: Row(children: [
              Icon(
                s == _Status.done ? Icons.check_circle : (s == _Status.progress ? Icons.pending_actions : Icons.receipt_long),
                color: _color(s),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$ref - $grossiste',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
                  Text('${_dateText(c)} - ${c.nbreProduit} produits',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
                ]),
              ),
              const SizedBox(width: 8),
              amount,
            ]),
          ),
        );
      case ListPresentation.guided:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: open,
            child: SoftCard(
              band: _color(s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text(ref,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Pal.ink)),
                  ),
                  _badge(s),
                ]),
                Text('$grossiste · ${_dateText(c)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Figure('${c.nbreProduit}', 'produits')),
                  Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: amount)),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: amberButton,
                    onPressed: open,
                    child: Text(s == _Status.done ? 'Revoir le contrôle' : 'Contrôler'),
                  ),
                ),
              ]),
            ),
          ),
        );
      case ListPresentation.dashboard:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: open,
            child: SoftCard(
              highlighted: s == _Status.done,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  GrossisteAvatar(grossiste),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ref,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Pal.ink)),
                      Text('$grossiste · ${_dateText(c)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
                    ]),
                  ),
                  const SizedBox(width: 6),
                  _badge(s),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: Figure('${c.nbreProduit}', 'produits')),
                  Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: amount)),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    style: navyButton,
                    icon: Icon(s == _Status.done ? Icons.assessment : Icons.fact_check, size: 20),
                    label: Text(s == _Status.done ? 'Revoir le contrôle' : 'Contrôler'),
                    onPressed: open,
                  ),
                ),
              ]),
            ),
          ),
        );
    }
  }
}
