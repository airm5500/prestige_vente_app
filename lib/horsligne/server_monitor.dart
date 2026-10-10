// lib/horsligne/server_monitor.dart
// Surveillance du serveur (hors ligne, étape H1) :
// - ping léger toutes les 30 s, seulement quand l'appli est au premier plan ;
// - ping immédiat après un échec réseau d'une opération (signalNetworkFailure) ;
// - 3 échecs consécutifs (~1 min) → « injoignable » : on PROPOSE de continuer hors ligne,
//   la bascule n'a lieu qu'après l'appui (goOffline) ; interrupteur manuel à tout moment ;
// - retour en ligne automatique dès que le serveur répond (ping ou toute réponse d'une opération).
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

enum EtatServeur { enLigne, injoignable, horsLigne }

enum RaisonHorsLigne { manuel, confirme }

typedef ServerPing = Future<bool> Function();

class ServerMonitor extends ChangeNotifier with WidgetsBindingObserver {
  /// Ping du serveur (null : pas de surveillance).
  ServerPing? ping;
  final DateTime Function() _clock;
  final Duration interval;

  /// Échecs consécutifs avant de proposer le hors ligne.
  final int seuil;

  ServerMonitor({this.ping, DateTime Function()? clock, this.interval = const Duration(seconds: 30), this.seuil = 3})
      : _clock = clock ?? DateTime.now;

  EtatServeur _etat = EtatServeur.enLigne;
  RaisonHorsLigne? _raison;
  DateTime? _depuis;
  DateTime? _premierEchec;
  DateTime? _retourAt;
  DateTime? _dernierPing;
  int _echecs = 0;
  int _pings = 0;
  bool _enCours = false;
  bool _premierPlan = true;
  bool _started = false;
  Timer? _timer;

  EtatServeur get etat => _etat;
  bool get isOffline => _etat == EtatServeur.horsLigne;
  RaisonHorsLigne? get raison => _raison;

  /// Injoignable : heure du premier échec ; hors ligne : heure de la bascule.
  DateTime? get depuis => _depuis;

  /// Dernier retour en ligne (bandeau « Serveur de nouveau joignable »).
  DateTime? get retourAt => _retourAt;
  DateTime? get dernierPing => _dernierPing;
  int get echecs => _echecs;

  /// Nombre de pings envoyés (diagnostic, tests).
  int get pings => _pings;
  bool get premierPlan => _premierPlan;
  bool get surveille => _timer != null;

  DateTime get now => _clock();

  /// Démarre la surveillance (premier plan seulement).
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final s = WidgetsBinding.instance.lifecycleState;
    _premierPlan = s == null || s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;
    _planifier();
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    if (fg == _premierPlan) return;
    _premierPlan = fg;
    _planifier();
    if (fg) checkNow();
  }

  void _planifier() {
    _timer?.cancel();
    _timer = null;
    if (_started && _premierPlan && ping != null) _timer = Timer.periodic(interval, (_) => checkNow());
  }

  /// Ping maintenant ; renvoie true si le serveur a répondu.
  Future<bool> checkNow() async {
    final p = ping;
    if (p == null || _enCours) return _echecs == 0;
    _enCours = true;
    _pings++;
    bool ok;
    try {
      ok = await p();
    } catch (_) {
      ok = false;
    } finally {
      _enCours = false;
    }
    _dernierPing = now;
    ok ? _succes() : _echec();
    return ok;
  }

  /// Une opération vient d'échouer faute de réseau : vérification immédiate
  /// (au premier échec seulement ; ensuite la cadence de 30 s compte les échecs).
  void signalNetworkFailure() {
    if (ping == null || !_premierPlan || _enCours || _echecs > 0 || isOffline) return;
    checkNow();
    _planifier(); // prochain ping dans 30 s
  }

  /// Le serveur a répondu à une opération : il est joignable.
  void signalReachable() => _succes();

  /// Hors ligne MANUEL et serveur de nouveau joignable : on reste hors ligne (choix de
  /// l'utilisateur) mais on le propose (« Repasser en ligne »).
  bool get joignablePendantManuel => _joignablePendantManuel;
  bool _joignablePendantManuel = false;

  void _succes() {
    _echecs = 0;
    _premierEchec = null;
    if (_etat == EtatServeur.enLigne) return;
    if (_etat == EtatServeur.horsLigne && _raison == RaisonHorsLigne.manuel) {
      if (!_joignablePendantManuel) {
        _joignablePendantManuel = true;
        notifyListeners();
      }
      return;
    }
    _etat = EtatServeur.enLigne;
    _raison = null;
    _depuis = null;
    _retourAt = now;
    notifyListeners();
  }

  void _echec() {
    _echecs++;
    _premierEchec ??= now;
    if (_etat == EtatServeur.enLigne && _echecs >= seuil) {
      _etat = EtatServeur.injoignable;
      _depuis = _premierEchec;
    }
    notifyListeners();
  }

  /// Passe hors ligne : après l'appui sur « Continuer hors ligne » ([manuel] false)
  /// ou par l'interrupteur des Réglages ([manuel] true).
  void goOffline({bool manuel = true}) {
    if (_etat == EtatServeur.horsLigne) return;
    _etat = EtatServeur.horsLigne;
    _raison = manuel ? RaisonHorsLigne.manuel : RaisonHorsLigne.confirme;
    _joignablePendantManuel = false;
    _depuis = now;
    _retourAt = null;
    notifyListeners();
  }

  /// Retour en ligne demandé (interrupteur) : on revérifie tout de suite.
  void goOnline() {
    if (_etat != EtatServeur.enLigne) {
      _etat = EtatServeur.enLigne;
      _joignablePendantManuel = false;
      _raison = null;
      _depuis = null;
      _echecs = 0;
      _premierEchec = null;
      notifyListeners();
    }
    checkNow();
  }

  /// Échec réseau (aucune réponse du serveur) ≠ refus du serveur.
  static bool isNetworkError(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout || DioExceptionType.sendTimeout || DioExceptionType.connectionError => true,
        DioExceptionType.unknown => e.response == null,
        _ => false,
      };
}

/// Observe les appels de l'appli (sans les modifier) : une réponse = serveur joignable,
/// un échec réseau = vérification immédiate.
class ServerMonitorInterceptor extends Interceptor {
  final ServerMonitor Function() monitor;
  ServerMonitorInterceptor(this.monitor);

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    monitor().signalReachable();
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response != null) {
      monitor().signalReachable();
    } else if (ServerMonitor.isNetworkError(err)) {
      monitor().signalNetworkFailure();
    }
    handler.next(err);
  }
}
