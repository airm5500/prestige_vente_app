// lib/horsligne/journal/journal_interceptor.dart
// Point unique de journalisation EN LIGNE : intercepteur posé sur le Dio de l'appli. Les routes
// d'écriture connues (vente, encaissement, prévente, caisse, réception, pointage, péremptions,
// périmés, retours, ajustements, emplacement, connexion) sont notées dans le journal du terminal
// avec leur résultat (ok / refus + motif / échec réseau / déjà appliqué). Les écrans ne changent pas.
// Seuls des champs choisis du corps sont lus (jamais le mot de passe, jamais de jeton ni de cookie).
//
// Anti double encaissement / double mouvement : une requête « unique » (clôture, prévente, entrée en
// stock, création de retour, clôture de caisse…) IDENTIQUE à une requête encore en cours est bloquée
// (double appui, double appel) : elle échoue tout de suite sans partir vers le serveur.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';

/// Ce qu'on retient d'une requête d'écriture.
class _Regle {
  final String methode;
  final RegExp chemin;
  final TypeJournal type;
  final String action;

  /// Bloquer une requête identique déjà en cours.
  final bool unique;
  const _Regle(this.methode, this.chemin, this.type, this.action, {this.unique = false});
}

final List<_Regle> _regles = [
  _Regle('POST', RegExp(r'^/vente/add/(vno|assurance|depot)$'), TypeJournal.vente, 'Création de vente + 1ʳᵉ ligne'),
  _Regle('POST', RegExp(r'^/vente/add/item$'), TypeJournal.vente, 'Ajout de ligne'),
  _Regle('POST', RegExp(r'^/vente/update/item/vno$'), TypeJournal.vente, 'Modification de ligne'),
  _Regle('POST', RegExp(r'^/vente/remove/vno/item/([^/]+)$'), TypeJournal.vente, 'Suppression de ligne'),
  _Regle('POST', RegExp(r'^/vente/cloturer/vno$'), TypeJournal.encaissement, 'Clôture / encaissement comptant', unique: true),
  _Regle('POST', RegExp(r'^/vente/cloturer/assurance$'), TypeJournal.encaissement, 'Clôture / encaissement assurance', unique: true),
  _Regle('POST', RegExp(r'^/vente/clotureVenteDepot$'), TypeJournal.encaissement, 'Clôture vente dépôt', unique: true),
  _Regle('PUT', RegExp(r'^/vente/terminerprevente/([^/]+)$'), TypeJournal.prevente, 'Prévente enregistrée', unique: true),
  _Regle('POST', RegExp(r'^/ventestats/remove/([^/]+)$'), TypeJournal.vente, 'Annulation de vente', unique: true),
  _Regle('POST', RegExp(r'^/caisse/ouvrir-caisse$'), TypeJournal.caisse, 'Ouverture de caisse', unique: true),
  _Regle('POST', RegExp(r'^/billetage/cloture$'), TypeJournal.caisse, 'Clôture de caisse (billetage)', unique: true),
  _Regle('POST', RegExp(r'^/commande/creerbl$'), TypeJournal.stock, 'Réception : création du BL', unique: true),
  _Regle('POST', RegExp(r'^/commande/add-lot$'), TypeJournal.stock, 'Réception : lot ajouté'),
  _Regle('PUT', RegExp(r'^/commande/remove-lots$'), TypeJournal.stock, 'Réception : lots retirés'),
  _Regle('PUT', RegExp(r'^/commande/validerbl/([^/]+)$'), TypeJournal.stock, 'Réception : entrée en stock du BL', unique: true),
  _Regle('POST', RegExp(r'^/commande/bon/items/checked-quantities$'), TypeJournal.stock, 'Pointage BL'),
  _Regle('POST', RegExp(r'^/commande/item/checked-quantities$'), TypeJournal.stock, 'Contrôle commande'),
  _Regle('POST', RegExp(r'^/fichearticle/add-lot$'), TypeJournal.stock, 'Péremption : lot ajouté'),
  _Regle('POST', RegExp(r'^/fichearticle/produit/update-lite-info$'), TypeJournal.stock, 'Fiche article / emplacement'),
  _Regle('POST', RegExp(r'^/gestionperime/add$'), TypeJournal.stock, 'Périmés : saisie'),
  _Regle('PUT', RegExp(r'^/gestionperime/close/([^/]+)$'), TypeJournal.stock, 'Périmés : clôture', unique: true),
  _Regle('DELETE', RegExp(r'^/gestionperime/([^/]+)$'), TypeJournal.stock, 'Périmés : ligne supprimée'),
  _Regle('POST', RegExp(r'^/retourfournisseur/new$'), TypeJournal.stock, 'Retour fournisseur : création', unique: true),
  _Regle('POST', RegExp(r'^/retourfournisseur/add-item$'), TypeJournal.stock, 'Retour fournisseur : produit ajouté'),
  _Regle('POST', RegExp(r'^/retourfournisseur/update-item$'), TypeJournal.stock, 'Retour fournisseur : quantité modifiée'),
  _Regle('DELETE', RegExp(r'^/retourfournisseur/remove-item/([^/]+)$'), TypeJournal.stock, 'Retour fournisseur : produit retiré'),
  _Regle('POST', RegExp(r'^/ajustement/creeation$'), TypeJournal.stock, 'Ajustement : création + ligne'),
  _Regle('POST', RegExp(r'^/ajustement/add/item$'), TypeJournal.stock, 'Ajustement : ligne ajoutée'),
  _Regle('PUT', RegExp(r'^/ajustement/([^/]+)$'), TypeJournal.stock, 'Ajustement : clôture', unique: true),
  _Regle('POST', RegExp(r'^/user/auth$'), TypeJournal.connexion, 'Connexion'),
  _Regle('POST', RegExp(r'^/user/logout$'), TypeJournal.connexion, 'Déconnexion'),
];

