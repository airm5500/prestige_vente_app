// Fiche client (Ordonnances des clients) : lecture tolérante, contrôles des mesures (bornes, décimales, tension,
// date), droits (consultation seule / saisie), client v1/ordonnance-client contre un serveur local, écran.
// Toutes les données sont FICTIVES (aucun vrai patient).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/droits/droits_modules.dart';
import 'package:prestige_vente_app/fiche_client/fiche_client_api.dart';
import 'package:prestige_vente_app/fiche_client/fiche_client_models.dart';
import 'package:prestige_vente_app/fiche_client/fiche_client_tab.dart' show FormatDateJJMMAAAA;
import 'package:prestige_vente_app/fiche_client/fiche_client_validation.dart';
import 'package:prestige_vente_app/fiche_client/ordonnances_clients_screen.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/utils/constants.dart';

import 'outils/serveur_json_local.dart';

const _poids = ParametreClinique(id: 'PARAM_POIDS', code: 'POIDS', libelle: 'Poids', unite: 'kg', decimales: 1, saisieMin: 0.5, saisieMax: 400);
const _tension = ParametreClinique(id: 'PARAM_TENSION', code: 'TENSION', libelle: 'Tension artérielle', unite: 'mmHg', genre: 'tension', saisieMin: 40, saisieMax: 260);
const _glycemie = ParametreClinique(id: 'PARAM_GLY', code: 'GLYCEMIE_JEUN', libelle: 'Glycémie à jeun', unite: 'g/L', decimales: 2);

Map<String, dynamic> _dossier({String naissance = '1980-01-01', bool? modifiable}) => {
      'success': true,
      'client': {
        'id': 'C1', 'nom': 'TEST', 'prenoms': 'Patient Fictif', 'telephone': '0100000000', 'naissance': naissance, 'age': naissance.isEmpty ? null : 46, 'sexe': 'F', 'type': 'STANDARD',
        if (modifiable != null) 'naissanceModifiable': modifiable,
      },
      'terrains': ['T1', 'T2'],
      'allergies': 'Allergie fictive',
      'parametres': [
        {'parametreId': 'PARAM_POIDS', 'code': 'POIDS', 'libelle': 'Poids', 'unite': 'kg', 'genre': 'simple', 'decimales': 1, 'nbMesures': 2, 'valeur': 72.5, 'date': '2026-10-01', 'etat': 'normal', 'analyse': 'Normale'},
        {'parametreId': 'PARAM_TENSION', 'code': 'TENSION', 'libelle': 'Tension artérielle', 'unite': 'mmHg', 'genre': 'tension', 'decimales': 0, 'nbMesures': 0},
      ],
      'imc': {'valeur': 24.1, 'etat': 'normal', 'analyse': 'Corpulence normale'},
      'nbOrdonnances': 3,
    };

/// 4.6.1 : note les clés X-Client-Ref des mesures ; le premier envoi se perd (résultat incertain).
class _FakeApiCles extends _FakeApi {
  _FakeApiCles() : super(const DroitsOrdonnances(consulter: true, modifier: true));
  final List<(String?, double?)> cles = [];
  @override
  Future<String> ajouterMesure(String clientId, SaisieMesure saisie, {String? cle}) async {
    cles.add((cle, saisie.toJson()['valeur'] as double?));
    if (cles.length == 1) throw const ServeurInjoignable(delai: true, resultatIncertain: true);
    return 'Mesure enregistrée.';
  }
}

class _FakeApi extends FicheClientApi {
  _FakeApi(this.d, {this.naissance = '1980-01-01', this.modifiable}) : super(ClientPrestige(() => 'http://127.0.0.1:1/prestige/api/v1'));

  /// 4.10.2 : capacité `naissanceModifiable` du dossier (null = absente, serveur ancien) ; corrections envoyées.
  final bool? modifiable;
  final List<DateTime?> modifications = [];

  @override
  Future<String> modifierNaissance(String clientId, DateTime? n) async {
    modifications.add(n);
    naissance = n == null ? '' : '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    return n == null ? 'Date de naissance effacée.' : 'Date de naissance modifiée.';
  }
  final DroitsOrdonnances d;
  int enregistrements = 0;

  /// 4.10.1 : date de naissance du dossier fictif ('' = absente) ; dates envoyées par « Ajouter ».
  String naissance;
  final List<DateTime> naissancesEnvoyees = [];

  @override
  Future<String> completerNaissance(String clientId, DateTime n) async {
    naissancesEnvoyees.add(n);
    naissance = '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    return 'Fiche complétée : date de naissance.';
  }

