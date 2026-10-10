// lib/ventes/common/vente_layout.dart
// Ventes sur tablette paysage (≥ 900 dp) : recherche / scan et carte client à gauche, panier à droite
// (comme l'ancienne Pré-vente au-delà de 800 px). Téléphone et tablette portrait : une colonne, inchangée.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

/// true : panneaux côte à côte (tablette paysage).
bool venteSplit(BuildContext context) => Responsive.isExpanded(context);

class VenteSplitBody extends StatelessWidget {
  /// Clé du panneau de gauche (tests).
  final Key? panelKey;

  /// Panneau de gauche : carte client, champ de recherche…
  final List<Widget> side;

  /// Panneau de droite : bandeau d'état et panier.
  final Widget main;

  const VenteSplitBody({super.key, this.panelKey, required this.side, required this.main});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          flex: 2,
          child: ListView(key: panelKey, padding: const EdgeInsets.fromLTRB(12, 12, 12, 16), children: [
            for (final (i, w) in side.indexed) ...[if (i > 0) const SizedBox(height: 10), w],
            const SizedBox(height: 14),
            const Row(children: [
              Icon(Icons.qr_code_scanner, size: 20, color: Pal.muted),
              SizedBox(width: 8),
              Expanded(
                child: Text('Scannez ou recherchez un produit : il s\'ajoute au panier à droite.',
                    style: TextStyle(fontSize: 13, color: Pal.muted)),
              ),
            ]),
          ]),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: Pal.line),
        Expanded(flex: 3, child: main),
      ]);
}