class JournalInterceptor extends Interceptor {
  final JournalTerminal Function() journal;

  /// La file des ventes hors ligne est-elle en train d'envoyer ? (requêtes marquées « envoi file HL »).
  final bool Function() fileEnCours;

  JournalInterceptor({JournalTerminal Function()? journal, bool Function()? fileEnCours})
      : journal = journal ?? (() => JournalTerminal.instance),
        fileEnCours = fileEnCours ?? (() => false);

  static const _cle = 'journal_regle';
  static const _cleVol = 'journal_vol';
  static const _cleDoublon = 'journal_doublon';

  /// Requêtes « uniques » en cours (clé : méthode + chemin + corps).
  static final Set<String> _enVol = {};

  /// Noms des produits vus dans les recherches (le corps des requêtes ne porte que l'identifiant).
  static final Map<String, String> nomsProduits = {};

  static String? _venteCourante;

  static const messageDoublon = 'Opération déjà en cours : double envoi bloqué.';

  static String _path(RequestOptions o) {
    var p = o.path;
    if (p.startsWith('http')) p = Uri.tryParse(p)?.path ?? p;
    final base = Uri.tryParse(o.baseUrl)?.path ?? '';
    if (base.isNotEmpty && base != '/' && p.startsWith(base)) p = p.substring(base.length);
    return p.startsWith('/') ? p : '/$p';
  }

  static (_Regle, RegExpMatch)? _regle(RequestOptions o) {
    final m = o.method.toUpperCase();
    final p = _path(o);
    for (final r in _regles) {
      if (r.methode != m) continue;
      final match = r.chemin.firstMatch(p);
      if (match != null) return (r, match);
    }
    return null;
  }

  static Map<String, dynamic> _corps(RequestOptions o) => o.data is Map ? Map<String, dynamic>.from(o.data as Map) : const {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final found = _regle(options);
    if (found == null) return handler.next(options);
    final (regle, _) = found;
    // Sondage de l'adresse (POST /user/auth sans identifiant) : pas une connexion.
    if (regle.type == TypeJournal.connexion && regle.action == 'Connexion' && _corps(options)['login'] == null) return handler.next(options);
    options.extra[_cle] = true;
    if (regle.unique) {
      String corps;
      try {
        corps = jsonEncode(options.data);
      } catch (_) {
        corps = '${options.data}';
      }
      final cle = '${options.method.toUpperCase()} ${_path(options)} $corps';
      if (_enVol.contains(cle)) {
        options.extra[_cleDoublon] = true;
        _noter(options, ResultatJournal.doublonBloque, motif: messageDoublon);
        return handler.reject(
          DioException(requestOptions: options, type: DioExceptionType.cancel, error: messageDoublon, message: messageDoublon),
          true,
        );
      }
      _enVol.add(cle);
      options.extra[_cleVol] = cle;
    }
    handler.next(options);
  }

