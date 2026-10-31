// RÉSEAU — 4.10.2 : ligne d'état Mobile Money de la borne et étape « Module Mobile Money » de « Tester la borne », en
// VRAI HTTP (faux serveur Prestige sur un port local) : connexion d'essai de l'utilisateur borne avec son propre pot à
// cookies, GET v1/paiements-mobile/capacites relu à chaque vérification, GET v1/user/droits, session d'essai fermée ;
// serveur coupé → « injoignable » ; mot de passe faux → « Vérification impossible ».
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_diagnostic.dart';
import 'package:prestige_vente_app/paiements/etat_mobile_money.dart';

import '../outils/faux_serveur_prestige.dart';

const _borne = 'borne.reseau';
const _mdp = 'MotDePasseBorneFictif2';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FauxServeurPrestige srv;
  setUp(() => avecVraiHttp(() async {
        srv = FauxServeurPrestige(comptes: {_borne: _mdp});
        await srv.demarrer();
      }));
  tearDown(() => avecVraiHttp(() => srv.arreter()));

  TesteurBorne testeur([String mdp = _mdp]) => TesteurBorne(baseUrl: srv.base, secrets: MemoireBorneSecrets(mdp), delai: const Duration(seconds: 3));
  const c = BorneConfig(login: _borne);
  int capacites() => srv.recues.where((r) => r.chemin.endsWith('/paiements-mobile/capacites')).length;

  test('chaque état, capacités relues à chaque vérification, session d\'essai fermée', () => avecVraiHttp(() async {
        expect((await testeur().mobileMoney(c, actif: true)).etat, EtatMobileMoney.serveurAncien);
        srv.routes['GET /paiements-mobile/capacites'] = (_) => FauxServeurPrestige.ok({'success': true, 'paiementsMobile': <String>[]});
        expect((await testeur().mobileMoney(c, actif: true)).etat, EtatMobileMoney.sansCompte);
        srv.routes['GET /paiements-mobile/capacites'] = (_) => FauxServeurPrestige.ok({'success': true, 'paiementsMobile': ['wave']});
        srv.droitsComptes = {_borne: ['P_SM_VENTE']};
        final s = await testeur().mobileMoney(c, actif: true);
        expect(s.etat, EtatMobileMoney.sansDroit);
        expect(s.message, contains('« $_borne »'));
        srv.droitsComptes = {_borne: ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE']};
        expect((await testeur().mobileMoney(c, actif: true)).message, 'Proposé au client : Wave.');
        expect(capacites(), 4, reason: 'relues à chaque vérification');
        expect(srv.recuesSur('/user/logout'), hasLength(4), reason: 'session d\'essai fermée à chaque fois');
        expect((await testeur().mobileMoney(c, actif: false)).etat, EtatMobileMoney.desactive);
        expect(capacites(), 4, reason: 'option décochée : aucune requête');
      }));

  test('« Tester la borne » : étape « Module Mobile Money » (attention sans droit, ok quand proposé)', () => avecVraiHttp(() async {
        srv.routes['GET /paiements-mobile/capacites'] = (_) => FauxServeurPrestige.ok({'success': true, 'paiementsMobile': ['orange']});
        srv.droitsComptes = {_borne: ['P_SM_VENTE']};
        final avant = TesteurBorne.mobileMoneyActif;
        TesteurBorne.mobileMoneyActif = () => true;
        addTearDown(() => TesteurBorne.mobileMoneyActif = avant);
        var d = await testeur().tester(c);
        var e = d.etapes.firstWhere((x) => x.titre == titreModuleMobileMoney);
        expect(e.etat, EtatEtapeBorne.attention);
        expect(e.detail, contains('n\'a pas le droit de clôturer'));
        srv.droitsComptes = {_borne: ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE']};
        d = await testeur().tester(c);
        e = d.etapes.firstWhere((x) => x.titre == titreModuleMobileMoney);
        expect(e.etat, EtatEtapeBorne.ok);
        expect(e.detail, 'Proposé au client : Orange Money.');
      }));

  test('serveur coupé : injoignable ; mot de passe faux : vérification impossible', () => avecVraiHttp(() async {
        expect((await testeur('faux').mobileMoney(c, actif: true)).message, startsWith('Vérification impossible : connexion de l\'utilisateur borne'));
        await srv.arreter();
        expect((await testeur().mobileMoney(c, actif: true)).etat, EtatMobileMoney.horsLigne);
      }));
}
