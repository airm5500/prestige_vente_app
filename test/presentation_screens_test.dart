// Les trois présentations (A, B, C) des écrans Analyse article et Proformas / Devis :
// mêmes données et mêmes actions, et aucun débordement sur un petit téléphone (360 px).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/article_analysis_model.dart';
import 'package:prestige_vente_app/api/models/proforma_models.dart';
import 'package:prestige_vente_app/providers/article_analysis_provider.dart';
import 'package:prestige_vente_app/providers/proforma_provider.dart';
import 'package:prestige_vente_app/screens/analysis/article_analysis_screen.dart';
import 'package:prestige_vente_app/screens/proforma/proforma_list_screen.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');

  @override
  Future<List<ArticleAnalysis>> fetchArticleAnalysis(String query) async => [
        ArticleAnalysis(
          produitId: 'p1',
          codeCip: '3595583',
          libelle: 'DOLIPRANE 1000MG CP B/8',
          emplacement: 'RAYON A3',
          grossiste: 'LABOREX',
          moyenne: 42.5,
          prixAchat: 1100,
          prixVente: 1500,
          quantiteVendue: 255,
          stock: 0,
          quantiteMoisBrut: '1:40,2:45',
        ),
        ArticleAnalysis(
          produitId: 'p2',
          codeCip: '3000000',
          libelle: 'DOLIPRANE 500MG CP B/16',
          emplacement: '',
          grossiste: 'DPCI',
          moyenne: 12,
          prixAchat: 600,
          prixVente: 900,
          quantiteVendue: 70,
          stock: 14,
          quantiteMoisBrut: '1:10,2:14',
        ),
      ];

  @override
  Future<List<ProformaListItem>> fetchProformas({String query = '', String dtStart = '', String dtEnd = ''}) async => [
        ProformaListItem(
          lgPREENREGISTREMENTID: 'v1',
          strREF: 'DV-0042',
          strClientFullName: 'CLINIQUE SAINTE MARIE DE COCODY',
          dtUPDATED: '10/10/2026',
          heure: '09:41',
          intPRICE: 1254300,
          strSTATUT: 'devis',
          strTYPEVENTE: 'VNO',
          userFullName: 'Awa Kouassi',
          clientId: 'c1',
        ),
      ];
}

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340); // 360 x 780
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  for (final style in ListPresentation.values) {
    testWidgets('Analyse article — ${style.label}', (tester) async {
      phone(tester);
      final api = _FakeApi();
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => ArticleAnalysisProvider(api),
        child: MaterialApp(home: ArticleAnalysisScreen(presentation: style)),
      ));
      expect(find.text('Saisissez le nom ou le code CIP du produit'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'doli');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('DOLIPRANE 1000MG CP B/8'), findsOneWidget);
      expect(find.text('DOLIPRANE 500MG CP B/16'), findsOneWidget);
      await tester.tap(find.text('DOLIPRANE 1000MG CP B/8'));
      await tester.pumpAndSettle();
      expect(find.text("Détails de l'Article"), findsOneWidget);
    });

    testWidgets('Proformas / Devis — ${style.label}', (tester) async {
      phone(tester);
      final api = _FakeApi();
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider(create: (_) => ProformaProvider(api)),
        ],
        child: MaterialApp(home: ProformaListScreen(presentation: style)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('CLINIQUE SAINTE MARIE DE COCODY'), findsOneWidget);
      expect(find.text('Nouveau Devis'), findsOneWidget);
      expect(find.byTooltip('Imprimer A4').evaluate().isNotEmpty || find.text('Imprimer A4').evaluate().isNotEmpty, isTrue);
    });
  }
}