  void _fin(RequestOptions o) {
    if (o.extra[_cleDoublon] == true) return;
    final cle = o.extra.remove(_cleVol);
    if (cle is String) _enVol.remove(cle);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final o = response.requestOptions;
    try {
      if (o.method.toUpperCase() == 'GET' && _path(o) == '/vente/search') _memoriserNoms(response.data);
      if (o.extra[_cle] == true) {
        _fin(o);
        final body = response.data;
        final code = response.statusCode ?? 200;
        if (code >= 400) {
          _noter(o, ResultatJournal.refus, motif: 'Erreur du serveur (code $code). ${_msg(body)}', reponse: body);
        } else if (body is Map && body['success'] == false) {
          final m = _msg(body);
          _noter(o, _dejaApplique(m) ? ResultatJournal.dejaApplique : ResultatJournal.refus, motif: m, reponse: body);
        } else {
          _noter(o, ResultatJournal.ok, reponse: body);
        }
      }
    } catch (_) {}
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final o = err.requestOptions;
    try {
      if (o.extra[_cle] == true && o.extra[_cleDoublon] != true) {
        _fin(o);
        final code = err.response?.statusCode ?? 0;
        switch (err.type) {
          case DioExceptionType.badResponse:
            final m = _msg(err.response?.data);
            _noter(o, _dejaApplique(m) ? ResultatJournal.dejaApplique : ResultatJournal.refus,
                motif: 'Refus du serveur${code > 0 ? ' (code $code)' : ''}${m.isEmpty ? '' : ' : $m'}');
          case DioExceptionType.receiveTimeout:
            _noter(o, ResultatJournal.echecReseau, motif: 'Réponse non reçue (délai dépassé) : la requête a pu être appliquée, à vérifier.');
          case DioExceptionType.cancel:
            _noter(o, ResultatJournal.echecReseau, motif: 'Requête annulée.');
          default:
            _noter(o, ResultatJournal.echecReseau, motif: 'Serveur injoignable (${err.type.name}).');
        }
      }
    } catch (_) {}
    handler.next(err);
  }

  static bool _dejaApplique(String m) {
    final t = m.toLowerCase();
    return (t.contains('déjà') || t.contains('deja')) && (t.contains('clôtur') || t.contains('clotur') || t.contains('appliqu') || t.contains('enregistr'));
  }

  static String _msg(Object? body) {
    if (body is Map) return '${body['msg'] ?? body['message'] ?? ''}'.trim();
    return '';
  }

  static void _memoriserNoms(Object? body) {
    if (body is! Map || body['data'] is! List) return;
    if (nomsProduits.length > 5000) nomsProduits.clear();
    for (final p in body['data'] as List) {
      if (p is Map && p['lgFAMILLEID'] != null) nomsProduits['${p['lgFAMILLEID']}'] = '${p['strNAME'] ?? ''}';
    }
  }

