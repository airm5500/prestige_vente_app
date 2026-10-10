// lib/accueil/recherche_globale_screen.dart
// Recherche de l'accueil : menus (par nom) + produits (même recherche fiable que les menus :
// code exact avec variantes ou liste texte par pages). Un code scanné ouvre la fiche produit.
// Puce « Début / Contient » : mode de la recherche texte des produits (réglage partagé).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/accueil/fiche_produit_screen.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/screens/common/camera_scan_screen.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_widgets.dart';
import 'package:prestige_vente_app/services/product_finder.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/product_paging.dart';

typedef CodeScanner = Future<String?> Function(BuildContext context);

/// Ouvre l'appareil photo et renvoie le code lu (null si annulé).
Future<String?> scannerParDefaut(BuildContext context) => CameraScanScreen.open(context, title: 'Scanner un produit');

class RechercheGlobaleScreen extends StatefulWidget {
  /// Menus proposés (les menus masqués de l'accueil n'y sont pas).
  final List<AccueilMenu> menus;
  final ValueChanged<AccueilMenu> onOpenMenu;

  /// Code scanné à rechercher dès l'ouverture.
  final String? initialCode;
  final CodeScanner? scanner;

  /// Recherche produits (tests) ; sinon l'ApiService de l'application.
  final ApiService Function()? api;
  const RechercheGlobaleScreen({super.key, required this.menus, required this.onOpenMenu, this.initialCode, this.scanner, this.api});

  @override
  State<RechercheGlobaleScreen> createState() => _RechercheGlobaleScreenState();
}

