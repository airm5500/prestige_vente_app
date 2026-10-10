// lib/ventes/prevente/vente_screen.dart
// Pré-vente / vente — nouvelle version (provisoire : en construction).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/screens/pre_vente/pre_vente_screen.dart';

class VenteScreen extends StatelessWidget {
  final int initialTabIndex;
  final String? resumeVenteId;
  const VenteScreen({super.key, this.initialTabIndex = 0, this.resumeVenteId});

  @override
  Widget build(BuildContext context) => PreVenteScreen(initialTabIndex: initialTabIndex);
}
