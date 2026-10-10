// lib/horsligne/journal/journal_screen.dart
// Écran « Journal du terminal » (Réglages › Hors ligne, et écran « Ventes hors ligne ») : actions du
// terminal ayant un effet stock ou caisse, en ligne et hors ligne. Par défaut : les actions du JOUR.
// Filtres : période (aujourd'hui, 3 jours, 7 jours, 30 jours, tout l'historique conservé, période…),
// type, utilisateur ; recherche par référence (HL…, n° de vente, BL…). Totaux encaissés par mode et
// quantités par produit. Export PDF (en-tête officine, terminal, utilisateur, période, tableau, totaux)
// et impression d'un ticket résumé.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:prestige_vente_app/horsligne/attente_ui.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_rapport.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/rapports_hl_screen.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

enum PeriodeJournal { jour, troisJours, septJours, trenteJours, tout, choisie }

extension PeriodeJournalInfo on PeriodeJournal {
  String get label => switch (this) {
        PeriodeJournal.jour => 'Aujourd\'hui',
        PeriodeJournal.troisJours => '3 jours',
        PeriodeJournal.septJours => '7 jours',
        PeriodeJournal.trenteJours => '30 jours',
        PeriodeJournal.tout => 'Tout',
        PeriodeJournal.choisie => 'Période…',
      };
}

class JournalTerminalScreen extends StatefulWidget {
  /// Journal utilisé (tests) ; sinon [JournalTerminal.instance].
  final JournalTerminal? journal;

  /// Partage du PDF (tests) ; par défaut le partage du téléphone.
  final Future<void> Function(List<int> bytes, String fichier)? partager;
  const JournalTerminalScreen({super.key, this.journal, this.partager});

  @override
  State<JournalTerminalScreen> createState() => _JournalTerminalScreenState();
}

class _JournalTerminalScreenState extends State<JournalTerminalScreen> {
  JournalTerminal get _j => widget.journal ?? JournalTerminal.instance;

  PeriodeJournal _periode = PeriodeJournal.jour;
  DateTimeRange? _choisie;
  TypeJournal? _type;
  String? _utilisateur;
  final _recherche = TextEditingController();

  List<JournalEntree> _entrees = const [];
  List<String> _utilisateurs = const [];
  Map<String, String> _nomsModes = const {};
  bool _chargement = true;
  String? _erreur;
  int _demande = 0;

  DateTime get _aujourdhui {
    final n = _j.now;
    return DateTime(n.year, n.month, n.day);
  }

  (DateTime?, DateTime?) get _bornes => switch (_periode) {
        PeriodeJournal.jour => (_aujourdhui, _aujourdhui),
        PeriodeJournal.troisJours => (_aujourdhui.subtract(const Duration(days: 2)), _aujourdhui),
        PeriodeJournal.septJours => (_aujourdhui.subtract(const Duration(days: 6)), _aujourdhui),
        PeriodeJournal.trenteJours => (_aujourdhui.subtract(const Duration(days: 29)), _aujourdhui),
        PeriodeJournal.tout => (null, null),
        PeriodeJournal.choisie => (_choisie?.start, _choisie?.end),
      };

  JournalFiltre get _filtre {
    final (du, au) = _bornes;
    return JournalFiltre(du: du, au: au, types: _type == null ? null : {_type!}, utilisateur: _utilisateur, recherche: _recherche.text);
  }

  @override
  void initState() {
    super.initState();
    _j.addListener(_charger);
    _charger();
    _chargerModes();
  }

  @override
  void dispose() {
    _j.removeListener(_charger);
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _chargerModes() async {
    try {
      final rows = await HorsLigne.instance.store.modes(qr: false);
      final m = {for (final r in rows) '${r['lgTYPEREGLEMENTID'] ?? ''}': '${r['strNAME'] ?? ''}'}..removeWhere((k, v) => k.isEmpty || v.isEmpty);
      if (mounted && m.isNotEmpty) setState(() => _nomsModes = m);
    } catch (_) {}
  }

  Future<void> _charger() async {
    final n = ++_demande;
    if (mounted) setState(() => _chargement = true);
    try {
      final list = await _j.lire(_filtre);
      final tous = _utilisateur == null ? list : await _j.lire(JournalFiltre(du: _filtre.du, au: _filtre.au));
      if (!mounted || n != _demande) return;
      setState(() {
        _entrees = list;
        _utilisateurs = ({for (final e in tous) e.utilisateur}..remove('')).toList()..sort();
        _erreur = null;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted || n != _demande) return;
      setState(() {
        _erreur = '$e';
        _chargement = false;
      });
    }
  }

  Future<void> _choisirPeriode(PeriodeJournal p) async {
    if (p == PeriodeJournal.choisie) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: _aujourdhui.subtract(Duration(days: JournalTerminal.conservationJours)),
        lastDate: _aujourdhui,
        initialDateRange: _choisie ?? DateTimeRange(start: _aujourdhui, end: _aujourdhui),
      );
      if (picked == null) return;
      _choisie = picked;
    }
    setState(() => _periode = p);
    _charger();
  }

