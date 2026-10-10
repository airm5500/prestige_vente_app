// lib/screens/perimes/perime_main_screen.dart
// Gestion des Périmés : Recherche, Saisie en cours, Historique.
// Présentations au choix : A · Tableau de bord (défaut), B · Liste groupée, C · Parcours guidé.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/perime_provider.dart';
import 'package:prestige_vente_app/screens/perimes/perime_widgets.dart';
import 'package:prestige_vente_app/screens/perimes/tabs/historique_saisies_tab.dart';
import 'package:prestige_vente_app/screens/perimes/tabs/recherche_perimes_tab.dart';
import 'package:prestige_vente_app/screens/perimes/tabs/saisie_en_cours_tab.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

class PerimeMainScreen extends StatefulWidget {
  /// Présentation (A, B, C) ; celle de l'appareil si non précisée.
  final ListPresentation? presentation;
  const PerimeMainScreen({super.key, this.presentation});

  @override
  State<PerimeMainScreen> createState() => _PerimeMainScreenState();
}

class _PerimeMainScreenState extends State<PerimeMainScreen> with SingleTickerProviderStateMixin, PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  late final TabController _tabController;

  static const _tabs = [
    (Icons.search, 'Recherche'),
    (Icons.edit_document, 'Saisie'),
    (Icons.history, 'Historique'),
  ];

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTab);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTab);
    _tabController.dispose();
    super.dispose();
  }

  void _onTab() {
    if (mounted) setState(() {});
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  void _go(int i) => _tabController.animateTo(i);

  // Chiffres clés de l'onglet affiché.
  List<(String, String, bool)> _figures(PerimeProvider p) {
    switch (_tabController.index) {
      case 0:
        final meta = p.metaData;
        return [
          (Constants.formatNumber(meta?.totalQuantiteLot ?? 0), 'Qté totale', false),
          (Constants.formatNumber(meta?.totalValeurAchat ?? 0), 'Val. achat', false),
          (Constants.formatNumber(meta?.totalValeurVente ?? 0), 'Val. vente', true),
        ];
      case 1:
        final boxes = p.saisieEnCoursList.fold<int>(0, (s, e) => s + e.quantity);
        return [
          ('${p.saisieEnCoursList.length}', 'lignes en cours', false),
          (Constants.formatNumber(boxes), 'boîtes à sortir', true),
        ];
      default:
        final boxes = p.saisieHistoryList.fold<int>(0, (s, e) => s + e.intQUANTITY);
        return [
          ('${p.saisieHistoryList.length}', 'sorties', false),
          (Constants.formatNumber(boxes), 'boîtes sorties', true),
        ];
    }
  }

  static const _subtitles = [
    'Produits périmés ou à date courte',
    'Sortie du stock des produits périmés',
    'Sorties de stock validées',
  ];

  @override
  Widget build(BuildContext context) {
    // Clavier ouvert : on masque les chiffres pour laisser la place à la saisie.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Consumer<PerimeProvider>(
      builder: (context, provider, _) {
        final figs = _figures(provider);
        final kpis = Row(children: [
          for (var i = 0; i < figs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: PerimeKpi(figs[i].$1, figs[i].$2, highlight: figs[i].$3)),
          ],
        ]);
        return PresentationScaffold(
          style: style,
          title: 'Gestion des Périmés',
          subtitle: style == ListPresentation.dashboard ? _subtitles[_tabController.index] : null,
          actions: (c) => [PresentationMenuButton(value: style, onChanged: _setStyle, color: c)],
          steps: StepsBar(active: _tabController.index, steps: [
            (title: 'Recherche', detail: '${provider.produitsPerimesList.length} lot(s)', onTap: () => _go(0)),
            (title: 'Saisie', detail: '${provider.saisieEnCoursList.length} en cours', onTap: () => _go(1)),
            (title: 'Historique', detail: 'sorties validées', onTap: () => _go(2)),
          ]),
          header: [
            if (style == ListPresentation.dashboard) PerimeTabBar(controller: _tabController, tabs: _tabs),
            if (!keyboard) kpis,
          ],
          compactHeader: [
            PerimeTabBar(controller: _tabController, tabs: _tabs, dark: false),
            if (!keyboard)
              LightFigures([
                for (final f in figs) (f.$1, f.$2, f.$3 ? const Color(0xFFB45309) : Pal.navy),
              ]),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              RecherchePerimesTab(presentation: style),
              SaisieEnCoursTab(presentation: style),
              HistoriqueSaisiesTab(presentation: style),
            ],
          ),
        );
      },
    );
  }
}
