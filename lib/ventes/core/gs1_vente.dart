// lib/ventes/core/gs1_vente.dart
// 4.9.0 — lecture des étiquettes GS1 (DataMatrix, QR) à la vente, alignée sur l'écran de vente du web (décision du
// pharmacien du 25/10/2026). Vérifié dans le code du serveur (lecture seule, branche claude/new-session-xm8ptu) :
//  - réglage : GET v1/app-params/value/KEY_VENTE_LECTURE_GS1 → {success:true, data:"1"|"0"|"", total:1} ; le web le
//    relit à chaque ouverture de la vente (VenteCtr.checkParamLectureGs1) ; « 1 » = lecture active, sinon inactive ;
//  - lecture : GET v1/vente/gs1?code=<brut> (SalesRessource.lireGs1, session) → success, actif, gs1, msg, lot,
//    peremption (jj/mm/aaaa), perime, cip, gtin, lotPrevu, peremptionPrevue, controle (CONFORME|DIFFERENT|INCONNU),
//    modeControle (A|B|C, KEY_VENTE_CONTROLE_LOT_GS1 lu par le serveur), lotEnStock, data (produit), etendu,
//    sansProduit ;
//  - web (VenteCtr.lireGs1) : !success → message ; perime → « Ce lot est périmé (…) : il n'est pas ajouté » ;
//    DIFFERENT + mode C → refus, « prenez la boîte du lot … » ; sinon produit ajouté, avertissement si DIFFERENT ;
//    mode B + lotEnStock + lot → `lotScanne` envoyé dans le corps de l'ajout de la ligne (vente/add/vno,
//    vente/add/assurance, vente/add/item ; SalesServiceImpl.noterLotScanne, mode B seulement), pris une seule fois
//    (VenteCtr.prendreLotScanne : vidé à la lecture, seulement pour ce produit).
//
// Ici, AUCUNE RÉGRESSION : lecture inactive (0, vide, absente), serveur ancien (404/405), panne, délai dépassé ou
// réponse illisible → exactement le comportement d'avant (décodage sur l'appareil : GTIN → EAN-13 / CIP7 / UPC). Le
// produit reste trouvé par le chemin d'avant (même recherche, même modèle de produit) : le serveur ne donne que le
// verdict (périmé, lot, mode) et le CIP. Les codes-barres classiques, le CIP tapé et la recherche par nom n'appellent
// jamais vente/gs1. Le contenu scanné (il peut porter un numéro de série) n'est jamais journalisé.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/api/dio_client.dart';
import 'package:prestige_vente_app/services/datamatrix_parser.dart';

/// Lot de la boîte scannée à sortir (mode B), en attente de l'ajout de la ligne de ce produit (comme le web).
class LotScanneEnAttente {
  LotScanneEnAttente._();
  static String? _produitId;
  static String? _lot;

  static void poser(String produitId, String lot) {
    _produitId = produitId;
    _lot = lot;
  }

  static void vider() => _produitId = _lot = null;

  /// Lot à envoyer pour [produitId] ; l'attente est vidée dans tous les cas (comme VenteCtr.prendreLotScanne).
  static String? prendre(String produitId) {
    final l = _produitId == produitId ? _lot : null;
    vider();
    return l;
  }

  /// Champ du corps de l'ajout (vide si aucun lot : corps inchangé pour un serveur ancien).
  static Map<String, dynamic> champ(String produitId) {
    final l = prendre(produitId);
    return l == null || l.isEmpty ? const {} : {'lotScanne': l};
  }
}

/// Verdict d'une lecture GS1 à la vente.
sealed class VerdictGs1 {
  const VerdictGs1();
}

/// Lecture GS1 inactive ou impossible : comportement d'avant (décodage sur l'appareil).
class Gs1CommeAvant extends VerdictGs1 {
  const Gs1CommeAvant();
}

/// Boîte refusée : rien n'est ajouté. [pourClient] : message de la borne (aucun détail de lot).
class Gs1Refus extends VerdictGs1 {
  final String message;
  final String raison;
  const Gs1Refus(this.message, {required this.raison});
  static const pourClient = 'Ce produit ne peut pas être ajouté ici : présentez-le au comptoir';
}

/// Boîte acceptée : produit à chercher par [code] (CIP de l'étiquette, sinon le contenu scanné) ; [avertissement]
/// (lot différent) à montrer au vendeur, jamais au client ; [lotScanne] (mode B) à envoyer à l'ajout.
class Gs1Accepte extends VerdictGs1 {
  final String code;
  final String? avertissement;
  final String? lotScanne;
  final String? info;
  const Gs1Accepte(this.code, {this.avertissement, this.lotScanne, this.info});
}

/// Réglage de l'officine et lecture des étiquettes GS1.
class Gs1Vente {
  Gs1Vente._();
  static Gs1Vente instance = Gs1Vente._();

  @visibleForTesting
  static void reinitialiser() => instance = Gs1Vente._();

  static const cleLecture = 'KEY_VENTE_LECTURE_GS1';

  /// Délai de GET v1/vente/gs1 (au-delà : comportement d'avant, le scan n'attend pas).
  static Duration delai = const Duration(milliseconds: 2500);

