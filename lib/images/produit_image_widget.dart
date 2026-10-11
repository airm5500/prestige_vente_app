// lib/images/produit_image_widget.dart
// B2 — Image d'un produit (cache disque, demandée au serveur si besoin) ; [placeholder] tant qu'elle
// n'est pas connue, si le produit n'en a pas, hors ligne sans cache ou sans l'API côté serveur.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/images/images_reglages.dart';
import 'package:prestige_vente_app/images/produit_images.dart';

class ProduitImage extends StatefulWidget {
  final String familleId;
  final double taille;
  final Widget placeholder;
  final BorderRadius? rayon;

  /// Demander l'image au serveur si elle n'est pas en cache.
  final bool charger;

  /// Marge à droite quand l'image est affichée (rien sinon).
  final bool avecMarge;

  /// Demande servie avant celles en attente (ex. fiche produit ouverte depuis une liste).
  final bool prioritaire;
  final ProduitImages? images;
  const ProduitImage({
    super.key,
    required this.familleId,
    required this.taille,
    required this.placeholder,
    this.rayon,
    this.charger = true,
    this.avecMarge = false,
    this.prioritaire = false,
    this.images,
  });

  @override
  State<ProduitImage> createState() => _ProduitImageState();
}

class _ProduitImageState extends State<ProduitImage> {
  ProduitImages get _s => widget.images ?? ProduitImages.instance;
  late final ProduitImages _ecoute = _s;
  File? _f;

  @override
  void initState() {
    super.initState();
    _ecoute.addListener(_maj);
    _f = _s.fichierConnu(widget.familleId);
    _demander();
  }

  @override
  void didUpdateWidget(ProduitImage old) {
    super.didUpdateWidget(old);
    if (old.familleId != widget.familleId) {
      _f = _s.fichierConnu(widget.familleId);
      _demander();
    }
  }

  @override
  void dispose() {
    _ecoute.removeListener(_maj);
    super.dispose();
  }

  void _demander() {
    if (!widget.charger || !ImagesReglages.courant.value.actif) return;
    final id = widget.familleId;
    _s.demander(id, prioritaire: widget.prioritaire).then((f) {
      if (mounted && id == widget.familleId && f?.path != _f?.path) setState(() => _f = f);
    });
  }

  void _maj() {
    final f = _s.fichierConnu(widget.familleId);
    if (mounted && f?.path != _f?.path) setState(() => _f = f);
  }

  @override
  Widget build(BuildContext context) {
    final f = _f;
    if (f == null || !ImagesReglages.courant.value.actif) return widget.placeholder;
    final px = (widget.taille * MediaQuery.devicePixelRatioOf(context)).round();
    final img = Image.file(
      f,
      key: ValueKey('image-produit-${widget.familleId}'),
      width: widget.taille,
      height: widget.taille,
      fit: BoxFit.cover,
      cacheWidth: px,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => widget.placeholder,
    );
    final w = widget.rayon == null ? img : ClipRRect(borderRadius: widget.rayon!, child: img);
    return widget.avecMarge ? Padding(padding: const EdgeInsets.only(right: 10), child: w) : w;
  }
}
