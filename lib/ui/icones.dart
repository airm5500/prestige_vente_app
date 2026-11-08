// lib/ui/icones.dart
// 4.11.0 — plan du pharmacien du 08/11 : « les icônes sont trop petites, sur tablette et sur terminal ».
// Constat (audit, docs/NOTE_VERSION_4.11.0.md) :
//   - toutes les icônes sans taille explicite (barres du haut, boutons-icônes, listes, barre du bas) font 24 dp,
//     quel que soit l'écran : sur une tablette 10″ (≈ 800 × 1280 dp), elles paraissent minuscules ;
//   - sur les terminaux Sunmi (V2s 360 × 720 dp, V3 360 × 640 dp), « Automatique » applique Compact (×0,9) à toute
//     l'interface : une icône de 24 dp n'y fait plus que 21,6 dp réels.
// Correction, d'un seul endroit (thème de l'application) et sans toucher la mise en page :
//   - tablette (côté court réel ≥ 600 dp) : ×1,33 (24 → 32 dp) ;
//   - petit écran / terminal ([TailleEcranReglage.petitEcran]) : ×1,25 (24 → 30 dp logiques, 27 dp réels en Compact) ;
//   - téléphone courant : inchangé (×1,0).
// Les icônes à taille explicite des écrans les plus vus (tuiles de l'accueil, en-têtes) passent par [tailleIcone].
// La borne libre-service (écran CLIENT) garde ses tailles ([SansEchelleIcones]) : sa mise en page a été réglée en
// 1.8.1 et ses pictogrammes sont déjà grands.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart';

class EchelleIcones {
  EchelleIcones._();

  static const tablette = 1.33;
  static const terminal = 1.25;

  /// Facteur des icônes pour l'écran RÉEL [ecran] (dp, avant la réduction de « Taille de l'écran »).
  static double pour(Size ecran) {
    if (ecran.isEmpty) return 1.0;
    if (ecran.shortestSide >= 600) return tablette;
    if (TailleEcranReglage.petitEcran(ecran)) return terminal;
    return 1.0;
  }

  /// Facteur de l'écran de [context] ; 1,0 sous [SansEchelleIcones].
  static double of(BuildContext context) {
    if (context.getInheritedWidgetOfExactType<_SansEchelle>() != null) return 1.0;
    return pour(TailleEcranReglage.ecranReel(context));
  }

  /// Thème dont les icônes par défaut (24 dp) sont multipliées par [f].
  static ThemeData theme(ThemeData t, double f) {
    final taille = 24.0 * f;
    IconThemeData agrandir(IconThemeData? i) => (i ?? const IconThemeData()).copyWith(size: taille);
    return t.copyWith(
      iconTheme: agrandir(t.iconTheme),
      primaryIconTheme: agrandir(t.primaryIconTheme),
      appBarTheme: t.appBarTheme.copyWith(iconTheme: agrandir(t.appBarTheme.iconTheme), actionsIconTheme: agrandir(t.appBarTheme.actionsIconTheme)),
      navigationBarTheme: t.navigationBarTheme.copyWith(
        iconTheme: WidgetStatePropertyAll(IconThemeData(size: taille)),
        height: t.navigationBarTheme.height ?? (f > 1.0 ? 80.0 * (1 + (f - 1) / 2) : null),
      ),
    );
  }
}

/// Taille d'une icône à taille explicite ([base] dp sur un téléphone), mise à l'échelle de l'écran.
double tailleIcone(BuildContext context, double base) => base * EchelleIcones.of(context);

/// Sous-arbre qui garde les tailles d'icônes d'origine (borne libre-service, écran client).
class SansEchelleIcones extends StatelessWidget {
  final Widget child;
  const SansEchelleIcones({super.key, required this.child});

  @override
  Widget build(BuildContext context) => _SansEchelle(child: Theme(data: EchelleIcones.theme(Theme.of(context), 1.0), child: child));
}

class _SansEchelle extends InheritedWidget {
  const _SansEchelle({required super.child});
  @override
  bool updateShouldNotify(_SansEchelle oldWidget) => false;
}
