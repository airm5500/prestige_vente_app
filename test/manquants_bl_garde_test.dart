// NON-RÉGRESSION — Prestige Mobile 4.12.0 (demandes 59 et 60 livrées le 08/11) : garde-fous sur le code.
//  - clôture classique du BL inchangée (aucun paramètre, aucun en-tête) ; clôture au reçu avec X-Client-Ref ;
//  - retour des manquants : seulement par la capacité `retourManquants`, toujours avec X-Client-Ref, jamais par la
//    file d'envoi hors ligne (stock_sender / stock_queue n'y touchent pas) ;
//  - le champ `reserve` de la clôture n'est jamais utilisé pour proposer une suggestion (aucune fenêtre « réserve
//    après entrée » côté mobile) ;
//  - demande 60 : 403 du droit « Voir les suggestions de réserve » constaté sur les routes de lecture et d'action,
//    jamais sur `creer` ni `motifs` ; « Réessayer » masqué sur un droit manquant.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _lire(String f) => File(f).readAsStringSync();

void main() {
  test('réception : clôture classique inchangée, clôture au reçu avec X-Client-Ref', () {
    final g = _lire('lib/reception/reception_gateway.dart');
    expect(g, contains("dio.put('/commande/validerbl/\$blId');"), reason: 'clôture classique sans paramètre ni en-tête');
    expect(g, contains("queryParameters: {'mode': 'RECU'}, options: clientRef == null ? null : Options(headers: {enteteClientRef: clientRef})"));
    final s = _lire('lib/screens/reception_bl/reception_summary_screen.dart');
    expect(s, contains('validateRecu(widget.bl.id, clientRef: _cleRecu)'));
    expect(s, contains('estAucunRecu(r)'));
    expect(s, contains("_retourManquants == true && mg is RetourManquantsGateway"));
  });

  test('retour des manquants : capacité, X-Client-Ref, en ligne seulement', () {
    final g = _lire('lib/reception/reception_gateway.dart');
    expect(g, contains("['retourManquants'] == true"));
    expect(g, contains("'/reception/\${Uri.encodeComponent(blId)}/retour-manquants',\n          options: Options(headers: {enteteClientRef: clientRef})"));
    expect(_lire('lib/reception/manquants_bl.dart'), contains('Future<RetourManquants> creerRetourManquants(String blId, {required String clientRef});'));
    for (final f in ['lib/horsligne/stock/stock_sender.dart', 'lib/horsligne/stock/stock_queue.dart']) {
      expect(_lire(f), isNot(contains('retour-manquants')), reason: '$f : jamais dans la file d\'envoi');
    }
    final hl = _lire('lib/horsligne/stock/stock_gateways.dart');
    expect(hl, contains("if (_off || o is! RetourManquantsGateway) return RetourManquants.refus('Retour des manquants : \$kEnLigneUniquement.');"));
  });

  test('aucune suggestion proposée à partir de `reserve` de la clôture', () {
    for (final f in Directory('lib/screens/reception_bl').listSync().whereType<File>()) {
      expect(f.readAsStringSync(), isNot(contains("data['reserve']")), reason: f.path);
    }
  });

  test('réserve : 403 « Voir les suggestions » constaté sur lecture et actions, jamais sur creer / motifs', () {
    final a = _lire('lib/reserve/reserve_api.dart');
    for (final route in ['en-attente', '/ouvrir', '/quantite', "ligne/\${Uri.encodeComponent(detailId)}', {'motif'", '/traiter', '/reessayer']) {
      expect(RegExp('_voir\\(\\(\\) => client\\.[a-z]+\\(\'/suggestion-reserve/[^\\n]*${RegExp.escape(route)}').hasMatch(a), isTrue, reason: route);
    }
    expect(a, contains("client.post('/suggestion-reserve/creer'"));
    expect(a, isNot(contains("_voir(() => client.post('/suggestion-reserve/creer'")));
    expect(a, contains("await client.getListe('/suggestion-reserve/motifs'"));
    for (final f in ['lib/reserve/reserve_screen.dart', 'lib/reserve/reserve_traitement_screen.dart', 'lib/reserve/reserve_panier_screen.dart']) {
      expect(_lire(f), contains('onReessayer: estDroitManquant('), reason: f);
    }
  });
}
