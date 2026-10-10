// lib/screens/reception_control/reception_detail_screen.dart
// Contrôle Réception : comptage des produits d'un bon (scan, saisie des quantités reçues).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:collection/collection.dart';
import 'package:prestige_vente_app/api/models/reception_model.dart';
import 'package:prestige_vente_app/providers/reception_provider.dart';
import 'package:prestige_vente_app/screens/reception_control/reception_report_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

/// Règles de saisie des quantités comptées (testables sans écran).
class ReceptionQuantity {
  ReceptionQuantity._();
  static const int max = 10000;
  static const int maxDigits = 5;

  /// Quantité saisie : entier de 0 à [max], sinon null.
  static int? parse(String text) {
    final v = int.tryParse(text.trim());
    if (v == null || v < 0 || v > max) return null;
    return v;
  }

  /// Écart inhabituel (probable faute de frappe) : plus du double attendu, avec une marge de 10.
  static bool isUnusual(int counted, int expected) {
    final e = expected < 0 ? 0 : expected;
    return counted > e + (e > 10 ? e : 10);
  }
}

class ReceptionDetailScreen extends StatefulWidget {
  /// Présentation reçue de la liste ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;
  const ReceptionDetailScreen({super.key, this.presentation});

  @override
  State<ReceptionDetailScreen> createState() => _ReceptionDetailScreenState();
}

