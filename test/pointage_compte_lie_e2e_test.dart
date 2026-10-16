// 4.4.0 — « Mon pointage » lié au compte de l'application (décision du pharmacien, proposition a).
// Scénario de la capture du pharmacien (NEMA / EMMANUEL), rejoué avec des comptes FICTIFS :
//   le téléphone gardait le jeton v1/mobile du compte « NEMA » ; EMMANUEL ouvre l'application et pointe →
//   le pointage partait au nom de NEMA (bandeau seulement).
// Désormais : jeton de NEMA effacé à l'ouverture, connexion v1/mobile automatique d'EMMANUEL (mot de passe mémorisé)
// ou mot de passe seul (identifiant non modifiable), et le pointage est reçu par le serveur pour EMMANUEL.
// Sécurité : aucun pointage au nom d'un autre compte (connexion d'un autre identifiant refusée sans requête, session
// d'un autre compte rendue par le serveur jamais gardée, jeton d'un autre compte jamais utilisé).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/rh/mobile_api.dart';
import 'package:prestige_vente_app/rh/mobile_pointage_screen.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/services/identifiants_securises.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

import 'outils/app_e2e.dart';

const _nema = 'nema.demo';
const _emmanuel = 'emmanuel.demo';
const _mdpNema = 'Fictif#Nema1';
const _mdpEmmanuel = 'Fictif#Emma1';
const _cleJeton = 'prestige_rh_session_mobile_v1';

/// Jeton v1/mobile de NEMA laissé sur le téléphone (comme sur la capture).
String _jetonNema(FauxServeurPrestige s) {
  s.jetonsMobile['JETON-NEMA-ANCIEN'] = _nema;
  return jsonEncode({
    'success': true,
    'utilisateur': {'id': 'U-$_nema', 'login': _nema, 'nom': 'TEST Nema'},
    'employe': {'id': 'E-$_nema', 'matricule': '06', 'nom': 'TEST Nema'},
    'droits': {'pointage': true, 'photos': false},
    'pointage': {'qr': false, 'gps': false},
    'jeton': 'JETON-NEMA-ANCIEN',
    'expiration': '2099-12-31T23:59:00Z',
  });
}

AppE2E _app() {
  final s = FauxServeurPrestige(comptes: {
    DonneesFictives.login: DonneesFictives.motDePasse,
    DonneesFictives.admin: DonneesFictives.motDePasseAdmin,
    _nema: _mdpNema,
    _emmanuel: _mdpEmmanuel,
  })
    ..activerPointageMobile({_nema: 'TEST Nema', _emmanuel: 'TEST Emmanuel'});
  return AppE2E(serveur: s);
}

Future<void> _ouvrirMonPointage(WidgetTester t, AppE2E app) async {
  await app.ouvrirMenu(t, ListPresentation.dashboard, 'pointage_rh');
  expect(await app.attendreQue(t, find.byKey(const Key('rh_voie_a'))), isTrue);
  await app.attendre(t, const Duration(seconds: 1));
  await t.tap(find.byKey(const Key('rh_voie_a')));
  expect(await app.attendreQue(t, find.byType(MobilePointageScreen)), isTrue);
  await app.attendre(t, const Duration(seconds: 1));
}

