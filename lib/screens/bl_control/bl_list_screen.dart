// lib/screens/bl_control/bl_list_screen.dart
// Pointage BL Stock : liste des bons de livraison à pointer (présentations A, B, C).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/bon_livraison.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/screens/bl_control/bl_detail_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

class BlListScreen extends StatefulWidget {
  final String? initialFilter;

  /// Présentation imposée (tests) ; sinon celle choisie sur l'appareil (A par défaut).
  final ListPresentation? presentation;

  const BlListScreen({super.key, this.initialFilter, this.presentation});

  @override
  State<BlListScreen> createState() => _BlListScreenState();
}

/// Caractères de contrôle refusés dans les champs texte.
final _noControlChars = FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]'));

class _BlListScreenState extends State<BlListScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  static final _uiDate = DateFormat('dd/MM/yyyy');
  static final _apiDate = DateFormat('yyyy-MM-dd');
  static const _filterLabels = ['À Traiter', 'Terminés', 'Tous'];

  final _searchController = TextEditingController();

  late DateTime _start;
  late DateTime _end;

  // 0 : à traiter, 1 : terminés, 2 : tous.
  int _filter = 0;
  bool _searching = false;
  bool _opening = false;

  String get _dtStart => _apiDate.format(_start);
  String get _dtEnd => _apiDate.format(_end);

  @override
  void initState() {
    super.initState();
    loadPresentation();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day);
    _end = _start;

    if (widget.initialFilter == 'A_TRAITER') {
      _filter = 0;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchData(); // Chargement initial silencieux
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

  // Requête silencieuse (utilisée à l'ouverture ou au pull-to-refresh)
  Future<void> _fetchData() async {
    try {
      await Provider.of<BlControlProvider>(context, listen: false).fetchBonsLivraison(
        query: _searchController.text.trim(),
        dtStart: _dtStart,
        dtEnd: _dtEnd,
      );
    } catch (_) {
      if (mounted) Constants.showSnackBar(context, 'Liste non chargée. Vérifiez la connexion au serveur.', isError: true);
    }
  }

  // Recherche avec popup bloquant (pas de double recherche).
  Future<void> _searchWithPopup() async {
    if (_searching) return;
    if (_start.isAfter(_end)) {
      Constants.showSnackBar(context, 'La date de début doit être avant la date de fin.', isError: true);
      return;
    }
    FocusScope.of(context).unfocus();
    _searching = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BusyDialog('Recherche en cours...'),
    );

    try {
      await _fetchData();
    } finally {
      _searching = false;
      if (mounted) {
        Navigator.of(context).pop(); // Ferme le popup une fois la recherche finie
      }
    }
  }

  /// Début ≤ fin garanti par les bornes du calendrier.
  Future<void> _selectDate({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: start ? DateTime(2020) : _start,
      lastDate: start ? _end : DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _openBl(BlControlProvider provider, BonLivraison bl) async {
    if (_opening) return;
    _opening = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BusyDialog('Ouverture du BL en cours...'),
    );

    try {
      await provider.selectBonLivraison(bl);
      if (!mounted) return;
      Navigator.of(context).pop();
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BlDetailScreen(presentation: style)));
      if (mounted) _fetchData();
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        Constants.showSnackBar(context, "Erreur lors de l'ouverture du BL. Vérifiez le réseau.", isError: true);
      }
    } finally {
      _opening = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Données affichées
  // ---------------------------------------------------------------------------
  static bool _done(BonLivraison bl) => bl.statutTraitement == 'TERMINE';
  static bool _inProgress(BonLivraison bl) => bl.statutTraitement == 'EN_COURS';

  List<BonLivraison> _visible(List<BonLivraison> all) => switch (_filter) {
        0 => all.where((bl) => !_done(bl)).toList(),
        1 => all.where(_done).toList(),
        _ => all,
      };

  static String _orDash(String s) => s.trim().isEmpty ? '—' : s.trim();

  StatusBadge _badge(BonLivraison bl) {
    if (_done(bl)) return const StatusBadge('Terminé', fg: Color(0xFF0B6B45), bg: Color(0xFFDCF5E7));
    if (_inProgress(bl)) return StatusBadge.enCours();
    return StatusBadge.aCommencer();
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Consumer<BlControlProvider>(builder: (context, provider, _) {
      final all = provider.bonsLivraison;
      final list = _visible(all);
      final todo = all.where((b) => !_done(b)).length;
      final inProgress = all.where(_inProgress).length;
      final done = all.where(_done).length;
      final counts = [todo, done, all.length];
      final compact = style == ListPresentation.compact;
      final guided = style == ListPresentation.guided;

      return PresentationScaffold(
        style: style,
        title: 'Bons de Livraison',
        subtitle: 'Du ${DateFormat('dd/MM').format(_start)} au ${_uiDate.format(_end)}',
        actions: (col) => [
          IconButton(icon: Icon(Icons.refresh, color: col), tooltip: 'Actualiser', onPressed: _searchWithPopup),
          PresentationMenuButton(value: style, onChanged: _setStyle, color: col),
        ],
        steps: StepsBar(active: 0, steps: [
          (title: 'Choisir le BL', detail: '$todo à traiter', onTap: null),
          (title: 'Pointer', detail: 'scan, quantités', onTap: null),
          (title: 'Rapport', detail: 'écarts, impression', onTap: null),
        ]),
        header: [
          if (style == ListPresentation.dashboard) ...[
            Row(children: [
              Expanded(child: KpiTile('$todo', 'à traiter', highlight: true)),
              const SizedBox(width: 8),
              Expanded(child: KpiTile('$inProgress', 'en cours')),
              const SizedBox(width: 8),
              Expanded(child: KpiTile('$done', 'terminés')),
            ]),
            const SizedBox(height: 10),
            SegmentedPills(
              labels: [for (var i = 0; i < 3; i++) '${_filterLabels[i]} · ${counts[i]}'],
              selected: _filter,
              onSelected: (i) => setState(() => _filter = i),
            ),
          ],
          if (guided) _searchField(fill: Colors.white),
        ],
        compactHeader: [_searchField(fill: Pal.page)],
        body: Column(children: [
          if (provider.isLoading) const LinearProgressIndicator(minHeight: 2),
          // Période et filtres défilent avec la liste : plus de place sur un petit écran.
          Expanded(
            child: _buildList(
              provider,
              list,
              Padding(
                padding: EdgeInsets.only(top: 12, bottom: compact ? 4 : 0),
                child: Column(children: [
                  if (style == ListPresentation.dashboard) ...[_searchField(fill: Colors.white), const SizedBox(height: 8)],
                  _periodRow(),
                  if (style != ListPresentation.dashboard) ...[const SizedBox(height: 4), _filterChips(counts)],
                ]),
              ),
            ),
          ),
        ]),
        bottomNavigationBar: _bottomBar(list),
      );
    });
  }

  Widget _searchField({required Color fill}) => TextField(
        controller: _searchController,
        maxLength: 40,
        inputFormatters: [_noControlChars],
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _searchWithPopup(), // Recherche via la touche "Entrée" du clavier
        decoration: InputDecoration(
          hintText: 'Rechercher par N° de BL...',
          counterText: '',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Effacer',
            onPressed: () {
              _searchController.clear();
              _searchWithPopup(); // On relance la recherche bloquante
            },
          ),
          filled: true,
          fillColor: fill,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: fill == Colors.white && style != ListPresentation.guided ? const BorderSide(color: Pal.line) : BorderSide.none,
          ),
        ),
      );

  Widget _dateButton(String label, DateTime value, bool start) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _selectDate(start: start),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              suffixIcon: const Icon(Icons.calendar_today, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC5D0DE))),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(_uiDate.format(value), style: const TextStyle(fontSize: 15, color: Pal.ink)),
            ),
          ),
        ),
      );

  Widget _periodRow() => Row(children: [
        _dateButton('Date Début', _start, true),
        const SizedBox(width: 8),
        _dateButton('Date Fin', _end, false),
      ]);

  Widget _filterChips(List<int> counts) => Align(
        alignment: Alignment.centerLeft,
        child: Wrap(spacing: 6, children: [
          for (var i = 0; i < 3; i++)
            ChoiceChip(
              label: Text('${_filterLabels[i]} (${counts[i]})'),
              selected: _filter == i,
              onSelected: (_) => setState(() => _filter = i),
            ),
        ]),
      );

  Widget _bottomBar(List<BonLivraison> list) {
    final total = list.fold<int>(0, (s, b) => s + b.montantTotal);
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Pal.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${list.length} BL affiché(s)', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('${Constants.formatNumber(total)} F', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink)),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                style: style == ListPresentation.guided ? amberButton : navyButton,
                icon: const Icon(Icons.search),
                label: const Text('Rechercher'),
                onPressed: _searching ? null : _searchWithPopup, // Recherche bloquante via le bouton
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildList(BlControlProvider provider, List<BonLivraison> list, Widget controls) {
    final compact = style == ListPresentation.compact;
    final top = Padding(padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16), child: controls);
    if (list.isEmpty) {
      final loading = provider.isLoading && provider.bonsLivraison.isEmpty;
      return RefreshIndicator(
        onRefresh: _fetchData,
        child: ListView(children: [
          top,
          if (loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(children: [
                const Icon(Icons.inventory_2_outlined, size: 48, color: Pal.muted),
                const SizedBox(height: 12),
                const Text('Aucun bon de livraison trouvé.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Pal.ink)),
                const SizedBox(height: 4),
                const Text('Élargissez la période ou changez le filtre.', textAlign: TextAlign.center, style: TextStyle(color: Pal.muted)),
                const SizedBox(height: 12),
                OutlinedButton.icon(style: outlineButton, icon: const Icon(Icons.refresh), label: const Text('Actualiser'), onPressed: _searchWithPopup),
              ]),
            ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchData,
      child: ListView.separated(
        padding: compact ? const EdgeInsets.only(bottom: 16) : const EdgeInsets.only(bottom: 24),
        itemCount: list.length + 1,
        separatorBuilder: (_, __) => SizedBox(height: compact ? 0 : 12),
        itemBuilder: (_, i) {
          if (i == 0) return top;
          final bl = list[i - 1];
          final card = switch (style) {
            ListPresentation.dashboard => _tappable(provider, bl, _cardA(provider, bl)),
            ListPresentation.compact => _rowB(provider, bl),
            ListPresentation.guided => _tappable(provider, bl, _cardC(provider, bl, featured: i == 1)),
          };
          return compact ? card : Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: card);
        },
      ),
    );
  }

  /// Toute la carte ouvre le BL (pas seulement le bouton).
  Widget _tappable(BlControlProvider provider, BonLivraison bl, Widget card) => Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: BorderRadius.circular(16), onTap: () => _openBl(provider, bl), child: card),
      );

  String _lines(BonLivraison bl) => '${bl.nbreLignes} ligne${bl.nbreLignes > 1 ? 's' : ''}';

  // --- A · Tableau de bord ------------------------------------------------------
  Widget _cardA(BlControlProvider provider, BonLivraison bl) => SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            GrossisteAvatar(_orDash(bl.grossiste)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('BL ${_orDash(bl.ref)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Pal.ink)),
                Text('${_orDash(bl.grossiste)} · ${_orDash(bl.date)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
              ]),
            ),
            const SizedBox(width: 6),
            _badge(bl),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Flexible(child: Figure('${bl.nbreLignes}', bl.nbreLignes > 1 ? 'lignes' : 'ligne')),
            const SizedBox(width: 18),
            Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Figure(Constants.formatNumber(bl.montantTotal), 'F'))),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: _done(bl)
                ? OutlinedButton.icon(
                    style: outlineButton,
                    icon: const Icon(Icons.visibility_outlined, size: 20),
                    label: const Text('Revoir le pointage'),
                    onPressed: () => _openBl(provider, bl),
                  )
                : ElevatedButton.icon(
                    style: navyButton,
                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                    label: Text(_inProgress(bl) ? 'Continuer le pointage' : 'Commencer le pointage'),
                    onPressed: () => _openBl(provider, bl),
                  ),
          ),
        ]),
      );

  // --- B · Liste groupée --------------------------------------------------------
  Widget _rowB(BlControlProvider provider, BonLivraison bl) {
    final (icon, color) = _done(bl)
        ? (Icons.check_circle, Pal.green)
        : _inProgress(bl)
            ? (Icons.pending_actions, const Color(0xFFB45309))
            : (Icons.receipt_long, Pal.navy);
    return InkWell(
      onTap: () => _openBl(provider, bl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _done(bl) ? const Color(0xFFF2FBF5) : null,
          border: const Border(bottom: BorderSide(color: Color(0xFFEEF1F5))),
        ),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_orDash(bl.ref)} - ${_orDash(bl.grossiste)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
              Text('${_orDash(bl.date)} - ${_lines(bl)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(Constants.formatNumber(bl.montantTotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink)),
          const Icon(Icons.chevron_right, color: Pal.muted),
        ]),
      ),
    );
  }

  // --- C · Parcours guidé -------------------------------------------------------
  Widget _cardC(BlControlProvider provider, BonLivraison bl, {required bool featured}) {
    final band = _done(bl) ? Pal.green : GrossisteAvatar.colorsFor(_orDash(bl.grossiste)).$2;
    final title = Text('BL ${_orDash(bl.ref)}',
        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: featured ? 18 : 16, fontWeight: FontWeight.bold, color: Pal.ink));
    final sub = Text('${_orDash(bl.grossiste)} · ${_orDash(bl.date)} · ${_lines(bl)}',
        maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted));
    if (!featured) {
      return SoftCard(
        band: band,
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, sub])),
          const SizedBox(width: 8),
          ElevatedButton(
            style: amberButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 44))),
            onPressed: () => _openBl(provider, bl),
            child: Text(_done(bl) ? 'Revoir' : 'Pointer'),
          ),
        ]),
      );
    }
    return SoftCard(
      band: band,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, sub])),
          const SizedBox(width: 6),
          _badge(bl),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: Pal.page, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Expanded(child: Text('Montant du BL', style: TextStyle(color: Color(0xFF4A5A70)))),
            Text('${Constants.formatNumber(bl.montantTotal)} F', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Pal.ink)),
          ]),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            style: amberButton,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(_done(bl) ? 'Revoir le pointage' : 'Pointer ce BL', style: const TextStyle(fontSize: 16)),
            onPressed: () => _openBl(provider, bl),
          ),
        ),
      ]),
    );
  }
}

/// Fenêtre d'attente bloquante (recherche, ouverture du BL).
class _BusyDialog extends StatelessWidget {
  final String text;
  const _BusyDialog(this.text);

  @override
  Widget build(BuildContext context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Flexible(child: Text(text)),
          ]),
        ),
      );
}
