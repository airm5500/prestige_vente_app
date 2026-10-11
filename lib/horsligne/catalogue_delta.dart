// lib/horsligne/catalogue_delta.dart
// H5 — mise à jour DIFFÉRENTIELLE du catalogue produits (patch serveur docs/serveur/H5_catalogue_delta.patch).
//
// Un serveur avec le patch annonce `catalogueDelta: true` (+ son horloge `serveurMaintenant`) sur
// GET /app-vente/capacites et répond à GET /app-vente/catalogue/changements?depuis=…&jusqua=…&start&limit
// (premières versions du patch : /mobile/… ; préfixe détecté par routes_app_vente.dart et gardé avec le curseur) :
// seuls les produits modifiés depuis `depuis` (vente clôturée, ajustement, entrée de BL, inventaire, prix,
// activation / désactivation…), au format de /vente/search avec `statut: actif`, ou `{lgFAMILLEID,
// statut: supprime}` pour un produit à retirer de la copie.
//
// Fonctionnement (CatalogueSync) :
//  - copie COMPLÈTE la première fois, et une fois par jour (première mise à jour du jour : la nuit si l'appli
//    tourne, sinon à la première connexion) pour rattraper ce que les changements ne voient pas ;
//  - ensuite, toutes les 5 min en ligne, seulement les changements (pause pendant l'activité de l'appli) ;
//  - l'horloge est TOUJOURS celle du serveur : le curseur est le `serveurMaintenant` de la dernière mise à
//    jour (lu avant la copie complète, ou renvoyé par les changements), et la suivante demande depuis
//    curseur − 2 min (chevauchement de sécurité : une modification de la même seconde n'est jamais perdue) ;
//  - les changements sont écrits avec le nouveau curseur en UNE transaction (échec = rien d'appliqué) ;
//  - le curseur est lié à l'adresse du serveur : un autre serveur repart d'une copie complète.
// Serveur sans le patch (capacité absente, 401 « expire », 404) : comportement d'origine exact (copie
// complète toutes les 30 min), aucune requête supplémentaire toutes les 5 min.
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/routes_app_vente.dart';

abstract final class CatalogueDelta {
  /// Route des changements (préfixe actuel `/app-vente`).
  static const String route = '${RoutesAppVente.prefixe}/catalogue/changements';

  /// Route des changements pour le préfixe détecté (null : préfixe actuel).
  static String routePour(String? prefixe) => RoutesAppVente.catalogueChangements(prefixe ?? RoutesAppVente.prefixe);

  /// Intervalle des mises à jour différentielles (en ligne).
  static const Duration intervalle = Duration(minutes: 5);

  /// Chevauchement de sécurité : depuis = dernier serveurMaintenant − 2 min.
  static const Duration chevauchement = Duration(minutes: 2);

  // Clés `meta` de la copie locale.
  static const String kCurseur = 'delta_curseur';
  static const String kServeur = 'delta_serveur';
  static const String kComplet = 'delta_complet';
  static const String kMaj = 'delta_maj';
  static const String kN = 'delta_n';

  /// Préfixe des routes du serveur (`/app-vente` ou l'ancien `/mobile`), lu avec la capacité.
  static const String kPrefixe = 'delta_prefixe';
  static const String prefixe = 'delta_';

  /// Toutes les clés (effacées quand le serveur n'a plus la capacité).
  static const Map<String, String?> oubli = {kCurseur: null, kServeur: null, kComplet: null, kMaj: null, kN: null, kPrefixe: null};

  static final RegExp _heure = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})');

  /// Heure du serveur « 2026-10-10 23:14:35 » (sans fuseau : c'est l'horloge de la base) ; null si illisible.
  static DateTime? lireHeure(String? s) {
    final m = _heure.firstMatch((s ?? '').trim());
    if (m == null) return null;
    int g(int i) => int.parse(m.group(i)!);
    final d = DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6));
    // Rejette 2026-02-31 & co (DateTime normalise silencieusement).
    if (d.month != g(2) || d.day != g(3)) return null;
    return d;
  }

  static String ecrireHeure(DateTime d) {
    String z(int v, [int w = 2]) => '$v'.padLeft(w, '0');
    return '${z(d.year, 4)}-${z(d.month)}-${z(d.day)} ${z(d.hour)}:${z(d.minute)}:${z(d.second)}';
  }

  /// Paramètre `depuis` de la requête : curseur (heure du serveur) − [chevauchement].
  static String depuis(String curseur) => ecrireHeure(lireHeure(curseur)!.subtract(chevauchement));

  /// Lecture de GET …/capacites (RoutesAppVente.lireCapacites) : true/false si clair, null si indéterminé.
  static bool? capaciteDepuisReponse(int status, dynamic body) {
    if (status == 200 && body is Map) return body['catalogueDelta'] == true;
    if (status == 404) return false;
    if (status == 401 && body is Map && body.containsKey('expire')) return false;
    return null;
  }
}