  /// Client de la session ; remplaçable pour les tests.
  Dio Function() dio = () => DioClient.session;

  /// L'application est hors ligne (décision 1 : contrôle local de la date seulement).
  bool Function() horsLigne = () => HorsLigne.instance.offline;

  /// Date du jour (tests).
  DateTime Function() maintenant = DateTime.now;

  bool _actif = false;

  /// Lecture GS1 active pour cette officine (dernier réglage lu ; false tant qu'il ne l'a pas été).
  bool get actif => _actif;

  @visibleForTesting
  set actifPourTests(bool v) => _actif = v;

  /// Relit KEY_VENTE_LECTURE_GS1 (connexion, retour au premier plan), avec [client] (session) ou [dio]. Jamais
  /// d'exception ; échec (serveur ancien, panne) → inactive.
  Future<void> relireReglage([Dio? client]) async {
    try {
      final r = await (client ?? dio()).get<dynamic>('/app-params/value/$cleLecture',
          options: Options(validateStatus: (_) => true, receiveTimeout: const Duration(seconds: 8)));
      final j = r.data is String ? jsonDecode(r.data as String) : r.data;
      _actif = r.statusCode == 200 && j is Map && j['success'] == true && '${j['data'] ?? ''}'.trim() == '1';
    } catch (_) {
      _actif = false;
    }
  }

  void oublier() => _actif = false;

  // -------------------------------------------------------------------------------------------------------------
  // Reconnaissance (sans réseau)
  // -------------------------------------------------------------------------------------------------------------

  static final RegExp _lienNumerique = RegExp(r'^https?://[^\s/]+(/[^\s?#]*)?/01/(\d{14})(/[^\s?#]*)?(\?[^\s#]*)?$', caseSensitive: false);

  /// Lien GS1 Digital Link (https://…/01/<GTIN>[/10/<lot>][/21/…][?17=…]) → forme lisible « (01)…(17)…(10)… » ;
  /// null si ce n'en est pas un ou si sa lecture n'est pas univoque.
  static String? depuisLienNumerique(String brut) {
    final v = brut.trim();
    final m = _lienNumerique.firstMatch(v);
    if (m == null) return null;
    final gtin = m.group(2)!;
    if (!DataMatrixParser.isValidGs1CheckDigit(gtin)) return null;
    final apres = (m.group(3) ?? '').split('/').where((s) => s.isNotEmpty).toList();
    if (apres.length.isOdd) return null;
    final champs = <String, String>{};
    for (var i = 0; i < apres.length; i += 2) {
      champs[apres[i]] = Uri.decodeComponent(apres[i + 1]);
    }
    final q = m.group(4);
    if (q != null && q.length > 1) {
      for (final e in Uri.splitQueryString(q.substring(1)).entries) {
        champs[e.key] = e.value;
      }
    }
    final date = champs['17'];
    if (date != null && !RegExp(r'^\d{6}$').hasMatch(date)) return null;
    final lot = champs['10'];
    if (lot != null && (lot.isEmpty || lot.contains('(') || lot.contains(')'))) return null;
    return ['(01)$gtin', if (date != null) '(17)$date', if (lot != null) '(10)$lot'].join();
  }

  /// La saisie est une étiquette GS1 (comme VenteCtr.ressembleGs1 du web, plus le lien GS1 Digital Link) : préfixe de
  /// lecteur 2D, forme entre parenthèses, ou (01) + (17/10/240). Un code-barres, un CIP ou un nom : jamais.
  static bool ressembleGs1(String brut) {
    final v = brut.trim();
    if (depuisLienNumerique(v) != null) return true;
    if (RegExp(r'^\](d2|Q3|C1)').hasMatch(v) ||
        RegExp(r'^\((01|17|10|240)\)').hasMatch(v) ||
        RegExp(r'^01\d{14}(17|10|240)').hasMatch(v) ||
        RegExp(r'^17\d{6}(10|240)').hasMatch(v) ||
        RegExp(r'^10[^\u001d|<]+(\u001d|<GS>|\|)240').hasMatch(v)) {
      return true;
    }
    // Séparateur GS après le GTIN (certains lecteurs) : GTIN valide et lot ou péremption décodés sur l'appareil.
    if (!v.startsWith('01') || !v.contains('\u001d')) return false;
    final dm = DataMatrixParser.parse(v);
    return dm != null && dm.gtin != null && (dm.lotCandidates.isNotEmpty || dm.expiryCandidates.isNotEmpty);
  }

  /// Contenu à envoyer au serveur et à décoder sur l'appareil (lien numérique traduit).
  static String contenu(String brut) => depuisLienNumerique(brut) ?? brut;

  static final _jj = DateFormat('dd/MM/yyyy');

  /// Hors ligne, lecture active (décision 1) : boîte refusée si la date de péremption (AI 17, certaine) est passée ;
  /// le lot n'est pas contrôlé (vente/gs1 injoignable) ; null sinon.
  Gs1Refus? controleHorsLigne(String brut) {
    final dm = DataMatrixParser.parse(contenu(brut), now: maintenant());
    final d = dm?.expiry;
    if (d == null) return null;
    final jour = DateTime(maintenant().year, maintenant().month, maintenant().day);
    if (!d.isBefore(jour)) return null;
    return Gs1Refus('Boîte périmée (${_jj.format(d)}) : non ajoutée', raison: 'perime');
  }