  @override
  Future<DroitsOrdonnances> droits() async => d;
  @override
  Future<List<ClientResume>> clients(String recherche, {int limit = 30}) async =>
      [const ClientResume(id: 'C1', nom: 'TEST', prenoms: 'Patient Fictif', telephone: '0100000000', type: 'STANDARD', naissance: '1980-01-01', sexe: 'F')];
  @override
  Future<List<LigneConsommation>> consommation(String clientId) async => const [
        LigneConsommation(cip: '0000001', nom: 'PRODUIT FICTIF A 500MG B/16', dernierAchat: '2026-10-01', nbAchats: 4, qteTotale: 6, frequenceJours: 30, montant: 12600, habitude: 'Mensuel', stock: 12),
        LigneConsommation(cip: '0000002', nom: 'PRODUIT FICTIF B SIROP', dernierAchat: '2026-02-11', nbAchats: 1, qteTotale: 1, montant: 2350, habitude: 'Dormant', stock: 0),
      ];
  @override
  Future<DossierClient> dossier(String clientId) async => DossierClient.fromJson(_dossier(naissance: naissance, modifiable: modifiable));
  @override
  Future<List<TerrainClinique>> terrains() async => const [TerrainClinique(id: 'T1', libelle: 'Diabète'), TerrainClinique(id: 'T2', libelle: 'Pénicilline', allergie: true)];
  @override
  Future<List<ParametreClinique>> parametres() async => const [_poids, _tension];
  @override
  Future<String> enregistrerDossier(String clientId, {required String allergies, required List<String> terrains}) async {
    enregistrements++;
    return 'Dossier du client enregistré.';
  }
}

Future<void> _taille(WidgetTester t, Size s) async {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
}

