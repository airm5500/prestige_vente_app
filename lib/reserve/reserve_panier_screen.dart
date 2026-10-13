// lib/reserve/reserve_panier_screen.dart
// Réappro manuel : panier de produits (recherche / scan de l'application), quantités contrôlées par le stock
// source, motif obligatoire, puis création de la suggestion et passage direct au traitement.
//
// Création NON idempotente côté serveur : une seule création par panier (bouton bloqué pendant l'envoi), les
// suggestions manuelles déjà en attente du même sens sont proposées à la reprise, et un délai dépassé après
// l'envoi n'est jamais renvoyé automatiquement (relecture des suggestions en attente d'abord).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/reserve/reserve_api.dart';
import 'package:prestige_vente_app/reserve/reserve_models.dart';
import 'package:prestige_vente_app/reserve/reserve_regles.dart';
import 'package:prestige_vente_app/reserve/reserve_traitement_screen.dart';
import 'package:prestige_vente_app/reserve/reserve_widgets.dart';
import 'package:prestige_vente_app/serveur/choix_produit.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/serveur/erreur_vue.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

class ReservePanierScreen extends StatefulWidget {
  final SensReserve sens;
  final ReserveApi api;
  final ChoixProduit? choixProduit;
  final ScanCode? scanner;
  const ReservePanierScreen({super.key, required this.sens, required this.api, this.choixProduit, this.scanner});

  @override
  State<ReservePanierScreen> createState() => _ReservePanierScreenState();
}

class _ReservePanierScreenState extends State<ReservePanierScreen> {
  SensReserve get _sens => widget.sens;
  List<LignePanier> _panier = const [];
  List<MotifReserve>? _motifs;
  int? _motifId;
  final _commentaire = TextEditingController();
  List<EnteteSuggestion> _aReprendre = const [];
  Object? _erreurChargement;
  bool _chargement = true;
  bool _ajout = false;

  /// Envoi de la création en cours (anti double appui).
  bool _envoi = false;

