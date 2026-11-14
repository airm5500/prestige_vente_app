// 4.13.0 — Client d'une vente comptant, côté FAUX serveur Prestige (données FICTIVES uniquement), avec les règles du
// serveur réel (branche integration/recette-2026-10-29, lues dans le code) :
//  - GET v1/client/lambda?query= : clients standard (type 6), nom, prénom, « nom prénom » ou numéro, espaces ignorés ;
//  - POST v1/client/add/lambda : nom mis en majuscules ; nom ET prénom vides, texte > 50 ou type inconnu refusés
//    (`success:false, msg`) ; chaque création est comptée ;
//  - POST v1/vente/update/client {venteId, clientId} : vente inconnue / terminée → `success:false, msg` ; identifiant
//    inconnu → `success:true` « Client inconnu : le client de la vente est inchangé. » ; clientId null → client retiré ;
//  - GET v1/ventestats/{id} : statut et champ `client` (lgCLIENTID, strFIRSTNAME, strLASTNAME, strADRESSE) ;
//  - POST v1/vente/cloturer/vno : clôture (corps gardé) ; un clientId CONNU rattache le client (comme le serveur),
//    un clientId inconnu ou absent laisse le client de la vente tel quel.
import 'faux_serveur_prestige.dart';

class ClientsVenteFictifs {
  final FauxServeurPrestige s;

  /// Clients du serveur (lgCLIENTID → fiche), dont les fiches créées par l'application.
  final Map<String, Map<String, dynamic>> clients = {};

  /// Client rattaché à chaque vente (venteId → lgCLIENTID).
  final Map<String, String> clientDeVente = {};

  /// Requêtes reçues (pour les vérifications).
  final List<String> recherches = [];
  final List<Map<String, dynamic>> creations = [];
  final List<({String venteId, String? clientId})> rattachements = [];
  final List<Map<String, dynamic>> clotures = [];

  /// Réponses forcées (refus de droit, session changée…) ; null = comportement normal.
  ReponseLocale? Function(RequeteRecue r)? forcerRecherche;
  ReponseLocale? Function(RequeteRecue r)? forcerCreation;
  ReponseLocale? Function(RequeteRecue r)? forcerRattachement;
  Duration delaiRattachement = Duration.zero;
  Duration delaiRecherche = Duration.zero;

  int _n = 0;

  ClientsVenteFictifs(this.s, {bool clientsDeBase = true, int nombreVentes = 40}) {
    if (clientsDeBase) {
      ajouter('CL-FICT-1', 'KOFFI-TEST', 'AMANI', '0700000001', telephoneFiche: '07 00 00 00 01');
      ajouter('CL-FICT-2', 'KOFFI-TEST', 'BINTOU', '0500000002', telephoneFiche: '05 00 00 00 02');
      ajouter('CL-FICT-3', 'YAO-FICTIF', 'CELESTE', '0100000003', telephoneFiche: '01 00 00 00 03');
    }
    s.routes['GET /client/lambda'] = (r) {
      final q = r.query['query'] ?? '';
      recherches.add(q);
      final f = forcerRecherche?.call(r);
      if (f != null) return f;
      final l = chercher(q);
      return FauxServeurPrestige.ok({'success': true, 'data': l, 'total': l.length}, delai: delaiRecherche);
    };
    s.routes['POST /client/add/lambda'] = (r) {
      final j = r.json;
      creations.add(Map<String, dynamic>.from(j));
      final f = forcerCreation?.call(r);
      if (f != null) return f;
      String t(String k) => '${j[k] ?? ''}'.trim();
      if (t('strFIRSTNAME').isEmpty && t('strLASTNAME').isEmpty) return FauxServeurPrestige.refus('Le nom ou le prénom du client est obligatoire.');
      for (final (k, l) in [('strFIRSTNAME', 'Le nom'), ('strLASTNAME', 'Le prénom'), ('strADRESSE', 'L\'adresse ou le téléphone')]) {
        if (t(k).length > 50) return FauxServeurPrestige.refus('$l ne doit pas dépasser 50 caractères.');
      }
      final type = t('lgTYPECLIENTID');
      if (type.isNotEmpty && type != '6' && type != '1' && type != '2') return FauxServeurPrestige.refus('Type de client inconnu.');
      final id = 'CL-CREE-${++_n}';
      final c = ajouter(id, t('strFIRSTNAME').toUpperCase(), t('strLASTNAME').toUpperCase(), t('strADRESSE'), type: type.isEmpty ? null : type);
      return FauxServeurPrestige.ok({'success': true, 'data': c, 'total': 1});
    };
    s.routes['POST /vente/update/client'] = (r) {
      final j = r.json;
      final venteId = '${j['venteId'] ?? ''}';
      final clientId = j['clientId'] == null ? null : '${j['clientId']}';
      rattachements.add((venteId: venteId, clientId: clientId));
      final f = forcerRattachement?.call(r);
      if (f != null) return f;
      final statut = s.statutVentes[venteId];
      if (statut == null) return FauxServeurPrestige.refus('Cette vente n\'existe plus : actualisez l\'écran de vente.');
      if (statut == 'is_Closed') {
        return FauxServeurPrestige.refus('La vente REF-$venteId est déjà terminée : elle ne peut plus être modifiée.');
      }
      if (clientId != null && clientId.trim().isNotEmpty && !clients.containsKey(clientId)) {
        return FauxServeurPrestige.ok({'success': true, 'msg': 'Client inconnu : le client de la vente est inchangé.'}, delai: delaiRattachement);
      }
      if (clientId == null || clientId.trim().isEmpty) {
        clientDeVente.remove(venteId);
      } else {
        clientDeVente[venteId] = clientId;
      }
      return FauxServeurPrestige.ok({'success': true, 'msg': 'Opération effectuée avec success'}, delai: delaiRattachement);
    };
    // Relecture d'une vente (V-1 … V-n du faux serveur) avec son client, comme reloadVenteById.
    for (var i = 1; i <= nombreVentes; i++) {
      final id = 'V-$i';
      s.routes['GET /ventestats/$id'] = (r) {
        final st = s.statutVentes[id];
        if (st == null) return FauxServeurPrestige.refus('Vente introuvable');
        final c = clientDeVente[id];
        return FauxServeurPrestige.ok({
          'success': true,
          'data': {'strSTATUT': st, 'lgTYPEVENTEID': '1', 'client': c == null ? null : clients[c]}
        });
      };
    }
    s.routes['POST /vente/cloturer/vno'] = (r) {
      final j = r.json;
      clotures.add(Map<String, dynamic>.from(j));
      final id = '${j['venteId'] ?? ''}';
      if (s.statutVentes[id] == 'is_Closed') return FauxServeurPrestige.refus('Cette vente a déjà été clôturée');
      if (s.statutVentes.containsKey(id)) s.statutVentes[id] = 'is_Closed';
      final c = j['clientId'];
      if (c is String && clients.containsKey(c)) clientDeVente[id] = c;
      return FauxServeurPrestige.ok({'success': true});
    };
  }

