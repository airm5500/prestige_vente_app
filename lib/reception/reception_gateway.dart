// lib/reception/reception_gateway.dart
// Appels au serveur Prestige pour la réception des BL. Fonctions existantes de Prestige (écran
// « gestion des lots » du BL) : aucune modification du serveur n'est nécessaire.
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/client_ref.dart';
import 'package:prestige_vente_app/reception/manquants_bl.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';

abstract class ReceptionGateway {
  Future<List<ReceptionBl>> bls({String query = ''});
  Future<List<ReceptionOrder>> orders();

  /// « Créer BL » depuis une commande (n° de BL refusé s'il existe déjà chez ce grossiste).
  Future<ReceptionResult> createBl({
    required String orderId,
    required String ref,
    required DateTime date,
    required int amountHt,
    required int tva,
  });

  /// Lignes du BL. [query] : CIP, EAN ou début du nom (recherche du serveur).
  Future<List<ReceptionLine>> lines(String blId, {String query = ''});

  /// [serie] / [gtin] (4.3.1, D18) : numéro de série et GTIN du DataMatrix de la boîte scannée ; un serveur à
  /// jour refuse une boîte déjà scannée (`code:"SERIE_DEJA_CONSOMMEE"`), un ancien serveur les ignore.
  Future<ReceptionResult> addLot({
    required String detailId,
    required int quantity,
    required int freeQty,
    required String numLot,
    DateTime? expiry,
    String? serie,
    String? gtin,
  });

  /// Efface tous les lots saisis sur la ligne (pour ressaisir).
  Future<ReceptionResult> clearLots(ReceptionLine line);

  /// Quantité contrôlée (information de pointage, utilisée par « Pointage BL Stock »).
  Future<void> markChecked(String detailId, int quantity);

  /// Droit « entrée en stock » de l'utilisateur connecté.
  Future<bool> canValidate();

  Future<ReceptionResult> validate(String blId);
}

/// 4.11.0 (plan du 08/11, demande 59) : terminer un BL incomplet en entrant SEULEMENT ce qui a été reçu, l'écart allant
/// au rapport. Seulement si le serveur l'annonce (`clotureRecu` de `GET v1/reception/parametres`) ; sinon (serveur
/// actuel), le BL incomplet reste ouvert : rien n'est jamais entré à la quantité commandée par ce chemin.
abstract class ClotureRecuGateway {
  Future<bool> clotureRecuDisponible();

  /// `PUT v1/commande/validerbl/{id}?mode=RECU` (droit P_ENTREE_EN_STOCK) : réponse `{success, mode:"RECU", msg,
  /// ecarts:[{detailId, cip, nom, commande, recu, ug, manquant}], totalManquant, reserve}` ; refus `code:"AUCUN_RECU"`
  /// (aucune ligne n'a de lot : rien n'entre, le BL reste ouvert).
  /// 4.12.0 : [clientRef] = en-tête `X-Client-Ref` (même clé = même réponse, rien n'est rejoué ; un refus n'est pas
  /// gardé par le serveur, la même clé peut donc resservir après un refus).
  Future<ReceptionResult> validateRecu(String blId, {String? clientRef});
}

/// Écart d'une ligne entrée « au reçu » (réponse `ecarts` de la demande 59).
typedef EcartBl = ({String cip, String nom, int commande, int recu, int manquant});

/// 4.12.0 : refus de la clôture « au reçu » quand aucune ligne du BL n'a de lot (rien n'entre, le BL reste ouvert).
const String codeAucunRecu = 'AUCUN_RECU';

/// Message affiché pour le refus [codeAucunRecu].
const String messageAucunRecu = 'Aucune boîte n\'a été saisie sur ce BL : rien n\'est entré en stock et le BL reste ouvert. '
    'Saisissez les lots reçus, ou laissez le BL pour validation sur Prestige.';

/// Vrai pour le refus [codeAucunRecu].
bool estAucunRecu(ReceptionResult r) => !r.success && '${r.data['code'] ?? ''}' == codeAucunRecu;

