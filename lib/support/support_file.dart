// lib/support/support_file.dart
// Centre de support : file locale des envois échoués (hors ligne, session absente, serveur sans la route).
// Petite (50 événements au plus, 7 jours) : gardée dans SharedPreferences ; mémoire pour les tests.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Événement en attente : corps JSON prêt à renvoyer (déjà filtré et borné).
class SupportEnAttente {
  final String id;
  final DateTime at;
  final Map<String, Object?> corps;
  final int essais;
  const SupportEnAttente({required this.id, required this.at, required this.corps, this.essais = 0});

  SupportEnAttente avecEssai() => SupportEnAttente(id: id, at: at, corps: corps, essais: essais + 1);

  Map<String, Object?> toJson() => {'id': id, 'at': at.toIso8601String(), 'corps': corps, 'essais': essais};

  static SupportEnAttente? fromJson(Object? j) {
    if (j is! Map || j['corps'] is! Map) return null;
    return SupportEnAttente(
      id: '${j['id'] ?? ''}',
      at: DateTime.tryParse('${j['at'] ?? ''}') ?? DateTime.now(),
      corps: Map<String, Object?>.from(j['corps'] as Map),
      essais: j['essais'] is num ? (j['essais'] as num).toInt() : 0,
    );
  }
}

abstract class SupportFileStore {
  Future<List<SupportEnAttente>> lire();
  Future<void> ecrire(List<SupportEnAttente> file);
}

class MemorySupportFileStore implements SupportFileStore {
  List<SupportEnAttente> file = [];
  @override
  Future<List<SupportEnAttente>> lire() async => List.of(file);
  @override
  Future<void> ecrire(List<SupportEnAttente> f) async => file = List.of(f);
}

class PrefsSupportFileStore implements SupportFileStore {
  static const cle = 'support_file_v1';

  @override
  Future<List<SupportEnAttente>> lire() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(cle);
      if (s == null || s.isEmpty) return [];
      final l = jsonDecode(s);
      if (l is! List) return [];
      return [for (final j in l) if (SupportEnAttente.fromJson(j) case final e?) e];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> ecrire(List<SupportEnAttente> file) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(cle, jsonEncode([for (final e in file) e.toJson()]));
    } catch (_) {}
  }
}
