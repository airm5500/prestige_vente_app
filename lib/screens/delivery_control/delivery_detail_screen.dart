// lib/screens/delivery_control/delivery_detail_screen.dart
// 10/10/2026 : présentations A/B/C, progression, filtres, quantités contrôlées bornées.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/commande_item.dart';
import 'package:prestige_vente_app/providers/delivery_control_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/delivery_control/delivery_report_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';
import 'package:provider/provider.dart';

/// Quantité contrôlée maximale acceptée (au-delà : scan de code-barres ou faute de frappe).
const int maxCheckedQuantity = 10000;

/// Quantité contrôlée saisie : entier de 0 à [maxCheckedQuantity], sinon null.
int? parseCheckedQuantity(String text) {
  final t = text.trim();
  if (t.isEmpty || !RegExp(r'^\d+$').hasMatch(t)) return null;
  final v = int.tryParse(t);
  if (v == null || v < 0 || v > maxCheckedQuantity) return null;
  return v;
}

const String _qtyError = 'Quantité invalide : nombre entier de 0 à 10 000.';

class DeliveryDetailScreen extends StatefulWidget {
  /// Présentation reçue de la liste ; sinon celle choisie sur l'appareil.
  final ListPresentation? presentation;
  const DeliveryDetailScreen({super.key, this.presentation});

  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

enum _Filter { all, todo, checked, gap }

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  final Map<String, FocusNode> _itemFocusNodes = {};
  final Map<String, TextEditingController> _itemControllers = {};

  late final DeliveryControlProvider _provider;
  _Filter _filter = _Filter.all;
  bool _dialogOpen = false;

  static const _filterLabels = {
    _Filter.all: 'Tous',
    _Filter.todo: 'À contrôler',
    _Filter.checked: 'Contrôlés',
    _Filter.gap: 'Écarts',
  };

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _provider = Provider.of<DeliveryControlProvider>(context, listen: false);
    _initializeControllers(_provider);

