// lib/screens/bl_control/bl_detail_screen.dart
// Pointage d'un BL : scan / recherche dans l'en-tête, quantité comptée par ligne, rapport en bas (présentations A, B, C).
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/bon_livraison_item.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/bl_control/bl_report_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

/// Quantité comptée maximale acceptée pour une ligne.
const int kBlMaxCountedQty = 10000;

/// Écart jugé anormal (faute de frappe probable) : à confirmer avant l'envoi.
/// Écart supérieur à 20 boîtes ET au stock de référence lui-même.
bool isSuspiciousBlCount({required int counted, required int reference}) {
  final diff = (counted - reference).abs();
  return diff > math.max(20, reference.abs());
}

class BlDetailScreen extends StatefulWidget {
  /// Présentation (A, B, C) ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;

  const BlDetailScreen({super.key, this.presentation});

  @override
  State<BlDetailScreen> createState() => _BlDetailScreenState();
}

class _BlDetailScreenState extends State<BlDetailScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  final Map<String, FocusNode> _itemFocusNodes = {};
  final Map<String, TextEditingController> _itemControllers = {};
  final Set<String> _confirming = {};
  bool _disposing = false;

  List<BonLivraisonItem> _filteredItems = [];
  String? _selectedEmplacement;

  // Gardés pour l'enregistrement à la perte du focus (même pendant la fermeture de l'écran).
  late final BlControlProvider _provider;
  late final SettingsProvider _settings;

  static const String _groupAllKey = "__GROUP_ALL__";

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _provider = Provider.of<BlControlProvider>(context, listen: false);
    _settings = Provider.of<SettingsProvider>(context, listen: false);
    _filteredItems = _provider.items;
    _initializeControllers(_provider);

    _searchController.addListener(_onSearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(_searchFocusNode);
    });
  }

  void _initializeControllers(BlControlProvider provider) {
    final checkedQuantities = provider.checkedQuantities;

    for (var item in provider.items) {
      if (!_itemControllers.containsKey(item.id)) {
        final savedQuantity = checkedQuantities[item.id];
        final controller = TextEditingController(
          text: savedQuantity != null ? savedQuantity.toString() : '',
        );

        final focusNode = FocusNode();

        focusNode.addListener(() {
          if (focusNode.hasFocus) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: controller.text.length,
              );
            });
          } else {
            // --- SÉCURITÉ : SAUVEGARDE À LA PERTE DU FOCUS ---
            // Déclenché quand on appuie sur "Entrée" (changement de case)
            // ou qu'on touche un autre produit.
            _commitField(item);
          }
        });

        _itemFocusNodes[item.id] = focusNode;
        _itemControllers[item.id] = controller;
      }
    }
  }

  @override
  void dispose() {
    // Retour arrière pendant une saisie : la quantité en cours est enregistrée (sans dialogue).
    _disposing = true;
    for (final item in _provider.items) {
      if (_itemFocusNodes[item.id]?.hasFocus ?? false) _commitField(item);
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
    _itemFocusNodes.forEach((_, node) => node.dispose());
    _itemControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  int _reference(BonLivraisonItem item) =>
      _settings.blStockComparisonMode == 'machine' ? item.stockFinal : item.stockFinalTheorique;

  /// Contrôle et envoi de la quantité saisie dans la case d'une ligne.
  Future<void> _commitField(BonLivraisonItem item) async {
    final controller = _itemControllers[item.id];
    if (controller == null || _confirming.contains(item.id)) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;

    final saved = _provider.checkedQuantities[item.id];
    final quantity = int.tryParse(text);
    if (quantity == null || quantity < 0 || quantity > kBlMaxCountedQty) {
      if (_disposing) return;
      controller.text = saved?.toString() ?? '';
      if (mounted && !_disposing) {
        Constants.showSnackBar(context, 'Quantité refusée pour ${item.nomProduit} : de 0 à $kBlMaxCountedQty.', isError: true);
      }
      return;
    }

    // On vérifie si la valeur a changé par rapport à la base
    // pour ne pas envoyer de requêtes inutiles au serveur
    if (saved == quantity) return;

    if (isSuspiciousBlCount(counted: quantity, reference: _reference(item))) {
      // Écran fermé : pas de confirmation possible, rien n'est envoyé.
      if (!mounted || _disposing) return;
      _confirming.add(item.id);
      final ok = await _confirmEcart(item, quantity);
      _confirming.remove(item.id);
      if (!ok) {
        controller.text = saved?.toString() ?? '';
        return;
      }
    }
    // C'est cet appel qui va sauvegarder en base ET mettre la ligne en vert !
    if (_disposing) {
      // Pas de notification pendant la fermeture de l'écran : envoi juste après.
      final provider = _provider;
      Future.microtask(() => provider.updateCheckedQuantity(item.id, quantity));
    } else {
      _provider.updateCheckedQuantity(item.id, quantity);
    }
  }

  Future<bool> _confirmEcart(BonLivraisonItem item, int quantity) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber, color: Colors.orange.shade800, size: 40),
        title: const Text('Quantité inhabituelle'),
        content: Text('$quantity pour ${item.nomProduit}\n\n'
            'Cette quantité s\'écarte fortement du stock attendu. Vérifiez le comptage avant de confirmer.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Corriger')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('Confirmer $quantity')),
        ],
      ),
    );
    return ok == true;
  }

  void _onSearchChanged() {
    _applyFilters();
  }

  void _onSearchSubmitted(String value) {
    if (_filteredItems.length == 1) {
      _showQuickScanDialog(_filteredItems.first);
    } else if (value.trim().isNotEmpty && _filteredItems.isEmpty) {
      Constants.showSnackBar(context, 'Aucun produit de ce BL ne correspond à « ${value.trim()} ».', isError: true);
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase().trim();

    List<BonLivraisonItem> tempItems = _provider.items;

    if (_selectedEmplacement != null && _selectedEmplacement != _groupAllKey) {
      tempItems = tempItems.where((item) => item.zoneGeoName == _selectedEmplacement).toList();
    }

    if (query.isNotEmpty) {
      tempItems = tempItems.where((item) {
        return item.nomProduit.toLowerCase().contains(query) || item.cip.contains(query);
      }).toList();
    }

    setState(() {
      _filteredItems = tempItems;
    });
  }

  Future<void> _showQuickScanDialog(BonLivraisonItem item) async {
    final existingQty = _provider.checkedQuantities[item.id];
    final String initialValue = (existingQty != null && existingQty > 0) ? existingQty.toString() : "";

    final int? result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _QuantityInputDialog(
        item: item,
        initialValue: initialValue,
      ),
    );

    if (result == null || !mounted) return;
    if (isSuspiciousBlCount(counted: result, reference: _reference(item)) && !await _confirmEcart(item, result)) {
      if (mounted) _searchFocusNode.requestFocus();
      return;
    }
    if (!mounted) return;

    _provider.updateCheckedQuantity(item.id, result);

    if (_itemControllers.containsKey(item.id)) {
      _itemControllers[item.id]?.text = result.toString();
    }

    _searchController.clear();
    _searchFocusNode.requestFocus();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Quantité mise à jour : $result pour ${item.nomProduit}"),
        duration: const Duration(milliseconds: 800),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final bool canEdit = settingsProvider.canEditBlControl;

    return Consumer<BlControlProvider>(
      builder: (context, provider, child) {
        final bl = provider.selectedBonLivraison;
        if (bl == null) {
          return PresentationScaffold(
            style: style,
            title: 'Pointage BL',
            actions: (_) => const [],
            body: const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.receipt_long, size: 48, color: Pal.muted),
                SizedBox(height: 12),
                Text("Aucun BL sélectionné."),
              ]),
            ),
          );
        }

        final bool isGrouped = (_selectedEmplacement == _groupAllKey);

        List<BonLivraisonItem> itemsToDisplay;

        if (isGrouped) {
          final groupedItems = groupBy(_filteredItems, (BonLivraisonItem item) => item.zoneGeoName);
          final sortedKeys = groupedItems.keys.toList()..sort();

          final List<BonLivraisonItem> sortedGroupedItems = [];
          for (final key in sortedKeys) {
            final itemsInGroup = groupedItems[key] ?? [];
            itemsInGroup.sort((a, b) => a.nomProduit.compareTo(b.nomProduit));
            sortedGroupedItems.addAll(itemsInGroup);
          }
          itemsToDisplay = sortedGroupedItems;
        } else {
          itemsToDisplay = List.from(_filteredItems);
          itemsToDisplay.sort((a, b) => a.nomProduit.compareTo(b.nomProduit));
        }

        String filterName = "Tous";
        if (_selectedEmplacement != null && _selectedEmplacement != _groupAllKey) {
          filterName = "Emplacement $_selectedEmplacement";
        } else if (_selectedEmplacement == _groupAllKey) {
          filterName = "Tous (Groupés)";
        }

        final total = provider.items.length;
        final checked = provider.items.where((i) => provider.checkedQuantities.containsKey(i.id)).length;
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        final compact = style == ListPresentation.compact;

        return PresentationScaffold(
          style: style,
          title: bl.ref.trim().isEmpty ? 'BL —' : 'BL ${bl.ref}',
          subtitle: bl.grossiste.trim().isEmpty ? null : bl.grossiste,
          actions: (col) => [PresentationMenuButton(value: style, onChanged: _setStyle, color: col)],
          steps: const StepsBar(active: 1, steps: [
            (title: 'Choisir le BL', detail: 'liste', onTap: null),
            (title: 'Pointer', detail: 'scan, quantités', onTap: null),
            (title: 'Rapport', detail: 'écarts, impression', onTap: null),
          ]),
          header: [
            // Clavier ouvert : en-tête allégé pour laisser la place à la saisie.
            if (style == ListPresentation.dashboard && !keyboardOpen)
              Row(children: [
                Expanded(child: KpiTile('$checked/$total', 'pointés')),
                const SizedBox(width: 8),
                Expanded(child: KpiTile('${total - checked}', 'restants', highlight: true)),
                const SizedBox(width: 8),
                Expanded(child: KpiTile('${provider.emplacements.length}', 'emplacements')),
              ]),
            _buildProgress(checked, total, dark: true),
            _buildScanBar(dark: true),
          ],
          compactHeader: [
            _buildProgress(checked, total, dark: false),
            const SizedBox(height: 8),
            _buildScanBar(dark: false),
            const SizedBox(height: 8),
            _buildFilterBar(provider.isLoading, provider.emplacements),
          ],
          body: Column(
            children: [
              if (!compact)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: _buildFilterBar(provider.isLoading, provider.emplacements),
                ),
              if (provider.isLoading) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: itemsToDisplay.isEmpty
                    ? _empty(provider.isLoading)
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(compact ? 0 : 12, 6, compact ? 0 : 12, 16),
                        itemCount: itemsToDisplay.length,
                        itemBuilder: (context, index) {
                          final item = itemsToDisplay[index];

                          final bool isFirstInGroup =
                              isGrouped && (index == 0 || itemsToDisplay[index - 1].zoneGeoName != item.zoneGeoName);

                          BonLivraisonItem? nextItem;
                          if (index + 1 < itemsToDisplay.length) {
                            nextItem = itemsToDisplay[index + 1];
                          }

                          final isChecked = provider.checkedQuantities.containsKey(item.id);
                          final bool isEnabled = canEdit || !isChecked;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (isFirstInGroup)
                                Padding(
                                  padding: EdgeInsets.fromLTRB(compact ? 16 : 4, 14, 16, 6),
                                  child: Text(
                                    item.zoneGeoName.toUpperCase(),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.6, color: Pal.navy),
                                  ),
                                ),
                              _buildItemTile(context, item, nextItem, provider, isEnabled),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
          // Action principale toujours visible : le rapport du pointage.
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Pal.line))),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                child: Row(children: [
                  Expanded(
                    child: Text('$checked / $total lignes pointées',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      style: style == ListPresentation.guided ? amberButton : navyButton,
                      icon: const Icon(Icons.assessment),
                      label: const Text('Rapport'),
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => BlReportScreen(
                                  filteredItems: itemsToDisplay,
                                  filterName: filterName,
                                  presentation: style,
                                )));
                      },
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _empty(bool loading) => ListView(children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            const Icon(Icons.search_off, size: 48, color: Pal.muted),
            const SizedBox(height: 12),
            Text(loading ? 'Chargement des lignes...' : 'Aucun produit ne correspond.', textAlign: TextAlign.center),
            if (!loading && _searchController.text.isNotEmpty)
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  _searchFocusNode.requestFocus();
                },
                child: const Text('Effacer la recherche'),
              ),
          ]),
        ),
      ]);

  Widget _buildProgress(int done, int total, {required bool dark}) => Row(children: [
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
        Text('$done/$total lignes',
            style: TextStyle(fontSize: 12, color: dark ? Colors.white : Pal.ink, fontWeight: FontWeight.w500)),
      ]);

  Widget _buildScanBar({required bool dark}) => TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        textInputAction: TextInputAction.search,
        onSubmitted: _onSearchSubmitted,
        maxLength: 64,
        inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]'))],
        decoration: InputDecoration(
          hintText: 'Rechercher (Scan, Nom, CIP)',
          counterText: '',
          prefixIcon: const Icon(Icons.qr_code_scanner),
          suffixIcon: IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Effacer',
            onPressed: () {
              _searchController.clear();
              _searchFocusNode.requestFocus();
            },
          ),
          filled: true,
          fillColor: dark ? Colors.white : Pal.page,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      );

  Widget _buildFilterBar(bool isLoading, List<String> emplacements) {
    final deco = InputDecoration(
      labelText: 'Emplacement',
      prefixIcon: const Icon(Icons.place_outlined),
      isDense: true,
      filled: true,
      fillColor: isLoading ? Colors.grey.shade200 : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC5D0DE))),
    );
    if (isLoading) {
      return InputDecorator(
        decoration: deco,
        child: const Text('Chargement...', style: TextStyle(color: Colors.black54), overflow: TextOverflow.ellipsis),
      );
    }
    return DropdownButtonFormField<String>(
      value: _selectedEmplacement,
      hint: const Text('Aucun (Liste plate)'),
      isExpanded: true,
      decoration: deco,
      items: [
        const DropdownMenuItem<String>(
          value: null,
          child: Text('Aucun (Liste plate)', overflow: TextOverflow.ellipsis),
        ),
        const DropdownMenuItem<String>(
          value: _groupAllKey,
          child: Text('Tous (Groupés)', overflow: TextOverflow.ellipsis),
        ),
        ...emplacements.map((String value) {
          return DropdownMenuItem<String>(
            value: value,
            child: Text(value, overflow: TextOverflow.ellipsis),
          );
        }),
      ],
      onChanged: (String? newValue) {
        setState(() {
          _selectedEmplacement = newValue;
        });
        _applyFilters();
      },
    );
  }

  Widget _buildItemTile(BuildContext context, BonLivraisonItem item, BonLivraisonItem? nextItem, BlControlProvider provider, bool isEnabled) {
    final controller = _itemControllers[item.id];
    final focusNode = _itemFocusNodes[item.id];
    if (controller == null || focusNode == null) {
      return const SizedBox();
    }

    final isChecked = provider.checkedQuantities.containsKey(item.id);
    final statusColor = isEnabled ? (isChecked ? Pal.green : const Color(0xFF8A99AD)) : Colors.grey;
    final cip = item.cip.trim().isEmpty ? '—' : item.cip;

    final qtyField = SizedBox(
      width: 84,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: isEnabled,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.ink),
        decoration: InputDecoration(
          labelText: 'Qté',
          filled: true,
          fillColor: isEnabled ? Colors.white : Colors.grey.shade100,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: isChecked ? Pal.green : const Color(0xFFC5D0DE)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        ),
        // On ne sauvegarde pas à chaque chiffre tapé : l'enregistrement se fait à la perte du focus.
        onSubmitted: (_) {
          // Le fait de changer le focus ci-dessous déclenchera l'enregistrement
          // et la mise au vert de la ligne !
          if (nextItem != null && _itemFocusNodes[nextItem.id] != null) {
            FocusScope.of(context).requestFocus(_itemFocusNodes[nextItem.id]);
          } else {
            FocusScope.of(context).requestFocus(_searchFocusNode);
          }
        },
      ),
    );

    final row = Row(children: [
      Icon(isChecked ? Icons.check_circle : Icons.radio_button_unchecked, color: statusColor),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.nomProduit.trim().isEmpty ? '—' : item.nomProduit,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
          Text('CIP: $cip | PV: ${Constants.formatNumber(item.prixVente)}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
          Text('Empl: ${item.zoneGeoName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
        ]),
      ),
      const SizedBox(width: 8),
      qtyField,
    ]);

    final tint = isChecked ? (isEnabled ? const Color(0xFFF2FBF5) : Colors.grey.shade200) : Colors.white;
    switch (style) {
      case ListPresentation.compact:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: tint, border: const Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
          child: row,
        );
      case ListPresentation.dashboard:
      case ListPresentation.guided:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(16),
              border: style == ListPresentation.guided
                  ? Border(left: BorderSide(color: isChecked ? Pal.green : Pal.line, width: 5))
                  : null,
              boxShadow: const [BoxShadow(color: Color(0x1214213D), blurRadius: 8, offset: Offset(0, 2))],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: row,
          ),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// FENÊTRE DE SAISIE RAPIDE (après un scan qui ne trouve qu'un produit)
