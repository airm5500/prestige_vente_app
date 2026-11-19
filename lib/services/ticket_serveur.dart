// lib/services/ticket_serveur.dart
// 4.14.0 — Ticket DESSINÉ PAR LE SERVEUR (demande de la session principale du 19/11/2026, « ticket 58 mm (terminal) et
// 80 mm (tablette), identique au web »).
//
// 4.15.1 — Contrat VÉRIFIÉ dans le code du serveur (réponse à la demande 63, correctif/demande63-1911, bb6b4604,
// pas encore fusionnée ; le serveur de l'officine n'a pas la route) :
//   GET v1/vente/ticket/{type}/{id}/image?largeur=58|80&dpi=203   type = vno | vo | prevente (PAS de « vo-combine » :
//   la route vo renvoie tous les tickets de la vente dans l'ordre d'impression, deux organismes compris)
//   → {success:true, largeur:58|80, dpi, tickets:[{modele, png (base64), largeurPoints, hauteurPoints}]}
// Chaque PNG est en NIVEAUX DE GRIS (fond blanc, texte lissé), largeur exacte 384 ou 576 points à 203 dpi : il est
// converti en 1 bit par l'application (lib/services/ticket_1bit.dart) puis imprimé dans l'ordre, une coupe entre deux
// tickets ; le serveur décide du nombre d'exemplaires (le mobile n'en ajoute pas). Lecture seule côté serveur.
// Refus du serveur : 401 sans session ; type inconnu → 400 {success:false, msg} ; vente inconnue ou non terminée
// → 200 {success:false, msg} ; jamais de 403 (la réimpression du poste n'exige que la session).
//
// Le mobile n'appelle JAMAIS `POST v1/vente/ticket/vno` ni `ticket/vo` : ces routes impriment sur l'imprimante du
// serveur (caisse). Vérifié le 19/11 : aucun appel dans l'application.
//
// RÈGLE DE NON-RÉGRESSION : tant qu'un serveur répond 404 / 405 (route absente : serveur de l'officine aujourd'hui),
// le ticket est imprimé avec le gabarit local (lib/services/ticket_texte.dart), comme en 4.15.0. Date de déploiement
// de la route en officine : pas encore fixée par le serveur.
//
// États de la route, par adresse de serveur, gardés en mémoire :
//  - inconnue : on essaie ; 404 / 405 → absente (gabarit local) ; réseau → gabarit local (rien n'a jamais été dessiné
//    par ce serveur, le ticket local est celui d'avant) ;
//  - présente (le serveur a répondu en JSON sur la route : tickets, 400 ou 200 `success:false`) : en cas de panne
//    réseau, PAS de ticket recomposé (il ne serait pas celui du web) : « Ticket non imprimé : réseau indisponible »
//    et « Réimprimer » ;
//  - absente : gabarit local sans nouvel essai pendant [delaiNouvelEssai] (le serveur peut être mis à jour).
// Une réponse JSON de la route prouve aussi que le serveur a la demande 63 (droit P_REMISE_VENTE contrôlé, « 0 » =
// sans remise) : noté dans DroitsVente (lib/ventes/common/remise_vente.dart).
// Aucun texte de ticket, aucun nom de client ni de patient n'est écrit dans un journal.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/services/largeur_ticket.dart';

/// Type de ticket demandé au serveur.
enum TypeTicketServeur {
  /// Vente comptant.
  vno('vno'),

  /// Vente assurance, carnet, dépôt (tous les tickets de la vente, dans l'ordre d'impression).
  vo('vo'),

  /// Ticket de prévente (QR code dans l'image).
  prevente('prevente');

  final String chemin;
  const TypeTicketServeur(this.chemin);
}

/// Un ticket dessiné par le serveur.
class TicketImage {
  final String modele;
  final Uint8List png;
  final int largeurPoints;
  final int hauteurPoints;
  const TicketImage({required this.modele, required this.png, required this.largeurPoints, required this.hauteurPoints});

