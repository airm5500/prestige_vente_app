// Pointage présence (Prestige, menu `pointage_rh`) : voie A (téléphone de l'employé, API v1/mobile, jeton Bearer) et voie B (terminal
// commun, API v1/rh, badge / NFC / empreinte, file hors ligne), présences du jour, mise en page 360 px / tablette.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/rapports_hl_screen.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_models.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/pointage/pointage_export.dart';
import 'package:prestige_vente_app/pointage/pointage_logic.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/rh/empreintes_screen.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/localisation.dart';
import 'package:prestige_vente_app/rh/mobile_api.dart';
import 'package:prestige_vente_app/rh/mobile_pointage_screen.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/presences_screen.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/rh/rh_pointage_screen.dart';
import 'package:prestige_vente_app/rh/rh_store.dart';
import 'package:prestige_vente_app/rh/terminal_pointage_screen.dart';
import 'package:prestige_vente_app/screens/pointage/pointage_home_screen.dart';
import 'package:prestige_vente_app/screens/pointage/pointage_report_screen.dart';
import 'package:prestige_vente_app/services/nfc_service.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Faux serveur, faux matériel
// ---------------------------------------------------------------------------

class FakeTransport implements TransportMobile {
  bool offline = false;
  final appels = <({String methode, String chemin, Map<String, dynamic>? corps, String? jeton})>[];
  final Map<String, ReponseHttp Function(Map<String, dynamic>? corps)> routes = {};

  @override
  Future<ReponseHttp> envoyer(String methode, String chemin, {Map<String, dynamic>? corps, String? jeton}) async {
    if (offline) throw const MobileHorsLigne();
    appels.add((methode: methode, chemin: chemin, corps: corps, jeton: jeton));
    final f = routes['$methode $chemin'];
    return f == null ? (status: 404, body: null) : f(corps);
  }

  List<Map<String, dynamic>?> corpsDe(String methode, String chemin) =>
      [for (final a in appels) if (a.methode == methode && a.chemin == chemin) a.corps];
}

Map<String, dynamic> moiJson({bool employe = true, bool pointage = true, bool qr = true, bool gps = false}) => {
      'success': true,
      'utilisateur': {'id': 'U1', 'login': 'awa', 'nom': 'Awa Kouassi'},
      'employe': employe ? {'id': 'E1', 'matricule': 'M01', 'nom': 'KOUASSI Awa'} : null,
      'droits': {'pointage': pointage, 'photos': false},
      'pointage': {'qr': qr, 'gps': gps},
    };

class FakeRh implements RhServeur {
  bool offline = false;
  int droitsStatus = 200;
  Map<String, dynamic> droits = {'success': true, 'valider': true};
  List<Map<String, dynamic>> employes = [
    {'id': 'E1', 'matricule': 'M01', 'badge': 'PV12AB34', 'nom': 'KOUASSI', 'prenoms': 'Awa Marie', 'statut': 'ACTIF'},
    {'id': 'E2', 'matricule': 'M02', 'badge': '04A1B2C3', 'nom': 'YAO', 'prenoms': 'Koffi', 'statut': 'ACTIF'},
  ];
  List<Map<String, dynamic>> presences = [];
  List<Map<String, dynamic>> pointagesJour = [];
  final posts = <Map<String, dynamic>>[];
  final _deja = <String>{};
  String? refus;

  /// Code HTTP imposé aux POST (401 : session de l'application expirée, corps non JSON comme Prestige).
  int? postStatus;
  int getsEmployes = 0;

  @override
  Future<ReponseRh> get(String chemin, [Map<String, dynamic> query = const {}]) async {
    if (offline) throw const RhHorsLigne();
    switch (chemin) {
      case '/rh/droits':
        return (status: droitsStatus, body: droitsStatus == 404 ? null : droits);
      case '/rh/employes':
        getsEmployes++;
        return (status: 200, body: {'success': true, 'data': employes});
      case '/rh/presence':
        return (status: 200, body: {'success': true, 'data': presences, 'pointages': pointagesJour});
    }
    return (status: 404, body: null);
  }

  @override
  Future<ReponseRh> post(String chemin, Map<String, dynamic> corps) async {
    if (offline) throw const RhHorsLigne();
    if (postStatus != null) return (status: postStatus!, body: null);
    posts.add(corps);
    if (refus != null) return (status: 200, body: {'success': false, 'msg': refus, 'message': refus});
    // INSERT IGNORE du serveur : même employé, même minute → refus « existe déjà ».
    if (!_deja.add('${corps['employeId']}|${corps['jour']}|${corps['heure']}')) {
      const m = 'Un pointage existe déjà à cette heure pour cet employé.';
      return (status: 200, body: {'success': false, 'msg': m, 'message': m});
    }
    return (status: 200, body: {'success': true, 'message': 'Pointage manuel enregistré.'});
  }
}

class FakeNfc implements NfcReader {
  NfcAvailability etat;
  final _tags = StreamController<String>.broadcast();
  FakeNfc([this.etat = NfcAvailability.ready]);
  void approcher(String uid) => _tags.add(uid);
  @override
  Future<NfcAvailability> availability() async => etat;
  @override
  Stream<String> get tags => _tags.stream;
  @override
  Future<bool> start() async => etat == NfcAvailability.ready;
  @override
  Future<void> stop() async {}
  @override
  Future<void> openSettings() async {}
}

class FakeEmpreinte implements FournisseurEmpreinte {
  bool present;
  int? reconnu;
  int captures = 0;
  List<Uint8List> derniersModeles = [];
  FakeEmpreinte({this.present = true, this.reconnu = 0});
  @override
  Future<bool> disponible() async => present;
  @override
  Future<Uint8List> enroler() async {
    if (!present) throw const EmpreinteIndisponible();
    captures++;
    return Uint8List.fromList([0xF0, captures]);
  }

  @override
  Future<int?> identifier(List<Uint8List> modeles) async {
    if (!present) throw const EmpreinteIndisponible();
    derniersModeles = modeles;
    return reconnu;
  }

  @override
  Future<void> annuler() async {}
}

class FakeLocalisateur implements Localisateur {
  ResultatPosition r;
  int appels = 0;
  final exigences = <bool>[];

  /// Position qui ne vient jamais (délai court de la position facultative).
  bool bloque = false;
  FakeLocalisateur(this.r);
  @override
  Future<ResultatPosition> position({required bool exigee}) {
    appels++;
    exigences.add(exigee);
    return bloque ? Completer<ResultatPosition>().future : Future.value(r);
  }

  @override
  Future<void> ouvrirReglages() async {}
}

/// Plate-forme de localisation factice : compte les DEMANDES d'autorisation (jamais pour une position facultative).
class FakePlateformeGeo implements PlateformeGeo {
  bool service = true;
  LocationPermission permission;
  LocationPermission apresDemande;
  int demandes = 0;
  int lectures = 0;
  FakePlateformeGeo(this.permission, {this.apresDemande = LocationPermission.whileInUse});
  @override
  Future<bool> serviceActif() async => service;
  @override
  Future<LocationPermission> verifierPermission() async => permission;
  @override
  Future<LocationPermission> demanderPermission() async {
    demandes++;
    return permission = apresDemande;
  }

  @override
  Future<PositionPointage> positionActuelle(Duration limite) async {
    lectures++;
    return const PositionPointage(5.3364, -4.0267, 12);
  }

  @override
  Future<void> ouvrirReglages() async {}
}

/// Position facultative indisponible (autorisation non accordée) : le pointage part sans position. Les tests
/// d'écran l'utilisent au lieu du vrai plugin de localisation (absent sous `flutter test`).
FakeLocalisateur sansPosition() => FakeLocalisateur(const ResultatPosition.echec('Localisation non autorisée.'));

final DateTime h0802 = DateTime(2026, 10, 12, 8, 2);

class Env {
  final rh = FakeRh();
  final transport = FakeTransport();
  final coffre = CoffreJetonMemoire();
  final journal = JournalTerminal(store: MemoryJournalStore());
  final empreinte = FakeEmpreinte(present: false);
  final nfc = FakeNfc(NfcAvailability.absent);
  final coffreEmpreintes = CoffreEmpreintesMemoire();
  bool horsLigne = false;
  DateTime now = h0802;
  late final MobileApi mobile = MobileApi(
    transport: transport,
    coffre: coffre,
    appareil: () => 'T-ABC123',
    nomAppareil: () => 'SUNMI V3H',
    clock: () => now,
  );
  late final IdentificationEmploye identification = IdentificationEmploye(empreinte: empreinte, nfc: nfc, coffre: coffreEmpreintes);
  late final PointageRh pr = PointageRh(
    store: MemoryRhStore(),
    serveur: rh,
    mobile: mobile,
    identification: identification,
    clock: () => now,
    horsLigne: () => horsLigne,
    nomTerminal: () => 'Accueil',
    journal: () => journal,
  );
}

