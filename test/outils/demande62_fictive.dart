// 4.15.0 — Demande 62, côté FAUX serveur Prestige (données FICTIVES uniquement), avec les règles du code de la branche
// serveur correctif/demande62-1911 (fb0a3cc2), lues dans le code :
//  - GET v1/user/droits : P_BORNE_PAIEMENT_MOBILE dans la liste des comptes qui l'ont (table du faux serveur) ;
//  - POST v1/paiements-mobile : `cloturer:true` exige P_SM_CLOTURER_CAISSE, P_SM_DEPOT_EXTENSION,
//    P_BT_MODIFICATION_DE_VENTE ou (demande 62) P_BORNE_PAIEMENT_MOBILE ; sinon 403 `interdit` AVANT toute création
//    (PaiementsMobileRessource.creer) ; `cloturer:false` : aucun droit ;
//  - confirmation (statut payé) : clôture automatique au nom du créateur du paiement ; refusée sans caisse ouverte
//    pour ce compte → `cloture:false`, message « Clôture refusée : … » (PaiementsMobileService.cloturer) ;
//  - GET v1/ventestats/{id} et GET v1/ventestats/preventes : `paiementMobile` + `typeReglementAttente` pour une
//    prévente ouverte payée, non clôturée (SalesStatsRessource.signalerPaiementsMobile) ;
//  - POST v1/vente/cloturer/vno : refus `{success:false, msg, codeError:0, paiementMobile:true}` si le mode de
//    l'opérateur ne porte pas exactement le montant payé (ClotureComptoir.refus), rien n'est écrit ; sinon clôture,
//    puis paiement marqué clôturé (« Vente terminée au comptoir »).
// [d62] false : serveur d'intégration d'aujourd'hui (aucun champ, aucun contrôle, droit inconnu).
import 'faux_serveur_prestige.dart';

/// Paiement mobile money fictif d'une vente.
class PaiementFictif {
  final String id;
  final String venteId;
  final int montant;
  final String operateur;
  final String login;
  final bool clotureAuto;
  String statut;
  bool cloture;
  String message;
  PaiementFictif(this.id, this.venteId, this.montant, this.operateur, this.login, this.clotureAuto)
      : statut = 'en_attente',
        cloture = false,
        message = '';
}

const _typeReglement = {'orange': '7', 'moov': '8', 'mtn': '9', 'wave': '10'};
const _libelle = {'orange': 'Orange Money', 'moov': 'Moov Money', 'mtn': 'MTN MoMo', 'wave': 'Wave'};
const droitsTerminer = {'P_SM_CLOTURER_CAISSE', 'P_SM_DEPOT_EXTENSION', 'P_BT_MODIFICATION_DE_VENTE'};
const droitBorne = 'P_BORNE_PAIEMENT_MOBILE';

class Demande62Fictive {
  final FauxServeurPrestige s;

  /// Serveur avec la branche de la demande 62 (false : intégration d'aujourd'hui).
  bool d62;

  /// Comptes dont la caisse est ouverte (clôture automatique possible).
  final Set<String> caissesOuvertes = {};

  /// Paiements créés (id → paiement) et requêtes reçues.
  final Map<String, PaiementFictif> paiements = {};
  final List<Map<String, dynamic>> creations = [];
  final List<Map<String, dynamic>> clotures = [];
  final List<String> refusClotures = [];
  int _n = 0;

  /// Contrôle supplémentaire avant la création d'un paiement (demande 64), null : aucun.
  String? Function(String? login, String venteId, Map<String, dynamic> corps)? controleAvantCreation;