  static int? _num(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

  void _noter(RequestOptions o, ResultatJournal resultat, {String motif = '', Object? reponse}) {
    final found = _regle(o);
    if (found == null) return;
    final (regle, match) = found;
    final d = _corps(o);
    final rep = reponse is Map ? reponse : const {};
    final data = rep['data'] is Map ? rep['data'] as Map : const {};
    final groupe = match.groupCount >= 1 ? (match.group(1) ?? '') : '';

    // Référence serveur : vente / BL / retour / objet visé.
    var refServeur = '${d['venteId'] ?? data['lgPREENREGISTREMENTID'] ?? data['strREF'] ?? data['strREFRETOURFRS'] ?? ''}';
    if (refServeur.isEmpty || refServeur == 'null') {
      refServeur = '${d['idBonDetail'] ?? d['id'] ?? d['lgRETOURFRSID'] ?? d['refParent'] ?? d['resumeCaisseId'] ?? ''}';
    }
    if ((refServeur.isEmpty || refServeur == 'null') && regle.type != TypeJournal.vente) refServeur = groupe;
    if (regle.action == 'Suppression de ligne' || regle.action == 'Annulation de vente' || regle.action == 'Prévente enregistrée') refServeur = groupe;
    if (refServeur == 'null') refServeur = '';
    // Vente en cours sur ce terminal : une modification de ligne (sans n° de vente) s'y rattache.
    if (regle.type == TypeJournal.vente && regle.action != 'Annulation de vente') {
      if (regle.action == 'Modification de ligne') {
        refServeur = _venteCourante ?? '';
      } else if (refServeur.isNotEmpty && regle.action != 'Suppression de ligne') {
        _venteCourante = refServeur;
      }
    }

    // Quantités par produit.
    final qte = _num(d['qte'] ?? d['qty'] ?? d['quantity'] ?? d['checkedQuantity'] ?? d['intNUMBERRETURN'] ?? d['value']);
    var produitId = '${d['produitId'] ?? d['refTwo'] ?? d['idProduit'] ?? ''}';
    if (regle.action == 'Périmés : saisie') produitId = '${d['ref'] ?? ''}';
    if (produitId.isEmpty && regle.type == TypeJournal.stock) produitId = '${d['idBonDetail'] ?? d['id'] ?? d['lgRETOURFRSDETAIL'] ?? ''}';
    final avecQte = qte != null && regle.type != TypeJournal.caisse && regle.type != TypeJournal.encaissement && produitId.isNotEmpty;
    final remplace = regle.action == 'Modification de ligne' || regle.action.startsWith('Pointage') || regle.action.startsWith('Contrôle');
    final produits = <JournalProduit>[
      if (avecQte) JournalProduit(id: produitId, nom: nomsProduits[produitId] ?? '', qte: qte, remplace: remplace),
      if (regle.action == 'Retour fournisseur : création' && d['items'] is List)
        for (final i in d['items'] as List)
          if (i is Map) JournalProduit(id: '${i['produitId'] ?? ''}', nom: nomsProduits['${i['produitId']}'] ?? '', qte: _num(i['intNUMBERRETURN']) ?? 0),
    ];

    // Encaissement : montant et règlements par mode.
    int? montant;
    final modes = <String, int>{};
    if (regle.type == TypeJournal.encaissement) {
      montant = _num(d['montantPaye'] ?? d['totalRecap']);
      if (d['reglements'] is List) {
        for (final r in d['reglements'] as List) {
          if (r is! Map) continue;
          final m = '${r['typeReglement'] ?? ''}';
          modes[m] = (modes[m] ?? 0) + (_num(r['montant']) ?? 0);
        }
      } else if (d['typeRegleId'] != null && montant != null) {
        modes['${d['typeRegleId']}'] = montant;
      }
    } else if (regle.type == TypeJournal.vente && qte != null) {
      final pu = _num(d['itemPu']);
      if (pu != null) montant = pu * qte;
    }

    final file = _safe(fileEnCours);
    final j = journal();
    j.noter(
      type: regle.type,
      action: regle.action,
      refLocale: '${o.headers['X-Client-Ref'] ?? o.headers['x-client-ref'] ?? ''}',
      refServeur: refServeur,
      montant: montant,
      // Espèces de la file hors ligne : déjà comptées à la saisie (pas de double comptage).
      modes: resultat == ResultatJournal.ok ? modes : const {},
      produits: produits,
      resultat: resultat,
      motif: motif,
      source: file ? SourceJournal.fileHL : SourceJournal.enLigne,
      // Connexion : identifiant saisi (jamais le mot de passe).
      utilisateur: regle.action == 'Connexion' ? '${d['login'] ?? ''}' : null,
    );
  }

  static bool _safe(bool Function() f) {
    try {
      return f();
    } catch (_) {
      return false;
    }
  }

  /// Remise à zéro (tests).
  static void reset() {
    _enVol.clear();
    nomsProduits.clear();
    _venteCourante = null;
  }
}