  /// La dernière création a dépassé le délai après l'envoi : elle a peut-être abouti.
  bool _incertain = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _commentaire.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreurChargement = null;
    });
    Object? erreur;
    try {
      final m = await widget.api.motifs(_sens);
      if (!mounted) return;
      setState(() {
        _motifs = m;
        if (_motifId == null || !m.any((x) => x.id == _motifId)) _motifId = m.length == 1 ? m.first.id : null;
      });
    } catch (e) {
      erreur = e;
    }
    await _relireEnAttente(onErreur: (e) => erreur ??= e);
    if (!mounted) return;
    setState(() {
      _erreurChargement = erreur;
      _chargement = false;
    });
  }

  Future<void> _relireEnAttente({void Function(Object)? onErreur}) async {
    try {
      final l = await widget.api.enAttente();
      if (!mounted) return;
      setState(() => _aReprendre = suggestionsAReprendre(l, _sens, OrigineSuggestion.manuelle));
    } catch (e) {
      onErreur?.call(e);
    }
  }

  Future<void> _ouvrirSuggestion(String id) async {
    await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ReserveTraitementScreen(suggestionId: id, api: widget.api)));
  }

  // ------------------------------------------------------------------------------------------------- produits

  Future<void> _ajouterProduit({bool scan = false}) async {
    if (_ajout) return;
    String? code;
    if (scan) {
      code = await (widget.scanner ?? scannerCodeParDefaut)(context);
      if (!mounted || code == null || code.trim().isEmpty) return;
    }
    final ProductSearchResult? p = await (widget.choixProduit ?? choisirProduitParDefaut)(context, code: code);
    if (!mounted || p == null) return;
    setState(() => _ajout = true);
    ArticleReserve? a;
    try {
      a = await widget.api.articleDuProduit(familleId: p.lgFAMILLEID, cip: p.intCIP);
    } catch (e) {
      if (mounted) afficherErreur(context, e);
      return;
    } finally {
      if (mounted) setState(() => _ajout = false);
    }
    if (!mounted) return;
    if (a == null) {
      afficherErreur(context, RefusMetier('« ${p.strNAME} » n\'est pas suivi en réserve sur cet emplacement : il ne peut pas être ajouté.'));
      return;
    }
    await _saisirQuantite(a);
  }

  Future<void> _saisirQuantite(ArticleReserve a, {int? actuelle}) async {
    final q = await demanderQuantite(
      context,
      produit: a.nom,
      sens: _sens,
      disponible: a.disponible(_sens),
      initiale: actuelle ?? quantiteParDefaut(a, _sens),
      aide: a.qteSuggeree != null && a.qteSuggeree! > 0 ? 'Quantité proposée par Prestige : ${a.qteSuggeree}' : null,
    );
    if (!mounted || q == null) return;
    setState(() => _panier = ajouterAuPanier(_panier, a, q));
  }

  Future<void> _produitsProposes() async {
    setState(() => _ajout = true);
    PageArticles page;
    try {
      page = await widget.api.articlesProposes(_sens);
    } catch (e) {
      if (mounted) afficherErreur(context, e);
      return;
    } finally {
      if (mounted) setState(() => _ajout = false);
    }
    if (!mounted) return;
    final candidats = [
      for (final a in page.articles)
        if (quantiteParDefaut(a, _sens) != null) a,
    ];
    if (candidats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Prestige ne propose aucun produit « ${_sens.fleche} » pour l\'instant.')));
      return;
    }
    final choisis = await showModalBottomSheet<List<ArticleReserve>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ChoixProposes(sens: _sens, articles: candidats, total: page.total),
    );
    if (!mounted || choisis == null || choisis.isEmpty) return;
    setState(() {
      for (final a in choisis) {
        _panier = ajouterAuPanier(_panier, a, quantiteParDefaut(a, _sens)!);
      }
    });
  }

  // ------------------------------------------------------------------------------------------------- création

  Future<void> _creer() async {
    if (_envoi || _panier.isEmpty) return;
    final motif = _motifId;
    if (motif == null) {
      afficherErreur(context, const RefusMetier('Choisissez le motif du réappro (obligatoire).'));
      return;
    }
    if (_aReprendre.isNotEmpty || _incertain) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Créer une nouvelle suggestion ?'),
          content: Text(_incertain
              ? 'La création précédente a peut-être été enregistrée (le serveur n\'a pas répondu à temps). '
                  'Vérifiez la liste « Déjà en attente » avant de créer à nouveau.'
              : '${_aReprendre.length} suggestion(s) manuelle(s) « ${_sens.fleche} » attendent déjà d\'être traitées. '
                  'Reprendre l\'une d\'elles évite un doublon.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            ElevatedButton(style: navyButton, onPressed: () => Navigator.pop(ctx, true), child: const Text('Créer quand même')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _envoi = true);
    try {
      final r = await widget.api.creer(_sens, motif, _commentaire.text, _panier);
      if (!mounted) return;
      _panier = const []; // la suggestion existe : le panier ne doit plus pouvoir être recréé
      if (r.ignorees > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${r.ref} créée : ${r.lignes} produit(s) retenu(s), ${r.ignorees} ignoré(s) par Prestige (doublon ou rien à déplacer).')));
      }
      await _ouvrirSuggestion(r.id);
    } on ServeurInjoignable catch (e) {
      if (!mounted) return;
      setState(() => _incertain = _incertain || e.resultatIncertain);
      if (e.resultatIncertain) {
        await _relireEnAttente();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Résultat incertain'),
            content: const Text('Le serveur n\'a pas répondu à temps : la suggestion a peut-être été créée. '
                'Elle apparaît alors dans « Déjà en attente » : ouvrez-la plutôt que d\'en créer une autre.'),
            actions: [ElevatedButton(style: navyButton, onPressed: () => Navigator.pop(ctx), child: const Text('Compris'))],
          ),
        );
      } else {
        afficherErreur(context, e);
      }
    } catch (e) {
      if (mounted) afficherErreur(context, e);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<bool> _confirmerSortie() async {
    if (_panier.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abandonner le panier ?'),
        content: Text('${_panier.length} produit(s) préparé(s) ne seront pas enregistrés.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Rester')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Abandonner')),
        ],
      ),
    );
    return ok == true;
  }

  // ------------------------------------------------------------------------------------------------- affichage

  @override
  Widget build(BuildContext context) {
    final boites = _panier.fold<int>(0, (s, l) => s + l.quantite);
    final inset = Responsive.sideInset(context);
    return PopScope(
      canPop: _panier.isEmpty && !_envoi,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _envoi) return;
        final sortir = await _confirmerSortie();
        if (!sortir || !context.mounted) return;
        setState(() => _panier = const []);
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Pal.page,
        body: Column(children: [
          NavyHeader(title: _sens == SensReserve.versReserve ? 'Ranger en réserve' : 'Regarnir le rayon', subtitle: '${_sens.fleche} · ${_sens.nomPrestige} manuel'),
          if (_chargement || _ajout) const LinearProgressIndicator(minHeight: 2),
          if (_erreurChargement != null) BandeauErreur(erreur: _erreurChargement!, onReessayer: _charger),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16 + inset, 12, 16 + inset, 24),
              children: [
                BandeauSens(_sens),
                if (_aReprendre.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Déjà en attente (${_aReprendre.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.ink)),
                  const Text('Reprenez une suggestion existante plutôt que d\'en créer une nouvelle.', style: TextStyle(fontSize: 12.5, color: Pal.muted)),
                  const SizedBox(height: 8),
                  for (final s in _aReprendre.take(5))
                    Padding(padding: const EdgeInsets.only(bottom: 8), child: CarteSuggestion(entete: s, onTap: () => _ouvrirSuggestion(s.id))),
                ],
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    key: const ValueKey('reserve-rechercher'),
                    style: outlineButton,
                    onPressed: _ajout || _envoi ? null : () => _ajouterProduit(),
                    icon: const Icon(Icons.search),
                    label: const Text('Rechercher'),
                  ),
                  OutlinedButton.icon(
                    style: outlineButton,
                    onPressed: _ajout || _envoi ? null : () => _ajouterProduit(scan: true),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scanner'),
                  ),
                  OutlinedButton.icon(
                    style: outlineButton,
                    onPressed: _ajout || _envoi ? null : _produitsProposes,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Produits proposés'),
                  ),
                ]),
                const SizedBox(height: 14),
                if (_panier.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Panier vide : recherchez ou scannez les produits à déplacer.', textAlign: TextAlign.center, style: TextStyle(color: Pal.muted)),
                  )
                else
                  for (final l in _panier) _lignePanier(l),
                const SizedBox(height: 14),
                _motifEtCommentaire(),
              ],
            ),
          ),
          BottomBarWidth(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const ValueKey('reserve-creer'),
                    style: amberButton,
                    onPressed: _panier.isEmpty || _envoi || _motifId == null ? null : _creer,
                    icon: _envoi
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.playlist_add_check),
                    label: Text(_envoi
                        ? 'Création…'
                        : _panier.isEmpty
                            ? 'Créer la suggestion'
                            : 'Créer la suggestion (${_panier.length} produit(s), $boites boîte(s))'),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _lignePanier(LignePanier l) {
    final a = l.article;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.nom, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
              Text('CIP ${a.cip}${a.zone.isEmpty ? '' : ' · ${a.zone}'}', style: const TextStyle(fontSize: 12, color: Pal.muted)),
              const SizedBox(height: 4),
              StocksLigne(rayon: a.stockRayon, reserve: a.stockReserve, sens: _sens),
            ]),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _envoi ? null : () => _saisirQuantite(a, actuelle: l.quantite),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFFE3ECF7), borderRadius: BorderRadius.circular(10)),
              child: Text('${l.quantite}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.navy)),
            ),
          ),
          IconButton(
            tooltip: 'Retirer du panier',
            onPressed: _envoi ? null : () => setState(() => _panier = [for (final x in _panier) if (x.article.familleId != a.familleId) x]),
            icon: const Icon(Icons.delete_outline, color: Pal.muted),
          ),
        ]),
      ),
    );
  }

  Widget _motifEtCommentaire() {
    final motifs = _motifs;
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (motifs == null)
          const Text('Motifs non chargés.', style: TextStyle(color: Pal.muted))
        else if (motifs.isEmpty)
          const Text('Aucun motif n\'est paramétré dans Prestige pour ce sens : la création est impossible.', style: TextStyle(color: Colors.red))
        else
          DropdownButtonFormField<int>(
            key: const ValueKey('reserve-motif'),
            value: _motifId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Motif (obligatoire)'),
            items: [for (final m in motifs) DropdownMenuItem(value: m.id, child: Text(m.libelle, overflow: TextOverflow.ellipsis))],
            onChanged: _envoi ? null : (v) => setState(() => _motifId = v),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _commentaire,
          maxLength: 200,
          enabled: !_envoi,
          decoration: const InputDecoration(labelText: 'Commentaire (facultatif)'),
        ),
      ]),
    );
  }
}