class _ReceptionDetailScreenState extends State<ReceptionDetailScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  final Map<String, TextEditingController> _itemControllers = {};
  final Map<String, FocusNode> _itemFocusNodes = {};

  late final ReceptionProvider _provider;
  List<ReceptionItem> _filteredItems = [];

  /// Lignes saisies sur ce terminal (un 0 saisi compte comme « traité »).
  final Set<String> _touched = {};
  final Set<String> _confirming = {};
  bool _leaving = false;

  // FILTRES
  String _selectedEmplacement = "__GROUP_ALL__"; // Par défaut : Groupé
  String _selectedStatus = "TOUS";

  static const String _groupAllKey = "__GROUP_ALL__";
  static const String _allKey = "__ALL__";
  static const String _noLocKey = "__NO_LOC__";

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _provider = Provider.of<ReceptionProvider>(context, listen: false);
    final bon = _provider.selectedBon;
    if (bon != null) {
      _initializeControllers(_provider);
      _filteredItems = _computeFilteredItems();
    }
    _searchController.addListener(_applyFilters);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(_searchFocusNode);
    });
  }

  void _initializeControllers(ReceptionProvider provider) {
    final quantities = provider.currentCheckedQuantities;
    if (provider.selectedBon == null) return;

    for (var item in provider.selectedBon!.details) {
      if (!_itemControllers.containsKey(item.id)) {
        final val = quantities[item.id] ?? 0;
        final ctrl = TextEditingController(text: val > 0 ? val.toString() : '');
        final focus = FocusNode();

        focus.addListener(() {
          if (focus.hasFocus) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
            });
          } else {
            // --- SÉCURITÉ : SAUVEGARDE À LA PERTE DU FOCUS ---
            if (mounted && !_leaving) _commit(item);
          }
        });

        _itemControllers[item.id] = ctrl;
        _itemFocusNodes[item.id] = focus;
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _itemControllers.forEach((_, c) => c.dispose());
    _itemFocusNodes.forEach((_, f) => f.dispose());
    super.dispose();
  }

  bool _isTraite(ReceptionItem item, Map<String, int> q) => (q[item.id] ?? 0) > 0 || _touched.contains(item.id);

  void _snack(String text, {bool error = false, Duration duration = const Duration(seconds: 3)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? Colors.red.shade700 : null, duration: duration));
  }

  /// Confirmation d'un écart inhabituel (évite une faute de frappe envoyée au serveur).
  Future<bool> _confirmUnusual(ReceptionItem item, int quantity) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309), size: 40),
        title: const Text('Quantité inhabituelle'),
        content: Text(
          '${item.nomProduit.isEmpty ? 'Produit' : item.nomProduit}\n\n'
          'Comptée : $quantity — attendue : ${item.qteRecue}.\n'
          'Confirmez-vous cette quantité ?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Corriger')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Confirmer')),
        ],
      ),
    );
    return ok == true;
  }

  /// Enregistre la quantité saisie dans la case d'une ligne (si valide et modifiée).
  Future<void> _commit(ReceptionItem item) async {
    final ctrl = _itemControllers[item.id];
    if (ctrl == null || _confirming.contains(item.id)) return;
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    final saved = _provider.currentCheckedQuantities[item.id];
    void revert() => ctrl.text = (saved ?? 0) > 0 ? '$saved' : '';

    final quantity = ReceptionQuantity.parse(text);
    if (quantity == null) {
      revert();
      _snack('Quantité refusée : saisir un nombre entier de 0 à ${ReceptionQuantity.max}.', error: true);
      return;
    }
    // On vérifie si la valeur a changé pour ne pas surcharger le serveur
    if (saved == quantity) {
      if (!_touched.contains(item.id) && mounted) setState(() => _touched.add(item.id));
      return;
    }
    if (ReceptionQuantity.isUnusual(quantity, item.qteRecue)) {
      if (!mounted) return;
      _confirming.add(item.id);
      final ok = await _confirmUnusual(item, quantity);
      _confirming.remove(item.id);
      if (!mounted) return;
      if (!ok) {
        revert();
        _itemFocusNodes[item.id]?.requestFocus();
        return;
      }
    }
    _provider.updateQuantity(item.id, quantity).then((ok) {
      if (!ok && mounted) showUnsyncedSnack(context);
    });
    if (mounted) setState(() => _touched.add(item.id));
  }

  Future<void> _retryUnsynced() async {
    final left = await _provider.retryUnsyncedQuantities();
    if (!mounted) return;
    _snack(left == 0 ? 'Quantités enregistrées.' : '$left quantité(s) toujours non enregistrée(s). Vérifiez le réseau.', error: left > 0);
  }

  /// Enregistre la case en cours de saisie (avant de quitter l'écran ou d'ouvrir le rapport).
  Future<void> _commitFocused() async {
    final item = _provider.selectedBon?.details.firstWhereOrNull((i) => _itemFocusNodes[i.id]?.hasFocus ?? false);
    if (item != null) await _commit(item);
  }

  Future<void> _leave() async {
    if (_leaving) return;
    await _commitFocused();
    if (!mounted) return;
    _leaving = true;
    final canLeave = await confirmLeaveWithUnsynced(context, _provider, _provider.retryUnsyncedQuantities);
    if (!mounted) return;
    if (!canLeave) {
      _leaving = false;
      return;
    }
    Navigator.of(context).pop();
  }

  List<ReceptionItem> _computeFilteredItems() {
    if (_provider.selectedBon == null) return [];

    final query = _searchController.text.toLowerCase().trim();
    List<ReceptionItem> items = List.from(_provider.selectedBon!.details);

    if (query.isNotEmpty) {
      items = items.where((item) {
        return item.nomProduit.toLowerCase().contains(query) || item.cip.contains(query) || item.ean.contains(query);
      }).toList();
    }

    bool isGroupedMode = _selectedEmplacement == _groupAllKey;
    if (!isGroupedMode && _selectedEmplacement != _allKey) {
      if (_selectedEmplacement == _noLocKey) {
        items = items.where((item) => item.emplacement.isEmpty).toList();
      } else {
        items = items.where((item) => item.emplacement == _selectedEmplacement).toList();
      }
    }

    if (_selectedStatus != "TOUS") {
      final q = _provider.currentCheckedQuantities;
      items = items.where((item) {
        final currentQty = q[item.id] ?? 0;
        final bool isTraite = _isTraite(item, q);

        switch (_selectedStatus) {
          case "A_TRAITER":
            return !isTraite;
          case "TRAITE":
            return isTraite;
          case "ECART":
            return isTraite && (currentQty != item.qteRecue);
          default:
            return true;
        }
      }).toList();
    }

    if (isGroupedMode) {
      final groupedItems = groupBy(items, (ReceptionItem item) => item.emplacement.isEmpty ? "Sans Emplacement" : item.emplacement);
      final sortedKeys = groupedItems.keys.toList()..sort();
      List<ReceptionItem> sortedList = [];
      for (var key in sortedKeys) {
        var group = groupedItems[key]!;
        group.sort((a, b) => a.nomProduit.compareTo(b.nomProduit));
        sortedList.addAll(group);
      }
      items = sortedList;
    } else {
      items.sort((a, b) => a.nomProduit.compareTo(b.nomProduit));
    }
    return items;
  }

  void _applyFilters() {
    if (!mounted) return;
    setState(() => _filteredItems = _computeFilteredItems());
  }

  // --- LOGIQUE SCAN RAPIDE ---
  void _onSearchSubmitted(String val) {
    if (_filteredItems.length == 1) {
      _showQuickScanDialog(_filteredItems.first);
    } else if (_filteredItems.isEmpty && val.trim().isNotEmpty) {
      _snack('Produit introuvable dans ce bon.', error: true);
      _searchFocusNode.requestFocus();
    }
  }

  Future<void> _showQuickScanDialog(ReceptionItem item) async {
    final provider = _provider;

    final currentQty = provider.currentCheckedQuantities[item.id] ?? 0;
    final String initialValue = currentQty > 0 ? currentQty.toString() : "";

    final int? result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _QuantityInputDialog(
        nomProduit: item.nomProduit,
        cip: item.cip,
        expected: item.qteRecue,
        initialValue: initialValue,
      ),
    );
    if (!mounted || result == null) return;
    if (ReceptionQuantity.isUnusual(result, item.qteRecue) && result != currentQty) {
      final ok = await _confirmUnusual(item, result);
      if (!mounted) return;
      if (!ok) {
        _searchFocusNode.requestFocus();
        return;
      }
    }

    provider.updateQuantity(item.id, result).then((ok) {
      if (!ok && mounted) showUnsyncedSnack(context);
    });
    _itemControllers[item.id]?.text = result.toString();
    setState(() => _touched.add(item.id));

    _searchController.clear();
    _searchFocusNode.requestFocus();

    _snack("Quantité mise à jour : ${item.nomProduit}", duration: const Duration(milliseconds: 800));
  }

  void _focusNextProduct(int currentIndex) {
    if (currentIndex + 1 < _filteredItems.length) {
      final nextItem = _filteredItems[currentIndex + 1];
      final nextNode = _itemFocusNodes[nextItem.id];
      if (nextNode != null) {
        FocusScope.of(context).requestFocus(nextNode);
      }
    } else {
      FocusScope.of(context).requestFocus(_searchFocusNode);
    }
  }

  Future<void> _openReport() async {
    await _commitFocused();
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ReceptionReportScreen(presentation: style)));
    if (mounted) _applyFilters();
  }

  void _setStatus(String s) {
    _selectedStatus = s;
    _applyFilters();
  }

  void _setEmplacement(String e) {
    _selectedEmplacement = e;
    _applyFilters();
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Consumer<ReceptionProvider>(
      builder: (context, provider, child) {
        final bon = provider.selectedBon;
        if (bon == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Contrôle Réception')),
            body: const Center(child: Text("Erreur de sélection")),
          );
        }

        final q = provider.currentCheckedQuantities;
        final total = bon.details.length;
        final traites = bon.details.where((i) => _isTraite(i, q)).length;
        final ecarts = bon.details.where((i) => _isTraite(i, q) && (q[i.id] ?? 0) != i.qteRecue).length;
        final isGroupedMode = _selectedEmplacement == _groupAllKey;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _leave();
          },
          child: PresentationScaffold(
            style: style,
            title: bon.ref.isEmpty ? 'Bon sans référence' : bon.ref,
            subtitle: bon.grossiste.isEmpty ? null : bon.grossiste,
            actions: (col) => [
              IconButton(icon: Icon(Icons.assessment, color: col), tooltip: 'Rapport', onPressed: _openReport),
            ],
            steps: StepsBar(active: 1, steps: [
              (title: 'Bons', detail: 'liste', onTap: _leave),
              (title: 'Comptage', detail: '$traites/$total lignes', onTap: null),
              (title: 'Rapport', detail: '$ecarts écart(s)', onTap: _openReport),
            ]),
            header: [
              if (style == ListPresentation.dashboard)
                Row(children: [
                  Expanded(child: KpiTile('$traites/$total', 'lignes comptées')),
                  const SizedBox(width: 8),
                  Expanded(child: KpiTile('$ecarts', 'écart(s)')),
                  const SizedBox(width: 8),
                  Expanded(child: KpiTile('${total - traites}', 'à compter', highlight: true)),
                ]),
              _progress(traites, total, ecarts, dark: true),
              _scanBar(dark: true),
            ],
            compactHeader: [
              _progress(traites, total, ecarts, dark: false),
              _scanBar(dark: false),
            ],
            body: Column(children: [
              if (provider.isLoading) const LinearProgressIndicator(minHeight: 2),
              UnsyncedBanner(count: provider.unsyncedCount, retrying: provider.isRetrying, onRetry: _retryUnsynced),
              _filtersBar(bon, q),
              Expanded(child: _buildList(q, isGroupedMode)),
            ]),
            // Action principale toujours visible : le rapport (contrôle, écarts, impression).
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    style: style == ListPresentation.guided ? amberButton : navyButton,
                    icon: const Icon(Icons.assessment),
                    label: Text(ecarts > 0 ? 'Rapport · $ecarts écart(s)' : 'Rapport', overflow: TextOverflow.ellipsis),
                    onPressed: _openReport,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _progress(int done, int total, int ecarts, {required bool dark}) => Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 8,
              backgroundColor: dark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFE6EBF2),
              color: dark ? Pal.amber : Pal.green,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('$done/$total lignes', style: TextStyle(fontSize: 12, color: dark ? Colors.white : Pal.ink, fontWeight: FontWeight.w500)),
      ]);

  Widget _scanBar({required bool dark}) => TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        inputFormatters: [
          FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]')),
          LengthLimitingTextInputFormatter(60),
        ],
        decoration: InputDecoration(
          hintText: "Scanner ou rechercher produit...",
          prefixIcon: const Icon(Icons.qr_code_scanner),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Effacer',
                  onPressed: () {
                    _searchController.clear();
                    _searchFocusNode.requestFocus();
                  })
              : null,
          filled: true,
          fillColor: dark ? Colors.white : Pal.page,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: _onSearchSubmitted,
      );

  Widget _filtersBar(ReceptionBon bon, Map<String, int> q) {
    final all = bon.details;
    final traites = all.where((i) => _isTraite(i, q)).length;
    final ecarts = all.where((i) => _isTraite(i, q) && (q[i.id] ?? 0) != i.qteRecue).length;
    final statuses = [
      ('TOUS', 'Tous (${all.length})'),
      ('A_TRAITER', 'À compter (${all.length - traites})'),
      ('TRAITE', 'Comptés ($traites)'),
      ('ECART', 'Écarts ($ecarts)'),
    ];
    final locations = all.map((e) => e.emplacement).where((e) => e.isNotEmpty).toSet().toList()..sort();
    final hasNoLoc = all.any((e) => e.emplacement.isEmpty);
    final zoneLabel = switch (_selectedEmplacement) {
      _groupAllKey => 'Zones groupées',
      _allKey => 'Toutes zones',
      _noLocKey => 'Sans emplacement',
      final z => z,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(children: [
        PopupMenuButton<String>(
          tooltip: 'Emplacement',
          initialValue: _selectedEmplacement,
          onSelected: _setEmplacement,
          itemBuilder: (_) => [
            const PopupMenuItem(value: _groupAllKey, child: Text('Toutes, groupées par zone')),
            const PopupMenuItem(value: _allKey, child: Text('Toutes, par nom')),
            if (hasNoLoc) const PopupMenuItem(value: _noLocKey, child: Text('Sans emplacement')),
            for (final l in locations) PopupMenuItem(value: l, child: Text(l)),
          ],
          child: Chip(
            avatar: const Icon(Icons.place_outlined, size: 18, color: Pal.navy),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(zoneLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        const SizedBox(width: 6),
        for (final (key, label) in statuses)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(label: Text(label), selected: _selectedStatus == key, onSelected: (_) => _setStatus(key)),
          ),
      ]),
    );
  }

  Widget _buildList(Map<String, int> q, bool isGroupedMode) {
    if (_filteredItems.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 32),
        const Icon(Icons.search_off, size: 52, color: Pal.muted),
        const SizedBox(height: 10),
        const Text("Aucun produit trouvé", textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Pal.ink)),
        const SizedBox(height: 10),
        Center(
          child: OutlinedButton.icon(
            style: outlineButton,
            icon: const Icon(Icons.filter_alt_off),
            label: const Text('Tout afficher'),
            onPressed: () {
              _selectedStatus = 'TOUS';
              _selectedEmplacement = _groupAllKey;
              _searchController.clear();
              _applyFilters();
            },
          ),
        ),
      ]);
    }
    final compact = style == ListPresentation.compact;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(compact ? 0 : 12, 4, compact ? 0 : 12, 16),
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) {
        final item = _filteredItems[index];

        // Header de groupe
        bool showHeader = false;
        if (isGroupedMode) {
          if (index == 0) {
            showHeader = true;
          } else {
            final prevItem = _filteredItems[index - 1];
            String currentLoc = item.emplacement.isEmpty ? "Sans Emplacement" : item.emplacement;
            String prevLoc = prevItem.emplacement.isEmpty ? "Sans Emplacement" : prevItem.emplacement;
            if (currentLoc != prevLoc) showHeader = true;
          }
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (showHeader) _groupHeader(item.emplacement.isEmpty ? "Sans Emplacement" : item.emplacement),
          _lineRow(item, index, q, isGroupedMode),
          if (!compact) const SizedBox(height: 8),
        ]);
      },
    );
  }

  Widget _groupHeader(String name) {
    if (style == ListPresentation.compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: const Color(0xFFF1F4F8),
        child: Text(name.toUpperCase(),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: Color(0xFF4A5A70))),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Row(children: [
        const Icon(Icons.place_outlined, size: 16, color: Pal.navy),
        const SizedBox(width: 6),
        Expanded(
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.navy)),
        ),
      ]),
    );
  }

  Widget _lineRow(ReceptionItem item, int index, Map<String, int> q, bool isGroupedMode) {
    final hasBeenChecked = _isTraite(item, q);
    final qtySaisie = q[item.id] ?? 0;
    final qtyRecueBL = item.qteRecue;
    final ecart = qtySaisie - qtyRecueBL;
    final color = !hasBeenChecked ? const Color(0xFF6B7A90) : (ecart == 0 ? Pal.green : const Color(0xFFB45309));
    final icon = !hasBeenChecked ? Icons.radio_button_unchecked : (ecart == 0 ? Icons.check_circle : Icons.warning_amber_rounded);

    final row = Row(children: [
      Icon(icon, color: color),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.nomProduit.isEmpty ? '—' : item.nomProduit,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Pal.ink)),
          Text(
            'CIP ${item.cip.isEmpty ? '—' : item.cip}${isGroupedMode ? '' : ' · Zone ${item.emplacement.isEmpty ? '-' : item.emplacement}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Pal.muted),
          ),
          Text.rich(
            TextSpan(style: const TextStyle(fontSize: 13, color: Pal.ink), children: [
              const TextSpan(text: 'Attendu : '),
              TextSpan(text: '$qtyRecueBL', style: const TextStyle(fontWeight: FontWeight.bold)),
              if (hasBeenChecked && ecart != 0)
                TextSpan(
                  text: '  Écart : ${ecart > 0 ? '+' : ''}$ecart',
                  style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                ),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ]),
      ),
      LineSyncMark(unsynced: _provider.isUnsynced(item.id), sending: _provider.isSending(item.id)),
      const SizedBox(width: 4),
      SizedBox(
        width: 76,
        child: TextField(
          key: ValueKey('qte_${item.id}'),
          controller: _itemControllers[item.id],
          focusNode: _itemFocusNodes[item.id],
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(ReceptionQuantity.maxDigits),
          ],
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: "Reçu",
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            isDense: true,
          ),
          // L'enregistrement se fait via le FocusNode quand on quitte la case.
          // En appuyant sur "Entrée", on passe à la ligne suivante.
          onSubmitted: (_) => _focusNextProduct(index),
        ),
      ),
    ]);

    return switch (style) {
      ListPresentation.compact => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: hasBeenChecked ? (ecart == 0 ? const Color(0xFFF2FBF5) : const Color(0xFFFFF8EC)) : null,
            border: const Border(bottom: BorderSide(color: Color(0xFFEEF1F5))),
          ),
          child: row,
        ),
      ListPresentation.guided => SoftCard(band: color, padding: const EdgeInsets.fromLTRB(12, 10, 10, 10), child: row),
      ListPresentation.dashboard => SoftCard(padding: const EdgeInsets.fromLTRB(12, 10, 10, 10), child: row),
    };
  }
}

