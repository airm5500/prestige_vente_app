// Fiche client (Ordonnances des clients) : lecture tolérante, contrôles des mesures (bornes, décimales, tension,
// date), droits (consultation seule / saisie), client v1/ordonnance-client contre un serveur local, écran.
// Toutes les données sont FICTIVES (aucun vrai patient).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/droits/droits_modules.dart';
import 'package:prestige_vente_app/fiche_client/fiche_client_api.dart';
import 'package:prestige_vente_app/fiche_client/fiche_client_models.dart';
import 'package:prestige_vente_app/fiche_client/fiche_client_validation.dart';
import 'package:prestige_vente_app/fiche_client/ordonnances_clients_screen.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';

import 'outils/serveur_json_local.dart';

const _poids = ParametreClinique(id: 'PARAM_POIDS', code: 'POIDS', libelle: 'Poids', unite: 'kg', decimales: 1, saisieMin: 0.5, saisieMax: 400);
const _tension = ParametreClinique(id: 'PARAM_TENSION', code: 'TENSION', libelle: 'Tension artérielle', unite: 'mmHg', genre: 'tension', saisieMin: 40, saisieMax: 260);
const _glycemie = ParametreClinique(id: 'PARAM_GLY', code: 'GLYCEMIE_JEUN', libelle: 'Glycémie à jeun', unite: 'g/L', decimales: 2);

Map<String, dynamic> _dossier() => {
      'success': true,
      'client': {'id': 'C1', 'nom': 'TEST', 'prenoms': 'Patient Fictif', 'telephone': '0100000000', 'naissance': '1980-01-01', 'age': 46, 'sexe': 'F', 'type': 'STANDARD'},
      'terrains': ['T1', 'T2'],
      'allergies': 'Allergie fictive',
      'parametres': [
        {'parametreId': 'PARAM_POIDS', 'code': 'POIDS', 'libelle': 'Poids', 'unite': 'kg', 'genre': 'simple', 'decimales': 1, 'nbMesures': 2, 'valeur': 72.5, 'date': '2026-10-01', 'etat': 'normal', 'analyse': 'Normale'},
        {'parametreId': 'PARAM_TENSION', 'code': 'TENSION', 'libelle': 'Tension artérielle', 'unite': 'mmHg', 'genre': 'tension', 'decimales': 0, 'nbMesures': 0},
      ],
      'imc': {'valeur': 24.1, 'etat': 'normal', 'analyse': 'Corpulence normale'},
      'nbOrdonnances': 3,
    };

class _FakeApi extends FicheClientApi {
  _FakeApi(this.d) : super(ClientPrestige(() => 'http://127.0.0.1:1/prestige/api/v1'));
  final DroitsOrdonnances d;
  int enregistrements = 0;

  @override
  Future<DroitsOrdonnances> droits() async => d;
  @override
  Future<List<ClientResume>> clients(String recherche, {int limit = 30}) async =>
      [const ClientResume(id: 'C1', nom: 'TEST', prenoms: 'Patient Fictif', telephone: '0100000000', type: 'STANDARD')];
  @override
  Future<DossierClient> dossier(String clientId) async => DossierClient.fromJson(_dossier());
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
  });
}