/// Liste des produits proposés par Prestige : tous cochés, le préparateur décoche ceux qu'il ne veut pas.
class _ChoixProposes extends StatefulWidget {
  final SensReserve sens;
  final List<ArticleReserve> articles;
  final int total;
  const _ChoixProposes({required this.sens, required this.articles, required this.total});

  @override
  State<_ChoixProposes> createState() => _ChoixProposesState();
}

class _ChoixProposesState extends State<_ChoixProposes> {
  late final Set<String> _coches = {for (final a in widget.articles) a.familleId};

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(children: [
          ListTile(
            title: Text('Produits proposés (${widget.articles.length}${widget.total > widget.articles.length ? ' sur ${widget.total}' : ''})'),
            subtitle: Text('${widget.sens.fleche} · quantité proposée par Prestige, bornée au stock ${widget.sens.source}'),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(children: [
              for (final a in widget.articles)
                CheckboxListTile(
                  value: _coches.contains(a.familleId),
                  onChanged: (v) => setState(() => v == true ? _coches.add(a.familleId) : _coches.remove(a.familleId)),
                  title: Text(a.nom, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('Rayon ${a.stockRayon} · Réserve ${a.stockReserve} · proposé ${quantiteParDefaut(a, widget.sens)}'),
                ),
            ]),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: navyButton,
                  onPressed: _coches.isEmpty ? null : () => Navigator.pop(context, [for (final a in widget.articles) if (_coches.contains(a.familleId)) a]),
                  child: Text('Ajouter ${_coches.length} produit(s)'),
                ),
              ),
            ),
          ),
        ]),
      );
}