  Demande62Fictive(this.s, {this.d62 = true, int nombreVentes = 40}) {
    s.routes['GET /paiements-mobile/capacites'] = (_) => FauxServeurPrestige.ok({
          'success': true,
          'paiementsMobile': ['wave', 'orange'],
          'paiementsMobileVersion': 1,
          'fournisseur': 'simulateur',
          'expirationMin': 10,
          'typesReglement': _typeReglement,
        });
    s.routes['POST /paiements-mobile'] = (r) {
      final j = r.json;
      creations.add(Map<String, dynamic>.from(j));
      final login = _compte(r);
      final cloturer = j['cloturer'] == true;
      if (cloturer) {
        final d = _droits(login);
        final ok = d.any(droitsTerminer.contains) || (d62 && d.contains(droitBorne));
        if (!ok) {
          return FauxServeurPrestige.interdit(d62
              ? 'Droit manquant : Terminer une vente (menu « Ventes ») ou Clôturer une vente payée par mobile money (borne).'
              : 'Droit manquant : Terminer une vente (menu « Ventes »).');
        }
      }
      final venteId = '${j['venteId']}';
      // 4.15.2 : contrôle ajouté par la demande 64 (test/outils/demande64_fictive.dart), après le droit, avant toute
      // création : `{success:false, message}`.
      final refus = controleAvantCreation?.call(login, venteId, j);
      if (refus != null) return FauxServeurPrestige.ok({'success': false, 'message': refus});
      final montant = _net(venteId);
      final p = PaiementFictif('PM-FICT-${++_n}', venteId, montant, '${j['operateur']}', login ?? '', cloturer);
      _ajouter(p);
      return FauxServeurPrestige.ok({'success': true, 'data': _json(p)});
    };
    // Relecture d'une vente : champs de la demande 62 ajoutés à la réponse existante.
    for (var i = 1; i <= nombreVentes; i++) {
      final id = 'V-$i';
      final avant = s.routes['GET /ventestats/$id'];
      s.routes['GET /ventestats/$id'] = (r) async {
        final st = s.statutVentes[id];
        if (st == null) return FauxServeurPrestige.refus('Vente introuvable');
        Map<String, dynamic> data = {'strSTATUT': st, 'lgTYPEVENTEID': '1', 'lgPREENREGISTREMENTID': id};
        if (avant != null) {
          final b = (await avant(r)).corps;
          if (b is Map && b['data'] is Map) data = {...data, ...Map<String, dynamic>.from(b['data'] as Map)};
        }
        _signaler(data);
        return FauxServeurPrestige.ok({'success': true, 'data': data});
      };
    }
    s.routes['GET /ventestats/preventes'] = (_) {
      final l = [
        for (final e in s.ventes.entries)
          if (s.statutVentes[e.key] == 'is_Process')
            _signaler({
              'lgPREENREGISTREMENTID': e.key,
              'heure': '10:4${e.key.length % 10}:00',
              'dtUPDATED': '19/11/2026',
              'intPRICE': _net(e.key),
              'strREF': 'REF-${e.key}',
              'userFullName': 'Vendeur Fictif',
              'lgTYPEVENTEID': '1',
            }),
      ];
      return FauxServeurPrestige.ok({'data': l, 'total': l.length});
    };
    final avantCloture = s.routes['POST /vente/cloturer/vno'];
    s.routes['POST /vente/cloturer/vno'] = (r) async {
      final j = r.json;
      clotures.add(Map<String, dynamic>.from(j));
      final venteId = '${j['venteId'] ?? ''}';
      final p = aEncaisser(venteId);
      if (d62 && p != null) {
        final motif = refusComptoir(p, j);
        if (motif != null) {
          refusClotures.add(venteId);
          return FauxServeurPrestige.ok({'success': false, 'msg': motif, 'codeError': 0, 'paiementMobile': true});
        }
      }
      final rep = avantCloture != null ? await avantCloture(r) : FauxServeurPrestige.ok({'success': true});
      if (s.statutVentes.containsKey(venteId) && avantCloture == null) s.statutVentes[venteId] = 'is_Closed';
      final b = rep.corps;
      if (d62 && p != null && b is Map && b['success'] == true) {
        p.cloture = true;
        p.message = 'Vente terminée au comptoir';
      }
      return rep;
    };
  }

  /// Paiement enregistré, avec sa route de statut (GET v1/paiements-mobile/{id}).
  void _ajouter(PaiementFictif p) {
    paiements[p.id] = p;
    s.routes['GET /paiements-mobile/${p.id}'] = (_) => FauxServeurPrestige.ok({'success': true, 'data': _json(p)});
  }

  String? _compte(RequeteRecue r) => r.jsessionid == null ? null : s.compteSession[r.jsessionid];

  Set<String> _droits(String? login) {
    final d = s.droitsComptes;
    if (d == null) return droitsTerminer; // serveur ancien sans lecture des droits : tout passe, comme avant
    return {...(d[login] ?? FauxServeurPrestige.droitsComplets)};
  }

  int _net(String venteId) => (s.ventes[venteId] ?? const []).fold<int>(0, (a, l) => a + (l['intPRICE'] as int));

