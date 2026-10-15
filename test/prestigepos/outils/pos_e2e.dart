// Banc e2e de PrestigePOS : l'application PrestigePOS ENTIÈRE (PrestigePosApp, initialisation de lib/main_pos.dart,
// vrais écrans, vrai client Dio, vraie borne partagée) reliée au faux serveur Prestige EN MÉMOIRE
// (test/outils/faux_serveur_prestige.dart). Simulés : le code administrateur (4827), l'épinglage d'écran,
// le pont Android des imprimantes Bluetooth / USB (octets reçus relevés), la détection Sunmi.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/session_expiree.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_kiosque.dart';
import 'package:prestige_vente_app/borne/borne_launcher.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/horsligne_ui.dart';
import 'package:prestige_vente_app/images/produit_images.dart';
import 'package:prestige_vente_app/main_pos.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/prestigepos/demarrage_auto.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_pos.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_reglages.dart';
import 'package:prestige_vente_app/prestigepos/impression/transports.dart';
import 'package:prestige_vente_app/prestigepos/pos_app.dart';
import 'package:prestige_vente_app/services/pin_securise.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../outils/faux_serveur_prestige.dart';

export '../../outils/faux_serveur_prestige.dart';

const loginBorne = 'borne.pos';
const mdpBorne = 'Borne#2026';
const codeAdminPos = '4827';
const imprimanteBt = AppareilImprimante(nom: 'MTP-II', adresse: '00:11:22:AA:BB:CC', appaire: true, imprimante: true);

/// Produit fictif de la recherche de vente.
Map<String, dynamic> produit(String id, String nom, String cip, int prix, int stock) =>
    {'lgFAMILLEID': id, 'strNAME': nom, 'intCIP': cip, 'intPRICE': prix, 'intNUMBERAVAILABLE': stock, 'strLIBELLEE': '', 'intPAF': 0};

final catalogueDefaut = [
  produit('F1', 'DOLIPRANE 1000MG CP B/8', '3595583', 1500, 40),
  produit('F2', 'DOLIRHUME PARACETAMOL CP B/16', '3400562', 2850, 14),
  produit('F3', 'VITAMINE C UPSA 1000MG CPR EFFV B/20', '3401178', 2300, 18),
];

/// Code administrateur simulé (vraie fenêtre PinCodeDialog, vérification : 4827).
class CodeSimule extends CodeAdmin {
  int demandes = 0;
  @override
  Future<Duration?> attenteRestante() async => null;
  @override
  Future<VerificationPin> verifier(String saisie) async {
    demandes++;
    return saisie == codeAdminPos ? VerificationPin.accepte : VerificationPin.refuse;
  }
}

/// Pont Android des imprimantes simulé.
class PontSimule implements PontImprimantes {
  bool autorise = true;
  List<AppareilImprimante> appairesListe = const [imprimanteBt];
  List<AppareilImprimante> decouverts = const [AppareilImprimante(nom: 'Casque JBL', adresse: '10:20:30:40:50:60')];
  List<AppareilImprimante> usbListe = const [AppareilImprimante(nom: 'Xprinter XP-58', adresse: '1155:22339', imprimante: true)];

  /// Échec à lever à l'envoi (null : envoi réussi).
  EchecImpression? echec;
  EchecImpression? echecRecherche;
  final List<(String, Uint8List)> envois = [];
  int recherches = 0;

  @override
  Future<bool> autorisations() async => autorise;
  @override
  Future<List<AppareilImprimante>> appaires() async {
    if (echecRecherche != null) throw echecRecherche!;
    return appairesListe;
  }

  @override
  Future<List<AppareilImprimante>> rechercher({Duration duree = const Duration(seconds: 12)}) async {
    recherches++;
    if (echecRecherche != null) throw echecRecherche!;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return [...appairesListe, ...decouverts];
  }

  @override
  Future<void> activerBluetooth() async {}
  @override
  Future<void> envoyerBluetooth(String adresse, Uint8List octets) async {
    if (echec != null) throw echec!;
    envois.add((adresse, octets));
  }

  @override
  Future<List<AppareilImprimante>> usb() async => usbListe;
  @override
  Future<void> envoyerUsb(int vendorId, int productId, Uint8List octets) async {
    if (echec != null) throw echec!;
    envois.add(('$vendorId:$productId', octets));
  }
}

