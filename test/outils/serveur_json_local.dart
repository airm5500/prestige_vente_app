// Serveur HTTP local pour tester les clients JSON (Réserve, Analyse posologie, Fiche client) sans Prestige.
// Données entièrement fictives : aucune donnée réelle de patient ou de pharmacie.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Requête reçue par le serveur local.
class RequeteRecue {
  final String methode;
  final String chemin;
  final Map<String, String> query;
  final String corps;
  final String cookie;
  RequeteRecue(this.methode, this.chemin, this.query, this.corps, this.cookie);

  Map<String, dynamic> get json => corps.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(corps) as Map);
}

/// Réponse programmée : statut, corps (objet JSON, ou texte brut si String), délai avant réponse.
class ReponseLocale {
  final int statut;
  final Object? corps;
  final Duration delai;
  const ReponseLocale(this.corps, {this.statut = 200, this.delai = Duration.zero});
}

class ServeurJsonLocal {
  late HttpServer _s;
  final List<RequeteRecue> recues = [];

  /// Réponse par « MÉTHODE suffixe-de-chemin » (ex. 'PUT /ouvrir'). La première clé dont le suffixe correspond gagne.
  final Map<String, FutureOr<ReponseLocale> Function(RequeteRecue r)> routes = {};

  String get base => 'http://127.0.0.1:${_s.port}/prestige/api/v1';

  Future<void> demarrer() async {
    _s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _s.listen((req) async {
      final corps = await utf8.decoder.bind(req).join();
      final r = RequeteRecue(req.method, req.uri.path, req.uri.queryParameters, corps, req.headers.value('cookie') ?? '');
      recues.add(r);
      ReponseLocale rep = const ReponseLocale({'success': false, 'message': 'route inconnue'}, statut: 404);
      for (final e in routes.entries) {
        final sp = e.key.indexOf(' ');
        if (req.method == e.key.substring(0, sp) && req.uri.path.endsWith(e.key.substring(sp + 1))) {
          rep = await e.value(r);
          break;
        }
      }
      if (rep.delai > Duration.zero) await Future<void>.delayed(rep.delai);
      try {
        req.response.statusCode = rep.statut;
        if (rep.corps is String) {
          req.response.headers.contentType = ContentType.text;
          req.response.write(rep.corps);
        } else {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(rep.corps));
        }
        await req.response.close();
      } catch (_) {
        // client parti (délai dépassé)
      }
    });
  }

  Future<void> arreter() => _s.close(force: true);

  List<RequeteRecue> recuesSur(String suffixe) => [for (final r in recues) if (r.chemin.endsWith(suffixe)) r];
}

class _VraiHttp extends HttpOverrides {}

/// Exécute [corps] avec le vrai client HTTP (les tests de widgets remplacent HttpClient).
Future<T> avecVraiHttp<T>(Future<T> Function() corps) => HttpOverrides.runWithHttpOverrides(corps, _VraiHttp());
