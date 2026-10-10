// lib/screens/product_search/product_search_widgets.dart
// Éléments communs à « Recherche Article » et « Évaluation Vente » :
// contrôle de la saisie de recherche, champ de recherche, ligne de résultat, états vides.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/services/product_finder.dart';
import 'package:prestige_vente_app/widgets/product_paging.dart';

/// Règles de saisie d'une recherche produit (nom, CIP ou code scanné).
class SearchQuery {
  SearchQuery._();

  /// Longueur maximale d'une recherche (un EAN/DataMatrix tient largement).
  static const int maxLength = 60;

  /// Longueur minimale pour interroger le serveur.
  static const int minLength = 2;

  static final _control = RegExp(r'[\x00-\x1F\x7F]');
  static final _spaces = RegExp(r'\s+');

  /// Filtres du champ : pas de caractères de contrôle, longueur bornée.
  static final List<TextInputFormatter> formatters = [
    FilteringTextInputFormatter.deny(_control),
    LengthLimitingTextInputFormatter(maxLength),
  ];

  /// Texte nettoyé : sans caractères de contrôle, espaces superflus retirés, longueur bornée.
  static String clean(String raw) {
    var q = raw.replaceAll(_control, ' ').replaceAll(_spaces, ' ').trim();
    if (q.length > maxLength) q = q.substring(0, maxLength).trim();
    return q;
  }

  /// Recherche trop courte pour être envoyée ?
  static bool tooShort(String q, {int min = minLength}) => q.length < min;
}

/// Valeur affichable : vide → « — ».
String orDash(String? v) {
  final t = v?.trim() ?? '';
  return t.isEmpty || t == 'N/A' ? '—' : t;
}

/// Champ de recherche (fond blanc dans l'en-tête bleu, fond clair en présentation B).
class ProductSearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool dark;
  final VoidCallback onClear;
  final ValueChanged<String> onSubmitted;
  const ProductSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.dark,
    required this.onClear,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.search,
        inputFormatters: SearchQuery.formatters,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(icon: const Icon(Icons.clear), tooltip: 'Effacer', onPressed: onClear),
          filled: true,
          fillColor: dark ? Colors.white : Pal.page,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      );
}

/// Message centré (icône + phrase + action facultative).
class InfoState extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  const InfoState({super.key, required this.icon, required this.text, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted, fontSize: 15)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(style: outlineButton, onPressed: onAction, icon: const Icon(Icons.refresh), label: Text(actionLabel!)),
            ],
          ]),
        ),
      );
}

/// Liste des résultats de recherche dans la présentation choisie.
class ProductResultsList extends StatelessWidget {
  final List<ProductSearchResult> results;
  final ListPresentation style;
  final ValueChanged<ProductSearchResult> onTap;

  /// Liste par pages : « 50 sur 120 » et chargement de la suite en faisant défiler.
  final PagedProductSearch? paging;
  final VoidCallback? onLoadMore;
  const ProductResultsList({super.key, required this.results, required this.style, required this.onTap, this.paging, this.onLoadMore});

  bool get _footer => paging != null && onLoadMore != null && ProductPagingFooter.visibleFor(paging!);

  Widget _footerRow() => ProductPagingFooter(paging!, onLoadMore: onLoadMore!);

  Widget _scroll(Widget list) =>
      paging != null && onLoadMore != null ? ProductPagingScroll(search: paging!, onLoadMore: onLoadMore!, child: list) : list;

  Color _stockColor(int stock) => stock <= 0 ? const Color(0xFFB91C1C) : Pal.green;

  Widget _metric(String value, String label, {Color fg = Pal.ink}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: Pal.page, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: fg)),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFF4A5A70))),
          ]),
        ),
      );

  String _sub(ProductSearchResult p) =>
      'CIP: ${orDash(p.intCIP)}${p.strLIBELLEE.trim().isNotEmpty ? ' · ${p.strLIBELLEE.trim()}' : ''}';

  Widget _card(ProductSearchResult p, {Color? band}) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onTap(p),
        child: SoftCard(
          band: band,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(orDash(p.strNAME),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Pal.ink)),
              ),
              const Icon(Icons.chevron_right, color: Pal.muted),
            ]),
            const SizedBox(height: 2),
            Text(_sub(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
            const SizedBox(height: 10),
            Row(children: [
              _metric('${p.intNUMBERAVAILABLE}', 'Stock', fg: _stockColor(p.intNUMBERAVAILABLE)),
              const SizedBox(width: 8),
              _metric('${Constants.formatNumber(p.intPRICE)} F', 'Prix de vente'),
            ]),
          ]),
        ),
      );

  Widget _row(ProductSearchResult p) => InkWell(
        onTap: () => onTap(p),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(orDash(p.strNAME),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
                Text('${_sub(p)} · ${Constants.formatNumber(p.intPRICE)} F',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
              ]),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text('${p.intNUMBERAVAILABLE}',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _stockColor(p.intNUMBERAVAILABLE))),
              ),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (style == ListPresentation.compact) {
      return Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Row(children: [
            Expanded(child: Text('PRODUIT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: Color(0xFF4A5A70)))),
            Text('STOCK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: Color(0xFF4A5A70))),
          ]),
        ),
        const Divider(height: 1, color: Pal.line),
        if (paging != null) ProductPagingCount(paging!),
        Expanded(
          child: _scroll(ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: results.length + (_footer ? 1 : 0),
            itemBuilder: (_, i) => i >= results.length ? _footerRow() : _row(results[i]),
          )),
        ),
      ]);
    }
    final guided = style == ListPresentation.guided;
    final list = _scroll(ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: results.length + (_footer ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => i >= results.length ? _footerRow() : _card(results[i], band: guided && i == 0 ? Pal.navy : null),
    ));
    if (paging == null || !paging!.showCount) return list;
    return Column(children: [ProductPagingCount(paging!), Expanded(child: list)]);
  }
}

/// Ligne libellé / valeur des fiches (le texte long passe à la ligne sans déborder).
class DetailLine extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool compact;
  const DetailLine(this.label, this.value, {super.key, this.bold = false, this.compact = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(vertical: compact ? 10 : 6, horizontal: compact ? 16 : 0),
        decoration: compact ? const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))) : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Pal.muted, fontSize: 14))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 15, color: Pal.ink, fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
          ),
        ]),
      );
}

/// Tuile chiffrée de l'en-tête bleu (le chiffre se réduit au lieu de déborder).
class HeaderFigure extends StatelessWidget {
  final String value;
  final String label;
  final bool highlight;
  const HeaderFigure(this.value, this.label, {super.key, this.highlight = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: highlight ? Pal.amber : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: highlight ? Pal.onAmber : Colors.white)),
          ),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: highlight ? Pal.onAmber : const Color(0xFFDCE6F2))),
        ]),
      );
}
