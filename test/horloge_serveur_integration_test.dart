// 5.5.0 — Transmission du serveur du 24/11/2026 (plan/24112026) : HEURE DU SERVEUR FAUSSE, clients HTTP de
// l'application contre le faux serveur Prestige (écritures refusées en 423 `{success:false, horlogeBloquee:true, msg}`) :
//  - réception (lot du BL), modules (ClientPrestige → HorlogeBloquee), paiement mobile money : msg tel quel, jamais
//    « erreur du serveur » ni « injoignable » ;
//  - suppression d'une vente (POST v1/ventestats/remove/{id}, point 3) : refus « vente en saisie sur un poste » et 423
//    affichés tels quels, rien n'est supprimé.
// Données fictives uniquement.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/serveur/horloge_serveur.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/faux_serveur_prestige.dart';

const _msg = FauxServeurPrestige.messageHorloge;

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
    UtilisateurSession.id = null;
    HorlogeServeur.instance.reinitialiser();
    final prev = JournalTerminal.instance;
    JournalTerminal.instance = JournalTerminal(store: MemoryJournalStore());
    addTearDown(() => JournalTerminal.instance = prev);
  });

  test('réception, modules, paiement mobile money : msg tel quel (jamais « erreur du serveur » ni « injoignable »)', () async {
    await avecVraiHttp(() async {
      final (s, api) = await _connecte((s) => s.horlogeBloquee = true);
      final lot = await DioReceptionGateway(api.dio).addLot(detailId: 'D1', quantity: 1, freeQty: 0, numLot: 'LOT-FICTIF');
      expect(lot.success, isFalse);
      expect(lot.message, _msg);
      Object? e;
      try {
        await ClientPrestige(() => s.base).post('/reserve/mouvement', {'quantite': 1});
      } catch (x) {
        e = x;
      }
      expect(e, isA<HorlogeBloquee>().having((x) => x.message, 'message', _msg));
      final pm = await DioPaiementsMobileApi(() => api.dio).creer(venteId: 'V-1', operateur: 'WAVE', cle: 'PM-fictif');
      expect(pm, isA<VenteRefused<PaiementMobile>>().having((x) => x.horlogeBloquee, 'horloge', isTrue));
      expect(pm.message, _msg);
    });
  });

  test('suppression d\'une vente : refus « en saisie sur un poste » et 423 affichés tels quels, rien supprimé', () async {
    await avecVraiHttp(() async {
      const enSaisie = 'Cette vente est en cours de saisie sur le poste CAISSE-1 : elle ne peut pas être supprimée.';
      final (s, api) = await _connecte((s) {
        s.routes['POST /ventestats/remove/V-9'] = (_) => FauxServeurPrestige.refus(enSaisie);
      });
      expect(await api.deleteSale('V-9'), isFalse);
      expect(api.prendreRefusSuppression(), enSaisie);
      expect(api.prendreRefusSuppression(), isNull, reason: 'lu une fois');
      s.horlogeBloquee = true;
      expect(await api.deleteSale('V-9'), isFalse);
      expect(api.prendreRefusSuppression(), _msg);
      s.horlogeBloquee = false;
      s.routes['POST /ventestats/remove/V-9'] = (_) => FauxServeurPrestige.ok(true);
      expect(await api.deleteSale('V-9'), isTrue);
      expect(api.prendreRefusSuppression(), isNull);
    });
  });

}