void tailleTelephone(WidgetTester t) {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void tailleTablette(WidgetTester t) {
  t.view.physicalSize = const Size(1280, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> pump(WidgetTester t, Widget w) async {
  await t.pumpWidget(MaterialApp(home: KeyedSubtree(key: UniqueKey(), child: w)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  // =========================================================================
  // Modèles et règles
  // =========================================================================
  group('Règles', () {
    test('badge → employé : insensible à la casse et aux caractères du lecteur, puis matricule ; inactif ignoré', () {
      final l = [
        const EmployeRh(id: 'a', badge: 'PV12AB34', matricule: 'M01', nom: 'A'),
        const EmployeRh(id: 'b', badge: 'XX', matricule: 'm02', nom: 'B'),
        const EmployeRh(id: 'c', badge: 'ZZ9', nom: 'C', statut: 'INACTIF'),
      ];
      expect(employePourBadge(l, ' pv12ab34\r\n')?.id, 'a');
      expect(employePourBadge(l, 'M02')?.id, 'b');
      expect(employePourBadge(l, 'zz9'), isNull);
      expect(employePourBadge(l, ''), isNull);
    });

    test('sens proposé = inverse du dernier ; QR de pointage ; doublon du serveur ; UID NFC', () {
      expect(sensPropose(null), SensPointage.entree);
      expect(sensPropose(SensPointage.entree), SensPointage.sortie);
      expect(sensPropose(SensPointage.sortie), SensPointage.entree);
      expect(dernierSensDuJour(const [
        PointageJourRh(employeId: 'a', horodatage: '2026-10-12 08:00', sens: SensPointage.entree),
        PointageJourRh(employeId: 'a', horodatage: '2026-10-12 12:00', sens: SensPointage.sortie),
        PointageJourRh(employeId: 'b', horodatage: '2026-10-12 13:00', sens: SensPointage.entree),
      ], 'a'), SensPointage.sortie);
      expect(estQrPointage('prestige-pointage:ABC234'), isTrue);
      expect(estQrPointage('3400930000001'), isFalse);
      expect(codePointagePourEnvoi(' abc 234 '), 'ABC234');
      expect(estDoublonServeur('Un pointage existe déjà à cette heure pour cet employé.'), isTrue);
      expect(normaliserUidNfc('04:a1:b2:c3'), '04A1B2C3');
      expect(MoyenIdentification.empreinte.motif('Accueil'), 'Empreinte terminal Accueil');
      expect(MoyenIdentification.nfc.motif('Accueil'), 'Badge terminal Accueil');
    });

    test('présence : anomalies en clair, durées', () {
      final p = PresenceRh.fromJson({'employeId': 'a', 'employe': 'A', 'entree': '08:12', 'retard': 12, 'anomalies': 'DOUBLON,ENTREE_SANS_SORTIE'});
      expect(p.present, isTrue);
      expect(p.enRetard, isTrue);
      expect(p.anomaliesLisibles, ['doublon', 'entrée sans sortie']);
      expect(dureeLisible(78), '1 h 18');
      expect(dureeLisible(12), '12 min');
    });
  });

  // =========================================================================
  // Voie A : API v1/mobile
  // =========================================================================
  group('Voie A — API', () {
    test('connexion : jeton gardé dans le coffre (jamais le mot de passe), Bearer ensuite ; appareil du terminal', () async {
      final e = Env();
      e.transport.routes['POST connexion'] = (c) => (status: 200, body: {...moiJson(), 'jeton': 'JETON-SECRET', 'expiration': '2026-10-12T20:00:00Z'});
      e.transport.routes['GET pointages'] = (_) => (status: 200, body: {'success': true, 'data': []});
      final r = await e.mobile.connexion('awa', 'MotDePasse!');
      expect(r.ok, isTrue);
      expect(r.valeur!.peutPointer, isTrue);
      final envoye = e.transport.corpsDe('POST', 'connexion').single!;
      expect(envoye['appareil'], 'T-ABC123');
      expect(envoye['nomAppareil'], 'SUNMI V3H');
      expect(e.coffre.valeur, contains('JETON-SECRET'));
      expect(e.coffre.valeur, isNot(contains('MotDePasse')));
      await e.mobile.mesPointages();
      expect(e.transport.appels.last.jeton, 'JETON-SECRET');
      expect(e.transport.appels.first.jeton, isNull);
    });

    test('coffre sécurisé (flutter_secure_storage) : rien dans les préférences en clair', () async {
      const c = CoffreJetonSecurise();
      await c.ecrire('{"jeton":"J"}');
      expect(await c.lire(), '{"jeton":"J"}');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => '${prefs.get(k)}'.contains('"jeton"')), isEmpty);
      await c.effacer();
      expect(await c.lire(), isNull);
    });

    test('401 {"expire":true} → jeton effacé, reconnexion demandée ; jeton expiré localement → reconnexion', () async {
      final e = Env();
      e.coffre.valeur = jsonEncode({...moiJson(), 'jeton': 'J1', 'expiration': '2026-10-12T20:00:00Z'});
      e.transport.routes['GET moi'] = (_) => (status: 401, body: {'success': false, 'expire': true, 'message': 'Session du téléphone expirée : reconnectez-vous.'});
      await expectLater(e.mobile.moi(), throwsA(isA<MobileSessionExpiree>()));
      expect(e.coffre.valeur, isNull);
      expect(e.mobile.session, isNull);

      final e2 = Env();
      e2.coffre.valeur = jsonEncode({...moiJson(), 'jeton': 'J1', 'expiration': '2026-10-12T07:00:00Z'});
      e2.now = DateTime.utc(2026, 10, 12, 8);
      expect(await e2.mobile.reprendre(), isNull);
      expect(e2.coffre.valeur, isNull);
    });

    test('module inactif (KEY_MOBILE_ACTIF=0) et route absente (404) détectés', () async {
      final e = Env();
      e.transport.routes['POST connexion'] =
          (_) => (status: 200, body: {'success': false, 'msg': 'La connexion des téléphones est désactivée par l\'officine.'});
      final r = await e.mobile.connexion('awa', 'x');
      expect(r.moduleInactif, isTrue);
      expect(r.refus, messageModuleMobileInactif);
      expect(await e.mobile.sonder(), (existe: true, actif: false));
      e.transport.routes.clear();
      expect(await e.mobile.sonder(), (existe: false, actif: false));
      e.transport.offline = true;
      expect(await e.mobile.sonder(), isNull);
    });
  });

  group('Voie A — écran', () {
    Env connecte({bool qr = true, bool gps = false, bool employe = true}) {
      final e = Env();
      e.coffre.valeur = jsonEncode({...moiJson(qr: qr, gps: gps, employe: employe), 'jeton': 'J1', 'expiration': '2026-10-12T20:00:00Z'});
      e.now = DateTime(2026, 10, 12, 8, 2);
      e.transport.routes['GET moi'] = (_) => (status: 200, body: moiJson(qr: qr, gps: gps, employe: employe));
      e.transport.routes['GET pointages'] = (_) => (status: 200, body: {'success': true, 'data': []});
      return e;
    }

    testWidgets('QR exigé : « Arrivée » puis scan → POST ENTREE avec le code brut ; résultat en grand ; « Départ » suggéré ensuite', (t) async {
      tailleTelephone(t);
      final e = connecte();
      var hist = <Map<String, dynamic>>[];
      e.transport.routes['GET pointages'] = (_) => (status: 200, body: {'success': true, 'data': hist});
      e.transport.routes['POST pointages'] = (c) {
        hist = [{'heure': '08:02', 'sens': 'ENTREE', 'source': 'MOBILE'}];
        return (status: 200, body: {'success': true, 'sens': 'ENTREE', 'heure': '08:02', 'message': 'Entrée enregistrée à 08:02.'});
      };
      await pump(t, MobilePointageScreen(rh: e.pr, presentation: ListPresentation.dashboard, scanner: (_) async => 'PRESTIGE-POINTAGE:ABC234', localisateur: sansPosition()));
      expect(find.text('QR code de l\'officine exigé'), findsOneWidget);
      expect(find.byKey(const Key('rh_suggere_arrivee')), findsOneWidget); // aucun pointage : arrivée suggérée
      await t.tap(find.byKey(const Key('rh_arrivee')));
      await t.pumpAndSettle();
      final corps = e.transport.corpsDe('POST', 'pointages').single!;
      expect(corps['code'], 'PRESTIGE-POINTAGE:ABC234');
      expect(corps['sens'], 'ENTREE');
      expect(corps.containsKey('latitude'), isFalse);
      expect(find.text('Entrée enregistrée à 08:02.'), findsOneWidget);
      // historique rechargé après le pointage : le départ devient le bouton suggéré
      expect(e.transport.appels.where((a) => a.methode == 'GET' && a.chemin == 'pointages').length, greaterThanOrEqualTo(2));
      expect(find.text('08:02 · Entrée'), findsOneWidget);
      expect(find.byKey(const Key('rh_suggere_depart')), findsOneWidget);
      expect(find.byKey(const Key('rh_suggere_arrivee')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('QR exigé : autre code scanné → message, rien envoyé ; refus du serveur affiché tel quel', (t) async {
      tailleTelephone(t);
      final e = connecte();
      var lu = '3400930000001';
      e.transport.routes['POST pointages'] =
          (_) => (status: 200, body: {'success': false, 'message': 'Code de pointage invalide ou expiré : scannez le QR code affiché à l\'officine.'});
      await pump(t, MobilePointageScreen(rh: e.pr, presentation: ListPresentation.dashboard, scanner: (_) async => lu, localisateur: sansPosition()));
      await t.tap(find.byKey(const Key('rh_arrivee')));
      await t.pumpAndSettle();
      expect(find.textContaining('Ce n\'est pas le QR code de pointage'), findsOneWidget);
      expect(e.transport.corpsDe('POST', 'pointages'), isEmpty);
      lu = 'PRESTIGE-POINTAGE:OLD999';
      await t.tap(find.byKey(const Key('rh_arrivee')));
      await t.pumpAndSettle();
      expect(find.text('Code de pointage invalide ou expiré : scannez le QR code affiché à l\'officine.'), findsOneWidget);
    });

    testWidgets('GPS exigé : localisation refusée → message clair, rien envoyé ; acceptée → position envoyée', (t) async {
      tailleTelephone(t);
      final e = connecte(qr: false, gps: true);
      e.transport.routes['POST pointages'] = (_) => (status: 200, body: {'success': true, 'sens': 'ENTREE', 'heure': '08:02', 'message': 'Entrée enregistrée à 08:02.'});
      final loc = FakeLocalisateur(const ResultatPosition.echec('Localisation refusée : l\'officine exige la position du téléphone pour pointer.'));
      await pump(t, MobilePointageScreen(rh: e.pr, presentation: ListPresentation.dashboard, localisateur: loc));
      expect(find.text('Position exigée'), findsOneWidget);
      await t.tap(find.byKey(const Key('rh_arrivee')));
      await t.pumpAndSettle();
      expect(find.textContaining('Localisation refusée'), findsOneWidget);
      expect(e.transport.corpsDe('POST', 'pointages'), isEmpty);
      loc.r = const ResultatPosition.ok(PositionPointage(5.3205, -4.02, 12));
      await t.tap(find.byKey(const Key('rh_arrivee')));
      await t.pumpAndSettle();
      final c = e.transport.corpsDe('POST', 'pointages').single!;
      expect([c['latitude'], c['longitude'], c['precision']], [5.3205, -4.02, 12.0]);
      expect(c.containsKey('code'), isFalse);
      expect(loc.exigences, [true, true]); // GPS exigé : position EXIGÉE (autorisation demandée si besoin)
    });

    testWidgets('401 pendant le pointage → retour à la connexion ; connexion par l\'écran (identifiant pré-rempli)', (t) async {
      tailleTelephone(t);
      final e = connecte(qr: false);
      e.transport.routes['POST pointages'] = (_) => (status: 401, body: {'success': false, 'expire': true, 'message': 'Session du téléphone expirée : reconnectez-vous.'});
      e.transport.routes['POST connexion'] = (_) => (status: 200, body: {...moiJson(qr: false), 'jeton': 'J2', 'expiration': '2026-10-12T20:00:00Z'});
      await pump(t, MobilePointageScreen(rh: e.pr, login: 'awa', presentation: ListPresentation.compact, localisateur: sansPosition()));
      await t.tap(find.byKey(const Key('rh_arrivee')));
      await t.pumpAndSettle();
      expect(find.text('Session du téléphone expirée : reconnectez-vous.'), findsOneWidget);
      expect(find.byKey(const Key('rh_mobile_mdp')), findsOneWidget);
      expect(e.coffre.valeur, isNull);
      expect(find.widgetWithText(TextField, 'awa'), findsOneWidget);
      await t.enterText(find.byKey(const Key('rh_mobile_mdp')), 'secret');
      await t.tap(find.byKey(const Key('rh_mobile_connecter')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rh_arrivee')), findsOneWidget);
      expect(find.byKey(const Key('rh_depart')), findsOneWidget);
      expect(e.coffre.valeur, contains('J2'));
      expect(e.coffre.valeur, isNot(contains('secret')));
    });

    testWidgets('compte sans employé : pas de pointage ; hors ligne : disponible en ligne uniquement', (t) async {
      tailleTelephone(t);
      final e = connecte(employe: false);
      await pump(t, MobilePointageScreen(rh: e.pr, presentation: ListPresentation.guided));
      expect(find.textContaining('rattaché à aucun employé'), findsOneWidget);
      expect(find.byKey(const Key('rh_arrivee')), findsNothing);
      expect(find.byKey(const Key('rh_depart')), findsNothing);

      final e2 = connecte();
      e2.horsLigne = true;
      await pump(t, MobilePointageScreen(rh: e2.pr, presentation: ListPresentation.dashboard));
      expect(find.textContaining('Disponible en ligne uniquement'), findsWidgets);
      expect(t.widget<ElevatedButton>(find.byKey(const Key('rh_arrivee'))).onPressed, isNull);
      expect(t.widget<ElevatedButton>(find.byKey(const Key('rh_depart'))).onPressed, isNull);
    });

    testWidgets('« Arrivée » → ENTREE, « Départ » → SORTIE ; le bouton suggéré n\'est jamais imposé', (t) async {
      tailleTelephone(t);
      final e = connecte(qr: false);
      // dernier pointage : ENTREE → « Départ » suggéré
      e.transport.routes['GET pointages'] = (_) => (status: 200, body: {'success': true, 'data': [{'heure': '07:58', 'sens': 'ENTREE', 'source': 'POINTEUSE'}]});
      e.transport.routes['POST pointages'] = (c) => (status: 200, body: {'success': true, 'sens': c!['sens'], 'heure': '08:02', 'message': 'Enregistré.'});
      await pump(t, MobilePointageScreen(rh: e.pr, presentation: ListPresentation.dashboard, localisateur: sansPosition()));
      expect(find.text('KOUASSI Awa · M01'), findsOneWidget); // en-tête : nom et matricule
      expect(find.byKey(const Key('rh_suggere_depart')), findsOneWidget);
      expect(find.byKey(const Key('rh_suggere_arrivee')), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('rh_depart')), matching: find.text('suggéré')), findsOneWidget);
      // l'arrivée reste utilisable même si le départ est suggéré
      await t.tap(find.byKey(const Key('rh_arrivee')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rh_depart')));
      await t.pumpAndSettle();
      expect(e.transport.corpsDe('POST', 'pointages').map((c) => c!['sens']), ['ENTREE', 'SORTIE']);
      expect(t.takeException(), isNull);
    });

    testWidgets('deux gestes : un appui → scan → POST aussitôt, aucune confirmation intermédiaire', (t) async {
      tailleTelephone(t);
      final e = connecte();
      e.transport.routes['POST pointages'] = (_) => (status: 200, body: {'success': true, 'sens': 'SORTIE', 'heure': '08:02', 'message': 'Sortie enregistrée à 08:02.'});
      var scans = 0;
      await pump(
          t,
          MobilePointageScreen(
            rh: e.pr,
            presentation: ListPresentation.guided,
            localisateur: sansPosition(),
            scanner: (_) async {
              scans++;
              return 'PRESTIGE-POINTAGE:XYZ789';
            },
          ));
      await t.tap(find.byKey(const Key('rh_depart'))); // geste 1 (le scan est le geste 2)
      await t.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      await t.pumpAndSettle();
      expect(scans, 1);
      final c = e.transport.corpsDe('POST', 'pointages').single!;
      expect(c['sens'], 'SORTIE');
      expect(c['code'], 'PRESTIGE-POINTAGE:XYZ789');
      expect(find.text('Sortie enregistrée à 08:02.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('GPS non exigé : position envoyée si l\'autorisation est déjà accordée, sans elle sinon (jamais bloquant)', (t) async {
      tailleTelephone(t);
      final e = connecte(qr: false, gps: false);
      e.transport.routes['POST pointages'] = (_) => (status: 200, body: {'success': true, 'sens': 'ENTREE', 'heure': '08:02', 'message': 'Entrée enregistrée à 08:02.'});
      final loc = FakeLocalisateur(const ResultatPosition.ok(PositionPointage(5.3364, -4.0267, 12)));
      await pump(t, MobilePointageScreen(rh: e.pr, presentation: ListPresentation.dashboard, localisateur: loc));
      expect(find.text('Position non exigée'), findsOneWidget);
      await t.tap(find.byKey(const Key('rh_arrivee')));
      await t.pumpAndSettle();
      var c = e.transport.corpsDe('POST', 'pointages').last!;
      expect([c['latitude'], c['longitude'], c['precision']], [5.3364, -4.0267, 12.0]);
      expect(loc.exigences, [false]); // jamais « exigée » : l'autorisation n'est pas demandée
      // autorisation absente : envoi sans position, aucun message d'erreur de localisation
      loc.r = const ResultatPosition.echec('Localisation non autorisée.');
      await t.tap(find.byKey(const Key('rh_depart')));
      await t.pumpAndSettle();
      c = e.transport.corpsDe('POST', 'pointages').last!;
      expect(c.keys.toSet().intersection({'latitude', 'longitude', 'precision'}), isEmpty);
      expect(c['sens'], 'SORTIE');
      expect(find.textContaining('Localisation'), findsNothing);
      expect(loc.exigences, [false, false]);
      // position qui ne vient pas : envoi sans elle après le délai court (~5 s)
      loc.bloque = true;
      final avant = e.transport.corpsDe('POST', 'pointages').length;
      await t.tap(find.byKey(const Key('rh_arrivee')));
      await t.pump(const Duration(seconds: 3));
      expect(e.transport.corpsDe('POST', 'pointages'), hasLength(avant));
      await t.pump(delaiPositionFacultative);
      await t.pumpAndSettle();
      expect(e.transport.corpsDe('POST', 'pointages'), hasLength(avant + 1));
      expect(e.transport.corpsDe('POST', 'pointages').last!.containsKey('latitude'), isFalse);
      expect(t.takeException(), isNull);
    });

    test('localisation : GPS non exigé → autorisation VÉRIFIÉE jamais demandée ; GPS exigé → demandée comme avant', () async {
      // non exigé, autorisation déjà accordée → position
      final ok = FakePlateformeGeo(LocationPermission.whileInUse);
      final r1 = await GeoLocalisateur(ok).position(exigee: false);
      expect(r1.ok, isTrue);
      expect(r1.position!.latitude, 5.3364);
      expect(ok.demandes, 0);
      // non exigé, autorisation pas encore donnée → aucune demande, aucune lecture
      for (final p in [LocationPermission.denied, LocationPermission.deniedForever, LocationPermission.unableToDetermine]) {
        final f = FakePlateformeGeo(p);
        expect((await GeoLocalisateur(f).position(exigee: false)).ok, isFalse);
        expect(f.demandes, 0);
        expect(f.lectures, 0);
      }
      // non exigé, localisation coupée → rien
      final coupe = FakePlateformeGeo(LocationPermission.always)..service = false;
      expect((await GeoLocalisateur(coupe).position(exigee: false)).ok, isFalse);
      // exigé : autorisation demandée (comportement d'origine), messages et réglages inchangés
      final ex = FakePlateformeGeo(LocationPermission.denied);
      expect((await GeoLocalisateur(ex).position(exigee: true)).ok, isTrue);
      expect(ex.demandes, 1);
      final refus = FakePlateformeGeo(LocationPermission.denied, apresDemande: LocationPermission.denied);
      expect((await GeoLocalisateur(refus).position(exigee: true)).erreur, 'Localisation refusée : l\'officine exige la position du téléphone pour pointer.');
      final jamais = FakePlateformeGeo(LocationPermission.deniedForever);
      final r3 = await GeoLocalisateur(jamais).position(exigee: true);
      expect(r3.reglages, isTrue);
      expect(jamais.demandes, 0);
      final off = FakePlateformeGeo(LocationPermission.whileInUse)..service = false;
      final r4 = await GeoLocalisateur(off).position(exigee: true);
      expect(r4.erreur, contains('localisation du téléphone est coupée'));
      expect(r4.reglages, isTrue);
    });

    testWidgets('saisie manuelle du code en secours : code puis « Départ » → SORTIE', (t) async {
      tailleTelephone(t);
      final e = connecte();
      e.transport.routes['POST pointages'] = (_) => (status: 200, body: {'success': true, 'sens': 'SORTIE', 'heure': '08:02', 'message': 'Sortie enregistrée à 08:02.'});
      var scans = 0;
      await pump(
          t,
          MobilePointageScreen(
              rh: e.pr,
              presentation: ListPresentation.compact,
              localisateur: sansPosition(),
              scanner: (_) async {
                scans++;
                return null;
              }));
      await t.tap(find.byKey(const Key('rh_saisir_code')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('rh_code_saisi')), ' abc 234 ');
      await t.tap(find.byKey(const Key('rh_code_depart')));
      await t.pumpAndSettle();
      final c = e.transport.corpsDe('POST', 'pointages').single!;
      expect(c['code'], 'ABC234');
      expect(c['sens'], 'SORTIE');
      expect(scans, 0);
      expect(find.text('Sortie enregistrée à 08:02.'), findsOneWidget);
    });

    testWidgets('déconnexion : le jeton est effacé du téléphone, retour à la connexion', (t) async {
      tailleTelephone(t);
      final e = connecte();
      await pump(t, MobilePointageScreen(rh: e.pr, presentation: ListPresentation.dashboard, localisateur: sansPosition()));
      expect(e.coffre.valeur, isNotNull);
      await t.tap(find.byKey(const Key('rh_mobile_deconnexion')));
      await t.pumpAndSettle();
      expect(e.coffre.valeur, isNull);
      expect(find.byKey(const Key('rh_mobile_mdp')), findsOneWidget);
      expect(find.byKey(const Key('rh_arrivee')), findsNothing);
    });

    testWidgets('rien n\'est journalisé : ni QR, ni position, ni réponse du serveur', (t) async {
      tailleTelephone(t);
      final e = connecte();
      e.transport.routes['POST pointages'] =
          (_) => (status: 200, body: {'success': true, 'sens': 'ENTREE', 'heure': '08:02', 'message': 'Entrée enregistrée à 08:02.', 'secret': 'REPONSE-COMPLETE'});
      final journal = <String>[];
      final ancien = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => journal.add('$m');
      try {
        await runZoned(
          () async {
            await pump(
                t,
                MobilePointageScreen(
                  rh: e.pr,
                  presentation: ListPresentation.dashboard,
                  scanner: (_) async => 'PRESTIGE-POINTAGE:QRSECRET1',
                  localisateur: FakeLocalisateur(const ResultatPosition.ok(PositionPointage(5.987654, -4.123456, 9))),
                ));
            await t.tap(find.byKey(const Key('rh_arrivee')));
            await t.pumpAndSettle();
          },
          zoneSpecification: ZoneSpecification(print: (_, __, ___, String m) => journal.add(m)),
        );
      } finally {
        debugPrint = ancien;
      }
      expect(e.transport.corpsDe('POST', 'pointages').single!['latitude'], 5.987654); // bien envoyé…
      final tout = journal.join('\n');
      for (final secret in ['QRSECRET1', '5.987654', '-4.123456', 'REPONSE-COMPLETE']) {
        expect(tout, isNot(contains(secret)), reason: '… mais jamais journalisé');
      }
      await e.journal.idle;
      expect(jsonEncode((await e.journal.lire()).map((j) => j.action).toList()), isNot(contains('QRSECRET1')));
    });
  });

  // =========================================================================
  // Intégration (serveur de test) : sautée si le serveur est injoignable. Aucune donnée créée.
  // =========================================================================
  group('Voie A — intégration serveur de test', () {
    final url = Platform.environment['PRESTIGE_TEST_URL'] ?? 'http://localhost:8080/prestige/api/v1';
    test('connexion avec un mauvais mot de passe → message du serveur, aucun jeton gardé', () => HttpOverrides.runWithHttpOverrides(() async {
          final coffre = CoffreJetonMemoire();
          final api = MobileApi(
            transport: DioTransportMobile(() => url),
            coffre: coffre,
            appareil: () => 'test-integration-mauvais-mdp',
            nomAppareil: () => 'Test d\'intégration (aucun enregistrement)',
          );
          final sonde = await api.sonder();
          if (sonde == null) {
            markTestSkipped('Serveur de test injoignable : $url');
            return;
          }
          if (!sonde.existe || !sonde.actif) {
            markTestSkipped('API des téléphones absente ou désactivée sur $url');
            return;
          }
          final login = Platform.environment['PRESTIGE_TEST_LOGIN'] ?? 'admin';
          final r = await api.connexion(login, 'mauvais-mot-de-passe-${DateTime.now().microsecondsSinceEpoch}');
          expect(r.ok, isFalse);
          expect(r.refus, isNotNull);
          expect(r.refus!.trim(), isNotEmpty);
          expect(r.refus, isNot(startsWith('Réponse illisible')), reason: 'le serveur doit répondre en JSON avec son message');
          expect(coffre.valeur, isNull);
          expect(api.session, isNull);
        }, _RealHttp()), timeout: const Timeout(Duration(minutes: 1)));
  });

  // =========================================================================
  // Voie B : logique
  // =========================================================================
  group('Voie B — logique', () {
    Future<Env> pret() async {
      final e = Env();
      await e.pr.verifierAcces();
      expect(await e.pr.rafraichirEmployes(), isNull);
      return e;
    }

    test('badge → employé, sens auto (présence du serveur), anti double lecture < 2 min, motif du terminal', () async {
      final e = await pret();
      e.rh.pointagesJour = [
        {'id': 'p1', 'employeId': 'E1', 'horodatage': '2026-10-12 07:58', 'sens': 'ENTREE', 'source': 'POINTEUSE'},
      ];
      await e.pr.presence(e.now);
      final l = e.pr.lire('pv12ab34') as BadgeAConfirmer;
      expect(l.employe.prenomAffiche, 'Awa');
      expect(l.sens, SensPointage.sortie);
      final r = await e.pr.enregistrer(l, l.sens);
      expect(r.issue, IssueBadge.enregistre);
      // 4.3.0 (demande 31) : + identifiant du terminal (celui du pointage, ignoré par un ancien serveur).
      expect(e.rh.posts.single, {'id': r.pointage.id, 'employeId': 'E1', 'jour': '2026-10-12', 'heure': '08:02', 'sens': 'SORTIE', 'motif': 'Badge terminal Accueil'});
      e.now = e.now.add(const Duration(seconds: 70));
      expect(e.pr.lire('PV12AB34'), isA<BadgeIgnore>());
      e.now = e.now.add(const Duration(minutes: 2));
      final l2 = e.pr.lire('PV12AB34') as BadgeAConfirmer;
      expect(l2.sens, SensPointage.entree);
      expect(e.pr.lire('INCONNU'), isA<BadgeInconnu>());
    });

    test('doublon du serveur (même minute) → « déjà enregistré », idempotent', () async {
      final e = await pret();
      final l = e.pr.lire('PV12AB34') as BadgeAConfirmer;
      await e.pr.enregistrer(l, SensPointage.entree);
      final r = await e.pr.enregistrer(l, SensPointage.entree);
      expect(r.issue, IssueBadge.dejaEnregistre);
      expect(r.accepte, isTrue);
      await e.journal.idle;
      final j = await e.journal.lire();
      expect(j.where((x) => x.resultat == ResultatJournal.dejaApplique), hasLength(1));
    });

    test('hors ligne : file persistante (heure de lecture), envoi au retour, refus → anomalie commune, doublon → appliqué', () async {
      final e = await pret();
      e.horsLigne = true;
      final a = e.pr.lire('PV12AB34') as BadgeAConfirmer;
      final r1 = await e.pr.enregistrer(a, a.sens);
      expect(r1.issue, IssueBadge.enFile);
      e.now = DateTime(2026, 10, 12, 8, 3);
      final b = e.pr.lire('04a1b2c3') as BadgeAConfirmer;
      await e.pr.enregistrer(b, b.sens);
      e.now = DateTime(2026, 10, 12, 8, 3, 30);
      final c = e.pr.lire('M01');
      expect(c, isA<BadgeIgnore>()); // Awa relue < 2 min
      expect(e.pr.enAttente, 2);
      expect(e.rh.posts, isEmpty);
      // la file survit : même magasin relu
      final relu = await e.pr.store.pointages();
      expect(relu.map((p) => p.heure), ['08:02', '08:03']);

      e.horsLigne = false;
      e.rh.posts.clear();
      await e.rh.post('/rh/pointages', {'employeId': 'E1', 'jour': '2026-10-12', 'heure': '08:02'}); // déjà saisi autrement
      e.rh.posts.clear();
      final bilan = await e.pr.envoyer();
      expect(bilan.envoyes, 1);
      expect(bilan.dejaAppliques, 1);
      expect(e.rh.posts.map((p) => p['heure']), ['08:02', '08:03']);
      expect(e.pr.enAttente, 0);

      e.horsLigne = true;
      e.now = DateTime(2026, 10, 12, 9, 0);
      final d = e.pr.lire('PV12AB34') as BadgeAConfirmer;
      await e.pr.enregistrer(d, d.sens);
      e.horsLigne = false;
      e.rh.refus = 'Un pointage ne peut pas être dans le futur.';
      final b2 = await e.pr.envoyer();
      expect(b2.refuses, 1);
      expect(e.pr.anomaliesList.single.motif, 'Un pointage ne peut pas être dans le futur.');
      await e.pr.setTraitee(e.pr.anomaliesList.single.id, true);
      expect(e.pr.anomaliesNonTraitees, 0);
    });

    test('accès : droit absent → refusé (message du serveur), 404 → absent ; extension de la copie sans erreur', () async {
      final e = Env();
      e.rh.droits = {'success': false, 'msg': 'Vous n\'avez pas accès aux ressources humaines.', 'message': 'Vous n\'avez pas accès aux ressources humaines.'};
      expect(await e.pr.verifierAcces(), AccesRh.refuse);
      expect(e.pr.accesMessage, contains('pas accès'));
      e.rh.droitsStatus = 404;
      expect(await e.pr.verifierAcces(), AccesRh.absent);
      // copie hors ligne : refus ou 404 ne font jamais échouer la mise à jour du catalogue
      await e.pr.sync((p, q) async => {'success': false, 'msg': 'Vous n\'avez pas accès'}, (_, __, ___) {});
      await e.pr.sync((p, q) async => throw Exception('404'), (_, __, ___) {});
      expect(e.pr.employes, isEmpty);
      await e.pr.sync((p, q) async => {'success': true, 'data': e.rh.employes}, (_, __, ___) {});
      expect(e.pr.employes, hasLength(2));
    });

    test('hors ligne : terminal autorisé seulement s\'il a déjà été ouvert en ligne (copie des employés)', () async {
      final e = Env();
      e.horsLigne = true;
      expect(await e.pr.verifierAcces(), AccesRh.inconnu);
      e.horsLigne = false;
      await e.pr.verifierAcces();
      await e.pr.rafraichirEmployes();
      e.horsLigne = true;
      expect(await e.pr.verifierAcces(), AccesRh.autorise);
    });
  });

  // =========================================================================
  // Identification : capacités, empreinte, NFC
  // =========================================================================
  group('Identification', () {
    test('capacités : ordre empreinte, scan, NFC, clavier ; SDK absent → scan / NFC / clavier', () async {
      final avec = IdentificationEmploye(empreinte: FakeEmpreinte(), nfc: FakeNfc(), coffre: CoffreEmpreintesMemoire());
      expect((await avec.detecter()).ordre,
          [MoyenIdentification.empreinte, MoyenIdentification.scan, MoyenIdentification.nfc, MoyenIdentification.clavier]);
      final sans = IdentificationEmploye(empreinte: const AucuneEmpreinte(), nfc: FakeNfc(NfcAvailability.absent), coffre: CoffreEmpreintesMemoire());
      expect((await sans.detecter()).ordre, [MoyenIdentification.scan, MoyenIdentification.clavier]);
    });

    test('empreinte : identification 1:N parmi les actifs ; suppression des employés devenus inactifs ; rien envoyé', () async {
      final e = Env();
      e.empreinte.present = true;
      await e.pr.verifierAcces();
      await e.pr.rafraichirEmployes();
      await e.identification.enregistrer(EmpreintesEmploye(employeId: 'E1', modeles: [Uint8List.fromList([1])], consentementLe: h0802));
      await e.identification.enregistrer(EmpreintesEmploye(employeId: 'E2', modeles: [Uint8List.fromList([2])], consentementLe: h0802));
      e.empreinte.reconnu = 1;
      expect((await e.identification.parEmpreinte(e.pr.employes))?.id, 'E2');
      e.empreinte.reconnu = null;
      expect(await e.identification.parEmpreinte(e.pr.employes), isNull);
      // Koffi devient inactif : absent de la liste des actifs → ses empreintes sont supprimées du terminal
      e.rh.employes = [e.rh.employes.first];
      await e.pr.rafraichirEmployes();
      expect(e.coffreEmpreintes.donnees.keys, ['E1']);
      expect(e.rh.posts, isEmpty);
      expect(jsonEncode(e.rh.posts), isNot(contains('modeles')));
    });
  });

  // =========================================================================
  // Écrans de la voie B
  // =========================================================================
  group('Terminal (écran)', () {
    Future<Env> pret() async {
      final e = Env();
      await e.pr.verifierAcces();
      await e.pr.rafraichirEmployes();
      return e;
    }

    Widget terminal(Env e, {Future<String?> Function(BuildContext)? camera}) => TerminalPointageScreen(
          rh: e.pr,
          presentation: ListPresentation.dashboard,
          camera: camera,
          identification: e.identification,
          rafraichirAuDemarrage: false,
        );

    Future<void> fin(WidgetTester t) async {
      await t.pump(const Duration(seconds: 5));
      await t.pumpWidget(const SizedBox());
    }

    testWidgets('lecteur clavier (saisie rapide + Entrée) → « Bonjour Awa — ENTRÉE 08:02 », enregistré après 3 s', (t) async {
      tailleTelephone(t);
      final e = await pret();
      await pump(t, terminal(e));
      expect(t.widget<TextField>(find.byKey(const Key('rh_badge_champ'))).focusNode!.hasFocus, isTrue);
      await t.enterText(find.byKey(const Key('rh_badge_champ')), 'pv12ab34');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(find.text('Bonjour Awa'), findsOneWidget);
      expect(find.text('ENTRÉE 08:02'), findsOneWidget);
      expect(e.rh.posts, isEmpty);
      await t.pump(const Duration(seconds: 3));
      await t.pump();
      expect(e.rh.posts.single['sens'], 'ENTREE');
      expect(find.text('Bonjour Awa — ENTRÉE 08:02 ✓'), findsWidgets);
      expect(t.takeException(), isNull);
      await fin(t);
    });

    testWidgets('correction du sens sur l\'écran de confirmation ; même badge relu < 2 min ignoré', (t) async {
      tailleTelephone(t);
      final e = await pret();
      await pump(t, terminal(e));
      await t.enterText(find.byKey(const Key('rh_badge_champ')), 'PV12AB34');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      await t.tap(find.byKey(const Key('rh_corriger')));
      await t.pump();
      expect(find.text('SORTIE 08:02'), findsOneWidget);
      await t.tap(find.byKey(const Key('rh_valider')));
      await t.pump();
      await t.pump();
      expect(e.rh.posts.single['sens'], 'SORTIE');
      await t.pump(const Duration(seconds: 5));
      e.now = e.now.add(const Duration(seconds: 30));
      await t.enterText(find.byKey(const Key('rh_badge_champ')), 'PV12AB34');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(find.text('Déjà pointé'), findsOneWidget);
      expect(e.rh.posts, hasLength(1));
      await fin(t);
    });

    testWidgets('scan par la caméra et badge NFC (UID hexadécimal) ; badge inconnu', (t) async {
      tailleTelephone(t);
      final e = await pret();
      e.nfc.etat = NfcAvailability.ready;
      await pump(t, terminal(e, camera: (_) async => 'pv12ab34'));
      await t.tap(find.byKey(const Key('rh_badge_camera')));
      await t.pump();
      await t.pump();
      expect(find.text('Bonjour Awa'), findsOneWidget);
      await t.tap(find.byKey(const Key('rh_annuler')));
      await t.pump();
      e.nfc.approcher('04:a1:b2:c3');
      await t.pump();
      expect(find.text('Bonjour Koffi'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await t.pump();
      expect(e.rh.posts.single['employeId'], 'E2');
      expect(e.rh.posts.single['motif'], 'Badge terminal Accueil');
      await t.pump(const Duration(seconds: 5));
      await t.enterText(find.byKey(const Key('rh_badge_champ')), 'BIDON');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(find.text('Badge non reconnu'), findsWidgets);
      await fin(t);
    });

    testWidgets('empreinte (fournisseur factice) → pointage, motif « Empreinte terminal » ; SDK absent → repli badge', (t) async {
      tailleTelephone(t);
      final e = await pret();
      e.empreinte.present = true;
      e.empreinte.reconnu = 0;
      await e.identification.enregistrer(EmpreintesEmploye(employeId: 'E1', modeles: [Uint8List.fromList([9])], consentementLe: h0802));
      await pump(t, terminal(e));
      await t.pump();
      await t.tap(find.byKey(const Key('rh_empreinte')));
      await t.pump();
      await t.pump();
      expect(find.text('Bonjour Awa'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await t.pump();
      expect(e.rh.posts.single['motif'], 'Empreinte terminal Accueil');
      expect(jsonEncode(e.rh.posts), isNot(contains('modeles')));
      await fin(t);

      final e2 = await pret();
      await pump(t, terminal(e2)); // SDK absent
      await t.pump();
      expect(find.byKey(const Key('rh_empreinte')), findsNothing);
      expect(find.byKey(const Key('rh_badge_champ')), findsOneWidget);
      await fin(t);
    });

    testWidgets('hors ligne : mis en file ; retour en ligne → confirmation (liste décochable) puis envoi', (t) async {
      tailleTelephone(t);
      final e = await pret();
      e.horsLigne = true;
      await pump(t, terminal(e));
      await t.enterText(find.byKey(const Key('rh_badge_champ')), 'PV12AB34');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      await t.tap(find.byKey(const Key('rh_valider')));
      await t.pump();
      await t.pump();
      expect(find.textContaining('Hors ligne : pointage gardé'), findsWidgets);
      e.now = DateTime(2026, 10, 12, 8, 10);
      await t.pump(const Duration(seconds: 5));
      await t.enterText(find.byKey(const Key('rh_badge_champ')), '04A1B2C3');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      await t.tap(find.byKey(const Key('rh_valider')));
      await t.pump();
      await t.pump(const Duration(seconds: 5));
      expect(e.pr.enAttente, 2);
      await fin(t);

      e.horsLigne = false;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => ElevatedButton(onPressed: () => confirmerEnvoiPointagesRh(c, e.pr), child: const Text('go'))))));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rh_confirmation_envoi')), findsOneWidget);
      final koffi = e.pr.aEnvoyer.firstWhere((p) => p.employeId == 'E2');
      await t.tap(find.byKey(Key('rh_coche_${koffi.id}')));
      await t.pump();
      expect(find.textContaining('décoché(s)'), findsOneWidget);
      await t.tap(find.byKey(const Key('rh_envoyer_selection')));
      await t.pumpAndSettle();
      expect(e.rh.posts.map((p) => p['employeId']), ['E1']);
      expect(e.pr.file.firstWhere((p) => p.id == koffi.id).statut, StatutPointageBadge.exclu);
      await t.pump(const Duration(seconds: 5));
    });
  });

  group('Écrans', () {
    testWidgets('anomalies : refus d\'un pointage du terminal dans le rapport commun', (t) async {
      tailleTelephone(t);
      final e = Env();
      await e.pr.verifierAcces();
      await e.pr.rafraichirEmployes();
      e.horsLigne = true;
      final l = e.pr.lire('PV12AB34') as BadgeAConfirmer;
      await e.pr.enregistrer(l, l.sens);
      e.horsLigne = false;
      e.rh.refus = 'Employé introuvable.';
      await e.pr.envoyer();
      final AnomalieSourceListe source = e.pr;
      await t.pumpWidget(MaterialApp(home: AnomaliesHorsLigneScreen(autres: [source])));
      await t.pumpAndSettle();
      expect(find.text('POINTAGES RH (BADGE)'), findsOneWidget);
      expect(find.text('Employé introuvable.'), findsOneWidget);
    });

    testWidgets('entrée « Pointage présence » : droits absents → terminal et présences désactivés et expliqués ; 404 mobile expliqué', (t) async {
      tailleTelephone(t);
      final e = Env();
      e.rh.droits = {'success': false, 'message': 'Vous n\'avez pas accès aux ressources humaines.'};
      await pump(t, RhPointageScreen(rh: e.pr, presentation: ListPresentation.dashboard));
      await t.pumpAndSettle();
      expect(find.textContaining('n\'existe pas sur cette version'), findsOneWidget);
      expect(find.textContaining('P_SM_RH'), findsWidgets);
      expect(t.widget<InkWell>(find.byKey(const Key('rh_voie_b'))).onTap, isNull);
      // ni administrateur ni droit RH : capture seule, le suivi (présences) n'est pas proposé du tout
      expect(find.byKey(const Key('rh_presences')), findsNothing);
      expect(t.widget<InkWell>(find.byKey(const Key('rh_voie_a'))).onTap, isNull);
      expect(t.takeException(), isNull);
    });

    testWidgets('entrée « Pointage présence » : tout disponible ; module mobile inactif → message', (t) async {
      tailleTablette(t);
      final e = Env();
      e.transport.routes['POST connexion'] = (_) => (status: 200, body: {'success': false, 'message': 'Identifiant, mot de passe et appareil obligatoires.'});
      await pump(t, RhPointageScreen(rh: e.pr, presentation: ListPresentation.guided));
      await t.pumpAndSettle();
      expect(t.widget<InkWell>(find.byKey(const Key('rh_voie_a'))).onTap, isNotNull);
      expect(t.widget<InkWell>(find.byKey(const Key('rh_voie_b'))).onTap, isNotNull);
      expect(t.widget<InkWell>(find.byKey(const Key('rh_presences'))).onTap, isNotNull);
      e.transport.routes['POST connexion'] = (_) => (status: 200, body: {'success': false, 'message': 'La connexion des téléphones est désactivée par l\'officine.'});
      await t.tap(find.byKey(const Key('rh_verifier')));
      await t.pumpAndSettle();
      expect(find.text(messageModuleMobileInactif), findsOneWidget);
      expect(t.takeException(), isNull);
      // libellés : « Pointage présence » › « Mon pointage » / « Terminal de pointage »
      expect(find.text('Pointage présence'), findsOneWidget);
      expect(find.text('Mon pointage'), findsOneWidget);
      expect(find.text('Terminal de pointage'), findsOneWidget);
    });

    test('menu « Pointage présence » : même identifiant pointage_rh ; Pointage BL inchangé ; Pointage local explicite', () {
      final m = accueilMenuById['pointage_rh']!;
      expect(m.label, 'Pointage présence');
      expect(m.icon, Icons.how_to_reg);
      expect(accueilMenuById['bl_control']!.label, 'Pointage BL Stock');
      expect(accueilMenuById['bl_control']!.short, 'Pointage BL');
      expect(accueilMenuById['bl_control']!.icon, Icons.checklist);
      expect(accueilMenuById['empreinte']!.label, 'Pointage local (non envoyé à Prestige)');
      expect(accueilMenuById['empreinte']!.short, 'Pointage local');
      expect(accueilMenuById['empreinte']!.icon, Icons.fingerprint);
    });

    testWidgets('enrôlement : PIN admin, consentement obligatoire, 3 captures, test, suppression ; rien envoyé', (t) async {
      tailleTelephone(t);
      final e = Env();
      e.empreinte.present = true;
      await e.pr.verifierAcces();
      await e.pr.rafraichirEmployes();
      await t.pumpWidget(MaterialApp(home: EmpreintesScreen(rh: e.pr, identification: e.identification, codeAdmin: (_) async => true)));
      await t.pumpAndSettle();
      expect(find.textContaining('ARTCI'), findsOneWidget);
      await t.tap(find.byKey(const Key('rh_enroler_E1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rh_consentement')), findsOneWidget);
      expect(t.widget<ElevatedButton>(find.byKey(const Key('rh_consentement_ok'))).onPressed, isNull);
      await t.tap(find.text('Refus / annuler'));
      await t.pumpAndSettle();
      expect(e.empreinte.captures, 0);
      expect(e.coffreEmpreintes.donnees, isEmpty);
      await t.tap(find.byKey(const Key('rh_enroler_E1')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('rh_consentement_coche')));
      await t.pump();
      await t.tap(find.byKey(const Key('rh_consentement_coche')));
      await t.pump();
      await t.tap(find.byKey(const Key('rh_consentement_ok')));
      await t.pumpAndSettle();
      expect(e.empreinte.captures, 3);
      expect(e.empreinte.derniersModeles, hasLength(3));
      expect(e.coffreEmpreintes.donnees['E1']!.modeles, hasLength(3));
      expect(find.textContaining('enregistrées et reconnues'), findsOneWidget);
      expect(e.rh.posts, isEmpty);
      await e.journal.idle;
      expect((await e.journal.lire()).map((j) => j.action).join(), isNot(contains('240')));
      await t.tap(find.byKey(const Key('rh_supprimer_E1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rh_supprimer_ok')));
      await t.pumpAndSettle();
      expect(e.coffreEmpreintes.donnees, isEmpty);
    });

    testWidgets('enrôlement : test de reconnaissance raté → rien enregistré', (t) async {
      tailleTelephone(t);
      final e = Env();
      e.empreinte.present = true;
      e.empreinte.reconnu = null;
      await e.pr.verifierAcces();
      await e.pr.rafraichirEmployes();
      await t.pumpWidget(MaterialApp(home: EmpreintesScreen(rh: e.pr, identification: e.identification, codeAdmin: (_) async => true)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rh_enroler_E2')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('rh_consentement_coche')));
      await t.pump();
      await t.tap(find.byKey(const Key('rh_consentement_coche')));
      await t.pump();
      await t.tap(find.byKey(const Key('rh_consentement_ok')));
      await t.pumpAndSettle();
      expect(find.textContaining('Test échoué'), findsOneWidget);
      expect(e.coffreEmpreintes.donnees, isEmpty);
    });

    for (final tablette in [false, true]) {
      testWidgets('présences du jour (${tablette ? 'tablette' : '360 px'}) : entrée, sortie, retard, anomalies', (t) async {
        tablette ? tailleTablette(t) : tailleTelephone(t);
        final e = Env();
        e.rh.presences = [
          {'employeId': 'E1', 'employe': 'KOUASSI Awa', 'matricule': 'M01', 'entree': '08:12', 'sortie': '18:30', 'retard': 12, 'heuresSup': 78, 'minutesPresence': 558, 'anomalies': 'DOUBLON', 'pointages': '08:12↑ 18:30↓', 'prevu': '08:00-17:00'},
          {'employeId': 'E2', 'employe': 'YAO Koffi', 'matricule': 'M02', 'anomalies': 'ABSENT', 'prevu': '08:00-17:00'},
        ];
        for (final style in ListPresentation.values) {
          await pump(t, PresencesScreen(rh: e.pr, presentation: style));
          await t.pumpAndSettle();
          expect(find.text('KOUASSI Awa'), findsOneWidget);
          expect(find.textContaining('Retard 12 min'), findsOneWidget);
          expect(find.textContaining('doublon'), findsOneWidget);
          expect(find.textContaining('absent (non justifié)'), findsOneWidget);
          expect(t.takeException(), isNull);
        }
      });

      testWidgets('mise en page ${tablette ? 'tablette' : '360 px'} : entrée, terminal, mon pointage (A, B, C)', (t) async {
        tablette ? tailleTablette(t) : tailleTelephone(t);
        final e = Env();
        await e.pr.verifierAcces();
        await e.pr.rafraichirEmployes();
        e.coffre.valeur = jsonEncode({...moiJson(gps: true), 'jeton': 'J1', 'expiration': '2026-10-12T20:00:00Z'});
        e.transport.routes['GET moi'] = (_) => (status: 200, body: moiJson(gps: true));
        e.transport.routes['GET pointages'] = (_) => (status: 200, body: {'success': true, 'data': [{'heure': '07:58', 'sens': 'ENTREE', 'source': 'POINTEUSE'}]});
        for (final style in ListPresentation.values) {
          await pump(t, RhPointageScreen(rh: e.pr, presentation: style));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          await pump(t, TerminalPointageScreen(rh: e.pr, presentation: style, identification: e.identification, rafraichirAuDemarrage: false));
          await t.pump(const Duration(milliseconds: 100));
          expect(t.takeException(), isNull);
          await t.enterText(find.byKey(const Key('rh_badge_champ')), 'M02');
          await t.testTextInput.receiveAction(TextInputAction.done);
          await t.pump();
          expect(find.text('Bonjour Koffi'), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.tap(find.byKey(const Key('rh_annuler')));
          await t.pump();
          await pump(t, MobilePointageScreen(rh: e.pr, presentation: style, localisateur: sansPosition()));
          await t.pumpAndSettle();
          // deux gros boutons côte à côte, sans débordement ; dernier pointage ENTREE → « Départ » suggéré
          final a = t.getRect(find.byKey(const Key('rh_arrivee')));
          final d = t.getRect(find.byKey(const Key('rh_depart')));
          expect(a.top, d.top);
          expect(a.right, lessThan(d.left));
          expect(d.right, lessThanOrEqualTo(tablette ? 1280 : 360));
          expect(find.text('Arrivée'), findsOneWidget);
          expect(find.text('Départ'), findsOneWidget);
          expect(find.byKey(const Key('rh_suggere_depart')), findsOneWidget);
          expect(find.text('KOUASSI Awa · M01'), findsOneWidget);
          expect(t.takeException(), isNull);
        }
        await t.pumpWidget(const SizedBox());
      });
    }
  });

  // =========================================================================
  // « Vous avez déjà pointé » : relecture < 2 min, doublon du serveur, voie A
  // =========================================================================
  group('Déjà pointé', () {
    Future<Env> pret() async {
      final e = Env();
      await e.pr.verifierAcces();
      await e.pr.rafraichirEmployes();
      return e;
    }

    Color? fondResultat(WidgetTester t) => t.widget<Container>(find.byKey(const Key('rh_resultat'))).color;

    test('règles : refus « moins de deux minutes », heure HH:mm, messages', () {
      expect(estRefusDeuxMinutes('Pointage refusé : moins de deux minutes depuis le dernier pointage.'), isTrue);
      expect(estRefusDeuxMinutes('Dernier pointage il y a moins de 2 min.'), isTrue);
      expect(estRefusDeuxMinutes('Code de pointage invalide ou expiré.'), isFalse);
      expect(estRefusDeuxMinutes('Un pointage existe déjà à cette heure.'), isFalse);
      expect(heureMinute('2026-10-12 8:01:30'), '08:01');
      expect(heureMinute('08:02'), '08:02');
      expect(heureMinute(''), '');
      expect(messageDejaPointe('Awa', SensPointage.entree, '08:02'), 'Awa, vous avez déjà pointé (ENTRÉE à 08:02)');
      expect(messageDejaPointe('Awa', null, '08:02'), 'Awa, vous avez déjà pointé (à 08:02)');
      expect(messageDejaPointeMobile('08:01'), 'Vous avez déjà pointé à 08:01');
      expect(messageDejaPointeMobile(''), 'Vous avez déjà pointé.');
    });

    test('relecture < 2 min : « Awa, vous avez déjà pointé (ENTRÉE à 08:02) », sens et heure du pointage, rien envoyé', () async {
      final e = await pret();
      final l = e.pr.lire('PV12AB34') as BadgeAConfirmer;
      expect((await e.pr.enregistrer(l, SensPointage.entree)).issue, IssueBadge.enregistre);
      e.now = e.now.add(const Duration(seconds: 50));
      final r = e.pr.lire('pv12ab34');
      expect(r, isA<BadgeIgnore>());
      final b = r as BadgeIgnore;
      expect(b.message, 'Awa, vous avez déjà pointé (ENTRÉE à 08:02)');
      expect(b.sens, SensPointage.entree);
      expect(b.at, h0802);
      // sens corrigé à la confirmation : c'est lui qui est rappelé
      final k = e.pr.lire('M02') as BadgeAConfirmer;
      await e.pr.enregistrer(k, SensPointage.sortie);
      expect((e.pr.lire('M02') as BadgeIgnore).message, 'Koffi, vous avez déjà pointé (SORTIE à 08:02)');
      expect(e.rh.posts, hasLength(2));
      // empreinte : même règle
      expect(e.pr.lireEmploye(e.pr.employes.first, moyen: MoyenIdentification.empreinte), isA<BadgeIgnore>());
      // au-delà de 2 minutes : nouvelle lecture normale
      e.now = h0802.add(const Duration(minutes: 2, seconds: 1));
      expect(e.pr.lire('PV12AB34'), isA<BadgeAConfirmer>());
    });

    test('doublon du serveur (« Un pointage existe déjà à cette heure ») : même message, accepté, sans nouvel envoi', () async {
      final e = await pret();
      e.rh.refus = 'Un pointage existe déjà à cette heure pour cet employé.';
      final l = e.pr.lire('PV12AB34') as BadgeAConfirmer;
      final r = await e.pr.enregistrer(l, SensPointage.entree);
      expect(r.issue, IssueBadge.dejaEnregistre);
      expect(r.accepte, isTrue);
      expect(r.message, 'Awa, vous avez déjà pointé (ENTRÉE à 08:02)');
      expect(e.rh.posts, hasLength(1));
      expect(e.pr.enAttente, 0);
      // relu tout de suite : pas de nouvel envoi
      expect(e.pr.lire('PV12AB34'), isA<BadgeIgnore>());
      expect(e.rh.posts, hasLength(1));
    });

    testWidgets('terminal : relecture < 2 min → écran orange « Awa, vous avez déjà pointé (ENTRÉE à 08:02) », rien envoyé', (t) async {
      tailleTelephone(t);
      final e = await pret();
      await pump(t, TerminalPointageScreen(rh: e.pr, presentation: ListPresentation.dashboard, identification: e.identification, rafraichirAuDemarrage: false));
      await t.enterText(find.byKey(const Key('rh_badge_champ')), 'PV12AB34');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      await t.tap(find.byKey(const Key('rh_valider')));
      await t.pump();
      await t.pump();
      expect(e.rh.posts, hasLength(1));
      expect(fondResultat(t), const Color(0xFFDCF5E7));
      await t.pump(const Duration(seconds: 5));
      e.now = e.now.add(const Duration(seconds: 40));
      await t.enterText(find.byKey(const Key('rh_badge_champ')), 'PV12AB34');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(find.text('Awa, vous avez déjà pointé (ENTRÉE à 08:02)'), findsOneWidget);
      expect(find.text('Déjà pointé'), findsOneWidget);
      expect(fondResultat(t), const Color(0xFFFFF1D6));
      expect(find.byKey(const Key('rh_confirmation')), findsNothing);
      await t.pump(const Duration(milliseconds: 300)); // second signal (double clic)
      expect(e.rh.posts, hasLength(1));
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 5));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('terminal : doublon du serveur → même écran orange (pas « Bonjour … ✓ »)', (t) async {
      tailleTelephone(t);
      final e = await pret();
      e.rh.refus = 'Un pointage existe déjà à cette heure pour cet employé.';
      await pump(t, TerminalPointageScreen(rh: e.pr, presentation: ListPresentation.dashboard, identification: e.identification, rafraichirAuDemarrage: false));
      await t.enterText(find.byKey(const Key('rh_badge_champ')), 'PV12AB34');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      await t.tap(find.byKey(const Key('rh_valider')));
      await t.pump();
      await t.pump();
      expect(find.text('Awa, vous avez déjà pointé (ENTRÉE à 08:02)'), findsWidgets);
      expect(fondResultat(t), const Color(0xFFFFF1D6));
      expect(find.textContaining('Bonjour Awa'), findsNothing);
      expect(e.rh.posts, hasLength(1));
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 5));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('voie A : refus « moins de deux minutes » → « Vous avez déjà pointé à HH:mm » (dernier pointage connu), orange', (t) async {
      tailleTelephone(t);
      final e = Env();
      e.coffre.valeur = jsonEncode({...moiJson(qr: false), 'jeton': 'J1', 'expiration': '2026-10-12T20:00:00Z'});
      e.transport.routes['GET moi'] = (_) => (status: 200, body: moiJson(qr: false));
      var hist = <Map<String, dynamic>>[];
      e.transport.routes['GET pointages'] = (_) => (status: 200, body: {'success': true, 'data': hist});
      e.transport.routes['POST pointages'] = (_) {
        // pointage fait depuis un autre écran juste avant : l'historique local n'est pas encore à jour
        hist = [{'heure': '2026-10-12 08:01:10', 'sens': 'ENTREE', 'source': 'MOBILE'}];
        return (status: 200, body: {'success': false, 'message': 'Pointage refusé : moins de deux minutes depuis le dernier pointage.'});
      };
      await pump(t, MobilePointageScreen(rh: e.pr, presentation: ListPresentation.dashboard, localisateur: sansPosition()));
      await t.tap(find.byKey(const Key('rh_arrivee')));
      await t.pumpAndSettle();
      expect(find.text('Vous avez déjà pointé à 08:01'), findsOneWidget);
      expect(find.textContaining('moins de deux minutes'), findsNothing);
      final deco = t.widget<Container>(find.byKey(const Key('rh_mobile_message'))).decoration as BoxDecoration;
      expect(deco.color, const Color(0xFFFFF1D6));
      expect(e.transport.corpsDe('POST', 'pointages'), hasLength(1));
      // autre refus : toujours affiché tel quel (rouge)
      e.transport.routes['POST pointages'] = (_) => (status: 200, body: {'success': false, 'message': 'Hors de la zone de l\'officine.'});
      await t.tap(find.byKey(const Key('rh_depart')));
      await t.pumpAndSettle();
      expect(find.text('Hors de la zone de l\'officine.'), findsOneWidget);
      final deco2 = t.widget<Container>(find.byKey(const Key('rh_mobile_message'))).decoration as BoxDecoration;
      expect(deco2.color, const Color(0xFFFDECEC));
      expect(t.takeException(), isNull);
    });
  });

  // =========================================================================
  // Retour client : « j'ai pointé mais je ne vois rien dans Prestige »
  // Capture seule pour l'employé, suivi réservé au gestionnaire, état de l'envoi toujours dit, pointage local
  // explicite et masqué par défaut, aucune perte (session expirée → file).
  // =========================================================================
  group('Capture seule et envoi à Prestige', () {
    Future<Env> pret() async {
      final e = Env();
      await e.pr.verifierAcces();
      await e.pr.rafraichirEmployes();
      return e;
    }

    test('gestionnaire = administrateur de l\'application OU droit RH (P_SM_RH) ; sinon capture seule', () {
      expect(estGestionnaireRh(admin: true, acces: AccesRh.refuse), isTrue);
      expect(estGestionnaireRh(admin: false, acces: AccesRh.autorise), isTrue);
      expect(estGestionnaireRh(admin: false, acces: AccesRh.refuse), isFalse);
      expect(estGestionnaireRh(admin: false, acces: AccesRh.absent), isFalse);
      expect(estGestionnaireRh(admin: false, acces: AccesRh.inconnu), isFalse);
    });

    testWidgets('employé (non gestionnaire) : « Mon pointage » et « Terminal » seulement, aucun écran d\'analyse', (t) async {
      tailleTelephone(t);
      final e = Env();
      await pump(t, RhPointageScreen(rh: e.pr, presentation: ListPresentation.guided, gestion: false));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rh_voie_a')), findsOneWidget);
      expect(find.byKey(const Key('rh_voie_b')), findsOneWidget);
      expect(find.byKey(const Key('rh_presences')), findsNothing);
      expect(find.text('Présences du jour'), findsNothing);
      expect(find.text('Suivre'), findsNothing);
      expect(find.byKey(const Key('rh_note_envoi')), findsOneWidget);
      expect(t.takeException(), isNull);

      // gestionnaire (droit RH) : le suivi est proposé
      await pump(t, RhPointageScreen(rh: e.pr, presentation: ListPresentation.guided));
      await t.pumpAndSettle();
      expect(t.widget<InkWell>(find.byKey(const Key('rh_presences'))).onTap, isNotNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('terminal : gestion des empreintes réservée au gestionnaire', (t) async {
      tailleTelephone(t);
      final e = await pret();
      e.empreinte.present = true;
      await pump(t, TerminalPointageScreen(rh: e.pr, presentation: ListPresentation.dashboard, identification: e.identification, rafraichirAuDemarrage: false, gestion: false));
      await t.pump();
      expect(find.byKey(const Key('rh_gerer_empreintes')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await pump(t, TerminalPointageScreen(rh: e.pr, presentation: ListPresentation.dashboard, identification: e.identification, rafraichirAuDemarrage: false, gestion: true));
      await t.pump();
      expect(find.byKey(const Key('rh_gerer_empreintes')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    Future<void> badger(WidgetTester t, String badge) async {
      await t.enterText(find.byKey(const Key('rh_badge_champ')), badge);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      await t.tap(find.byKey(const Key('rh_valider')));
      await t.pump();
      await t.pump();
    }

    Color? fond(WidgetTester t) => t.widget<Container>(find.byKey(const Key('rh_resultat'))).color;

    testWidgets('terminal : « Envoyé à Prestige ✓ », « En attente d\'envoi (hors ligne) », « Refusé par Prestige : … »', (t) async {
      tailleTelephone(t);
      final e = await pret();
      await pump(t, TerminalPointageScreen(rh: e.pr, presentation: ListPresentation.dashboard, identification: e.identification, rafraichirAuDemarrage: false));
      await badger(t, 'PV12AB34');
      expect(find.text(etatEnvoyePrestige), findsWidgets);
      expect(fond(t), const Color(0xFFDCF5E7));
      await t.pump(const Duration(seconds: 5));

      e.horsLigne = true;
      await badger(t, '04A1B2C3');
      expect(find.textContaining(etatEnAttenteEnvoi), findsWidgets);
      expect(find.descendant(of: find.byKey(const Key('rh_resultat')), matching: find.textContaining(etatEnvoyePrestige)), findsNothing,
          reason: 'un pointage gardé n\'est jamais présenté comme envoyé');
      expect(fond(t), const Color(0xFFFFF1D6));
      expect(e.pr.enAttente, 1);
      await t.pump(const Duration(seconds: 5));

      e.horsLigne = false;
      e.now = DateTime(2026, 10, 12, 8, 30);
      e.rh.refus = 'Un pointage ne peut pas être dans le futur.';
      await badger(t, 'PV12AB34');
      expect(find.text('$etatRefusPrestige : Un pointage ne peut pas être dans le futur.'), findsWidgets);
      expect(fond(t), const Color(0xFFFDECEC));
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 5));
      await t.pumpWidget(const SizedBox());
    });

    test('session Prestige expirée (401) : pointage GARDÉ en file (jamais refusé), envoi arrêté au 401 puis repris', () async {
      final e = await pret();
      e.rh.postStatus = 401;
      final l = e.pr.lire('PV12AB34') as BadgeAConfirmer;
      final r = await e.pr.enregistrer(l, SensPointage.entree);
      expect(r.issue, IssueBadge.enFile);
      expect(r.message, messageSessionExpireeFile('08:02'));
      expect(e.pr.enAttente, 1);
      expect(e.pr.anomaliesNonTraitees, 0);
      // toujours 401 : rien n'est marqué refusé, tout reste en attente
      final b = await e.pr.envoyer();
      expect(b.sessionExpiree, isTrue);
      expect(b.refuses, 0);
      expect(b.message, contains('session Prestige expirée'));
      expect(e.pr.enAttente, 1);
      // après reconnexion : envoyé
      e.rh.postStatus = null;
      final b2 = await e.pr.envoyer();
      expect(b2.envoyes, 1);
      expect(b2.message, startsWith('1 pointage(s) envoyé(s) à Prestige'));
      expect(e.pr.enAttente, 0);
      expect(e.rh.posts.single['heure'], '08:02');
    });

    test('badge inconnu en ligne : copie des employés relue (employé créé depuis l\'ouverture), au plus une fois par 30 s', () async {
      final e = await pret();
      final avant = e.rh.getsEmployes;
      e.rh.employes = [
        ...e.rh.employes,
        {'id': 'E3', 'matricule': 'M03', 'badge': 'NOUVEAU01', 'nom': 'TRAORE', 'prenoms': 'Fanta', 'statut': 'ACTIF'},
      ];
      final l = await e.pr.lireAvecRafraichissement('nouveau01');
      expect(l, isA<BadgeAConfirmer>());
      expect((l as BadgeAConfirmer).employe.id, 'E3');
      expect(e.rh.getsEmployes, avant + 1);
      expect(await e.pr.lireAvecRafraichissement('INCONNU'), isA<BadgeInconnu>());
      expect(e.rh.getsEmployes, avant + 1, reason: 'pas de nouvelle relecture avant 30 s');
      // hors ligne : aucune requête
      e.now = e.now.add(const Duration(minutes: 1));
      e.horsLigne = true;
      expect(await e.pr.lireAvecRafraichissement('AUTRE'), isA<BadgeInconnu>());
      expect(e.rh.getsEmployes, avant + 1);
    });

    Env connecte({String login = 'awa'}) {
      final e = Env();
      final moi = {...moiJson(qr: false), 'utilisateur': {'id': 'U1', 'login': login, 'nom': 'X'}};
      e.coffre.valeur = jsonEncode({...moi, 'jeton': 'J1', 'expiration': '2026-10-12T20:00:00Z'});
      e.transport.routes['GET moi'] = (_) => (status: 200, body: moi);
      e.transport.routes['GET pointages'] = (_) => (status: 200, body: {'success': true, 'data': []});
      return e;
    }

    testWidgets('mon pointage : « Envoyé à Prestige ✓ » sous le résultat ; refus → « Refusé par Prestige »', (t) async {
      tailleTelephone(t);
      final e = connecte();
      e.transport.routes['POST pointages'] = (_) => (status: 200, body: {'success': true, 'sens': 'ENTREE', 'heure': '08:02', 'message': 'Entrée enregistrée à 08:02.'});
      await pump(t, MobilePointageScreen(rh: e.pr, login: 'awa', presentation: ListPresentation.dashboard, localisateur: sansPosition()));
      expect(find.byKey(const Key('rh_mobile_autre_compte')), findsNothing);
      await t.tap(find.byKey(const Key('rh_arrivee')));
      await t.pumpAndSettle();
      expect(find.text('Entrée enregistrée à 08:02.'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('rh_mobile_etat_envoi'))).data, etatEnvoyePrestige);
      e.transport.routes['POST pointages'] = (_) => (status: 200, body: {'success': false, 'message': 'Le pointage par téléphone est désactivé par l\'officine.'});
      await t.tap(find.byKey(const Key('rh_depart')));
      await t.pumpAndSettle();
      expect(find.text('Le pointage par téléphone est désactivé par l\'officine.'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('rh_mobile_etat_envoi'))).data, startsWith(etatRefusPrestige));
      expect(t.takeException(), isNull);
    });

    testWidgets('mon pointage : téléphone connecté avec un AUTRE compte que l\'application → bandeau explicite', (t) async {
      tailleTelephone(t);
      final e = connecte(login: 'caissiere');
      await pump(t, MobilePointageScreen(rh: e.pr, login: 'admin', presentation: ListPresentation.dashboard, localisateur: sansPosition()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rh_mobile_autre_compte')), findsOneWidget);
      expect(find.textContaining('connecté au compte « caissiere » (KOUASSI Awa), pas à « admin »'), findsOneWidget);
      expect(find.byKey(const Key('rh_arrivee')), findsOneWidget, reason: 'information seulement : le pointage reste possible');
      expect(t.takeException(), isNull);
    });
  });

  group('Pointage local (non envoyé à Prestige)', () {
    test('menu masqué par défaut, réaffichable par un administrateur ; les menus masqués de l\'utilisateur sont gardés', () async {
      final s = SettingsProvider();
      await s.saveMenuConfig(const [], const ['depot']);
      expect(s.pointageLocalVisible, isFalse);
      expect(s.menusMasques, containsAll(['depot', 'empreinte']));
      expect(s.hiddenMenuIds, ['depot'], reason: 'le réglage ne touche pas aux menus masqués enregistrés');
      final familles = menusByFamille(s.menuOrder, s.menusMasques);
      expect(familles[MenuFamille.equipe]!.map((m) => m.id), ['pointage_rh']);
      await s.setPointageLocalVisible(true);
      expect(s.menusMasques, ['depot']);
      expect(menusByFamille(s.menuOrder, s.menusMasques)[MenuFamille.equipe]!.map((m) => m.id), ['empreinte', 'pointage_rh']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SettingsProvider.pointageLocalVisibleKey), isTrue);
      final relu = SettingsProvider();
      await relu.loadSettings();
      expect(relu.pointageLocalVisible, isTrue);
    });

    testWidgets('écran : titre « Pointage local », avertissement « non envoyé à Prestige », lien vers Pointage présence', (t) async {
      tailleTelephone(t);
      final repo = MemoryPointageRepository();
      await pump(t, PointageHomeScreen(repository: repo, detectCapability: () async => const DeviceCapability(mode: PointageMode.pinOrName), presentation: ListPresentation.dashboard));
      await t.pumpAndSettle();
      expect(find.text(titrePointageLocal), findsWidgets);
      expect(find.byKey(const Key('pointage_local_avertissement')), findsOneWidget);
      expect(find.textContaining('Non envoyé à Prestige'), findsOneWidget);
      expect(find.byKey(const Key('pointage_local_vers_presence')), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const Key('pointage_local_note')), 200, scrollable: find.byType(Scrollable).last);
      expect(find.textContaining(avertissementPointageLocal), findsOneWidget);
      expect(find.textContaining('synchronisation'), findsNothing);
      expect(t.takeException(), isNull);
    });

    test('export CSV : toutes les données locales, « Envoyé à Prestige : non », champs protégés', () {
      final emp = [const Employee(id: 'a', name: 'Awa; Kouassi', matricule: 'M01')];
      final recs = [
        PointageRecord(id: '2', employeeId: 'a', type: PointageType.depart, time: DateTime(2026, 10, 12, 17, 5), method: PointageMethod.pin),
        PointageRecord(id: '1', employeeId: 'a', type: PointageType.arrivee, time: DateTime(2026, 10, 12, 8, 2), method: PointageMethod.badge, device: 'SUNMI'),
        PointageRecord(id: '3', employeeId: 'x', type: PointageType.arrivee, time: DateTime(2026, 10, 13, 8, 0), method: PointageMethod.manual),
      ];
      final l = csvPointagesLocaux(emp, recs).trim().split('\n');
      expect(l.first, 'Date;Heure;Matricule;Employé;Type;Méthode;Appareil;Envoyé à Prestige');
      expect(l[1], '2026-10-12;08:02;M01;"Awa; Kouassi";Arrivée;Badge;SUNMI;non');
      expect(l[2], '2026-10-12;17:05;M01;"Awa; Kouassi";Départ;Nom + PIN;;non');
      expect(l[3], '2026-10-13;08:00;;x;Arrivée;Nom seul;;non', reason: 'employé supprimé : le pointage n\'est pas perdu');
    });

    testWidgets('rapport : export (presse-papiers) des pointages locaux', (t) async {
      tailleTelephone(t);
      final repo = MemoryPointageRepository();
      await repo.saveEmployee(const Employee(id: 'a', name: 'Awa', matricule: 'M01'));
      await repo.addRecord(PointageRecord(id: '1', employeeId: 'a', type: PointageType.arrivee, time: DateTime(2026, 10, 12, 8, 2), method: PointageMethod.pin));
      String? copie;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copie = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pump(t, PointageReportScreen(repository: repo, clock: () => DateTime(2026, 10, 12, 18), presentation: ListPresentation.dashboard));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('pointage_local_export')));
      await t.pumpAndSettle();
      expect(copie, contains('2026-10-12;08:02;M01;Awa;Arrivée;Nom + PIN;;non'));
      expect(find.textContaining('1 pointage(s) local(aux) copié(s)'), findsOneWidget);
    });

    testWidgets('Paramètres › Équipe : interrupteur « Afficher le menu Pointage local » (masqué par défaut)', (t) async {
      tailleTelephone(t);
      final s = SettingsProvider();
      await t.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
        value: s,
        child: MaterialApp(home: EquipePage(repository: MemoryPointageRepository())),
      ));
      await t.pumpAndSettle();
      expect(find.textContaining('n\'apparaissent pas dans Prestige'), findsOneWidget);
      expect(s.pointageLocalVisible, isFalse);
      await t.tap(find.byKey(const Key('pointage_local_visible')));
      await t.pumpAndSettle();
      expect(s.pointageLocalVisible, isTrue);
      expect(t.takeException(), isNull);
    });
  });

  // =========================================================================
  // Intégration réelle (serveur de test + base MySQL pour le nettoyage) : sautée si l'un manque.
  // Employé créé et rattaché au compte, pointage voie B (terminal, v1/rh) puis voie A (téléphone, v1/mobile),
  // les deux lus dans GET rh/presence?jour=<aujourd'hui> (ce qu'affiche « Présence du jour » de Prestige).
  // Tout est supprimé ensuite (pointages, employé, téléphone enregistré).
  // =========================================================================
  group('Intégration : pointages visibles dans « Présence du jour »', () {
    final url = Platform.environment['PRESTIGE_TEST_URL'] ?? 'http://localhost:8080/prestige/api/v1';
    final login = Platform.environment['PRESTIGE_TEST_LOGIN'] ?? 'admin';
    final mdp = Platform.environment['PRESTIGE_TEST_PASSWORD'] ?? 'Test1234';
    final base = Platform.environment['PRESTIGE_TEST_DB'] ?? 'laborex';

    Future<String?> sql(String requete) async {
      try {
        final r = await Process.run('mysql', ['-N', base, '-e', requete]);
        return r.exitCode == 0 ? '${r.stdout}'.trim() : null;
      } catch (_) {
        return null;
      }
    }

    test('voie A et voie B → GET rh/presence du jour pour l\'employé, puis nettoyage', () => HttpOverrides.runWithHttpOverrides(() async {
          final n0 = DateTime.now();
          if (n0.hour == 0 && n0.minute < 10) {
            markTestSkipped('Trop près de minuit (pointages à cheval sur deux jours).');
            return;
          }
          final dio = Dio(BaseOptions(baseUrl: url, validateStatus: (_) => true, connectTimeout: const Duration(seconds: 5)))
            ..interceptors.add(CookieManager(DioClient.cookieJar));
          try {
            await dio.get('/officine');
          } on DioException {
            markTestSkipped('Serveur de test injoignable : $url');
            return;
          }
          final userId = await sql("SELECT lg_USER_ID FROM t_user WHERE str_LOGIN = '$login'");
          if (userId == null || userId.isEmpty) {
            markTestSkipped('Base de test inaccessible (mysql $base) : nettoyage impossible, test non lancé.');
            return;
          }
          if ((await sql("SELECT COUNT(*) FROM t_employe WHERE lg_USER_ID = '$userId'")) != '0') {
            markTestSkipped('Le compte $login est déjà rattaché à un employé : données existantes non touchées.');
            return;
          }
          final auth = await dio.post('/user/auth', data: {'login': login, 'password': mdp});
          if (auth.data is! Map || auth.data['success'] != true) {
            markTestSkipped('Connexion $login refusée sur $url');
            return;
          }
          final tag = DateTime.now().millisecondsSinceEpoch.toString();
          final appareil = 'test-integration-presence-$tag';
          final pr = PointageRh(
            store: MemoryRhStore(),
            serveur: DioRhServeur(() => url),
            mobile: MobileApi(transport: DioTransportMobile(() => url), coffre: CoffreJetonMemoire(), appareil: () => appareil, nomAppareil: () => 'Test intégration'),
            // heure de lecture 5 min plus tôt : le téléphone refuse un second pointage < 2 min
            clock: () => DateTime.now().subtract(const Duration(minutes: 5)),
            horsLigne: () => false,
            nomTerminal: () => 'Test integration',
            journal: () => JournalTerminal(store: MemoryJournalStore()),
          );
          if (await pr.verifierAcces() != AccesRh.autorise) {
            markTestSkipped('Routes RH absentes ou droit P_SM_RH manquant : ${pr.accesMessage}');
            return;
          }
          final badge = 'ZZIT$tag';
          String? employeId;
          try {
            final c = await pr.serveur!.post('/rh/employes', {
              'matricule': 'ZZIT-$tag',
              'nom': 'ZZTEST',
              'prenoms': 'Integration',
              'badge': badge,
              'userId': userId,
              'dtEntree': PointageRh.jourCle(DateTime.now()),
            });
            employeId = await sql("SELECT id FROM t_employe WHERE matricule = 'ZZIT-$tag'");
            expect(c.body?['success'], isTrue, reason: '${c.body}');

            // Voie B : terminal (badge) → v1/rh/pointages
            expect(await pr.rafraichirEmployes(), isNull);
            final l = pr.lire(badge) as BadgeAConfirmer;
            final rb = await pr.enregistrer(l, SensPointage.entree);
            expect(rb.issue, IssueBadge.enregistre, reason: rb.message);

            // Voie A : téléphone → v1/mobile/pointages (QR du moment)
            final code = await pr.serveur!.get('/rh/mobile/code');
            final s = await pr.mobile!.connexion(login, mdp);
            expect(s.ok, isTrue, reason: s.refus);
            expect(s.valeur!.employeId, employeId, reason: 'le compte doit être rattaché à l\'employé créé');
            final ra = await pr.mobile!.pointer(sens: SensPointage.sortie, code: '${code.body?['contenu'] ?? ''}');
            expect(ra.ok, isTrue, reason: ra.refus);

            // « Présence du jour » de Prestige : même route
            final p = await pr.presence(DateTime.now());
            expect(p.erreur, isNull);
            final ligne = p.presences.where((x) => x.employeId == employeId).toList();
            expect(ligne, hasLength(1), reason: 'l\'employé doit figurer dans la présence du jour');
            expect(ligne.single.entree, isNotEmpty);
            expect(ligne.single.sortie, isNotEmpty);
            final sources = p.pointages.where((x) => x.employeId == employeId).map((x) => x.source).toSet();
            expect(sources, containsAll(['MANUEL', 'MOBILE']));
          } finally {
            await pr.mobile!.deconnecter();
            if (employeId != null && employeId.isNotEmpty) {
              await sql("DELETE FROM t_pointage WHERE employe_id = '$employeId'");
            }
            await sql("DELETE FROM t_mobile_terminal WHERE appareil = '$appareil'");
            await sql("DELETE FROM t_employe WHERE matricule = 'ZZIT-$tag'");
            expect(await sql("SELECT COUNT(*) FROM t_employe WHERE matricule = 'ZZIT-$tag'"), '0');
            expect(await sql("SELECT COUNT(*) FROM t_mobile_terminal WHERE appareil = '$appareil'"), '0');
          }
        }, _RealHttp()), timeout: const Timeout(Duration(minutes: 2)));
  });
}

class _RealHttp extends HttpOverrides {}
