// lib/api/models/user.dart
// 28/09/2025 00:25

class User {
  final String userId;
  final String login;
  final String firstName;
  final String lastName;
  final String officineName;

  /// Rôle du compte s'il figure dans la réponse de connexion (sinon vide ; affiché sur l'écran
  /// « Qui êtes-vous ? »). Lecture tolérante : aucune modification du serveur.
  final String role;

  User({
    required this.userId,
    required this.login,
    required this.firstName,
    required this.lastName,
    required this.officineName,
    this.role = '',
  });

  // Crée une instance de User à partir d'un map JSON
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: json['str_USER_ID'] ?? '',
      login: json['str_LOGIN'] ?? '',
      firstName: json['str_FIRST_NAME'] ?? '',
      lastName: json['str_LAST_NAME'] ?? '',
      officineName: json['OFFICINE'] ?? '',
      role: _role(json),
    );
  }

  static String _role(Map<String, dynamic> json) {
    for (final k in const ['str_ROLE', 'str_ROLE_NAME', 'str_DESCRIPTION_ROLE', 'ROLE', 'role', 'libelleRole']) {
      final v = json[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  String get fullName => '$firstName $lastName';
}