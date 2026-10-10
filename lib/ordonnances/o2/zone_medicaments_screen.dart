// lib/ordonnances/o2/zone_medicaments_screen.dart
// Étape O2 : « zone des médicaments ». L'utilisateur encadre la partie utile de l'ordonnance
// (sans en-tête, tampon, signature ni nom du patient) ; seule cette zone est lue.
// Renvoie la zone en fractions de l'image (0…1), Rect.fromLTRB(0, 0, 1, 1) pour la page entière, null si annulé.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

class ZoneMedicamentsScreen extends StatefulWidget {
  final ImageProvider image;

  /// Taille de l'image en pixels (calculée à l'ouverture si absente).
  final Size? taille;

  const ZoneMedicamentsScreen({super.key, required this.image, this.taille});

  static const pageEntiere = Rect.fromLTRB(0, 0, 1, 1);

  /// Ouvre l'écran sur le fichier [chemin].
  static Future<Rect?> ouvrir(BuildContext context, String chemin) async {
    Size? taille;
    try {
      final codec = await ui.instantiateImageCodec(await File(chemin).readAsBytes());
      final frame = await codec.getNextFrame();
      taille = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      frame.image.dispose();
    } catch (_) {}
    if (!context.mounted) return null;
    return Navigator.of(context).push<Rect>(MaterialPageRoute(
      builder: (_) => ZoneMedicamentsScreen(image: FileImage(File(chemin)), taille: taille),
    ));
  }

  @override
  State<ZoneMedicamentsScreen> createState() => _ZoneMedicamentsScreenState();
}

enum _Poignee { hautGauche, hautDroite, basGauche, basDroite, centre }

class _ZoneMedicamentsScreenState extends State<ZoneMedicamentsScreen> {
  // Zone par défaut : sous l'en-tête, au-dessus du tampon.
  Rect _zone = const Rect.fromLTRB(0.04, 0.22, 0.96, 0.82);
  static const _min = 0.08;

  void _deplacer(_Poignee p, Offset delta, Size affichee) {
    final d = Offset(delta.dx / affichee.width, delta.dy / affichee.height);
    var z = _zone;
    switch (p) {
      case _Poignee.hautGauche:
        z = Rect.fromLTRB((z.left + d.dx).clamp(0.0, z.right - _min), (z.top + d.dy).clamp(0.0, z.bottom - _min), z.right, z.bottom);
      case _Poignee.hautDroite:
        z = Rect.fromLTRB(z.left, (z.top + d.dy).clamp(0.0, z.bottom - _min), (z.right + d.dx).clamp(z.left + _min, 1.0), z.bottom);
      case _Poignee.basGauche:
        z = Rect.fromLTRB((z.left + d.dx).clamp(0.0, z.right - _min), z.top, z.right, (z.bottom + d.dy).clamp(z.top + _min, 1.0));
      case _Poignee.basDroite:
        z = Rect.fromLTRB(z.left, z.top, (z.right + d.dx).clamp(z.left + _min, 1.0), (z.bottom + d.dy).clamp(z.top + _min, 1.0));
      case _Poignee.centre:
        final dx = d.dx.clamp(-z.left, 1.0 - z.right);
        final dy = d.dy.clamp(-z.top, 1.0 - z.bottom);
        z = z.shift(Offset(dx, dy));
    }
    setState(() => _zone = z);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Zone des médicaments')),
      body: SafeArea(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(
              'Encadrez seulement les médicaments : sans en-tête, tampon, signature ni nom du patient.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          Expanded(child: LayoutBuilder(builder: (context, c) => _cadre(c.biggest))),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('zone_page_entiere'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                  onPressed: () => Navigator.of(context).pop(ZoneMedicamentsScreen.pageEntiere),
                  child: const Text('Page entière'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  key: const Key('zone_valider'),
                  style: navyButton,
                  onPressed: () => Navigator.of(context).pop(_zone),
                  child: const Text('Lire cette zone'),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _cadre(Size dispo) {
    final t = widget.taille ?? const Size(1000, 1414);
    final echelle = (dispo.width / t.width) < (dispo.height / t.height) ? dispo.width / t.width : dispo.height / t.height;
    final affichee = Size(t.width * echelle, t.height * echelle);
    final r = Rect.fromLTRB(_zone.left * affichee.width, _zone.top * affichee.height, _zone.right * affichee.width,
        _zone.bottom * affichee.height);
    Widget poignee(_Poignee p, Offset o) => Positioned(
          left: o.dx - 22,
          top: o.dy - 22,
          child: GestureDetector(
            key: Key('zone_${p.name}'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => _deplacer(p, d.delta, affichee),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(color: Pal.amber, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                ),
              ),
            ),
          ),
        );
    return Center(
      child: SizedBox(
        width: affichee.width,
        height: affichee.height,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: Image(image: widget.image, fit: BoxFit.fill, errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.white10))),
          Positioned.fill(child: CustomPaint(painter: _Voile(r))),
          Positioned.fromRect(
            rect: r,
            child: GestureDetector(
              key: const Key('zone_centre'),
              behavior: HitTestBehavior.translucent,
              onPanUpdate: (d) => _deplacer(_Poignee.centre, d.delta, affichee),
            ),
          ),
          poignee(_Poignee.hautGauche, r.topLeft),
          poignee(_Poignee.hautDroite, r.topRight),
          poignee(_Poignee.basGauche, r.bottomLeft),
          poignee(_Poignee.basDroite, r.bottomRight),
        ]),
      ),
    );
  }
}

class _Voile extends CustomPainter {
  final Rect zone;
  _Voile(this.zone);

  @override
  void paint(Canvas canvas, Size size) {
    final dehors = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(zone);
    canvas.drawPath(dehors, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawRect(zone, Paint()
      ..color = Pal.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(_Voile old) => old.zone != zone;
}
