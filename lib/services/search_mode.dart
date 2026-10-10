// lib/services/search_mode.dart
// Recherche texte « Commence par » / « Contient » (produits, clients, tiers payants).
// Le serveur cherche « commence par » (LIKE 'texte%') et accepte le joker % : en « Contient »,
// l'appli envoie « %mot1%mot2 » (docs/PLAN_EVOLUTION_MOBILE.md §7). Les CODES scannés ou tapés
// ne passent jamais par ici (recherche exacte, voir ProductLookup.byCode).
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SearchMode { commencePar, contient }

extension SearchModeInfo on SearchMode {
  String get label => switch (this) {
        SearchMode.commencePar => 'Commence par',
        SearchMode.contient => 'Contient',
      };

  /// Libellé court de la puce de bascule.
  String get short => switch (this) {
        SearchMode.commencePar => 'Début',
        SearchMode.contient => 'Contient',
      };

  /// « commence par » / « contient » dans une phrase.
  String get verbe => switch (this) {
        SearchMode.commencePar => 'commence par',
        SearchMode.contient => 'contient',
      };

  SearchMode get other => this == SearchMode.commencePar ? SearchMode.contient : SearchMode.commencePar;
}

/// Préférence mémorisée sur l'appareil (« Commence par » par défaut = comportement d'avant).
class SearchModePrefs {
  SearchModePrefs._();
  static const key = 'recherche_mode_v1';

  static final ValueNotifier<SearchMode> mode = ValueNotifier<SearchMode>(SearchMode.commencePar);

  static SearchMode get current => mode.value;

  static Future<SearchMode> load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(key);
      mode.value = v == SearchMode.contient.name ? SearchMode.contient : SearchMode.commencePar;
    } catch (_) {}
    return mode.value;
  }

  static Future<void> save(SearchMode value) async {
    mode.value = value;
    try {
      await (await SharedPreferences.getInstance()).setString(key, value.name);
    } catch (_) {}
  }

  static Future<void> toggle() => save(current.other);
}

/// « Contient » à partir de 3 caractères (comme la recherche produit des ventes) ;
/// en dessous, la recherche reste « commence par ».
const int contientMinLength = 3;

/// Mode à appliquer à [text] : le réglage ([mode], sinon celui de l'appareil), sauf texte trop court.
SearchMode modeFor(String text, [SearchMode? mode]) {
  final m = mode ?? SearchModePrefs.current;
  return m == SearchMode.contient && text.trim().length < contientMinLength ? SearchMode.commencePar : m;
}

final RegExp _jokers = RegExp(r'[%_]');
final RegExp _separators = RegExp(r'[\s%_]+');

/// Texte envoyé au serveur pour une recherche TEXTE (jamais pour un code).
/// Les jokers SQL tapés (% et _) sont neutralisés :
/// - « Commence par » : jokers du début retirés, texte coupé au premier joker restant
///   (« BETADINE 10% » → « BETADINE 10 ») : le serveur renvoie au moins tous les produits
///   dont le nom commence par le texte tapé ; sans joker, le texte est inchangé.
/// - « Contient » : % et _ comptent comme des espaces ; « doli 1000 » → « %doli%1000 ».
/// Renvoie '' s'il ne reste rien à chercher.
String serverQuery(String text, SearchMode mode) {
  final t = text.trim();
  if (mode == SearchMode.contient) {
    final words = t.split(_separators).where((w) => w.isNotEmpty).toList();
    return words.isEmpty ? '' : '%${words.join('%')}';
  }
  var q = t.replaceFirst(RegExp(r'^[\s%_]+'), '');
  final i = q.indexOf(_jokers);
  if (i >= 0) q = q.substring(0, i).trimRight();
  return q;
}

/// Puce « Début / Contient » : bascule la recherche texte (même réglage que les Réglages).
class SearchModeChip extends StatelessWidget {
  final VoidCallback? onToggle;
  const SearchModeChip({super.key, this.onToggle});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SearchMode>(
        valueListenable: SearchModePrefs.mode,
        builder: (context, mode, _) {
          final on = mode == SearchMode.contient;
          return Tooltip(
            message: 'Recherche : ${mode.verbe} le texte tapé. Toucher pour « ${mode.other.label} ».',
            child: InkWell(
              key: const ValueKey('recherche-mode'),
              borderRadius: BorderRadius.circular(8),
              onTap: onToggle ?? SearchModePrefs.toggle,
              child: Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? const Color(0xFFFFF3D6) : const Color(0xFFE9EEF5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: on ? const Color(0xFFF59E0B) : const Color(0xFFC5D0DE)),
                ),
                child: Text(mode.short,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? const Color(0xFF92400E) : const Color(0xFF334155))),
              ),
            ),
          );
        },
      );
}
