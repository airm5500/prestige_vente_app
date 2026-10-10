// lib/screens/perimes/tabs/saisie_perimes_screen.dart
// Saisie en cours + Historique des saisies dans deux sous-onglets lisibles
// (texte blanc, indicateur ambre sur fond bleu). Le menu principal affiche
// désormais ces deux onglets directement ; cet écran reste disponible tel quel.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/screens/perimes/perime_widgets.dart';
import 'package:prestige_vente_app/screens/perimes/tabs/historique_saisies_tab.dart';
import 'package:prestige_vente_app/screens/perimes/tabs/saisie_en_cours_tab.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

class SaisiePerimesScreen extends StatefulWidget {
  /// Présentation imposée par l'écran parent ; celle de l'appareil sinon.
  final ListPresentation? presentation;
  const SaisiePerimesScreen({super.key, this.presentation});

  @override
  State<SaisiePerimesScreen> createState() => _SaisiePerimesScreenState();
}

class _SaisiePerimesScreenState extends State<SaisiePerimesScreen> with SingleTickerProviderStateMixin, PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didUpdateWidget(covariant SaisiePerimesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final p = widget.presentation;
    if (p != null && p != style) style = p;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = style == ListPresentation.compact;
    return Column(
      children: [
        Container(
          color: compact ? Colors.white : Pal.navy,
          child: PerimeTabBar(
            controller: _tabController,
            dark: !compact,
            tabs: const [
              (Icons.edit_document, 'Saisie en Cours'),
              (Icons.history, 'Historique des Saisies'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              SaisieEnCoursTab(presentation: style),
              HistoriqueSaisiesTab(presentation: style),
            ],
          ),
        ),
      ],
    );
  }
}
