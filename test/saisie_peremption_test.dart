// 4.11.0 — UNITAIRES : saisie manuelle de la péremption, règle UNIQUE (lib/services/saisie_peremption.dart) partagée
// par « Mise à jour péremption » et la réception des BL (plan du pharmacien du 08/11 : « 0128 = 01/01/2028,
// 010128 = 01/01/2028 ») ; nombre de lignes des commandes ; écarts de la clôture « au reçu » ; droit « Voir les
// suggestions de réserve » ; échelle des icônes par type d'écran. Données FICTIVES.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/droits/droits_modules.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/services/saisie_peremption.dart';
import 'package:prestige_vente_app/ui/icones.dart';

void main() {
  group('saisie de la péremption (règle de « Mise à jour péremption »)', () {
    test('sans barres : MMAA, JJMMAA, JJMMAAAA', () {
      expect(lireDatePeremption('0128'), DateTime(2028, 1, 1));
      expect(lireDatePeremption('010128'), DateTime(2028, 1, 1));
      expect(lireDatePeremption('01012028'), DateTime(2028, 1, 1));
      expect(lireDatePeremption('1229'), DateTime(2029, 12, 1));
      expect(lireDatePeremption('311227'), DateTime(2027, 12, 31));
    });
    test('avec séparateurs (/ - . espace), jour et mois sur 1 ou 2 chiffres', () {
      expect(lireDatePeremption('31/12/2027'), DateTime(2027, 12, 31));
      expect(lireDatePeremption('1/1/28'), DateTime(2028, 1, 1));
      expect(lireDatePeremption('01-01-2028'), DateTime(2028, 1, 1));
      expect(lireDatePeremption('01.01.28'), DateTime(2028, 1, 1));
      expect(lireDatePeremption('05/2028'), DateTime(2028, 5, 1));
      expect(lireDatePeremption(' 0128 '), DateTime(2028, 1, 1));
    });
    test('dates impossibles ou illisibles : refusées, jamais « corrigées »', () {
      for (final s in ['', '1', '12345', '1328', '310228', '320128', '000128', '31/02/2027', '13/2027', 'AB12', '0128x', '1/1/202']) {
        expect(lireDatePeremption(s), isNull, reason: s);
      }
    });
    test('réception : parseExpiryInput = même règle ; affichage JJ/MM/AAAA', () {
      for (final s in ['0128', '010128', '01012028', '31/12/2027', '05/2028', '310228']) {
        expect(parseExpiryInput(s), lireDatePeremption(s), reason: s);
      }
      expect(formaterDatePeremption(DateTime(2028, 1, 1)), '01/01/2028');
    });
  });

  group('réception', () {
    test('commandes : nombre de LIGNES (int_LINE), boîtes à défaut', () {
      final o = ReceptionOrder.fromJson({'lg_ORDER_ID': 'O1', 'int_NBRE_PRODUIT': 48, 'int_LINE': 3});
      expect(o.lines, 3);
      expect(o.linesLabel, 'lignes');
      expect(o.products, 48);
      final un = ReceptionOrder.fromJson({'lg_ORDER_ID': 'O2', 'int_NBRE_PRODUIT': 5, 'int_LINE': 1});
      expect(un.linesLabel, 'ligne');
      final ancien = ReceptionOrder.fromJson({'lg_ORDER_ID': 'O3', 'int_NBRE_PRODUIT': 5});
      expect(ancien.lines, 5);
      expect(ancien.linesLabel, 'boîtes', reason: 'serveur sans int_LINE : jamais « lignes » pour des boîtes');
    });
    test('écarts de la clôture « au reçu » (demande 59)', () {
      const r = ReceptionResult(true, 'ok', {
        'success': true,
        'ecarts': [
          {'cip': '3595583', 'nom': 'PRODUIT FICTIF', 'commande': 10, 'recu': 7, 'manquant': 3},
          {'cip': '3000000', 'nom': 'AUTRE', 'commande': '4', 'recu': '0', 'manquant': '4'},
        ]
      });
      final e = ecartsDe(r);
      expect(e, hasLength(2));
      expect(e.first.manquant, 3);
      expect(e.last.recu, 0);
      expect(ecartsDe(const ReceptionResult(true, 'ok')), isEmpty);
    });
  });

  test('réserve : « Voir les suggestions » absent = vrai (serveur sans la demande 60), faux = masqué', () {
    final d = DroitsModules();
    d.fixer(reserveDedie: true);
    expect(d.reserveSuggestions, isTrue);
    d.fixer(reserveDedie: true, reserveSuggestions: false);
    expect(d.reserveSuggestions, isFalse);
    d.oublier();
    expect(d.reserveSuggestions, isTrue);
  });

  test('icônes : tablette ×1,33, terminal ×1,25, téléphone inchangé', () {
    expect(EchelleIcones.pour(const Size(800, 1280)), EchelleIcones.tablette);
    expect(EchelleIcones.pour(const Size(1280, 800)), EchelleIcones.tablette);
    expect(EchelleIcones.pour(const Size(360, 720)), EchelleIcones.terminal, reason: 'Sunmi V2s');
    expect(EchelleIcones.pour(const Size(360, 640)), EchelleIcones.terminal, reason: 'Sunmi V3');
    expect(EchelleIcones.pour(const Size(360, 800)), 1.0, reason: 'téléphone courant');
    expect(EchelleIcones.pour(const Size(411, 914)), 1.0);
    final t = EchelleIcones.theme(ThemeData(), 1.25);
    expect(t.iconTheme.size, 30);
    expect(t.appBarTheme.actionsIconTheme?.size, 30);
  });
}