void main() {
  testWidgets('NEMA / EMMANUEL : jeton de NEMA effacé, EMMANUEL connecté sans geste (mot de passe mémorisé), pointage reçu pour EMMANUEL', (t) async {
    TailleEcran.telephone360x800.appliquer(t);
    final app = _app();
    await app.preparer(resterConnecte: true, login: _emmanuel, motDePasse: _mdpEmmanuel, prefs: const {'hiddenMenuIds': <String>[]});
    FlutterSecureStorage.setMockInitialValues({IdentifiantsSecurises.cleSure: _mdpEmmanuel, _cleJeton: _jetonNema(app.serveur)});
    await app.lancer(t);
    // « Rester connecté » : l'accueil s'ouvre directement pour EMMANUEL.
    if (!await app.attendreQue(t, find.byKey(const Key('accueil_deconnexion')))) {
      expect(await app.seConnecter(t, login: _emmanuel, motDePasse: _mdpEmmanuel), isTrue);
    }
    await app.attendre(t, const Duration(seconds: 3));
    await _ouvrirMonPointage(t, app);

    expect(find.textContaining('était connecté au compte « $_nema » : déconnecté'), findsOneWidget);
    expect(find.textContaining('pointe désormais pour « $_emmanuel »'), findsOneWidget);
    expect(app.serveur.connexionsMobile, [_emmanuel], reason: 'connexion v1/mobile automatique, pour EMMANUEL seulement');
    expect(find.byKey(const Key('rh_mobile_mdp')), findsNothing, reason: 'aucun mot de passe à ressaisir');
    expect(find.text('TEST Emmanuel · M-$_emmanuel'), findsOneWidget);
    expect(find.byKey(const Key('rh_mobile_autre_compte')), findsNothing);

    await t.tap(find.byKey(const Key('rh_depart')));
    await app.attendre(t, const Duration(seconds: 6)); // position facultative : 5 s au plus
    expect(app.serveur.pointagesMobile.map((p) => p.login), [_emmanuel], reason: 'reçu au nom d\'EMMANUEL');
    expect(app.serveur.pointagesMobile.where((p) => p.login == _nema), isEmpty, reason: 'jamais au nom de NEMA');
    expect(find.text('Sortie enregistrée à 08:02.'), findsOneWidget);
    final coffre = await const FlutterSecureStorage().read(key: _cleJeton);
    expect(coffre, isNot(contains('JETON-NEMA-ANCIEN')));
    expect(coffre, contains('"login":"$_emmanuel"'));
    expect(coffre, isNot(contains(_mdpEmmanuel)), reason: 'mot de passe jamais dans le coffre du jeton');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('sans mot de passe mémorisé : mot de passe seul, identifiant d\'EMMANUEL pré-rempli et non modifiable', (t) async {
    TailleEcran.telephone360x800.appliquer(t);
    final app = _app();
    await app.preparer(prefs: const {'hiddenMenuIds': <String>[]});
    FlutterSecureStorage.setMockInitialValues({_cleJeton: _jetonNema(app.serveur)});
    await app.lancer(t);
    expect(await app.seConnecter(t, login: _emmanuel, motDePasse: _mdpEmmanuel), isTrue);
    await _ouvrirMonPointage(t, app);

    expect(find.textContaining('était connecté au compte « $_nema »'), findsOneWidget);
    expect(app.serveur.connexionsMobile, isEmpty);
    final champ = t.widget<TextField>(find.byKey(const Key('rh_mobile_login')));
    expect(champ.controller!.text, _emmanuel);
    expect(champ.readOnly, isTrue, reason: 'identifiant non modifiable');
    // Même en forçant le texte du champ, c'est le compte de l'application qui se connecte.
    champ.controller!.text = _nema;
    await t.enterText(find.byKey(const Key('rh_mobile_mdp')), _mdpNema);
    await t.tap(find.byKey(const Key('rh_mobile_connecter')));
    await app.attendre(t, const Duration(seconds: 2));
    expect(app.serveur.connexionsMobile, [_emmanuel], reason: 'jamais de connexion au compte de NEMA');
    expect(find.text('Identifiant ou mot de passe incorrect.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('rh_mobile_mdp')), _mdpEmmanuel);
    await t.tap(find.byKey(const Key('rh_mobile_connecter')));
    await app.attendre(t, const Duration(seconds: 2));
    await t.tap(find.byKey(const Key('rh_arrivee')));
    await app.attendre(t, const Duration(seconds: 6)); // position facultative : 5 s au plus
    expect(app.serveur.pointagesMobile.map((p) => p.login), [_emmanuel]);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  group('sécurité : aucun pointage au nom d\'un autre compte', () {
    MobileApi api(FauxServeurPrestige s, CoffreJetonMemoire c, List<String> chemins) => MobileApi(
          transport: _Espion(chemins, s),
          coffre: c,
          appareil: () => 'test',
          nomAppareil: () => 'test',
        );

    test('connexion d\'un autre identifiant : refusée sans requête', () async {
      final chemins = <String>[];
      final m = api(FauxServeurPrestige(), CoffreJetonMemoire(), chemins);
      await m.lier(_emmanuel);
      final r = await m.connexion(_nema, _mdpNema);
      expect(r.ok, isFalse);
      expect(r.refus, contains('« $_emmanuel »'));
      expect(chemins, isEmpty);
    });

    test('casse et espaces de l\'identifiant tolérés ; session d\'un AUTRE compte rendue par le serveur : jamais gardée', () async {
      final chemins = <String>[];
      final c = CoffreJetonMemoire();
      final m = api(FauxServeurPrestige(), c, chemins);
      await m.lier(_emmanuel);
      _Espion.reponse = (status: 200, body: {'success': true, 'utilisateur': {'login': _nema}, 'jeton': 'J-NEMA', 'expiration': '2099-01-01T00:00:00Z'});
      final r = await m.connexion(' EMMANUEL.DEMO ', 'x');
      expect(chemins, ['POST connexion']);
      expect(r.ok, isFalse);
      expect(c.valeur, isNull, reason: 'jeton de l\'autre compte jamais gardé');
      expect(m.session, isNull);
    });

    test('jeton d\'un autre compte dans le coffre : effacé au lien ; jamais envoyé, même sans lien préalable relu', () async {
      final chemins = <String>[];
      final s = FauxServeurPrestige();
      final c = CoffreJetonMemoire(_jetonNema(s));
      final m = api(s, c, chemins);
      expect(await m.lier(_emmanuel), isTrue);
      expect(m.jetonEfface, _nema);
      expect(c.valeur, isNull);
      await expectLater(m.pointer(sens: SensPointage.entree), throwsA(isA<MobileSessionExpiree>()));
      expect(chemins, isEmpty, reason: 'aucun appel avec le jeton de NEMA');
      // Coffre réécrit derrière le dos de l'écran (restauration…) : revérifié à chaque appel.
      c.valeur = _jetonNema(s);
      final m2 = api(s, c, chemins);
      await m2.lier(_emmanuel);
      c.valeur = _jetonNema(s);
      await expectLater(m2.mesPointages(), throwsA(isA<MobileSessionExpiree>()));
      expect(chemins, isEmpty);
    });

    test('même compte : rien n\'est effacé ; sans compte connu : comportement d\'avant', () async {
      final s = FauxServeurPrestige();
      final c = CoffreJetonMemoire(_jetonNema(s));
      final m = api(s, c, []);
      expect(await m.lier('NEMA.demo'), isFalse);
      expect(c.valeur, isNotNull);
      final m2 = api(s, CoffreJetonMemoire(_jetonNema(s)), []);
      expect(await m2.lier(null), isFalse);
      expect(m2.session?.login, _nema);
    });
  });
}

/// Transport espion : note les appels ; réponse fixe ([reponse]).
class _Espion implements TransportMobile {
  final List<String> chemins;
  final FauxServeurPrestige s;
  _Espion(this.chemins, this.s);
  static ReponseHttp reponse = (status: 404, body: null);
  @override
  Future<ReponseHttp> envoyer(String methode, String chemin, {Map<String, dynamic>? corps, String? jeton}) async {
    chemins.add('$methode $chemin');
    return reponse;
  }
}
