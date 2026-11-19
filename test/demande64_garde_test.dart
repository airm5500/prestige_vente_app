// NON-RÉGRESSION — 4.15.2 : réponse du serveur aux demandes 64 (correctif/demande64-1911, d6cf51fa5) et 65
// (plan/support-1811, f8ef5afa6), PAS encore fusionnées ni déployées (officine : integration 76aa5fc1) :
//  - règle du pharmacien du 19/11 (« s'il paye par mobile money la vente est validée ») : à la borne, jamais de
//    paiement `cloturer:false`, jamais de nouvelle demande après un refus ; sans droit de clôture, pas de mobile money ;
//  - comptoir : `cloturer` toujours absent (false) comme en 4.15.1 ; routes et corps du panier inchangés ;
//  - refus lus dans `msg` puis `message` (panier) et `message` puis `msg` (paiement) ;
//  - demande 65 : route image du ticket et sa lecture inchangées ;
//  - confidentialité : aucun journal du texte d'un refus de panier (il peut nommer un produit).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/borne/borne_screen.dart';

String _lire(String p) => File(p).readAsStringSync();

void main() {
  test('borne : toujours cloturer:true, une seule demande, aucun repli cloturer:false nulle part', () {
    final borne = _lire('lib/borne/borne_screen.dart');
    expect(borne, contains('a.demarrer(venteId: p.venteId, operateur: op, cloturer: true);'));
    expect(borne, isNot(contains('cloturer: false')));
    expect(borne, isNot(contains('_clotureLancee')));
    expect(borne, contains('List<String> get _opsProposes => _clotureAuto ? _opsMobile : const [];'));
    expect(borne, contains('if ((a.interdit || a.refusAvantPaiement) && vue == BorneVue.mobile) {'));
    final pm = _lire('lib/paiements/paiements_mobile.dart');
    expect(RegExp(r'api\.creer\(').allMatches(pm), hasLength(1), reason: 'une seule demande de création par appel');
    expect(pm, isNot(contains('repliSansCloture')));
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      expect(f.readAsStringSync(), isNot(contains('repliSiInterdit')), reason: f.path);
    }
  });

  test('borne : avis du client inchangé (même texte pour le 403 et le refus de la demande 64)', () {
    expect(BorneScreen.avisMobileIndisponible, 'Paiement mobile indisponible, rendez-vous à la caisse avec votre ticket.');
  });

  test('comptoir : paiement mobile money sans clôture automatique, comme en 4.15.1', () {
    expect(_lire('lib/paiements/attente_paiement_screen.dart'), contains('_a.demarrer(venteId: widget.venteId, operateur: widget.operateur, part: widget.part);'));
  });

  test('lecture des refus : paiement `message` d\'abord, panier `msg` d\'abord', () {
    expect(_lire('lib/paiements/paiements_mobile.dart'), contains("VenteRefused('\${body['message'] ?? body['msg'] ?? 'Paiement refusé par le serveur.'}')"));
    expect(_lire('lib/ventes/core/vente_gateway.dart'), contains("final msg = '\${body['msg'] ?? body['message'] ?? ''}'.trim();"));
    expect(_lire('lib/api/api_service.dart'), contains("final m = '\${d['msg'] ?? d['message'] ?? ''}'.trim();"));
  });

  test('routes et corps du panier inchangés (nouvelle et ancienne interface)', () {
    final gw = _lire('lib/ventes/core/vente_gateway.dart');
    expect(gw, contains("_dio.post('/vente/remove/vno/item/\$itemId')"));
    expect(gw, contains('_dio.post(\'/vente/update/item/vno\', data: {"itemId": itemId, "produitId": produitId, "qte": qte, "qteServie": qte, "itemPu": itemPu})'));
    expect(gw, contains('_dio.post(\'/vente/remise\', data: {"remiseId": remiseId, "venteId": venteId})'));
    final api = _lire('lib/api/api_service.dart');
    expect(api, contains("final response = await _dio.post('/vente/remove/vno/item/\$itemId'); _noterRefusPanier(response);"));
    expect(api, contains('"qteServie": qte, "itemPu": itemPu, }); _noterRefusPanier(response); return response.statusCode == 200'));
  });

  test('demande 65 : route image du ticket et lecture inchangées', () {
    final t = _lire('lib/services/ticket_serveur.dart');
    expect(t, contains("static String chemin(TypeTicketServeur type, String id) => '/vente/ticket/\${type.chemin}/\${Uri.encodeComponent(id)}/image';"));
    expect(t, contains("queryParameters: {'largeur': mm, 'dpi': dpi},"));
    expect(t, contains('return TicketRefuseVente(msg.isEmpty ? \'Le serveur n\\\'a pas rendu le ticket.\' : msg);'));
  });

  test('confidentialité : aucun journal du texte d\'un refus de panier ni du motif côté écran', () {
    final sp = _lire('lib/providers/sale_provider.dart');
    final panier = sp.substring(sp.indexOf('Future<String?> addProductToCart'), sp.indexOf('Future<Map<String, dynamic>> cloturerVente'));
    expect(RegExp(r'\b(print|debugPrint|journalErreur|log)\(').hasMatch(panier), isFalse, reason: 'SaleProvider : ajout, modification, retrait');
    for (final p in [
      'lib/screens/pre_vente/widgets/sale_cart_widget.dart',
      'lib/ventes/common/vente_messages.dart',
      'lib/ventes/core/vente_result.dart',
    ]) {
      expect(RegExp(r'\b(print|debugPrint|journalErreur|log)\(').hasMatch(_lire(p)), isFalse, reason: p);
    }
    final api = _lire('lib/api/api_service.dart');
    final i = api.indexOf('void _noterRefusPanier');
    expect(api.substring(i, api.indexOf('\n  }', i)), isNot(contains('journal')));
  });
}
