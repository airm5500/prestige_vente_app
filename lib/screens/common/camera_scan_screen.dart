// lib/screens/common/camera_scan_screen.dart
// Lecture d'un code (DataMatrix, EAN, QR...) avec l'appareil photo du téléphone.
// Alternative à la douchette du terminal Sunmi : renvoie le contenu brut du code lu.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraScanScreen extends StatefulWidget {
  final String title;
  final List<BarcodeFormat> formats;

  const CameraScanScreen({
    super.key,
    this.title = 'Scanner avec l\'appareil photo',
    this.formats = const [
      BarcodeFormat.dataMatrix,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.code128,
      BarcodeFormat.qrCode,
    ],
  });

  /// Ouvre le scanner et renvoie le contenu du premier code lu (ou `null` si annulé).
  /// [dataMatrixOnly] : ne lit que les DataMatrix (évite de capter l'EAN de la boîte).
  static Future<String?> open(BuildContext context, {String? title, bool dataMatrixOnly = false}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CameraScanScreen(
          title: title ?? 'Scanner avec l\'appareil photo',
          formats: dataMatrixOnly
              ? const [BarcodeFormat.dataMatrix]
              : const [
                  BarcodeFormat.dataMatrix,
                  BarcodeFormat.ean13,
                  BarcodeFormat.ean8,
                  BarcodeFormat.code128,
                  BarcodeFormat.qrCode,
                ],
        ),
      ),
    );
  }

  /// Contenu du code. Si le texte a perdu les séparateurs GS (ASCII 29) du GS1
  /// mais que les octets bruts les contiennent, on reprend les octets : le lot
  /// et le numéro de série restent ainsi séparés sans ambiguïté.
  static String? valueOf(Barcode barcode) {
    final value = barcode.rawValue;
    final bytes = barcode.rawBytes;
    if (bytes != null &&
        bytes.contains(29) &&
        (value == null || !value.contains('\u001d')) &&
        bytes.every((b) => b == 29 || (b >= 32 && b <= 126))) {
      return String.fromCharCodes(bytes);
    }
    return value;
  }

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen> {
  late final MobileScannerController _controller = MobileScannerController(
    formats: widget.formats,
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  bool _startTimedOut = false;
  Timer? _startTimer;

  @override
  void initState() {
    super.initState();
    // Si la caméra ne démarre pas (module non chargé, caméra occupée...), on
    // l'explique au lieu de laisser un écran noir.
    _startTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && !_controller.value.isRunning && _controller.value.error == null) {
        setState(() => _startTimedOut = true);
      }
    });
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final value = CameraScanScreen.valueOf(barcode);
      if (value != null && value.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Lampe',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _buildError(error),
          ),
          if (_startTimedOut)
            _buildMessage(
              'L\'appareil photo ne démarre pas.\n\n'
              'Fermez complètement l\'application puis relancez-la (après une mise à jour, '
              'un hot restart ne suffit pas), et vérifiez que Prestige a l\'autorisation Caméra.',
            ),
          if (!_startTimedOut)
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (!_startTimedOut)
          const Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Text(
              'Placez le code entièrement dans le cadre',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(MobileScannerException error) {
    final message = error.errorCode == MobileScannerErrorCode.permissionDenied
        ? 'Accès à l\'appareil photo refusé.\nAutorisez la caméra dans les paramètres Android.'
        : 'Appareil photo indisponible sur cet appareil.\nUtilisez la douchette du terminal.';
    return _buildMessage(message);
  }

  Widget _buildMessage(String message) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
        ),
      ),
    );
  }
}
