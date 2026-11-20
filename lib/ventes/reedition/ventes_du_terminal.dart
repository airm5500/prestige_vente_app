// lib/ventes/reedition/ventes_du_terminal.dart
// 5.4.0 — Réédition des ventes (retour du pharmacien du 20/11) : liste LOCALE des ventes clôturées sur CE terminal.
//
// Le serveur garde le nom du poste (en-tête X-Poste, lib/serveur/nom_appareil.dart) sur chaque vente
// (str_POSTE_SAISIE à la création, str_POSTE à l'encaissement) et sait filtrer « Ventes terminées » par poste
// (GET v1/ventestats?poste=…, SalesStatsServiceImpl : str_POSTE, str_POSTE_SAISIE ou str_IP). Mais un nom de poste
// n'est pas un identifiant : deux terminaux peuvent porter le même nom, et un nom changé ne retrouve plus les ventes
// d'avant. L'application note donc aussi, au moment où le serveur ACCEPTE la clôture, l'identifiant de la vente :
//   {id : identifiant serveur de la vente, t : « vno » (comptant) ou « vo » (assurance, carnet, dépôt), d : date}.
// Rien d'autre : ni nom de client ou de patient, ni montant, ni produit, ni numéro de bon (aucune donnée client en
// clair n'est gardée). 45 jours et 2 000 ventes au plus. Une vente du terminal = son identifiant est dans cette liste,
// OU le serveur a noté ce terminal comme poste de saisie ou d'encaissement.
//
// Enregistrement : intercepteur posé sur le client HTTP de l'application (HorsLigne.bind) : réponse acceptée
// (pas de `success:false`) à POST /vente/cloturer/vno, /vente/cloturer/assurance (assurance et carnet) ou
// /vente/clotureVenteDepot, identifiant lu dans le corps envoyé (`venteId`). Toutes les voies passent par là :
// nouvelle et ancienne interface, encaissement d'une prévente, envoi de la file hors ligne, PrestigePOS.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Une vente clôturée sur ce terminal (identifiants seulement).
class VenteDuTerminal {
  final String id;

  /// « vno » (comptant) ou « vo » (assurance, carnet, dépôt) : type de la route image du ticket.
  final String type;
  final DateTime date;
  const VenteDuTerminal({required this.id, required this.type, required this.date});

  Map<String, Object> toJson() => {'id': id, 't': type, 'd': date.millisecondsSinceEpoch};

  static VenteDuTerminal? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = '${j['id'] ?? ''}'.trim();
    final d = j['d'];
    if (id.isEmpty || d is! int) return null;
    return VenteDuTerminal(id: id, type: j['t'] == 'vno' ? 'vno' : 'vo', date: DateTime.fromMillisecondsSinceEpoch(d));
  }
}

class VentesDuTerminal extends ChangeNotifier {
  VentesDuTerminal();

  static VentesDuTerminal instance = VentesDuTerminal();

  @visibleForTesting
  static void reinitialiser() => instance = VentesDuTerminal();

  /// Clé des préférences (liste JSON d'identifiants).
  static const String cle = 'ventes_terminal_v1';
  static const Duration conservation = Duration(days: 45);
  static const int maximum = 2000;

  /// Horloge remplaçable dans les tests.
  DateTime Function() maintenant = DateTime.now;

  final Map<String, VenteDuTerminal> _ventes = {};
  bool _charge = false;

  bool get charge => _charge;
  List<VenteDuTerminal> get ventes => _ventes.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  bool contient(String id) => _ventes.containsKey(id);
  int get nombre => _ventes.length;

  Future<void> charger() async {
    try {
      final brut = (await SharedPreferences.getInstance()).getString(cle);
      final l = brut == null ? const [] : jsonDecode(brut);
      if (l is List) {
        for (final j in l) {
          final v = VenteDuTerminal.fromJson(j);
          if (v != null) _ventes.putIfAbsent(v.id, () => v);
        }
      }
    } catch (_) {}
    _charge = true;
    _purger();
  }

  /// Vente clôturée sur ce terminal (appelé par [VentesDuTerminalInterceptor]).
  Future<void> noter(String id, {required String type, DateTime? date}) async {
    final i = id.trim();
    if (i.isEmpty || i == 'null') return;
    if (!_charge) await charger();
    _ventes[i] = VenteDuTerminal(id: i, type: type == 'vno' ? 'vno' : 'vo', date: date ?? maintenant());
    _purger();
    notifyListeners();
    await _enregistrer();
  }

  void _purger() {
    final limite = maintenant().subtract(conservation);
    _ventes.removeWhere((_, v) => v.date.isBefore(limite));
    if (_ventes.length > maximum) {
      final garder = ventes.take(maximum).map((v) => v.id).toSet();
      _ventes.removeWhere((k, _) => !garder.contains(k));
    }
  }

  Future<void> _enregistrer() async {
    try {
      await (await SharedPreferences.getInstance()).setString(cle, jsonEncode([for (final v in ventes) v.toJson()]));
    } catch (_) {}
  }
}

/// Note les clôtures acceptées par le serveur dans [VentesDuTerminal].
class VentesDuTerminalInterceptor extends Interceptor {
  final VentesDuTerminal Function() registre;
  VentesDuTerminalInterceptor({VentesDuTerminal Function()? registre}) : registre = registre ?? (() => VentesDuTerminal.instance);

  static final RegExp _cloture = RegExp(r'/vente/(cloturer/(vno|assurance)|clotureVenteDepot)$');

  /// Type de la route image pour une clôture ([chemin] relatif ou complet), null si ce n'est pas une clôture.
  static String? typeCloture(String methode, String chemin) {
    if (methode.toUpperCase() != 'POST') return null;
    final p = chemin.split('?').first;
    final m = _cloture.firstMatch(p);
    if (m == null) return null;
    return m.group(2) == 'vno' ? 'vno' : 'vo';
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    try {
      final o = response.requestOptions;
      final type = typeCloture(o.method, o.uri.path);
      final code = response.statusCode ?? 200;
      final body = response.data;
      final refuse = body is Map && body['success'] == false;
      if (type != null && code < 400 && !refuse) {
        final d = o.data;
        final id = d is Map ? '${d['venteId'] ?? ''}' : '';
        if (id.isNotEmpty) registre().noter(id, type: type);
      }
    } catch (_) {}
    handler.next(response);
  }
}
