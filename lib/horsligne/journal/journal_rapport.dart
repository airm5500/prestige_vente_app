// lib/horsligne/journal/journal_rapport.dart
// Totaux et export du journal du terminal :
// - totaux ENCAISSÉS par mode (encaissements réussis en ligne + espèces encaissées à la saisie hors
//   ligne ; l'envoi de la file hors ligne n'est jamais recompté) ;
// - totaux de QUANTITÉS par produit (ventes : lignes ajoutées, une modification remplace la quantité ;
//   stock : réceptions, pointages, péremptions, retours, ajustements) ;
// - PDF (en-tête officine, terminal, utilisateur, période, tableau, totaux) et lignes du ticket résumé.
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/utils/constants.dart';

class TotalProduitJournal {
  final String id;
  final String nom;
  final int vendu;
  final int stock;
  const TotalProduitJournal({required this.id, required this.nom, required this.vendu, required this.stock});
}

class JournalTotaux {
  /// Mode (nom lisible) → montant encaissé.
  final Map<String, int> parMode;
  final List<TotalProduitJournal> produits;
  final int entrees;
  final int refus;
  final int echecs;
  final int doublons;
  const JournalTotaux({required this.parMode, required this.produits, required this.entrees, this.refus = 0, this.echecs = 0, this.doublons = 0});

  int get encaisse => parMode.values.fold(0, (s, v) => s + v);
}

/// Totaux d'une liste d'entrées. [nomsModes] : identifiant de mode → nom (« 1 » → « ESPECES »).
JournalTotaux calculerTotaux(List<JournalEntree> entrees, {Map<String, String> nomsModes = const {}}) {
  final parMode = <String, int>{};
  // Quantités : clé (référence + produit) → quantité, pour qu'une modification remplace.
  final vendu = <String, int>{};
  final stock = <String, int>{};
  final produitDe = <String, String>{};
  final noms = <String, String>{};
  var refus = 0, echecs = 0, doublons = 0;
  for (final e in entrees) {
    switch (e.resultat) {
      case ResultatJournal.refus:
        refus++;
      case ResultatJournal.echecReseau:
        echecs++;
      case ResultatJournal.doublonBloque:
        doublons++;
      default:
    }
    if (e.resultat != ResultatJournal.ok || e.source == SourceJournal.fileHL) continue;
    for (final m in e.modes.entries) {
      final nom = nomsModes[m.key] ?? (m.key.isEmpty ? 'Non précisé' : m.key);
      parMode[nom] = (parMode[nom] ?? 0) + m.value;
    }
    final cible = e.type == TypeJournal.stock ? stock : (e.type == TypeJournal.vente || e.type == TypeJournal.venteHL ? vendu : null);
    if (cible == null) continue;
    for (final p in e.produits) {
      if (p.id.isEmpty) continue;
      if (p.nom.isNotEmpty) noms[p.id] = p.nom;
      // Ventes : par vente et produit (une modification remplace) ; stock : un pointage remplace.
      final parVente = !identical(cible, stock);
      final cle = parVente || p.remplace ? '${e.refServeur}|${e.refLocale}|${p.id}' : '${e.id ?? e.at.microsecondsSinceEpoch}|${p.id}|${cible.length}';
      produitDe[cle] = p.id;
      cible[cle] = p.remplace ? p.qte : (cible[cle] ?? 0) + p.qte;
    }
  }
  final parProduitVendu = <String, int>{};
  final parProduitStock = <String, int>{};
  vendu.forEach((k, q) => parProduitVendu[produitDe[k]!] = (parProduitVendu[produitDe[k]!] ?? 0) + q);
  stock.forEach((k, q) => parProduitStock[produitDe[k]!] = (parProduitStock[produitDe[k]!] ?? 0) + q);
  final ids = {...parProduitVendu.keys, ...parProduitStock.keys};
  final produits = [
    for (final id in ids) TotalProduitJournal(id: id, nom: noms[id] ?? id, vendu: parProduitVendu[id] ?? 0, stock: parProduitStock[id] ?? 0),
  ]..sort((a, b) => a.nom.compareTo(b.nom));
  return JournalTotaux(parMode: parMode, produits: produits, entrees: entrees.length, refus: refus, echecs: echecs, doublons: doublons);
}

String _f(int v) => Constants.formatNumber(v);
final _dt = DateFormat('dd/MM/yyyy HH:mm');
final _d = DateFormat('dd/MM/yyyy');

/// « 10/10/2026 » ou « 08/10/2026 → 10/10/2026 ».
String periodeLabel(DateTime? du, DateTime? au) {
  if (du == null && au == null) return 'Tout l\'historique';
  final a = du == null ? '…' : _d.format(du);
  final b = au == null ? '…' : _d.format(au);
  return a == b ? a : '$a au $b';
}

/// Texte compatible avec la police standard du PDF (Latin-1) : flèches, espaces fines, tirets…
String pdfSafe(String s) {
  const remplace = {'→': '->', '…': '...', '—': '-', '–': '-', '’': "'", '‘': "'", '“': '"', '”': '"', 'ʳ': 'r', 'ᵉ': 'e', '≠': '<>', '•': '-', 'œ': 'oe', 'Œ': 'OE'};
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (remplace.containsKey(c)) {
      b.write(remplace[c]);
    } else if (r == 0x202F || r == 0x00A0 || r == 0x2009) {
      b.write(' ');
    } else if (r > 0xFF) {
      b.write('?');
    } else {
      b.write(c);
    }
  }
  return b.toString();
}

String _montant(JournalEntree e) => e.montant == null ? '' : _f(e.montant!);

String _refs(JournalEntree e) => [if (e.refLocale.isNotEmpty) e.refLocale, if (e.refServeur.isNotEmpty) e.refServeur].join(' / ');