    _searchController.addListener(_filterList);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(_searchFocusNode);
    });
  }

  void _initializeControllers(DeliveryControlProvider provider) {
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
              controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
            });
          } else {
            // --- SÉCURITÉ : SAUVEGARDE À LA PERTE DU FOCUS ---
            // On ne sauvegarde que quand l'utilisateur valide (Entrée) ou clique ailleurs.
            _commit(item, controller);
          }
        });

        _itemFocusNodes[item.id] = focusNode;
        _itemControllers[item.id] = controller;
      }
    }
  }

  /// Enregistre la quantité saisie si elle est valide et différente ; sinon remet l'ancienne.
  void _commit(CommandeItem item, TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    final currentSaved = _provider.checkedQuantities[item.id];
    final quantity = parseCheckedQuantity(text);
    if (quantity == null) {
      controller.text = currentSaved?.toString() ?? '';
      _toast('$_qtyError (${item.nomProduit})', error: true);
      return;
    }
    // On vérifie si la valeur a changé pour ne pas spammer le serveur
    if (currentSaved != quantity) {
      _provider.updateCheckedQuantity(item.id, quantity).then((ok) {
        if (!ok && mounted) showUnsyncedSnack(context);
      });
    }
  }

  bool _leaving = false;

  /// Retour : enregistre la case en cours, attend les envois, prévient s'il reste des quantités non enregistrées.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    final canLeave = await confirmLeaveWithUnsynced(context, _provider, _provider.retryUnsyncedQuantities);
    if (!mounted) return;
    if (!canLeave) {
      _leaving = false;
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _retryUnsynced() async {
    final left = await _provider.retryUnsyncedQuantities();
    if (!mounted) return;
    _toast(left == 0 ? 'Quantités enregistrées.' : '$left quantité(s) toujours non enregistrée(s). Vérifiez le réseau.', error: left > 0);
  }

  void _toast(String message, {bool error = false, Duration? duration}) {
    if (!mounted) return;
    try {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : null,
        duration: duration ?? const Duration(seconds: 2),
      ));
    } catch (_) {
      // Écran en cours de fermeture : rien à afficher.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _itemFocusNodes.forEach((_, node) => node.dispose());
    _itemControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  void _filterList() {
    if (mounted) setState(() {});
  }

  /// Lignes correspondant à la recherche (nom ou CIP).
  List<CommandeItem> _searched(DeliveryControlProvider provider) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return provider.items;
    return provider.items.where((item) => item.nomProduit.toLowerCase().contains(query) || item.cip.contains(query)).toList();
  }

  bool _hasGap(DeliveryControlProvider provider, CommandeItem item) {
    final q = provider.checkedQuantities[item.id];
    return q != null && q != item.qteCommandee;
  }

  List<CommandeItem> _visible(DeliveryControlProvider provider) => _searched(provider).where((item) {
        final checked = provider.checkedQuantities.containsKey(item.id);
        return switch (_filter) {
          _Filter.all => true,
          _Filter.todo => !checked,
          _Filter.checked => checked,
          _Filter.gap => _hasGap(provider, item),
        };
      }).toList();

  // --- LOGIQUE SCAN RAPIDE ---
  void _onSearchSubmitted(String val) {
    final found = _searched(_provider);
    if (found.length == 1) {
      _showQuickScanDialog(found.first);
    } else if (found.isEmpty && val.trim().isNotEmpty) {
      _toast('Aucun produit de la commande ne correspond à « ${val.trim()} ».', error: true);
      _searchFocusNode.requestFocus();
    }
  }

  Future<void> _showQuickScanDialog(CommandeItem item) async {
    if (_dialogOpen) return;
    final provider = _provider;
    final canEdit = Provider.of<SettingsProvider>(context, listen: false).canEditDeliveryControl;
    if (!canEdit && provider.checkedQuantities.containsKey(item.id)) {
      _toast('Produit déjà contrôlé : modification non autorisée.', error: true);
      return;
    }

    // Récupération de la quantité actuelle
    final currentQty = provider.checkedQuantities[item.id] ?? 0;
    final String initialValue = currentQty > 0 ? currentQty.toString() : "";

    _dialogOpen = true;
    final int? result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _QuantityInputDialog(
        nomProduit: item.nomProduit,
        cip: item.cip,
        qteCommandee: item.qteCommandee,
        initialValue: initialValue,
      ),
    );
    _dialogOpen = false;
    if (!mounted) return;

    if (result != null) {
      provider.updateCheckedQuantity(item.id, result).then((ok) {
        if (!ok && mounted) showUnsyncedSnack(context);
      });
      _itemControllers[item.id]?.text = result.toString();

      // Reset pour enchaîner
      _searchController.clear();
      _searchFocusNode.requestFocus();
      _toast("Quantité mise à jour : ${item.nomProduit}", duration: const Duration(milliseconds: 800));
    }
  }

  void _openReport() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeliveryReportScreen(presentation: style)));
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    final bool canEdit = settingsProvider.canEditDeliveryControl;

    return Consumer<DeliveryControlProvider>(
      builder: (context, provider, child) {
        final commande = provider.selectedCommande;
        if (commande == null) {
          return PresentationScaffold(
            style: style,
            title: 'Contrôle Livraison',
            actions: (_) => const [],
            body: const Center(child: Text("Aucune commande sélectionnée.")),
          );
        }

        final total = provider.items.length;
        final checked = provider.items.where((i) => provider.checkedQuantities.containsKey(i.id)).length;
        final gaps = provider.items.where((i) => _hasGap(provider, i)).length;
        final remaining = total - checked;
        final completed = provider.isCurrentOrderCompleted;
        final visible = _visible(provider);
        final compact = style == ListPresentation.compact;
        final guided = style == ListPresentation.guided;
        final title = commande.ref.trim().isEmpty ? 'Commande' : commande.ref;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _leave();
          },
          child: PresentationScaffold(
          style: style,
          title: title,
          subtitle: commande.grossiste.trim().isEmpty ? null : commande.grossiste,
          actions: (col) => [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: col, disabledForegroundColor: col.withValues(alpha: 0.4)),
              icon: const Icon(Icons.assessment),
              label: const Text('Rapport'),
              onPressed: completed ? _openReport : null,
            ),
          ],
          steps: StepsBar(active: completed ? 2 : 1, steps: [
            (title: 'Commande', detail: title, onTap: () => Navigator.of(context).maybePop()),
            (title: 'Contrôle', detail: '$checked / $total lignes', onTap: null),
            (title: 'Rapport', detail: '$gaps écart(s)', onTap: completed ? _openReport : null),
          ]),
          header: [
            if (!guided)
              Row(children: [
                Expanded(child: KpiTile('$checked/$total', 'contrôlées', highlight: true)),
                const SizedBox(width: 6),
                Expanded(child: KpiTile('$remaining', 'à contrôler')),
                const SizedBox(width: 6),
                Expanded(child: KpiTile('$gaps', 'écart(s)')),
              ]),
            _buildSearchBar(dark: true),
          ],
          compactHeader: [
            _buildSearchBar(dark: false),
            const SizedBox(height: 6),
            LightFigures([
              ('$checked/$total', 'Contrôlées', Pal.green),
              ('$remaining', 'À contrôler', Pal.navy),
              ('$gaps', 'Écarts', gaps > 0 ? AppColors.error : Pal.muted),
            ]),
          ],
          body: Column(
            children: [
              if (provider.isLoading) const LinearProgressIndicator(minHeight: 2),
              UnsyncedBanner(count: provider.unsyncedCount, retrying: provider.isRetrying, onRetry: _retryUnsynced),
              Padding(
                padding: EdgeInsets.fromLTRB(compact ? 16 : 12, 10, compact ? 16 : 12, 0),
                child: ThinProgress(
                  value: total == 0 ? 0 : checked / total,
                  left: 'Progression du contrôle',
                  right: '$checked / $total',
                  color: completed ? Pal.green : Pal.blue,
                ),
              ),
              _filterChips(provider),
              Expanded(
                child: visible.isEmpty
                    ? _empty(provider)
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(compact ? 0 : 12, 4, compact ? 0 : 12, 16),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final item = visible[index];
                          final nextItem = (index + 1 < visible.length) ? visible[index + 1] : null;
                          final isChecked = provider.checkedQuantities.containsKey(item.id);
                          final bool isEnabled = canEdit || !isChecked;
                          return _buildItemTile(context, item, nextItem, provider, isEnabled);
                        },
                      ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  style: guided ? amberButton : navyButton,
                  icon: Icon(completed ? Icons.assessment : Icons.hourglass_bottom),
                  label: Text(
                    completed ? 'Voir le rapport' : '$remaining ligne(s) à contrôler',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: completed ? _openReport : null,
                ),
              ),
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _filterChips(DeliveryControlProvider provider) {
    final searched = _searched(provider);
    int count(_Filter f) => switch (f) {
          _Filter.all => searched.length,
          _Filter.todo => searched.where((i) => !provider.checkedQuantities.containsKey(i.id)).length,
          _Filter.checked => searched.where((i) => provider.checkedQuantities.containsKey(i.id)).length,
          _Filter.gap => searched.where((i) => _hasGap(provider, i)).length,
        };
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(style == ListPresentation.compact ? 16 : 12, 6, 12, 0),
        children: [
          for (final f in _Filter.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${_filterLabels[f]} (${count(f)})'),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty(DeliveryControlProvider provider) {
    final String text;
    if (provider.items.isEmpty) {
      text = provider.isLoading ? 'Chargement des produits…' : 'Aucun produit dans cette commande.';
    } else if (_searchController.text.trim().isNotEmpty) {
      text = 'Aucun produit ne correspond à la recherche.';
    } else {
      text = switch (_filter) {
        _Filter.todo => 'Tous les produits sont contrôlés.',
        _Filter.gap => 'Aucun écart pour le moment.',
        _ => 'Aucun produit à afficher.',
      };
    }
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          Icon(Icons.fact_check_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: Pal.ink)),
          const SizedBox(height: 8),
          if (_filter != _Filter.all || _searchController.text.isNotEmpty)
            OutlinedButton(
              style: outlineButton,
              onPressed: () {
                _searchController.clear();
                setState(() => _filter = _Filter.all);
              },
              child: const Text('Afficher tous les produits'),
            ),
        ]),
      ),
    ]);
  }

  Widget _buildSearchBar({required bool dark}) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      textInputAction: TextInputAction.search, // Important pour le déclenchement
      onSubmitted: _onSearchSubmitted, // Appel de la fonction de scan
      inputFormatters: [LengthLimitingTextInputFormatter(60)],
      decoration: InputDecoration(
        hintText: 'Rechercher ou Scanner (Nom, CIP)',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: dark ? Colors.white : Pal.page,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        suffixIcon: IconButton(
          icon: const Icon(Icons.clear),
          tooltip: 'Effacer',
          onPressed: () {
            _searchController.clear();
            _searchFocusNode.requestFocus();
          },
        ),
      ),
    );
  }

  Widget _buildItemTile(BuildContext context, CommandeItem item, CommandeItem? nextItem, DeliveryControlProvider provider, bool isEnabled) {
    final controller = _itemControllers[item.id];
    final focusNode = _itemFocusNodes[item.id];
    if (controller == null || focusNode == null) return const SizedBox();

    final isChecked = provider.checkedQuantities.containsKey(item.id);
    final checkedQty = provider.checkedQuantities[item.id];
    final gap = checkedQty == null ? 0 : checkedQty - item.qteCommandee;
    final name = item.nomProduit.trim().isEmpty ? '—' : item.nomProduit;
    final cip = item.cip.trim().isEmpty ? '—' : item.cip;
    final statusColor = !isChecked ? Colors.grey : (gap != 0 ? Colors.orange.shade800 : AppColors.success);

    final field = SizedBox(
      width: 92,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: isEnabled,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: 'Qté reçue',
          isDense: true,
          filled: !isEnabled,
          fillColor: Colors.grey.shade200,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onSubmitted: (_) {
          // Le changement de focus valide l'input et déclenche la sauvegarde
          // (via le listener focusNode défini dans l'initState)
          if (nextItem != null && _itemFocusNodes[nextItem.id] != null) {
            FocusScope.of(context).requestFocus(_itemFocusNodes[nextItem.id]);
          } else {
            FocusScope.of(context).requestFocus(_searchFocusNode);
          }
        },
      ),
    );

    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink)),
      Text('CIP: $cip | Qté Cmd: ${item.qteCommandee}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
      if (isChecked && gap != 0)
        Text('Écart : ${gap > 0 ? '+' : ''}$gap', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange.shade900)),
      if (!isEnabled) const Text('Contrôlé (verrouillé)', style: TextStyle(fontSize: 12, color: Pal.muted)),
    ]);

    final row = Row(children: [
      Icon(isChecked ? Icons.check_circle : Icons.radio_button_unchecked, color: isEnabled ? statusColor : Colors.grey),
      const SizedBox(width: 10),
      Expanded(child: info),
      LineSyncMark(unsynced: provider.isUnsynced(item.id), sending: provider.isSending(item.id)),
      const SizedBox(width: 4),
      field,
    ]);

    switch (style) {
      case ListPresentation.compact:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isChecked && !isEnabled ? Colors.grey.shade100 : null,
            border: const Border(bottom: BorderSide(color: Color(0xFFEEF1F5))),
          ),
          child: row,
        );
      case ListPresentation.guided:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SoftCard(band: isChecked ? statusColor : Pal.line, padding: const EdgeInsets.all(12), child: row),
        );
      case ListPresentation.dashboard:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SoftCard(highlighted: isChecked && gap == 0, padding: const EdgeInsets.all(12), child: row),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// WIDGET POPUP SÉCURISÉ
