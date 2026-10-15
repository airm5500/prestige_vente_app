// lib/borne/borne_ticket.dart
// Ticket de la borne : numéro de prévente en GRAND, code (QR ou code-barres) de la RÉFÉRENCE —
// le caissier la retrouve dans « Préventes à encaisser » en la scannant dans la recherche —,
// produits (sauf ticket discret), total, « Présentez ce ticket à la caisse », date/heure.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
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
  const BorneTicket({
    required this.officine,
    required this.prevente,
    this.discret = false,
    this.codeType = 'QR_CODE',
    this.largeur = 58,
    this.payePar,
  });

  static const String invitation = 'Présentez ce ticket à la caisse';
  static const String invitationPayee = 'Présentez ce ticket au comptoir pour récupérer vos produits';

  bool get paye => payePar != null;
  String get titre => paye ? 'VENTE BORNE - PAYEE' : 'PRE-VENTE BORNE';
  String get invitationTexte => paye ? invitationPayee : invitation;

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

/// Imprimante qui sait dire POURQUOI le dernier ticket n'est pas sorti (PrestigePOS : Bluetooth, USB, réseau).
/// La borne affiche alors ce message clair au-dessus du ticket montré à l'écran (le client peut le photographier).
/// Facultatif : l'imprimante Sunmi de Prestige Mobile ne l'implémente pas (affichage inchangé).
abstract class BorneImprimanteDiagnostic {
  /// Cause du dernier échec d'impression, en clair (null : imprimé, ou pas d'imprimante configurée).
  String? get dernierEchec;
}

class SunmiBorneImprimante implements BorneImprimante {
  /// Mode test d'impression (Réglages › Impression) : pas d'impression, affichage plein écran.
  final bool modeTest;
  const SunmiBorneImprimante({this.modeTest = false});

  @override
  Future<bool> imprimer(BorneTicket t) async {
    if (modeTest) return false;
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