  String get _officine {
    try {
      return Provider.of<AuthProvider>(context, listen: false).officine?.nomComplet ?? '';
    } catch (_) {
      return '';
    }
  }

  JournalTotaux get _totaux => calculerTotaux(_entrees, nomsModes: _nomsModes);

  Future<void> _pdf() async {
    final (du, au) = _bornes;
    final fichier = 'Journal_terminal_${DateFormat('yyyyMMdd_HHmm').format(_j.now)}.pdf';
    try {
      final bytes = await construirePdfJournal(
        entrees: _entrees,
        totaux: _totaux,
        officine: _officine,
        terminal: _j.terminal,
        utilisateur: _utilisateur ?? '',
        du: du,
        au: au,
        genereLe: _j.now,
      );
      final p = widget.partager;
      if (p != null) {
        await p(bytes, fichier);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: fichier);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF impossible : $e')));
    }
  }

  Future<void> _ticket() async {
    final (du, au) = _bornes;
    final t = _totaux;
    await imprimerRapport(context,
        titre: 'JOURNAL DU TERMINAL',
        lignes: (cols) => lignesTicketJournal(t, terminal: _j.terminal, utilisateur: _utilisateur ?? '', du: du, au: au, cols: cols));
  }

  static String _f(int v) => '${Constants.formatNumber(v)} F';

  ({Color fg, Color bg}) _couleur(ResultatJournal r) => switch (r) {
        ResultatJournal.ok => (fg: const Color(0xFF0B6B45), bg: const Color(0xFFDCF5E7)),
        ResultatJournal.refus => (fg: const Color(0xFFB91C1C), bg: const Color(0xFFFDECEC)),
        ResultatJournal.echecReseau => (fg: const Color(0xFF8A5300), bg: const Color(0xFFFFF1D6)),
        ResultatJournal.dejaApplique => (fg: const Color(0xFF1F4F8F), bg: const Color(0xFFE3ECF7)),
        ResultatJournal.doublonBloque => (fg: const Color(0xFF7C2D12), bg: const Color(0xFFFFEDD5)),
        ResultatJournal.info => (fg: const Color(0xFF3D4B60), bg: const Color(0xFFE6EBF2)),
      };

