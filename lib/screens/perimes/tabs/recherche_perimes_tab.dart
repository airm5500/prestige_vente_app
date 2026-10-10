// lib/screens/perimes/tabs/recherche_perimes_tab.dart
// Recherche des produits périmés ou à date courte (présentations A, B, C).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/perime_models.dart';
import 'package:prestige_vente_app/providers/perime_provider.dart';
import 'package:prestige_vente_app/screens/perimes/perime_widgets.dart';
import 'package:prestige_vente_app/services/pdf_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

class RecherchePerimesTab extends StatefulWidget {
  /// Présentation imposée par l'écran parent ; celle de l'appareil sinon.
  final ListPresentation? presentation;
  const RecherchePerimesTab({super.key, this.presentation});

  @override
  State<RecherchePerimesTab> createState() => _RecherchePerimesTabState();
}

class _RecherchePerimesTabState extends State<RecherchePerimesTab> with PresentationAware, AutomaticKeepAliveClientMixin {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  @override
  bool get wantKeepAlive => true;

  bool _isPrinting = false;

  static const _moisOptions = [0, 1, 2, 3, 6, 12];

  @override
  void initState() {
    super.initState();
    loadPresentation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<PerimeProvider>(context, listen: false).loadProduitsPerimes();
    });
  }

  @override
  void didUpdateWidget(covariant RecherchePerimesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final p = widget.presentation;
    if (p != null && p != style) style = p;
  }

  Future<void> _handlePrint() async {
    if (_isPrinting) return;
    final provider = Provider.of<PerimeProvider>(context, listen: false);
    if (provider.produitsPerimesList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Aucune donnée à imprimer")));
      return;
    }

    setState(() => _isPrinting = true);

    try {
      // 1. Déterminer le texte du filtre
      final int nbreMois = provider.nbreMoisFilter;
      final String filterText = nbreMois == 0 ? "Produits déjà périmés" : "Périmés dans les $nbreMois mois";

      // 2. Récupérer les totaux (avec sécurité null)
      final int totalAchat = provider.metaData?.totalValeurAchat ?? 0;
      final int totalVente = provider.metaData?.totalValeurVente ?? 0;

      // 3. Appel de la méthode mise à jour
      await PdfService().generateAndPrintPerimesReport(
        provider.produitsPerimesList,
        filterText,
        totalAchat: totalAchat,
        totalVente: totalVente,
      );
    } catch (e) {
      if (mounted) Constants.showSnackBar(context, "Erreur d'impression : impossible de générer le document.", isError: true);
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  static bool _isExpired(ProduitPerime p) => p.statut.contains('Périmé il y a');

  void _showDetailDialog(ProduitPerime produit) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(perimeOrDash(produit.libelle), style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.ink)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              PerimeInfoRow('CIP', produit.codeCip),
              PerimeInfoRow('N° Lot', produit.numLot),
              PerimeInfoRow('Date Péremption', produit.datePerement),
              PerimeInfoRow('Statut', produit.statut),
              const Divider(),
              PerimeInfoRow('Quantité', produit.quantiteLot.toString()),
              PerimeInfoRow('Valeur Vente', Constants.formatNumber(produit.valeurVente)),
              PerimeInfoRow('Valeur Achat', Constants.formatNumber(produit.valeurAchat)),
              const Divider(),
              PerimeInfoRow('Rayon', produit.libelleRayon),
              PerimeInfoRow('Famille', produit.libelleFamille),
              PerimeInfoRow('Grossiste', produit.libelleGrossiste),
            ],
          ),
        ),
        actions: [
          TextButton(child: const Text('Fermer'), onPressed: () => Navigator.of(ctx).pop()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<PerimeProvider>(
      builder: (context, provider, child) {
        final list = provider.produitsPerimesList;
        final compact = style == ListPresentation.compact;
        return Container(
          color: compact ? Colors.white : null,
          child: Column(
            children: [
              _buildToolbar(provider),
              if (provider.isLoading && list.isNotEmpty) const LinearProgressIndicator(minHeight: 2),
              Expanded(child: _buildList(provider)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbar(PerimeProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(
            child: Text('Périmés dans :', style: TextStyle(fontWeight: FontWeight.bold, color: Pal.ink, fontSize: 15)),
          ),
          SizedBox(
            height: 40,
            child: OutlinedButton.icon(
              style: outlineButton,
              onPressed: _isPrinting ? null : _handlePrint,
              icon: _isPrinting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.print, size: 18),
              label: const Text("Imprimer"),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final mois in _moisOptions)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(mois == 0 ? 'Déjà périmés' : '$mois mois'),
                  selected: provider.nbreMoisFilter == mois,
                  selectedColor: const Color(0xFFFFE7B3),
                  // Pas de nouveau chargement tant que le précédent n'est pas fini.
                  onSelected: provider.isLoading
                      ? null
                      : (_) {
                          if (provider.nbreMoisFilter != mois) provider.setNbreMois(mois);
                        },
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildList(PerimeProvider provider) {
    final list = provider.produitsPerimesList;
    if (provider.isLoading && list.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Chargement des produits périmés..."),
          ],
        ),
      );
    }
    final compact = style == ListPresentation.compact;
    return RefreshIndicator(
      onRefresh: () => provider.loadProduitsPerimes(),
      child: list.isEmpty
          ? PerimeEmptyState(
              icon: Icons.event_available,
              text: "Aucun produit trouvé.",
              detail: 'Aucun lot ne correspond à ce délai. Choisissez une autre période.',
              actionLabel: 'Actualiser',
              onAction: () => provider.loadProduitsPerimes(),
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(compact ? 0 : 12, 8, compact ? 0 : 12, 24),
              itemCount: list.length,
              separatorBuilder: (_, __) => SizedBox(height: compact ? 0 : 10),
              itemBuilder: (context, index) => compact ? _rowB(list[index]) : _cardAC(list[index]),
            ),
    );
  }

  Widget _statusBadge(ProduitPerime p) {
    final expired = _isExpired(p);
    return StatusBadge(
      perimeOrDash(p.statut),
      fg: expired ? const Color(0xFF9B1C1C) : const Color(0xFF8A5300),
      bg: expired ? const Color(0xFFFDE7E7) : const Color(0xFFFFF1D6),
    );
  }

  // A et C : carte arrondie (bande de couleur en C).
  Widget _cardAC(ProduitPerime p) {
    final expired = _isExpired(p);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showDetailDialog(p),
      child: SoftCard(
        band: style == ListPresentation.guided ? (expired ? const Color(0xFFDC2626) : Pal.amber) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(perimeOrDash(p.libelle),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Pal.ink)),
            ),
            const Icon(Icons.chevron_right, color: Pal.muted),
          ]),
          const SizedBox(height: 4),
          Text('CIP: ${perimeOrDash(p.codeCip)} | Lot: ${perimeOrDash(p.numLot)}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _statusBadge(p),
            Text('Péremption: ${perimeOrDash(p.datePerement)}', style: const TextStyle(fontSize: 13, color: Pal.ink)),
            Figure('${p.quantiteLot}', 'boîte(s)'),
          ]),
        ]),
      ),
    );
  }

  // B : ligne compacte séparée par un filet.
  Widget _rowB(ProduitPerime p) {
    final expired = _isExpired(p);
    return InkWell(
      onTap: () => _showDetailDialog(p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: expired ? const Color(0xFFFFF7F7) : null,
          border: const Border(bottom: BorderSide(color: Color(0xFFEEF1F5))),
        ),
        child: Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: expired ? AppColors.error : Colors.orange.shade700, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(perimeOrDash(p.libelle),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
              Text('CIP: ${perimeOrDash(p.codeCip)} · Lot: ${perimeOrDash(p.numLot)} · ${perimeOrDash(p.datePerement)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Qté ${p.quantiteLot}', style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.ink)),
              Text(perimeOrDash(p.statut),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: expired ? AppColors.error : Colors.orange.shade700)),
            ]),
          ),
        ]),
      ),
    );
  }
}
