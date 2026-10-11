// lib/ordonnances/o5/lecture_avancee_screen.dart
// Étape O5 : parcours de la lecture avancée sur le téléphone — consentement (Réglages), puis à chaque ordonnance :
// photo → zone des médicaments OBLIGATOIRE → masquage (bandes haut / bas automatiques + masques à la main) → aperçu de
// l'image exacte à envoyer et confirmation « Envoyer cette zone pour lecture avancée ? » → envoi au serveur Prestige.
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prestige_vente_app/ordonnances/o2/zone_medicaments_screen.dart';
import 'package:prestige_vente_app/ordonnances/o5/lecture_avancee.dart';
import 'package:prestige_vente_app/ordonnances/o5/masquage_o5.dart';
import 'package:prestige_vente_app/screens/common/guided_capture_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Texte du consentement (Réglages, à l'activation).
const String texteConsentementO5 =
    'La lecture avancée envoie une PHOTO de la zone des médicaments de l\'ordonnance à un service externe de lecture '
    'd\'écriture (par l\'intermédiaire de votre serveur Prestige, qui détient la clé et ne garde pas l\'image).\n\n'
    '• Données de santé : une ordonnance est une donnée de santé. Seule la zone des médicaments est envoyée ; '
    'l\'en-tête, le bas de page (signature, tampon) sont masqués automatiquement et vous masquez à la main tout ce qui '
    'reste (nom, date de naissance, téléphone…). L\'image est montrée avant chaque envoi.\n'
    '• Service externe : l\'image quitte la pharmacie (fournisseur configuré sur le serveur, par défaut l\'API Claude '
    'd\'Anthropic). Le service ne renvoie que la liste des médicaments.\n'
    '• Coût : chaque lecture est facturée par le fournisseur (quelques dixièmes de centime à quelques centimes), avec '
    'un quota par jour fixé sur le serveur.\n'
    '• Validation : les médicaments lus sont proposés comme d\'habitude ; rien n\'est ajouté au panier sans votre '
    'validation.\n\n'
    'Vous pouvez désactiver la lecture avancée à tout moment.';

/// Écran de consentement : true si accepté (case cochée + « J'accepte »).
Future<bool> demanderConsentementO5(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var coche = false;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Lecture avancée en ligne'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(texteConsentementO5, style: TextStyle(fontSize: 13)),
                CheckboxListTile(
                  key: const Key('o5_consentement_case'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: coche,
                  onChanged: (v) => setState(() => coche = v ?? false),
                  title: const Text('J\'ai compris et la pharmacie accepte l\'envoi de la zone des médicaments à un service externe.',
                      style: TextStyle(fontSize: 13)),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Refuser')),
              ElevatedButton(
                key: const Key('o5_consentement_ok'),
                onPressed: coche ? () => Navigator.of(ctx).pop(true) : null,
                child: const Text('J\'accepte'),
              ),
            ],
          ),
        );
      },
    ) ??
    false;

/// Confirmation à chaque envoi, avec l'aperçu EXACT de l'image envoyée.
Future<bool> confirmerEnvoiO5(BuildContext context, Uint8List image) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Envoyer cette zone pour lecture avancée ?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ConstrainedBox(constraints: const BoxConstraints(maxHeight: 320), child: Image.memory(image, key: const Key('o5_apercu'))),
            const SizedBox(height: 8),
            Text('${(image.length / 1024).toStringAsFixed(0)} Ko, sans métadonnées. Vérifiez qu\'aucun nom, date ou téléphone '
                'n\'est visible.', style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          ElevatedButton(key: const Key('o5_envoyer'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Envoyer')),
        ],
      ),
    ) ??
    false;

/// Masquage à la main : la zone (déjà masquée en haut / bas) ; glisser le doigt pour cacher un rectangle.
/// Renvoie les masques (fractions de la zone), ou null si annulé.
class MasquageScreen extends StatefulWidget {
  final Uint8List zone;
  const MasquageScreen({super.key, required this.zone});

  @override
  State<MasquageScreen> createState() => _MasquageScreenState();
}

class _MasquageScreenState extends State<MasquageScreen> {
  final List<Rect> _masques = [];
  Offset? _debut;
  Rect? _courant;

