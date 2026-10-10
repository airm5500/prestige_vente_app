// lib/horsligne/horsligne.dart
// Point d'entrée du hors ligne (étape H1) : surveillance du serveur, copie locale, synchro,
// et recherche produit des nouveaux écrans qui bascule sur la copie locale UNIQUEMENT
// quand l'état est « hors ligne » (en ligne : appel serveur inchangé).
// Étape H2 : file des ventes saisies hors ligne, envoyée automatiquement au retour du serveur.
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/horsligne/activite_app.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/horsligne/ventes_sync.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

class HorsLigne {
  final ServerMonitor monitor;
  final LocalStore store;
  final CatalogueSync sync;

  /// File des ventes saisies hors ligne (étape H2).
  final FileVentesHL ventes;

  /// Ventes en attente d'envoi (null : aucune, rien affiché).
  final ValueNotifier<int?> ventesEnAttente = ValueNotifier<int?>(null);

  /// Navigateur de l'appli (ouverture de l'écran « Ventes hors ligne » depuis le bandeau).
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  EtatServeur _etat;

  HorsLigne._(this.monitor, this.store, this.sync, this.ventes) : _etat = monitor.etat {
    ventes.addListener(_onVentes);
    monitor.addListener(_onMonitor);
  }

  factory HorsLigne({ServerMonitor? monitor, LocalStore? store, CatalogueSync? sync, FileVentesHL? ventes}) {
    final s = store ?? sync?.store ?? SqfliteLocalStore();
    return HorsLigne._(monitor ?? ServerMonitor(), s, sync ?? CatalogueSync(store: s), ventes ?? FileVentesHL(store: SqfliteVentesHLStore()));
  }

  void _onVentes() {
    final n = ventes.enAttente;
    ventesEnAttente.value = n > 0 ? n : null;
  }

  /// Retour en ligne : confirmation demandée avant d'envoyer les ventes en attente.
  void _onMonitor() {
    final avant = _etat;
    _etat = monitor.etat;
    if (_etat == EtatServeur.enLigne && avant != EtatServeur.enLigne) ventes.demanderConfirmation();
  }

  /// Ventes hors ligne : file chargée, puis confirmation si le serveur répond (après la connexion).
  Future<void> demarrerVentes() async {
    await ventes.ensureLoaded();
    if (monitor.etat == EtatServeur.enLigne) await ventes.demanderConfirmation();
  }

  /// Instance de l'appli (remplaçable dans les tests).
  static HorsLigne instance = HorsLigne();

  bool get offline => monitor.isOffline;

  /// « 10/10 08:30 » : date du catalogue local.
  static String formatDate(DateTime d) => DateFormat('dd/MM HH:mm').format(d);

  /// « catalogue du 10/10 08:30 » (ou « aucun catalogue local »).
  String get catalogueLabel {
    final at = sync.catalogueAt;
    return at == null ? 'aucun catalogue local' : 'catalogue du ${formatDate(at)}';
  }

  /// Recherche produit par pages dans la copie locale (même format que le serveur).
  Future<VenteResult<ProductPage>> localPage(String query, int start, int limit) async {
    try {
      if (!sync.statsLoaded) await sync.refreshStats();
      if (sync.stats.count(CatalogueCategorie.produits) == 0) {
        return const VenteFailed('Hors ligne : aucun catalogue sur cet appareil. '
            'Mettez-le à jour quand le serveur répond (Réglages › Hors ligne).');
      }
      return VenteOk(await store.searchProducts(query, start, limit));
    } catch (e) {
      return VenteFailed('Hors ligne : recherche locale impossible ($e).');
    }
  }

  // ---------------------------------------------------------------------------
  // Branchement sur l'appli (serveur réel)
  // ---------------------------------------------------------------------------

  ApiService? _api;
  Dio? _pingDio;
  Dio? _syncDio;

  /// Relie la surveillance et la synchro à l'[ApiService] courant (adresse du serveur, session).
  void bind(ApiService api) {
    _api = api;
    final dio = api.dio;
    if (!dio.interceptors.any((i) => i is ServerMonitorInterceptor)) {
      dio.interceptors.add(ServerMonitorInterceptor(() => monitor));
    }
    // Requêtes de l'utilisateur en cours : la mise à jour automatique de la copie se met en pause.
    if (!dio.interceptors.any((i) => i is ActiviteInterceptor)) dio.interceptors.add(ActiviteInterceptor());
    monitor.ping ??= _ping;
    sync.fetch ??= _fetch;
    // Mêmes appels que la vente en ligne (session de l'appli).
    if (ventes.gateway == null || ventes.gateway is DioVenteGateway) ventes.gateway = DioVenteGateway(api);
  }

  String get _baseUrl => _api?.dio.options.baseUrl ?? '';

  /// GET /officine, délai court, sans journal ni session.
  Future<bool> _ping() async {
    final d = _pingDio ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      validateStatus: (_) => true,
    ));
    d.options.baseUrl = _baseUrl;
    try {
      final r = await d.get('/officine');
      final code = r.statusCode ?? 0;
      return code > 0 && code < 500;
    } catch (_) {
      return false;
    }
  }

  /// GET pour la synchro : même session (cookies) que l'appli, sans le journal des réponses.
  Future<Map<String, dynamic>> _fetch(String path, Map<String, dynamic> query) async {
    // BackgroundTransformer (défaut de Dio 5, rendu explicite) : grosses réponses JSON décodées hors du thread UI.
    final d = _syncDio ??= (Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 60)))
      ..transformer = BackgroundTransformer()
      ..interceptors.add(CookieManager(DioClient.cookieJar)));
    d.options.baseUrl = _baseUrl;
    try {
      final r = await d.get(path, queryParameters: query);
      monitor.signalReachable();
      final body = r.data;
      if (body is Map) return Map<String, dynamic>.from(body);
      throw CatalogueSyncException('Réponse inattendue du serveur ($path). La session a peut-être expiré : reconnectez-vous.');
    } on DioException catch (e) {
      if (ServerMonitor.isNetworkError(e)) {
        monitor.signalNetworkFailure();
        throw const CatalogueSyncException('Serveur injoignable.', network: true);
      }
      final code = e.response?.statusCode ?? 0;
      if (code == 401 || code == 403) throw const CatalogueSyncException('Session expirée : reconnectez-vous.');
      if (e.type == DioExceptionType.receiveTimeout) throw const CatalogueSyncException('Le serveur met trop de temps à répondre.', network: true);
      throw CatalogueSyncException('Erreur du serveur${code > 0 ? ' (code $code)' : ''}.');
    }
  }
}

/// Recherche par pages des nouveaux écrans : copie locale si hors ligne, sinon [online] (inchangé).
ProductPageSearch offlineAware(ProductPageSearch online) =>
    (query, start, limit) => HorsLigne.instance.offline ? HorsLigne.instance.localPage(query, start, limit) : online(query, start, limit);
