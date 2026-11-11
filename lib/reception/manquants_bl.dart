// lib/reception/manquants_bl.dart
// 4.12.0 (demande 59 livrée par le serveur le 08/11) : écarts d'un BL et retour fournisseur des manquants.
// 4.12.1 (réponse du serveur à la demande 61, 11/11) : un retour ABANDONNÉ (`is_Abandoned`) ne compte plus (le POST en
// crée un nouveau, `deja:false`) ; `retourManquants` des écarts peut donc être un abandonné (le plus récent) ; la
// réponse `deja:true` et `retourManquants` portent `lignes` et `totalManquant` (lus s'ils sont présents : un serveur
// plus ancien ne les envoie pas).
//
//   GET  v1/reception/parametres                → capacité `retourManquants: true` (absente : serveur plus ancien,
//                                                 aucune de ces fonctions n'est proposée)
//   GET  v1/reception/{blId}/ecarts             → {success, blId, ref, mode: RECU|PROVISOIRE|COMPLET, provisoire,
//                                                 ecarts:[{detailId, cip, nom, commande, recu, ug, manquant}],
//                                                 totalManquant, retourManquants: null | {retourId, ref, statut
//                                                 [, lignes, totalManquant]}} (le plus récent, abandonné compris)
//                                                 refus 404 BL_INCONNU
//   POST v1/reception/{blId}/retour-manquants   (P_SM_RETOUR_FRS ou P_VALIDER_RETOUR_FRS, X-Client-Ref)
//                                               → {success, deja, retourId, ref, statut:"is_Waiting", lignes,
//                                                 totalManquant, route, msg} (retour existant non abandonné :
//                                                 deja:true, même forme depuis le 11/11 ; avant, sans lignes ni
//                                                 totalManquant) ; refus 409 BL_NON_ENTRE_AU_RECU, 409
//                                                 AUCUN_MANQUANT, 404 BL_INCONNU, 403 {interdit:true, msg}
//
// Le retour des manquants est créé EN ATTENTE de validation, motif « Manquant », SANS sortie de stock : les boîtes
// n'ont jamais été entrées (option a du pharmacien, 08/11). Rien n'est envoyé hors ligne : ces routes sont en ligne
// seulement (la clôture du BL l'est aussi).
import 'package:uuid/uuid.dart';

/// Passerelle des écarts et du retour des manquants (implémentée par la passerelle Dio de la réception et par la
/// passerelle hors ligne, qui la désactive sans réseau).
abstract class RetourManquantsGateway {
  /// Capacité `retourManquants` de `GET v1/reception/parametres` (faux si absente, route absente ou serveur coupé).
  Future<bool> retourManquantsDisponible();

  /// Bilan des écarts du BL, tel que le serveur le calcule (provisoire tant que le BL est ouvert).
  Future<EcartsBl> ecartsBl(String blId);

  /// Crée (ou relit, `deja:true`) le retour en attente des manquants. [clientRef] : en-tête `X-Client-Ref`, à garder
  /// identique pour un nouvel essai après un délai dépassé (le serveur renvoie alors la même réponse).
  Future<RetourManquants> creerRetourManquants(String blId, {required String clientRef});
}

/// Nouvelle clé `X-Client-Ref` (préfixe lisible dans les traces du serveur).
String nouvelleCleClotureRecu() => 'BLR-${const Uuid().v4()}';
String nouvelleCleRetourManquants() => 'BLM-${const Uuid().v4()}';

/// Code de refus (`code`) d'un corps JSON, vide sinon.
String codeDe(Object? corps) => corps is Map ? '${corps['code'] ?? ''}'.trim() : '';

int _n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

/// Nombre facultatif : null si absent ou illisible (serveur plus ancien).
int? _nOpt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim());
String _t(Object? v) => v == null ? '' : '$v'.trim();

/// Ligne en écart (reçu < commandé).
class LigneEcart {
  final String detailId;
  final String cip;
  final String nom;
  final int commande;
  final int recu;
  final int ug;
  final int manquant;
  const LigneEcart({this.detailId = '', this.cip = '', required this.nom, required this.commande, required this.recu, this.ug = 0, required this.manquant});

