// lib/screens/common/guided_capture_screen.dart
// Capture guidée d'une étiquette (LOT / EXP) :
// cadre fixe, contrôle de la luminosité, de la netteté et de la stabilité, lampe proposée si trop sombre,
// photo prise automatiquement quand l'image est bonne, puis recadrage sur le cadre avant la lecture du texte.
// Renvoie les lignes de texte lues (comme OcrService.captureAndRead), null si annulé.
// Mode « page » (ordonnance, étape O2) : cadre A5/A4 portrait, renvoie le chemin de la photo recadrée
// (sans lecture : la zone des médicaments est choisie ensuite).
import 'dart:async';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prestige_vente_app/services/capture/capture_geometry.dart';
import 'package:prestige_vente_app/services/capture/frame_quality.dart';
import 'package:prestige_vente_app/services/capture/image_crop.dart';
import 'package:prestige_vente_app/services/ocr_service.dart';

class GuidedCaptureScreen extends StatefulWidget {
  final String title;
  final String hint;

  /// Mode page (ordonnance) : cadre A5/A4 et retour du chemin de la photo recadrée.
  final bool page;

  const GuidedCaptureScreen({
    super.key,
    this.title = 'Photo étiquette',
    this.hint = 'Placez LOT et EXP dans le cadre',
    this.page = false,
  });

  /// Capture guidée d'une page d'ordonnance : chemin de la photo recadrée sur la page, null si annulé.
  /// Le fichier est temporaire : à supprimer par l'appelant après lecture.
  static Future<String?> openPage(BuildContext context) {
    return Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => const GuidedCaptureScreen(
        title: 'Photo ordonnance',
        hint: 'Placez toute la page dans le cadre, bien à plat',
        page: true,
      ),
    ));
  }

  static Future<List<String>?> open(BuildContext context, {String? title, String? hint}) {
    return Navigator.of(context).push<List<String>>(MaterialPageRoute(
      builder: (_) => GuidedCaptureScreen(
        title: title ?? 'Photo étiquette',
        hint: hint ?? 'Placez LOT et EXP dans le cadre',
      ),
    ));
  }

  @override
  State<GuidedCaptureScreen> createState() => _GuidedCaptureScreenState();
}

class _GuidedCaptureScreenState extends State<GuidedCaptureScreen> with WidgetsBindingObserver {
  static const _analysisInterval = Duration(milliseconds: 120);

  CameraPlatform get _cam => CameraPlatform.instance;

