// lib/screens/perimes/tabs/saisie_en_cours_tab.dart
// Saisie des produits périmés à sortir du stock (présentations A, B, C).
// Contrôles : date réelle et plausible, lot non vide sans caractère de contrôle,
// quantité entière 1..99 999, confirmation avant suppression et validation, pas de double envoi.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/perime_models.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/providers/perime_provider.dart';
import 'package:prestige_vente_app/screens/perimes/perime_widgets.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/product_paging.dart';
import 'package:provider/provider.dart';

class SaisieEnCoursTab extends StatefulWidget {
  /// Présentation imposée par l'écran parent ; celle de l'appareil sinon.
  final ListPresentation? presentation;
  const SaisieEnCoursTab({super.key, this.presentation});

  @override
  State<SaisieEnCoursTab> createState() => _SaisieEnCoursTabState();
}

class _SaisieEnCoursTabState extends State<SaisieEnCoursTab> with PresentationAware, AutomaticKeepAliveClientMixin {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  @override
  bool get wantKeepAlive => true;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounce;

  final _formKey = GlobalKey<FormState>();
  final _lotController = TextEditingController();
  final _qteController = TextEditingController(text: '1');
  final _dateController = TextEditingController();

  final _lotFocusNode = FocusNode();
  final _qteFocusNode = FocusNode();
  final _dateFocusNode = FocusNode();

