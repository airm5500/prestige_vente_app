// lib/horsligne/routes_app_vente.dart
// Routes des patchs serveur de l'appli de vente (H4 clé client, H5 catalogue différentiel, O4 corrections
// d'ordonnances, O5 lecture avancée) et détection de leur préfixe.
//
// Les patchs serveur actuels (docs/serveur/*.patch, 11/10/2026) servent ces routes sous `v1/app-vente/…`, avec la
// session habituelle de l'appli : le préfixe `v1/mobile/` est réservé, sur la branche serveur à jour, à l'API mobile à
// jeton Bearer. Les premières versions des patchs (encore installées sur le serveur de test) utilisaient
// `v1/mobile/…` : l'appli reste compatible avec elles.
//
// Détection ([lireCapacites]) : GET /app-vente/capacites ; s'il répond 404 (route inconnue de ce serveur), repli sur
// l'ancien GET /mobile/capacites. Le préfixe de la route qui a répondu 200 est retenu pour ce serveur
// ([prefixePour]) et sert aux autres routes (client-ref, catalogue/changements, ordonnances/…). Aucune des deux :
// la réponse du repli est rendue telle quelle (404, ou 401 « expire » de l'API à jeton = capacité absente).
// Toute autre réponse du nouveau chemin (401 de session, 500…) est rendue sans repli : « indéterminé ».

/// Lecture brute d'une route (code HTTP et corps, sans lever d'exception pour un 401 / 404).
typedef LectureRoute = Future<({int status, Object? body})> Function(String chemin);

abstract final class RoutesAppVente {
  /// Préfixe actuel des patchs serveur (`v1/app-vente/`).
  static const String prefixe = '/app-vente';

  /// Ancien préfixe (premières versions des patchs, serveur de test).
  static const String ancienPrefixe = '/mobile';

  static String capacites([String p = prefixe]) => '$p/capacites';
  static String clientRef(String ref, [String p = prefixe]) => '$p/client-ref/${Uri.encodeComponent(ref)}';
  static String catalogueChangements([String p = prefixe]) => '$p/catalogue/changements';
  static String ordonnancesCorrections([String p = prefixe]) => '$p/ordonnances/corrections';
  static String lectureAvancee([String p = prefixe]) => '$p/ordonnances/lecture-avancee';

  static final Map<String, String> _prefixes = {};

  /// Préfixe détecté pour [serveur] (adresse) ; le préfixe actuel tant que rien n'a été détecté.
  static String prefixePour(String serveur) => _prefixes[serveur] ?? prefixe;

  /// Un préfixe a été détecté pour [serveur].
  static bool connu(String serveur) => _prefixes.containsKey(serveur);

  /// Oublie tout (tests).
  static void vider() => _prefixes.clear();

  /// Capacités de [serveur] : nouveau chemin, puis l'ancien si le nouveau répond 404. Retient le préfixe trouvé.
  /// `prefixe` : celui de la réponse 200, null sinon. Les exceptions (réseau) de [lire] remontent.
  static Future<({int status, Object? body, String? prefixe})> lireCapacites(String serveur, LectureRoute lire) async {
    final a = await lire(capacites(prefixe));
    if (a.status == 200 && a.body is Map) {
      _prefixes[serveur] = prefixe;
      return (status: a.status, body: a.body, prefixe: prefixe);
    }
    if (a.status != 404) return (status: a.status, body: a.body, prefixe: null);
    final b = await lire(capacites(ancienPrefixe));
    if (b.status == 200 && b.body is Map) {
      _prefixes[serveur] = ancienPrefixe;
      return (status: b.status, body: b.body, prefixe: ancienPrefixe);
    }
    return (status: b.status, body: b.body, prefixe: null);
  }
}
