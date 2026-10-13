// Droits des menus « Réserve » (administrateur + droit dédié) et « Ordonnances des clients »
// (P_ORDONNANCE_CLIENT / _MAJ) : règles, lecture sur le serveur, menus visibles ou masqués dans l'accueil.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/droits/droits_modules.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';

import 'outils/serveur_json_local.dart';

List<String> _ids() => orderedMenus(const []).map((m) => m.id).toList();

void main() {
  tearDown(() => DroitsModules.instance.oublier());

  group('règles', () {
    test('menu Réserve : administrateur local, administrateur serveur ou droit dédié ; sinon masqué', () {
      expect(menuReserveVisible(adminLocal: false), isFalse);
      expect(menuReserveVisible(adminLocal: false, adminServeur: false, droitDedie: false), isFalse);
      expect(menuReserveVisible(adminLocal: true), isTrue);
      expect(menuReserveVisible(adminLocal: false, adminServeur: true), isTrue);
      expect(menuReserveVisible(adminLocal: false, droitDedie: true), isTrue);
    });

    test('ordonnances : consulter pour voir, consulter ET modifier pour saisir', () {
      expect(menuOrdonnancesVisible(null), isFalse);
      expect(menuOrdonnancesVisible(const DroitsOrdonnances(consulter: true, modifier: false)), isTrue);
      expect(saisieFicheClientAutorisee(const DroitsOrdonnances(consulter: true, modifier: false)), isFalse);
      expect(saisieFicheClientAutorisee(const DroitsOrdonnances(consulter: true, modifier: true)), isTrue);
      // modifier sans consulter (réponse incohérente) : aucune saisie
      expect(DroitsOrdonnances.fromJson({'consulter': false, 'modifier': true}).modifier, isFalse);
      expect(DroitsOrdonnances.fromJson({'consulter': 'true', 'modifier': 1}).modifier, isTrue);
      expect(DroitsOrdonnances.fromJson({}).consulter, isFalse);
    });
  });

  group('menus de l\'accueil', () {
    test('sans droit : Réserve et Ordonnances des clients absents ; Analyse posologie présent', () {
      DroitsModules.instance.fixer();
      final ids = _ids();
      expect(ids, isNot(contains('reserve')));
      expect(ids, isNot(contains('ordonnances_clients')));
      expect(ids, contains('posos'));
      // les menus d'origine ne bougent pas
      for (final id in ['prevente', 'assurance', 'carnet', 'stock', 'search', 'pointage_rh']) {
        expect(ids, contains(id));
      }
      expect(menusByFamille(const [], const [])[MenuFamille.stock]!.map((m) => m.id), isNot(contains('reserve')));
    });

    test('administrateur : Réserve visible (famille Stock) ; droit de consultation : Ordonnances des clients visible', () {
      DroitsModules.instance.fixer(adminLocal: true, ordonnances: const DroitsOrdonnances(consulter: true, modifier: false));
      expect(_ids(), containsAll(['reserve', 'ordonnances_clients']));
      expect(menusByFamille(const [], const [])[MenuFamille.stock]!.map((m) => m.id), contains('reserve'));
      expect(chercherMenus('reserve', orderedMenus(const [])).map((m) => m.id), contains('reserve'));
    });

    test('aucun utilisateur identifié : aucun des nouveaux menus ; catalogue d\'origine inchangé (23)', () {
      DroitsModules.instance.oublier();
      final ids = _ids();
      expect(ids, hasLength(23));
      expect(ids, isNot(contains('posos')));
      expect(accueilMenus, hasLength(23));
      expect(accueilMenuById.containsKey('reserve'), isFalse, reason: 'jamais en favori : pas de recherche par identifiant');
    });

    test('organisation de l\'accueil : les menus soumis à un droit n\'y sont pas proposés', () {
      DroitsModules.instance.fixer(adminLocal: true, ordonnances: const DroitsOrdonnances(consulter: true, modifier: true));
      final orga = menusByFamille(const [], const [], withHidden: true).values.expand((l) => l).map((m) => m.id);
      expect(orga, isNot(contains('reserve')));
      expect(orga, isNot(contains('posos')));
      expect(orga, hasLength(23));
      final accueil = menusByFamille(const [], const []).values.expand((l) => l).map((m) => m.id);
      expect(accueil, containsAll(['reserve', 'posos', 'ordonnances_clients']));
    });

    test('ordre enregistré contenant un menu non autorisé : ignoré', () {
      DroitsModules.instance.fixer();
      expect(orderedMenus(const ['reserve', 'stock']).first.id, 'stock');
    });
  });

  group('lecture sur le serveur', () {
    late ServeurJsonLocal srv;
    setUp(() => avecVraiHttp(() async {
          srv = ServeurJsonLocal();
          await srv.demarrer();
        }));
    tearDown(() => avecVraiHttp(() => srv.arreter()));

    test('profil administrateur côté serveur + droits ordonnances ; route de droit dédié absente (404) ignorée', () => avecVraiHttp(() async {
          srv.routes['GET /roles/est-admin'] = (_) => const ReponseLocale({'authorize': true});
          srv.routes['GET /ordonnance-client/droits'] = (_) => const ReponseLocale({'success': true, 'consulter': true, 'modifier': false});
          final d = DroitsModules();
          var notifs = 0;
          d.addListener(() => notifs++);
          await d.actualiser(ClientPrestige(() => srv.base), utilisateur: 'u1', adminLocal: false);
          expect(d.reserve, isTrue);
          expect(d.ordonnancesConsulter, isTrue);
          expect(d.ordonnancesModifier, isFalse);
          expect(notifs, greaterThan(0));
          expect(srv.recuesSur('/reserve/droits'), hasLength(1));
        }));

    test('non administrateur sans droit dédié : Réserve masquée ; droit dédié exposé par le serveur : visible', () => avecVraiHttp(() async {
          srv.routes['GET /roles/est-admin'] = (_) => const ReponseLocale({'authorize': false});
          srv.routes['GET /ordonnance-client/droits'] = (_) => const ReponseLocale({'success': false, 'message': 'Votre profil ne donne pas accès'});
          final d = DroitsModules();
          await d.actualiser(ClientPrestige(() => srv.base), utilisateur: 'u2', adminLocal: false);
          expect(d.reserve, isFalse);
          expect(d.ordonnancesConsulter, isFalse);
          srv.routes['GET /reserve/droits'] = (_) => const ReponseLocale({'success': true, 'traiter': true});
          await d.actualiser(ClientPrestige(() => srv.base), utilisateur: 'u2', adminLocal: false, forcer: true);
          expect(d.reserve, isTrue);
        }));

    test('relecture limitée (5 min) ; changement d\'utilisateur : droits du précédent oubliés', () => avecVraiHttp(() async {
          srv.routes['GET /roles/est-admin'] = (r) => ReponseLocale({'authorize': r.query['x'] == null});
          srv.routes['GET /ordonnance-client/droits'] = (_) => const ReponseLocale({'success': true, 'consulter': true, 'modifier': true});
          final d = DroitsModules();
          final c = ClientPrestige(() => srv.base);
          await d.actualiser(c, utilisateur: 'u1', adminLocal: false);
          await d.actualiser(c, utilisateur: 'u1', adminLocal: false);
          expect(srv.recuesSur('/roles/est-admin'), hasLength(1));
          srv.routes['GET /roles/est-admin'] = (_) => const ReponseLocale('Veuillez vous connecter', statut: 401);
          srv.routes['GET /ordonnance-client/droits'] = (_) => const ReponseLocale('Veuillez vous connecter', statut: 401);
          final f = d.actualiser(c, utilisateur: 'u3', adminLocal: false);
          expect(d.reserve, isFalse, reason: 'les droits de u1 ne doivent pas servir à u3');
          await f;
          expect(d.reserve, isFalse);
          expect(d.ordonnancesConsulter, isFalse);
        }));

    test('serveur injoignable : droits déjà connus du même utilisateur conservés', () => avecVraiHttp(() async {
          srv.routes['GET /roles/est-admin'] = (_) => const ReponseLocale({'authorize': true});
          srv.routes['GET /ordonnance-client/droits'] = (_) => const ReponseLocale({'success': true, 'consulter': true, 'modifier': true});
          final d = DroitsModules();
          var base = srv.base;
          final c = ClientPrestige(() => base, delaiConnexion: const Duration(seconds: 1));
          await d.actualiser(c, utilisateur: 'u1', adminLocal: false);
          base = 'http://127.0.0.1:1/prestige/api/v1';
          await d.actualiser(c, utilisateur: 'u1', adminLocal: false, forcer: true);
          expect(d.reserve, isTrue);
          expect(d.ordonnancesModifier, isTrue);
        }));
  });
}