  // Envoi en cours (ajout, suppression, validation) : bloque les doubles appuis.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    loadPresentation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<PerimeProvider>(context, listen: false).loadSaisieEnCours();
    });
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(covariant SaisieEnCoursTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final p = widget.presentation;
    if (p != null && p != style) style = p;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    _lotController.dispose();
    _qteController.dispose();
    _dateController.dispose();
    _lotFocusNode.dispose();
    _qteFocusNode.dispose();
    _dateFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      Provider.of<PerimeProvider>(context, listen: false).searchProduct(_searchController.text.trim());
    });
    if (mounted) setState(() {}); // bouton « effacer »
  }

  void _resetForm() {
    Provider.of<PerimeProvider>(context, listen: false).clearSelection();
    _searchController.clear();
    _lotController.clear();
    _qteController.text = '1';
    _dateController.clear();
    _searchFocusNode.requestFocus();
  }

  void _selectProduct(PerimeProvider provider, ProductSearchResult product) {
    _searchFocusNode.unfocus();
    provider.selectProduct(product);
    // Met le focus sur le premier champ du formulaire
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(_dateFocusNode);
    });
  }

  String? _validateDate(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Date requise (JJMMAA ou MMAA)';
    if (parseDatePeremption(value!) == null) return 'Date invalide (JJMMAA ou MMAA)';
    return null;
  }

  String? _validateLot(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Requis';
    if (v.length > kPerimeMaxLot) return '$kPerimeMaxLot caractères max';
    if (perimeControlChars.hasMatch(v)) return 'Caractères non autorisés';
    return null;
  }

  String? _validateQte(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Requis';
    final q = int.tryParse(v);
    if (q == null || q < 1) return 'Min. 1';
    if (q > kPerimeMaxQte) return 'Max. 99 999';
    return null;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final current = parseDatePeremption(_dateController.text);
    final first = DateTime(2000);
    final last = DateTime(now.year + 10, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: first,
      lastDate: last,
      helpText: 'Date de péremption',
    );
    if (!mounted || picked == null) return;
    setState(() => _dateController.text = DateFormat('dd/MM/yyyy').format(picked));
    FocusScope.of(context).requestFocus(_lotFocusNode);
  }

  Future<void> _submitItem() async {
    if (_busy) return;
    final provider = Provider.of<PerimeProvider>(context, listen: false);
    if (provider.isLoading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final product = provider.selectedProduct;
    if (product == null) {
      provider.clearMessages();
      _setError("Veuillez sélectionner un produit.");
      return;
    }
    final date = parseDatePeremption(_dateController.text);
    final qte = int.tryParse(_qteController.text.trim());
    if (date == null || qte == null || qte < 1 || qte > kPerimeMaxQte) return;
    _dateController.text = DateFormat('dd/MM/yyyy').format(date);

    // Quantité supérieure au stock : on demande confirmation sans bloquer.
    final stock = product.intNUMBERAVAILABLE;
    if (stock >= 0 && qte > stock) {
      final ok = await confirmPerime(
        context,
        title: 'Quantité supérieure au stock',
        message: 'Vous sortez $qte boîte(s) alors que le stock affiché est de $stock. Continuer ?',
        confirmLabel: 'Continuer',
      );
      if (!mounted || !ok) return;
    }

    setState(() => _busy = true);
    var sent = false;
    try {
      await provider.addSaisieItem(
        lot: _lotController.text.trim(),
        datePeremption: DateFormat('yyyy-MM-dd').format(date),
        quantite: qte,
      );
      sent = true;
    } catch (_) {
      sent = false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;

    // Si succès, on réinitialise le formulaire pour la saisie suivante
    if (sent && provider.errorMessage == null) {
      _resetForm();
      Constants.showSnackBar(context, 'Produit ajouté.');
    } else {
      _setError(provider.errorMessage ?? "Erreur réseau : l'ajout n'a pas été enregistré.");
    }
  }

  Future<void> _deleteItem(SaisieEnCoursItem item) async {
    if (_busy) return;
    final ok = await confirmPerime(
      context,
      title: 'Retirer ce produit ?',
      message: '${perimeOrDash(item.produitLibelle)}\nLot ${perimeOrDash(item.lot)} · Qté ${item.quantity}',
      confirmLabel: 'Retirer',
      danger: true,
    );
    if (!mounted || !ok) return;
    final provider = Provider.of<PerimeProvider>(context, listen: false);
    setState(() => _busy = true);
    provider.clearMessages();
    try {
      await provider.deleteSaisieItem(item.id);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    if (provider.errorMessage != null) _setError(provider.errorMessage!);
  }

  Future<void> _validateSaisie() async {
    if (_busy) return;
    final provider = Provider.of<PerimeProvider>(context, listen: false);
    if (provider.saisieEnCoursList.isEmpty) return;

    final confirm = await confirmPerime(
      context,
      title: 'Valider la Saisie ?',
      message:
          'Vous êtes sur le point de valider la sortie de ${provider.saisieEnCoursList.length} produit(s) du stock. Cette action est irréversible.',
      confirmLabel: 'Valider',
    );
    if (!mounted || !confirm) return;

    setState(() => _busy = true);
    var ok = false;
    try {
      ok = await provider.validateSaisie();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok || provider.errorMessage != null) {
      Constants.showSnackBar(context, provider.errorMessage ?? 'La validation a échoué.', isError: true);
    } else if (provider.successMessage.isNotEmpty) {
      Constants.showSnackBar(context, provider.successMessage);
    }
  }

  // Helper local pour afficher l'erreur
  void _setError(String msg) {
    Constants.showSnackBar(context, msg, isError: true);
  }

  ButtonStyle get _mainButton => style == ListPresentation.guided ? amberButton : navyButton;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = Provider.of<PerimeProvider>(context);
    final selected = provider.selectedProduct;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final compact = style == ListPresentation.compact;

    Widget? bottom;
    if (selected != null) {
      bottom = PerimeBottomAction(
        label: 'Ajouter à la liste',
        icon: Icons.add,
        style: _mainButton,
        busy: _busy,
        onPressed: provider.isLoading ? null : _submitItem,
      );
    } else if (provider.saisieEnCoursList.isNotEmpty && !keyboard) {
      bottom = PerimeBottomAction(
        label: 'Valider la Saisie (${provider.saisieEnCoursList.length})',
        icon: Icons.check_circle,
        style: _mainButton,
        busy: _busy,
        onPressed: provider.isLoading ? null : _validateSaisie,
      );
    }

    Widget content;
    if (selected != null) {
      content = ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        children: [
          _buildEntryForm(provider, selected),
          if (provider.saisieEnCoursList.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle('Saisie en cours (${provider.saisieEnCoursList.length})'),
            for (final item in provider.saisieEnCoursList) ...[_itemTile(item), SizedBox(height: compact ? 0 : 8)],
          ],
        ],
      );
    } else if (provider.productSearchResults.isNotEmpty) {
      content = _buildSearchResults(provider);
    } else {
      content = RefreshIndicator(
        onRefresh: () => provider.loadSaisieEnCours(),
        child: provider.saisieEnCoursList.isEmpty
            ? PerimeEmptyState(
                icon: Icons.inventory_2_outlined,
                text: 'Aucun produit en cours de saisie.',
                detail: 'Recherchez un produit (CIP, nom ou scan) pour le déclarer périmé.',
                actionLabel: 'Rechercher un produit',
                onAction: () => _searchFocusNode.requestFocus(),
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(compact ? 0 : 12, 8, compact ? 0 : 12, 24),
                itemCount: provider.saisieEnCoursList.length,
                separatorBuilder: (_, __) => SizedBox(height: compact ? 0 : 8),
                itemBuilder: (context, index) => _itemTile(provider.saisieEnCoursList[index]),
              ),
      );
    }

    return Container(
      color: compact ? Colors.white : null,
      child: Column(
        children: [
          if (selected == null)
            Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 4), child: _buildSearchField(provider)),
          if (selected == null) _searchNotice(provider),
          if (provider.isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: content),
          if (bottom != null) bottom,
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.6, color: Pal.muted)),
      );

  Widget _buildSearchField(PerimeProvider provider) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      inputFormatters: [perimeNoControlChars, LengthLimitingTextInputFormatter(60)],
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        labelText: 'Rechercher Produit (CIP, Nom, Scan)',
        floatingLabelBehavior: FloatingLabelBehavior.never,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: style == ListPresentation.compact ? Pal.page : Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Pal.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Pal.line)),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                tooltip: 'Effacer',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  provider.searchProduct('');
                },
              )
            : null,
      ),
      onSubmitted: (_) => _onSearchChanged(),
    );
  }

  InputDecoration _fieldDeco(String label, {Widget? suffix}) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC5D0DE))),
      );

  Widget _buildEntryForm(PerimeProvider provider, ProductSearchResult product) {
    return SoftCard(
      band: style == ListPresentation.guided ? Pal.navy : null,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(perimeOrDash(product.strNAME),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.ink)),
                ),
                IconButton(tooltip: 'Fermer', icon: const Icon(Icons.close), onPressed: _busy ? null : _resetForm),
              ],
            ),
            Text('CIP: ${perimeOrDash(product.intCIP)} | Stock: ${product.intNUMBERAVAILABLE}', style: const TextStyle(color: Pal.muted)),
            const SizedBox(height: 14),
            TextFormField(
              controller: _dateController,
              focusNode: _dateFocusNode,
              decoration: _fieldDeco(
                'Date Péremption (JJMMAA ou MMAA) *',
                suffix: IconButton(tooltip: 'Calendrier', icon: const Icon(Icons.calendar_month), onPressed: _pickDate),
              ),
              keyboardType: TextInputType.datetime,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9/\-\. ]')),
                LengthLimitingTextInputFormatter(10),
              ],
              textInputAction: TextInputAction.next,
              validator: _validateDate,
              onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_lotFocusNode),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _lotController,
                    focusNode: _lotFocusNode,
                    decoration: _fieldDeco('N° Lot *'),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [perimeNoControlChars, LengthLimitingTextInputFormatter(kPerimeMaxLot)],
                    textInputAction: TextInputAction.next,
                    validator: _validateLot,
                    onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(_qteFocusNode),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _qteController,
                    focusNode: _qteFocusNode,
                    decoration: _fieldDeco('Quantité *'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submitItem(),
                    validator: _validateQte,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Ligne de la saisie en cours : carte (A, C) ou ligne compacte (B).
  Widget _itemTile(SaisieEnCoursItem item) {
    final compact = style == ListPresentation.compact;
    final row = Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(perimeOrDash(item.produitLibelle),
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink)),
          const SizedBox(height: 2),
          Text('Lot: ${perimeOrDash(item.lot)} | Qté: ${item.quantity} | Péremption: ${perimeOrDash(item.datePeremption)}',
              style: const TextStyle(fontSize: 13, color: Pal.muted)),
        ]),
      ),
      IconButton(
        tooltip: 'Retirer',
        icon: const Icon(Icons.delete_outline, color: AppColors.error),
        onPressed: _busy ? null : () => _deleteItem(item),
      ),
    ]);
    if (compact) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
        child: row,
      );
    }
    return SoftCard(
      band: style == ListPresentation.guided ? Pal.amber : null,
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      child: row,
    );
  }

  /// Recherche en panne (≠ introuvable) ou code inconnu : message sous le champ.
  Widget _searchNotice(PerimeProvider provider) {
    if (provider.isLoading || _searchController.text.trim().isEmpty) return const SizedBox.shrink();
    final error = provider.productSearchError;
    final notFound = provider.productSearchNotFound;
    if (error == null && notFound == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
      child: Row(children: [
        Icon(error != null ? Icons.cloud_off : Icons.search_off, size: 18, color: error != null ? Colors.red.shade700 : Colors.orange.shade800),
        const SizedBox(width: 6),
        Expanded(
          child: Text(error != null ? 'Recherche impossible : $error' : notFound!,
              style: TextStyle(fontSize: 13, color: error != null ? Colors.red.shade900 : Colors.orange.shade900)),
        ),
        if (error != null) TextButton(onPressed: _onSearchChanged, child: const Text('Réessayer')),
      ]),
    );
  }

  Widget _buildSearchResults(PerimeProvider provider) {
    final compact = style == ListPresentation.compact;
    final results = provider.productSearchResults;
    final paging = provider.productSearch;
    final footer = ProductPagingFooter.visibleFor(paging);
    final list = ListView.separated(
      padding: EdgeInsets.fromLTRB(compact ? 0 : 12, 8, compact ? 0 : 12, 16),
      itemCount: results.length + (footer ? 1 : 0),
      separatorBuilder: (_, __) => SizedBox(height: compact ? 0 : 8),
      itemBuilder: (context, index) {
        if (index >= results.length) return ProductPagingFooter(paging, onLoadMore: provider.loadMoreProducts);
        final product = results[index];
        final row = Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(perimeOrDash(product.strNAME),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink)),
              Text('CIP: ${perimeOrDash(product.intCIP)} | Stock: ${product.intNUMBERAVAILABLE}',
                  style: const TextStyle(fontSize: 13, color: Pal.muted)),
            ]),
          ),
          const Icon(Icons.chevron_right, color: Pal.muted),
        ]);
        if (compact) {
          return InkWell(
            onTap: () => _selectProduct(provider, product),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
              child: row,
            ),
          );
        }
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _selectProduct(provider, product),
          child: SoftCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: row),
        );
      },
    );
    // Liste par pages : « 50 sur 120 », la suite se charge en faisant défiler.
    return Column(children: [
      ProductPagingCount(paging),
      Expanded(child: ProductPagingScroll(search: paging, onLoadMore: provider.loadMoreProducts, child: list)),
    ]);
  }
}
