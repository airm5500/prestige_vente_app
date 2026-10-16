// lib/images/photos_produits_screen.dart
// 4.4.0 — Menu « Photos produits » (demande du pharmacien : « scan pour reconnaissance ou recherche, ensuite capture
// image et OK on enregistre et on valide pour aller au produit suivant ; ergonomique et intuitif »).
// Parcours en boucle, sans quitter l'écran :
//   1. Produit : douchette Sunmi (saisie + Entrée dans le champ, curseur toujours prêt), appareil photo, ou
//      recherche par nom → choix dans la recherche produit de l'application (code exact → produit direct).
//   2. Le produit s'affiche avec sa photo actuelle (« A déjà une photo » / « Sans photo »).
//   3. « Prendre la photo » : capture guidée existante (cadre, netteté), recadrage carré, JPEG ≤ 1024 px.
//   4. Aperçu : « OK, enregistrer » (envoi, puis produit suivant : champ vidé, curseur prêt), « Reprendre »,
//      « Annuler ».
// Aucune nouvelle route : envoi par l'ajout de photo existant (POST /produit-images/{f}, image principale,
// ProduitImages.ajouterPhoto) ; mêmes droits que l'ajout actuel : réglages « photo terminal » ou administrateur
// (« photoAdmin »), et droit du serveur sur les images (champ « modifiable »). La photo n'est gardée qu'en mémoire
// jusqu'à l'envoi (le fichier de la capture est supprimé aussitôt).
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/droits/droits_modules.dart';
import 'package:prestige_vente_app/images/images_reglages.dart';
import 'package:prestige_vente_app/images/photo_produit.dart';
import 'package:prestige_vente_app/images/produit_image_widget.dart';
import 'package:prestige_vente_app/images/produit_images.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/serveur/choix_produit.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';
import 'package:provider/provider.dart';

/// Menu visible : images actives, et ajout de photo permis (réglage « photo terminal », ou administrateur avec
/// « photoAdmin ») — les mêmes conditions que le bouton de la fiche produit.
bool menuPhotosProduitsVisible({required ImagesConfig config, required bool admin}) =>
    config.actif && (config.photoTerminal || (admin && config.photoAdmin));

Uint8List? _preparer(Uint8List o) => preparerPhoto(o);

/// Capture par défaut : capture guidée, recadrage carré, JPEG ; null si annulé ou illisible.
Future<Uint8List?> capturerPhotoProduitJpeg(BuildContext context) async {
  final chemin = await capturerPhotoProduit(context);
  if (chemin == null) return null;
  final f = File(chemin);
  try {
    return await compute(_preparer, await f.readAsBytes());
  } finally {
    try {
      await f.delete();
    } catch (_) {}
  }
}

enum _Etape { produit, apercu }

class PhotosProduitsScreen extends StatefulWidget {
  final ProduitImages? images;
  final ChoixProduit? choixProduit;
  final ScanCode? scanner;
  final Future<Uint8List?> Function(BuildContext context)? capturer;

  /// Compte administrateur (tests) ; sinon AuthProvider.isAdmin.
  final bool? admin;
  const PhotosProduitsScreen({super.key, this.images, this.choixProduit, this.scanner, this.capturer, this.admin});

  @override
  State<PhotosProduitsScreen> createState() => _PhotosProduitsScreenState();
}

class _PhotosProduitsScreenState extends State<PhotosProduitsScreen> {
  ProduitImages get _s => widget.images ?? ProduitImages.instance;
  final _champ = TextEditingController();
  final _focus = FocusNode(debugLabel: 'photos-produits-recherche');

  _Etape _etape = _Etape.produit;
  ProductSearchResult? _produit;
  EtatPhotoProduit? _etat;
  bool _chargeEtat = false;
  Uint8List? _jpeg;
  bool _occupe = false;
  String? _erreur;
  final List<String> _faits = []; // noms des produits photographiés pendant la séance

