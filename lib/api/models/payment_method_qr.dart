// lib/api/models/payment_method_qr.dart
// 20/10/2025 02:40
import 'dart:typed_data';

class PaymentMethodQr {
  final String id; // Cet ID correspondra au typeReglementId
  final String name;
  final Uint8List? qrCode;

  PaymentMethodQr({
    required this.id,
    required this.name,
    this.qrCode,
  });

  factory PaymentMethodQr.fromJson(Map<String, dynamic> json) {
    List<int>? qrCodeBytes;
    if (json['qrCode'] != null && json['qrCode'] is List) {
      qrCodeBytes = List<int>.from(json['qrCode']);
    }

    return PaymentMethodQr(
      // MODIFICATION : On utilise "typeReglementId" comme ID unique
      id: json['typeReglementId'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      qrCode: qrCodeBytes != null ? Uint8List.fromList(qrCodeBytes) : null,
    );
  }
}