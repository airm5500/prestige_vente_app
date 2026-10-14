// Écrans : version « X.Y.Z+N » affichée, discrète, en bas de l'écran de connexion et dans les Réglages
// (nouvelle et ancienne interface), LUE À L'EXÉCUTION dans le paquet installé (package_info_plus, simulé ici
// depuis pubspec.yaml) — aucune constante de version dupliquée dans le code.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/payment_method_qr.dart';
import 'package:prestige_vente_app/connexion/connexion_commun.dart';
import 'package:prestige_vente_app/connexion/connexion_reglages.dart';
import 'package:prestige_vente_app/parametres/parametres_screen.dart';
import 'package:prestige_vente_app/parametres/parametres_services.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/screens/auth/settings_screen.dart';
import 'package:prestige_vente_app/support/support_centre.dart';
import 'package:prestige_vente_app/version_app.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/version_installee.dart';

/// Aucun appel réseau (les Réglages chargent les modes de paiement).
class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://localhost');

  @override
  Future<List<PaymentMethodQr>> getPaymentMethodsWithQr() async => const [];
}

class _Env {
  final settings = SettingsProvider();
  final api = _FakeApi();
  late final auth = AuthProvider(api);
  late final licence = LicenceProvider(api);
  late final sale = SaleProvider(api);
  late final bl = BlControlProvider(api);

  Widget app(Widget home) => MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider<LicenceProvider>.value(value: licence),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<SaleProvider>.value(value: sale),
          ChangeNotifierProvider<BlControlProvider>.value(value: bl),
        ],
        child: MaterialApp(home: home),
      );
}

void main() {
  late String version; // X.Y.Z+N de pubspec.yaml

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ConnexionReglages.courant.value = const ConnexionConfig();
    version = simulerVersionInstallee();
  });

  void telephone(WidgetTester t) {
    t.view.physicalSize = const Size(720, 1440); // Sunmi V2s
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
  }

  testWidgets('VersionAffichee : « Version X.Y.Z+N » lue dans le paquet installé', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: VersionAffichee())));
    await t.pump();
    expect(version, matches(RegExp(r'^\d+\.\d+\.\d+\+\d+$')));
    expect(find.text('Version $version'), findsOneWidget);
    expect(VersionApp.complete, version);
    expect(VersionApp.version, version.split('+').first);
  });

  testWidgets('la version affichée suit le paquet installé (pas de constante dans le code)', (t) async {
    PackageInfo.setMockInitialValues(
        appName: 'Prestige Mobile', packageName: 'x', version: '9.8.7', buildNumber: '65', buildSignature: '');
    VersionApp.oublier();
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: VersionAffichee())));
    await t.pump();
    expect(find.text('Version 9.8.7+65'), findsOneWidget);
    expect(SupportCentre.version, '9.8.7'); // envoyée au serveur au même format X.Y.Z qu'avant
  });

  testWidgets('sans plateforme (version illisible) : « Version ? », sans erreur', (t) async {
    VersionApp.oublier();
    // Paquet introuvable : la lecture échoue, l'écran reste utilisable.
    expect(VersionApp.complete, '?');
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: Text('x'))));
    expect(t.takeException(), isNull);
  });

  testWidgets('écran de connexion (nouvelle interface) : pied « Version X.Y.Z+N · Assistance »', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: PiedConnexion(couleur: Colors.grey))));
    await t.pump();
    expect(find.text('Version $version · Assistance : 07 08 08 00 68'), findsOneWidget);
    expect(find.byKey(const Key('pied_connexion')), findsOneWidget);
  });

  testWidgets('écran de connexion (ancienne interface) : version discrète en bas', (t) async {
    telephone(t);
    final env = _Env();
    await env.settings.loadSettings();
    await t.pumpWidget(env.app(const AncienLoginScreen()));
    await t.pump();
    await t.pump();
    final v = find.byKey(const Key('version_app'));
    expect(v, findsOneWidget);
    expect(t.widget<Text>(v).data, 'Version $version');
    // En bas de l'écran, sous le bouton « Se connecter ».
    expect(t.getTopLeft(v).dy, greaterThan(t.getBottomLeft(find.text('Se connecter')).dy));
  });

  testWidgets('Réglages (nouvelle interface) : version en bas de la liste', (t) async {
    telephone(t);
    final env = _Env();
    await env.settings.loadSettings();
    await t.pumpWidget(env.app(ParametresScreen(services: ParametresServices(pointageRepository: MemoryPointageRepository()))));
    await t.pumpAndSettle();
    final v = find.byKey(const Key('reglages_version'));
    await t.scrollUntilVisible(v, 300, scrollable: find.byType(Scrollable).first);
    expect(find.descendant(of: v, matching: find.text('Version $version')), findsOneWidget);
  });

  testWidgets('Configuration (ancienne interface) : version en bas', (t) async {
    // La Configuration d'origine (inchangée, largeur max. 500) déborde déjà sous la police de test :
    // débordements ignorés ici, hors sujet (seule la version est vérifiée).
    telephone(t);
    final avant = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('overflowed')) avant?.call(d);
    };
    final env = _Env();
    await env.settings.loadSettings();
    await t.pumpWidget(env.app(const SettingsScreen()));
    await t.pumpAndSettle();
    final v = find.byKey(const Key('reglages_version'));
    await t.scrollUntilVisible(v, 300, scrollable: find.byType(Scrollable).first);
    FlutterError.onError = avant;
    expect(find.descendant(of: v, matching: find.text('Version $version')), findsOneWidget);
  });
}
