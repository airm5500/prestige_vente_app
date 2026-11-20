// 5.3.0 — Outils des tests du pointage sans service d'empreinte Sunmi (pistes 1, 2 et 4) : canal natif
// `prestige/fingerprint` SIMULÉ (service Sunmi présent / absent, lecteur Android, BiometricPrompt), faux serveur RH,
// faux NFC, terminal de pointage prêt à l'emploi. Données FICTIVES seulement (aucun vrai nom, badge ni modèle).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/rh/rh_store.dart';
import 'package:prestige_vente_app/rh/terminal_pointage_screen.dart';
import 'package:prestige_vente_app/services/nfc_service.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Badges et employés FICTIFS.
const badgeFictif1 = 'FX12AB34';
const badgeFictif2 = '0FA1B2C3';
const matriculeFictif1 = 'MX01';

/// Matériel d'un SUNMI V3 (Android 13) : lecteur Android, aucun service d'identification Sunmi.
Map<String, Object?> materielSunmiV3({int? biometricStatus = 0, bool lecteur = true}) => {
      'manufacturer': 'SUNMI',
      'model': 'V3',
      'android': '13',
      'sdk': 33,
      'featureFingerprint': lecteur,
      'biometricStatus': biometricStatus,
      'sunmiServices': <Object?>[],
      'sunmiPackages': <Object?>[],
    };

/// Ancien terminal Sunmi (service com.sunmi.fingerprintservice présent).
Map<String, Object?> materielAncienSunmi() => {
      'manufacturer': 'SUNMI',
      'model': 'V2 Pro',
      'android': '7.1',
      'sdk': 25,
      'featureFingerprint': false,
      'sunmiServices': <Object?>['com.sunmi.fingerprintservice/.FingerprintService'],
      'sunmiPackages': <Object?>['com.sunmi.fingerprintservice'],
    };

/// Tablette ordinaire : ni Sunmi ni lecteur.
Map<String, Object?> materielTablette() => {
      'manufacturer': 'Lenovo',
      'model': 'Tab',
      'android': '12',
      'sdk': 31,
      'featureFingerprint': false,
      'biometricStatus': 12,
      'sunmiServices': <Object?>[],
      'sunmiPackages': <Object?>[],
    };

/// Canal natif `prestige/fingerprint` simulé.
class CanalEmpreinteSimule {
  static const canal = MethodChannel('prestige/fingerprint');

  /// Service d'identification Sunmi installé (piste 4).
  bool service;
  Map<String, Object?> materiel;

  /// Réponse de BiometricPrompt : null → reconnue (true) ; sinon code d'erreur (CANCELED, LOCKOUT, …) ou
  /// « false » pour un refus sans erreur.
  String? reponseAuthentification;

  /// Index renvoyé par l'identification 1:N (piste 4), -1 : non reconnue.
  int indexIdentifie = 0;

  final appels = <MethodCall>[];

  CanalEmpreinteSimule({this.service = false, Map<String, Object?>? materiel, this.reponseAuthentification})
      : materiel = materiel ?? materielSunmiV3();

  List<MethodCall> appelsDe(String methode) => [for (final a in appels) if (a.method == methode) a];

  void installer(WidgetTester t) {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(canal, _repondre);
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(canal, null));
  }

  /// Hors widget (tests unitaires).
  void installerGlobal() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, _repondre);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, null));
  }

  Future<Object?> _repondre(MethodCall c) async {
    appels.add(c);
    switch (c.method) {
      case 'isServiceInstalled':
        return service;
      case 'hardwareInfo':
        return materiel;
      case 'authenticate':
        final r = reponseAuthentification;
        if (r == null) return true;
        if (r == 'false') return false;
        throw PlatformException(code: r, message: 'Erreur simulée ($r)');
      case 'connect':
      case 'engage':
        if (!service) throw PlatformException(code: 'NOT_CONNECTED', message: 'Service d\'empreinte non connecté');
        return true;
      case 'identify':
        return {'index': indexIdentifie, 'score': 90};
      case 'enroll':
        return Uint8List.fromList([0xA5, appels.length & 0xFF]);
      case 'release':
      case 'cancel':
        return 0;
      case 'empreinteAppareil':
        return null;
    }
    return null;
  }
}

