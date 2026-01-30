// lib/providers/article_analysis_provider.dart
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/article_analysis_model.dart';

class ArticleAnalysisProvider with ChangeNotifier {
  final ApiService _apiService;

  List<ArticleAnalysis> _results = [];
  List<ArticleAnalysis> get results => _results;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  ArticleAnalysisProvider(this._apiService);

  void clear() {
    _results = [];
    notifyListeners();
  }

  Future<void> searchArticles(String query) async {
    // Règle métier : 2 chars pour libellé, 3 pour cip (approximatif, on bloque si < 2 globalement)
    if (query.trim().length < 2) {
      _results = [];
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      _results = await _apiService.fetchArticleAnalysis(query);
    } catch (e) {
      _results = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}