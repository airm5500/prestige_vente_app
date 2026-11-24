// 5.5.0 — Transmission du serveur du 24/11/2026 (plan/24112026) : HEURE DU SERVEUR FAUSSE, vrai HTTP vers le faux
// serveur Prestige (toute écriture refusée en 423 `{success:false, horlogeBloquee:true, msg}` sauf v1/user/auth,
// auth-badge, logout et horloge/* ; GET permis) :
//  - connexion de l'application permise ; v1/mobile/connexion, pointage par téléphone (session) : msg affiché ;
//  - vente hors ligne en file (X-Client-Ref) : gardée EN ATTENTE (jamais « à vérifier »), une seule tentative par
//    envoi (aucune boucle), puis après le déblocage : envoyée avec la MÊME clé, une seule vente ;
//  - encaissement (clôture) refusé : vente gardée, renvoyée ensuite sans seconde vente ;
//  - pointage du terminal : gardé en file avec le msg, envoi interrompu, puis envoyé une fois (même identifiant) ;
//  (réception, modules, paiement mobile money, suppression d'une vente : test/horloge_serveur_integration_test.dart)
//  - état de l'application : bloqué au 423, débloqué par la 1re écriture acceptée ; horloge/public lu par la
//    surveillance seulement quand c'est bloqué.
// Données fictives uniquement.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/horsligne/client_ref.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/horsligne/ventes_sync.dart';
import 'package:prestige_vente_app/rh/mobile_api.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/rh/rh_store.dart';
import 'package:prestige_vente_app/serveur/horloge_serveur.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../outils/faux_serveur_prestige.dart';

const _msg = FauxServeurPrestige.messageHorloge;

VenteHorsLigne _especes(String id) {
  final p = DonneesFictives.produitRecherche();
  return VenteHorsLigne(
    id: id,
    numero: 1,
    type: TypeVenteHL.comptant,
    lignes: [LigneHL(cle: 'l1', produitId: '${p['lgFAMILLEID']}', nom: '${p['strNAME']}', cip: '${p['intCIP']}', qte: 1, prix: p['intPRICE'] as int, stockConnu: 18)],
    fin: FinVenteHL.especes,
    totalEstime: p['intPRICE'] as int,
    netEstime: p['intPRICE'] as int,
    montantRecu: p['intPRICE'] as int,
    createdAt: DateTime(2026, 11, 24, 9),
    updatedAt: DateTime(2026, 11, 24, 9),
    userId: 'U-awa',
  );
}

/// Serveur avec la clé client (H4) : capacité annoncée, clé inconnue en relecture (rien n'a été créé).
Future<(FauxServeurPrestige, FileVentesHL)> _file() async {
  final s = FauxServeurPrestige(exigerSession: false);
  s.routes['GET /app-vente/capacites'] = (_) => FauxServeurPrestige.ok({'success': true, 'clientRef': true});
  s.routes['GET /app-vente/client-ref'] = (_) => const ReponseLocale({'success': false}, statut: 404);
  s.routes['POST /vente/cloturer/vno'] = (r) {
    s.statutVentes['${r.json['venteId']}'] = 'is_Closed';
    return FauxServeurPrestige.ok({'success': true});
  };
  await s.demarrer();
  addTearDown(s.arreter);
  CapaciteClientRef.vider();
  final f = FileVentesHL(store: MemoryVentesHLStore(), gateway: DioVenteGateway(ApiService(baseUrl: s.base)));
  f.compteCourant = () => 'U-awa';
  return (s, f);
}

