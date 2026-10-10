// lib/accueil/fiche_produit_screen.dart
// Fiche produit ouverte depuis la recherche ou le scan de l'accueil :
// nom, CIP, stock, prix de vente (résultat de recherche) + emplacement et grossiste (GET /info).
// Hors ligne : données de la copie locale du catalogue (lib/horsligne) avec leur date ;
// ce qui exige le serveur affiche « Disponible en ligne uniquement » (jamais une erreur).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_info.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_widgets.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

class FicheProduitScreen extends StatefulWidget {
  final ProductSearchResult produit;

  /// Chargement du complément (tests) ; sinon ApiService.getProductInfo.
  final Future<ProductInfo?> Function(String cip)? loadInfo;
  const FicheProduitScreen({super.key, required this.produit, this.loadInfo});

  @override
  State<FicheProduitScreen> createState() => _FicheProduitScreenState();
}

class _FicheProduitScreenState extends State<FicheProduitScreen> {
  ProductInfo? _info;
  bool _loading = true;
  bool _failed = false;

  /// Hors ligne : produit relu dans la copie locale (null : celui reçu).
  ProductSearchResult? _local;
  late final HorsLigne _hl = HorsLigne.instance;
  late bool _offline = _hl.offline;

  @override
  void initState() {
    super.initState();
    _hl.monitor.addListener(_onMonitor);
    _load();
  }

  @override
  void dispose() {
    _hl.monitor.removeListener(_onMonitor);
    super.dispose();
  }

  /// Passage hors ligne / retour en ligne : la fiche est rechargée depuis la bonne source.
  void _onMonitor() {
    if (!mounted || _hl.offline == _offline) return;
    _offline = _hl.offline;
    _load();
  }

  /// Copie locale : produit à jour (stock connu, prix) et date du catalogue.
  Future<void> _loadLocal() async {
    ProductSearchResult? local;
    try {
      if (!_hl.sync.statsLoaded) await _hl.sync.refreshStats();
      final p = widget.produit;
      final cip = p.intCIP.trim();
      if (cip.isNotEmpty) {
        final page = await _hl.store.searchProducts(cip, 0, 20);
        local = page.items.where((e) => e.lgFAMILLEID == p.lgFAMILLEID && e.intCIP.trim() == cip).firstOrNull ??
            page.items.where((e) => e.intCIP.trim() == cip).firstOrNull;
      }
    } catch (_) {
      local = null;
    }
    if (!mounted) return;
    setState(() {
      _local = local;
      _info = null;
      _loading = false;
      _failed = false;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    if (_offline) return _loadLocal();
    ProductInfo? info;
    try {
      final cip = widget.produit.intCIP.trim();
      if (cip.isNotEmpty) {
        info = widget.loadInfo != null
            ? await widget.loadInfo!(cip)
            : await Provider.of<ApiService>(context, listen: false).getProductInfo(cip);
      }
    } catch (_) {
      info = null;
    }
    if (!mounted || _offline) return;
    setState(() {
      _info = info;
      _local = null;
      _loading = false;
      _failed = info == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _offline ? (_local ?? widget.produit) : widget.produit;
    final info = _offline ? null : _info;
    final stock = info?.stock ?? p.intNUMBERAVAILABLE;
    final stockColor = stock <= 0 ? const Color(0xFFB91C1C) : Pal.green;
    return Scaffold(
      backgroundColor: Pal.page,
      body: Column(children: [
        const NavyHeader(title: 'Fiche produit', subtitle: 'Stock, prix et emplacement'),
        Expanded(
          child: ContentWidth(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
              if (_offline) ...[_noteHorsLigne(), const SizedBox(height: 12)],
              SoftCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(orDash(info?.libelle.isNotEmpty == true ? info!.libelle : p.strNAME),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Pal.ink)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _figure('$stock', 'En stock', stockColor)),
                    const SizedBox(width: 8),
                    Expanded(child: _figure('${Constants.formatNumber(p.intPRICE)} F', 'Prix de vente', Pal.ink)),
                  ]),
                  const SizedBox(height: 12),
                  DetailLine('Code CIP', orDash(p.intCIP), bold: true),
                  if (p.strLIBELLEE.trim().isNotEmpty) DetailLine('Famille', orDash(p.strLIBELLEE)),
                  if (_loading)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: LinearProgressIndicator(minHeight: 2))
                  else if (_offline) ...[
                    const DetailLine('Emplacement', 'Disponible en ligne uniquement'),
                    const DetailLine('Grossiste', 'Disponible en ligne uniquement'),
                  ] else if (info != null) ...[
                    DetailLine('Emplacement', orDash(info.emplacement)),
                    DetailLine('Grossiste', orDash(info.grossiste)),
                  ],
                ]),
              ),
              if (_failed && !_loading && !_offline) ...[
                const SizedBox(height: 12),
                SoftCard(
                  child: Row(children: [
                    const Icon(Icons.cloud_off, color: Color(0xFFB45309)),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Emplacement et grossiste non disponibles (serveur ou fiche introuvable).', style: TextStyle(color: Pal.muted))),
                    TextButton(onPressed: _load, child: const Text('Réessayer')),
                  ]),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  /// « Hors ligne — données du catalogue du JJ/MM HH:MM ».
  Widget _noteHorsLigne() {
    final at = _hl.sync.catalogueAt;
    final texte = at == null
        ? 'Hors ligne — aucun catalogue local sur cet appareil'
        : 'Hors ligne — données du catalogue du ${HorsLigne.formatDate(at)}';
    return Container(
      key: const Key('fiche_hors_ligne'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        const Icon(Icons.cloud_off, size: 18, color: Color(0xFF334155)),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$texte. Stock connu à cette date.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _figure(String value, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: Pal.page, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          ),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Pal.muted)),
        ]),
      );
}