  /// Téléphone de la FICHE (strTELEPHONE, saisi sur le poste) : c'est lui que la recherche par numéro du serveur lit.
  /// La création rapide range le téléphone dans strADRESSE et ne remplit pas strTELEPHONE (code du serveur).
  final Map<String, String> telephoneFiche = {};

  /// Ajoute un client fictif au serveur.
  Map<String, dynamic> ajouter(String id, String nom, String prenom, String telephone, {String? type = '6', String? telephoneFiche}) {
    if (telephoneFiche != null) this.telephoneFiche[id] = telephoneFiche;
    return clients[id] = {'lgCLIENTID': id, 'strFIRSTNAME': nom, 'strLASTNAME': prenom, 'strADRESSE': telephone, 'lgTYPECLIENTID': type};
  }

  /// Recherche du serveur : clients standard dont nom, prénom ou « nom prénom » commence par le texte, ou dont le
  /// numéro de FICHE (strTELEPHONE, séparateurs ignorés) contient les chiffres tapés.
  List<Map<String, dynamic>> chercher(String q) {
    final t = q.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
    final chiffres = t.replaceAll(RegExp(r'[\s.\-+]'), '');
    final numero = RegExp(r'^\d+$').hasMatch(chiffres);
    return [
      for (final c in clients.values)
        if (c['lgTYPECLIENTID'] == '6' &&
            (numero
                ? (telephoneFiche[c['lgCLIENTID']] ?? '').replaceAll(RegExp(r'[\s.\-]'), '').contains(chiffres)
                : ('${c['strFIRSTNAME']}'.startsWith(t) || '${c['strLASTNAME']}'.startsWith(t) || '${c['strFIRSTNAME']} ${c['strLASTNAME']}'.startsWith(t))))
          c,
    ];
  }

  /// Réponses des refus de sécurité (DEMANDE_SESSION_MOBILE_VENTES.md).
  static const ReponseLocale interdit403 =
      ReponseLocale({'success': false, 'interdit': true, 'msg': 'Vous n\'avez pas le droit d\'associer un client à une vente.'}, statut: 403);
  static const ReponseLocale sessionChangee409 = ReponseLocale(
      {'success': false, 'sessionChangee': true, 'msg': 'Un autre compte s\'est connecté sur ce navigateur. Rien n\'a été enregistré.'},
      statut: 409);
}
