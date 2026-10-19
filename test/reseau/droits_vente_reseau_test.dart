// 4.5.1 — Réseau et sécurité des ventes (demande du serveur du 19/10/2026), vrai HTTP vers le faux serveur Prestige :
//  - vente terminée hors ligne (espèces) puis droit refusé à l'envoi (403 interdit) : vente gardée, motif lisible,
//    une seule tentative, aucune boucle ;
//  - 409 sessionChangee à l'envoi : rien d'exécuté, la vente reste en attente (aucune anomalie), envoyée ensuite ;
//  - vente hors ligne d'un AUTRE compte : jamais envoyée sous cette session ;
//  - lecture des droits lente (serveur lent) : la connexion n'attend pas plus que le délai prévu ; coupure pendant la
//    lecture : dernière lecture gardée.
// Données fictives uniquement.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/horsligne/ventes_sync.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../outils/faux_serveur_prestige.dart';

VenteHorsLigne _especes(String id, {String user = 'U-awa'}) {
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
    createdAt: DateTime(2026, 10, 19, 9),
    updatedAt: DateTime(2026, 10, 19, 9),
    userId: user,
  );
}

Future<(FauxServeurPrestige, FileVentesHL)> _file() async {
  final s = FauxServeurPrestige(exigerSession: false);
  await s.demarrer();
  addTearDown(s.arreter);
  final f = FileVentesHL(store: MemoryVentesHLStore(), gateway: DioVenteGateway(ApiService(baseUrl: s.base)));
  f.compteCourant = () => 'U-awa';
  return (s, f);
}

void main() {
  setUp(() {
    DroitsVente.instance.oublier();
    UtilisateurSession.id = null;
    SessionChangee.instance = SessionChangee();
  });

  test('vente espèces hors ligne, droit refusé à l\'envoi (403) : gardée « à vérifier », motif lisible, une seule clôture', () async {
    await avecVraiHttp(() async {
      final (s, f) = await _file();
      var clotures = 0;
      s.routes['POST /vente/cloturer/vno'] = (_) {
        clotures++;
        return FauxServeurPrestige.interdit('Droit manquant : terminer une vente.');
      };
      await f.ajouter(_especes('A'));
      await f.envoyer();
      final v = f.byId('A')!;
      expect(v.statut, StatutVenteHL.aVerifier);
      expect(v.motif, contains('Droit manquant : terminer une vente.'));
      expect(v.venteId, isNotNull, reason: 'vente gardée sur le serveur (prévente), rien de perdu');
      expect(f.panne, isNull, reason: 'pas une panne réseau');
      await f.envoyer();
      await f.envoyer();
      expect(clotures, 1, reason: 'aucune boucle : une vente refusée n\'est plus renvoyée automatiquement');
      expect(f.anomalies, hasLength(1));
    });
  });

  test('409 sessionChangee à l\'envoi : rien d\'exécuté, vente en attente (aucune anomalie), envoyée ensuite', () async {
    await avecVraiHttp(() async {
      final (s, f) = await _file();
      s.routes['POST /vente/add/vno'] =
          (_) => const ReponseLocale({'success': false, 'sessionChangee': true, 'msg': 'Un autre compte s\'est connecté.'}, statut: 409);
      await f.ajouter(_especes('B'));
      await f.envoyer();
      expect(f.byId('B')!.statut, StatutVenteHL.enAttente);
      expect(f.anomalies, isEmpty);
      expect(f.panne, contains('Un autre compte'));
      expect(s.ventes, isEmpty);
      s.routes.remove('POST /vente/add/vno');
      s.routes['POST /vente/cloturer/vno'] = (r) {
        s.statutVentes['${r.json['venteId']}'] = 'is_Closed';
        return FauxServeurPrestige.ok({'success': true});
      };
      await f.envoyer();
      expect(f.byId('B')!.statut, StatutVenteHL.envoyee);
    });
  });

  test('vente hors ligne d\'un autre compte : jamais envoyée sous cette session', () async {
    await avecVraiHttp(() async {
      final (s, f) = await _file();
      await f.ajouter(_especes('C', user: 'U-admin'));
      expect(f.enAttenteAutreCompte, 1);
      await f.envoyer();
      expect(f.byId('C')!.statut, StatutVenteHL.enAttente);
      expect(s.recues.where((r) => r.chemin.contains('/vente/')), isEmpty);
      f.compteCourant = () => 'U-admin';
      expect(f.enAttenteAutreCompte, 0);
    });
  });

  test('lecture des droits lente : connexion bornée par le délai ; coupure ensuite : dernière lecture gardée', () async {
    await avecVraiHttp(() async {
      SharedPreferences.setMockInitialValues({});
      final s = FauxServeurPrestige()..droitsComptes = {DonneesFictives.login: ['P_SM_VENTE']};
      await s.demarrer();
      addTearDown(s.arreter);
      await DioClient.cookieJar.deleteAll();
      final api = ApiService(baseUrl: s.base);
      final auth = AuthProvider(api);
      final avant = AuthProvider.delaiDroits;
      AuthProvider.delaiDroits = const Duration(milliseconds: 600);
      addTearDown(() => AuthProvider.delaiDroits = avant);
      s.routes['GET /user/droits'] = (_) => FauxServeurPrestige.lent({'success': true, 'droits': ['P_SM_VENTE']}, const Duration(seconds: 2));
      final chrono = Stopwatch()..start();
      expect(await auth.login(DonneesFictives.login, DonneesFictives.motDePasse), isTrue);
      expect(chrono.elapsedMilliseconds, lessThan(1800), reason: 'la connexion n\'attend pas la lecture lente au-delà du délai');
      expect(UtilisateurSession.id, 'U-${DonneesFictives.login}');
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(DroitsVente.instance.preventeSeule, isTrue, reason: 'lue dès la réponse');
      s.routes.remove('GET /user/droits');
      await s.couper();
      await auth.relireDroits();
      expect(DroitsVente.instance.preventeSeule, isTrue, reason: 'coupure : dernière lecture gardée');
      await s.retablir();
      await DioClient.cookieJar.deleteAll();
    });
  });
}
