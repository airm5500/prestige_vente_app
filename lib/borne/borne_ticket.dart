// lib/borne/borne_ticket.dart
// Ticket de la borne : numéro de prévente en GRAND, code (QR ou code-barres) de la RÉFÉRENCE —
// le caissier la retrouve dans « Préventes à encaisser » en la scannant dans la recherche —,
// produits (sauf ticket discret), total, « Présentez ce ticket à la caisse », date/heure.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/services/impression_ticket.dart';
import 'package:prestige_vente_app/services/largeur_ticket.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/services/ticket_prevente.dart';
import 'package:prestige_vente_app/utils/constants.dart';

class BorneTicket {
  final String officine;
  final BornePrevente prevente;
  final bool discret;

  /// 'QR_CODE' ou 'BARCODE' (réglage Impression).
  final String codeType;
  final int largeur;

  /// B3 : vente payée par mobile money (nom de l'opérateur) ; null : prévente à payer en caisse.
  final String? payePar;

  /// 4.13.1 : payée SANS clôture automatique (utilisateur borne sans le droit de terminer une vente) : la caisse
  /// termine la vente. 4.15.0 (demande 62) : aussi quand la clôture automatique demandée n'a pas été confirmée par le
  /// serveur (caisse du compte de la borne fermée, net modifié) : jamais « vente terminée » sans `cloture:true`.
  final bool aTerminer;
  const BorneTicket({
    required this.officine,
    required this.prevente,
    this.discret = false,
    this.codeType = 'QR_CODE',
    this.largeur = 58,
    this.payePar,
    this.aTerminer = false,
  });

  static const String invitation = 'Présentez ce ticket à la caisse';
  static const String invitationPayee = 'Présentez ce ticket au comptoir pour récupérer vos produits';
  static const String invitationPayeeATerminer = 'PAYÉE, présentez ce ticket à la caisse';

  /// 4.14.0 : le même ticket composé pour une autre largeur (imprimante intégrée de 58 mm).
  BorneTicket aLargeur(int mm) => mm == largeur
      ? this
      : BorneTicket(officine: officine, prevente: prevente, discret: discret, codeType: codeType, largeur: mm, payePar: payePar, aTerminer: aTerminer);

  /// 4.14.0 : le ticket de prévente du serveur (GET v1/vente/ticket/prevente/{id}/image) remplace ce ticket seulement
  /// pour une prévente à payer en caisse, hors « ticket discret » (l'image du serveur porte les produits) : un ticket
  /// payé ou discret garde le gabarit de la borne.
  bool get serveurPossible => !paye && !discret && prevente.venteId.isNotEmpty;

  bool get paye => payePar != null;
  String get titre => paye ? 'VENTE BORNE - PAYEE' : 'PRE-VENTE BORNE';
  String get invitationTexte => paye ? (aTerminer ? invitationPayeeATerminer : invitationPayee) : invitation;

  String get date => DateFormat('dd/MM/yyyy HH:mm').format(prevente.at);

  /// Lignes de texte (après le numéro et avant le code) : produits ou mention discrète, puis total.
  /// 4.1.1 : un nom plus long que la ligne passe sur deux lignes (coupure à un espace) au lieu d'être tronqué
  /// sans signe (« …CPR EFFV » perdait « B/20 ») ; les noms qui tiennent sont imprimés comme avant.
  /// Le « ticket discret » est propre à la borne (indépendant du réglage Impression du comptoir).
  List<String> get lignes {
    final cols = TicketPrevente.colonnes(largeur);
    final out = <String>[];
    if (discret) {
      out.add(TicketPrevente.articles(TicketPrevente.nombreArticles(prevente.lignes)));
    } else {
      out.addAll(TicketPrevente.produits(prevente.lignes, cols));
    }
    out.add(List.filled(cols, '-').join());
    out.add(paye ? 'TOTAL: ${Constants.formatNumber(prevente.total)} F' : 'TOTAL A PAYER: ${Constants.formatNumber(prevente.total)} F');
    if (paye) out.add('PAYE PAR ${payePar!.toUpperCase()}');
    return out;
  }

  /// Aperçu (écran sans imprimante, tests).
  Widget apercu() {
    const s = TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black);
    return Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Text(officine.toUpperCase(), style: s.copyWith(fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center),
      Text(titre, key: const ValueKey('borne-ticket-titre'), style: s.copyWith(fontWeight: FontWeight.bold)),
      Text('N° ${prevente.numero}', key: const ValueKey('borne-ticket-numero'), style: s.copyWith(fontWeight: FontWeight.w900, fontSize: 30)),
      const SizedBox(height: 4),
      Align(alignment: Alignment.centerLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final l in lignes) Text(l, style: s)])),
      const SizedBox(height: 6),
      Text(prevente.reference, key: const ValueKey('borne-ticket-reference'), style: s),
      Text(invitationTexte, style: s.copyWith(fontWeight: FontWeight.bold)),
      Text(date, style: s),
    ]);
  }
}

/// Impression du ticket : true si imprimé (imprimante intégrée Sunmi), false sinon (affichage plein écran).
abstract class BorneImprimante {
  Future<bool> imprimer(BorneTicket ticket);
}

/// 4.14.0 : images du ticket de prévente dessiné par le serveur, ou null (route absente, refus, réseau : gabarit
/// de la borne, comme avant). La borne ne pose jamais de question : en cas d'échec, ticket à l'écran.
Future<List<TicketImage>?> ticketBorneServeur(Dio? dio, BorneTicket t) async {
  if (dio == null || !t.serveurPossible) return null;
  if (TicketServeur.etat(dio.options.baseUrl) == EtatRouteTicket.absente) return null;
  final r = await TicketServeur.lire(dio, type: TypeTicketServeur.prevente, id: t.prevente.venteId, largeur: t.largeur);
  return r is TicketsServeur ? r.tickets : null;
}

class SunmiBorneImprimante implements BorneImprimante {
  /// Mode test d'impression (Réglages › Impression) : pas d'impression, affichage plein écran.
  final bool modeTest;

  /// 4.14.0 : client de la session de la borne (ticket du serveur) ; null : gabarit de la borne seulement.
  final Dio? dio;
  const SunmiBorneImprimante({this.modeTest = false, this.dio});

  @override
  Future<bool> imprimer(BorneTicket ticket) async {
    if (modeTest) return false;
    // 4.14.0 : largeur de l'imprimante intégrée imposée (un réglage 80 mm sur un terminal de 58 mm coupait les lignes).
    final t = ticket.aLargeur(await LargeurTicket.pourImpression(ticket.largeur));
    final images = await ticketBorneServeur(dio, t);
    if (images != null) {
      final echec = await ImpressionTicket.imprimeur(images);
      if (echec == null) return true;
      return false;
    }
    return ReceiptService().printBorneTicket(
      officine: t.officine,
      numero: t.prevente.numero,
      reference: t.prevente.reference,
      lignes: t.lignes,
      pied: [t.invitationTexte, t.date],
      titre: t.titre,
      codeType: t.codeType,
    );
  }
}