// ---------------------------------------------------------------------------
class _QuantityInputDialog extends StatefulWidget {
  final BonLivraisonItem item;
  final String initialValue;

  const _QuantityInputDialog({
    required this.item,
    required this.initialValue,
  });

  @override
  State<_QuantityInputDialog> createState() => _QuantityInputDialogState();
}

class _QuantityInputDialogState extends State<_QuantityInputDialog> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  String? _errorText;
  bool _closing = false;

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
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    }
  }

  void _close([int? value]) {
    if (_closing) return; // pas de double validation
    _closing = true;
    Navigator.of(context).pop(value);
  }

  void _validate() {
    final text = _controller.text.trim();

    if (text.isEmpty) {
      _close(0);
      return;
    }

    final value = int.tryParse(text);

    if (value == null || value < 0 || value > kBlMaxCountedQty) {
      setState(() {
        _errorText = "Mauvaise valeur : de 0 à $kBlMaxCountedQty";
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.item.nomProduit, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("CIP: ${widget.item.cip}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 20),
          const Text("Saisir la quantité comptée :"),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              errorText: _errorText,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(vertical: 15),
            ),
            onChanged: (val) {
              if (_errorText != null) {
                setState(() => _errorText = null);
              }
            },
            onSubmitted: (_) => _validate(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => _close(), child: const Text("Annuler")),
        ElevatedButton(
          style: navyButton,
          onPressed: _validate,
          child: const Text("Valider"),
        )
      ],
    );
  }
}
