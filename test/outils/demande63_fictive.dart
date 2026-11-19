// 4.15.1 — Demande 63, côté FAUX serveur Prestige (données FICTIVES uniquement), avec les règles du code de la branche
// serveur correctif/demande63-1911 (bb6b4604), lues dans le code :
//  - GET v1/vente/ticket/{type}/{id}/image?largeur&dpi (SalesRessource.imageTicket) : 401 sans session ; type autre que
//    vno / vo / prevente → 400 {success:false, msg} ; vente inconnue ou non terminée (vno / vo) → 200
//    {success:false, msg} ; sinon {success:true, largeur, dpi, tickets:[{modele, png, largeurPoints, hauteurPoints}]},
//    PNG en NIVEAUX DE GRIS (texte lissé, fond blanc), 384 / 576 points ; vo : un ticket par organisme ;
//  - POST v1/vente/remise : 403 {success:false, interdit:true, msg:"Droit manquant : Remise sur une vente"} sans
//    P_REMISE_VENTE (Droits.refus, avant tout) ; vente terminée / inconnue, remise inconnue → {success:false, msg},
//    vente non touchée ; "0" ou vide = sans remise ; comptant : `data` = net recalculé (net/vno) ;
//  - remise appliquée à une vente assurance / carnet (SalesNetComputingServiceImpl.remiseAppliquee) : celle de la
//    vente ; à défaut celle de la fiche du client, SAUF "0" (sans remise pour cette vente).
// [d63] false : intégration d'aujourd'hui f0282bf0 (RemiseServiceImpl.addRemise) : aucun droit, `lg_REMISE_ID` reçu
// écrit tel quel ("0" compris), aucune vérification de la remise, pas de `data`, fiche toujours appliquée sans remise
// choisie ; route image absente (404).
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

import 'faux_serveur_prestige.dart';
import 'remises_fictives.dart';

const droitRemise = 'P_REMISE_VENTE';
const messageDroitRemise = 'Droit manquant : Remise sur une vente';
const messageRemiseInconnue = 'Cette remise n\'existe pas (ou plus) : choisissez une remise de la liste.';
const messageVenteTerminee = 'Cette vente est terminée : elle ne peut plus être modifiée.';
const messageVenteInconnue = 'Cette vente n\'existe plus : actualisez l\'écran de vente.';

class Demande63Fictive {
  final FauxServeurPrestige s;
  final RemisesFictives rf;

  /// Serveur avec la branche de la demande 63 (false : intégration d'aujourd'hui).
  bool d63;

  /// `lg_REMISE_ID` écrit sur chaque vente (tel que reçu, "0" compris).
  final Map<String, String?> lgRemise = {};

  /// Remise de la fiche du client de chaque vente assurance / carnet (id de remise).
  final Map<String, String> remiseFiche = {};

  /// Ventes assurance / carnet (pas de `data` dans la réponse de vente/remise).
  final Set<String> ventesVo = {};

  /// Nombre de tickets par vente vo (un par organisme).
  int ticketsVo = 2;

  final List<String> images = [];
  int refus403 = 0;

  /// Réseau : la réponse de vente/remise est coupée en cours (la remise est pourtant appliquée).
  bool couperReponsePose = false;

  /// Types de ticket connus de la route image (les autres : 400).
  Set<String> typesConnus = {'vno', 'vo', 'prevente'};

