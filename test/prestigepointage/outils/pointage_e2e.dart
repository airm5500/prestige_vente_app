// Prestige Pointage — outils des tests de bout en bout : application ENTIÈRE (PrestigePointageApp, initialisation de
// lib/main_pointage.dart) contre le faux serveur Prestige en mémoire, bornes de la demande 57 comprises
// (test/outils/faux_serveur_borne.dart). Données FICTIVES seulement.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/main_pointage.dart';
import 'package:prestige_vente_app/prestigepointage/identite_borne.dart';
import 'package:prestige_vente_app/prestigepointage/pointage_app.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/serveur/nom_appareil_serveur.dart';
import 'package:prestige_vente_app/services/nfc_service.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../outils/faux_serveur_borne.dart';
import '../../outils/faux_serveur_prestige.dart';

export '../../outils/faux_serveur_borne.dart';
export '../../outils/faux_serveur_prestige.dart';

/// Empreinte FICTIVE de l'appareil (demande 56).
final empreinteE2E = 'c0ffee12' * 8;

/// QR d'un badge FICTIF (format de la 4.6.2) : le secret ne doit apparaître nulle part.
const secretBadgeE2E = 'SecretFictifDuBadge0123456789AB';
const qrBadgeE2E = 'PRESTIGE-BADGE|1|B001|caisse.demo|$secretBadgeE2E';

class NfcSimule implements NfcReader {
  NfcAvailability etat;
  final _tags = StreamController<String>.broadcast();
  NfcSimule([this.etat = NfcAvailability.ready]);
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

class EmpreinteSimulee implements FournisseurEmpreinte {
  bool present;
  int? reconnu;
  int captures = 0;
  EmpreinteSimulee({this.present = false, this.reconnu = 0});
  @override
  Future<bool> disponible() async => present;
  @override
  Future<Uint8List> enroler() async {
    captures++;
    return Uint8List.fromList([0xF0, captures]);
  }

  @override
  Future<int?> identifier(List<Uint8List> modeles) async => reconnu;
  @override
  Future<void> annuler() async {}
}

class _SansCamera implements CameraControle {
  @override
  Future<SessionCamera> ouvrir() async => throw const CameraIndisponible(MotifSansPhoto.cameraAbsente);
}

class PointageE2E {
  final serveur = FauxServeurPrestige();
  late final FauxBornes bornes;
  final coffre = CoffreBorneMemoire();
  final nfc = NfcSimule();
  final empreinte = EmpreinteSimulee();
  final coffreEmpreintes = CoffreEmpreintesMemoire();
  int codesAdmin = 0;

