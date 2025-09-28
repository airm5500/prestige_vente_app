// lib/api/models/user.dart
// 28/09/2025 00:25

class User {
  final String userId;
  final String login;
  final String firstName;
  final String lastName;
  final String officineName;

  User({
    required this.userId,
    required this.login,
    required this.firstName,
    required this.lastName,
    required this.officineName,
  });

  // Crée une instance de User à partir d'un map JSON
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: json['str_USER_ID'] ?? '',
      login: json['str_LOGIN'] ?? '',
      firstName: json['str_FIRST_NAME'] ?? '',
      lastName: json['str_LAST_NAME'] ?? '',
      officineName: json['OFFICINE'] ?? '',
    );
  }

  String get fullName => '$firstName $lastName';
}