// lib/providers/licence_provider.dart
// 30/12/2025 03:30 (Correction : Gestion stricte Serveur Local + Fix updateApiService)
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/licence_model.dart';

enum LicenceStatus {
  loading,
  valid,
  expired,
  none,
  error // Signifie "Erreur Technique / Réseau"
}

class LicenceProvider with ChangeNotifier {
  // On enlève 'final' pour pouvoir le mettre à jour
  ApiService _apiService;

  LicenceModel? _licence;
  LicenceStatus _status = LicenceStatus.loading;
  String _errorMessage = '';

  LicenceProvider(this._apiService);

  LicenceModel? get licence => _licence;
  LicenceStatus get status => _status;
  String get errorMessage => _errorMessage;

  // CORRECTION CRITIQUE : Cette méthode doit vraiment mettre à jour la variable
  void updateApiService(ApiService newApiService) {
    _apiService = newApiService;
  }

  int get remainingDays {
    if (_licence == null) return 0;
    try {
      final end = DateTime.parse(_licence!.dateEnd);
      final now = DateTime.now();
      final endDate = DateTime(end.year, end.month, end.day);
      final nowDate = DateTime(now.year, now.month, now.day);
      return endDate.difference(nowDate).inDays;
    } catch (e) {
      return 0;
    }
  }

  bool checkLocalExpiration() {
    if (_licence == null) return true;
    return _isExpired(_licence!.dateEnd);
  }

  Future<LicenceStatus> checkLicence() async {
    _status = LicenceStatus.loading;
    notifyListeners();

    try {
      // Appel direct au serveur (Pas de cache)
      final result = await _apiService.findLicence();

      if (result != null) {
        _licence = result;
        if (_isExpired(result.dateEnd)) {
          _status = LicenceStatus.expired;
        } else {
          _status = LicenceStatus.valid;
        }
      } else {
        // Le serveur a répondu (200 OK) mais renvoie null -> Pas de licence enregistrée
        _licence = null;
        _status = LicenceStatus.none;
      }
    } catch (e) {
      // Le serveur est injoignable ou renvoie une erreur 500/404
      print("Erreur Licence: $e");
      _status = LicenceStatus.error;
      _errorMessage = "Impossible de joindre le serveur local. Vérifiez votre Wifi/Câble.";
    }

    notifyListeners();
    return _status;
  }

  Future<bool> registerLicence(String key) async {
    _status = LicenceStatus.loading;
    notifyListeners();

    // Protection crash si API mal configurée
    try {
      final success = await _apiService.saveLicence(key);
      if (success) {
        await checkLicence();
        return _status == LicenceStatus.valid;
      } else {
        _status = LicenceStatus.error;
        _errorMessage = "Clé invalide ou refusée par le serveur.";
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = LicenceStatus.error;
      _errorMessage = "Erreur connexion lors de l'enregistrement.";
      notifyListeners();
      return false;
    }
  }

  bool _isExpired(String dateEndStr) {
    try {
      final end = DateTime.parse(dateEndStr);
      final now = DateTime.now();
      final endOfDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
      return now.isAfter(endOfDay);
    } catch (e) {
      return true;
    }
  }

  void checkReminders(BuildContext context) {
    if (_status != LicenceStatus.valid || _licence == null) return;

    // Logique identique à avant pour les popups...
    final days = remainingDays;
    String? message;
    if (days == 90) message = "Rappel : Votre licence expire dans 3 mois.";
    else if (days == 30) message = "Attention : Votre licence expire dans 1 mois.";
    else if (days == 7) message = "Urgent : Plus qu'une semaine avant l'expiration.";
    else if (days == 1) message = "Dernier jour ! Votre licence expire demain.";

    if (message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(context: context, builder: (ctx) => AlertDialog(
          title: const Text("Expiration Licence"), content: Text(message!),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
        ));
      });
    }
  }
}