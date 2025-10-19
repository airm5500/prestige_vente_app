// lib/api/models/rayon.dart
// 16/10/2025 10:10
class Rayon {
  final String id;
  final String libelle;

  Rayon({required this.id, required this.libelle});

  factory Rayon.fromJson(Map<String, dynamic> json) {
    return Rayon(
      id: json['id'] ?? '',
      libelle: (json['libelle'] ?? '').trim(), // .trim() pour nettoyer les espaces
    );
  }
}