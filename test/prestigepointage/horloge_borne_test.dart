// Prestige Pointage 1.2.0 (Prestige Mobile 5.5.0) — transmission du serveur du 24/11/2026 : HEURE DU SERVEUR FAUSSE.
// Borne enrôlée (client signé) contre le faux serveur Prestige en mémoire : le pointage (POST v1/borne-pointage/…)
// refusé en 423 `{horlogeBloquee:true, msg}` est GARDÉ en file avec le message du serveur (jamais « refusé », jamais
// « hors ligne »), l'état de la borne reste « en service » (pas une panne), aucune relance automatique ; après la
// correction : envoyé une fois, même identifiant. Données fictives uniquement.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/prestigepointage/client_borne.dart';
import 'package:prestige_vente_app/prestigepointage/controleur_borne.dart';
import 'package:prestige_vente_app/prestigepointage/identite_borne.dart';
import 'package:prestige_vente_app/prestigepointage/enrolement_borne.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/rh/rh_store.dart';
import 'package:prestige_vente_app/serveur/horloge_serveur.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';

import '../outils/faux_serveur_borne.dart';
import '../outils/faux_serveur_prestige.dart';

void main() {
  late FauxServeurPrestige srv;
  late FauxBornes bornes;

  setUp(() async {
    srv = FauxServeurPrestige()..installerEnMemoire();
    bornes = FauxBornes(srv);
    SondeDeploiement.vider();
    HorlogeServeur.instance.reinitialiser();
    await DioClient.cookieJar.deleteAll();
  });
  tearDown(() async {
    srv.desinstaller();
    await DioClient.cookieJar.deleteAll();
  });

  test('borne : pointage refusé en 423 gardé en file avec le msg, puis envoyé une fois après correction', () async {
    final r = await EnrolementBorne().enroler(
        baseUrl: srv.base, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin, nom: 'Borne entrée', empreinte: 'ab12cd34' * 8);
    expect(r.reussi, isTrue, reason: r.message);
    final c = ClientBorne(r.identite!);
    final n = DateTime.now();
    final rh = PointageRh(
      store: MemoryRhStore(),
      serveur: c,
      clock: () => n,
      horsLigne: () => false,
      nomTerminal: () => 'Borne entrée',
      journal: () => JournalTerminal(store: MemoryJournalStore()),
    );
    srv.horlogeBloquee = true;
    const e = EmployeRh(id: 'E1', nom: 'KOUASSI', prenoms: 'Awa', badge: 'B001');
    final res = await rh.enregistrer(BadgeAConfirmer(e, SensPointage.entree, n), SensPointage.entree);
    expect(res.issue, IssueBadge.enFile);
    expect(res.horloge, isTrue);
    expect(res.message, startsWith(FauxServeurPrestige.messageHorloge));
    expect(c.etat, EtatBorne.ok, reason: 'serveur joignable : ni hors ligne, ni « heure du terminal incorrecte »');
    expect(bornes.pointages, isEmpty);
    final b = await rh.envoyer();
    expect(b.horloge, FauxServeurPrestige.messageHorloge);
    expect(rh.enAttente, 1);
    expect(srv.refusHorloge, hasLength(2), reason: 'aucune relance automatique');

    srv.horlogeBloquee = false;
    expect((await rh.envoyer()).envoyes, 1);
    expect(bornes.pointages, hasLength(1));
    expect(rh.enAttente, 0);
  });

  test('contrôleur de la borne : horloge/public lu toutes les minutes tant que c\'est bloqué, puis file envoyée seule', () async {
    final r = await EnrolementBorne().enroler(
        baseUrl: srv.base, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin, nom: 'Borne entrée', empreinte: 'ab12cd34' * 8);
    final coffre = CoffreBorneMemoire();
    await coffre.ecrire(r.identite!);
    final ctl = ControleurBorne(coffre: coffre, store: MemoryRhStore(), intervalleVerification: const Duration(milliseconds: 200));
    addTearDown(ctl.dispose);
    await ctl.charger();
    final rh = ctl.rh!;
    srv.horlogeBloquee = true;
    srv.etatHorloge = 'BLOQUE';
    const e = EmployeRh(id: 'E1', nom: 'KOUASSI', prenoms: 'Awa', badge: 'B001');
    final n = DateTime.now();
    expect((await rh.enregistrer(BadgeAConfirmer(e, SensPointage.entree, n), SensPointage.entree)).issue, IssueBadge.enFile);
    expect(HorlogeServeur.instance.bloquee, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(srv.recuesSur('/horloge/public'), isNotEmpty, reason: 'vérification légère, sans écriture');
    expect(srv.refusHorloge, hasLength(1), reason: 'aucune écriture rejouée pendant le blocage');
    srv.horlogeBloquee = false;
    srv.etatHorloge = 'OK';
    for (var i = 0; i < 20 && bornes.pointages.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(HorlogeServeur.instance.bloquee, isFalse);
    expect(bornes.pointages, hasLength(1));
    expect(rh.enAttente, 0);
  });
}