/// Faux serveur RH (routes v1/rh), employés FICTIFS.
class FauxRhEmpreinte implements RhServeur {
  bool offline = false;
  final posts = <Map<String, dynamic>>[];
  final gets = <String>[];
  List<Map<String, dynamic>> employes = [
    {'id': 'EX1', 'matricule': matriculeFictif1, 'badge': badgeFictif1, 'nom': 'TESTEUR', 'prenoms': 'Alpha', 'statut': 'ACTIF'},
    {'id': 'EX2', 'matricule': 'MX02', 'badge': badgeFictif2, 'nom': 'ESSAI', 'prenoms': 'Beta', 'statut': 'ACTIF'},
  ];

  @override
  Future<ReponseRh> get(String chemin, [Map<String, dynamic> query = const {}]) async {
    if (offline) throw const RhHorsLigne();
    gets.add(chemin);
    switch (chemin) {
      case '/rh/droits':
        return (status: 200, body: {'success': true, 'pointer': true, 'gerer': true});
      case '/rh/employes':
        return (status: 200, body: {'success': true, 'data': employes});
      case '/rh/presence':
        return (status: 200, body: {'success': true, 'data': <Object>[], 'pointages': <Object>[]});
    }
    return (status: 404, body: null);
  }

  @override
  Future<ReponseRh> post(String chemin, Map<String, dynamic> corps) async {
    if (offline) throw const RhHorsLigne();
    posts.add(corps);
    return (status: 200, body: {'success': true, 'message': 'Pointage manuel enregistré.'});
  }
}

class FauxNfcEmpreinte implements NfcReader {
  NfcAvailability etat;
  final _tags = StreamController<String>.broadcast();
  FauxNfcEmpreinte([this.etat = NfcAvailability.absent]);
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

/// Terminal de pointage RH avec le VRAI pont Sunmi (SunmiEmpreinte, confirmation Android) sur le canal simulé.
class TerminalEmpreinte {
  final canal = CanalEmpreinteSimule();
  final rh = FauxRhEmpreinte();
  final nfc = FauxNfcEmpreinte();
  final coffre = CoffreEmpreintesMemoire();
  final journal = JournalTerminal(store: MemoryJournalStore());
  DateTime now = DateTime(2026, 11, 23, 8, 2);
  late final IdentificationEmploye identification = IdentificationEmploye(nfc: nfc, coffre: coffre);
  late final PointageRh pr = PointageRh(
    store: MemoryRhStore(),
    serveur: rh,
    identification: identification,
    clock: () => now,
    horsLigne: () => false,
    nomTerminal: () => 'Entrée',
    journal: () => journal,
  );

  Future<void> preparer(WidgetTester t) async {
    canal.installer(t);
    await pr.verifierAcces();
    await pr.rafraichirEmployes();
  }

  Widget ecran({
    bool? gestion,
    bool borne = false,
    Future<String?> Function(BuildContext)? camera,
    ListPresentation presentation = ListPresentation.dashboard,
  }) =>
      TerminalPointageScreen(
        rh: pr,
        presentation: presentation,
        identification: identification,
        rafraichirAuDemarrage: false,
        gestion: gestion,
        borneAuDemarrage: borne,
        camera: camera,
        codeAdmin: (_) async => true,
      );

  /// Tout le journal du terminal (pour vérifier qu'aucune donnée personnelle n'y est).
  Future<String> toutLeJournal() async {
    await journal.idle;
    return [for (final x in await journal.lire()) [x.action, x.motif, x.refLocale, x.refServeur].join('|')].join('\n');
  }
}

Future<void> afficher(WidgetTester t, Widget w) async {
  await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, home: KeyedSubtree(key: UniqueKey(), child: w)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
  await t.pump(const Duration(milliseconds: 50));
}

Future<void> lireBadge(WidgetTester t, String code) async {
  // Champ caché du lecteur de badge : construit et focalisé même sous le bas d'un petit écran.
  await t.enterText(find.byKey(const Key('rh_badge_champ'), skipOffstage: false), code);
  await t.testTextInput.receiveAction(TextInputAction.done);
  await t.pump();
  await t.pump();
  await t.pump();
}

Future<void> finir(WidgetTester t) async {
  await t.pump(const Duration(seconds: 6));
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

void taille(WidgetTester t, Size dp, {double densite = 1}) {
  t.view.physicalSize = dp * densite;
  t.view.devicePixelRatio = densite;
  addTearDown(t.view.reset);
}