  Demande63Fictive(this.s, this.rf, {this.d63 = true}) {
    final poseAvant = s.routes['POST /vente/remise']!;
    s.routes['POST /vente/remise'] = (r) async {
      final j = r.json;
      final venteId = '${j['venteId'] ?? ''}';
      final brut = j['remiseId'] == null ? null : '${j['remiseId']}';
      if (!d63) {
        // intégration f0282bf0 : lg_REMISE_ID = valeur reçue ; remise = find(id) (null pour "0") ; succès
        if (s.ventes.containsKey(venteId)) lgRemise[venteId] = brut;
        return poseAvant(r);
      }
      final login = r.jsessionid == null ? null : s.compteSession[r.jsessionid];
      if (!_droits(login).contains(droitRemise)) {
        refus403++;
        return FauxServeurPrestige.interdit(messageDroitRemise);
      }
      final st = s.statutVentes[venteId];
      if (!s.ventes.containsKey(venteId) || st == null) return FauxServeurPrestige.ok({'success': false, 'msg': messageVenteInconnue});
      if (st == 'is_Closed') return FauxServeurPrestige.ok({'success': false, 'msg': messageVenteTerminee});
      final sans = brut == null || brut.isEmpty || brut == '0';
      if (!sans && !rf.remises.containsKey(brut)) return FauxServeurPrestige.ok({'success': false, 'msg': messageRemiseInconnue});
      rf.poses.add((venteId: venteId, remiseId: sans ? null : brut));
      lgRemise[venteId] = brut;
      if (sans) {
        rf.remiseDeVente.remove(venteId);
      } else {
        rf.remiseDeVente[venteId] = brut;
      }
      final rep = <String, dynamic>{'success': true, 'msg': 'Opération effectuée avec success'};
      if (!ventesVo.contains(venteId)) rep['data'] = netComptant(venteId);
      if (couperReponsePose) return const ReponseLocale('{"success":tr', entetes: {'content-type': 'application/json; charset=utf-8'});
      return FauxServeurPrestige.ok(rep);
    };
    s.routes['GET /image'] = (r) {
      final m = RegExp(r'/vente/ticket/([^/]+)/([^/]+)/image$').firstMatch(r.chemin);
      if (m == null || !d63) return s.reponseInconnue;
      final type = m.group(1)!, id = m.group(2)!;
      images.add('$type $id ${r.query['largeur']} ${r.query['dpi']}');
      if (r.jsessionid == null || !s.compteSession.containsKey(r.jsessionid)) {
        return const ReponseLocale({'success': false, 'msg': 'Veuillez vous connecter'}, statut: 401);
      }
      if (!typesConnus.contains(type)) {
        return const ReponseLocale({'success': false, 'msg': 'Type de ticket inconnu : vno, vo ou prevente.'}, statut: 400);
      }
      final st = s.statutVentes[id];
      if (st == null || (type != 'prevente' && st != 'is_Closed')) {
        return FauxServeurPrestige.ok({'success': false, 'msg': 'Ticket introuvable : vente $id non terminée.'});
      }
      final largeur = int.tryParse(r.query['largeur'] ?? '') ?? 80;
      final mm = largeur <= 58 ? 58 : 80;
      final dpi = int.tryParse(r.query['dpi'] ?? '') ?? 203;
      final points = mm == 58 ? 384 : 576;
      final n = type == 'vo' ? ticketsVo : 1;
      return FauxServeurPrestige.ok({
        'success': true,
        'largeur': mm,
        'dpi': dpi,
        'tickets': [
          for (var k = 0; k < n; k++)
            () {
              final png = ticketGris(points, qr: type == 'prevente' ? 'REF-$id' : null, organisme: type == 'vo' ? k + 1 : null);
              final i = img.decodePng(png)!;
              return {'modele': type == 'prevente' ? 'PREVENTE' : (type == 'vo' ? 'VENTE_ASSURANCE' : 'VENTE'), 'png': base64Encode(png), 'largeurPoints': i.width, 'hauteurPoints': i.height};
            }(),
        ],
      });
    };
  }

  Set<String> _droits(String? login) {
    final d = s.droitsComptes;
    if (d == null) return const {};
    return {...(d[login] ?? FauxServeurPrestige.droitsComplets)};
  }

  /// Net comptant (même calcul que POST v1/vente/net/vno du faux serveur, avec la remise posée).
  Map<String, dynamic> netComptant(String id) {
    final lignes = s.ventes[id] ?? const [];
    final total = lignes.fold<int>(0, (a, l) => a + (l['intPRICE'] as int));
    var remise = 0;
    final posee = rf.remiseDeVente[id];
    if (posee != null) {
      final taux = rf.remises[posee]?.taux ?? 0;
      for (final l in lignes) {
        if (!rf.nonRemisables.contains(l['lgFAMILLEID'])) remise += (l['intPRICE'] as int) * taux ~/ 100;
      }
    }
    var net = total - remise;
    if (remise > 0) {
      net = (net / 5).round() * 5;
      remise = total - net;
    }
    return {'montant': total, 'montantNet': net, 'remise': remise, 'marge': 0, 'montantTva': 0};
  }

