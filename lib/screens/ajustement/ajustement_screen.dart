// lib/screens/ajustement/ajustement_screen.dart
// Ajustement de stock, en trois présentations (A, B, C). Chaque ligne n'apparaît qu'après
// confirmation du serveur ; la clôture est confirmée avec un récapitulatif.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/api/api_service.dart' show ApiLoadException;
import 'package:prestige_vente_app/providers/ajustement_provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/ajustement.dart';
import 'package:prestige_vente_app/services/pdf_ajustement_service.dart';
import 'package:prestige_vente_app/screens/common/product_search_modal.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/sync_status.dart';

/// Quantité maximale d'une ligne (au-delà : erreur de saisie ou de scan probable).
const int kAjustementQteMax = 9999;

/// Au-delà, une confirmation est demandée (règle existante).
const int kAjustementQteAlerte = 50;

const Color _red = Color(0xFFDC2626);

class AjustementScreen extends StatefulWidget {
  /// Présentation (A, B, C) ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;

  /// Impression du bon, remplaçable pour les tests. Par défaut : [PdfAjustementService].
  final Future<void> Function(List<AjustementItem> items, String userName)? printTicket;

  const AjustementScreen({super.key, this.presentation, this.printTicket});

  @override
  State<AjustementScreen> createState() => _AjustementScreenState();
}