  // -------------------------------------------------------------------------------------------------------------
  // Lecture
  // -------------------------------------------------------------------------------------------------------------

  /// Verdict d'un scan. [brut] : contenu tel que reçu. Jamais d'exception.
  /// [lotEnvoye] (4.9.1) : false pour les ventes dont la route d'ajout n'utilise pas `lotScanne` (dépôt, proforma) :
  /// aucun lot mis en attente, avertissement « lot différent » sans annoncer quel lot sortira.
  Future<VerdictGs1> verdict(String brut, {bool lotEnvoye = true}) async {
    if (!ressembleGs1(brut)) return const Gs1CommeAvant();
    // Lecture inactive (dernier réglage lu : 0, vide, absent, ou jamais lu) : rien ne change, même hors ligne.
    if (!_actif) return const Gs1CommeAvant();
    if (horsLigne()) return controleHorsLigne(brut) ?? const Gs1CommeAvant();
    try {
      return await _lire(contenu(brut), lotEnvoye: lotEnvoye).timeout(delai, onTimeout: () => const Gs1CommeAvant());
    } catch (_) {
      return const Gs1CommeAvant();
    }
  }

  Future<VerdictGs1> _lire(String code, {required bool lotEnvoye}) async {
    final r = await dio().get<dynamic>('/vente/gs1',
        queryParameters: {'code': code},
        options: Options(validateStatus: (_) => true, receiveTimeout: delai, sendTimeout: delai));
    if (r.statusCode != 200) return const Gs1CommeAvant(); // 404/405 : serveur ancien ; autre : comme avant
    final j = r.data is String ? jsonDecode(r.data as String) : r.data;
    if (j is! Map) return const Gs1CommeAvant();
    if (j['etendu'] == true) {
      return Gs1Refus('${j['msg'] ?? 'Étiquette étendue : elle ne passe pas à la vente.'}', raison: 'etendu');
    }
    if (j['actif'] != true) return const Gs1CommeAvant(); // désactivée entre-temps : comme avant
    if (j['sansProduit'] == true) return Gs1Refus('${j['msg'] ?? 'Étiquette sans produit.'}', raison: 'sansProduit');
    // Aucun produit, ou « pas une étiquette GS1 » : le décodage d'avant est essayé (il peut trouver une variante).
    if (j['success'] != true) return const Gs1CommeAvant();
    final lot = '${j['lot'] ?? ''}'.trim();
    final per = '${j['peremption'] ?? ''}'.trim();
    final info = [if (lot.isNotEmpty) 'lot $lot', if (per.isNotEmpty) 'pér. $per'].join(' - ');
    if (j['perime'] == true) return Gs1Refus('Boîte périmée ($per) : non ajoutée', raison: 'perime');
    final mode = '${j['modeControle'] ?? 'A'}' == 'B' ? 'B' : ('${j['modeControle'] ?? 'A'}' == 'C' ? 'C' : 'A');
    final lotPrevu = '${j['lotPrevu'] ?? ''}'.trim();
    final perPrevue = '${j['peremptionPrevue'] ?? ''}'.trim();
    final prevu = [if (lotPrevu.isNotEmpty) 'lot $lotPrevu', if (perPrevue.isNotEmpty) 'péremption $perPrevue'].join(', ');
    final different = j['controle'] == 'DIFFERENT';
    if (different && mode == 'C') {
      return Gs1Refus('Prenez une boîte du ${prevu.isEmpty ? 'lot prévu' : prevu} : la boîte scannée ($info) n\'est pas ajoutée.',
          raison: 'controle');
    }
    final lotEnStock = j['lotEnStock'] == true;
    final cip = '${j['cip'] ?? ''}'.trim();
    String? avert;
    if (different && !lotEnvoye) {
      avert = 'Lot différent : boîte scannée $info (prévu : ${prevu.isEmpty ? 'lot prévu' : prevu}).';
    } else if (different) {
      avert = mode == 'B' && lotEnStock
          ? 'Lot différent : boîte scannée $info ; la vente sortira ce lot (au lieu du ${prevu.isEmpty ? 'lot prévu' : prevu}).'
          : 'Lot différent : boîte scannée $info ; Prestige sort le ${prevu.isEmpty ? 'lot prévu' : prevu}.';
    }
    final data = j['data'];
    final produitId = data is Map ? '${data['lgFAMILLEID'] ?? ''}' : '';
    final sortir = lotEnvoye && mode == 'B' && lotEnStock && lot.isNotEmpty ? lot : null;
    if (sortir != null && produitId.isNotEmpty) {
      LotScanneEnAttente.poser(produitId, sortir);
    } else {
      LotScanneEnAttente.vider();
    }
    return Gs1Accepte(cip.isNotEmpty ? cip : code, avertissement: avert, lotScanne: sortir, info: info.isEmpty ? null : info);
  }
}