  Rect _rect(Offset a, Offset b, Size s) => Rect.fromLTRB(
        (a.dx < b.dx ? a.dx : b.dx) / s.width,
        (a.dy < b.dy ? a.dy : b.dy) / s.height,
        (a.dx > b.dx ? a.dx : b.dx) / s.width,
        (a.dy > b.dy ? a.dy : b.dy) / s.height,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Masquer les données personnelles'),
          actions: [
            if (_masques.isNotEmpty)
              IconButton(tooltip: 'Retirer le dernier masque', icon: const Icon(Icons.undo), onPressed: () => setState(() => _masques.removeLast())),
          ],
        ),
        body: Column(children: [
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text('Glissez le doigt sur tout nom, date de naissance, téléphone ou adresse encore visible pour le cacher.',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
          Expanded(
            child: Center(
              child: LayoutBuilder(builder: (context, c) {
                return AspectRatioImage(
                  image: widget.zone,
                  child: (taille) => GestureDetector(
                    key: const Key('o5_masquage_zone'),
                    onPanStart: (d) => setState(() {
                      _debut = d.localPosition;
                      _courant = null;
                    }),
                    onPanUpdate: (d) => setState(() => _courant = _rect(_debut!, d.localPosition, taille)),
                    onPanEnd: (_) => setState(() {
                      final r = _courant;
                      if (r != null && r.width > 0.01 && r.height > 0.01) _masques.add(r);
                      _courant = null;
                    }),
                    child: CustomPaint(size: taille, painter: _Masques([..._masques, if (_courant != null) _courant!])),
                  ),
                );
              }),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler'))),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('o5_masquage_ok'),
                    onPressed: () => Navigator.of(context).pop(List<Rect>.of(_masques)),
                    child: const Text('Continuer'),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      );
}

/// Image affichée en entier avec un calque de même taille.
class AspectRatioImage extends StatefulWidget {
  final Uint8List image;
  final Widget Function(Size taille) child;
  const AspectRatioImage({super.key, required this.image, required this.child});

  @override
  State<AspectRatioImage> createState() => _AspectRatioImageState();
}

class _AspectRatioImageState extends State<AspectRatioImage> {
  double? _ratio;

  @override
  void initState() {
    super.initState();
    decodeImageFromList(widget.image).then((i) {
      if (mounted) setState(() => _ratio = i.width / i.height);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: _ratio ?? 1.4,
        child: LayoutBuilder(
          builder: (context, c) => Stack(fit: StackFit.expand, children: [
            Image.memory(widget.image, fit: BoxFit.fill),
            widget.child(Size(c.maxWidth, c.maxHeight)),
          ]),
        ),
      );
}

class _Masques extends CustomPainter {
  final List<Rect> masques;
  _Masques(this.masques);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black;
    for (final m in masques) {
      canvas.drawRect(Rect.fromLTRB(m.left * size.width, m.top * size.height, m.right * size.width, m.bottom * size.height), p);
    }
  }

  @override
  bool shouldRepaint(_Masques old) => true;
}

/// Parcours complet ; renvoie les lignes lues (pour le découpage / la correspondance O3), ou null.
abstract final class LectureAvanceeFlux {
  /// Prépare l'image hors du fil de l'interface.
  static Future<Uint8List> preparer(Uint8List source, Rect zone, List<Rect> masques) =>
      Isolate.run(() => MasquageO5.preparer(source, zone, masques: masques));

  static Future<List<String>?> lire(BuildContext context, {required bool camera, LectureAvancee? service}) async {
    final la = service ?? LectureAvancee.instance;
    if (!la.utilisable) {
      _message(context, 'Lecture avancée : disponible en ligne uniquement.');
      return null;
    }
    String? chemin;
    final temporaires = <String>[];
    try {
      if (camera) {
        chemin = await GuidedCaptureScreen.openPage(context);
        if (chemin != null) temporaires.add(chemin);
      } else {
        chemin = (await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, maxHeight: 2400, imageQuality: 95))?.path;
      }
      if (chemin == null || !context.mounted) return null;
      final source = await File(chemin).readAsBytes();
      // Recadrage OBLIGATOIRE : la page entière n'est jamais envoyée.
      Rect? zone;
      while (true) {
        if (!context.mounted) return null;
        zone = await ZoneMedicamentsScreen.ouvrir(context, chemin);
        if (zone == null) return null;
        if (MasquageO5.zoneValide(zone)) break;
        if (!context.mounted) return null;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Recadrage obligatoire'),
            content: const Text('Pour la lecture avancée, encadrez seulement la zone des médicaments : la page entière '
                '(en-tête, patient, signature) n\'est jamais envoyée.'),
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Recadrer'))],
          ),
        );
      }
      final apercu = await preparer(source, zone, const []);
      if (!context.mounted) return null;
      final masques = await Navigator.of(context).push<List<Rect>>(MaterialPageRoute(builder: (_) => MasquageScreen(zone: apercu)));
      if (masques == null || !context.mounted) return null;
      final image = await preparer(source, zone, masques);
      if (!context.mounted || !await confirmerEnvoiO5(context, image)) return null;
      final r = await la.lire(image);
      if (!r.ok) {
        if (context.mounted) _message(context, r.erreur!);
        return null;
      }
      return r.texte;
    } finally {
      for (final t in temporaires) {
        try {
          final f = File(t);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
  }

  static void _message(BuildContext context, String m) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }
}