/// État de la mise à jour différentielle (lu dans la copie locale).
class EtatDelta {
  /// Heure du serveur de la dernière mise à jour réussie (copie complète ou changements).
  final String? curseur;

  /// Serveur auquel se rapporte le curseur.
  final String? serveur;

  /// Dernière copie complète des produits faite avec la capacité (heure du téléphone).
  final DateTime? complet;

  /// Dernière mise à jour (complète ou différentielle) et nombre de produits modifiés (null : copie complète).
  final DateTime? maj;
  final int? n;

  /// Préfixe des routes du serveur au moment de la copie complète (null : préfixe actuel `/app-vente`).
  final String? prefixe;
  const EtatDelta({this.curseur, this.serveur, this.complet, this.maj, this.n, this.prefixe});

  static const vide = EtatDelta();

  factory EtatDelta.depuisMeta(Map<String, String> m) => EtatDelta(
        curseur: CatalogueDelta.lireHeure(m[CatalogueDelta.kCurseur]) == null ? null : m[CatalogueDelta.kCurseur],
        serveur: m[CatalogueDelta.kServeur],
        complet: DateTime.tryParse(m[CatalogueDelta.kComplet] ?? ''),
        maj: DateTime.tryParse(m[CatalogueDelta.kMaj] ?? ''),
        n: int.tryParse(m[CatalogueDelta.kN] ?? ''),
        prefixe: m[CatalogueDelta.kPrefixe],
      );

  /// Les changements sont utilisables pour ce serveur (copie complète déjà faite avec la capacité).
  bool actifPour(String serveurCle) => curseur != null && serveur == serveurCle;

  /// Vérification complète du jour à faire (aucune aujourd'hui, heure du téléphone).
  bool completDu(DateTime now) {
    final c = complet;
    return c == null || c.year != now.year || c.month != now.month || c.day != now.day || c.isAfter(now);
  }

  /// « Dernière mise à jour : il y a 3 min (12 produits modifiés) ».
  String? libelle(DateTime now) {
    final at = maj;
    if (curseur == null || at == null) return null;
    final d = now.difference(at);
    final quand = d.inMinutes < 1
        ? 'à l\'instant'
        : d.inHours < 1
            ? 'il y a ${d.inMinutes} min'
            : d.inDays < 1
                ? 'il y a ${d.inHours} h'
                : 'le ${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}';
    final quoi = n == null ? 'copie complète' : '$n produit${n! > 1 ? 's' : ''} modifié${n! > 1 ? 's' : ''}';
    return 'Dernière mise à jour : $quand ($quoi)';
  }
}

/// Changements téléchargés (toutes les pages, figées par `jusqua`).
class ChangementsCatalogue {
  /// Produits ajoutés / modifiés (JSON de /vente/search, sans `statut`).
  final List<Map<String, dynamic>> upserts;

  /// Identifiants à retirer de la copie.
  final List<String> suppressions;

  /// Nouveau curseur (horloge du serveur).
  final String serveurMaintenant;
  const ChangementsCatalogue(this.upserts, this.suppressions, this.serveurMaintenant);

  int get nombre => upserts.length + suppressions.length;
}

/// Télécharge les changements depuis [curseur] − 2 min ; lève [CatalogueSyncException] en cas d'échec.
Future<ChangementsCatalogue> telechargerChangements(CatalogueFetch f, String curseur,
    {int pageSize = 500, void Function(int done, int? total)? progress, String route = CatalogueDelta.route}) async {
  final depuis = CatalogueDelta.depuis(curseur);
  final upserts = <String, Map<String, dynamic>>{};
  final suppressions = <String>{};
  String? jusqua;
  var start = 0;
  int? total;
  var recus = 0;
  while (true) {
    final body = await f(route, {'depuis': depuis, if (jusqua != null) 'jusqua': jusqua, 'start': start, 'limit': pageSize});
    final t = '${body['serveurMaintenant'] ?? ''}';
    if (body['success'] == false || CatalogueDelta.lireHeure(t) == null || body['data'] is! List) {
      throw CatalogueSyncException('Réponse inattendue du serveur ($route).');
    }
    jusqua ??= t;
    total = int.tryParse('${body['total'] ?? ''}') ?? total;
    final data = body['data'] as List;
    for (final e in data) {
      if (e is! Map) continue;
      final r = Map<String, dynamic>.from(e);
      final id = '${r['lgFAMILLEID'] ?? ''}';
      if (id.isEmpty) continue;
      if (r.remove('statut') == 'supprime') {
        upserts.remove(id);
        suppressions.add(id);
      } else {
        suppressions.remove(id);
        upserts[id] = r;
      }
    }
    recus += data.length;
    progress?.call(recus, total);
    if (data.length < pageSize || data.isEmpty || (total != null && recus >= total)) break;
    start += pageSize;
  }
  return ChangementsCatalogue(upserts.values.toList(), suppressions.toList(), jusqua);
}
