// lib/widgets/sortie_kiosque.dart
// Sortie SIMPLE et FIABLE des modes « borne » (borne libre-service, terminal de pointage), 4.1.2 :
//   cadenas visible (discret) → APPUI LONG de 2 s (anneau de progression) → confirmation → code administrateur.
// Retours du pharmacien : il restait bloqué. Causes relevées :
// - terminal de pointage : l'appui long était posé AUTOUR d'un IconButton désactivé portant une infobulle ; sur
//   Android, l'infobulle (Tooltip) capte l'appui long pour s'afficher : le geste de sortie ne partait jamais ;
// - borne : zone de 64 × 64 INVISIBLE dans le coin haut gauche, en partie sous la barre d'état (hors SafeArea),
//   appui de 5 s, rien à l'écran pour le signaler.
// Ici : événements bruts du pointeur (Listener, hors de l'arène des gestes : ni infobulle ni défilement ne peuvent
// le voler), aucune infobulle, zone ≥ 48 dp, un appui court explique le geste.

import 'dart:async';

import 'package:flutter/material.dart';

/// Durée de l'appui long de sortie.
const Duration dureeSortieKiosque = Duration(seconds: 2);

/// Libellé (accessibilité, aide).
const String libelleSortieKiosque = 'Quitter le mode borne';

/// Aide affichée après un appui court.
const String aideSortieKiosque = 'Maintenez le cadenas appuyé 2 secondes pour quitter le mode borne (code administrateur demandé).';

/// Cadenas de sortie : appui long [duree] → [onSortie]. Appui court → [onAppuiCourt] (aide).
class BoutonSortieKiosque extends StatefulWidget {
  final VoidCallback onSortie;
  final VoidCallback? onAppuiCourt;
  final Duration duree;
  final Color couleur;
  final double taille;

  /// Texte à côté du cadenas (null : icône seule).
  final String? texte;
  const BoutonSortieKiosque({
    super.key,
    required this.onSortie,
    this.onAppuiCourt,
    this.duree = dureeSortieKiosque,
    this.couleur = const Color(0xFF5B6B82),
    this.taille = 48,
    this.texte,
  });

  @override
  State<BoutonSortieKiosque> createState() => _BoutonSortieKiosqueState();
}

class _BoutonSortieKiosqueState extends State<BoutonSortieKiosque> with SingleTickerProviderStateMixin {
  // Anneau de progression (affichage) ; la sortie est déclenchée par une minuterie de [BoutonSortieKiosque.duree]
  // depuis l'appui, indépendante des images affichées.
  late final AnimationController _anim = AnimationController(vsync: this, duration: widget.duree);
  Timer? _minuterie;
  bool _fini = false;
  bool _enCours = false;

  @override
  void dispose() {
    _minuterie?.cancel();
    _anim.dispose();
    super.dispose();
  }

  void _debut(PointerDownEvent _) {
    _fini = false;
    _enCours = true;
    _anim.forward(from: 0);
    _minuterie?.cancel();
    _minuterie = Timer(widget.duree, () {
      if (!mounted || !_enCours) return;
      _fini = true;
      _enCours = false;
      _anim.value = 0;
      widget.onSortie();
    });
  }

  void _fin(bool annule) {
    _minuterie?.cancel();
    if (!_enCours) return;
    _enCours = false;
    _anim.stop();
    _anim.value = 0;
    if (!_fini && !annule) widget.onAppuiCourt?.call();
  }

  @override
  Widget build(BuildContext context) {
    final icone = SizedBox(
      width: widget.taille,
      height: widget.taille,
      child: Stack(alignment: Alignment.center, children: [
        AnimatedBuilder(
          animation: _anim,
          builder: (_, __) => _anim.value == 0
              ? const SizedBox.shrink()
              : SizedBox(
                  width: widget.taille - 6,
                  height: widget.taille - 6,
                  child: CircularProgressIndicator(value: _anim.value, strokeWidth: 3, color: widget.couleur),
                ),
        ),
        Icon(Icons.lock_outline, color: widget.couleur, size: widget.taille * 0.5),
      ]),
    );
    final contenu = widget.texte == null
        ? icone
        : Row(mainAxisSize: MainAxisSize.min, children: [
            icone,
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(widget.texte!, style: TextStyle(color: widget.couleur, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
          ]);
    return Semantics(
      button: true,
      label: '$libelleSortieKiosque (maintenir ${widget.duree.inSeconds} secondes)',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _debut,
        onPointerUp: (_) => _fin(false),
        onPointerCancel: (_) => _fin(true),
        child: ConstrainedBox(constraints: const BoxConstraints(minWidth: 48, minHeight: 48), child: Center(widthFactor: 1, heightFactor: 1, child: contenu)),
      ),
    );
  }
}

/// « Quitter le mode borne ? » (Rester / Quitter), puis le code administrateur [codeAdmin].
/// true seulement si les deux sont acceptés.
Future<bool> confirmerSortieKiosque(
  BuildContext context, {
  required Future<bool> Function(BuildContext) codeAdmin,
  String titre = 'Quitter le mode borne ?',
  String texte = 'Le code administrateur va être demandé.',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titre),
      content: Text(texte),
      actions: [
        TextButton(key: const ValueKey('sortie-kiosque-rester'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Rester')),
        ElevatedButton(key: const ValueKey('sortie-kiosque-confirmer'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Quitter')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  return codeAdmin(context);
}

/// Aide (appui court sur le cadenas).
void montrerAideSortieKiosque(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text(aideSortieKiosque), duration: Duration(seconds: 4)));
}
