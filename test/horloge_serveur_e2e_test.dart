// 5.5.0 — Transmission du serveur du 24/11/2026 (plan/24112026) : HEURE DU SERVEUR FAUSSE, parcours complet en vrai
// HTTP (faux serveur Prestige) avec le hors ligne de l'application (HorsLigne, file des ventes, file des pointages) :
//  1. heure du serveur fausse : vente encaissée gardée en file, pointage du terminal gardé en file, message du serveur ;
//     aucune relance automatique ;
//  2. l'administrateur remet l'heure : la surveillance lit GET v1/horloge/public (OK) → déblocage → les deux files
//     proposent l'envoi (confirmation), RIEN n'est envoyé sans accord ;
//  3. après l'accord : chaque opération part une fois, avec la même clé (X-Client-Ref / identifiant du pointage).
// Données fictives uniquement.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/client_ref.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/horsligne/ventes_sync.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/rh/rh_store.dart';
import 'package:prestige_vente_app/serveur/horloge_serveur.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/faux_serveur_prestige.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DroitsVente.instance.oublier();
    UtilisateurSession.id = null;
    HorlogeServeur.instance.reinitialiser();
    CapaciteClientRef.vider();
    final prev = JournalTerminal.instance;
    JournalTerminal.instance = JournalTerminal(store: MemoryJournalStore());
    addTearDown(() => JournalTerminal.instance = prev);
  });

  test('heure fausse → files gardées → heure corrigée → confirmation → une seule vente et un seul pointage', () async {
    await avecVraiHttp(() async {
      final s = FauxServeurPrestige()
        ..droitsRh[DonneesFictives.login] = (pointer: true, gerer: false)
        ..activerTerminalRh();
      s.routes['GET /app-vente/capacites'] = (_) => FauxServeurPrestige.ok({'success': true, 'clientRef': true});
      s.routes['GET /app-vente/client-ref'] = (_) => const ReponseLocale({'success': false}, statut: 404);
      s.routes['POST /vente/cloturer/vno'] = (r) {
        s.statutVentes['${r.json['venteId']}'] = 'is_Closed';
        return FauxServeurPrestige.ok({'success': true});
      };
      await s.demarrer();
      addTearDown(s.arreter);
      await DioClient.cookieJar.deleteAll();
      addTearDown(DioClient.cookieJar.deleteAll);
      final api = ApiService(baseUrl: s.base);
      expect(await api.login(DonneesFictives.login, DonneesFictives.motDePasse), isNotNull);

      final store = MemoryLocalStore();
      final ventes = FileVentesHL(store: MemoryVentesHLStore(), gateway: DioVenteGateway(api))..compteCourant = () => 'U-awa';
      final hl = HorsLigne(monitor: ServerMonitor(), store: store, sync: CatalogueSync(store: store, occupee: () => false), ventes: ventes);
      final rh = PointageRh(
        store: MemoryRhStore(),
        serveur: DioRhServeur(() => s.base),
        clock: () => DateTime(2026, 11, 24, 8, 2),
        horsLigne: () => false,
        nomTerminal: () => 'Accueil',
      )..attach(hl);

      // 1. Heure du serveur fausse.
      s.horlogeBloquee = true;
      final p = DonneesFictives.produitRecherche();
      await ventes.ajouter(VenteHorsLigne(
        id: 'E2E',
        numero: 1,
        type: TypeVenteHL.comptant,
        lignes: [LigneHL(cle: 'l1', produitId: '${p['lgFAMILLEID']}', nom: '${p['strNAME']}', cip: '${p['intCIP']}', qte: 1, prix: p['intPRICE'] as int, stockConnu: 18)],
        fin: FinVenteHL.especes,
        totalEstime: p['intPRICE'] as int,
        netEstime: p['intPRICE'] as int,
        montantRecu: p['intPRICE'] as int,
        createdAt: DateTime(2026, 11, 24, 8),
        updatedAt: DateTime(2026, 11, 24, 8),
        userId: 'U-awa',
      ));
      await ventes.envoyer();
      const e = EmployeRh(id: 'E1', nom: 'KOUASSI', prenoms: 'Awa', badge: 'B001');
      final pt = await rh.enregistrer(BadgeAConfirmer(e, SensPointage.entree, DateTime(2026, 11, 24, 8, 2)), SensPointage.entree);
      expect(pt.issue, IssueBadge.enFile);
      expect(pt.message, startsWith(FauxServeurPrestige.messageHorloge));
      expect(ventes.panne, FauxServeurPrestige.messageHorloge);
      expect(ventes.enAttente, 1);
      expect(rh.enAttente, 1);
      expect(HorlogeServeur.instance.bloquee, isTrue);
      final refusAvant = s.refusHorloge.length;
      expect(refusAvant, 2, reason: 'une tentative chacune, aucune relance');

      // 2. L'administrateur remet l'heure ; la surveillance (30 s) lit horloge/public.
      s.horlogeBloquee = false;
      s.etatHorloge = 'OK';
      await HorlogeServeur.instance.verifierSiBloquee(Dio(BaseOptions(baseUrl: s.base)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(HorlogeServeur.instance.bloquee, isFalse);
      expect(ventes.confirmationDemandee, isTrue, reason: 'confirmation proposée, comme au retour du serveur');
      expect(rh.confirmationDemandee, isTrue);
      expect(s.ventes, isEmpty, reason: 'rien n\'est envoyé sans accord');
      expect(s.pointagesTerminal, isEmpty);

      // 3. Accord de l'utilisateur.
      await ventes.envoyer();
      final b = await rh.envoyer();
      expect(ventes.byId('E2E')!.statut, StatutVenteHL.envoyee);
      expect(b.envoyes, 1);
      expect(s.ventes, hasLength(1));
      expect(s.recues.where((r) => r.chemin.endsWith('/vente/add/vno')).map((r) => r.clientRef).toSet(), {cleClientVente('E2E')});
      expect(s.pointagesTerminal.single['id'], pt.pointage.id);
      expect(s.refusHorloge, hasLength(refusAvant));
    });
  });
}