  factory LigneEcart.fromJson(Map m) => LigneEcart(
        detailId: _t(m['detailId']),
        cip: _t(m['cip']),
        nom: _t(m['nom']),
        commande: _n(m['commande']),
        recu: _n(m['recu']),
        ug: _n(m['ug']),
        manquant: _n(m['manquant']),
      );

  String get libelle => '$nom — reçu $recu/$commande, manquant $manquant';
}

/// Lignes en écart d'une réponse (`ecarts`), vide si absentes.
List<LigneEcart> lignesEcart(Object? l) => [
      if (l is List)
        for (final e in l)
          if (e is Map) LigneEcart.fromJson(e),
    ];

/// Total manquant d'une réponse (`totalManquant`), sinon somme des lignes [ecarts].
int totalManquantDe(Map j, List<LigneEcart> ecarts) =>
    j.containsKey('totalManquant') ? _n(j['totalManquant']) : ecarts.fold<int>(0, (t, e) => t + e.manquant);

/// Libellé d'un statut de retour fournisseur (états du serveur, 08/11).
String libelleStatutRetour(String statut) => switch (statut) {
      'is_Waiting' => 'en attente de validation',
      'is_Process' => 'en saisie',
      'is_Refused' => 'refusé',
      'is_Abandoned' => 'abandonné',
      'enable' => 'validé',
      _ => statut,
    };

/// Statut d'un retour abandonné sur Prestige : il ne compte plus (4.12.1, serveur du 11/11).
const statutRetourAbandonne = 'is_Abandoned';

/// « n ligne(s), m boîte(s) » si le serveur les donne, vide sinon.
String _detailRetour(int? lignes, int? total) => [
      if (lignes != null && lignes > 0) '$lignes ligne(s)',
      if (total != null && total > 0) '$total boîte(s)',
    ].join(', ');

/// Retour des manquants déjà créé pour un BL (le plus récent : il peut être abandonné).
class RetourExistant {
  final String retourId;
  final String ref;
  final String statut;

  /// Facultatifs (serveur du 11/11) : null si absents.
  final int? lignes;
  final int? totalManquant;
  const RetourExistant({required this.retourId, required this.ref, required this.statut, this.lignes, this.totalManquant});

  static RetourExistant? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = _t(j['retourId']);
    final ref = _t(j['ref']);
    if (id.isEmpty && ref.isEmpty) return null;
    return RetourExistant(retourId: id, ref: ref, statut: _t(j['statut']), lignes: _nOpt(j['lignes']), totalManquant: _nOpt(j['totalManquant']));
  }

  /// Abandonné sur Prestige : il ne compte plus, un nouveau retour peut être créé.
  bool get abandonne => statut == statutRetourAbandonne;

  String get libelle {
    final d = _detailRetour(lignes, totalManquant);
    return 'Retour $ref (${libelleStatutRetour(statut)}${d.isEmpty ? '' : ' ; $d'})';
  }

  /// Texte affiché selon le statut.
  String get texte => switch (statut) {
        statutRetourAbandonne => 'Retour $ref abandonné sur Prestige : il ne compte plus.',
        'is_Refused' => '$libelle : à corriger dans « Retour fournisseur » sur Prestige ; rien ne sort du stock.',
        'enable' => '$libelle : traité dans « Retour fournisseur » sur Prestige ; rien n\'est sorti du stock.',
        _ => '$libelle : à valider dans « Retour fournisseur » sur Prestige ; rien ne sort du stock.',
      };
}

/// Réponse de `GET v1/reception/{blId}/ecarts`.
class EcartsBl {
  final bool success;
  final String message;
  final String code;
  final int? status;
  final String ref;

  /// `RECU` (BL entré au reçu), `PROVISOIRE` (BL ouvert, calcul sur les lots saisis), `COMPLET` (ancienne voie).
  final String mode;
  final bool provisoire;
  final List<LigneEcart> ecarts;
  final int totalManquant;
  final RetourExistant? retour;

  const EcartsBl({
    required this.success,
    this.message = '',
    this.code = '',
    this.status,
    this.ref = '',
    this.mode = '',
    this.provisoire = false,
    this.ecarts = const [],
    this.totalManquant = 0,
    this.retour,
  });

  factory EcartsBl.refus(String message, {String code = '', int? status}) => EcartsBl(success: false, message: message, code: code, status: status);

