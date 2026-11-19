// 4.15.2 — Demande 64, côté FAUX serveur Prestige (données FICTIVES uniquement), avec les règles du code de la branche
// serveur correctif/demande64-1911 (d6cf51fa5), lues dans le code (PaiementsMobileService.creer, SalesServiceImpl,
// VenteRessource, ClotureComptoir) :
//  - POST v1/paiements-mobile avec `cloturer:true` sur une vente comptant, pour tout le net (sans `part`) : APRÈS le
//    contrôle du droit (403 `interdit`), AVANT toute création, les contrôles de la clôture en lecture seule (caisse du
//    compte connecté ouverte, vente en cours avec des produits…) ; refus
//    `{success:false, message:"Paiement mobile money impossible : <motif> Le client paie à la caisse."}` (HTTP 200),
//    rien n'est créé, l'opérateur n'est pas appelé. Sans `cloturer`, ou avec `part` : inchangé ;
//  - verrou du panier tant qu'un paiement est payé (ou en cours, non expiré) et non clôturé : ajout (add/item),
//    retrait (remove/vno/item/{id}), quantité (update/item/vno), remise (vente/remise) refusés avec
//    `{success:false, msg}` et rien n'est écrit. Messages de ClotureComptoir.refusModificationPanier ;
//  - le verrou tombe quand le paiement en cours est annulé ou expiré.
// [d64] false : serveur déployé en officine (integration 76aa5fc1) : aucun de ces contrôles (comme 4.15.1).
// Le faux serveur de base n'a ni update/item/vno, ni remove/vno/item, ni vente/remise : ils sont simulés ici.
import 'demande62_fictive.dart';
import 'faux_serveur_prestige.dart';
import 'serveur_json_local.dart';

const _libelles = {'orange': 'Orange Money', 'moov': 'Moov Money', 'mtn': 'MTN MoMo', 'wave': 'Wave'};

/// ClotureComptoir.refusModificationPanier (serveur, demande 64).
String refusModificationPanierFictif(String operateur, int montant, {required bool paye}) {
  final l = _libelles[operateur] ?? operateur;
  return paye
      ? 'Cette prévente est déjà payée par $l ($montant F) : le panier ne peut plus être modifié. Terminez-la au comptoir '
          'avec ce paiement, sans encaisser à nouveau.'
      : 'Un paiement $l de $montant F est en cours sur cette prévente : le panier ne peut pas être modifié pendant le '
          'paiement.';
}

/// ClotureComptoir.refusPaiement (serveur, demande 64).
String refusPaiementFictif(String motif) => 'Paiement mobile money impossible : $motif Le client paie à la caisse.';

/// Messages exacts annoncés par le serveur (REPONSE_DEMANDES64_65_2026-11-19.md).
const messagePayeWave4125 = 'Cette prévente est déjà payée par Wave (4125 F) : le panier ne peut plus être modifié. '
    'Terminez-la au comptoir avec ce paiement, sans encaisser à nouveau.';
const messageEnCoursOrange4125 =
    'Un paiement Orange Money de 4125 F est en cours sur cette prévente : le panier ne peut pas être modifié pendant le paiement.';
const messageCaisseFermee = 'Paiement mobile money impossible : la caisse de la borne est fermée. Le client paie à la caisse.';

class Demande64Fictive {
  final FauxServeurPrestige s;
  final Demande62Fictive d62;

  /// Serveur avec la branche de la demande 64 (false : serveur déployé en officine, 76aa5fc1).
  bool d64;

  /// Modifications du panier refusées (route, vente) et appliquées.
  final List<String> refus = [];
  final List<String> appliquees = [];

  /// Remise posée sur chaque vente (vente/remise).
  final Map<String, String?> remises = {};

  Demande64Fictive(this.s, {this.d64 = true, bool d62Actif = true, int nombreVentes = 40})
      : d62 = Demande62Fictive(s, d62: d62Actif, nombreVentes: nombreVentes) {
    d62.controleAvantCreation = (login, venteId, j) {
      if (!d64 || j['cloturer'] != true || (j['part'] != null)) return null;
      if (!d62.caissesOuvertes.contains(login)) return refusPaiementFictif('la caisse de la borne est fermée.');
      if (s.statutVentes[venteId] != 'is_Process') return refusPaiementFictif('la vente n\'est plus en cours.');
      if ((s.ventes[venteId] ?? const []).isEmpty) return refusPaiementFictif('la vente n\'a aucun produit.');
      return null;
    };
    final avant = s.filtreAvantSession;
    s.filtreAvantSession = (r) async {
      final ReponseLocale? rep = avant == null ? null : await avant(r);
      if (rep != null) return rep;
      return _panier(r);
    };
  }

