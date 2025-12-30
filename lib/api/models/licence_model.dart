// lib/api/models/licence_model.dart
class LicenceModel {
  final String id;
  final String dateStart;
  final String dateEnd;
  final String typeLicence;

  LicenceModel({
    required this.id,
    required this.dateStart,
    required this.dateEnd,
    required this.typeLicence,
  });

  factory LicenceModel.fromJson(Map<String, dynamic> json) {
    return LicenceModel(
      id: json['id']?.toString() ?? '',
      dateStart: json['dateStart']?.toString() ?? '',
      dateEnd: json['dateEnd']?.toString() ?? '',
      typeLicence: json['typeLicence']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dateStart': dateStart,
      'dateEnd': dateEnd,
      'typeLicence': typeLicence,
    };
  }
}