/// Écarts renvoyés par la clôture « au reçu » (vide si absents).
List<EcartBl> ecartsDe(ReceptionResult r) {
  final l = r.data['ecarts'];
  if (l is! List) return const [];
  int n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  return [
    for (final e in l)
      if (e is Map)
        (cip: '${e['cip'] ?? ''}', nom: '${e['nom'] ?? ''}', commande: n(e['commande']), recu: n(e['recu']), manquant: n(e['manquant'])),
  ];
}

class DioReceptionGateway implements ReceptionGateway, ClotureRecuGateway, RetourManquantsGateway {
  final Dio dio;
  DioReceptionGateway(this.dio);

  static final _iso = DateFormat('yyyy-MM-dd');

  List<Map<String, dynamic>> _list(dynamic data) {
    final list = data is Map ? data['data'] : null;
    if (list is! List) return const [];
    return [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)];
  }

  ReceptionResult _result(dynamic data, {String ok = 'Opération effectuée'}) {
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final success = m['success'] != false;
      return ReceptionResult(success, '${m['msg'] ?? (success ? ok : 'Échec de l\'opération')}', m);
    }
    return ReceptionResult(true, ok);
  }

  /// 4.6.0 (décision 12) : 403 `interdit` sur add-lot / creerbl = droit P_BL_MOBILE_SCANNER contrôlé par ce serveur
  /// (le scan est ensuite masqué pour ce compte) ; message du serveur affiché, jamais de déconnexion.
  ReceptionResult _errorScanner(Object e) {
    if (e is DioException && refusDeDroit(e.response?.statusCode, e.response?.data) != null) {
      DroitsVente.instance.controleConstate(DroitsVente.scannerBlDroit);
      return ReceptionResult(false, refusDeDroit(e.response?.statusCode, e.response?.data)!, const {'interdit': true});
    }
    return _error(e);
  }

  ReceptionResult _error(Object e) {
    if (e is DioException) {
      final r = e.response;
      // 4.3.3 : serveur injoignable ≠ Prestige en démarrage / redéploiement.
      final panne = panneDe(e);
      if (panne != null) return ReceptionResult(false, MessagesServeur.message(panne));
      if (r?.data is Map && (r!.data as Map)['msg'] != null) return ReceptionResult(false, '${(r.data as Map)['msg']}');
      if (r != null) return ReceptionResult(false, 'Erreur du serveur (${r.statusCode}).');
      return const ReceptionResult(false, MessagesServeur.injoignable);
    }
    return ReceptionResult(false, '$e');
  }

  @override
  Future<List<ReceptionBl>> bls({String query = ''}) async {
    final r = await dio.get('/commande/list-bons', queryParameters: {
      'query': query,
      'start': 0,
      'limit': 200,
      'statut': 'enable',
    });
    return _list(r.data).map(ReceptionBl.fromJson).toList();
  }

  @override
  Future<List<ReceptionOrder>> orders() async {
    final params = {'start': 0, 'limit': 200, 'query': ''};
    final encours = await dio.get('/commande/list', queryParameters: params);
    final passees = await dio.get('/commande/list/passees', queryParameters: params);
    return [
      ..._list(passees.data).map(ReceptionOrder.fromJson),
      ..._list(encours.data).map(ReceptionOrder.fromJson),
    ];
  }

  @override
  Future<ReceptionResult> createBl({
    required String orderId,
    required String ref,
    required DateTime date,
    required int amountHt,
    required int tva,
  }) async {
    try {
      final r = await dio.post('/commande/creerbl', data: {
        'refParent': orderId,
        'ref': ref,
        'dtStart': _iso.format(date),
        'value': amountHt,
        'valueTwo': tva,
      });
      return _result(r.data, ok: 'BL créé');
    } catch (e) {
      return _errorScanner(e);
    }
  }

  @override
  Future<List<ReceptionLine>> lines(String blId, {String query = ''}) async {
    final r = await dio.get('/commande/bon/items/$blId', queryParameters: {
      'start': 0,
      'limit': 9999,
      'query': query,
      'filtre': 'ALL',
    });
    return _list(r.data).map(ReceptionLine.fromJson).toList();
  }

  @override
  Future<ReceptionResult> addLot({
    required String detailId,
    required int quantity,
    required int freeQty,
    required String numLot,
    DateTime? expiry,
    String? serie,
    String? gtin,
  }) async {
    Map<String, dynamic> corps({required bool avecSerie}) => {
          'idBonDetail': detailId,
          'qty': quantity,
          'freeQty': freeQty,
          'numLot': numLot,
          'datePeremption': expiry == null ? '' : _iso.format(expiry),
          // Toujours un nouveau lot (le mode « import direct » remplacerait le lot existant).
          'directImport': false,
          ...champsSerie(serie, gtin, avecSerie: avecSerie),
        };
    try {
      final r = await dio.post('/commande/add-lot', data: corps(avecSerie: true));
      return resultatAjoutLot(_result(r.data, ok: 'Lot enregistré'));
    } on DioException catch (e) {
      // Serveur qui refuserait des champs inconnus (400 avant toute écriture) : même lot, sans série.
      if (e.response?.statusCode == 400 && champsSerie(serie, gtin).isNotEmpty) {
        try {
          final r = await dio.post('/commande/add-lot', data: corps(avecSerie: false));
          return resultatAjoutLot(_result(r.data, ok: 'Lot enregistré'));
        } catch (e2) {
          return _errorScanner(e2);
        }
      }
      return _errorScanner(e);
    } catch (e) {
      return _error(e);
    }
  }

  @override
  Future<ReceptionResult> clearLots(ReceptionLine line) async {
    try {
      await dio.put('/commande/remove-lots', data: {
        // removeLot=false : uniquement les lots de CE produit sur CE BL.
        'removeLot': false,
        'idProduit': line.produitId,
        'refBon': line.blRef,
        'idBonDetail': line.detailId,
      });
      return const ReceptionResult(true, 'Lots de la ligne effacés');
    } catch (e) {
      return _error(e);
    }
  }

  @override
  Future<void> markChecked(String detailId, int quantity) async {
    try {
      await dio.post('/commande/bon/items/checked-quantities', data: {'id': detailId, 'checked': true, 'checkedQuantity': quantity});
    } catch (_) {
      // Information secondaire : sans effet sur la réception.
    }
  }

  @override
  Future<bool> canValidate() async {
    try {
      final r = await dio.get('/commande/entree-stock/autorisation');
      return r.data is Map && (r.data as Map)['authorize'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ReceptionResult> validate(String blId) async {
    try {
      final r = await dio.put('/commande/validerbl/$blId');
      return _result(r.data, ok: 'Entrée en stock effectuée');
    } catch (e) {
      return _error(e);
    }
  }

  /// Lecture en cours de `GET v1/reception/parametres` : les deux capacités, demandées ensemble par le bilan, ne font
  /// qu'UN appel (rien n'est gardé ensuite : un serveur mis à jour est relu au bilan suivant).
  Future<Map<String, dynamic>>? _parametres;

  Future<Map<String, dynamic>> _lireParametres() => _parametres ??= () async {
        try {
          final r = await dio.get('/reception/parametres');
          return r.data is Map ? Map<String, dynamic>.from(r.data as Map) : const <String, dynamic>{};
        } catch (_) {
          return const <String, dynamic>{}; // serveur sans la route ou injoignable : capacités absentes
        }
      }()
          .whenComplete(() => _parametres = null);

  @override
  Future<bool> clotureRecuDisponible() async {
    final p = await _lireParametres();
    return p['clotureRecu'] == true; // serveur sans la route ou sans la demande 59 : chemin désactivé
  }

  @override
  Future<ReceptionResult> validateRecu(String blId, {String? clientRef}) async {
    try {
      final r = await dio.put('/commande/validerbl/$blId',
          queryParameters: {'mode': 'RECU'}, options: clientRef == null ? null : Options(headers: {enteteClientRef: clientRef}));
      return _result(r.data, ok: 'Entrée en stock effectuée (reçu)');
    } catch (e) {
      return _error(e);
    }
  }

  @override
  Future<bool> retourManquantsDisponible() async => (await _lireParametres())['retourManquants'] == true;

  @override
  Future<EcartsBl> ecartsBl(String blId) async {
    try {
      final r = await dio.get('/reception/${Uri.encodeComponent(blId)}/ecarts');
      return EcartsBl.fromJson(r.data);
    } on DioException catch (e) {
      return EcartsBl.refus(_error(e).message, code: codeDe(e.response?.data), status: e.response?.statusCode);
    } catch (e) {
      return EcartsBl.refus(_error(e).message);
    }
  }

  @override
  Future<RetourManquants> creerRetourManquants(String blId, {required String clientRef}) async {
    try {
      final r = await dio.post('/reception/${Uri.encodeComponent(blId)}/retour-manquants',
          options: Options(headers: {enteteClientRef: clientRef}));
      return RetourManquants.fromJson(r.data);
    } on DioException catch (e) {
      final interdit = refusDeDroit(e.response?.statusCode, e.response?.data);
      if (interdit != null) return RetourManquants.refus(interdit, interdit: true, status: 403);
      return RetourManquants.refus(_error(e).message, code: codeDe(e.response?.data), status: e.response?.statusCode);
    } catch (e) {
      return RetourManquants.refus(_error(e).message);
    }
  }
}

/// 4.6.0 (décision 12) : entrée en stock refusée tant que des produits ne sont pas saisis.
const String codeProduitsNonSaisis = 'PRODUITS_NON_SAISIS';

/// Produits nommés par le refus `PRODUITS_NON_SAISIS` de `commande/validerbl` (« CIP NOM (3/10) ») ; null pour un
/// autre résultat. Liste absente (forme inattendue) : lue dans le message « Produits non saisis : a, b ».
List<String>? produitsNonSaisis(ReceptionResult r) {
  if (r.success || '${r.data['code'] ?? ''}' != codeProduitsNonSaisis) return null;
  final l = r.data['produits'];
  if (l is List && l.isNotEmpty) return [for (final p in l) if ('$p'.trim().isNotEmpty) '$p'.trim()];
  final m = r.message.replaceFirst(RegExp(r'^\s*Produits non saisis\s*:\s*', caseSensitive: false), '');
  return [for (final p in m.split(RegExp(r',\s+(?=\S)'))) if (p.trim().isNotEmpty) p.trim()];
}

/// D18 (4.3.1) : refus d'une boîte déjà scannée par le serveur.
const String codeSerieDejaConsommee = 'SERIE_DEJA_CONSOMMEE';

/// Message affiché pour une boîte déjà scannée.
const String messageBoiteDejaScannee = 'Boîte déjà scannée';

/// Champs `serie` / `gtin` du corps de `commande/add-lot` (vides si absents ; [avecSerie] faux : aucun).
Map<String, dynamic> champsSerie(String? serie, String? gtin, {bool avecSerie = true}) {
  final s = (serie ?? '').trim();
  if (!avecSerie || s.isEmpty) return const {};
  final g = (gtin ?? '').trim();
  return {'serie': s, if (g.isNotEmpty) 'gtin': g};
}

/// Réponse de `commande/add-lot` : le refus « boîte déjà scannée » reçoit son message clair et son code.
ReceptionResult resultatAjoutLot(ReceptionResult r) {
  if (r.success) return r;
  if ('${r.data['code'] ?? ''}' == codeSerieDejaConsommee) {
    return ReceptionResult(false, '$messageBoiteDejaScannee : cette boîte a déjà été enregistrée. Aucune quantité ajoutée ; scannez la boîte suivante.', r.data);
  }
  return r;
}
