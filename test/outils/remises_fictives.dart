// 4.14.0 — Remise des ventes et ticket dessiné par le serveur, côté FAUX serveur Prestige (données FICTIVES), avec les
// règles du serveur réel (integration/recette-2026-10-29 f0282bf0, lues dans le code) :
//  - GET v1/common/remises-client : remises + {lgREMISEID:null, « SANS REMISE »} (CommonRessource.remisesclient) ;
//  - POST v1/vente/remise {venteId, remiseId} : pose la remise (null = retire), {success, msg} (RemiseServiceImpl) ;
//  - POST v1/vente/net/vno {venteId, remiseId} : remise calculée par ligne remisable (taux de la grille), net arrondi
//    à 5 F ; SANS remiseId, la remise de la vente est remise à 0 (audit VC-06, shownetpayVno) ;
//  - GET v1/ventestats/{id} : lgREMISEID de la vente ;
//  - GET v1/vente/ticket/{type}/{id}/image (demande du 19/11, PAS encore sur le serveur) : absente par défaut (404),
//    ou présente : PNG 1 bit de 384 / 576 points.
import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'faux_serveur_prestige.dart';

class RemisesFictives {
  final FauxServeurPrestige s;

  /// Remises du serveur : id → (nom, taux %).
  final Map<String, ({String nom, int taux})> remises = {
    'REM-FICT-10': (nom: 'REMISE FICTIVE 10 %', taux: 10),
    'REM-FICT-5': (nom: 'REMISE FICTIVE 5 %', taux: 5),
  };

  /// Remise posée sur chaque vente.
  final Map<String, String> remiseDeVente = {};

  /// Produits non remisables (lgFAMILLEID).
  final Set<String> nonRemisables = {};

  final List<({String venteId, String? remiseId})> poses = [];
  final List<Map<String, dynamic>> netsVno = [];
  final List<String> images = [];

  ReponseLocale? Function(RequeteRecue r)? forcerPose;
  ReponseLocale? Function(RequeteRecue r)? forcerListe;
  ReponseLocale? Function(RequeteRecue r)? forcerImage;
  Duration delaiPose = Duration.zero;

  /// Route image présente sur ce faux serveur (false : 404, comme le serveur d'aujourd'hui).
  bool routeImage = false;

  /// Nombre de tickets rendus par la route image (exemplaires décidés par le serveur).
  int ticketsParImage = 1;

  RemisesFictives(this.s, {int nombreVentes = 40, bool ventestats = true}) {
    s.routes['GET /common/remises-client'] = (r) {
      final f = forcerListe?.call(r);
      if (f != null) return f;
      final l = [
        for (final e in remises.entries) {'lgREMISEID': e.key, 'strNAME': e.value.nom, 'strCODE': e.key},
        {'lgREMISEID': null, 'strNAME': 'SANS REMISE'},
      ];
      return FauxServeurPrestige.ok({'success': true, 'data': l, 'total': l.length});
    };
    s.routes['POST /vente/remise'] = (r) {
      final j = r.json;
      final venteId = '${j['venteId'] ?? ''}';
      final remiseId = j['remiseId'] == null || '${j['remiseId']}'.isEmpty ? null : '${j['remiseId']}';
      poses.add((venteId: venteId, remiseId: remiseId));
      final f = forcerPose?.call(r);
      if (f != null) return f;
      if (!s.ventes.containsKey(venteId)) return FauxServeurPrestige.ok({'success': false, 'msg': 'Erreur::: L\'Opération n\'a pas aboutie'});
      if (remiseId == null) {
        remiseDeVente.remove(venteId);
      } else {
        remiseDeVente[venteId] = remiseId;
      }
      return FauxServeurPrestige.ok({'success': true, 'msg': 'Opération effectuée avec success'}, delai: delaiPose);
    };
    s.routes['POST /vente/net/vno'] = (r) {
      final j = r.json;
      netsVno.add(Map<String, dynamic>.from(j));
      final id = '${j['venteId']}';
      final lignes = s.ventes[id] ?? const [];
      final total = lignes.fold<int>(0, (a, l) => a + (l['intPRICE'] as int));
      final demande = j['remiseId'] == null || '${j['remiseId']}'.isEmpty ? null : '${j['remiseId']}';
      var remise = 0;
      final posee = remiseDeVente[id];
      if (demande != null && posee != null) {
        final taux = remises[posee]?.taux ?? 0;
        for (final l in lignes) {
          if (!nonRemisables.contains(l['lgFAMILLEID'])) remise += (l['intPRICE'] as int) * taux ~/ 100;
        }
      }
      var net = total - remise;
      if (remise > 0) {
        net = (net / 5).round() * 5;
        remise = total - net;
      }
      return FauxServeurPrestige.ok({
        'success': true,
        'data': {'montant': total, 'montantNet': net, 'remise': remise, 'marge': 0, 'montantTva': 0},
        'lgPREENREGISTREMENTID': id,
        'strREF': 'REF-$id',
      });
    };
    if (ventestats) {
      for (var i = 1; i <= nombreVentes; i++) {
        final id = 'V-$i';
        final avant = s.routes['GET /ventestats/$id'];
        s.routes['GET /ventestats/$id'] = (r) async {
          final st = s.statutVentes[id];
          if (st == null) return FauxServeurPrestige.refus('Vente introuvable');
          Map<String, dynamic> data = {'strSTATUT': st, 'lgTYPEVENTEID': '1'};
          if (avant != null) {
            final b = (await avant(r)).corps;
            if (b is Map && b['data'] is Map) data = Map<String, dynamic>.from(b['data'] as Map);
          }
          data['lgREMISEID'] = remiseDeVente[id];
          return FauxServeurPrestige.ok({'success': true, 'data': data});
        };
      }
    }
    s.routes['GET /image'] = (r) {
      final m = RegExp(r'/vente/ticket/([a-z\-]+)/([^/]+)/image$').firstMatch(r.chemin);
      if (m == null || !routeImage) return s.reponseInconnue;
      images.add('${m.group(1)} ${m.group(2)} ${r.query['largeur']}');
      final f = forcerImage?.call(r);
      if (f != null) return f;
      final largeur = int.tryParse(r.query['largeur'] ?? '') ?? 80;
      final mm = largeur <= 58 ? 58 : 80;
      final points = mm == 58 ? 384 : 576;
      return FauxServeurPrestige.ok({
        'success': true,
        'largeur': mm,
        'tickets': [
          for (var k = 0; k < ticketsParImage; k++)
            {'modele': m.group(1) == 'vno' ? 'VENTE' : 'VENTE_ASSURANCE', 'png': base64Encode(pngFictif(points, 120)), 'largeurPoints': points, 'hauteurPoints': 120},
        ],
      });
    };
  }

  /// PNG noir et blanc de [largeur] × [hauteur] points (bandes, sans texte).
  static Uint8List pngFictif(int largeur, int hauteur) {
    final i = img.Image(width: largeur, height: hauteur, numChannels: 1);
    img.fill(i, color: img.ColorUint8.rgb(255, 255, 255));
    for (var y = 0; y < hauteur; y += 8) {
      img.drawLine(i, x1: 0, y1: y, x2: largeur - 1, y2: y, color: img.ColorUint8.rgb(0, 0, 0));
    }
    return Uint8List.fromList(img.encodePng(i));
  }
}