  /// Prépare l'appareil : adresse du serveur NON configurée (premier lancement) sauf [configure] ; nom de l'appareil
  /// déjà enregistré sauf [sansNom] ; photo de contrôle coupée sauf [photo].
  Future<void> preparer({bool configure = false, bool sansNom = false, bool photo = false, Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues({
      if (configure) ...{'local_ip': FauxServeurPrestige.hoteMemoire, 'port': FauxServeurPrestige.portMemoire, 'app_name': 'prestige'},
      if (!sansNom) NomAppareil.prefNom: 'Borne entrée',
      ReglagesPointageTerminal.prefPhoto: photo,
      PhotoControle.prefPermissionExpliquee: true,
      ...prefs,
    });
    FlutterSecureStorage.setMockInitialValues({});
    serveur.installerEnMemoire();
    bornes = FauxBornes(serveur);
    serveur.employesRh = [
      ...serveur.employesRh,
      {'id': 'E3', 'matricule': '03', 'nom': 'KONE', 'prenoms': 'Mariam', 'badge': '04A1B2C3', 'statut': 'ACTIF', 'poste': 'Préparatrice', 'telephone': '0000'},
    ];
    NomAppareilServeur.instance.empreinte = () async => empreinteE2E;
    NomAppareil.reinitialiser();
    NomAppareil.instance.modele = () => 'SUNMI V2s';
    final codeAvant = PointageApp.codeAdmin;
    PointageApp.codeAdmin = (_) async {
      codesAdmin++;
      return true;
    };
    PointageApp.delaiConfirmation = const Duration(seconds: 1);
    PointageApp.delaiResultat = const Duration(seconds: 2);
    await DioClient.cookieJar.deleteAll();
    await initialiserPrestigePointage(
      store: MemoryLocalStore(),
      coffre: coffre,
      photos: PhotoControle(camera: _SansCamera(), registre: RegistrePhotosPointage(stockage: StockagePhotosMemoire())),
      identification: IdentificationEmploye(empreinte: empreinte, nfc: nfc, coffre: coffreEmpreintes),
    );
    addTearDown(() async {
      liberer();
      TailleEcranReglage.reinitialiser();
      PointageApp.codeAdmin = codeAvant;
      PointageApp.delaiConfirmation = const Duration(seconds: 3);
      PointageApp.delaiResultat = const Duration(seconds: 4);
      serveur.desinstaller();
      await DioClient.cookieJar.deleteAll();
    });
  }

  /// Borne déjà enrôlée (identité dans le coffre, borne connue du serveur) ; après [preparer], avant [lancer].
  Future<IdentiteBorne> enrolerDirectement({String nom = 'Borne entrée'}) async {
    final secret = List<int>.generate(32, (i) => 200 - i);
    const id = 'BORNE-E2E';
    bornes.bornes[id] = BorneServeur(id, nom, empreinteE2E, secret, DonneesFictives.admin);
    final i = IdentiteBorne(borneId: id, secret: secret, empreinte: empreinteE2E, nom: nom, serveur: serveur.base);
    await coffre.ecrire(i);
    await PointageApp.controleur.charger();
    return i;
  }

  final List<Object?> modesSysteme = [];
  bool _libere = false;

  /// Arrête les minuteries du contrôleur (avant la fin du test : aucune minuterie ne doit rester).
  void liberer() {
    if (_libere) return;
    _libere = true;
    PointageApp.controleur.dispose();
  }

  /// Tout ce que l'application a écrit par debugPrint pendant le test (rendu à la fermeture).
  final List<String> journaux = [];
  void Function(String? message, {int? wrapWidth})? _printAvant;

  Future<void> lancer(WidgetTester t) async {
    _printAvant ??= debugPrint;
    debugPrint = (m, {wrapWidth}) => journaux.add(m ?? '');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') modesSysteme.add(call.arguments);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await t.pumpWidget(const PrestigePointageApp());
    await t.pump();
  }

  Future<void> attendre(WidgetTester t, [Duration duree = const Duration(seconds: 2)]) async {
    const pas = Duration(milliseconds: 100);
    var e = Duration.zero;
    while (e < duree) {
      await t.pump(pas);
      e += pas;
    }
  }

  Future<bool> attendreQue(WidgetTester t, Finder f, {Duration max = const Duration(seconds: 15)}) async {
    const pas = Duration(milliseconds: 100);
    var e = Duration.zero;
    while (e < max) {
      if (f.evaluate().isNotEmpty) return true;
      await t.pump(pas);
      e += pas;
    }
    return f.evaluate().isNotEmpty;
  }

  /// Attend [f] en laissant passer le temps simulé (le transport en mémoire a besoin des images).
  Future<T> fini<T>(WidgetTester t, Future<T> f, {Duration max = const Duration(seconds: 30)}) async {
    var fait = false;
    late T v;
    Object? err;
    f.then((x) {
      v = x;
      fait = true;
    }, onError: (Object e) {
      err = e;
      fait = true;
    });
    const pas = Duration(milliseconds: 50);
    var e = Duration.zero;
    while (!fait && e < max) {
      await t.pump(pas);
      e += pas;
    }
    if (err != null) throw err!;
    if (!fait) throw StateError('délai dépassé');
    return v;
  }

  /// Lecture d'un badge par la douchette (saisie rapide + Entrée), puis confirmation automatique.
  Future<void> badge(WidgetTester t, String code) async {
    await t.enterText(find.byKey(const Key('rh_badge_champ')), code);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    await attendre(t, const Duration(milliseconds: 1500));
  }

  Future<void> fermer(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    liberer();
    if (_printAvant != null) debugPrint = _printAvant!;
    await t.pump(const Duration(seconds: 31));
  }
}