class _AjustementScreenState extends State<AjustementScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _keyboardFocusNode = FocusNode();

  Timer? _debounce;
  bool _isProcessing = false;
  bool _isModalOpen = false; // Verrou anti-doublon
  bool _isDialogOpen = false; // dialogue de quantité ouvert
  bool _closing = false; // clôture en cours (confirmation + envoi)
  bool _printing = false; // impression en cours (pas de double impression)
  int? _lastMotifId; // dernier motif choisi (proposé par défaut)

  // Dernier ajustement validé (pour imprimer le bon plus tard).
  List<AjustementItem>? _lastValidated;
  String _lastValidatedUser = '';

  String _scanBuffer = "";

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _searchController.addListener(_onSearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<AjustementProvider>(context, listen: false).loadTypesAjustement();
      _requestSearchFocus();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.dispose();
    _keyboardFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  void _requestSearchFocus() {
    if (mounted && !_isProcessing && !_isModalOpen && !_isDialogOpen) {
      FocusScope.of(context).requestFocus(_focusNode);
    }
  }

  void _snack(String text, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  // --- GESTION DOUCHETTE / CLAVIER PHYSIQUE ---
  void _handleKeyEvent(KeyEvent event) {
    if (_focusNode.hasFocus) {
      _scanBuffer = "";
      return;
    }

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_scanBuffer.isNotEmpty) {
          // C'est un scan : on lance la recherche directe (isScan: true)
          _performSearch(_scanBuffer.trim(), isScan: true);
          _scanBuffer = "";
        }
      } else if (event.character != null && _scanBuffer.length < 64) {
        _scanBuffer += event.character!;
      }
    }
  }

  // --- DÉTECTION DE SAISIE MANUELLE ---
  void _onSearchChanged() {
    if (_isProcessing || _isModalOpen) return;

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // Délai de 800ms pour laisser le temps de taper
    _debounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted || _isProcessing || _isModalOpen) return;

      final text = _searchController.text.trim();

      // On ne lance rien si moins de 3 caractères
      if (text.length >= 3) {
        _performSearch(text, isScan: false);
      }
    });
  }

  /// Une ligne peut-elle être ajoutée maintenant ? Sinon, explique pourquoi.
  bool _canAddLine() {
    final provider = Provider.of<AjustementProvider>(context, listen: false);
    if (provider.isLoading || _closing) {
      _snack("Envoi en cours, patientez avant d'ajouter une ligne.");
      return false;
    }
    if (provider.typesAjustement.isEmpty) {
      // Le motif est obligatoire pour le serveur.
      _snack(
        provider.typesLoading
            ? "Chargement des motifs en cours, patientez."
            : "Motifs d'ajustement non chargés : impossible d'ajouter une ligne. Touchez « Réessayer ».",
        color: provider.typesLoading ? null : Colors.red.shade700,
      );
      return false;
    }
    return true;
  }

  // --- OUVERTURE DU MODAL DE RECHERCHE CONTINUE ---
  void _openSearchModal(String currentQuery) {
    if (_isModalOpen) return;
    if (!_canAddLine()) return;

    setState(() {
      _isModalOpen = true;
      _isProcessing = false;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (ctx) => ProductSearchModal(
        initialQuery: currentQuery,
        onProductSelected: (selectedProduct) {
          // Au retour, on vide le champ et on ouvre le DIALOG DE QUANTITÉ
          _searchController.clear();

          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) _showAddDialog(selectedProduct);
          });
        },
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isModalOpen = false);
        _searchController.clear();
        _requestSearchFocus();
      }
    });
  }

  // --- CŒUR DE LA RECHERCHE ---
  Future<void> _performSearch(String query, {required bool isScan}) async {
    _debounce?.cancel();
    if (query.isEmpty) return;
    if (_isModalOpen || _isDialogOpen || _isProcessing) return;

    // 1. CAS DU SCANNER PHYSIQUE (Code exact)
    if (isScan) {
      if (!_canAddLine()) return;
      setState(() => _isProcessing = true);
      final provider = Provider.of<AjustementProvider>(context, listen: false);
      try {
        final List<ProductSearchResult> results;
        try {
          results = await provider.searchProductForScan(query);
        } on ApiLoadException catch (e) {
          _snack(e.message, color: Colors.red.shade700);
          return;
        }
        if (!mounted) return;

        if (results.length == 1) {
          // Scan exact -> On ouvre direct le Dialog Quantité (Pas d'ajout auto +1)
          _searchController.clear();
          setState(() => _isProcessing = false);
          _showAddDialog(results.first);
        } else if (results.isNotEmpty) {
          // Plusieurs résultats (ex: code court) -> On laisse choisir
          setState(() => _isProcessing = false);
          _openSearchModal(query);
        } else {
          _snack("Produit introuvable : $query");
        }
      } finally {
        if (mounted) {
          setState(() => _isProcessing = false);
          if (!_isModalOpen) _requestSearchFocus();
        }
      }
      return;
    }

    // 2. CAS DE LA SAISIE MANUELLE : on ouvre le modal pour continuer la saisie
    _openSearchModal(query);
  }

  // --- DIALOGUE QUANTITÉ / MOTIF ---
  Future<void> _showAddDialog(ProductSearchResult product) async {
    if (_isDialogOpen) return;
    if (!_canAddLine()) return;
    final provider = Provider.of<AjustementProvider>(context, listen: false);
    final types = provider.typesAjustement;
    final initialMotif = types.any((t) => t.id == _lastMotifId) ? _lastMotifId! : types.first.id;

    setState(() => _isDialogOpen = true);
    final result = await showDialog<_AddResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ChangeNotifierProvider<AjustementProvider>.value(
        value: provider,
        child: _AddLineDialog(product: product, initialMotifId: initialMotif),
      ),
    );
    if (!mounted) return;
    setState(() => _isDialogOpen = false);
    _searchController.clear();
    if (result != null) {
      _lastMotifId = result.motifId;
      final sign = result.quantity > 0 ? '+' : '';
      _snack("Ligne enregistrée : ${product.strNAME} ($sign${result.quantity})", color: Pal.green);
    }
    _requestSearchFocus();
  }

  // --- CLÔTURE ---
  Future<void> _validateAjustement() async {
    if (_closing) return; // pas de double validation
    final provider = Provider.of<AjustementProvider>(context, listen: false);
    if (provider.isLoading || provider.items.isEmpty) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    setState(() => _closing = true);
    try {
      final items = List<AjustementItem>.from(provider.items);
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => _CloseConfirmDialog(items: items),
      );
      if (!mounted || confirm != true) return;

      final List<AjustementItem> itemsToPrint = items;
      final String userName = authProvider.user?.fullName ?? "Inconnu";

      final success = await provider.validateAjustement();
      if (!mounted) return;

      if (!success) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(Icons.error_outline, color: Colors.red.shade700, size: 36),
            title: const Text("Ajustement NON validé"),
            content: Text(provider.errorMessage ?? "Le serveur n'a pas confirmé la clôture. Réessayez."),
            actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
          ),
        );
        return;
      }

      setState(() {
        _lastValidated = itemsToPrint;
        _lastValidatedUser = userName;
      });
      _snack("Ajustement validé !", color: Pal.green);

      final bool? wantToPrint = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("Impression"),
          content: const Text("Terminé.\nVoulez-vous imprimer le bon ?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Non, terminer"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Oui, imprimer"),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (wantToPrint == true) await _print(itemsToPrint, userName);
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Future<void> _print(List<AjustementItem> items, String userName) async {
    if (_printing) return; // pas de double impression
    setState(() => _printing = true);
    try {
      final printer = widget.printTicket ?? PdfAjustementService().printAjustementTicket;
      await printer(items, userName);
    } catch (e) {
      _snack("Erreur PDF: $e", color: Colors.red);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  // --- QUITTER AVEC DES LIGNES NON CLÔTURÉES ---
  Future<void> _onPopBlocked() async {
    final provider = Provider.of<AjustementProvider>(context, listen: false);
    if (provider.isLoading || _closing) {
      _snack("Envoi en cours, patientez avant de quitter.");
      return;
    }
    final n = provider.items.length;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Ajustement non clôturé"),
        content: Text(
          "${n == 1 ? '1 ligne saisie n\'est' : '$n lignes saisies ne sont'} pas encore validée${n == 1 ? '' : 's'} "
          "(ajustement non clôturé).\n\nPour valider, restez et touchez « CLÔTURER AJUSTEMENT ».",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Quitter quand même")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Rester")),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AjustementProvider>(context);
    final items = provider.items;
    final totals = _Totals.of(items);
    final busy = provider.isLoading || _closing;
    final guided = style == ListPresentation.guided;

    return PopScope(
      canPop: items.isEmpty && !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPopBlocked();
      },
      child: KeyboardListener(
        focusNode: _keyboardFocusNode,
        onKeyEvent: _handleKeyEvent,
        child: PresentationScaffold(
          style: style,
          title: "Ajustement de Stock",
          subtitle: style == ListPresentation.compact ? null : "Scannez ou recherchez un produit",
          actions: (c) => [
            if (provider.currentAjustementId != null)
              IconButton(
                tooltip: 'Actualiser les lignes',
                icon: Icon(Icons.refresh, color: c),
                onPressed: provider.itemsLoading ? null : provider.refreshItems,
              ),
            PresentationMenuButton(value: style, onChanged: _setStyle, color: c),
          ],
          steps: StepsBar(active: items.isEmpty ? 0 : 1, steps: [
            (title: 'Produit', detail: 'scan ou recherche', onTap: null),
            (title: 'Lignes', detail: '${items.length} saisie${items.length > 1 ? 's' : ''}', onTap: null),
            (title: 'Clôturer', detail: 'valider + bon', onTap: null),
          ]),
          header: [
            _buildSearchBar(dark: true),
            Row(children: [
              Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: KpiTile('${items.length}', 'Lignes'))),
              const SizedBox(width: 8),
              Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: KpiTile('+${totals.entrees}', 'Entrées'))),
              const SizedBox(width: 8),
              Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: KpiTile('−${totals.sorties}', 'Sorties'))),
            ]),
          ],
          compactHeader: [
            _buildSearchBar(dark: false),
            LightFigures([
              ('${items.length}', 'lignes', Pal.ink),
              ('+${totals.entrees}', 'entrées', Pal.green),
              ('−${totals.sorties}', 'sorties', _red),
            ]),
          ],
          body: Column(children: [
            if (provider.isLoading || provider.itemsLoading || provider.typesLoading) const LinearProgressIndicator(minHeight: 2),
            if (provider.typesError != null && provider.typesAjustement.isEmpty)
              LoadErrorBanner(
                message: provider.typesError!,
                onRetry: provider.typesLoading ? null : provider.loadTypesAjustement,
              ),
            if (provider.itemsError != null)
              LoadErrorBanner(
                message: "Lignes non rechargées : ${provider.itemsError}",
                onRetry: provider.itemsLoading ? null : provider.refreshItems,
              ),
            if (_lastValidated != null && items.isEmpty) _buildLastValidated(),
            Expanded(child: items.isEmpty ? _buildEmpty() : _buildList(items)),
          ]),
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: style == ListPresentation.compact ? Colors.white : null,
                border: style == ListPresentation.compact ? const Border(top: BorderSide(color: Pal.line)) : null,
              ),
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  style: guided ? amberButton : navyButton,
                  icon: provider.isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_circle),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(items.isEmpty ? "CLÔTURER AJUSTEMENT" : "CLÔTURER AJUSTEMENT (${items.length})"),
                  ),
                  onPressed: items.isEmpty || busy ? null : _validateAjustement,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar({required bool dark}) {
    return TextField(
      controller: _searchController,
      focusNode: _focusNode,
      inputFormatters: [
        FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]')),
        LengthLimitingTextInputFormatter(50),
      ],
      decoration: InputDecoration(
        hintText: "Scanner ou Rechercher (min 3 car.)",
        prefixIcon: _isProcessing
            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            : const Icon(Icons.search),
        suffixIcon: IconButton(
          icon: const Icon(Icons.clear),
          tooltip: 'Effacer',
          onPressed: () {
            _searchController.clear();
            _requestSearchFocus();
          },
        ),
        filled: true,
        fillColor: dark ? Colors.white : Pal.page,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      // Pour le clavier virtuel : lance la recherche quand on fait "Entrée"
      onSubmitted: (val) {
        final q = val.trim();
        if (q.isNotEmpty) _performSearch(q, isScan: false);
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.inventory_2_outlined, size: 44, color: Pal.muted),
          const SizedBox(height: 12),
          const Text("Aucun ajustement en cours", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.ink)),
          const SizedBox(height: 6),
          const Text(
            "Scannez un produit ou saisissez au moins 3 caractères pour ajouter une ligne.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Pal.muted),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: outlineButton,
            icon: const Icon(Icons.search),
            label: const Text("Rechercher un produit"),
            onPressed: () => _openSearchModal(_searchController.text.trim()),
          ),
        ]),
      ),
    );
  }

  Widget _buildLastValidated() {
    final n = _lastValidated!.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SoftCard(
        band: style == ListPresentation.guided ? Pal.green : null,
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(children: [
          const Icon(Icons.check_circle, color: Pal.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Dernier ajustement validé ($n ligne${n > 1 ? 's' : ''})",
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Pal.ink, fontWeight: FontWeight.w600),
            ),
          ),
          _printing
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : TextButton.icon(
                  icon: const Icon(Icons.print),
                  label: const Text("Imprimer"),
                  onPressed: () => _print(_lastValidated!, _lastValidatedUser),
                ),
        ]),
      ),
    );
  }

  Widget _buildList(List<AjustementItem> items) {
    if (style == ListPresentation.compact) {
      return ListView.separated(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Pal.line, indent: 16, endIndent: 16),
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: _LineContent(item: items[i]),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final item = items[i];
        return SoftCard(
          band: style == ListPresentation.guided ? (item.intNUMBER >= 0 ? Pal.green : _red) : null,
          child: _LineContent(item: item),
        );
      },
    );
  }
}

