// lib/ventes/core/pending_sale_store.dart
// Mémorise la vente en cours de chaque menu (identifiant, référence, total) pour proposer
// « Reprendre la vente ? » après une fermeture de l'appli ou une perte de session.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum VenteMenu { prevente, assurance, carnet }

class PendingSale {
  final String venteId;
  final String reference;
  final int itemCount;
  final int total;
  final DateTime savedAt;

  /// Données propres au menu (client, ayant droit, bons…), pour reconstituer l'écran.
  final Map<String, dynamic> extra;

  const PendingSale({
    required this.venteId,
    this.reference = '',
    this.itemCount = 0,
    this.total = 0,
    required this.savedAt,
    this.extra = const {},
  });

  Map<String, dynamic> toJson() => {
        'venteId': venteId,
        'reference': reference,
        'itemCount': itemCount,
        'total': total,
        'savedAt': savedAt.toIso8601String(),
        'extra': extra,
      };

  static PendingSale? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = '${j['venteId'] ?? ''}';
    if (id.isEmpty) return null;
    return PendingSale(
      venteId: id,
      reference: '${j['reference'] ?? ''}',
      itemCount: (j['itemCount'] as num?)?.toInt() ?? 0,
      total: (j['total'] as num?)?.toInt() ?? 0,
      savedAt: DateTime.tryParse('${j['savedAt']}') ?? DateTime.now(),
      extra: j['extra'] is Map ? Map<String, dynamic>.from(j['extra'] as Map) : const {},
    );
  }
}

class PendingSaleStore {
  PendingSaleStore._();

  static String _key(VenteMenu m) => 'vente_en_cours_v1_${m.name}';

  static Future<PendingSale?> load(VenteMenu m) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(m));
      if (raw == null) return null;
      return PendingSale.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(VenteMenu m, PendingSale sale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(m), jsonEncode(sale.toJson()));
    } catch (_) {}
  }

  static Future<void> clear(VenteMenu m) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(m));
    } catch (_) {}
  }
}
