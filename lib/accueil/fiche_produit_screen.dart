// lib/accueil/fiche_produit_screen.dart
// Fiche produit ouverte depuis la recherche ou le scan de l'accueil :
// nom, CIP, stock, prix de vente (résultat de recherche) + emplacement et grossiste (GET /info).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/api/models/product_info.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_widgets.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
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
    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
      _failed = info == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.produit;
    final info = _info;
    final stock = info?.stock ?? p.intNUMBERAVAILABLE;
    final stockColor = stock <= 0 ? const Color(0xFFB91C1C) : Pal.green;
    return Scaffold(
      backgroundColor: Pal.page,
      body: Column(children: [
        const NavyHeader(title: 'Fiche produit', subtitle: 'Stock, prix et emplacement'),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
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
                else if (info != null) ...[
                  DetailLine('Emplacement', orDash(info.emplacement)),
                  DetailLine('Grossiste', orDash(info.grossiste)),
                ],
              ]),
            ),
            if (_failed && !_loading) ...[
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
