// lib/horsligne/rapports_hl.dart
// Rapports des ventes hors ligne (étape H2) :
// - fin de journée (contrôle de stock) : ventes du jour (HL, heure, vendeur, type, statut, référence
//   serveur), TOTAL PAR PRODUIT (CIP, nom, quantité sortie, montant), espèces encaissées provisoirement ;
// - anomalies de synchronisation (date, HL, client, bon, motif, état).
// Lignes de texte communes au ticket (ReceiptService.printTextReport) et au PDF partagé.
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/utils/constants.dart';

/// Total d'un produit sur la journée.
class TotalProduitHL {
  final String produitId;
  final String cip;
  final String nom;
  final int qte;
  final int montant;
  const TotalProduitHL({required this.produitId, required this.cip, required this.nom, required this.qte, required this.montant});
}

class RapportJourHL {
  final DateTime jour;
  final List<VenteHorsLigne> ventes;
  final List<TotalProduitHL> produits;
  const RapportJourHL({required this.jour, required this.ventes, required this.produits});

  int get montantTotal => ventes.fold(0, (s, v) => s + v.totalEstime);

  /// Espèces encaissées provisoirement (net encaissé des ventes « espèces »).
  int get especes => ventes.where((v) => v.fin == FinVenteHL.especes).fold(0, (s, v) => s + v.netEstime);
  int get quantiteTotale => produits.fold(0, (s, p) => s + p.qte);
  int compte(StatutVenteHL s) => ventes.where((v) => v.statut == s).length;
}

bool _memeJour(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Rapport du [jour] : toutes les ventes saisies hors ligne ce jour-là (quel que soit leur statut :
/// les produits sont sortis du stock même si la vente a été ressaisie ou est en anomalie).
RapportJourHL rapportDuJour(List<VenteHorsLigne> ventes, DateTime jour) {
  final duJour = ventes.where((v) => _memeJour(v.createdAt, jour)).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final parProduit = <String, TotalProduitHL>{};
  for (final v in duJour) {
    for (final l in v.lignes) {
      final t = parProduit[l.produitId];
      parProduit[l.produitId] = TotalProduitHL(
        produitId: l.produitId,
        cip: l.cip,
        nom: l.nom,
        qte: (t?.qte ?? 0) + l.qte,
        montant: (t?.montant ?? 0) + l.total,
      );
    }
  }
  final produits = parProduit.values.toList()..sort((a, b) => a.nom.compareTo(b.nom));
  return RapportJourHL(jour: jour, ventes: duJour, produits: produits);
}

String _f(int v) => Constants.formatNumber(v);

/// Statut court pour le rapport.
String statutCourt(StatutVenteHL s) => switch (s) {
      StatutVenteHL.envoyee => 'envoyée',
      StatutVenteHL.enAttente || StatutVenteHL.envoiEnCours => 'non envoyée',
      StatutVenteHL.ressaisie => 'ressaisie',
      StatutVenteHL.aVerifier => 'anomalie',
      StatutVenteHL.traitee => 'traitée',
    };

String _coupe(String s, int n) => s.length <= n ? s : s.substring(0, n);

/// Lignes du rapport de fin de journée ([cols] : largeur du ticket).
List<String> lignesRapportJour(RapportJourHL r, {int cols = 32}) {
  final h = DateFormat('HH:mm');
  final out = <String>[
    'Journée du ${DateFormat('dd/MM/yyyy').format(r.jour)}',
    '${r.ventes.length} vente(s) hors ligne · ${_f(r.montantTotal)} F',
    'Envoyées ${r.compte(StatutVenteHL.envoyee)} · non envoyées ${r.compte(StatutVenteHL.enAttente) + r.compte(StatutVenteHL.envoiEnCours)}',
    'Ressaisies ${r.compte(StatutVenteHL.ressaisie)} · anomalies ${r.compte(StatutVenteHL.aVerifier)} · traitées ${r.compte(StatutVenteHL.traitee)}',
    'Espèces provisoires : ${_f(r.especes)} F',
    '',
    'VENTES',
  ];
  for (final v in r.ventes) {
    out.add('${v.numeroLabel} ${h.format(v.createdAt)} ${v.type.label} ${_f(v.netEstime)} F');
    out.add('  ${statutCourt(v.statut)}${v.reference == null ? '' : ' → ${v.reference}'}${v.userName.isEmpty ? '' : ' · ${v.userName}'}');
  }
  out
    ..add('')
    ..add('TOTAL PAR PRODUIT (quantité sortie)');
  for (final p in r.produits) {
    out.add(_coupe('${p.cip.isEmpty ? '' : '${p.cip} '}${p.nom}', cols));
    out.add('  qté ${p.qte} · ${_f(p.montant)} F');
  }
  out.add('Total : ${r.quantiteTotale} boîte(s) · ${_f(r.produits.fold(0, (s, p) => s + p.montant))} F');
  return out;
}

/// Lignes du rapport d'anomalies.
List<String> lignesAnomalies(List<AnomalieHL> anomalies, {int cols = 32}) {
  final d = DateFormat('dd/MM HH:mm');
  final out = <String>['${anomalies.length} anomalie(s) · ${anomalies.where((a) => !a.traitee).length} non traitée(s)', ''];
  for (final a in anomalies) {
    out.add('${a.numeroLabel} ${d.format(a.date)} ${a.traitee ? '[traitée]' : '[à traiter]'}');
    if (a.client.isNotEmpty) out.add(_coupe('  Client : ${a.client}', cols));
    if (a.bons.isNotEmpty) out.add('  Bon : ${a.bons}');
    out.add('  ${a.natureLabel}');
    out.add('  ${a.motif}');
  }
  return out;
}

/// PDF simple (texte) partagé avec le service d'impression / partage du téléphone.
Future<void> partagerRapportPdf({required String titre, required List<String> lignes, required String fichier}) async {
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    build: (_) => [
      pw.Text(titre, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      for (final l in lignes) pw.Text(l.replaceAll('→', '->'), style: const pw.TextStyle(fontSize: 10)),
    ],
  ));
  await Printing.sharePdf(bytes: await doc.save(), filename: fichier);
}