/// Totaux des entrées (+) et sorties (−) en unités.
class _Totals {
  final int entrees;
  final int sorties;
  final int lignesEntree;
  final int lignesSortie;
  const _Totals(this.entrees, this.sorties, this.lignesEntree, this.lignesSortie);

  static _Totals of(List<AjustementItem> items) {
    var e = 0, s = 0, le = 0, ls = 0;
    for (final i in items) {
      if (i.intNUMBER > 0) {
        e += i.intNUMBER;
        le++;
      } else if (i.intNUMBER < 0) {
        s += -i.intNUMBER;
        ls++;
      }
    }
    return _Totals(e, s, le, ls);
  }
}

String _signed(int n) => n > 0 ? '+$n' : (n < 0 ? '−${-n}' : '0');

/// Contenu d'une ligne : produit, stock actuel → nouveau, écart signé en couleur, motif.
class _LineContent extends StatelessWidget {
  final AjustementItem item;
  const _LineContent({required this.item});

  @override
  Widget build(BuildContext context) {
    final positive = item.intNUMBER >= 0;
    final color = positive ? Pal.green : _red;
    final name = item.strNAME.trim().isEmpty ? '—' : item.strNAME;
    final cip = item.intCIP.trim().isEmpty ? '—' : item.intCIP;
    final motif = item.motifAjustement.trim().isEmpty ? '—' : item.motifAjustement;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Pal.ink)),
          const SizedBox(height: 2),
          Text("CIP $cip · $motif", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Pal.muted)),
          const SizedBox(height: 6),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
            const Text("Stock", style: TextStyle(fontSize: 12, color: Pal.muted)),
            Text('${item.intNUMBERCURRENTSTOCK}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Pal.ink)),
            const Icon(Icons.arrow_forward, size: 14, color: Pal.muted),
            Text('${item.intNUMBERAFTERSTOCK}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          ]),
        ]),
      ),
      const SizedBox(width: 8),
      Container(
        constraints: const BoxConstraints(minWidth: 56),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Text(
          _signed(item.intNUMBER),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
      ),
    ]);
  }
}

