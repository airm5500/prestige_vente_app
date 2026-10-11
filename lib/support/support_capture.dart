// lib/support/support_capture.dart
// Centre de support : captures automatiques.
// - Erreurs Flutter non gérées (FlutterError.onError, PlatformDispatcher.onError) : type MOBILE / ERROR
//   (équivalent des erreurs « JS » du web), urlOuEcran = écran affiché, module = module de l'écran.
// - Échecs HTTP inattendus (intercepteur Dio) : format « AJAX » du web (ERROR si ≥ 500, sinon WARN,
//   « Échec Ajax HTTP <code> <libellé> », url, corps de la réponse filtré). Jamais : les 401 de session,
//   les échecs réseau purs, les requêtes annulées, les envois du support lui-même.
// - Fil d'Ariane : écrans ouverts (observateur de navigation) et appels API (sans paramètres).
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/support/support_centre.dart';
import 'package:prestige_vente_app/support/support_event.dart';

/// Module métier d'un chemin d'API (sinon MOBILE).
String moduleDuChemin(String chemin) {
  final p = chemin.toLowerCase();
  bool a(String re) => RegExp(re).hasMatch(p);
  if (a(r'/(vente|ventestats|caisse|billetage|reglement|modereglement|proforma|tierspayant|client|carnet|assurance|depot)')) return 'VENTE';
  if (a(r'/(commande|fichearticle|gestionperime|retourfournisseur|ajustement|produit|stock|inventaire|emplacement|info)')) return 'STOCK';
  if (a(r'/(pointage|employe|badge)')) return 'POINTAGE';
  if (a(r'/(mobile|app-vente)/')) return 'HORS_LIGNE';
  return 'MOBILE';
}

/// Module métier d'un écran (nom du widget), sinon MOBILE.
String moduleDeLEcran(String ecran) {
  final e = ecran.toLowerCase();
  if (e.contains('horsligne') || e.contains('journal')) return 'HORS_LIGNE';
  if (RegExp(r'vente|sale|caisse|encaissement|paiement|carnet|assurance|proforma|depot').hasMatch(e)) return 'VENTE';
  if (RegExp(r'reception|blcontrol|bllist|bldetail|stock|perime|expiration|retour|ajustement|inventaire|emplacement|commande|delivery|article|produit')
      .hasMatch(e)) {
    return 'STOCK';
  }
  if (RegExp(r'pointage|employee|badge').hasMatch(e)) return 'POINTAGE';
  return 'MOBILE';
}

/// Exceptions de réseau pur : pas une anomalie de l'app (le serveur était injoignable).
bool erreurReseau(Object e) {
  if (e is SocketException || e is TimeoutException || e is HttpException || e is HandshakeException) return true;
  if (e is DioException) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError ||
      DioExceptionType.cancel =>
        true,
      DioExceptionType.unknown => e.response == null,
      _ => false,
    };
  }
  return false;
}

/// Événement « erreur Flutter non gérée ».
SupportEvent? evenementErreur(Object exception, StackTrace? stack, {required String ecran, String? contexte}) {
  if (erreurReseau(exception)) return null;
  final texte = '$exception'.trim();
  var message = texte.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => exception.runtimeType.toString()).trim();
  if (message.isEmpty) message = exception.runtimeType.toString();
  // Débordement de mise en page : défaut d'affichage, pas une panne.
  final niveau = message.contains('overflowed') ? NiveauSupport.warn : NiveauSupport.error;
  final pile = StringBuffer(tronquer('${exception.runtimeType}: $message', 500));
  if (contexte != null && contexte.isNotEmpty) pile.write('\n($contexte)');
  if (stack != null) pile.write('\n$stack');
  return SupportEvent(
    type: TypeSupport.mobile,
    niveau: niveau,
    module: moduleDeLEcran(ecran),
    messageCourt: tronquer(message, BornesSupport.messageCourt),
    urlOuEcran: tronquer(ecran.isEmpty ? 'Application' : ecran, BornesSupport.urlOuEcran),
    stack: tronquer(pile.toString(), 8000),
  );
}

