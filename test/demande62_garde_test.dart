// NON-RÉGRESSION — 4.15.0 (demande 62, serveur correctif/demande62-1911 PAS encore fusionné dans l'intégration) :
// avec le serveur d'aujourd'hui, tout reste comme en 4.14.0, sauf la remise ouverte aux comptes de prévente :
//  - « Terminer une vente » : toujours les trois mêmes droits ; P_BORNE_PAIEMENT_MOBILE n'y entre jamais ;
//  - clôture automatique : mêmes décisions qu'en 4.14.0 pour toute liste de droits sans P_BORNE_PAIEMENT_MOBILE ;
//  - 4.15.2 (demande 64) : plus de repli cloturer:false (règle du pharmacien : payer à la borne termine la vente) ;
//  - prévente payée : seulement si `paiementMobile` est présent ; la page d'encaissement d'origine sinon ;
//  - aucun journal (ni nom, ni numéro, ni texte de ticket) dans le code de la demande 62.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';

String _lire(String p) => File(p).readAsStringSync();

void main() {
  test('« Terminer une vente » : mêmes trois droits qu\'en 4.14.0 ; le droit de la borne n\'en fait pas partie', () {
    expect(DroitsVente.terminerVenteDroits, {'P_SM_CLOTURER_CAISSE', 'P_SM_DEPOT_EXTENSION', 'P_BT_MODIFICATION_DE_VENTE'});
    expect(_lire('lib/droits/droits_vente.dart'), contains('bool get terminerVente => _unDe(terminerVenteDroits);'));
  });

  test('clôture automatique : décisions de 4.14.0 inchangées sans le droit de la borne', () {
    final d = DroitsVente();
    for (final droits in <Set<String>?>[
      null,
      {},
      {'P_SM_VENTE'},
      {'P_SM_CLOTURER_CAISSE'},
      {'P_SM_DEPOT_EXTENSION'},
      {'P_BT_MODIFICATION_DE_VENTE'},
      {'P_SM_VENTE', 'P_BT_ANNULER_VENTE'},
    ]) {
      d.fixer(droits);
      expect(d.cloturerPaiementMobile, d.terminerVente, reason: '$droits');
      expect(d.bornePaiementMobile, isFalse);
    }
  });

  test('4.15.2 (demande 64) : plus aucun repli cloturer:false, nulle part ; la borne demande toujours cloturer:true', () {
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      expect(f.readAsStringSync(), isNot(contains('repliSiInterdit')), reason: f.path);
    }
    expect(_lire('lib/borne/borne_screen.dart'), contains('a.demarrer(venteId: p.venteId, operateur: op, cloturer: true);'));
  });

  test('« vente terminée » à la borne seulement si le serveur confirme la clôture', () {
    expect(_lire('lib/borne/borne_screen.dart'), contains('aTerminer: !a.paiement!.clotureConfirmee'));
    expect(_lire('lib/paiements/paiements_mobile.dart'), contains('bool get clotureConfirmee => statut == StatutPM.paye && cloture;'));
  });

  test('prévente payée : activée seulement par le champ du serveur ; page d\'origine sinon', () {
    final p = _lire('lib/ventes/prevente/encaissement_page.dart');
    expect(p, contains('final PreventePayee? dejaPayee;'));
    expect(p, contains('bool get _impose => _payee != null && widget.dejaPayeeImpose;'));
    expect(p, contains('_impose && _methods != null ? _bottomPayee() : _bottom(methods, method)'));
    expect(_lire('lib/paiements/prevente_payee.dart'), contains("final pm = vente['paiementMobile'];\n    if (pm is! Map) return null;"));
  });

  test('confidentialité : aucun journal dans le code de la demande 62', () {
    for (final p in ['lib/paiements/prevente_payee.dart', 'lib/ventes/prevente/encaissement_page.dart', 'lib/ventes/prevente/prevente_list.dart']) {
      expect(RegExp(r'\b(print|debugPrint|journalErreur|log)\(').hasMatch(_lire(p)), isFalse, reason: p);
    }
  });

  test('la borne ne propose jamais de remise ; la remise ne dépend plus de « Terminer une vente »', () {
    for (final f in Directory('lib/borne').listSync(recursive: true).whereType<File>()) {
      expect(f.readAsStringSync(), isNot(contains('RemiseVenteZone')), reason: f.path);
    }
    final r = _lire('lib/ventes/common/remise_vente.dart');
    expect(r, isNot(contains('d.connus && !d.terminerVente')));
    expect(r, contains('return !d.controle(droitRemiseVente);'));
  });
}
