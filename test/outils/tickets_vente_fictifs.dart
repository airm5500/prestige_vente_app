// 4.14.0 — Tickets de vente FICTIFS (comptant, différé, assurance, carnet / crédit, avec et sans remise) pour les tests
// de mise en page et les captures. Aucune donnée réelle : noms, matricules, bons et montants inventés.
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/ayant_droit.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/services/ticket_texte.dart';

final dateFictive = DateTime(2026, 11, 19, 10, 42);
final officineTicket = Officine(fullName: 'Dr TEST Fictif', nomComplet: 'Pharmacie Fictive du Test');
final vendeurTicket = User(userId: 'U1', login: 'vendeur', firstName: 'Vendeur', lastName: 'Fictif', officineName: 'TEST');

SaleItemDetail ligneTicket(String nom, int q, int pu) => SaleItemDetail(
    lgPREENREGISTREMENTDETAILID: 'L-$nom', lgFAMILLEID: 'F-$nom', strNAME: nom, intCIP: '0000000', intQUANTITY: q, intPRICEUNITAIR: pu, intPRICE: q * pu, strREF: '20261119000045');

final lignesTicket = [
  ligneTicket('PRODUIT FICTIF A 500MG CPR B/20', 1, 1500),
  ligneTicket('PRODUIT FICTIF B SIROP', 2, 2350),
  // Désignation très longue : passe à la ligne, jamais tronquée, prix jamais coupé.
  ligneTicket('PRODUIT FICTIF C AU NOM TRES LONG POUR LE TEST DE COUPURE 1000MG COMPRIMES EFFERVESCENTS B/40', 3, 12500),
];

int get totalTicket => lignesTicket.fold(0, (s, l) => s + l.intPRICE);

final clientTicket = ClientAssurance(
  lgCLIENTID: 'CL-FICT',
  fullName: 'CLIENT FICTIF Test',
  strFIRSTNAME: 'CLIENT FICTIF',
  strLASTNAME: 'Test',
  strNUMEROSECURITESOCIAL: 'MAT-FICT-001',
  tiersPayants: [
    ClientTiersPayant(lgTIERSPAYANTID: 'TP1', tpFullName: 'ORGANISME FICTIF UN', taux: 70, numSecurity: 'MAT-FICT-001', compteTp: 'CT1', order: 1, principal: true),
    ClientTiersPayant(lgTIERSPAYANTID: 'TP2', tpFullName: 'MUTUELLE FICTIVE DEUX', taux: 30, numSecurity: 'MAT-FICT-001', compteTp: 'CT2', order: 2, principal: false),
    ClientTiersPayant(lgTIERSPAYANTID: 'TP3', tpFullName: 'CARNET FICTIF', taux: 100, numSecurity: 'MAT-FICT-001', compteTp: 'CT3', order: 1, principal: true),
  ],
  ayantDroits: const [],
);

final ayantDroitTicket = AyantDroit(
    lgAYANTSDROITSID: 'AD1', lgCLIENTID: 'CL-FICT', fullName: 'BENEFICIAIRE FICTIF', strFIRSTNAME: 'BENEFICIAIRE', strLASTNAME: 'FICTIF', strNUMEROSECURITESOCIAL: 'MAT-FICT-001', strSEXE: 'F');

/// Comptant, 43 700 F, remise du serveur de 4 070 F (net 39 630 F), espèces.
TicketTexte ticketComptant(int papier, {bool remise = true, String mode = 'ESPECES', int? verse = 40000}) {
  final r = remise ? 4070 : 0;
  final net = totalTicket - r;
  return ReceiptService.ticketVenteComptant(
    papier: papier,
    officine: officineTicket,
    saleSummary: SaleSummary(montant: totalTicket, remise: r, montantNet: net, reference: '20261119000045', venteId: 'V-FICT'),
    items: lignesTicket,
    paymentMethod: PaymentMethod(id: '1', name: mode),
    currentUser: vendeurTicket,
    showQrCode: true,
    montantVerse: verse,
    monnaie: verse == null ? null : verse - net,
    date: dateFictive,
  );
}

/// Assurance : organisme à 70 %, part du client 30 % moins la remise (la remise porte sur la part du client).
TicketTexte ticketAssurance(int papier, {bool remise = true}) {
  final tp = (totalTicket * 70) ~/ 100; // 30 590
  final r = remise ? 1220 : 0;
  return ReceiptService.ticketVenteAssurance(
    papier: papier,
    officine: officineTicket,
    saleSummary: AssuranceSaleSummary(
      montant: totalTicket,
      remise: r,
      montantTp: tp,
      montantNet: totalTicket - tp - r,
      tierspayants: [TiersPayantSummary(numBon: 'BON-FICT-77', taux: 70, compteTp: 'CT1', tpnet: tp)],
      reference: '20261119000046',
      venteId: 'V-FICT-A',
    ),
    items: lignesTicket,
    client: clientTicket,
    ayantDroit: ayantDroitTicket,
    paymentMethod: PaymentMethod(id: '1', name: 'ESPECES'),
    currentUser: vendeurTicket,
    reference: '20261119000046',
    title: 'VENTE ASSURANCE',
    montantVerse: 15000,
    monnaie: 15000 - (totalTicket - tp - r),
    date: dateFictive,
  );
}

/// Carnet (crédit) à 100 % : pris sur le carnet, part client 0, remise sur le montant.
TicketTexte ticketCarnet(int papier, {bool remise = true}) {
  final r = remise ? 4070 : 0;
  return ReceiptService.ticketVenteAssurance(
    papier: papier,
    officine: officineTicket,
    saleSummary: AssuranceSaleSummary(
      montant: totalTicket,
      remise: r,
      montantTp: totalTicket - r,
      montantNet: 0,
      tierspayants: [TiersPayantSummary(numBon: 'BON-FICT-12', taux: 100, compteTp: 'CT3', tpnet: totalTicket - r)],
      reference: '20261119000047',
      venteId: 'V-FICT-C',
    ),
    items: lignesTicket,
    client: clientTicket,
    ayantDroit: ayantDroitTicket,
    paymentMethod: PaymentMethod(id: '1', name: 'CARNET'),
    currentUser: vendeurTicket,
    reference: '20261119000047',
    title: 'VENTE CARNET',
    date: dateFictive,
  );
}

/// Les tickets de référence : nom de fichier → ticket.
Map<String, TicketTexte> ticketsReference() => {
      for (final p in [58, 80]) ...{
        'comptant_remise_$p': ticketComptant(p),
        'comptant_sans_remise_$p': ticketComptant(p, remise: false),
        'comptant_differe_$p': ticketComptant(p, remise: false, mode: 'DIFFERE', verse: null),
        'assurance_remise_$p': ticketAssurance(p),
        'carnet_remise_$p': ticketCarnet(p),
        'carnet_sans_remise_$p': ticketCarnet(p, remise: false),
      },
    };

/// Résumé d'une vente assurance fictive (identifiant serveur : route image).
final ticketAssuranceResume = AssuranceSaleSummary(
  montant: totalTicket,
  remise: 1220,
  montantTp: 30590,
  montantNet: totalTicket - 30590 - 1220,
  tierspayants: [TiersPayantSummary(numBon: 'BON-FICT-77', taux: 70, compteTp: 'CT1', tpnet: 30590)],
  reference: '20261119000046',
  venteId: 'V-FICT-A',
);