/// Branche la capture des erreurs Flutter (en chaîne avec les gestionnaires existants).
void installerCaptureErreurs({SupportCentre Function()? centre}) {
  SupportCentre c() => (centre ?? () => SupportCentre.instance)();
  final avantFlutter = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    try {
      final e = evenementErreur(d.exception, d.stack, ecran: c().ecran, contexte: d.context?.toDescription());
      if (e != null && !d.silent) unawaited(c().signaler(e));
    } catch (_) {}
    if (avantFlutter != null) {
      avantFlutter(d);
    } else {
      FlutterError.presentError(d);
    }
  };
  final dispatcher = PlatformDispatcher.instance;
  final avant = dispatcher.onError;
  dispatcher.onError = (Object error, StackTrace stack) {
    try {
      final e = evenementErreur(error, stack, ecran: c().ecran);
      if (e != null) unawaited(c().signaler(e));
    } catch (_) {}
    return avant?.call(error, stack) ?? false;
  };
}

/// Fil d'Ariane des écrans + écran courant.
class SupportNavigatorObserver extends NavigatorObserver {
  final SupportCentre Function() centre;
  SupportNavigatorObserver({SupportCentre Function()? centre}) : centre = centre ?? (() => SupportCentre.instance);

  static final RegExp _ecran = RegExp(r'(Screen|Page|Ecran|Scaffold\w+)$');

  /// Nom de l'écran d'une route : nom déclaré, sinon premier widget « …Screen / …Page » de la page.
  static String nomEcran(Route<dynamic>? r) {
    if (r == null) return '';
    final n = r.settings.name;
    if (n != null && n.isNotEmpty && n != '/') return n;
    if (r is ModalRoute) {
      final ctx = r.subtreeContext;
      if (ctx != null) {
        final trouve = _chercher(ctx);
        if (trouve != null) return trouve;
      }
    }
    return '';
  }

  static String? _chercher(BuildContext ctx) {
    String? nom;
    var vus = 0;
    void visiter(Element e, int profondeur) {
      if (nom != null || vus > 400 || profondeur > 40) return;
      vus++;
      final t = e.widget.runtimeType.toString();
      if (!t.startsWith('_') && _ecran.hasMatch(t) && t != 'Scaffold') {
        nom = t.split('<').first;
        return;
      }
      e.visitChildElements((x) => visiter(x, profondeur + 1));
    }

    try {
      ctx.visitChildElements((x) => visiter(x, 0));
    } catch (_) {}
    return nom;
  }

  void _afficher(Route<dynamic>? r) {
    if (r is! PageRoute) return;
    void noter() {
      final nom = nomEcran(r);
      if (nom.isNotEmpty) centre().noterEcran(nom);
    }

    // La page n'est construite qu'à l'image suivante.
    if (r.subtreeContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => noter());
    } else {
      noter();
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _afficher(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _afficher(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _afficher(previousRoute);
  }
}

/// Intercepteur Dio de l'app : fil d'Ariane des appels et échecs HTTP inattendus (format AJAX du web).
class SupportInterceptor extends Interceptor {
  final SupportCentre Function() centre;
  SupportInterceptor({SupportCentre Function()? centre}) : centre = centre ?? (() => SupportCentre.instance);

  static bool _support(RequestOptions o) {
    if (o.extra[SupportCles.ignorer] == true) return true;
    final p = o.uri.path;
    return p.contains('/support/events') || p.contains('/support-contact');
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      if (!_support(options)) centre().noterApi(options.method, options.uri.toString());
    } catch (_) {}
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    try {
      final e = evenementHttp(err);
      if (e != null) unawaited(centre().signaler(e));
    } catch (_) {}
    handler.next(err);
  }

  /// Événement « AJAX » d'un échec HTTP, ou null s'il ne faut pas le signaler.
  static SupportEvent? evenementHttp(DioException err) {
    final o = err.requestOptions;
    if (_support(o)) return null;
    if (err.type != DioExceptionType.badResponse) return null; // réseau pur, délai, annulation (doublon bloqué)
    final r = err.response;
    final status = r?.statusCode ?? 0;
    if (status == 0 || status == 401) return null; // 0 : non actionnable ; 401 : session expirée
    if (status < 400) return null;
    final chemin = SupportFiltre.chemin(o.uri.toString());
    return SupportEvent(
      type: TypeSupport.ajax,
      niveau: status >= 500 ? NiveauSupport.error : NiveauSupport.warn,
      module: moduleDuChemin(chemin),
      messageCourt: tronquer('Échec Ajax HTTP $status ${r?.statusMessage ?? ''}', BornesSupport.messageCourt),
      urlOuEcran: chemin,
      stack: SupportFiltre.corpsReponse(r?.data),
    );
  }
}