void main() {
  group('modèles', () {
    test('dossier complet et dossier dégradé (champs manquants, nuls, types inattendus)', () {
      final d = DossierClient.fromJson(_dossier());
      expect(d.client.nomComplet, 'TEST Patient Fictif');
      expect(d.client.age, 46);
      expect(d.terrains, ['T1', 'T2']);
      expect(formaterParametre(d.parametres.first), '72,5 kg');
      expect(formaterParametre(d.parametres[1]), 'Non mesuré');
      expect(d.imc!.valeur, 24.1);
      final v = DossierClient.fromJson({'client': 'x', 'terrains': [null, 3], 'parametres': [{'parametreId': ''}, {'parametreId': 'P', 'decimales': 9, 'valeur': '12,5'}], 'imc': {}});
      expect(v.client.id, '');
      expect(v.terrains, ['3']);
      expect(v.parametres.single.decimales, 3);
      expect(v.parametres.single.valeur, 12.5);
      expect(v.imc, isNull);
      expect(ClientResume.fromJson({'lgCLIENTID': 'X', 'libelleTypeClient': null, 'typeClient': 'Carnet'}).type, 'Carnet');
      expect(TerrainClinique.fromJson({'id': 'A', 'categorie': 'ALLERGIE'}).allergie, isTrue);
      expect(ParametreClinique.fromJson({'id': 'P', 'genre': 'Tension', 'saisieMin': '40'}).tension, isTrue);
      expect(LigneConsommation.fromJson({'name': 'PRODUIT', 'stock': null}).stock, isNull);
    });
  });

  group('contrôles de saisie', () {
    test('bornes : intersection Prestige / plausibles ; décimales ; nombres', () {
      expect(bornes(_poids), (0.5, 350.0), reason: '400 kg du référentiel resserré à 350');
      expect(bornes(_glycemie), (0.2, 6.0), reason: 'bornes plausibles si Prestige n\'en a pas');
      expect(bornes(const ParametreClinique(id: 'X', libelle: 'Autre')), (null, null));
      expect(validerValeur('72,5', _poids), isNull);
      expect(validerValeur('72.5', _poids), isNull);
      expect(validerValeur('72,55', _poids), contains('1 décimale'));
      expect(validerValeur('', _poids), contains('obligatoire'));
      expect(validerValeur('abc', _poids), contains('nombre'));
      expect(validerValeur('-3', _poids), contains('nombre'));
      expect(validerValeur('500', _poids), contains('trop haut'));
      expect(validerValeur('0,2', _poids), contains('trop bas'));
      expect(validerValeur('1,26', _glycemie), isNull);
      expect(validerValeur('12', _glycemie), contains('g/L'));
      expect(validerValeur('120,5', _tension), contains('entier'));
      expect(validerValeur('0', const ParametreClinique(id: 'X', libelle: 'Autre')), contains('supérieure à 0'));
      expect(lireNombre(' 1,5 '), 1.5);
    });

    test('tension : au moins un bras, systolique ET diastolique, diastolique < systolique', () {
      final now = DateTime(2026, 10, 13, 10);
      SaisieMesure m({String sg = '', String dg = '', String sd = '', String dd = ''}) =>
          SaisieMesure(parametre: _tension, date: now, systoliqueG: sg, diastoliqueG: dg, systoliqueD: sd, diastoliqueD: dd);
      expect(m().erreurs(maintenant: now), contains(contains('au moins un bras')));
      expect(m(sg: '130').erreurs(maintenant: now), contains(contains('systolique ET la diastolique')));
      expect(m(sg: '80', dg: '120').erreurs(maintenant: now), contains(contains('inférieure à la systolique')));
      expect(m(sg: '300', dg: '80').erreurs(maintenant: now), contains(contains('trop haut')));
      expect(m(sg: '130', dg: '80').erreurs(maintenant: now), isEmpty);
      expect(m(sg: '130', dg: '80', sd: '125', dd: '82').toJson(), {
        'parametreId': 'PARAM_TENSION',
        'date': '2026-10-13T10:00',
        'gauche': {'systolique': 130.0, 'diastolique': 80.0},
        'droite': {'systolique': 125.0, 'diastolique': 82.0},
      });
    });

    test('date : ni future ni trop ancienne ; commentaire et allergies bornés', () {
      final now = DateTime(2026, 10, 13, 10);
      expect(validerDateMesure(now.add(const Duration(hours: 1)), maintenant: now), isNotNull);
      expect(validerDateMesure(DateTime(1999), maintenant: now), isNotNull);
      expect(validerDateMesure(now.subtract(const Duration(days: 3)), maintenant: now), isNull);
      final long = SaisieMesure(parametre: _poids, date: now, valeur: '70', commentaire: 'x' * 201);
      expect(long.erreurs(maintenant: now), contains(contains('200 caractères')));
      expect(SaisieMesure(parametre: _poids, date: now, valeur: '70,4', commentaire: ' ok ').toJson(),
          {'parametreId': 'PARAM_POIDS', 'date': '2026-10-13T10:00', 'commentaire': 'ok', 'valeur': 70.4});
      expect(validerAllergies('a' * 2001), isNotNull);
      expect(validerAllergies('a' * 2000), isNull);
    });
  });

  group('date de naissance (4.10.1)', () {
    test('JJ/MM/AAAA : illisible, inexistante, à venir, avant 1900 refusées (comme le serveur) ; date lue', () {
      final now = DateTime(2026, 10, 31, 9);
      expect(validerNaissance('', maintenant: now), contains('Saisissez'));
      expect(validerNaissance('1985-03-02', maintenant: now), contains('JJ/MM/AAAA'));
      expect(validerNaissance('31/02/1985', maintenant: now), contains('n\'existe pas'));
      expect(validerNaissance('01/11/2026', maintenant: now), contains('futur'));
      expect(validerNaissance('31/10/2026', maintenant: now), isNull, reason: 'aujourd\'hui accepté');
      expect(validerNaissance('31/12/1899', maintenant: now), contains('1900'));
      expect(lireNaissance(' 02/03/1985 ', maintenant: now), DateTime(1985, 3, 2));
      expect(validerNaissance('30/10/1895', maintenant: DateTime(2027, 1, 1)), contains('130 ans'), reason: '4.10.2 : AGE_MAX du serveur');
      expect(lireNaissance('29/02/2001', maintenant: now), isNull);
      expect(dateClientFr('1985-03-02'), '02/03/1985');
    });

    test('saisie au clavier : chiffres seulement, « / » ajoutés, 8 chiffres au plus', () {
      final f = FormatDateJJMMAAAA();
      TextEditingValue v(String t) => f.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: t));
      expect(v('02').text, '02');
      expect(v('023').text, '02/3');
      expect(v('02031985').text, '02/03/1985');
      expect(v('02/03/19851').text, '02/03/1985');
      expect(v('ab0-2').text, '02');
    });
  });

  group('client v1/ordonnance-client', () {
    late ServeurJsonLocal srv;
    late FicheClientApi api;
    setUp(() => avecVraiHttp(() async {
          srv = ServeurJsonLocal();
          await srv.demarrer();
          api = FicheClientApi(ClientPrestige(() => srv.base, delaiReponse: const Duration(milliseconds: 500)));
        }));
    tearDown(() => avecVraiHttp(() => srv.arreter()));

    test('droits, recherche, dossier, enregistrement du dossier, mesures', () => avecVraiHttp(() async {
          srv.routes['GET /ordonnance-client/droits'] = (_) => const ReponseLocale({'success': true, 'consulter': true, 'modifier': true});
          srv.routes['GET /ordonnance-client/clients'] = (_) => const ReponseLocale({
                'success': true,
                'data': [
                  {'lgCLIENTID': 'C1', 'strFIRSTNAME': 'TEST', 'strLASTNAME': 'Patient Fictif'}
                ]
              });
          srv.routes['GET /client/C1/dossier'] = (_) => ReponseLocale(_dossier());
          srv.routes['POST /client/C1/dossier'] = (_) => const ReponseLocale({'success': true, 'message': 'Dossier du client enregistré.'});
          srv.routes['POST /client/C1/mesures'] = (_) => const ReponseLocale({'success': true, 'nombre': 1, 'message': 'Mesure enregistrée.'});
          srv.routes['GET /client/C1/mesures'] = (_) => const ReponseLocale({
                'success': true,
                'data': [
                  {'id': 'M1', 'valeur': 72.5, 'date': '2026-10-01 08:00'}
                ]
              });
          expect((await api.droits()).modifier, isTrue);
          expect(await api.clients('T'), isEmpty, reason: 'moins de 2 caractères : pas d\'appel');
          expect((await api.clients('TE')).single.id, 'C1');
          expect(srv.recuesSur('/clients').single.query['query'], 'TE');
          expect((await api.dossier('C1')).nbOrdonnances, 3);
          await api.enregistrerDossier('C1', allergies: ' Allergie fictive ', terrains: ['T1']);
          expect(srv.recuesSur('/dossier').last.json, {'allergies': 'Allergie fictive', 'terrains': ['T1']});
          await api.ajouterMesure('C1', SaisieMesure(parametre: _poids, date: DateTime(2026, 10, 1, 8), valeur: '72,5'));
          expect(srv.recuesSur('/mesures').last.json, {'parametreId': 'PARAM_POIDS', 'date': '2026-10-01T08:00', 'valeur': 72.5});
          expect((await api.mesures('C1', 'PARAM_POIDS')).single.valeur, 72.5);
          expect(srv.recuesSur('/mesures').last.query['parametreId'], 'PARAM_POIDS');
        }));

    test('saisie invalide refusée sans appel ; refus de droit (HTTP 200) ; 401 ; délai d\'une mesure = incertain', () => avecVraiHttp(() async {
          await expectLater(api.ajouterMesure('C1', SaisieMesure(parametre: _poids, date: DateTime(2026, 10, 1), valeur: '900')), throwsA(isA<RefusMetier>()));
          await expectLater(api.enregistrerDossier('C1', allergies: 'a' * 2001, terrains: const []), throwsA(isA<RefusMetier>()));
          expect(srv.recues, isEmpty);
          srv.routes['POST /client/C1/dossier'] =
              (_) => const ReponseLocale({'success': false, 'total': 0, 'message': 'Votre profil ne permet pas de saisir ou de modifier une ordonnance.'});
          await expectLater(api.enregistrerDossier('C1', allergies: '', terrains: const []),
              throwsA(isA<RefusMetier>().having((e) => e.message, 'message', contains('ne permet pas de saisir'))));
          srv.routes['GET /client/C1/dossier'] = (_) => const ReponseLocale('Veuillez vous connecter', statut: 401);
          await expectLater(api.dossier('C1'), throwsA(isA<SessionExpiree>()));
          srv.routes['POST /client/C1/mesures'] = (_) => const ReponseLocale({'success': true}, delai: Duration(seconds: 2));
          await expectLater(api.ajouterMesure('C1', SaisieMesure(parametre: _poids, date: DateTime(2026, 10, 1), valeur: '70')),
              throwsA(isA<ServeurInjoignable>().having((e) => e.resultatIncertain, 'incertain', isTrue)));
          expect(srv.recuesSur('/mesures'), hasLength(1));
        }));

    // 4.6.1 (demande 19, serveur aa4e2390) : X-Client-Ref sur POST mesures.
    test('X-Client-Ref envoyé avec la clé de la saisie ; sans clé : aucun en-tête (comme avant)', () => avecVraiHttp(() async {
          srv.routes['POST /client/C1/mesures'] = (_) => const ReponseLocale({'success': true, 'message': 'Mesure enregistrée.'});
          await api.ajouterMesure('C1', SaisieMesure(parametre: _poids, date: DateTime(2026, 10, 1, 8), valeur: '70'), cle: 'FM-essai-1');
          expect(srv.recuesSur('/mesures').last.clientRef, 'FM-essai-1');
          await api.ajouterMesure('C1', SaisieMesure(parametre: _poids, date: DateTime(2026, 10, 1, 8), valeur: '70'));
          expect(srv.recuesSur('/mesures').last.clientRef, isEmpty);
          expect(FicheClientApi.nouvelleCle(), startsWith('FM-'));
          expect(FicheClientApi.nouvelleCle().length, lessThanOrEqualTo(64));
          expect(FicheClientApi.nouvelleCle(), isNot(FicheClientApi.nouvelleCle()));
        }));

    // 4.10.1 : POST client/{id}/identite (serveur a2bb8cc8 du 13/10) : complète la date absente, sans écrasement.
    test('date de naissance : AAAA-MM-JJ envoyée ; « Déjà renseigné » ; serveur ancien (404) ; date à venir sans appel', () => avecVraiHttp(() async {
          srv.routes['POST /client/C1/identite'] = (_) => const ReponseLocale({'success': true, 'message': 'Fiche complétée : date de naissance.'});
          expect(await api.completerNaissance('C1', DateTime(1985, 3, 2)), 'Fiche complétée : date de naissance.');
          expect(srv.recuesSur('/identite').single.json, {'naissance': '1985-03-02'});
          srv.routes['POST /client/C1/identite'] = (_) => const ReponseLocale({'success': false, 'message': 'Déjà renseigné : la fiche n\'a pas été modifiée.'});
          await expectLater(api.completerNaissance('C1', DateTime(1985, 3, 2)), throwsA(isA<RefusMetier>().having((e) => e.message, 'message', startsWith('Déjà renseigné'))));
          srv.routes.remove('POST /client/C1/identite');
          await expectLater(api.completerNaissance('C1', DateTime(1985, 3, 2)), throwsA(isA<ErreurHttp>().having((e) => e.status, 'status', 404)));
          final avant = srv.recues.length;
          await expectLater(api.completerNaissance('C1', DateTime.now().add(const Duration(days: 2))), throwsA(isA<RefusMetier>()));
          expect(srv.recues.length, avant, reason: 'aucun appel pour une date à venir');
        }));

    // 4.10.2 (demande 58, serveur b5020735) : remplacer / effacer, refus en HTTP 200, capacité du dossier.
    test('modifier : {naissance, remplacer:true} ; effacer : naissance vide ; refus du serveur ; capacité lue', () => avecVraiHttp(() async {
          srv.routes['POST /client/C1/identite'] = (r) => ReponseLocale({
                'success': true,
                'message': r.json['naissance'] == '' ? 'Date de naissance effacée.' : 'Date de naissance modifiée.',
                'naissance': r.json['naissance'],
              });
          expect(await api.modifierNaissance('C1', DateTime(1979, 12, 31)), 'Date de naissance modifiée.');
          expect(srv.recuesSur('/identite').last.json, {'naissance': '1979-12-31', 'remplacer': true});
          expect(await api.modifierNaissance('C1', null), 'Date de naissance effacée.');
          expect(srv.recuesSur('/identite').last.json, {'naissance': '', 'remplacer': true});
          srv.routes['POST /client/C1/identite'] = (_) => const ReponseLocale({'success': false, 'message': 'Client introuvable.'});
          await expectLater(api.modifierNaissance('C1', DateTime(1979, 12, 31)), throwsA(isA<RefusMetier>().having((e) => e.message, 'message', 'Client introuvable.')));
          final avant = srv.recues.length;
          await expectLater(api.modifierNaissance('C1', DateTime.now().add(const Duration(days: 3))), throwsA(isA<RefusMetier>()));
          expect(srv.recues.length, avant);
          expect(DossierClient.fromJson(_dossier(modifiable: true)).client.naissanceModifiable, isTrue);
          expect(DossierClient.fromJson(_dossier()).client.naissanceModifiable, isFalse, reason: 'absente : serveur ancien');
        }));
  });

  group('écran', () {
    Future<void> ouvrirDossier(WidgetTester t, _FakeApi api) async {
      await t.pumpWidget(MaterialApp(home: OrdonnancesClientsScreen(api: api)));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('fiche-recherche')), 'TEST');
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('fiche-client-C1')));
      await t.pumpAndSettle();
    }

    testWidgets('4.10.1 : date absente + droit de saisie → « Ajouter » ; date à venir refusée ; JJ/MM/AAAA envoyée et affichée', (t) async {
      await _taille(t, const Size(720, 1440));
      final api = _FakeApi(const DroitsOrdonnances(consulter: true, modifier: true), naissance: '');
      await ouvrirDossier(t, api);
      await t.tap(find.byKey(const ValueKey('fiche-ajouter-naissance')));
      await t.pumpAndSettle();
      final demain = DateTime.now().add(const Duration(days: 1));
      String deux(int v) => v.toString().padLeft(2, '0');
      await t.enterText(find.byKey(const ValueKey('fiche-naissance-champ')), '${deux(demain.day)}${deux(demain.month)}${demain.year}');
      await t.tap(find.byKey(const ValueKey('fiche-naissance-enregistrer')));
      await t.pumpAndSettle();
      expect(find.textContaining('futur'), findsOneWidget);
      expect(api.naissancesEnvoyees, isEmpty);
      await t.enterText(find.byKey(const ValueKey('fiche-naissance-champ')), '02031985');
      await t.pump();
      expect(t.widget<TextField>(find.byKey(const ValueKey('fiche-naissance-champ'))).controller!.text, '02/03/1985');
      await t.tap(find.byKey(const ValueKey('fiche-naissance-enregistrer')));
      await t.pumpAndSettle();
      expect(api.naissancesEnvoyees, [DateTime(1985, 3, 2)]);
      expect(find.text('Fiche complétée : date de naissance.'), findsOneWidget);
      expect(find.byKey(const ValueKey('fiche-ajouter-naissance')), findsNothing, reason: 'date désormais renseignée');
      expect(find.textContaining('02/03/1985'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('4.10.2 : date présente + capacité → « Modifier » (date pré-remplie) puis « Effacer » confirmé', (t) async {
      await _taille(t, const Size(720, 1440));
      final api = _FakeApi(const DroitsOrdonnances(consulter: true, modifier: true), modifiable: true);
      await ouvrirDossier(t, api);
      await t.tap(find.byKey(const ValueKey('fiche-modifier-naissance')));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byKey(const ValueKey('fiche-naissance-champ'))).controller!.text, '01/01/1980');
      await t.enterText(find.byKey(const ValueKey('fiche-naissance-champ')), '31121979');
      await t.tap(find.byKey(const ValueKey('fiche-naissance-enregistrer')));
      await t.pumpAndSettle();
      expect(api.modifications, [DateTime(1979, 12, 31)]);
      expect(find.text('Date de naissance modifiée.'), findsOneWidget);
      expect(find.textContaining('31/12/1979'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('fiche-effacer-naissance')));
      await t.pumpAndSettle();
      expect(find.text('Effacer la date de naissance ?'), findsOneWidget);
      await t.tap(find.text('Annuler'));
      await t.pumpAndSettle();
      expect(api.modifications, hasLength(1), reason: 'annulé : rien envoyé');
      await t.tap(find.byKey(const ValueKey('fiche-effacer-naissance')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('fiche-effacer-naissance-confirmer')));
      await t.pumpAndSettle();
      expect(api.modifications.last, isNull);
      expect(find.text('Date de naissance effacée.'), findsOneWidget);
      expect(find.byKey(const ValueKey('fiche-ajouter-naissance')), findsOneWidget, reason: 'date absente : « Ajouter »');
      expect(t.takeException(), isNull);
    });

    for (final cap in [false, null]) {
      testWidgets('4.10.2 : capacité ${cap == null ? 'absente (serveur ancien)' : 'fausse'} → ni « Modifier » ni « Effacer »', (t) async {
        await _taille(t, const Size(720, 1440));
        await ouvrirDossier(t, _FakeApi(const DroitsOrdonnances(consulter: true, modifier: true), modifiable: cap));
        expect(find.byKey(const ValueKey('fiche-modifier-naissance')), findsNothing);
        expect(find.byKey(const ValueKey('fiche-effacer-naissance')), findsNothing);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('4.10.1 : date présente → JJ/MM/AAAA, pas de bouton', (t) async {
      await _taille(t, const Size(720, 1440));
      await ouvrirDossier(t, _FakeApi(const DroitsOrdonnances(consulter: true, modifier: true)));
      expect(find.text('01/01/1980 · 46 ans'), findsOneWidget);
      expect(find.byKey(const ValueKey('fiche-ajouter-naissance')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('4.10.1 : date absente en consultation seule → pas de bouton', (t) async {
      await _taille(t, const Size(720, 1440));
      await ouvrirDossier(t, _FakeApi(const DroitsOrdonnances(consulter: true, modifier: false), naissance: ''));
      expect(find.byKey(const ValueKey('fiche-ajouter-naissance')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('sans droit de consultation : message, aucune recherche', (t) async {
      await _taille(t, const Size(720, 1440));
      await t.pumpWidget(MaterialApp(home: OrdonnancesClientsScreen(api: _FakeApi(const DroitsOrdonnances(consulter: false, modifier: false)))));
      await t.pumpAndSettle();
      expect(find.text('Votre profil ne donne pas accès aux ordonnances des clients.'), findsOneWidget);
      expect(find.byKey(const ValueKey('fiche-recherche')), findsNothing);
    });

    testWidgets('consultation seule : dossier affiché, aucun bouton de saisie (Sunmi 720×1440)', (t) async {
      await _taille(t, const Size(720, 1440));
      await ouvrirDossier(t, _FakeApi(const DroitsOrdonnances(consulter: true, modifier: false)));
      expect(find.text('Consultation seule'), findsOneWidget);
      expect(find.text('Fiche client'), findsOneWidget);
      expect(find.text('Allergie fictive'), findsOneWidget);
      expect(find.text('Pénicilline'), findsOneWidget);
      expect(find.byKey(const ValueKey('fiche-modifier-dossier')), findsNothing);
      expect(find.byKey(const ValueKey('fiche-ajouter-mesure')), findsNothing);
      await t.scrollUntilVisible(find.text('72,5 kg'), 200);
      expect(find.text('72,5 kg'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('saisie autorisée : allergies et terrains enregistrés ; mesure hors bornes refusée avant envoi (tablette)', (t) async {
      await _taille(t, const Size(2048, 1536));
      final api = _FakeApi(const DroitsOrdonnances(consulter: true, modifier: true));
      await ouvrirDossier(t, api);
      expect(find.text('Consultation et saisie'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('fiche-modifier-dossier')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilterChip, 'Diabète'));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('fiche-enregistrer-dossier')));
      await t.pumpAndSettle();
      expect(api.enregistrements, 1);
      await t.tap(find.byKey(const ValueKey('fiche-ajouter-mesure')));
      await t.pumpAndSettle();
      expect(find.text('kg'), findsWidgets, reason: 'unité affichée');
      expect(find.textContaining('entre 0,5 et 350,0'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('fiche-valeur')), '900');
      await t.tap(find.byKey(const ValueKey('fiche-enregistrer-mesure')));
      await t.pumpAndSettle();
      expect(find.textContaining('paraît trop haut'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('4.6.1 : réponse perdue puis renvoi de la même saisie = même clé ; saisie modifiée = nouvelle clé', (t) async {
      await _taille(t, const Size(2048, 1536));
      final api = _FakeApiCles();
      await ouvrirDossier(t, api);
      await t.tap(find.byKey(const ValueKey('fiche-ajouter-mesure')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('fiche-valeur')), '70');
      await t.tap(find.byKey(const ValueKey('fiche-enregistrer-mesure')));
      await t.pumpAndSettle();
      expect(find.textContaining('a peut-être été enregistrée'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('fiche-enregistrer-mesure')));
      await t.pumpAndSettle();
      expect(api.cles, hasLength(2));
      expect(api.cles[0].$1, startsWith('FM-'));
      expect(api.cles[1].$1, api.cles[0].$1, reason: 'même saisie renvoyée : même clé (pas de doublon sur un serveur à jour)');
      // Nouvelle fiche : la saisie suivante (autre valeur) a sa propre clé.
      await t.tap(find.byKey(const ValueKey('fiche-ajouter-mesure')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('fiche-valeur')), '71');
      await t.tap(find.byKey(const ValueKey('fiche-enregistrer-mesure')));
      await t.pumpAndSettle();
      expect(api.cles, hasLength(3));
      expect(api.cles[2].$1, isNot(api.cles[0].$1));
      expect(t.takeException(), isNull);
    });

    // 4.4.0 — demande du pharmacien : curseur, « Changer », lignes de résultats, consommation.
    testWidgets('curseur dans la recherche à l\'ouverture ; « Changer » : curseur revenu, texte présélectionné', (t) async {
      await _taille(t, const Size(720, 1440));
      await t.pumpWidget(MaterialApp(home: OrdonnancesClientsScreen(api: _FakeApi(const DroitsOrdonnances(consulter: true, modifier: false)))));
      await t.pumpAndSettle();
      EditableText champ() => t.widget<EditableText>(find.descendant(of: find.byKey(const ValueKey('fiche-recherche')), matching: find.byType(EditableText)));
      expect(champ().focusNode.hasFocus, isTrue, reason: 'curseur automatique à l\'ouverture');
      // Saisie au clavier (sans toucher le champ) puis choix du client.
      t.testTextInput.enterText('TEST');
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('fiche-client-C1')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('fiche-recherche')), findsNothing);
      await t.tap(find.byKey(const ValueKey('fiche-changer')));
      await t.pumpAndSettle();
      expect(champ().focusNode.hasFocus, isTrue, reason: 'curseur remis dans le champ');
      expect(champ().controller.text, 'TEST');
      expect(champ().controller.selection, const TextSelection(baseOffset: 0, extentOffset: 4), reason: 'texte présélectionné');
      // Une frappe remplace la sélection.
      t.testTextInput.enterText('AUTRE');
      await t.pump();
      expect(champ().controller.text, 'AUTRE');
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
    });

    for (final (nom, taille, echelle) in [('Sunmi V2s', const Size(720, 1440), 1.0), ('téléphone 360', const Size(720, 1280), 1.3)]) {
      testWidgets('ligne de résultat ($nom, texte ×$echelle) : initiales, nom, téléphone, type, âge, sexe — sans débordement', (t) async {
        await _taille(t, taille);
        t.platformDispatcher.textScaleFactorTestValue = echelle;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await t.pumpWidget(MaterialApp(home: OrdonnancesClientsScreen(api: _FakeApi(const DroitsOrdonnances(consulter: true, modifier: false)))));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const ValueKey('fiche-recherche')), 'TEST');
        await t.pump(const Duration(milliseconds: 500));
        await t.pumpAndSettle();
        final ligne = find.byKey(const ValueKey('fiche-client-C1'));
        Finder dans(String s) => find.descendant(of: ligne, matching: find.text(s));
        expect(dans('TP'), findsOneWidget, reason: 'initiales');
        expect(dans('TEST Patient Fictif'), findsOneWidget);
        expect(dans('0100000000'), findsOneWidget);
        expect(dans('STANDARD'), findsOneWidget);
        expect(dans('${ageClient('1980-01-01', DateTime.now())} ans'), findsOneWidget);
        expect(dans('Femme'), findsOneWidget);
        expect(find.text('1 client trouvé'), findsOneWidget);
        expect(t.getSize(ligne).height, greaterThanOrEqualTo(48), reason: 'cible tactile');
        expect(t.takeException(), isNull);
      });

      testWidgets('consommation ($nom, texte ×$echelle) : synthèse, montants alignés à droite, rythme, dernier achat, habitude, stock', (t) async {
        await _taille(t, taille);
        t.platformDispatcher.textScaleFactorTestValue = echelle;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await ouvrirDossier(t, _FakeApi(const DroitsOrdonnances(consulter: true, modifier: false)));
        await t.scrollUntilVisible(find.byKey(const ValueKey('fiche-conso')), 200);
        await t.tap(find.byKey(const ValueKey('fiche-conso')));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(find.byKey(const ValueKey('fiche-conso-ligne-1')), 200);
        final resume = find.byKey(const ValueKey('fiche-conso-resume'));
        expect(find.descendant(of: resume, matching: find.text('2')), findsOneWidget, reason: '2 produits');
        expect(find.descendant(of: resume, matching: find.text('5')), findsOneWidget, reason: '5 achats');
        expect(find.descendant(of: resume, matching: find.text('7')), findsOneWidget, reason: '7 boîtes');
        expect(find.byKey(const ValueKey('fiche-conso-total')), findsOneWidget);
        expect(t.widget<Text>(find.byKey(const ValueKey('fiche-conso-total'))).data, contains('14'));
        final l0 = find.byKey(const ValueKey('fiche-conso-ligne-0')), l1 = find.byKey(const ValueKey('fiche-conso-ligne-1'));
        expect(find.descendant(of: l0, matching: find.text('4 achats · 6 boîtes')), findsOneWidget);
        expect(find.descendant(of: l0, matching: find.textContaining('tous les 30 j', findRichText: true)), findsOneWidget);
        expect(find.descendant(of: l0, matching: find.textContaining('dernier le 01/10/2026', findRichText: true)), findsOneWidget);
        expect(find.descendant(of: l0, matching: find.text('Mensuel')), findsOneWidget);
        expect(find.descendant(of: l0, matching: find.text('Stock 12')), findsOneWidget);
        expect(find.descendant(of: l1, matching: find.text('1 achat · 1 boîte')), findsOneWidget);
        expect(find.descendant(of: l1, matching: find.textContaining('tous les', findRichText: true)), findsNothing, reason: 'pas de rythme sur un seul achat');
        // Montants alignés à droite : même bord droit pour les deux lignes.
        final m0 = find.descendant(of: l0, matching: find.text('${Constants.formatNumber(12600)} F'));
        final m1 = find.descendant(of: l1, matching: find.text('${Constants.formatNumber(2350)} F'));
        expect((t.getTopRight(m0).dx - t.getTopRight(m1).dx).abs(), lessThan(1), reason: 'montants alignés');
        expect(t.getTopRight(m0).dx, closeTo(t.getTopRight(l0).dx, 1));
        expect(t.takeException(), isNull);
      });
    }
  });

  group('présentation', () {
    test('âge, date, sexe, initiales, rythme, synthèse', () {
      final now = DateTime(2026, 10, 16);
      expect(ageClient('1980-10-16', now), 46);
      expect(ageClient('1980-10-17', now), 45, reason: 'anniversaire pas encore passé');
      expect(ageClient('17/10/1980', now), 45);
      expect(ageClient('', now), isNull);
      expect(ageClient('n/a', now), isNull);
      expect(ageClient('2030-01-01', now), isNull, reason: 'date future');
      expect(ageClient('1980-02-31', now), isNull, reason: 'date impossible');
      expect(dateClientFr('2026-03-05'), '05/03/2026');
      expect(dateClientFr('2026-03-05T10:00:00'), '05/03/2026');
      expect(dateClientFr('hier'), 'hier');
      expect(sexeLisible('f'), 'Femme');
      expect(sexeLisible('H'), 'Homme');
      expect(sexeLisible(''), '');
      expect(initialesClient(const ClientResume(id: '1', nom: 'TEST', prenoms: 'Patient Fictif')), 'TP');
      expect(initialesClient(const ClientResume(id: '1', nom: 'éLODIE')), 'É');
      expect(initialesClient(const ClientResume(id: '1', nom: '')), '?');
      expect(rythmeAchat(const LigneConsommation(nom: 'X', nbAchats: 3, frequenceJours: 15)), 'tous les 15 j');
      expect(rythmeAchat(const LigneConsommation(nom: 'X', nbAchats: 1, frequenceJours: 0)), '');
      final r = resumeConsommation(const [LigneConsommation(nom: 'A', nbAchats: 2, qteTotale: 3, montant: 100), LigneConsommation(nom: 'B', nbAchats: 1, qteTotale: 1, montant: 50)]);
      expect((r.produits, r.achats, r.boites, r.montant), (2, 3, 4, 150));
    });
  });
}