class _RechercheGlobaleScreenState extends State<RechercheGlobaleScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  late final PagedProductSearch _search =
      PagedProductSearch(widget.api ?? () => Provider.of<ApiService>(context, listen: false));
  bool _loading = false;
  String _lastSent = '';
  List<AccueilMenu> _menus = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    final code = widget.initialCode;
    if (code != null && code.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _chercherCode(code);
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.clear();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _lastText = '';

  void _onChanged() {
    if (_controller.text == _lastText) return;
    _lastText = _controller.text;
    final q = SearchQuery.clean(_controller.text);
    setState(() => _menus = chercherMenus(q, widget.menus));
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _lancer);
  }

  Future<void> _lancer() async {
    if (!mounted) return;
    final q = SearchQuery.clean(_controller.text);
    if (q.isEmpty || SearchQuery.tooShort(q)) {
      _lastSent = '';
      _search.clear();
      setState(() => _loading = false);
      return;
    }
    if (q == _lastSent && !_loading && _search.error == null) return;
    _lastSent = q;
    setState(() => _loading = true);
    final current = await _search.run(q);
    if (!mounted || !current) return;
    setState(() => _loading = false);
  }

  /// Code scanné : produit exact → fiche ; sinon liste des candidats / message.
  Future<void> _chercherCode(String raw) async {
    _debounce?.cancel();
    final shown = SearchQuery.clean(raw);
    _lastText = shown;
    _controller.text = shown;
    _lastSent = shown;
    setState(() {
      _menus = const [];
      _loading = true;
    });
    final current = await _search.run(raw, asCode: true);
    if (!mounted || !current) return;
    setState(() => _loading = false);
    if (_search.items.length == 1 && _search.error == null) _ouvrirProduit(_search.items.first);
  }

  Future<void> _scanner() async {
    final code = await (widget.scanner ?? scannerParDefaut)(context);
    if (!mounted || code == null || code.trim().isEmpty) return;
    await _chercherCode(code);
  }

  void _ouvrirProduit(ProductSearchResult p) {
    _focus.unfocus();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FicheProduitScreen(produit: p)));
  }

  Future<void> _suite() async {
    final f = _search.loadMore();
    setState(() {});
    await f;
    if (mounted) setState(() {});
  }

  /// Bascule « Commence par » / « Contient » et relance la recherche produit.
  Future<void> _basculerMode() async {
    await SearchModePrefs.toggle();
    if (!mounted) return;
    _debounce?.cancel();
    _lastSent = '';
    if (!_search.byCode) await _lancer();
  }

  void _effacer() {
    _debounce?.cancel();
    _controller.clear();
    _lastText = '';
    _lastSent = '';
    _search.clear();
    setState(() {
      _menus = const [];
      _loading = false;
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pal.page,
      body: Column(children: [
        NavyHeader(title: 'Rechercher', subtitle: 'Un menu ou un produit', children: [
          TextField(
            controller: _controller,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            inputFormatters: SearchQuery.formatters,
            onSubmitted: (_) {
              _debounce?.cancel();
              _lastSent = '';
              _lancer();
            },
            decoration: InputDecoration(
              hintText: 'Menu, nom du produit ou code CIP',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                SearchModeChip(onToggle: _basculerMode),
                if (_controller.text.isNotEmpty) IconButton(icon: const Icon(Icons.clear), tooltip: 'Effacer', onPressed: _effacer),
                IconButton(icon: const Icon(Icons.qr_code_scanner), tooltip: 'Scanner un code', onPressed: _scanner),
              ]),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ]),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _resultats()),
      ]),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Pal.muted)),
      );

  Widget _resultats() {
    final q = SearchQuery.clean(_controller.text);
    if (q.isEmpty && !_loading) {
      return const InfoState(icon: Icons.manage_search, text: 'Tapez le nom d\'un menu (ex. « stock ») ou d\'un produit, ou scannez un code');
    }
    final children = <Widget>[];
    if (_menus.isNotEmpty) {
      children.add(_section('Menus'));
      for (final m in _menus) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              leading: Icon(m.icon, color: m.color),
              title: Row(children: [
                Flexible(child: Text(m.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink))),
                if (m.protege) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.lock, size: 16, color: Pal.amber)),
              ]),
              subtitle: Text(m.famille.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => widget.onOpenMenu(m),
            ),
          ),
        ));
      }
    }
    children.add(_section('Produits'));
    if (SearchQuery.tooShort(q) && !_search.byCode) {
      children.add(const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Saisissez au moins ${SearchQuery.minLength} caractères pour chercher un produit.', style: TextStyle(color: Pal.muted)),
      ));
    } else if (_loading && _search.items.isEmpty) {
      children.add(const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())));
    } else if (_search.error != null) {
      // Panne (réseau, serveur) : jamais « aucun produit ».
      children.add(SoftCard(
        child: Row(children: [
          const Icon(Icons.cloud_off, color: Color(0xFFB91C1C)),
          const SizedBox(width: 10),
          Expanded(child: Text('Recherche impossible : ${_search.error}', style: const TextStyle(color: Pal.ink))),
          TextButton(
            onPressed: () {
              _lastSent = '';
              if (_search.byCode) {
                _chercherCode(_search.query.isEmpty ? q : _search.query);
              } else {
                _lancer();
              }
            },
            child: const Text('Réessayer'),
          ),
        ]),
      ));
    } else if (_search.notFound != null) {
      children.add(Padding(padding: const EdgeInsets.all(8), child: Text(_search.notFound!, style: const TextStyle(color: Pal.muted))));
    } else if (_search.items.isEmpty) {
      if (_lastSent == q && !_loading) {
        children.add(const Padding(padding: EdgeInsets.all(8), child: Text('Aucun produit trouvé.', style: TextStyle(color: Pal.muted))));
      }
    } else {
      if (_search.showCount) children.add(ProductPagingCount(_search, padding: const EdgeInsets.fromLTRB(4, 0, 4, 6)));
      for (final p in _search.items) {
        children.add(_produit(p));
      }
      if (ProductPagingFooter.visibleFor(_search)) children.add(ProductPagingFooter(_search, onLoadMore: _suite));
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: children,
    );
  }

  Widget _produit(ProductSearchResult p) {
    final enStock = p.intNUMBERAVAILABLE > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _ouvrirProduit(p),
        child: SoftCard(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(orDash(p.strNAME), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink)),
                Text('CIP ${orDash(p.intCIP)} · stock ${p.intNUMBERAVAILABLE} · ${Constants.formatNumber(p.intPRICE)} F',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
              ]),
            ),
            const SizedBox(width: 8),
            enStock
                ? const StatusBadge('En stock', fg: Color(0xFF0B6B45), bg: Color(0xFFDCF5E7))
                : const StatusBadge('Rupture', fg: Color(0xFF9B1C1C), bg: Color(0xFFFDE7E7)),
          ]),
        ),
      ),
    );
  }
}