class PosE2E {
  final FauxServeurPrestige serveur;
  final pont = PontSimule();
  final kiosque = KiosqueSimule();
  final code = CodeSimule();

  /// Démarrage automatique (1.1.0) : Android simulé.
  final demarrage = DemarrageSimule();
  List<Map<String, dynamic>> catalogue;

  /// Recherches reçues par le serveur (texte demandé).
  final List<String> recherches = [];

  PosE2E({FauxServeurPrestige? serveur, List<Map<String, dynamic>>? catalogue})
      : serveur = serveur ??
            FauxServeurPrestige(comptes: {
              DonneesFictives.login: DonneesFictives.motDePasse,
              DonneesFictives.admin: DonneesFictives.motDePasseAdmin,
              loginBorne: mdpBorne,
            }),
        catalogue = catalogue ?? catalogueDefaut {
    this.serveur.routes['GET /vente/search'] = (r) {
      final q = (r.query['query'] ?? '').toUpperCase();
      recherches.add(q);
      final start = int.tryParse(r.query['start'] ?? '') ?? 0;
      final limit = int.tryParse(r.query['limit'] ?? '') ?? 20;
      final contient = q.startsWith('%');
      final mots = q.split('%').where((m) => m.isNotEmpty).toList();
      final l = [
        for (final p in this.catalogue)
          if (p['intCIP'] == q ||
              (contient ? mots.every((m) => (p['strNAME'] as String).contains(m)) : (p['strNAME'] as String).startsWith(q)))
            p
      ];
      return FauxServeurPrestige.ok({'data': l.skip(start).take(limit).toList(), 'total': l.length});
    };
  }

  /// Préférences de PrestigePOS déjà configuré (serveur, utilisateur borne, imprimante Bluetooth).
  static Map<String, Object> prefsConfigure({BorneConfig? borne, ImprimanteConfig? imprimante}) => {
        'local_ip': FauxServeurPrestige.hoteMemoire,
        'port': FauxServeurPrestige.portMemoire,
        'app_name': 'prestige',
        'prestigepos_configure_v1': true,
        'borne_config_v1': jsonEncode((borne ?? const BorneConfig(actif: true, login: loginBorne)).toJson()),
        'prestigepos_imprimante_v1':
            jsonEncode((imprimante ?? const ImprimanteConfig(type: TypeImprimante.bluetooth, bluetooth: imprimanteBt, memorisees: [imprimanteBt])).toJson()),
      };

  /// Appareil neuf ([configure] false) ou PrestigePOS configuré.
  Future<void> preparer({bool configure = false, Map<String, Object> prefs = const {}, bool motDePasse = true}) async {
    SharedPreferences.setMockInitialValues({if (configure) ...prefsConfigure(), ...prefs});
    FlutterSecureStorage.setMockInitialValues({});
    final secretsAvant = BorneReglages.secrets;
    BorneReglages.secrets = MemoireBorneSecrets(configure && motDePasse ? mdpBorne : null);
    final codeAvant = CodeAdmin.instance;
    CodeAdmin.instance = code;
    final kiosqueAvant = BorneKiosque.instance;
    BorneKiosque.instance = kiosque;
    final pontAvant = PontImprimantes.instance;
    PontImprimantes.instance = pont;
    final hlAvant = HorsLigne.instance;
    final imprimanteAvant = PosApp.imprimante;
    final codeAdminAvant = PosApp.codeAdmin;
    final hoteAvant = BorneLauncher.hote;
    final sortieAvant = BorneLauncher.apresSortie;
    PosApp.imprimante = () => ImprimantePos(sunmi: () async => false);
    PosApp.codeAdmin = PinCodeDialog.show;
    PaiementsMobile.instance = PaiementsMobile();
    ProduitImages.instance = ProduitImages();
    SessionExpiree.instance = SessionExpiree();
    await DioClient.cookieJar.deleteAll();
    final demarrageAvant = DemarrageAuto.plateforme;
    DemarrageAuto.plateforme = demarrage;
    DemarrageAuto.courant.value = const EtatDemarrage();
    addTearDown(() {
      DemarrageAuto.plateforme = demarrageAvant;
      DemarrageAuto.courant.value = const EtatDemarrage();
    });
    await initialiserPrestigePos();
    serveur.installerEnMemoire();
    addTearDown(() async {
      TailleEcranReglage.reinitialiser();
      serveur.desinstaller();
      BorneReglages.secrets = secretsAvant;
      BorneReglages.courant.value = const BorneConfig();
      ImprimanteReglages.courant.value = const ImprimanteConfig();
      CodeAdmin.instance = codeAvant;
      BorneKiosque.instance = kiosqueAvant;
      PontImprimantes.instance = pontAvant;
      HorsLigne.instance = hlAvant;
      HorsLigneScope.masquer.value = false;
      PosApp.imprimante = imprimanteAvant;
      PosApp.codeAdmin = codeAdminAvant;
      BorneLauncher.hote = hoteAvant;
      BorneLauncher.apresSortie = sortieAvant;
      PaiementsMobileReglages.actif.value = false;
      await DioClient.cookieJar.deleteAll();
    });
  }