/// Confirmation de clôture avec récapitulatif.
class _CloseConfirmDialog extends StatelessWidget {
  final List<AjustementItem> items;
  const _CloseConfirmDialog({required this.items});

  @override
  Widget build(BuildContext context) {
    final t = _Totals.of(items);
    final n = items.length;
    Widget row(String label, String value, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(color: Pal.muted))),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
          ]),
        );
    return AlertDialog(
      title: const Text("Confirmer l'ajustement"),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text("Clôturer cet ajustement de $n ligne${n > 1 ? 's' : ''} ?"),
          const SizedBox(height: 12),
          row("Lignes", '$n', Pal.ink),
          row("Entrées (${t.lignesEntree} ligne${t.lignesEntree > 1 ? 's' : ''})", '+${t.entrees}', Pal.green),
          row("Sorties (${t.lignesSortie} ligne${t.lignesSortie > 1 ? 's' : ''})", '−${t.sorties}', _red),
          const SizedBox(height: 12),
          const Text("Cette validation est définitive.", style: TextStyle(fontSize: 12, color: Pal.muted)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Non")),
        ElevatedButton(style: navyButton, onPressed: () => Navigator.pop(context, true), child: const Text("Oui, clôturer")),
      ],
    );
  }
}

class _AddResult {
  final int quantity;
  final int motifId;
  const _AddResult(this.quantity, this.motifId);
}

