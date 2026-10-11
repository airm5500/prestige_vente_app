// lib/rh/presences_screen.dart
// « Présences du jour » (responsable, droit P_SM_RH) : GET v1/rh/presence?jour= — employés attendus ou
// pointés, entrée / sortie, retard, présence, anomalies (en clair) ; jour précédent / suivant.
// En ligne uniquement (calcul fait par Prestige). Téléphone : cartes ; tablette : deux colonnes.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

class PresencesScreen extends StatefulWidget {
  final PointageRh rh;
  final ListPresentation? presentation;
  final DateTime? jour;
  const PresencesScreen({super.key, required this.rh, this.presentation, this.jour});

  @override
  State<PresencesScreen> createState() => _PresencesScreenState();
}

class _PresencesScreenState extends State<PresencesScreen> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  late DateTime _jour = widget.jour ?? widget.rh.now;
  List<PresenceRh> _lignes = [];
  String? _erreur;
  bool _charge = false;
  bool _anomaliesSeules = false;

  @override
  void initState() {
    super.initState();
    loadPresentation();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _charge = false);
    final r = await widget.rh.presence(_jour);
    if (!mounted) return;
    setState(() {
      _lignes = [...r.presences]..sort((a, b) => a.employe.compareTo(b.employe));
      _erreur = r.erreur;
      _charge = true;
    });
  }

  void _decaler(int j) {
    _jour = DateTime(_jour.year, _jour.month, _jour.day + j);
    _charger();
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  @override
  Widget build(BuildContext context) {
    final presents = _lignes.where((l) => l.present).length;
    final retards = _lignes.where((l) => l.enRetard).length;
    final anomalies = _lignes.where((l) => l.anomalies.isNotEmpty).length;
    final absents = _lignes.where((l) => l.absent).length;
    final visibles = _anomaliesSeules ? _lignes.where((l) => l.anomalies.isNotEmpty || l.enRetard).toList() : _lignes;
    final cartes = [for (final l in visibles) _carte(l)];
    return PresentationScaffold(
      style: style,
      wide: true,
      title: 'Présences du jour',
      subtitle: DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(_jour),
      actions: (col) => [
        IconButton(tooltip: 'Actualiser', onPressed: _charger, icon: Icon(Icons.refresh, color: col)),
        PresentationMenuButton(value: style, onChanged: _setStyle, color: col),
      ],
      header: [
        if (style == ListPresentation.dashboard)
          Row(children: [
            Expanded(child: KpiTile('$presents', 'présent(s)')),
            const SizedBox(width: 6),
            Expanded(child: KpiTile('$retards', 'retard(s)')),
            const SizedBox(width: 6),
            Expanded(child: KpiTile('$anomalies', 'anomalie(s)', highlight: anomalies > 0)),
          ]),
      ],
      compactHeader: [
        LightFigures([
          ('$presents', 'Présents', Colors.green.shade700),
          ('$retards', 'Retards', const Color(0xFFB45309)),
          ('$absents', 'Absents', const Color(0xFFB91C1C)),
          ('$anomalies', 'Anomalies', Pal.navy),
        ]),
      ],
      body: ListView(
        key: const Key('rh_presences_liste'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Row(children: [
            IconButton(tooltip: 'Jour précédent', onPressed: () => _decaler(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text(DateFormat('dd/MM/yyyy').format(_jour),
                  key: const Key('rh_presences_jour'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.ink)),
            ),
            IconButton(tooltip: 'Jour suivant', onPressed: () => _decaler(1), icon: const Icon(Icons.chevron_right)),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Retards et anomalies seulement'),
            value: _anomaliesSeules,
            onChanged: (v) => setState(() => _anomaliesSeules = v),
          ),
          if (!_charge) const LinearProgressIndicator(),
          if (_erreur != null) Padding(padding: const EdgeInsets.all(12), child: Text(_erreur!, style: const TextStyle(color: Color(0xFFB91C1C)))),
          if (_charge && _erreur == null && visibles.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucun employé attendu ni pointé ce jour-là.'))),
          ...cardColumn(cartes, Responsive.isCompact(context) ? 1 : 2, spacing: 8),
        ],
      ),
    );
  }

  Widget _carte(PresenceRh l) {
    final probleme = l.anomalies.isNotEmpty;
    return SoftCard(
      key: Key('rh_presence_${l.employeId}'),
      band: probleme ? const Color(0xFFDC2626) : (l.enRetard ? const Color(0xFFF59E0B) : null),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(l.employe, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink))),
          if (l.matricule.isNotEmpty) Text(l.matricule, style: const TextStyle(fontSize: 12, color: Pal.muted)),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _info(Icons.login, 'Entrée', l.entree.isEmpty ? '—' : l.entree),
          _info(Icons.logout, 'Sortie', l.sortie.isEmpty ? '—' : l.sortie),
          if (l.prevu.isNotEmpty) _info(Icons.event, 'Prévu', l.prevu),
          if (l.minutesPresence > 0) _info(Icons.timer_outlined, 'Présence', dureeLisible(l.minutesPresence)),
        ]),
        if (l.enRetard || l.departAnticipe > 0 || l.heuresSup > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              [
                if (l.enRetard) 'Retard ${dureeLisible(l.retard)}',
                if (l.departAnticipe > 0) 'Départ anticipé ${dureeLisible(l.departAnticipe)}',
                if (l.heuresSup > 0) 'Heures sup. ${dureeLisible(l.heuresSup)}',
              ].join(' · '),
              style: const TextStyle(fontSize: 13, color: Color(0xFFB45309), fontWeight: FontWeight.w600),
            ),
          ),
        if (l.absence.isNotEmpty) Text('Absence : ${l.absence.toLowerCase()}', style: const TextStyle(fontSize: 13, color: Pal.muted)),
        if (probleme)
          Text('Anomalie : ${l.anomaliesLisibles.join(', ')}', style: const TextStyle(fontSize: 13, color: Color(0xFFB91C1C), fontWeight: FontWeight.w600)),
        if (l.pointages.isNotEmpty) Text(l.pointages, style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
      ]),
    );
  }

  Widget _info(IconData i, String t, String v) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 16, color: Pal.muted),
        const SizedBox(width: 4),
        Text('$t : ', style: const TextStyle(fontSize: 13, color: Pal.muted)),
        Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Pal.ink)),
      ]);
}
