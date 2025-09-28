// lib/api/models/officine.dart
// 28/09/2025 00:26
class Officine {
  final String fullName; // "KONAN KOU"
  final String nomComplet; // "PHCIE NACHET"

  Officine({
    required this.fullName,
    required this.nomComplet,
  });

  factory Officine.fromJson(Map<String, dynamic> json) {
    return Officine(
      fullName: json['fullName'] ?? '',
      nomComplet: json['nomComplet'] ?? '',
    );
  }
}