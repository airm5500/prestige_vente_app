// lib/reserve/reserve_traitement_screen.dart
// Traitement d'une suggestion de réserve (manuelle ou automatique), comme la fenêtre web « Traitement de la
// suggestion » : ouverture (verrou de 20 min), quantités ligne par ligne (aucun stock ne bouge), puis « Traiter »
// après confirmation explicite (le stock est réellement déplacé), compte rendu des lignes déplacées / refusées,
// « Réessayer » des échecs, et libération du verrou en quittant l'écran.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/reserve/reserve_api.dart';
import 'package:prestige_vente_app/reserve/reserve_models.dart';
import 'package:prestige_vente_app/reserve/reserve_regles.dart';
import 'package:prestige_vente_app/reserve/reserve_widgets.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/serveur/erreur_vue.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

class ReserveTraitementScreen extends StatefulWidget {
  final String suggestionId;
  final ReserveApi api;
  const ReserveTraitementScreen({super.key, required this.suggestionId, required this.api});

  @override
  State<ReserveTraitementScreen> createState() => _ReserveTraitementScreenState();
}

class _ReserveTraitementScreenState extends State<ReserveTraitementScreen> {
  SuggestionOuverte? _s;
  CompteRendu? _compteRendu;
  Object? _erreur;
  bool _chargement = true;

  /// Écriture en cours (quantité, retrait, traitement) : les autres actions sont bloquées.
  bool _occupe = false;

  /// Fenêtre de confirmation ouverte (pas d'indicateur de chargement pendant ce temps).
  bool _confirmation = false;

  /// Le verrou a été obtenu au moins une fois : à libérer en quittant.
  bool _verrouPris = false;

  ReserveApi get _api => widget.api;

  @override
  void initState() {
    super.initState();
    _ouvrir();
  }

  @override
  void dispose() {
    if (_verrouPris) _api.liberer(widget.suggestionId);
    super.dispose();
  }

