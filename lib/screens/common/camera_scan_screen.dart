// lib/screens/common/camera_scan_screen.dart
// Lecture d'un code (DataMatrix, EAN, QR...) avec l'appareil photo du téléphone.
// Alternative à la douchette du terminal Sunmi : renvoie le contenu brut du code lu.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraScanScreen extends StatefulWidget {
  final String title;
  final List<BarcodeFormat> formats;

  /// Texte d'aide sous le cadre (par défaut : « Placez le code entièrement dans le cadre »).
  final String? aide;

  /// Haute définition (4.4.0) : analyse en 1280×720 au lieu de 640×480 (défaut Android de mobile_scanner),
  /// zoom automatique de ML Kit et bouton « Zoom ×2 ». Indispensable pour les petits DataMatrix des boîtes
  /// (lot / péremption) : en 640×480, un DataMatrix de 8 à 10 mm n'a que 2 à 3 pixels par module et n'est lu
  /// qu'à 5-6 cm, en deçà de la distance de mise au point de la plupart des téléphones.
  final bool hauteDefinition;

  /// Contrôle d'un code lu : null = accepté (l'écran se ferme et le rend) ; sinon message affiché sur l'image
  /// et la lecture continue (ex. « code-barres sans lot ni date : visez le DataMatrix »).
  final String? Function(String valeur)? verifier;

  /// Résolution d'analyse demandée en haute définition.
  static const Size resolutionHauteDefinition = Size(1280, 720);

  /// Contrôleur de la caméra (exposé pour les tests : formats, résolution, zoom automatique).
  static MobileScannerController controleur({required List<BarcodeFormat> formats, bool hauteDefinition = false}) => MobileScannerController(
        formats: formats,
        detectionSpeed: DetectionSpeed.noDuplicates,
        cameraResolution: hauteDefinition ? resolutionHauteDefinition : null,
        autoZoom: hauteDefinition,
        autoStart: true,
      );

  /// Codes des boîtes de médicaments : DataMatrix et tous les codes-barres classiques
  /// (EAN-13/8, UPC-A/E — un EAN-13 commençant par 0 est lu comme UPC-A —, Code 128/39/93, ITF).
  static const List<BarcodeFormat> formatsProduit = [
    BarcodeFormat.dataMatrix,
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.code93,
    BarcodeFormat.itf,
    BarcodeFormat.qrCode,
  ];

  const CameraScanScreen({
    super.key,
    this.aide,
    this.hauteDefinition = false,
    this.verifier,
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
  /// [produit] : tous les formats des boîtes ([formatsProduit]) ; [aide] : texte sous le cadre.
  /// [hauteDefinition] : voir le champ ; [verifier] : refus d'un code lu, avec un message, sans fermer.
  static Future<String?> open(BuildContext context,
      {String? title, bool dataMatrixOnly = false, bool produit = false, String? aide, bool hauteDefinition = false, String? Function(String)? verifier}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CameraScanScreen(
          title: title ?? 'Scanner avec l\'appareil photo',
          aide: aide,
          hauteDefinition: hauteDefinition,
          verifier: verifier,
          formats: dataMatrixOnly
              ? const [BarcodeFormat.dataMatrix]
              : produit
                  ? formatsProduit
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
    // UPC-A (12 chiffres) = EAN-13 commençant par 0 : on rend l'EAN-13 complet.
    if (barcode.format == BarcodeFormat.upcA && value != null && RegExp(r'^\d{12}$').hasMatch(value)) return '0$value';
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
  late final MobileScannerController _controller = CameraScanScreen.controleur(formats: widget.formats, hauteDefinition: widget.hauteDefinition);
  bool _done = false;
  bool _zoom = false;
  String? _refus; // dernier code refusé par [CameraScanScreen.verifier]
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
        final refus = widget.verifier?.call(value);
        if (refus != null) {
          if (refus != _refus) setState(() => _refus = refus);
          continue; // un autre code de la même image (le DataMatrix à côté de l'EAN) peut convenir
        }
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
          if (widget.hauteDefinition)
            IconButton(
              key: const Key('scan_zoom'),
              icon: Icon(_zoom ? Icons.zoom_out : Icons.zoom_in),
              tooltip: _zoom ? 'Zoom normal' : 'Zoom ×2 (petits codes)',
              onPressed: () {
                setState(() => _zoom = !_zoom);
                _controller.setZoomScale(_zoom ? 0.5 : 0.0);
              },
            ),
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
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_refus != null)
                Container(
                  key: const Key('scan_refus'),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xE6B45309), borderRadius: BorderRadius.circular(10)),
                  child: Text(_refus!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              Text(
                widget.aide ?? 'Placez le code entièrement dans le cadre',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ]),
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