  @override
  void dispose() {
    _champ.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _admin {
    if (widget.admin != null) return widget.admin!;
    try {
      return Provider.of<AuthProvider>(context, listen: false).isAdmin;
    } catch (_) {
      return DroitsModules.instance.adminLocal;
    }
  }

  void _curseur() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _etape == _Etape.produit) _focus.requestFocus();
      });

  // ------------------------------------------------------------------------------------------- 1. produit

  Future<void> _chercher({String? code, bool scan = false}) async {
    if (_occupe) return;
    var c = code;
    if (scan) {
      c = await (widget.scanner ?? scannerCodeParDefaut)(context);
      if (!mounted || c == null || c.trim().isEmpty) return _curseur();
    }
    final p = await (widget.choixProduit ?? choisirProduitParDefaut)(context, code: c?.trim());
    _champ.clear();
    if (!mounted) return;
    if (p == null) return _curseur();
    setState(() {
      _produit = p;
      _etat = null;
      _erreur = null;
      _jpeg = null;
      _chargeEtat = true;
    });
    final e = await _s.etatPhoto(p.lgFAMILLEID);
    if (!mounted || _produit?.lgFAMILLEID != p.lgFAMILLEID) return;
    setState(() {
      _etat = e;
      _chargeEtat = false;
    });
  }

  // ------------------------------------------------------------------------------------------- 2. photo

  Future<void> _prendre() async {
    if (_occupe || _produit == null) return;
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    try {
      final j = await (widget.capturer ?? capturerPhotoProduitJpeg)(context);
      if (!mounted) return;
      if (j == null) return;
      setState(() {
        _jpeg = j;
        _etape = _Etape.apercu;
      });
    } catch (_) {
      if (mounted) setState(() => _erreur = 'Photo illisible : reprenez-la.');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _enregistrer() async {
    final p = _produit, j = _jpeg;
    if (_occupe || p == null || j == null) return;
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    final r = await _s.ajouterPhoto(p.lgFAMILLEID, j, admin: _admin);
    if (!mounted) return;
    setState(() => _occupe = false);
    if (!r.isOk) {
      setState(() => _erreur = r.message ?? 'Photo non envoyée.');
      return;
    }
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF15803D),
        duration: const Duration(seconds: 2),
        content: Text('Photo enregistrée : ${p.strNAME}. Produit suivant.'),
      ));
    setState(() => _faits.insert(0, p.strNAME));
    _suivant();
  }

  /// Produit suivant (ou annulation) : retour au champ, vide, curseur prêt pour la douchette.
  void _suivant() {
    setState(() {
      _etape = _Etape.produit;
      _produit = null;
      _etat = null;
      _jpeg = null;
      _erreur = null;
    });
    _champ.clear();
    _curseur();
  }

  void _reprendre() {
    setState(() {
      _jpeg = null;
      _etape = _Etape.produit;
    });
    _prendre();
  }

  // ------------------------------------------------------------------------------------------- affichage

  @override
  Widget build(BuildContext context) {
    final inset = Responsive.sideInset(context);
    return PopScope(
      canPop: _etape == _Etape.produit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _suivant(); // retour depuis l'aperçu = annuler cette photo
      },
      child: Scaffold(
        backgroundColor: Pal.page,
        body: Column(children: [
          NavyHeader(
            title: 'Photos produits',
            subtitle: _faits.isEmpty ? 'Scanner, photographier, OK : produit suivant' : '${_faits.length} photo(s) enregistrée(s) dans cette séance',
            // Étapes dans l'en-tête bleu (textes clairs prévus pour ce fond).
            children: [_etapes(_etape == _Etape.apercu ? 2 : (_produit == null ? 0 : 1))],
          ),
          if (_occupe || _chargeEtat) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ContentWidth(
              child: ListView(
                key: const Key('photos_produits'),
                padding: EdgeInsets.fromLTRB(16 + inset, 14, 16 + inset, 24),
                children: _etape == _Etape.apercu ? _apercu() : _produitVue(),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _produitVue() {
    final p = _produit;
    return [
      TextField(
        key: const Key('photos_recherche'),
        controller: _champ,
        focusNode: _focus,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: (v) => v.trim().isEmpty ? _curseur() : _chercher(code: v),
        decoration: InputDecoration(
          hintText: 'Scannez (douchette) ou tapez le nom / CIP',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            key: const Key('photos_scanner'),
            tooltip: 'Scanner avec l\'appareil photo',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _occupe ? null : () => _chercher(scan: true),
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('photos_rechercher'),
          onPressed: _occupe ? null : () => _chercher(code: _champ.text.trim().isEmpty ? null : _champ.text),
          icon: const Icon(Icons.manage_search),
          label: const Text('Rechercher un produit'),
        ),
      ),
      if (p != null) ...[const SizedBox(height: 8), _carteProduit(p)],
      if (_erreur != null) _messageErreur(_erreur!),
      if (_faits.isNotEmpty) ...[
        const SizedBox(height: 18),
        Text('Faits dans cette séance (${_faits.length})', key: const Key('photos_compteur'), style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.ink)),
        const SizedBox(height: 4),
        for (final n in _faits.take(10))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              const Icon(Icons.check_circle, size: 18, color: Color(0xFF15803D)),
              const SizedBox(width: 6),
              Expanded(child: Text(n, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.ink))),
            ]),
          ),
      ],
    ];
  }

  Widget _etapes(int active) => StepsBar(active: active, steps: const [
        (title: 'Produit', detail: 'scan ou recherche', onTap: null),
        (title: 'Photo', detail: 'cadre, netteté', onTap: null),
        (title: 'OK', detail: 'produit suivant', onTap: null),
      ]);

  Widget _carteProduit(ProductSearchResult p) {
    final e = _etat;
    final aPhoto = e?.aPhoto == true;
    final bloque = e != null && (e.erreur != null || !e.modifiable);
    final (libelle, fg, bg) = e == null
        ? ('Vérification…', Pal.muted, const Color(0xFFF1F3F6))
        : e.erreur != null
            ? ('État inconnu', const Color(0xFF9A3412), const Color(0xFFFDEEE3))
            : aPhoto
                ? ('A déjà une photo', const Color(0xFF1F4F8F), const Color(0xFFE3ECF7))
                : ('Sans photo', const Color(0xFF166534), const Color(0xFFE7F6EC));
    return SoftCard(
      key: const Key('photos_produit'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ProduitImage(
              key: ValueKey('photos_actuelle_${p.lgFAMILLEID}'),
              familleId: p.lgFAMILLEID,
              taille: 88,
              prioritaire: true,
              images: widget.images,
              placeholder: Container(
                width: 88,
                height: 88,
                color: const Color(0xFFF1F3F6),
                child: const Icon(Icons.image_not_supported_outlined, color: Pal.muted, size: 32),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.strNAME, key: const Key('photos_produit_nom'), maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Pal.ink)),
              if (p.intCIP.isNotEmpty) Text('CIP ${p.intCIP}', style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
              const SizedBox(height: 6),
              Container(
                key: const Key('photos_etat'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                child: Text(libelle, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
              ),
            ]),
          ),
        ]),
        if (e?.erreur != null) _messageErreur(e!.erreur!),
        if (e != null && e.erreur == null && !e.modifiable)
          _messageErreur('Vous n\'avez pas le droit de modifier les images des produits (droit du serveur).'),
        if (aPhoto && !bloque)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('La nouvelle photo remplacera la photo actuelle.', style: TextStyle(fontSize: 12.5, color: Pal.muted)),
          ),
        const SizedBox(height: 12),
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            key: const Key('photos_prendre'),
            style: navyButton,
            onPressed: _occupe || e == null || bloque ? null : _prendre,
            icon: const Icon(Icons.photo_camera, size: 26),
            label: Text(aPhoto ? 'Remplacer la photo' : 'Prendre la photo', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(key: const Key('photos_produit_suivant'), onPressed: _occupe ? null : _suivant, child: const Text('Passer : produit suivant')),
      ]),
    );
  }

  List<Widget> _apercu() {
    final p = _produit!, j = _jpeg!;
    final cote = (MediaQuery.sizeOf(context).width - 32).clamp(160.0, 420.0);
    return [
      Text(p.strNAME, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Pal.ink)),
      const SizedBox(height: 10),
      Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            key: const Key('photos_apercu'),
            width: cote,
            height: cote,
            child: Image.memory(j, fit: BoxFit.cover, gaplessPlayback: true),
          ),
        ),
      ),
      if (_erreur != null) _messageErreur(_erreur!),
      const SizedBox(height: 14),
      SizedBox(
        height: 56,
        child: ElevatedButton.icon(
          key: const Key('photos_ok'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF15803D), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          onPressed: _occupe ? null : _enregistrer,
          icon: _occupe ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check, size: 26),
          label: Text(_erreur == null ? 'OK, enregistrer' : 'Réessayer l\'envoi', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('photos_reprendre'),
            style: outlineButton,
            onPressed: _occupe ? null : _reprendre,
            icon: const Icon(Icons.replay),
            label: const Text('Reprendre'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('photos_annuler'),
            style: outlineButton,
            onPressed: _occupe ? null : _suivant,
            icon: const Icon(Icons.close),
            label: const Text('Annuler'),
          ),
        ),
      ]),
    ];
  }

  Widget _messageErreur(String m) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          key: const Key('photos_erreur'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(10)),
          child: Text(m, style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w600)),
        ),
      );
}
