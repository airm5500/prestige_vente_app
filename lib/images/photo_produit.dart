// lib/images/photo_produit.dart
// B2 — « Photo du produit » depuis la fiche produit (CACHÉ derrière un réglage administrateur, désactivé
// par défaut, en attendant les précisions du client) : capture guidée existante, recadrage carré centré,
// réduction à 1024 px, compression JPEG, puis envoi (POST /produit-images/{f}, image principale).
// Visible seulement si l'utilisateur a le droit (champ « modifiable » de la liste du serveur) et en ligne.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:prestige_vente_app/images/images_reglages.dart';
import 'package:prestige_vente_app/images/produit_images.dart';
import 'package:prestige_vente_app/screens/common/guided_capture_screen.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

/// Recadrage carré centré, côté ≤ [cote] px, JPEG qualité [qualite] (null : image illisible).
Uint8List? preparerPhoto(Uint8List octets, {int cote = 1024, int qualite = 85}) {
  img.Image? src;
  try {
    src = img.decodeImage(octets);
  } catch (_) {
    src = null;
  }
  if (src == null) return null;
  final c = src.width < src.height ? src.width : src.height;
  var carre = img.copyCrop(src, x: (src.width - c) ~/ 2, y: (src.height - c) ~/ 2, width: c, height: c);
  if (c > cote) carre = img.copyResize(carre, width: cote, height: cote, interpolation: img.Interpolation.average);
  return Uint8List.fromList(img.encodeJpg(carre, quality: qualite));
}

Uint8List? _preparer(Uint8List o) => preparerPhoto(o);

/// Capture guidée (cadre page) : chemin de la photo recadrée, null si annulé.
Future<String?> capturerPhotoProduit(BuildContext context) => Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => const GuidedCaptureScreen(title: 'Photo du produit', hint: 'Placez le produit dans le cadre, sur un fond uni', page: true),
    ));

class PhotoProduitBouton extends StatefulWidget {
  final String familleId;
  final ProduitImages? images;

  /// Capture (tests) ; sinon capture guidée.
  final Future<Uint8List?> Function(BuildContext)? capturer;
  const PhotoProduitBouton({super.key, required this.familleId, this.images, this.capturer});

  @override
  State<PhotoProduitBouton> createState() => _PhotoProduitBoutonState();
}

class _PhotoProduitBoutonState extends State<PhotoProduitBouton> {
  ProduitImages get _s => widget.images ?? ProduitImages.instance;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _s.addListener(_maj);
    ImagesReglages.courant.addListener(_maj);
  }

  @override
  void dispose() {
    _s.removeListener(_maj);
    ImagesReglages.courant.removeListener(_maj);
    super.dispose();
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  Future<void> _photo() async {
    if (_envoi) return;
    setState(() => _envoi = true);
    try {
      Uint8List? jpeg;
      if (widget.capturer != null) {
        jpeg = await widget.capturer!(context);
      } else {
        final chemin = await capturerPhotoProduit(context);
        if (chemin == null) return;
        final f = File(chemin);
        final brut = await f.readAsBytes();
        jpeg = await compute(_preparer, brut);
        try {
          await f.delete();
        } catch (_) {}
      }
      if (jpeg == null || !mounted) return;
      final r = await _s.ajouterPhoto(widget.familleId, jpeg);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: r.isOk ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
        content: Text(r.isOk ? 'Photo enregistrée sur le serveur.' : (r.message ?? 'Photo non envoyée.')),
      ));
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ImagesReglages.courant.value;
    if (!c.actif || !c.photoTerminal || _s.modifiable(widget.familleId) != true || _s.horsLigne()) return const SizedBox.shrink();
    return OutlinedButton.icon(
      key: const ValueKey('photo-produit'),
      onPressed: _envoi ? null : _photo,
      icon: _envoi ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_camera),
      label: const Text('Photo du produit'),
    );
  }
}

/// Résultat d'envoi lisible (tests).
String messageEnvoi(VenteResult<String> r) => r.isOk ? 'Photo enregistrée sur le serveur.' : (r.message ?? 'Photo non envoyée.');