  /// Paiement EN COURS (en attente, non expiré) d'une vente, créé au comptoir (sans clôture automatique).
  PaiementFictif paiementEnCours(String venteId, {String operateur = 'orange', int? montant}) {
    final p = PaiementFictif('PM-FICT-EC-${d62.paiements.length + 1}', venteId, montant ?? _net(venteId), operateur, 'comptoir.fictif', false);
    d62.paiements[p.id] = p;
    return p;
  }

  /// Le paiement en cours est annulé (ou expire) : le verrou tombe.
  void annuler(PaiementFictif p) => p.statut = 'annule';

  int _net(String venteId) => (s.ventes[venteId] ?? const []).fold<int>(0, (a, l) => a + (l['intPRICE'] as int));

  /// SalesServiceImpl.controlePreventePayee : paiement payé d'abord, sinon en cours ; non clôturé.
  String? verrou(String venteId) {
    if (!d64) return null;
    PaiementFictif? enCours;
    for (final p in d62.paiements.values) {
      if (p.venteId != venteId || p.cloture) continue;
      if (p.statut == 'paye') return refusModificationPanierFictif(p.operateur, p.montant, paye: true);
      if (p.statut == 'en_attente') enCours ??= p;
    }
    return enCours == null ? null : refusModificationPanierFictif(enCours.operateur, enCours.montant, paye: false);
  }

  String? _venteDeLigne(String itemId) {
    for (final e in s.ventes.entries) {
      if (e.value.any((l) => l['lgPREENREGISTREMENTDETAILID'] == itemId)) return e.key;
    }
    return null;
  }

  ReponseLocale _refus(String route, String venteId, String msg) {
    refus.add('$route $venteId');
    return FauxServeurPrestige.ok({'success': false, 'msg': msg});
  }

  Future<ReponseLocale?> _panier(RequeteRecue r) async {
    final c = r.chemin;
    if (r.methode != 'POST') return null;
    if (c.endsWith('/vente/add/item')) {
      final id = '${r.json['venteId']}';
      final v = verrou(id);
      if (v != null) return _refus('add/item', id, v);
      appliquees.add('add/item $id');
      return null; // ajout du faux serveur de base
    }
    if (c.endsWith('/vente/update/item/vno')) {
      final j = r.json;
      final itemId = '${j['itemId']}';
      final id = _venteDeLigne(itemId);
      if (id == null) return FauxServeurPrestige.ok({'success': false, 'msg': 'Ce produit n\'est plus dans la vente.'});
      final v = verrou(id);
      if (v != null) return _refus('update/item/vno', id, v);
      final l = s.ventes[id]!.firstWhere((x) => x['lgPREENREGISTREMENTDETAILID'] == itemId);
      final qte = (j['qte'] as num).toInt();
      final pu = (j['itemPu'] as num?)?.toInt() ?? l['intPRICEUNITAIR'] as int;
      l['intQUANTITY'] = qte;
      l['intPRICEUNITAIR'] = pu;
      l['intPRICE'] = qte * pu;
      appliquees.add('update/item/vno $id');
      return FauxServeurPrestige.ok({'success': true});
    }
    final m = RegExp(r'/vente/remove/vno/item/([^/]+)$').firstMatch(c);
    if (m != null) {
      final itemId = m.group(1)!;
      final id = _venteDeLigne(itemId);
      if (id == null) return FauxServeurPrestige.ok({'success': false, 'msg': 'Ce produit n\'est plus dans la vente : actualisez l\'écran avant de continuer.'});
      final v = verrou(id);
      if (v != null) return _refus('remove/vno/item', id, v);
      s.ventes[id]!.removeWhere((x) => x['lgPREENREGISTREMENTDETAILID'] == itemId);
      appliquees.add('remove/vno/item $id');
      final net = _net(id);
      return FauxServeurPrestige.ok({'success': true, 'data': {'montant': net, 'montantNet': net, 'remise': 0}});
    }
    if (c.endsWith('/vente/remise')) {
      final j = r.json;
      final id = '${j['venteId']}';
      final v = verrou(id);
      if (v != null) return _refus('remise', id, v);
      remises[id] = j['remiseId'] == null ? null : '${j['remiseId']}';
      appliquees.add('remise $id');
      return FauxServeurPrestige.ok({'success': true});
    }
    return null;
  }
}
