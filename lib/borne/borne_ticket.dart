// lib/borne/borne_ticket.dart
// Ticket de la borne : numéro de prévente en GRAND, code (QR ou code-barres) de la RÉFÉRENCE —
// le caissier la retrouve dans « Préventes à encaisser » en la scannant dans la recherche —,
// produits (sauf ticket discret), total, « Présentez ce ticket à la caisse », date/heure.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/utils/constants.dart';

class BorneTicket {
  final String officine;
  final BornePrevente prevente;
  final bool discret;

  /// 'QR_CODE' ou 'BARCODE' (réglage Impression).
  final String codeType;
  final int largeur;
  const BorneTicket({required this.officine, required this.prevente, this.discret = false, this.codeType = 'QR_CODE', this.largeur = 58});

  static const String invitation = 'Présentez ce ticket à la caisse';

  String get date => DateFormat('dd/MM/yyyy HH:mm').format(prevente.at);

  /// Lignes de texte (après le numéro et avant le code) : produits ou mention discrète, puis total.
  List<String> get lignes {
    final cols = largeur == 58 ? 32 : 48;
    String fit(String s, int n) => s.length <= n ? s.padRight(n) : s.substring(0, n);
    final out = <String>[];
    if (discret) {
      final n = prevente.lignes.fold<int>(0, (s, l) => s + l.intQUANTITY);
      out.add('$n article${n > 1 ? 's' : ''}');
    } else {
      for (final l in prevente.lignes) {
        out.add(fit(l.strNAME.replaceAll('\n', ' '), cols));
        final px = '${l.intQUANTITY} x ${Constants.formatNumber(l.intPRICEUNITAIR)}';
        final tot = Constants.formatNumber(l.intPRICE == 0 ? l.intQUANTITY * l.intPRICEUNITAIR : l.intPRICE);
        out.add('  $px${tot.padLeft(cols - 2 - px.length)}');
      }
    }
    out.add(List.filled(cols, '-').join());
    out.add('TOTAL A PAYER: ${Constants.formatNumber(prevente.total)} F');
    return out;
  }

  /// Aperçu (écran sans imprimante, tests).
  Widget apercu() {
    const s = TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black);
    return Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Text(officine.toUpperCase(), style: s.copyWith(fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center),
      Text('PRE-VENTE BORNE', style: s.copyWith(fontWeight: FontWeight.bold)),
      Text('N° ${prevente.numero}', key: const ValueKey('borne-ticket-numero'), style: s.copyWith(fontWeight: FontWeight.w900, fontSize: 30)),
      const SizedBox(height: 4),
      Align(alignment: Alignment.centerLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final l in lignes) Text(l, style: s)])),
      const SizedBox(height: 6),
      Text(prevente.reference, key: const ValueKey('borne-ticket-reference'), style: s),
      Text(invitation, style: s.copyWith(fontWeight: FontWeight.bold)),
      Text(date, style: s),
    ]);
  }
}

/// Impression du ticket : true si imprimé (imprimante intégrée Sunmi), false sinon (affichage plein écran).
abstract class BorneImprimante {
  Future<bool> imprimer(BorneTicket ticket);
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
      pied: [BorneTicket.invitation, t.date],
      codeType: t.codeType,
    );
  }
}
