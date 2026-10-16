// PERFORMANCE — Empreintes partagées (4.4.0, demande 43), 50 employés × 3 gabarits FACTICES (480 octets) :
//  - première synchronisation d'un second terminal (lecture, décodage, application, écriture du coffre) ;
//  - synchronisation suivante sans changement (incrémentale : une seule requête, rien d'écrit) ;
//  - identification 1:N sur les 150 modèles (préparation de la liste avant le lecteur).
// Meilleur de 3 passages (la CI joue les tests en parallèle) ; seuils : test/outils/performance.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/rh/empreintes_partagees.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../empreintes_partagees_test.dart' show Terminal;
import '../outils/faux_serveur_empreintes.dart';
import '../outils/performance.dart';

Future<int> _ms(Future<void> Function() f) async {
  final sw = Stopwatch()..start();
  await f();
  return sw.elapsedMilliseconds;
}

void main() {
  test('50 employés × 3 gabarits : première synchronisation, synchronisation vide, identification', () async {
    var meilleureSynchro = 1 << 30, meilleureVide = 1 << 30, meilleureId = 1 << 30;
    for (var passage = 0; passage < 3; passage++) {
      SharedPreferences.setMockInitialValues({});
      final srv = FauxServeurEmpreintes()..employesActifs.addAll([for (var i = 0; i < 50; i++) 'E$i']);
      final a = Terminal(srv, 'A$passage');
      for (var i = 0; i < 50; i++) {
        final e = EmpreintesEmploye(
            employeId: 'E$i',
            modeles: [gabaritFactice(i * 3), gabaritFactice(i * 3 + 1), gabaritFactice(i * 3 + 2)],
            consentementLe: DateTime(2026, 10, 16, 9),
            recueilliPar: 'admin',
            consentementPartage: true);
        await a.id.enregistrer(e);
        await a.partage.envoyer(e);
      }
      expect(srv.nombreModeles, 150);
      final b = Terminal(srv, 'B$passage');
      late BilanSynchroEmpreintes bilan;
      meilleureSynchro = [meilleureSynchro, await _ms(() async => bilan = await b.partage.synchroniser())].reduce((x, y) => x < y ? x : y);
      expect(bilan.ajoutes, 150);
      expect((await b.coffre.lire()).length, 50);
      final appels = srv.appels.length;
      late BilanSynchroEmpreintes vide;
      meilleureVide = [meilleureVide, await _ms(() async => vide = await b.partage.synchroniser())].reduce((x, y) => x < y ? x : y);
      expect([vide.ajoutes, vide.retires], [0, 0]);
      expect(srv.appels.length, appels + 1, reason: 'une seule requête');
      // Doigt du dernier employé : reconnu parmi les 150 modèles.
      b.lecteur.doigt = gabaritFactice(49 * 3 + 2);
      final employes = [for (var i = 0; i < 50; i++) EmployeRh.fromJson({'id': 'E$i', 'nom': 'TEST', 'prenoms': '$i', 'statut': 'ACTIF'})];
      EmployeRh? trouve;
      meilleureId = [meilleureId, await _ms(() async => trouve = await b.id.parEmpreinte(employes))].reduce((x, y) => x < y ? x : y);
      expect(trouve?.id, 'E49');
    }
    mesurer('Empreintes : 1re synchronisation, 50 employés × 3 gabarits', meilleureSynchro, seuil: Seuils.synchroEmpreintes50Ms, unite: 'ms', detail: '150 modèles reçus et écrits dans le coffre');
    mesurer('Empreintes : synchronisation sans changement', meilleureVide, seuil: Seuils.synchroEmpreintesVideMs, unite: 'ms', detail: 'incrémentale, 1 requête');
    mesurer('Empreintes : identification 1:N sur 150 modèles', meilleureId, seuil: Seuils.identification150Ms, unite: 'ms', detail: 'lecteur simulé');
  });
}