Future<(FauxServeurPrestige, ApiService)> _connecte(void Function(FauxServeurPrestige s) preparer) async {
  final s = FauxServeurPrestige();
  preparer(s);
  await s.demarrer();
  addTearDown(s.arreter);
  await DioClient.cookieJar.deleteAll();
  addTearDown(DioClient.cookieJar.deleteAll);
  final api = ApiService(baseUrl: s.base);
  expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);
  return (s, api);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DroitsVente.instance.oublier();
    UtilisateurSession.id = null;
    HorlogeServeur.instance.reinitialiser();
    final prev = JournalTerminal.instance;
    JournalTerminal.instance = JournalTerminal(store: MemoryJournalStore());
    addTearDown(() => JournalTerminal.instance = prev);
  });

  test('connexion de l\'application permise pendant le blocage (v1/user/auth non bloquée), écritures refusées', () async {
    await avecVraiHttp(() async {
      final (s, api) = await _connecte((s) => s.horlogeBloquee = true);
      expect(s.refusHorloge, isEmpty);
      expect(HorlogeServeur.instance.bloquee, isFalse, reason: 'rien n\'est encore constaté');
      final r = await api.dio.post('/vente/add/vno', options: Options(validateStatus: (_) => true), data: {'produitId': 'P1'});
      expect(r.statusCode, 423);
      expect(HorlogeServeur.instance.bloquee, isTrue);
    });
  });

  test('vente hors ligne en file : 423 → gardée en attente, msg, une tentative ; après déblocage : même clé, une vente', () async {
    await avecVraiHttp(() async {
      final (s, f) = await _file();
      s.horlogeBloquee = true;
      await f.ajouter(_especes('A'));
      await f.envoyer();
      final v = f.byId('A')!;
      expect(v.statut, isNot(StatutVenteHL.aVerifier));
      expect(v.aFaire, isTrue, reason: 'reste dans la file');
      expect(f.anomalies, isEmpty, reason: 'jamais une anomalie');
      expect(f.panne, _msg, reason: 'message du serveur tel quel');
      expect(f.panne, isNot(contains('injoignable')));
      expect(s.refusHorloge, ['POST /prestige/api/v1/vente/add/vno HL2-A'], reason: 'une seule tentative, aucune boucle');
      expect(s.ventes, isEmpty);
      expect(HorlogeServeur.instance.bloquee, isTrue);

      // Déblocage (l'administrateur a remis l'heure) : la file repart, même X-Client-Ref, aucun doublon.
      s.horlogeBloquee = false;
      await f.envoyer();
      expect(f.byId('A')!.statut, StatutVenteHL.envoyee);
      expect(s.ventes, hasLength(1));
      final creations = s.recues.where((r) => r.methode == 'POST' && r.chemin.endsWith('/vente/add/vno')).toList();
      expect(creations.map((r) => r.clientRef).toSet(), {cleClientVente('A')});
      expect(HorlogeServeur.instance.bloquee, isFalse, reason: 'écriture acceptée = débloqué');
      expect(HorlogeServeur.instance.deblocages, 1);
    });
  });

  test('encaissement (clôture) refusé en 423 : vente gardée, aucune seconde vente au renvoi', () async {
    await avecVraiHttp(() async {
      final (s, f) = await _file();
      s.routes['POST /vente/cloturer/vno'] = (_) =>
          const ReponseLocale({'success': false, 'horlogeBloquee': true, 'msg': _msg}, statut: 423);
      await f.ajouter(_especes('B'));
      await f.envoyer();
      expect(f.byId('B')!.aFaire, isTrue);
      expect(f.anomalies, isEmpty);
      expect(f.panne, _msg);
      s.routes['POST /vente/cloturer/vno'] = (r) {
        s.statutVentes['${r.json['venteId']}'] = 'is_Closed';
        return FauxServeurPrestige.ok({'success': true});
      };
      await f.envoyer();
      expect(f.byId('B')!.statut, StatutVenteHL.envoyee);
      expect(s.ventes, hasLength(1), reason: 'la vente déjà créée est reprise, jamais recréée');
      expect(s.recuesSur('/vente/cloturer/vno'), hasLength(2));
    });
  });

  test('pointage du terminal : gardé en file avec le msg, envoi interrompu, puis envoyé une fois (même identifiant)', () async {
    await avecVraiHttp(() async {
      final (s, api) = await _connecte((s) {
        s.droitsRh[DonneesFictives.login] = (pointer: true, gerer: false);
        s.activerTerminalRh();
      });
      final rh = PointageRh(
        store: MemoryRhStore(),
        serveur: DioRhServeur(() => api.dio.options.baseUrl),
        clock: () => DateTime(2026, 11, 24, 8, 2),
        horsLigne: () => false,
        nomTerminal: () => 'Accueil',
      );
      s.horlogeBloquee = true;
      const e = EmployeRh(id: 'E1', nom: 'KOUASSI', prenoms: 'Awa', badge: 'B001');
      final r = await rh.enregistrer(BadgeAConfirmer(e, SensPointage.entree, DateTime(2026, 11, 24, 8, 2)), SensPointage.entree);
      expect(r.issue, IssueBadge.enFile);
      expect(r.horloge, isTrue);
      expect(r.message, startsWith(_msg));
      expect(r.message, contains('08:02'));
      expect(rh.enAttente, 1);
      final bilan = await rh.envoyer();
      expect(bilan.interrompu, isTrue);
      expect(bilan.horloge, _msg);
      expect(bilan.message, contains(_msg));
      expect(bilan.message, isNot(contains('injoignable')));
      expect(rh.enAttente, 1, reason: 'jamais refusé');
      expect(s.refusHorloge, hasLength(2), reason: 'une tentative en ligne, une à l\'envoi : aucune boucle');
      expect(s.pointagesTerminal, isEmpty);

      s.horlogeBloquee = false;
      final apres = await rh.envoyer();
      expect(apres.envoyes, 1);
      expect(rh.enAttente, 0);
      expect(s.pointagesTerminal, hasLength(1));
      expect(s.pointagesTerminal.single['id'], r.pointage.id, reason: 'même identifiant : aucun doublon');
    });
  });

  test('téléphone : v1/mobile/connexion et pointage (session) refusés en 423 : msg tel quel, une requête', () async {
    await avecVraiHttp(() async {
      final (s, _) = await _connecte((s) => s.activerPointageMobile({DonneesFictives.login: 'TEST Awa'}));
      final m = MobileApi(transport: DioTransportMobile(() => s.base), coffre: CoffreJetonMemoire(), appareil: () => 'test', nomAppareil: () => 'Test');
      s.horlogeBloquee = true;
      final c = await m.connexion(DonneesFictives.login, DonneesFictives.motDePasse);
      expect(c.ok, isFalse);
      expect(c.refus, _msg);
      expect(s.refusHorloge.where((x) => x.contains('/mobile/connexion')), hasLength(1));
    });
    await avecVraiHttp(() async {
      final (s, _) = await _connecte((s) => s.activerPointageSession({DonneesFictives.login: 'TEST Awa'}));
      final rh = DioRhServeur(() => s.base);
      final m = MobileApi(
          transport: DioTransportMobile(() => s.base),
          transportSession: TransportSessionRh(() => rh),
          coffre: CoffreJetonMemoire(),
          appareil: () => 'test',
          nomAppareil: () => 'Test');
      await m.lier(DonneesFictives.login);
      s.horlogeBloquee = true;
      final p = await m.pointer(sens: SensPointage.entree);
      expect(p.ok, isFalse);
      expect(p.refus, _msg);
      expect(s.pointagesSession, isEmpty);
      expect(s.refusHorloge, hasLength(1));
    });
  });

  test('horloge/public : lu seulement quand c\'est bloqué ; OK → débloqué ; 404 (serveur ancien) → rien', () async {
    await avecVraiHttp(() async {
      final s = FauxServeurPrestige(exigerSession: false)..etatHorloge = 'BLOQUE';
      await s.demarrer();
      addTearDown(s.arreter);
      final d = Dio(BaseOptions(baseUrl: s.base));
      await HorlogeServeur.instance.verifierSiBloquee(d);
      expect(s.recuesSur('/horloge/public'), isEmpty, reason: 'aucune requête en fonctionnement normal');
      expect((await HorlogeServeur.lirePublique(d))!.bloque, isTrue);
      HorlogeServeur.instance.signaler(_msg);
      await HorlogeServeur.instance.verifierSiBloquee(d);
      expect(HorlogeServeur.instance.bloquee, isTrue);
      s.etatHorloge = 'REGULARISATION';
      await HorlogeServeur.instance.verifierSiBloquee(d);
      expect(HorlogeServeur.instance.bloquee, isFalse);
      s.etatHorloge = null;
      expect(await HorlogeServeur.lirePublique(d), isNull);
    });
  });
}