/// Saisie d'une ligne : sens (entrée / sortie), quantité entière bornée et motif.
/// Le dialogue reste ouvert jusqu'à la réponse du serveur ; en cas d'échec, l'erreur s'affiche ici.
class _AddLineDialog extends StatefulWidget {
  final ProductSearchResult product;
  final int initialMotifId;
  const _AddLineDialog({required this.product, required this.initialMotifId});

  @override
  State<_AddLineDialog> createState() => _AddLineDialogState();
}

class _AddLineDialogState extends State<_AddLineDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qteController = TextEditingController();
  int? _sign; // +1 entrée, -1 sortie ; à choisir
  bool _signError = false;
  late int _motifId = widget.initialMotifId;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _qteController.dispose();
    super.dispose();
  }

  int? get _qty {
    final v = int.tryParse(_qteController.text.trim());
    if (v == null || _sign == null) return null;
    return v * _sign!;
  }

  static String? validateQty(String? val) {
    final t = (val ?? '').trim();
    if (t.isEmpty) return "Quantité requise";
    final v = int.tryParse(t);
    if (v == null) return "Nombre entier requis";
    if (v <= 0) return "La quantité doit être au moins 1";
    if (v > kAjustementQteMax) return "Trop grand (max $kAjustementQteMax). Erreur de scan ?";
    return null;
  }

  Future<void> _submit() async {
    if (_sending) return; // pas de double envoi
    final formOk = _formKey.currentState!.validate();
    setState(() => _signError = _sign == null);
    if (!formOk || _sign == null) return;
    final qty = _qty;
    if (qty == null) return;

    // Écarts inhabituels : confirmation.
    final stock = widget.product.intNUMBERAVAILABLE;
    final after = stock + qty;
    final warnings = <String>[
      if (qty.abs() > kAjustementQteAlerte) "Quantité élevée : ${_signed(qty)} unités.",
      if (after < 0) "Le stock deviendrait négatif ($stock → $after).",
      if (stock > 0 && qty.abs() >= 10 && qty.abs() > 2 * stock) "Écart très grand par rapport au stock actuel ($stock).",
    ];
    if (warnings.isNotEmpty) {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (alertCtx) => AlertDialog(
          icon: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 36),
          title: const Text("Quantité élevée"),
          content: Text("Vous allez ajuster le stock de : ${_signed(qty)} unités.\n\n${warnings.join('\n')}\n\nConfirmer ?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(alertCtx, false), child: const Text("Corriger", style: TextStyle(color: Colors.red))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(alertCtx, true),
              child: const Text("Confirmer", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (!mounted || confirm != true) return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    final provider = Provider.of<AjustementProvider>(context, listen: false);
    final ok = await provider.addProduct(product: widget.product, quantity: qty, typeAjustementId: _motifId);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, _AddResult(qty, _motifId));
    } else {
      setState(() {
        _sending = false;
        _error = provider.errorMessage ?? "Ligne NON enregistrée. Réessayez.";
      });
    }
  }

  Widget _signButton(int sign, String label, Color color) {
    final on = _sign == sign;
    return Expanded(
      child: Material(
        color: on ? color : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: on ? color : (_signError ? Colors.red : const Color(0xFFC5D0DE))),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _sending ? null : () => setState(() {
                _sign = sign;
                _signError = false;
              }),
          child: SizedBox(
            height: 44,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: on ? Colors.white : color)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AjustementProvider>(context);
    final types = provider.typesAjustement;
    final p = widget.product;
    final stock = p.intNUMBERAVAILABLE;
    final qty = _qty;
    final after = qty == null ? null : stock + qty;
    final motifId = types.any((t) => t.id == _motifId) ? _motifId : (types.isEmpty ? null : types.first.id);

    return PopScope(
      canPop: !_sending,
      child: AlertDialog(
        title: Text(p.strNAME.isEmpty ? '—' : p.strNAME, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("Stock Actuel : $stock", style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.muted)),
                const SizedBox(height: 12),
                Row(children: [
                  _signButton(1, "+ Entrée", Pal.green),
                  const SizedBox(width: 8),
                  _signButton(-1, "− Sortie", _red),
                ]),
                if (_signError)
                  const Padding(
                    padding: EdgeInsets.only(top: 4, left: 4),
                    child: Text("Choisissez Entrée ou Sortie", style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _qteController,
                  enabled: !_sending,
                  decoration: const InputDecoration(
                    labelText: "Quantité",
                    border: OutlineInputBorder(),
                    helperText: "Nombre d'unités (1 à 9999)",
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    // Pas de troncature à 4 chiffres : un code-barres scanné ici est refusé (« Trop grand »).
                    LengthLimitingTextInputFormatter(15),
                  ],
                  autofocus: true,
                  validator: validateQty,
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: motifId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: "Motif", border: OutlineInputBorder()),
                  items: types
                      .map((t) => DropdownMenuItem(value: t.id, child: Text(t.libelle, maxLines: 1, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  validator: (v) => v == null ? "Motif requis" : null,
                  onChanged: _sending ? null : (val) => setState(() => _motifId = val ?? _motifId),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: Pal.page, borderRadius: BorderRadius.circular(10)),
                  child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                    const Text("Nouveau stock", style: TextStyle(color: Pal.muted)),
                    Text('$stock', style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
                    const Icon(Icons.arrow_forward, size: 16, color: Pal.muted),
                    Text(
                      after == null ? '?' : '$after',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: after == null ? Pal.muted : (after < 0 ? _red : (qty! >= 0 ? Pal.green : _red)),
                      ),
                    ),
                    if (qty != null) Text("(${_signed(qty)})", style: TextStyle(color: qty >= 0 ? Pal.green : _red)),
                  ]),
                ),
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDECEC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFF5C2C2)),
                    ),
                    child: Text(_error!, style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _sending ? null : () => Navigator.pop(context), child: const Text("Annuler")),
          ElevatedButton(
            style: navyButton,
            onPressed: _sending ? null : _submit,
            child: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Valider"),
          ),
        ],
      ),
    );
  }
}