// ---------------------------------------------------------------------------
class _QuantityInputDialog extends StatefulWidget {
  final String nomProduit;
  final String cip;
  final int qteCommandee;
  final String initialValue;

  const _QuantityInputDialog({
    required this.nomProduit,
    required this.cip,
    required this.qteCommandee,
    required this.initialValue,
  });

  @override
  State<_QuantityInputDialog> createState() => _QuantityInputDialogState();
}

class _QuantityInputDialogState extends State<_QuantityInputDialog> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  String? _errorText;

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

  void _validate() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      Navigator.of(context).pop(0);
      return;
    }

    // SÉCURITÉ ANTI-SCAN & COHÉRENCE
    final value = parseCheckedQuantity(text);
    if (value == null) {
      setState(() => _errorText = 'Mauvaise valeur : 0 à 10 000 maximum');
      _selectAllText();
      _focusNode.requestFocus();
    } else {
      Navigator.of(context).pop(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(widget.nomProduit,
          maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.ink)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("CIP: ${widget.cip}", style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.muted)),
            Text("Qté commandée : ${widget.qteCommandee}", style: const TextStyle(color: Pal.muted)),
            const SizedBox(height: 16),
            const Text("Saisir la quantité comptée :"),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
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
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Annuler")),
        ElevatedButton(style: navyButton, onPressed: _validate, child: const Text("Valider")),
      ],
    );
  }
}
