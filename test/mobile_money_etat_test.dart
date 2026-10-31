// 4.10.2 — UNITAIRES : ligne d'état Mobile Money (retour du pharmacien du 31/10), mêmes conditions que la borne et
// l'encaissement : réglage, serveur joignable, capacités (404 = serveur ancien ; aucun opérateur = pas de compte de
// paiement sur le serveur), droit de clôture du compte qui paie (droits inconnus : pas d'obstacle).
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/paiements/etat_mobile_money.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

void main() {
  Future<DiagnosticMobileMoney> diag({
    bool actif = true,
    bool horsLigne = false,
    VenteResult<CapacitesPM> cap = const VenteOk(CapacitesPM(operateurs: ['orange', 'wave'])),
    Set<String>? droits = const {'P_SM_VENTE', 'P_SM_CLOTURER_CAISSE'},
    bool borne = true,
  }) {
    var appels = 0;
    return diagnostiquerMobileMoney(
      actif: actif,
      horsLigne: horsLigne,
      capacites: () async {
        appels++;
        return cap;
      },
      droits: () async => droits,
      compte: 'borne.pos',
      borne: borne,
    ).then((d) {
      if (!actif || horsLigne) expect(appels, 0, reason: 'aucune requête inutile');
      return d;
    });
  }

  test('tout bon : « Proposé au client : Orange Money, Wave. »', () async {
    final d = await diag();
    expect(d.etat, EtatMobileMoney.propose);
    expect(d.message, 'Proposé au client : Orange Money, Wave.');
    expect((await diag(droits: null)).etat, EtatMobileMoney.propose, reason: 'droits inconnus (serveur ancien) : pas d\'obstacle');
  });

  test('option décochée ; hors ligne : sans requête', () async {
    expect((await diag(actif: false)).etat, EtatMobileMoney.desactive);
    final h = await diag(horsLigne: true);
    expect(h.message, 'Serveur injoignable : impossible de vérifier.');
  });

  test('404 : serveur sans module ; aucun opérateur : pas de compte de paiement (modes de la caisse insuffisants)', () async {
    final a = await diag(cap: const VenteRefused('Paiement mobile money non disponible sur ce serveur.', code: '404'));
    expect(a.message, 'Serveur sans module Mobile Money (version ancienne).');
    final v = await diag(cap: const VenteOk(CapacitesPM()));
    expect(v.etat, EtatMobileMoney.sansCompte);
    expect(v.message, startsWith('Mobile Money activé, mais le serveur Prestige n\'a pas de compte de paiement configuré (agrégateur).'));
    expect(v.message, contains('Les modes Wave / Orange de la caisse ne suffisent pas'));
    expect(v.message, isNot(contains('PRESTIGE_PAIEMENTS')), reason: 'aucun nom de variable dans le message');
    final deux = await diag(cap: const VenteOk(CapacitesPM()), droits: const {'P_SM_VENTE'});
    expect(deux.message, contains('n\'a pas le droit de clôturer'), reason: 'les deux obstacles signalés');
  });

  test('sans droit de clôture : compte de la borne nommé ; compte de l\'appareil', () async {
    final b = await diag(droits: const {'P_SM_VENTE'});
    expect(b.etat, EtatMobileMoney.sansDroit);
    expect(b.message,
        'Mobile Money activé, mais le compte de la borne « borne.pos » n\'a pas le droit de clôturer : donnez-lui P_SM_CLOTURER_CAISSE (ou P_SM_DEPOT_EXTENSION, P_BT_MODIFICATION_DE_VENTE).');
    for (final d in ['P_SM_DEPOT_EXTENSION', 'P_BT_MODIFICATION_DE_VENTE']) {
      expect((await diag(droits: {d})).etat, EtatMobileMoney.propose, reason: d);
    }
    expect((await diag(droits: const {}, borne: false)).message, startsWith('Mobile Money activé, mais le compte « borne.pos »'));
  });

  test('réseau coupé pendant la vérification : injoignable ; autre erreur : « Vérification impossible »', () async {
    expect((await diag(cap: const VenteFailed('Paiement : serveur injoignable (connectionError).'))).etat, EtatMobileMoney.horsLigne);
    final e = await diag(cap: const VenteFailed('Paiement : erreur du serveur (code 500).'));
    expect(e.etat, EtatMobileMoney.erreur);
    expect(e.message, 'Vérification impossible : Paiement : erreur du serveur (code 500).');
  });
}
