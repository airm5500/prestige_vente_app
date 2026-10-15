// lib/providers/licence_provider.dart
// 30/12/2025 03:30 (Correction : Gestion stricte Serveur Local + Fix updateApiService)
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/licence_model.dart';
import 'package:prestige_vente_app/api/models/licence_lookup.dart';
import 'package:prestige_vente_app/serveur/adresse_serveur.dart';

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
  LicenceIssue? _issue; // Cause précise quand status == error (connexion / serveur)

  LicenceProvider(this._apiService);

  /// 4.3.0 (demande 11, option A) : message quand le serveur exige une session pour activer la licence.
  static const messageActivationAdministrateur = 'Activez la licence après connexion d\'un administrateur.';

  /// L'écran « Clé de licence » est ouvert avec la session d'un ADMINISTRATEUR gardée (licence absente ou expirée
  /// constatée à sa connexion) : seule l'activation est possible, la session est fermée ensuite.
  bool activationParAdministrateur = false;

  /// Le dernier refus d'activation venait de l'absence de session (bouton « Connexion administrateur »).
  bool get sessionRequise => _sessionRequise;
  bool _sessionRequise = false;

  LicenceModel? get licence => _licence;
  LicenceStatus get status => _status;
  String get errorMessage => _errorMessage;
  LicenceIssue? get issue => _issue;

  /// Titre court selon la cause (connexion ou serveur), pour les boîtes de dialogue.
  String get errorTitle => switch (_issue) {
        LicenceIssue.unreachable => 'Serveur injoignable',
        LicenceIssue.appNotFound => 'Application Prestige introuvable',
        LicenceIssue.serverError => 'Erreur du serveur Prestige',
        LicenceIssue.unexpectedResponse => 'Réponse inattendue du serveur',
        LicenceIssue.certificate => ErreurTls.certificat.titre,
        LicenceIssue.notHttps => ErreurTls.protocole.titre,
        null => 'Erreur de connexion',
      };

  static String messageFor(LicenceIssue issue, String? detail) {
    final base = switch (issue) {
      LicenceIssue.unreachable => 'Aucun serveur ne répond à l\'adresse configurée.\n\n'
          'Vérifiez :\n1. Que le serveur (PC) est allumé.\n2. Que le Wifi est activé.\n3. Que l\'adresse IP et le port sont corrects.',
      LicenceIssue.appNotFound => 'Le serveur répond, mais l\'application Prestige n\'est pas à cette adresse.\n\n'
          'Vérifiez dans Configuration :\n1. Le port.\n2. Le nom de l\'application (ex. "prestige").\n'
          '3. Que l\'application est démarrée sur le serveur (console Payara).',
      LicenceIssue.serverError => 'Le serveur Prestige répond avec une erreur.\n\nRedémarrez l\'application sur le serveur ou contactez le support.',
      LicenceIssue.unexpectedResponse => 'Le serveur répond, mais ce n\'est pas une réponse Prestige.\n\nVérifiez l\'adresse IP, le port et le nom de l\'application.',
      // HTTPS (4.1.0) : la licence n'est pas en cause.
      LicenceIssue.certificate => '${ErreurTls.messageCertificat}\n\n${ErreurTls.conseilCertificat}\nLa licence n\'est pas en cause.',
      LicenceIssue.notHttps => '${ErreurTls.messageProtocole}\n\nLa licence n\'est pas en cause.',
    };
    // Le détail technique (exception réseau) reste dans les logs, pas à l'écran.
    if (detail != null && detail.isNotEmpty) print('Licence - détail : $detail');
    return base;
  }

  /// Adresse du serveur à afficher : l'IP (ou le nom) seule, sans port ni chemin d'API.
  static String serverHost(String baseUrl) {
    final host = Uri.tryParse(baseUrl)?.host ?? '';
    return host.isEmpty ? baseUrl : host;
  }

  /// Vérification auprès du serveur pendant l'utilisation (connexion, retour dans
  /// l'application, contrôle périodique). Renvoie true si l'accès doit être bloqué :
  /// licence absente ou expirée. Une coupure réseau ne bloque pas le travail en cours :
  /// on s'appuie alors sur la date de fin de la dernière licence connue.
  Future<bool> mustBlockAccess() async {
    final status = await checkLicence();
    if (status == LicenceStatus.none || status == LicenceStatus.expired) return true;
    if (status == LicenceStatus.error) return _licence != null && _isExpired(_licence!.dateEnd);
    return false;
  }

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

    _issue = null;
    try {
      // Appel direct au serveur (Pas de cache). La cause d'un échec est distinguée :
      // un problème de connexion ne doit jamais être présenté comme "pas de licence".
      final lookup = await _apiService.lookupLicence();
      final result = lookup.licence;

      if (lookup.issue != null) {
        _status = LicenceStatus.error;
        _issue = lookup.issue;
        _errorMessage = messageFor(lookup.issue!, lookup.detail);
      } else if (result != null) {
        _licence = result;
        if (_isExpired(result.dateEnd)) {
          _status = LicenceStatus.expired;
        } else {
          _status = LicenceStatus.valid;
        }
      } else {
        // Le serveur Prestige a répondu : aucune licence enregistrée
        _licence = null;
        _status = LicenceStatus.none;
      }
    } catch (e) {
      print("Erreur Licence: $e");
      _status = LicenceStatus.error;
      _issue = LicenceIssue.unreachable;
      _errorMessage = messageFor(LicenceIssue.unreachable, e.toString());
    }

    notifyListeners();
    return _status;
  }

  Future<bool> registerLicence(String key) async {
    _status = LicenceStatus.loading;
    notifyListeners();

    // Protection crash si API mal configurée
    _sessionRequise = false;
    try {
      final r = await _apiService.enregistrerLicence(key);
      if (r.sessionRequise) {
        // Option A du pharmacien : jamais d'activation sans session ; on explique quoi faire.
        _status = LicenceStatus.error;
        _issue = null;
        _sessionRequise = true;
        _errorMessage = messageActivationAdministrateur;
        notifyListeners();
        return false;
      }
      if (r.ok) {
        await checkLicence();
        return _status == LicenceStatus.valid;
      } else {
        // Échec : clé refusée, ou serveur inaccessible ? On vérifie la connexion.
        final lookup = await _apiService.lookupLicence();
        _status = LicenceStatus.error;
        _issue = lookup.issue;
        _errorMessage = lookup.issue != null
            ? messageFor(lookup.issue!, lookup.detail)
            : "Clé invalide ou refusée par le serveur.";
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