  Widget _filtres() {
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in PeriodeJournal.values)
            ChoiceChip(
              key: Key('periode_journal_${p.name}'),
              label: Text(p == PeriodeJournal.choisie && _choisie != null && _periode == p ? periodeLabel(_choisie!.start, _choisie!.end) : p.label),
              selected: _periode == p,
              onSelected: (_) => _choisirPeriode(p),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<TypeJournal?>(
              key: const Key('filtre_type_journal'),
              isExpanded: true,
              value: _type,
              decoration: const InputDecoration(labelText: 'Type', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tous')),
                for (final t in TypeJournal.values) DropdownMenuItem(value: t, child: Text(t.label, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (t) {
                setState(() => _type = t);
                _charger();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              key: const Key('filtre_utilisateur_journal'),
              isExpanded: true,
              value: _utilisateurs.contains(_utilisateur) ? _utilisateur : null,
              decoration: const InputDecoration(labelText: 'Utilisateur', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tous')),
                for (final u in _utilisateurs) DropdownMenuItem(value: u, child: Text(u, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (u) {
                setState(() => _utilisateur = u);
                _charger();
              },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
          key: const Key('recherche_journal'),
          controller: _recherche,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Référence (HL-0001, n° de vente, BL…)', isDense: true),
          onChanged: (_) => _charger(),
        ),
      ]),
    );
  }

  Widget _resume(JournalTotaux t) => SoftCard(
        key: const Key('resume_journal'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${t.entrees} action(s) · ${t.refus} refus · ${t.echecs} échec(s) réseau${t.doublons > 0 ? ' · ${t.doublons} doublon(s) bloqué(s)' : ''}',
              key: const Key('compteur_journal'), style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
          const SizedBox(height: 6),
          for (final m in t.parMode.entries)
            Row(children: [
              Expanded(child: Text(m.key, style: const TextStyle(fontSize: 13, color: Pal.muted))),
              Text(_f(m.value), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Pal.ink)),
            ]),
          Row(children: [
            const Expanded(child: Text('Total encaissé', style: TextStyle(fontWeight: FontWeight.bold, color: Pal.ink))),
            Text(_f(t.encaisse), key: const Key('total_encaisse_journal'), style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.ink)),
          ]),
          if (t.produits.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Quantités par produit (${t.produits.length})', style: const TextStyle(fontSize: 13.5, color: Pal.ink)),
                children: [
                  for (final p in t.produits)
                    Row(children: [
                      Expanded(child: Text(p.nom, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                      Text('vendu ${p.vendu} · stock ${p.stock}', style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
                    ]),
                ],
              ),
            ),
        ]),
      );

  Widget _ligne(JournalEntree e) {
    final c = _couleur(e.resultat);
    final refs = [if (e.refLocale.isNotEmpty) e.refLocale, if (e.refServeur.isNotEmpty) e.refServeur].join(' → ');
    final details = [
      if (e.montant != null) _f(e.montant!),
      if (e.produits.isNotEmpty) 'qté ${e.quantite}',
      if (e.utilisateur.isNotEmpty) e.utilisateur,
      e.source,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SoftCard(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(DateFormat('dd/MM HH:mm:ss').format(e.at), style: const TextStyle(fontSize: 12, color: Pal.muted)),
            const SizedBox(width: 8),
            Expanded(child: Text(e.type.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Pal.navy))),
            StatusBadge(e.resultat.label, fg: c.fg, bg: c.bg),
          ]),
          const SizedBox(height: 2),
          Text(e.action, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
          if (refs.isNotEmpty) Text(refs, style: const TextStyle(fontSize: 12.5, color: Pal.ink)),
          Text(details, style: const TextStyle(fontSize: 12, color: Pal.muted)),
          if (e.motif.isNotEmpty) Text(e.motif, style: TextStyle(fontSize: 12.5, color: c.fg)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _totaux;
    return Scaffold(
      backgroundColor: Pal.page,
      appBar: AppBar(
        title: const Text('Journal du terminal'),
        actions: [
          IconActionOccupee(
            key: const Key('journal_imprimer'),
            tooltip: 'Imprimer le ticket résumé',
            icon: Icons.print,
            onPressed: _chargement ? null : _ticket,
          ),
          IconActionOccupee(
            key: const Key('journal_pdf'),
            tooltip: 'Exporter en PDF',
            icon: Icons.picture_as_pdf_outlined,
            onPressed: _chargement ? null : _pdf,
          ),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(3), child: BarreChargement(visible: _chargement)),
      ),
      body: ListView.builder(
        key: const Key('liste_journal'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: _entrees.length + 3,
        itemBuilder: (context, i) {
          if (i == 0) return _filtres();
          if (i == 1) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Terminal : ${_j.terminal.isEmpty ? '—' : _j.terminal} · conservation ${JournalTerminal.conservationJours} jours',
                    style: const TextStyle(fontSize: 12, color: Pal.muted)),
                if (_erreur != null) Text(_erreur!, style: const TextStyle(color: Color(0xFFB91C1C))),
                const SizedBox(height: 6),
                _resume(t),
              ]),
            );
          }
          if (i == 2) {
            return !_chargement && _entrees.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: Text('Aucune action sur cette période.', key: Key('journal_vide'), style: TextStyle(color: Pal.muted))),
                  )
                : const SizedBox.shrink();
          }
          // Plus récentes d'abord.
          return _ligne(_entrees[_entrees.length - 1 - (i - 3)]);
        },
      ),
    );
  }
}

/// Ouvre le journal du terminal.
Future<void> ouvrirJournalTerminal(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JournalTerminalScreen()));
