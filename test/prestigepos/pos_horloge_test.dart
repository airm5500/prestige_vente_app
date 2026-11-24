// PrestigePOS 1.18.0 (Prestige Mobile V3 5.5.0) — transmission du serveur du 24/11/2026 : HEURE DU SERVEUR FAUSSE.
// Borne de PrestigePOS contre le faux serveur Prestige (vrai HTTP) : la prévente refusée en 423 `{horlogeBloquee:true,
// msg}` n'est pas créée, le refus porte le message du serveur tel quel (jamais « serveur injoignable »), une seule
// requête (aucune relance), journal du terminal par catégorie seulement ; après la correction, la prévente est créée
// normalement. Données fictives uniquement.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/borne/borne_panier.dart';
import 'package:prestige_vente_app/borne/borne_produit.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/serveur/horloge_serveur.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

import '../outils/faux_serveur_prestige.dart';

void main() {
  test('borne : prévente refusée en 423 (message du serveur, une requête), créée après la correction', () async {
    await avecVraiHttp(() async {
      HorlogeServeur.instance.reinitialiser();
      final store = MemoryJournalStore();
      final prev = JournalTerminal.instance;
      JournalTerminal.instance = JournalTerminal(store: store);
      addTearDown(() => JournalTerminal.instance = prev);
      final s = FauxServeurPrestige(exigerSession: false)..horlogeBloquee = true;
      await s.demarrer();
      addTearDown(s.arreter);
      final service = BorneService(DioVenteGateway(ApiService(baseUrl: s.base)));
      final p = DonneesFictives.produitRecherche();
      final ligne = BorneLigne(
          BorneProduit(ProductSearchResult(
              lgFAMILLEID: '${p['lgFAMILLEID']}', strNAME: '${p['strNAME']}', intCIP: '${p['intCIP']}', intPRICE: p['intPRICE'] as int,
              intNUMBERAVAILABLE: 10, strLIBELLEE: '', intPAF: 0)),
          1);
      final r = await service.creerPrevente([ligne]);
      expect(r, isA<VenteRefused>().having((x) => x.horlogeBloquee, 'horloge', isTrue));
      expect(r.message, FauxServeurPrestige.messageHorloge);
      expect(r.message, isNot(contains(MessagesServeur.titreInjoignable)));
      expect(s.refusHorloge, hasLength(1), reason: 'aucune relance');
      expect(s.ventes, isEmpty);
      await JournalTerminal.instance.idle;
      final motifs = (await store.lire(const JournalFiltre())).map((e) => e.motif).join('\n');
      expect(motifs, contains(motifJournalHorloge));
      expect(motifs, isNot(contains(FauxServeurPrestige.messageHorloge)));

      s.horlogeBloquee = false;
      expect((await service.creerPrevente([ligne])).isOk, isTrue);
      expect(s.ventes, hasLength(1));
    });
  });
}