  Future<SuggestionOuverte?> _ouvrir() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final s = await _api.ouvrir(widget.suggestionId);
      if (!mounted) return s;
      setState(() {
        _s = s;
        _verrouPris = _verrouPris || s.modifiable;
        _chargement = false;
      });
      return s;
    } catch (e) {
      if (mounted) {
        setState(() {
          _erreur = e;
          _chargement = false;
        });
      }
      return null;
    }
  }

  /// Écriture refusée parce qu'un autre utilisateur a pris la suggestion : on repasse en consultation.
  Future<void> _apresErreurEcriture(Object e) async {
    if (!mounted) return;
    afficherErreur(context, e);
    if (e is RefusMetier && e.code == 'SUGGESTION_OCCUPEE') await _ouvrir();
  }

  SensReserve get _sens => _s?.entete.sens ?? SensReserve.versRayon;
  bool get _modifiable => _s?.modifiable == true && _compteRendu == null;

  Future<void> _changerQuantite(LigneSuggestion l) async {
    if (!_modifiable || !l.modifiable || _occupe) return;
    final q = await demanderQuantite(
      context,
      produit: l.nom,
      sens: _sens,
      disponible: l.disponible(_sens),
      initiale: l.qteATraiter > 0 ? l.qteATraiter : null,
      aide: l.formule,
    );
    if (q == null || !mounted || q == l.qteRetenue) return;
    setState(() => _occupe = true);
    try {
      final retenue = await _api.majQuantite(l.detailId, q);
      if (!mounted) return;
      final s = _s!;
      setState(() => _s = s.avecLignes([for (final x in s.lignes) x.detailId == l.detailId ? x.avecQuantite(retenue) : x]));
    } catch (e) {
      await _apresErreurEcriture(e);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _retirer(LigneSuggestion l) async {
    if (!_modifiable || !l.modifiable || _occupe) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer cette ligne ?'),
        content: Text('« ${l.nom} » ne sera pas déplacé. La ligne reste visible dans Prestige comme retirée.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(style: navyButton, onPressed: () => Navigator.pop(ctx, true), child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _occupe = true);
    try {
      await _api.retirerLigne(l.detailId);
      if (mounted) await _ouvrir();
    } catch (e) {
      await _apresErreurEcriture(e);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _traiter() async {
    if (_occupe) return;
    setState(() => _occupe = true);
    try {
      // Relecture juste avant : stocks actuels, verrou toujours détenu, lignes à jour.
      final s = await _ouvrir();
      if (!mounted || s == null) return;
      if (!s.modifiable) {
        afficherErreur(context, RefusMetier(s.motifLectureSeule.isEmpty ? 'Cette suggestion ne peut pas être traitée.' : s.motifLectureSeule));
        return;
      }
      final r = resumeTraitement(s.lignes);
      if (r.lignes == 0) {
        afficherErreur(context, const RefusMetier('Aucune ligne à déplacer (toutes retirées, traitées ou à 0).'));
        return;
      }
      final depassent = lignesAuDelaDuStock(s.lignes, _sens);
      setState(() => _confirmation = true);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Déplacer le stock ?'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SensBadge(_sens),
            const SizedBox(height: 10),
            Text('${r.boites} boîte(s) de ${r.lignes} produit(s) vont passer du stock ${_sens.source} au stock ${_sens.destination}.'),
            const SizedBox(height: 8),
            const Text('Le stock Prestige est modifié immédiatement. Préparez physiquement les boîtes.', style: TextStyle(fontWeight: FontWeight.w600)),
            if (depassent.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${depassent.length} ligne(s) dépassent le stock ${_sens.source} actuel : Prestige les refusera.',
                  style: const TextStyle(color: Color(0xFFB91C1C))),
            ],
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            ElevatedButton(key: const ValueKey('reserve-confirmer-traiter'), style: amberButton, onPressed: () => Navigator.pop(ctx, true), child: const Text('Oui, déplacer')),
          ],
        ),
      );
      if (mounted) setState(() => _confirmation = false);
      if (ok != true || !mounted) return;
      final cr = await _api.traiter(widget.suggestionId);
      if (mounted) setState(() => _compteRendu = cr);
    } catch (e) {
      if (!mounted) return;
      afficherErreur(context, e);
      // Le traitement a peut-être eu lieu (délai) : on relit l'état réel des lignes.
      if (e is ServeurInjoignable || e is ErreurHttp) await _ouvrir();
      if (e is RefusMetier && e.code == 'SUGGESTION_OCCUPEE') await _ouvrir();
    } finally {
      if (mounted) {
        setState(() {
          _occupe = false;
          _confirmation = false;
        });
      }
    }
  }

  Future<void> _reessayer() async {
    if (_occupe) return;
    setState(() => _occupe = true);
    try {
      final cr = await _api.reessayer(widget.suggestionId);
      if (mounted) setState(() => _compteRendu = cr);
    } catch (e) {
      if (mounted) afficherErreur(context, e);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  // ------------------------------------------------------------------------------------------------- affichage

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final e = s?.entete;
    final Widget corps;
    if (s == null && _erreur != null) {
      corps = ErreurVue(erreur: _erreur!, onReessayer: _ouvrir);
    } else if (s == null) {
      corps = const Center(child: CircularProgressIndicator());
    } else if (_compteRendu != null) {
      corps = _VueCompteRendu(compteRendu: _compteRendu!);
    } else {
      corps = _lignes(s);
    }
    return PopScope(
      canPop: !_occupe,
      child: Scaffold(
        backgroundColor: Pal.page,
        body: Column(children: [
          NavyHeader(
            title: e == null ? 'Suggestion' : (e.ref.isEmpty ? 'Suggestion' : e.ref),
            subtitle: e == null
                ? null
                : '${e.sens.fleche} · ${e.origine.libelle} · ${StatutSuggestion.libelle(_compteRendu?.entete.statut ?? e.statut)}',
            actions: [
              if (_compteRendu == null)
                IconButton(tooltip: 'Relire', onPressed: _chargement || _occupe ? null : _ouvrir, icon: const Icon(Icons.refresh, color: Colors.white)),
            ],
          ),
          if ((_chargement && s != null) || (_occupe && !_confirmation)) const LinearProgressIndicator(minHeight: 2),
          if (_erreur != null && s != null) BandeauErreur(erreur: _erreur!, onReessayer: _ouvrir),
          if (s != null && !s.modifiable && _compteRendu == null) _bandeauLecture(s),
          Expanded(child: corps),
          if (s != null) _pied(s),
        ]),
      ),
    );
  }

  Widget _bandeauLecture(SuggestionOuverte s) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(color: const Color(0xFFE3ECF7), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(s.occupeeParAutre ? Icons.lock_person : Icons.visibility, color: Pal.navy, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.motifLectureSeule.isNotEmpty
                  ? s.motifLectureSeule
                  : s.occupeeParAutre
                      ? '${s.verrouPar} traite cette suggestion depuis ${s.verrouDepuis} : consultation seulement.'
                      : 'Consultation seulement.',
              style: const TextStyle(color: Pal.navy, fontSize: 13),
            ),
          ),
          if (s.occupeeParAutre) TextButton(onPressed: _occupe ? null : _ouvrir, child: const Text('Réessayer')),
        ]),
      );

  Widget _lignes(SuggestionOuverte s) {
    final inset = Responsive.sideInset(context);
    final visibles = [for (final l in s.lignes) if (l.etat != EtatLigne.supprimee) l];
    final retirees = s.lignes.length - visibles.length;
    return RefreshIndicator(
      onRefresh: () async => _ouvrir(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16 + inset, 12, 16 + inset, 24),
        children: [
          BandeauSens(_sens),
          if (s.entete.motifLibelle.isNotEmpty || s.entete.commentaire.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text([s.entete.motifLibelle, s.entete.commentaire].where((x) => x.isNotEmpty).join(' · '),
                style: const TextStyle(color: Pal.muted, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          if (visibles.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('Aucune ligne.', textAlign: TextAlign.center, style: TextStyle(color: Pal.muted))),
          for (final l in visibles) _ligne(l),
          if (retirees > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('$retirees ligne(s) retirée(s) non affichée(s).', style: const TextStyle(color: Pal.muted, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _ligne(LigneSuggestion l) {
    final editable = _modifiable && l.modifiable && !_occupe;
    final depasse = l.traitable && l.qteATraiter > l.disponible(_sens);
    final (fg, bg) = switch (l.etat) {
      EtatLigne.traitee => (const Color(0xFF0B6B45), const Color(0xFFDCF5E7)),
      EtatLigne.echec => (const Color(0xFF9B1C1C), const Color(0xFFFDECEC)),
      EtatLigne.modifiee => (const Color(0xFF1F4F8F), const Color(0xFFE3ECF7)),
      _ => (const Color(0xFF3D4B60), const Color(0xFFE6EBF2)),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftCard(
        highlighted: false,
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.nom, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
              Text('CIP ${l.cip} · proposé ${l.qteProposee}', style: const TextStyle(fontSize: 12, color: Pal.muted)),
              const SizedBox(height: 4),
              StocksLigne(rayon: l.stockRayon, reserve: l.stockReserve, sens: _sens),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                StatusBadge(EtatLigne.libelle(l.etat), fg: fg, bg: bg),
                if (l.etat == EtatLigne.echec && (l.codeEchec.isNotEmpty || l.motifLigne.isNotEmpty))
                  Text(l.motifLigne.isNotEmpty ? l.motifLigne : libelleCodeEchec(l.codeEchec, _sens),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF9B1C1C))),
                if (depasse)
                  Text('Dépasse le stock ${_sens.source} actuel (${l.disponible(_sens)})', style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C))),
              ]),
            ]),
          ),
          Column(children: [
            InkWell(
              key: ValueKey('reserve-qte-${l.detailId}'),
              borderRadius: BorderRadius.circular(10),
              onTap: editable ? () => _changerQuantite(l) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: editable ? const Color(0xFFE3ECF7) : const Color(0xFFF2F4F8), borderRadius: BorderRadius.circular(10)),
                child: Column(children: [
                  Text('${l.etat == EtatLigne.traitee ? l.qteDeplacee : l.qteATraiter}',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: editable ? Pal.navy : Pal.muted)),
                  Text(l.etat == EtatLigne.traitee ? 'déplacé' : 'à déplacer', style: const TextStyle(fontSize: 10, color: Pal.muted)),
                ]),
              ),
            ),
          ]),
          if (editable)
            IconButton(tooltip: 'Retirer la ligne', onPressed: () => _retirer(l), icon: const Icon(Icons.remove_circle_outline, color: Pal.muted))
          else
            const SizedBox(width: 8),
        ]),
      ),
    );
  }

  Widget _pied(SuggestionOuverte s) {
    final cr = _compteRendu;
    final Widget bouton;
    if (cr != null) {
      bouton = Row(children: [
        if (cr.relancable) ...[
          Expanded(
            child: OutlinedButton.icon(
                style: outlineButton, onPressed: _occupe ? null : _reessayer, icon: const Icon(Icons.replay), label: const Text('Réessayer les échecs')),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(child: ElevatedButton(style: navyButton, onPressed: _occupe ? null : () => Navigator.of(context).maybePop(), child: const Text('Terminer'))),
      ]);
    } else if (!s.modifiable) {
      return const SizedBox.shrink();
    } else {
      final r = resumeTraitement(s.lignes);
      bouton = ElevatedButton.icon(
        key: const ValueKey('reserve-traiter'),
        style: amberButton,
        onPressed: _occupe || r.lignes == 0 ? null : _traiter,
        icon: const Icon(Icons.local_shipping_outlined),
        label: Text(r.lignes == 0 ? 'Rien à déplacer' : 'Traiter : ${r.lignes} ligne(s), ${r.boites} boîte(s)'),
      );
    }
    return BottomBarWidth(
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: SizedBox(height: 50, width: double.infinity, child: bouton)),
      ),
    );
  }
}