  @override
  String toString() => 'TicketImage($modele, ${largeurPoints}x$hauteurPoints)';
}

/// Réponse de la route image.
sealed class ReponseTicketServeur {
  const ReponseTicketServeur();
}

/// Tickets à imprimer, dans l'ordre.
class TicketsServeur extends ReponseTicketServeur {
  final int largeur;
  final List<TicketImage> tickets;
  const TicketsServeur(this.largeur, this.tickets);
}

/// Route absente (404 / 405) : gabarit local.
class RouteTicketAbsente extends ReponseTicketServeur {
  const RouteTicketAbsente();
}

/// Refus du serveur (403 `interdit`, `success:false`, réponse illisible) : [message] tel quel.
class TicketRefuse extends ReponseTicketServeur {
  final String message;
  const TicketRefuse(this.message);
}

/// 4.15.1 : 200 `{success:false, msg}` de la route (vente inconnue ou non terminée, aucun ticket) : [message] du
/// serveur tel quel.
class TicketRefuseVente extends TicketRefuse {
  const TicketRefuseVente(super.message);
}

/// 4.15.1 : 400 `{success:false, msg}` (type de ticket inconnu du serveur) : gabarit local.
class TicketTypeInconnu extends TicketRefuse {
  const TicketTypeInconnu(super.message);
}

/// Réseau indisponible (aucune réponse).
class TicketReseauIndisponible extends ReponseTicketServeur {
  const TicketReseauIndisponible();
}

enum EtatRouteTicket { inconnue, presente, absente }

class TicketServeur {
  TicketServeur._();

  static const String messageReseau = 'Ticket non imprimé : réseau indisponible';

  /// Route absente : nouvel essai après ce délai (mise à jour du serveur).
  static const Duration delaiNouvelEssai = Duration(minutes: 30);

  static final Map<String, EtatRouteTicket> _etats = {};
  static final Map<String, DateTime> _absenteDepuis = {};

  /// Horloge remplaçable dans les tests.
  @visibleForTesting
  static DateTime Function() maintenant = DateTime.now;

  /// Chemin de la route (relatif à l'adresse v1 du client Dio).
  static String chemin(TypeTicketServeur type, String id) => '/vente/ticket/${type.chemin}/${Uri.encodeComponent(id)}/image';

  static EtatRouteTicket etat(String serveur) {
    final e = _etats[serveur] ?? EtatRouteTicket.inconnue;
    if (e == EtatRouteTicket.absente) {
      final depuis = _absenteDepuis[serveur];
      if (depuis != null && maintenant().difference(depuis) >= delaiNouvelEssai) return EtatRouteTicket.inconnue;
    }
    return e;
  }

  static void _noter(String serveur, EtatRouteTicket e) {
    _etats[serveur] = e;
    if (e == EtatRouteTicket.absente) {
      _absenteDepuis[serveur] = maintenant();
    } else {
      _absenteDepuis.remove(serveur);
    }
  }

  /// La route a répondu en JSON : elle existe (état « présente ») et le serveur a la demande 63.
  static void _routeRepond(String serveur) {
    _noter(serveur, EtatRouteTicket.presente);
    DroitsVente.instance.controleConstate(DroitsVente.remiseVenteDroit);
  }

  @visibleForTesting
  static void oublier() {
    _etats.clear();
    _absenteDepuis.clear();
    maintenant = DateTime.now;
  }