// ---------------------------------------------------------------------------
// WIDGET POPUP SÉCURISÉ
// ---------------------------------------------------------------------------
class _QuantityInputDialog extends StatefulWidget {
  final String nomProduit;
  final String cip;
  final int expected;
  final String initialValue;

  const _QuantityInputDialog({
    required this.nomProduit,
    required this.cip,
    required this.expected,
    required this.initialValue,
  });

  @override
  State<_QuantityInputDialog> createState() => _QuantityInputDialogState();
}

class _QuantityInputDialogState extends State<_QuantityInputDialog> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  String? _errorText;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _selectAllText();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _selectAllText() {
    if (_controller.text.isNotEmpty) {
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    }
  }

  void _close(int? value) {
    if (_closed) return; // pas de double validation
    _closed = true;
    Navigator.of(context).pop(value);
  }

  void _validate() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _close(0);
      return;
    }

    final value = ReceptionQuantity.parse(text);

    if (value == null) {
      setState(() {
        _errorText = "Quantité invalide (0 à ${ReceptionQuantity.max})";
      });
      _selectAllText();
      _focusNode.requestFocus();
    } else {
      _close(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(widget.nomProduit.isEmpty ? 'Produit' : widget.nomProduit, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("CIP: ${widget.cip}", style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.muted)),
            Text("Attendu : ${widget.expected}", style: const TextStyle(color: Pal.ink)),
            const SizedBox(height: 16),
            const Text("Saisir la quantité comptée :"),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(ReceptionQuantity.maxDigits),
              ],
              textInputAction: TextInputAction.done,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                errorText: _errorText,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onChanged: (val) {
                if (_errorText != null) setState(() => _errorText = null);
              },
              onSubmitted: (_) => _validate(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => _close(null), child: const Text("Annuler")),
        ElevatedButton(style: navyButton, onPressed: _validate, child: const Text("Valider")),
      ],
    );
  }
}