String _resultat(JournalEntree e) => e.motif.isEmpty ? e.resultat.label : '${e.resultat.label} : ${e.motif}';

/// PDF du journal (octets). [officine] : nom affiché en en-tête.
Future<Uint8List> construirePdfJournal({
  required List<JournalEntree> entrees,
  required JournalTotaux totaux,
  String officine = '',
  String terminal = '',
  String utilisateur = '',
  DateTime? du,
  DateTime? au,
  DateTime? genereLe,
}) async {
  final doc = pw.Document(title: 'Journal du terminal', author: 'Prestige Mobile');
  const petit = pw.TextStyle(fontSize: 7.5);
  final gras = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
  String s(String t) => pdfSafe(t);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(20),
    header: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(s(officine.isEmpty ? 'Officine' : officine.toUpperCase()), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.Text(s('Page ${ctx.pageNumber}/${ctx.pagesCount}'), style: petit),
      ]),
      pw.Text('JOURNAL DU TERMINAL', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.Text(s('Terminal : ${terminal.isEmpty ? '-' : terminal}   ·   Utilisateur : ${utilisateur.isEmpty ? 'tous' : utilisateur}   ·   '
          'Période : ${periodeLabel(du, au)}   ·   Édité le ${_dt.format(genereLe ?? DateTime.now())}'), style: petit),
      pw.SizedBox(height: 6),
    ]),
    build: (_) => [
      pw.TableHelper.fromTextArray(
        headers: ['Date / heure', 'Utilisateur', 'Type', 'Action', 'Réf. locale / serveur', 'Montant', 'Qté', 'Source', 'Résultat'].map(s).toList(),
        data: [
          for (final e in entrees)
            [
              _dt.format(e.at),
              e.utilisateur,
              e.type.label,
              e.action,
              _refs(e),
              _montant(e),
              e.produits.isEmpty ? '' : '${e.quantite}',
              e.source,
              _resultat(e),
            ].map(s).toList(),
        ],
        headerStyle: gras,
        cellStyle: petit,
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        cellAlignments: {5: pw.Alignment.centerRight, 6: pw.Alignment.centerRight},
        columnWidths: {
          0: const pw.FixedColumnWidth(62),
          1: const pw.FixedColumnWidth(55),
          2: const pw.FixedColumnWidth(55),
          3: const pw.FlexColumnWidth(2),
          4: const pw.FlexColumnWidth(1.6),
          5: const pw.FixedColumnWidth(45),
          6: const pw.FixedColumnWidth(25),
          7: const pw.FixedColumnWidth(45),
          8: const pw.FlexColumnWidth(2),
        },
      ),
      pw.SizedBox(height: 10),
      pw.Text(s('${totaux.entrees} action(s) · ${totaux.refus} refus · ${totaux.echecs} échec(s) réseau · ${totaux.doublons} doublon(s) bloqué(s)'), style: gras),
      pw.SizedBox(height: 8),
      pw.Text(s('TOTAUX ENCAISSÉS PAR MODE'), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      pw.TableHelper.fromTextArray(
        headers: ['Mode', 'Montant (F)'].map(s).toList(),
        data: [
          for (final m in totaux.parMode.entries) [s(m.key), s(_f(m.value))],
          [s('TOTAL'), s(_f(totaux.encaisse))],
        ],
        headerStyle: gras,
        cellStyle: const pw.TextStyle(fontSize: 8.5),
        cellAlignments: {1: pw.Alignment.centerRight},
        columnWidths: {0: const pw.FixedColumnWidth(200), 1: const pw.FixedColumnWidth(100)},
      ),
      pw.SizedBox(height: 8),
      pw.Text(s('TOTAUX QUANTITÉS PAR PRODUIT'), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      pw.TableHelper.fromTextArray(
        headers: ['Produit', 'Vendu', 'Mouvements stock'].map(s).toList(),
        data: [
          for (final p in totaux.produits) [s(p.nom), '${p.vendu}', '${p.stock}'],
          ['TOTAL', '${totaux.produits.fold(0, (a, p) => a + p.vendu)}', '${totaux.produits.fold(0, (a, p) => a + p.stock)}'],
        ],
        headerStyle: gras,
        cellStyle: const pw.TextStyle(fontSize: 8.5),
        cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
        columnWidths: {0: const pw.FixedColumnWidth(300), 1: const pw.FixedColumnWidth(60), 2: const pw.FixedColumnWidth(90)},
      ),
    ],
  ));
  return doc.save();
}

String _coupe(String s, int n) => s.length <= n ? s : s.substring(0, n);

/// Lignes du ticket résumé ([cols] : largeur du ticket).
List<String> lignesTicketJournal(JournalTotaux t, {required String terminal, String utilisateur = '', DateTime? du, DateTime? au, int cols = 32}) => [
      _coupe('Terminal : $terminal', cols),
      _coupe('Utilisateur : ${utilisateur.isEmpty ? 'tous' : utilisateur}', cols),
      _coupe('Période : ${periodeLabel(du, au)}', cols),
      '${t.entrees} action(s)',
      '${t.refus} refus · ${t.echecs} échec(s)',
      if (t.doublons > 0) '${t.doublons} doublon(s) bloqué(s)',
      '',
      'ENCAISSÉ PAR MODE',
      for (final m in t.parMode.entries) _coupe('${m.key} : ${_f(m.value)} F', cols),
      'TOTAL : ${_f(t.encaisse)} F',
      '',
      'QUANTITÉS PAR PRODUIT',
      for (final p in t.produits) ...[
        _coupe(p.nom, cols),
        '  vendu ${p.vendu} · stock ${p.stock}',
      ],
    ];
