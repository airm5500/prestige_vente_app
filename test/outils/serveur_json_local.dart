// Serveur HTTP local pour tester les clients JSON (Réserve, Analyse posologie, Fiche client) sans Prestige.
// Données entièrement fictives : aucune donnée réelle de patient ou de pharmacie.
//
// Base du faux serveur Prestige unifié (test/outils/faux_serveur_prestige.dart), qui ajoute les sessions
// (JSESSIONID), les routes Prestige par défaut, la coupure et un transport en mémoire pour les tests de widgets.
// L'interface d'origine (routes, recues, base, demarrer, arreter, recuesSur, avecVraiHttp) est inchangée.
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

  /// Identifiant de session (cookie JSESSIONID) envoyé, ou null.
  String? get jsessionid => RegExp(r'JSESSIONID=([^;\s]+)').firstMatch(cookie)?.group(1);

  @override
  String toString() => '$methode $chemin';
}

/// Réponse programmée : statut, corps (objet JSON, ou texte brut si String), délai avant réponse,
/// en-têtes supplémentaires (ex. set-cookie ; un « content-type » donné remplace celui par défaut).
/// [coupeeApres] (tests réseau) : la connexion est fermée après ce nombre d'octets du corps (réponse tronquée).
class ReponseLocale {
  final int statut;
  final Object? corps;
  final Duration delai;
  final Map<String, String> entetes;
  final int? coupeeApres;
  const ReponseLocale(this.corps, {this.statut = 200, this.delai = Duration.zero, this.entetes = const {}, this.coupeeApres});

  /// Corps envoyé (texte brut tel quel, sinon JSON).
  String get texte => corps is String ? corps as String : jsonEncode(corps);

  /// Type de contenu envoyé.
  String get typeContenu {
    for (final e in entetes.entries) {
      if (e.key.toLowerCase() == 'content-type') return e.value;
    }
    return corps is String ? 'text/plain; charset=utf-8' : 'application/json; charset=utf-8';
  }
}

class ServeurJsonLocal {
  HttpServer? _s;
  int _port = 0;
  final List<RequeteRecue> recues = [];

  /// Réponse par « MÉTHODE suffixe-de-chemin » (ex. 'PUT /ouvrir'). La première clé dont le suffixe correspond gagne.
  final Map<String, FutureOr<ReponseLocale> Function(RequeteRecue r)> routes = {};

  /// Hôte utilisé par [base] (127.0.0.1 en mode réseau local).
  String get hote => '127.0.0.1:$_port';

  /// HTTPS (4.1.0) : contexte TLS du serveur (certificat de test, voir test/outils/certificat_tls.dart). Null : HTTP.
  SecurityContext? contexteTls;

  String get base => '${contexteTls == null ? 'http' : 'https'}://$hote/prestige/api/v1';

  /// Réponse quand aucune route ne correspond.
  ReponseLocale get reponseInconnue => const ReponseLocale({'success': false, 'message': 'route inconnue'}, statut: 404);

  /// Route programmée correspondant à la requête, ou null.
  FutureOr<ReponseLocale> Function(RequeteRecue r)? routePour(RequeteRecue r) {
    for (final e in routes.entries) {
      final sp = e.key.indexOf(' ');
      if (r.methode == e.key.substring(0, sp) && r.chemin.endsWith(e.key.substring(sp + 1))) return e.value;
    }
    return null;
  }

  /// Traitement d'une requête (redéfini par le faux serveur Prestige) : la requête est déjà notée dans [recues].
  Future<ReponseLocale> repondre(RequeteRecue r) async {
    final route = routePour(r);
    return route == null ? reponseInconnue : await route(r);
  }

  /// Le serveur écoute-t-il ? (false avant [demarrer] ou pendant une coupure réseau).
  bool get ecoute => _s != null;

  Future<void> demarrer() async {
    final tls = contexteTls;
    final s = tls == null
        ? await HttpServer.bind(InternetAddress.loopbackIPv4, _port)
        : await HttpServer.bindSecure(InternetAddress.loopbackIPv4, _port, tls);
    _s = s;
    _port = s.port;
    s.listen((req) async {
      final corps = await utf8.decoder.bind(req).join();
      final r = RequeteRecue(req.method, req.uri.path, req.uri.queryParameters, corps, req.headers.value('cookie') ?? '');
      recues.add(r);
      final rep = await repondre(r);
      if (rep.delai > Duration.zero) await Future<void>.delayed(rep.delai);
      try {
        req.response.statusCode = rep.statut;
        rep.entetes.forEach((k, v) {
          if (k.toLowerCase() != 'content-type') req.response.headers.add(k, v);
        });
        req.response.headers.set('content-type', rep.typeContenu);
        final octets = utf8.encode(rep.texte);
        final coupe = rep.coupeeApres;
        if (coupe != null && coupe < octets.length) {
          // Réponse tronquée : longueur annoncée complète, connexion fermée au milieu du corps.
          req.response.contentLength = octets.length;
          req.response.add(octets.sublist(0, coupe));
          await req.response.flush();
          (await req.response.detachSocket(writeHeaders: false)).destroy();
          return;
        }
        req.response.add(octets);
        await req.response.close();
      } catch (_) {
        // client parti (délai dépassé)
      }
    }, onError: (Object _) {
      // HTTPS : poignée de main refusée par le client (certificat non approuvé) : rien à répondre.
    });
  }

  /// Arrêt du serveur (le port est gardé : [demarrer] le rouvre au même endroit).
  Future<void> arreter() async {
    final s = _s;
    _s = null;
    await s?.close(force: true);
  }

  List<RequeteRecue> recuesSur(String suffixe) => [for (final r in recues) if (r.chemin.endsWith(suffixe)) r];
}

class _VraiHttp extends HttpOverrides {}

/// Exécute [corps] avec le vrai client HTTP (les tests de widgets remplacent HttpClient).
Future<T> avecVraiHttp<T>(Future<T> Function() corps) => HttpOverrides.runWithHttpOverrides(corps, _VraiHttp());
