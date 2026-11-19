// NON-RÉGRESSION — 4.15.1 (réponse du serveur à la demande 63, correctif/demande63-1911 PAS encore fusionnée dans
// l'intégration) : avec le serveur de l'officine d'aujourd'hui, tout reste comme en 4.15.0 :
//  - route image absente (404 / 405) → gabarit local ; pas de « vo-combine » ;
//  - sans preuve de la demande 63, la règle de la remise est celle de 4.15.0 et « Retirer » envoie null ;
//  - le net comptant reste relu par net/vno quand vente/remise ne rend pas `data` ;
//  - ticket de la borne de 4.15.0 gardé (« terminée » seulement si cloture:true, « PAYÉE, présentez ce ticket à la
//    caisse ») : confirmé par le pharmacien le 19/11 ;
//  - aucun journal (ni texte de ticket, ni client, ni recherche) dans le code de la demande 63.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/ventes/common/remise_vente.dart';

String _lire(String p) => File(p).readAsStringSync();

/// Règle de 4.15.0 (lib/ventes/common/remise_vente.dart à 0ac0f1e).
bool _regle4150(DroitsVente d) => d.droits.contains('P_REMISE_VENTE') || !d.controle('P_REMISE_VENTE');

void main() {
  test('remise : sans preuve de la demande 63, mêmes décisions qu\'en 4.15.0 ; « Retirer » envoie null', () {
    for (final droits in <Set<String>?>[
      null,
      {},
      {'P_SM_VENTE'},
      {'P_SM_CLOTURER_CAISSE'},
      {'P_SM_VENTE', 'P_BT_ANNULER_VENTE'},
      {DroitsVente.bornePaiementMobileDroit},
    ]) {
      final d = DroitsVente()..fixer(droits);
      expect(remiseAutorisee(d), _regle4150(d), reason: '$droits');
      expect(remiseAutorisee(d), isTrue);
      expect(remiseIdEnvoye(null, d), isNull, reason: '$droits');
      d.refusConstate(droitRemiseVente);
      expect(remiseAutorisee(d), isFalse, reason: '403 : masquée, comme 4.15.0');
    }
  });

  test('route image : 404 / 405 → gabarit local ; aucun « vo-combine » ; jamais POST ticket/vno|vo', () {
    expect(TypeTicketServeur.values.map((t) => t.chemin), ['vno', 'vo', 'prevente']);
    final s = _lire('lib/services/ticket_serveur.dart');
    expect(s, contains('if (code == 404 || code == 405 || code == 501) {'));
    final i = _lire('lib/services/impression_ticket.dart');
    expect(i, contains('case RouteTicketAbsente():\n          return false;'));
    expect(i, contains('case TicketRefuse():\n          return false;'));
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      expect(f.readAsStringSync(), isNot(contains("'vo-combine'")), reason: f.path);
    }
  });

  test('net comptant : relu par net/vno sans `data` (même appel qu\'en 4.15.0)', () {
    final c = _lire('lib/ventes/prevente/vente_controller.dart');
    expect(c, contains('Future.wait([gateway.saleDetails(id), _netVno(id)])'));
    expect(c, contains('if (netRendu != null) {'));
    expect(c, contains('await _reload();'));
  });

  test('borne : changement de 4.15.0 gardé (confirmé par le pharmacien le 19/11)', () {
    expect(_lire('lib/borne/borne_screen.dart'), contains('aTerminer: !a.paiement!.clotureConfirmee'));
    expect(_lire('lib/borne/borne_screen.dart'), contains('PAYÉE, présentez ce ticket à la caisse'));
  });

  test('aucun journal dans le code de la demande 63', () {
    for (final p in [
      'lib/services/ticket_1bit.dart',
      'lib/services/ticket_serveur.dart',
      'lib/services/impression_ticket.dart',
      'lib/ventes/common/remise_vente.dart',
    ]) {
      final s = _lire(p);
      for (final m in ['print(', 'debugPrint(', 'log(', 'Journal', 'developer']) {
        expect(s.replaceAll('AlertDialog(', ''), isNot(contains(m)), reason: '$p : $m');
      }
    }
  });
}