  /// Lecture des tickets (jamais d'exception). [largeur] : 58 ou 80 (ramenée par la règle du serveur).
  static Future<ReponseTicketServeur> lire(Dio dio, {required TypeTicketServeur type, required String id, required int largeur, int dpi = 203}) async {
    final serveur = dio.options.baseUrl;
    final mm = LargeurTicket.valide(largeur);
    try {
      final r = await dio.get<dynamic>(
        chemin(type, id),
        queryParameters: {'largeur': mm, 'dpi': dpi},
        options: Options(validateStatus: (_) => true, receiveTimeout: const Duration(seconds: 20)),
      );
      final code = r.statusCode ?? 0;
      final body = r.data is String ? _json(r.data as String) : r.data;
      if (code == 404 || code == 405 || code == 501) {
        _noter(serveur, EtatRouteTicket.absente);
        return const RouteTicketAbsente();
      }
      if (code == 403) {
        final msg = body is Map ? '${body['msg'] ?? body['message'] ?? ''}'.trim() : '';
        return TicketRefuse(msg.isEmpty ? 'Accès refusé : ticket du serveur non disponible pour ce compte.' : msg);
      }
      if (code == 401) return const TicketRefuse('Session expirée : reconnectez-vous puis réimprimez.');
      if (code == 400 && body is Map && body['success'] == false) {
        _routeRepond(serveur);
        final msg = '${body['msg'] ?? ''}'.trim();
        return TicketTypeInconnu(msg.isEmpty ? 'Type de ticket inconnu du serveur.' : msg);
      }
      if (code != 200) {
        if (code == 502 || code == 503 || code == 504) return const TicketReseauIndisponible();
        return TicketRefuse('Erreur du serveur (code $code) : ticket non lu.');
      }
      if (body is! Map) return const TicketRefuse('Réponse inattendue du serveur (ticket).');
      if (body['success'] != true) {
        final msg = '${body['msg'] ?? body['message'] ?? ''}'.trim();
        if (body['success'] == false) {
          _routeRepond(serveur);
          return TicketRefuseVente(msg.isEmpty ? 'Le serveur n\'a pas rendu le ticket.' : msg);
        }
        return TicketRefuse(msg.isEmpty ? 'Le serveur n\'a pas rendu le ticket.' : msg);
      }
      final lus = <TicketImage>[];
      final attendu = LargeurTicket.points(mm);
      for (final t in (body['tickets'] is List ? body['tickets'] as List : const [])) {
        if (t is! Map) continue;
        final b64 = '${t['png'] ?? ''}';
        if (b64.isEmpty) continue;
        final Uint8List png;
        try {
          png = base64Decode(b64.contains(',') ? b64.substring(b64.indexOf(',') + 1) : b64);
        } catch (_) {
          return const TicketRefuse('Image du ticket illisible.');
        }
        if (!_estPng(png)) return const TicketRefuse('Image du ticket illisible.');
        final lp = int.tryParse('${t['largeurPoints'] ?? ''}') ?? 0;
        if (lp != attendu) return TicketRefuse('Ticket du serveur à la mauvaise largeur ($lp points au lieu de $attendu).');
        lus.add(TicketImage(
          modele: '${t['modele'] ?? ''}',
          png: png,
          largeurPoints: lp,
          hauteurPoints: int.tryParse('${t['hauteurPoints'] ?? ''}') ?? 0,
        ));
      }
      if (lus.isEmpty) return const TicketRefuse('Le serveur n\'a rendu aucun ticket.');
      _routeRepond(serveur);
      return TicketsServeur(int.tryParse('${body['largeur'] ?? ''}') ?? mm, lus);
    } on DioException catch (e) {
      // Réponse reçue mais illisible (JSON tronqué) : refus (gabarit local) ; aucune réponse : réseau.
      if (e.type == DioExceptionType.unknown && e.error is FormatException) return const TicketRefuse('Réponse du serveur illisible (ticket).');
      return const TicketReseauIndisponible();
    } catch (_) {
      return const TicketRefuse('Ticket du serveur illisible.');
    }
  }

  static Object? _json(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return s;
    }
  }

  static bool _estPng(Uint8List b) =>
      b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 && b[4] == 0x0D && b[5] == 0x0A && b[6] == 0x1A && b[7] == 0x0A;
}
