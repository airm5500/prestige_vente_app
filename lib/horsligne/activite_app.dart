// lib/horsligne/activite_app.dart
// Activité de l'utilisateur vue depuis les appels au serveur de l'appli (vente, réception, pointage…) :
// la mise à jour AUTOMATIQUE de la copie locale se met en pause tant qu'une requête de l'appli est en
// cours ou vient de se terminer, pour que les requêtes de l'utilisateur passent toujours avant.
// Aucune modification des écrans : un intercepteur observe le Dio de l'appli.
import 'package:dio/dio.dart';

class ActiviteApp {
  ActiviteApp._();

  static int _enCours = 0;
  static DateTime? _derniere;

  /// Autres signaux « occupé » (ex. file d'opérations d'un écran), ajoutés par les modules.
  static final List<bool Function()> occupations = [];

  /// Délai de calme après la dernière requête de l'appli.
  static Duration calme = const Duration(seconds: 2);

  static int get enCours => _enCours;

  static void debut() {
    _enCours++;
    _derniere = DateTime.now();
  }

  static void fin() {
    if (_enCours > 0) _enCours--;
    _derniere = DateTime.now();
  }

  /// L'utilisateur travaille (requête en cours, récente, ou module occupé) ?
  static bool get occupee {
    final d = _derniere;
    // Garde-fou : un compteur resté bloqué (réponse jamais reçue) ne bloque pas plus de 2 min.
    if (_enCours > 0 && (d == null || DateTime.now().difference(d) < const Duration(minutes: 2))) return true;
    if (d != null && DateTime.now().difference(d) < calme) return true;
    return occupations.any((o) {
      try {
        return o();
      } catch (_) {
        return false;
      }
    });
  }

  /// Remise à zéro (tests).
  static void reset() {
    _enCours = 0;
    _derniere = null;
    occupations.clear();
    calme = const Duration(seconds: 2);
  }
}

/// Compte les requêtes de l'appli en cours (posé sur le Dio de l'appli, pas sur celui de la synchro).
class ActiviteInterceptor extends Interceptor {
  static const _cle = 'hl_activite';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_cle] = true;
    ActiviteApp.debut();
    handler.next(options);
  }

  void _fin(RequestOptions o) {
    if (o.extra.remove(_cle) == true) ActiviteApp.fin();
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _fin(response.requestOptions);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _fin(err.requestOptions);
    handler.next(err);
  }
}