  factory EcartsBl.fromJson(Object? j) {
    if (j is! Map) return EcartsBl.refus('Réponse inattendue du serveur.');
    if (j['success'] == false) return EcartsBl.refus(_t(j['msg']).isEmpty ? 'Écarts non lus.' : _t(j['msg']), code: codeDe(j));
    final ecarts = lignesEcart(j['ecarts']);
    final total = j.containsKey('totalManquant') ? _n(j['totalManquant']) : ecarts.fold<int>(0, (t, e) => t + e.manquant);
    final mode = _t(j['mode']).toUpperCase();
    return EcartsBl(
      success: true,
      ref: _t(j['ref']),
      mode: mode,
      provisoire: j['provisoire'] == true || mode == 'PROVISOIRE',
      ecarts: ecarts,
      totalManquant: total,
      retour: RetourExistant.fromJson(j['retourManquants']),
    );
  }

  bool get entreAuRecu => success && mode == 'RECU';
}

/// Réponse de `POST v1/reception/{blId}/retour-manquants`.
class RetourManquants {
  final bool success;
  final String message;
  final String code;
  final int? status;
  final bool interdit;

  /// Le retour existait déjà (second appel) : il est relu, rien n'est créé. Jamais pour un retour abandonné depuis le
  /// serveur du 11/11 (un serveur plus ancien renvoie encore l'abandonné).
  final bool deja;
  final String retourId;
  final String ref;
  final String statut;
  final int lignes;
  final int totalManquant;

  const RetourManquants({
    required this.success,
    this.message = '',
    this.code = '',
    this.status,
    this.interdit = false,
    this.deja = false,
    this.retourId = '',
    this.ref = '',
    this.statut = '',
    this.lignes = 0,
    this.totalManquant = 0,
  });

  factory RetourManquants.refus(String message, {String code = '', int? status, bool interdit = false}) =>
      RetourManquants(success: false, message: message, code: code, status: status, interdit: interdit);

  factory RetourManquants.fromJson(Object? j) {
    if (j is! Map) return RetourManquants.refus('Réponse inattendue du serveur.');
    if (j['success'] == false) {
      return RetourManquants.refus(_t(j['msg']).isEmpty ? 'Retour des manquants refusé.' : _t(j['msg']),
          code: codeDe(j), interdit: j['interdit'] == true);
    }
    return RetourManquants(
      success: true,
      message: _t(j['msg']),
      deja: j['deja'] == true,
      retourId: _t(j['retourId']),
      ref: _t(j['ref']),
      statut: _t(j['statut']),
      lignes: _n(j['lignes']),
      totalManquant: _n(j['totalManquant']),
    );
  }

  /// Retour à afficher après une réponse réussie (remplace l'éventuel retour abandonné).
  RetourExistant get retour => RetourExistant(
      retourId: retourId, ref: ref, statut: statut, lignes: lignes > 0 ? lignes : null, totalManquant: totalManquant > 0 ? totalManquant : null);

  /// Texte affiché à l'utilisateur.
  String get texte {
    if (!success) {
      return switch (code) {
        'BL_NON_ENTRE_AU_RECU' => 'Ce BL n\'a pas été entré au reçu : il n\'a pas de manquants enregistrés.',
        'AUCUN_MANQUANT' => 'Ce BL n\'a aucun manquant : aucun retour à créer.',
        'BL_INCONNU' => 'Ce BL n\'existe pas sur Prestige.',
        _ => message,
      };
    }
    if (deja && statut == statutRetourAbandonne) {
      // Serveur antérieur au 11/11 : il renvoie le retour abandonné au lieu d'en créer un nouveau.
      return 'Retour $ref abandonné : aucun nouveau retour n\'a été créé (serveur Prestige à mettre à jour).';
    }
    if (deja) {
      final d = _detailRetour(lignes, totalManquant);
      return 'Retour $ref déjà créé (${libelleStatutRetour(statut)}${d.isEmpty ? '' : ' ; $d'}).';
    }
    return 'Retour $ref créé, en attente de validation sur Prestige : rien ne sort du stock'
        '${lignes > 0 ? ' ($lignes ligne(s), $totalManquant boîte(s))' : ''}.';
  }
}