  int? _cameraId;
  CameraDescription? _description;
  Size? _previewSize; // orientation capteur (paysage en général)
  StreamSubscription<CameraImageData>? _frames;
  final _gate = AutoCaptureGate();
  FrameQuality? _quality;
  CaptureAdvice _advice = const CaptureAdvice(CaptureHint.starting);
  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);
  Size? _view;
  bool _torch = false;
  bool _capturing = false;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _release();
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // La caméra est libérée quand l'application passe en arrière-plan, et reprise au retour.
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _release();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _cameraId == null && !_capturing) {
      _start();
    }
  }

  Rect _frameOf(Size view) => widget.page ? CaptureGeometry.pageFrameInView(view) : CaptureGeometry.frameInView(view);

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    setState(() => _error = null);
    try {
      final cameras = await _cam.availableCameras();
      if (cameras.isEmpty) throw CameraException('NoCamera', 'Aucune caméra sur cet appareil.');
      final d = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      final id = await _cam.createCameraWithSettings(
        d,
        const MediaSettings(resolutionPreset: ResolutionPreset.veryHigh, enableAudio: false),
      );
      final initialized = _cam.onCameraInitialized(id).first;
      await _cam.initializeCamera(id, imageFormatGroup: ImageFormatGroup.yuv420);
      final event = await initialized;
      if (!mounted) {
        await _cam.dispose(id);
        return;
      }
      try {
        await _cam.lockCaptureOrientation(id, DeviceOrientation.portraitUp);
      } catch (_) {
        // Non bloquant : la photo est redressée d'après ses informations EXIF.
      }
      // Pas de flash automatique (reflets sur les boîtes) : seulement la lampe, si l'opérateur la demande.
      await _cam.setFlashMode(id, _torch ? FlashMode.torch : FlashMode.off);
      setState(() {
        _cameraId = id;
        _description = d;
        _previewSize = Size(event.previewWidth, event.previewHeight);
      });
      _listen();
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } catch (e) {
      if (mounted) setState(() => _error = 'Caméra indisponible ($e).');
    } finally {
      _starting = false;
    }
  }

  String _friendly(CameraException e) => switch (e.code) {
        'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' || 'CameraAccessRestricted' =>
          'Accès à la caméra refusé. Autorisez la caméra pour Prestige dans les réglages Android.',
        'NoCamera' => 'Aucune caméra sur cet appareil.',
        _ => 'Caméra indisponible : ${e.description ?? e.code}',
      };

  void _listen() {
    final id = _cameraId;
    if (id == null) return;
    _quality = null;
    _gate.reset();
    _frames = _cam.onStreamedFrameAvailable(id).listen(_onFrame, onError: (_) {});
  }

  Future<void> _release() async {
    final frames = _frames;
    _frames = null;
    await frames?.cancel();
    final id = _cameraId;
    _cameraId = null;
    if (id != null) {
      try {
        await _cam.dispose(id);
      } catch (_) {}
    }
  }

  void _onFrame(CameraImageData f) {
    final view = _view;
    final d = _description;
    if (_capturing || view == null || d == null || f.planes.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastAnalysis) < _analysisInterval) return;
    _lastAnalysis = now;

    final odd = ((d.sensorOrientation ~/ 90) % 4).isOdd;
    final upright = odd ? Size(f.height.toDouble(), f.width.toDouble()) : Size(f.width.toDouble(), f.height.toDouble());
    final inUpright = CaptureGeometry.frameInImage(
      image: upright,
      view: view,
      frame: _frameOf(view),
      margin: 0,
    );
    final region = CaptureGeometry.uprightToSensor(
      inUpright,
      sensor: Size(f.width.toDouble(), f.height.toDouble()),
      sensorOrientation: d.sensorOrientation,
    );
    final plane = f.planes.first;
    final q = FrameQuality.measure(
      y: plane.bytes,
      width: f.width,
      height: f.height,
      bytesPerRow: plane.bytesPerRow,
      region: region,
      previous: _quality,
    );
    final advice = _gate.update(q, now);
    if (!mounted) return;
    setState(() {
      _quality = q;
      _advice = advice;
    });
    if (advice.capture) _capture();
  }

  Future<void> _toggleTorch() async {
    final id = _cameraId;
    if (id == null) return;
    final on = !_torch;
    try {
      await _cam.setFlashMode(id, on ? FlashMode.torch : FlashMode.off);
      setState(() => _torch = on);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lampe indisponible sur cet appareil.')));
      }
    }
  }

  Future<void> _capture() async {
    final id = _cameraId;
    final view = _view;
    if (_capturing || id == null || view == null) return;
    setState(() => _capturing = true);
    final frames = _frames;
    _frames = null;
    await frames?.cancel();
    final temp = <String>[];
    try {
      HapticFeedback.mediumImpact();
      final photo = await _cam.takePicture(id);
      temp.add(photo.path);
      final cropped = await ImageCrop.cropToFrame(path: photo.path, view: view, frame: _frameOf(view));
      if (widget.page) {
        if (mounted) Navigator.of(context).pop(cropped);
        return;
      }
      temp.add(cropped);
      final lines = await OcrService.readImageFile(cropped);
      if (mounted) Navigator.of(context).pop(lines);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Photo non lue : ${OcrService.friendlyError(e)}'),
        backgroundColor: Colors.red.shade700,
      ));
      setState(() => _capturing = false);
      _listen();
    } finally {
      for (final p in temp) {
        try {
          final f = File(p);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Repli : photo classique (sans cadre) si la caméra guidée ne démarre pas sur cet appareil.
  Future<void> _classicPhoto() async {
    if (widget.page) {
      try {
        final f = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2400, maxHeight: 2400, imageQuality: 95);
        if (mounted && f != null) Navigator.of(context).pop(f.path);
      } catch (e) {
        if (mounted) setState(() => _error = OcrService.friendlyError(e));
      }
      return;
    }
    try {
      final lines = await OcrService.captureAndRead(ImageSource.camera);
      if (mounted && lines != null) Navigator.of(context).pop(lines);
    } catch (e) {
      if (mounted) setState(() => _error = OcrService.friendlyError(e));
    }
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(_torch ? Icons.flashlight_on : Icons.flashlight_off),
            tooltip: 'Lampe',
            onPressed: _cameraId == null ? null : _toggleTorch,
          ),
        ],
      ),
      body: _error != null ? _buildError() : LayoutBuilder(builder: (context, c) => _buildCamera(c.biggest)),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, color: Colors.white70, size: 64),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(icon: const Icon(Icons.refresh), label: const Text('Réessayer'), onPressed: _start),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Photo classique'),
              onPressed: _classicPhoto,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCamera(Size view) {
    _view = view;
    final id = _cameraId;
    final preview = _previewSize;
    final frame = _frameOf(view);
    final ready = _advice.hint == CaptureHint.ready;
    final warn = _advice.hint == CaptureHint.blurry || _advice.hint == CaptureHint.moving || _advice.hint == CaptureHint.starting;
    final color = ready ? Colors.greenAccent : (warn ? Colors.orangeAccent : Colors.white);
    final q = _quality;

    return Stack(
      children: [
        if (id != null && preview != null)
          Positioned.fill(
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  // Aperçu redressé (portrait).
                  width: preview.height,
                  height: preview.width,
                  child: _cam.buildPreview(id),
                ),
              ),
            ),
          )
        else
          const Center(child: CircularProgressIndicator()),
        Positioned.fill(child: CustomPaint(painter: _FramePainter(frame: frame, color: color, progress: ready ? _advice.progress : 0))),
        // Consigne au-dessus du cadre.
        Positioned(
          left: 16,
          right: 16,
          top: frame.top - 64,
          child: Column(
            children: [
              Text(widget.hint, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                _capturing
                    ? (widget.page ? 'Photo en cours...' : 'Lecture en cours...')
                    : (widget.page && _advice.hint == CaptureHint.noText ? 'Page non détectée dans le cadre' : _advice.message),
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 15),
              ),
            ],
          ),
        ),
        if (_advice.suggestTorch && !_torch && !_capturing)
          Positioned(
            left: 16,
            right: 16,
            top: frame.bottom + 12,
            child: Material(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
              child: ListTile(
                leading: const Icon(Icons.flashlight_on, color: Colors.amber),
                title: const Text('Image trop sombre', style: TextStyle(color: Colors.white)),
                trailing: TextButton(onPressed: _toggleTorch, child: const Text('Allumer la lampe')),
              ),
            ),
          ),
        // Indicateurs et déclencheur manuel.
        Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _indicator('Lumière', q != null && q.brightness >= AutoCaptureGate.minBrightness && q.brightness <= AutoCaptureGate.maxBrightness),
                  _indicator('Netteté', q != null && _advice.hint != CaptureHint.blurry && q.contrast >= AutoCaptureGate.minContrast),
                  _indicator('Stabilité', q?.motion != null && q!.motion! <= AutoCaptureGate.maxMotion),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 72,
                height: 72,
                child: _capturing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : FloatingActionButton(
                        heroTag: 'guided-capture',
                        backgroundColor: Colors.white,
                        tooltip: 'Prendre la photo',
                        onPressed: id == null ? null : _capture,
                        child: const Icon(Icons.camera_alt, color: Colors.black, size: 32),
                      ),
              ),
              const SizedBox(height: 6),
              const Text('Photo automatique quand l\'image est nette', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _indicator(String label, bool ok) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Chip(
          visualDensity: VisualDensity.compact,
          backgroundColor: Colors.black54,
          side: BorderSide(color: ok ? Colors.greenAccent : Colors.white38),
          avatar: Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: ok ? Colors.greenAccent : Colors.white54),
          label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      );
}

/// Assombrit l'extérieur du cadre, dessine le cadre et la progression de la capture automatique.
class _FramePainter extends CustomPainter {
  final Rect frame;
  final Color color;
  final double progress;

  _FramePainter({required this.frame, required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(frame, const Radius.circular(12));
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rrect);
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    if (progress > 0) {
      final y = frame.bottom + 6;
      canvas.drawLine(
        Offset(frame.left, y),
        Offset(frame.left + frame.width * progress, y),
        Paint()
          ..color = color
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.frame != frame || old.color != color || old.progress != progress;
}