  Map<String, dynamic> _json(PaiementFictif p) => {
        'id': p.id,
        'venteId': p.venteId,
        'reference': 'REF-${p.venteId}',
        'montant': p.montant,
        'devise': 'XOF',
        'operateur': p.operateur,
        'typeReglement': _typeReglement[p.operateur],
        'fournisseur': 'simulateur',
        'statut': p.statut,
        'lien': 'simulateur://${p.id}',
        'clotureAuto': p.clotureAuto,
        'cloture': p.cloture,
        'message': p.message,
        'creeLe': '2026-11-19 10:40:00.0',
        'expireLe': '2026-11-19 10:50:00.0',
        'payeLe': p.statut == 'paye' ? '2026-11-19 10:42:07.0' : '',
        'aRegulariser': false,
      };

  /// Le client paie : statut payé, puis clôture automatique (si demandée) au nom du créateur du paiement.
  void payer(String paiementId) {
    final p = paiements[paiementId]!;
    p.statut = 'paye';
    if (!p.clotureAuto || p.cloture) return;
    if (!caissesOuvertes.contains(p.login)) {
      p.message = 'Clôture refusée : Votre caisse est fermée';
      return;
    }
    p.cloture = true;
    if (s.statutVentes.containsKey(p.venteId)) s.statutVentes[p.venteId] = 'is_Closed';
  }

  /// Prévente payée à la borne SANS clôture (cloturer:false ou clôture refusée), directement (tests du comptoir).
  PaiementFictif payeeALaBorne(String venteId, {String operateur = 'wave', int? montant}) {
    final p = PaiementFictif('PM-FICT-${++_n}', venteId, montant ?? _net(venteId), operateur, 'borne.fictive', false)..statut = 'paye';
    _ajouter(p);
    return p;
  }

  /// Prévente créée par la borne (un article fictif de [prix] F), en attente au comptoir ; [payee] : payée par
  /// mobile money sans clôture. Renvoie son identifiant.
  String preventeDeLaBorne({int prix = 4125, bool payee = true, String operateur = 'wave'}) {
    final id = 'V-${s.ventes.length + 1}';
    s.ventes[id] = [
      {
        'lgPREENREGISTREMENTDETAILID': '$id-L1',
        'lgFAMILLEID': 'F1',
        'strNAME': 'PRODUIT 0001 CPR B/20',
        'intCIP': '3400900000001',
        'intQUANTITY': 1,
        'intPRICEUNITAIR': prix,
        'intPRICE': prix,
        'strREF': 'REF-$id',
      }
    ];
    s.statutVentes[id] = 'is_Process';
    if (payee) payeeALaBorne(id, operateur: operateur);
    return id;
  }

  /// Paiement payé, non clôturé, d'une vente encore ouverte (PaiementsMobileService.aEncaisser).
  PaiementFictif? aEncaisser(String venteId) {
    if (s.statutVentes[venteId] == 'is_Closed') return null;
    for (final p in paiements.values.toList().reversed) {
      if (p.venteId == venteId && p.statut == 'paye' && !p.cloture) return p;
    }
    return null;
  }

  Map<String, dynamic> _signaler(Map<String, dynamic> vente) {
    if (!d62) return vente;
    final p = aEncaisser('${vente['lgPREENREGISTREMENTID']}');
    if (p == null) return vente;
    vente['paiementMobile'] = {
      ..._json(p),
      'operateurLibelle': _libelle[p.operateur],
      'referenceFournisseur': 'TX-FICT-0042',
    };
    vente['typeReglementAttente'] = _typeReglement[p.operateur];
    return vente;
  }

  /// ClotureComptoir.refus (serveur) : le mode de l'opérateur doit porter exactement le montant payé.
  static String? refusComptoir(PaiementFictif p, Map<String, dynamic> j) {
    final type = _typeReglement[p.operateur]!;
    final reglements = j['reglements'];
    int porte;
    if (reglements is! List || reglements.isEmpty) {
      final sansDetail = (j['montantPaye'] as num?)?.toInt() ?? (j['totalRecap'] as num?)?.toInt() ?? 0;
      porte = '${j['typeRegleId'] ?? ''}'.trim() == type ? sansDetail : 0;
    } else {
      porte = 0;
      for (final r in reglements) {
        if (r is Map && '${r['typeReglement'] ?? ''}'.trim() == type) porte += (r['montant'] as num).toInt();
      }
    }
    if (porte == p.montant) return null;
    final l = _libelle[p.operateur];
    return 'Cette prévente est déjà payée par $l : ${p.montant} F (n° TX-FICT-0042). Terminez-la avec le mode $l pour ce '
        'montant, sans encaisser à nouveau.';
  }
}
