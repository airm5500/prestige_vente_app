// lib/accueil/point_serveur.dart
// Point d'état du serveur de l'accueil : vert qui clignote doucement (opacité, ~1 s) quand le
// serveur est connecté, couleur fixe sinon (rouge : non connecté, gris : vérification).
// Pas d'animation si l'appareil demande moins d'animations (MediaQuery.disableAnimations),
// sous TickerMode désactivé, ou pendant les tests (pumpAndSettle ne doit pas attendre sans fin).
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PointServeur extends StatefulWidget {
  final Color couleur;

  /// Clignote (serveur connecté).
  final bool clignote;
  final double taille;
  const PointServeur({super.key, required this.couleur, this.clignote = false, this.taille = 9});

  /// Clignotement autorisé (désactivé par défaut sous `flutter test` ; un test peut le forcer).
  static bool clignotementActif = !_sousFlutterTest();

  static bool _sousFlutterTest() {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  @override
  State<PointServeur> createState() => _PointServeurState();
}

class _PointServeurState extends State<PointServeur> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
  late final Animation<double> _opacite = Tween<double>(begin: 1, end: 0.25).animate(CurvedAnimation(parent: _anim, curve: Curves.easeInOut));

  bool get _anime => widget.clignote && PointServeur.clignotementActif && !MediaQuery.disableAnimationsOf(context);

  void _maj() {
    if (_anime) {
      if (!_anim.isAnimating) _anim.repeat(reverse: true);
    } else {
      _anim.stop();
      _anim.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maj();
  }

  @override
  void didUpdateWidget(PointServeur oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maj();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final point = Container(
      width: widget.taille,
      height: widget.taille,
      decoration: BoxDecoration(color: widget.couleur, shape: BoxShape.circle),
    );
    return FadeTransition(key: const Key('point_serveur'), opacity: _opacite, child: point);
  }
}