  /// Remise appliquée à une vente assurance / carnet au calcul du net et à la clôture (règle du serveur).
  String? remiseAppliquee(String venteId) {
    final choisie = rf.remiseDeVente[venteId];
    if (choisie != null && rf.remises.containsKey(choisie)) return choisie;
    if (d63 && lgRemise[venteId] == '0') return null;
    return remiseFiche[venteId];
  }

  /// Ticket FICTIF dessiné « comme le serveur » : texte lissé en niveaux de gris (dessiné 3 fois plus grand puis
  /// réduit en moyenne), traits, cadre du net, QR (modules de 2,8 points, bords gris) pour une prévente.
  static Uint8List ticketGris(int points, {String? qr, int? organisme}) {
    const k = 3;
    final lignes = <String>[
      'PHARMACIE FICTIVE',
      'TICKET DE TEST - DONNEES FICTIVES',
      if (organisme != null) 'ORGANISME FICTIF $organisme',
      '--------------------------------',
      'PRODUIT FICTIF A',
      '  2 x 1 250                2 500',
      'PRODUIT FICTIF B',
      '  1 x 1 625                1 625',
      'REMISE                     - 410',
      'NET A PAYER                3 715',
    ];
    final hauteurTexte = lignes.length * 26 + 30;
    final module = 2.8;
    final qrImg = qr == null ? null : (QrImage(QrCode.fromData(data: qr, errorCorrectLevel: QrErrorCorrectLevel.M)));
    final tailleQr = qrImg == null ? 0 : (qrImg.moduleCount * module).ceil();
    final h = hauteurTexte + (qrImg == null ? 0 : tailleQr + 20) + 10;
    final grand = img.Image(width: points * k, height: hauteurTexte * k);
    img.fill(grand, color: img.ColorUint8.rgb(255, 255, 255));
    final noir = img.ColorUint8.rgb(0, 0, 0);
    var y = 6 * k;
    for (final l in lignes) {
      if (l.startsWith('---')) {
        img.fillRect(grand, x1: 3 * k, y1: y + 10 * k, x2: points * k - 3 * k, y2: y + 10 * k + 4, color: noir);
      } else {
        img.drawString(grand, l, font: img.arial48, x: 3 * k, y: y, color: noir);
      }
      y += 26 * k;
    }
    // cadre du net (trait fin, 1,6 point du serveur)
    img.drawRect(grand, x1: 2 * k, y1: y - 27 * k, x2: points * k - 2 * k, y2: y - 2 * k, color: noir, thickness: 5);
    final petit = img.copyResize(grand, width: points, height: hauteurTexte, interpolation: img.Interpolation.average);
    final out = img.Image(width: points, height: h, numChannels: 1);
    img.fill(out, color: img.ColorUint8.rgb(255, 255, 255));
    img.compositeImage(out, petit, dstX: 0, dstY: 0);
    if (qrImg != null) {
      final x0 = (points - tailleQr) / 2, y0 = hauteurTexte + 10.0;
      dessinerQr(out, qrImg, x0, y0, module);
    }
    // niveaux de gris (un canal), comme BufferedImage.TYPE_BYTE_GRAY
    return Uint8List.fromList(img.encodePng(out.convert(numChannels: 1)));
  }

  /// QR à [module] points par module (non entier), chaque point gris à la part couverte par les modules noirs.
  static void dessinerQr(img.Image out, QrImage q, double x0, double y0, double module) {
    final n = q.moduleCount;
    final x1 = (x0 + n * module).ceil(), y1 = (y0 + n * module).ceil();
    for (var py = y0.floor(); py < y1; py++) {
      for (var px = x0.floor(); px < x1; px++) {
        var couvert = 0.0;
        for (var sy = 0; sy < 4; sy++) {
          for (var sx = 0; sx < 4; sx++) {
            final mx = ((px + (sx + 0.5) / 4) - x0) / module, my = ((py + (sy + 0.5) / 4) - y0) / module;
            if (mx >= 0 && my >= 0 && mx < n && my < n && q.isDark(my.floor(), mx.floor())) couvert += 1 / 16;
          }
        }
        final v = (255 * (1 - couvert)).round();
        out.setPixelRgb(px, py, v, v, v);
      }
    }
  }

  /// Point de module du QR [q] dessiné à ([x0], [y0]) : centre en points.
  static math.Point<int> centreModule(double x0, double y0, double module, int ligne, int colonne) =>
      math.Point(((colonne + 0.5) * module + x0).floor(), ((ligne + 0.5) * module + y0).floor());
}