/// Compte rendu du traitement : lignes déplacées et lignes refusées avec la raison.
class _VueCompteRendu extends StatelessWidget {
  final CompteRendu compteRendu;
  const _VueCompteRendu({required this.compteRendu});

  @override
  Widget build(BuildContext context) {
    final c = compteRendu;
    final sens = c.entete.sens;
    final inset = Responsive.sideInset(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(16 + inset, 12, 16 + inset, 24),
      children: [
        SoftCard(
          band: c.totalEchoue > 0 ? const Color(0xFFB91C1C) : Pal.green,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.totalEchoue > 0 ? 'Traitement partiel' : 'Traitement terminé',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.ink)),
            const SizedBox(height: 4),
            Text(syntheseCompteRendu(c), style: const TextStyle(color: Pal.muted)),
            const SizedBox(height: 10),
            Wrap(spacing: 18, runSpacing: 8, children: [
              Figure('${c.totalReussi}', 'déplacée(s)'),
              Figure('${c.totalEchoue}', 'refusée(s)'),
              Figure('${c.boitesDeplacees}', 'boîte(s)'),
            ]),
          ]),
        ),
        if (c.traites.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Déplacées (${sens.fleche})', style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.ink)),
          const SizedBox(height: 6),
          for (final l in c.traites)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle, color: Pal.green),
              title: Text(l.nom, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Text('${l.qteDeplacee}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
        if (c.nonTraites.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Non déplacées', style: TextStyle(fontWeight: FontWeight.w700, color: Pal.ink)),
          const SizedBox(height: 6),
          for (final l in c.nonTraites)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(l.etat == EtatLigne.echec ? Icons.error : Icons.remove_circle_outline,
                  color: l.etat == EtatLigne.echec ? const Color(0xFFB91C1C) : Pal.muted),
              title: Text(l.nom, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(raisonNonTraitee(l, sens)),
              trailing: Text('${l.qteATraiter}'),
            ),
        ],
      ],
    );
  }
}