  /// Monte PrestigePOS (comme runApp(const PrestigePosApp())). Barres système et épinglage relevés.
  final List<Object?> modesSysteme = [];
  Future<void> lancer(WidgetTester t) async {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') modesSysteme.add(call.arguments);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpWidget(const PrestigePosApp());
    await t.pump();
  }

  Future<void> attendre(WidgetTester t, [Duration duree = const Duration(seconds: 2)]) async {
    const pas = Duration(milliseconds: 100);
    var ecoule = Duration.zero;
    while (ecoule < duree) {
      await t.pump(pas);
      ecoule += pas;
    }
  }

  Future<bool> attendreQue(WidgetTester t, Finder f, {Duration max = const Duration(seconds: 15)}) async {
    const pas = Duration(milliseconds: 100);
    var ecoule = Duration.zero;
    while (ecoule < max) {
      if (f.evaluate().isNotEmpty) return true;
      await t.pump(pas);
      ecoule += pas;
    }
    return f.evaluate().isNotEmpty;
  }

  Future<void> fermer(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 31));
  }

  // --- Gestes ---------------------------------------------------------------------------------------

  Future<void> toucher(WidgetTester t, String cle) async {
    final f = find.byKey(ValueKey(cle));
    expect(await attendreQue(t, f), isTrue, reason: '« $cle » introuvable');
    await t.ensureVisible(f.first);
    await t.pump();
    await t.tap(f.first);
    await attendre(t, const Duration(milliseconds: 600));
  }

  Future<void> saisir(WidgetTester t, String cle, String texte) async {
    final f = find.byKey(ValueKey(cle));
    expect(await attendreQue(t, f), isTrue, reason: '« $cle » introuvable');
    await t.ensureVisible(f.first);
    await t.enterText(f.first, texte);
    await t.pump();
  }

  Future<void> saisirCode(WidgetTester t, [String c = codeAdminPos]) async {
    expect(await attendreQue(t, find.byKey(const Key('pin_admin_saisie'))), isTrue, reason: 'code administrateur demandé');
    await t.enterText(find.byKey(const Key('pin_admin_saisie')), c);
    await t.tap(find.text('Valider'));
    await attendre(t, const Duration(seconds: 1));
  }

  /// Appui long de 2,1 s (cadenas de sortie).
  Future<void> appuiLong(WidgetTester t, Finder f) async {
    final g = await t.startGesture(t.getCenter(f.first));
    await t.pump(const Duration(milliseconds: 2100));
    await g.up();
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  /// Sortie de la borne : cadenas 2 s → « Quitter » → code administrateur.
  Future<void> quitterBorne(WidgetTester t) async {
    await appuiLong(t, find.byKey(const ValueKey('borne-sortie')));
    await toucher(t, 'sortie-kiosque-confirmer');
    await saisirCode(t);
  }

  /// Recherche dans la borne (saisie puis délai anti-rebond).
  Future<void> chercher(WidgetTester t, String texte) async {
    await saisir(t, 'borne-recherche', texte);
    await attendre(t, const Duration(seconds: 1));
  }

  /// Tickets imprimés (octets reçus par l'imprimante Bluetooth simulée), décodés en texte lisible.
  List<String> ticketsTexte() => [for (final e in pont.envois) latin1.decode(e.$2, allowInvalid: true)];
}
