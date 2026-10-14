// lib/providers/article_analysis_provider.dart
// Analyse article (GET /info?search=…) :
// - une seule requête en vol : chaque nouvelle recherche ANNULE la précédente (frappe suivante, effacement) ;
// - jamais « rien » : chargement, résultats, « aucun produit » ou erreur précise (code HTTP, délai, session
//   expirée, réponse illisible) avec Réessayer ;
// - délai maximal (ApiService.delaiInfo) : jamais de roue sans fin.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/article_analysis_model.dart';
import 'package:prestige_vente_app/services/classement_code.dart';

class ArticleAnalysisProvider with ChangeNotifier {
  final ApiService _apiService;

  List<ArticleAnalysis> _results = [];
  List<ArticleAnalysis> get results => _results;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Panne de la dernière recherche (cause précise) ; null si le serveur a répondu.
  String? _error;
  String? get error => _error;

  /// Texte de la dernière recherche envoyée ('' : aucune).
  String _query = '';
  String get query => _query;

  /// Le serveur a répondu sans aucun produit pour [query].
  bool get aucunResultat => !_isLoading && _error == null && _query.isNotEmpty && _results.isEmpty;

  /// Diagnostic (tests) : requêtes envoyées / annulées car remplacées.
  int requetes = 0;
  int annulees = 0;

  CancelToken? _jeton;
  int _seq = 0;

  ArticleAnalysisProvider(this._apiService);

  /// Abandonne la requête en vol (remplacée ou écran effacé).
  void _annuler() {
    final j = _jeton;
    _jeton = null;
    if (j != null && !j.isCancelled) {
      annulees++;
      j.cancel('Recherche remplacée');
    }
  }

  void clear() {
    _seq++;
    _annuler();
    _results = [];
    _error = null;
    _query = '';
    _isLoading = false;
    notifyListeners();
  }

  /// Relance la dernière recherche (bouton Réessayer).
  Future<void> reessayer() => searchArticles(_query);

  Future<void> searchArticles(String query) async {
    final q = query.trim();
    // Règle métier : on lance la recherche si au moins 2 caractères
    if (q.length < 2) {
      clear();
      return;
    }
    _annuler();
    final seq = ++_seq;
    final jeton = CancelToken();
    _jeton = jeton;
    _query = q;
    _error = null;
    _isLoading = true;
    notifyListeners();

    List<ArticleAnalysis> lignes = const [];
    String? erreur;
    try {
      requetes++;
      lignes = await ApiService.avecJeton(jeton, () => _apiService.fetchArticleAnalysis(q))
          .timeout(ApiService.delaiInfo + const Duration(seconds: 5), onTimeout: () {
        jeton.cancel('Délai dépassé');
        throw TimeoutException('GET /info');
      });
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel && seq != _seq) return; // remplacée : rien à afficher
      erreur = ApiService.messageErreurInfo(e);
    } catch (e) {
      erreur = ApiService.messageErreurInfo(e);
    }
    if (seq != _seq) return; // une recherche plus récente a pris la main
    if (identical(_jeton, jeton)) _jeton = null;
    // Saisie en chiffres : CIP commençant par la saisie en tête (exact d'abord), reste dans l'ordre du serveur
    // (4.0.3, F3 ; un nom n'est jamais réordonné).
    _results = erreur == null ? classerParCode(lignes, q, (a) => a.codeCip) : [];
    _error = erreur;
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _annuler();
    super.dispose();
  }
}
