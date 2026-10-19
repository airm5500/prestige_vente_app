// lib/fiche_client/fiche_client_tab.dart
// Onglet « Fiche client » : recherche d'un client (nom ou téléphone), identité (lecture seule), terrains et
// allergies, paramètres suivis (tension, poids, glycémie…) avec leur historique, consommation sur 12 mois.
// Saisie (allergies / terrains, nouvelle mesure) seulement si [modifier] (P_ORDONNANCE_CLIENT_MAJ).
// Données de santé : en mémoire seulement (jamais journalisées ni écrites sur le disque).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/fiche_client/fiche_client_api.dart';
import 'package:prestige_vente_app/fiche_client/fiche_client_models.dart';
import 'package:prestige_vente_app/fiche_client/fiche_client_validation.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/serveur/erreur_vue.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

class FicheClientTab extends StatefulWidget {
  final FicheClientApi api;
  final bool modifier;
  const FicheClientTab({super.key, required this.api, required this.modifier});

  @override
  State<FicheClientTab> createState() => _FicheClientTabState();
}

class _FicheClientTabState extends State<FicheClientTab> {
  FicheClientApi get _api => widget.api;

  // Recherche
  final _recherche = TextEditingController();
  final _focusRecherche = FocusNode(debugLabel: 'fiche-recherche');
  Timer? _attente;
  List<ClientResume>? _resultats;
  Object? _erreurRecherche;
  bool _cherche = false;
  int _numeroRecherche = 0;

  // Dossier
  ClientResume? _client;
  DossierClient? _dossier;
  Object? _erreurDossier;
  bool _chargeDossier = false;
  List<TerrainClinique>? _terrains;
  List<ParametreClinique>? _parametres;
  Object? _erreurReferentiels;

  // Consommation (à la demande)
  List<LigneConsommation>? _conso;
  Object? _erreurConso;
  bool _chargeConso = false;

  @override
  void dispose() {
    _attente?.cancel();
    _recherche.dispose();
    _focusRecherche.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------------------------------------- recherche

  void _saisie(String _) {
    _attente?.cancel();
    _attente = Timer(const Duration(milliseconds: 400), _chercher);
  }

  Future<void> _chercher() async {
    final q = _recherche.text.trim();
    final n = ++_numeroRecherche;
    if (q.length < 2) {
      setState(() {
        _resultats = null;
        _erreurRecherche = null;
        _cherche = false;
      });
      return;
    }
    setState(() {
      _cherche = true;
      _erreurRecherche = null;
    });
    try {
      final r = await _api.clients(q);
      if (!mounted || n != _numeroRecherche) return;
      setState(() {
        _resultats = r;
        _cherche = false;
      });
    } catch (e) {
      if (!mounted || n != _numeroRecherche) return;
      setState(() {
        _erreurRecherche = e;
        _cherche = false;
      });
    }
  }

  void _choisir(ClientResume c) {
    FocusScope.of(context).unfocus();
    setState(() {
      _client = c;
      _dossier = null;
      _conso = null;
      _erreurConso = null;
    });
    _chargerDossier();
    if (_terrains == null || _parametres == null) _chargerReferentiels();
  }

  /// Retour à la recherche : curseur dans le champ, texte précédent présélectionné (une frappe le remplace).
  void _changerClient() {
    setState(() {
      _client = null;
      _dossier = null;
      _erreurDossier = null;
      _conso = null;
      _erreurConso = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _client != null) return;
      _focusRecherche.requestFocus();
      _recherche.selection = TextSelection(baseOffset: 0, extentOffset: _recherche.text.length);
    });
  }

  // ------------------------------------------------------------------------------------------------- dossier

  Future<void> _chargerDossier() async {
    final c = _client;
    if (c == null) return;
    setState(() {
      _chargeDossier = true;
      _erreurDossier = null;
    });
    try {
      final d = await _api.dossier(c.id);
      if (!mounted || _client?.id != c.id) return;
      setState(() {
        _dossier = d;
        _chargeDossier = false;
      });
    } catch (e) {
      if (!mounted || _client?.id != c.id) return;
      setState(() {
        _erreurDossier = e;
        _chargeDossier = false;
      });
    }
  }

  Future<void> _chargerReferentiels() async {
    setState(() => _erreurReferentiels = null);
    try {
      final t = await _api.terrains();
      final p = await _api.parametres();
      if (!mounted) return;
      setState(() {
        _terrains = t;
        _parametres = p;
      });
    } catch (e) {
      if (mounted) setState(() => _erreurReferentiels = e);
    }
  }

  Future<void> _chargerConso() async {
    final c = _client;
    if (c == null || _chargeConso) return;
    setState(() {
      _chargeConso = true;
      _erreurConso = null;
    });
    try {
      final l = await _api.consommation(c.id);
      if (!mounted || _client?.id != c.id) return;
      setState(() {
        _conso = l;
        _chargeConso = false;
      });
    } catch (e) {
      if (!mounted || _client?.id != c.id) return;
      setState(() {
        _erreurConso = e;
        _chargeConso = false;
      });
    }
  }

  Future<void> _modifierDossier() async {
    final d = _dossier, c = _client, terrains = _terrains;
    if (!widget.modifier || d == null || c == null) return;
    if (terrains == null) {
      afficherErreur(context, _erreurReferentiels ?? const RefusMetier('Référentiel des terrains non chargé : réessayez.'));
      _chargerReferentiels();
      return;
    }
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditionDossier(api: _api, clientId: c.id, dossier: d, terrains: terrains),
    );
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    _chargerDossier();
  }

  Future<void> _ajouterMesure({ParametreClinique? parametre}) async {
    final c = _client, parametres = _parametres;
    if (!widget.modifier || c == null) return;
    if (parametres == null || parametres.isEmpty) {
      afficherErreur(context, _erreurReferentiels ?? const RefusMetier('Paramètres non chargés : réessayez.'));
      _chargerReferentiels();
      return;
    }
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SaisieMesureSheet(api: _api, clientId: c.id, parametres: parametres, initial: parametre),
    );
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    _chargerDossier();
  }

  Future<void> _historique(ParametreSuivi p) async {
    final c = _client;
    if (c == null) return;
    final ref = _parametres?.where((x) => x.id == p.parametreId).firstOrNull;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _HistoriqueMesures(
        api: _api,
        clientId: c.id,
        parametre: p,
        onAjouter: widget.modifier && ref != null
            ? () {
                Navigator.pop(context);
                _ajouterMesure(parametre: ref);
              }
            : null,
      ),
    );
  }

  // ------------------------------------------------------------------------------------------------- affichage

  @override
  Widget build(BuildContext context) => _client == null ? _vueRecherche() : _vueDossier();

  Widget _vueRecherche() {
    final r = _resultats;
    final inset = Responsive.sideInset(context);
    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(16 + inset, 14, 16 + inset, 8),
        child: TextField(
          key: const ValueKey('fiche-recherche'),
          controller: _recherche,
          focusNode: _focusRecherche,
          autofocus: true, // curseur prêt dès l'ouverture (4.4.0)
          onChanged: _saisie,
          onSubmitted: (_) => _chercher(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.person_search),
            hintText: 'Nom ou téléphone du client',
            suffixIcon: _cherche ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))) : null,
          ),
        ),
      ),
      if (_erreurRecherche != null) BandeauErreur(erreur: _erreurRecherche!, onReessayer: _chercher),
      Expanded(
        child: r == null
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Saisissez au moins 2 caractères du nom ou du téléphone.', textAlign: TextAlign.center, style: TextStyle(color: Pal.muted)),
              )
            : r.isEmpty
                ? const Padding(padding: EdgeInsets.all(24), child: Text('Aucun client trouvé.', textAlign: TextAlign.center, style: TextStyle(color: Pal.muted)))
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(16 + inset, 4, 16 + inset, 24),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: r.length + 1,
                    separatorBuilder: (_, i) => i == 0 ? const SizedBox(height: 2) : const SizedBox(height: 8),
                    itemBuilder: (_, i) => i == 0
                        ? Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 2),
                            child: Text(r.length == 1 ? '1 client trouvé' : '${r.length} clients trouvés',
                                key: const ValueKey('fiche-nb-resultats'), style: const TextStyle(color: Pal.muted, fontSize: 12)),
                          )
                        : LigneResultatClient(client: r[i - 1], onTap: () => _choisir(r[i - 1])),
                  ),
      ),
    ]);
  }

  Widget _vueDossier() {
    final d = _dossier;
    final c = _client!;
    final inset = Responsive.sideInset(context, wide: true);
    if (d == null && _erreurDossier != null) {
      return Column(children: [
        _barreClient(c.nomComplet),
        Expanded(child: ErreurVue(erreur: _erreurDossier!, onReessayer: _chargerDossier)),
      ]);
    }
    if (d == null) {
      return Column(children: [_barreClient(c.nomComplet), const Expanded(child: Center(child: CircularProgressIndicator()))]);
    }
    final deux = Responsive.columns(context, medium: 2, expanded: 2) > 1;
    final gauche = [_carteIdentite(d), const SizedBox(height: 12), _carteTerrains(d)];
    final droite = [_carteParametres(d), const SizedBox(height: 12), _carteConso()];
    return Column(children: [
      _barreClient(d.client.nomComplet.isEmpty ? c.nomComplet : d.client.nomComplet),
      if (_chargeDossier) const LinearProgressIndicator(minHeight: 2),
      if (_erreurDossier != null) BandeauErreur(erreur: _erreurDossier!, onReessayer: _chargerDossier),
      if (_erreurReferentiels != null) BandeauErreur(erreur: _erreurReferentiels!, onReessayer: _chargerReferentiels),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _chargerDossier,
          child: ListView(
            padding: EdgeInsets.fromLTRB(16 + inset, 8, 16 + inset, 24),
            children: deux
                ? [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: gauche)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: droite)),
                    ]),
                  ]
                : [...gauche, const SizedBox(height: 12), ...droite],
          ),
        ),
      ),
    ]);
  }

  Widget _barreClient(String nom) => Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(16 + Responsive.sideInset(context, wide: true), 6, 8 + Responsive.sideInset(context, wide: true), 6),
        child: Row(children: [
          const Icon(Icons.person, color: Pal.navy),
          const SizedBox(width: 8),
          Expanded(child: Text(nom.isEmpty ? 'Client' : nom, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.ink))),
          TextButton.icon(key: const ValueKey('fiche-changer'), onPressed: _changerClient, icon: const Icon(Icons.swap_horiz), label: const Text('Changer')),
        ]),
      );

  Widget _titre(String t, {Widget? action}) => Row(children: [
        Expanded(child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Pal.ink))),
        if (action != null) action,
      ]);

  Widget _carteIdentite(DossierClient d) {
    final i = d.client;
    Widget ligne(String l, String v) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 110, child: Text(l, style: const TextStyle(color: Pal.muted, fontSize: 13))),
            Expanded(child: Text(v.isEmpty ? '—' : v, style: const TextStyle(fontSize: 13))),
          ]),
        );
    final sexe = switch (i.sexe.toUpperCase()) { 'F' => 'Femme', 'M' || 'H' => 'Homme', _ => i.sexe };
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _titre('Identité', action: const Tooltip(message: 'Lecture seule depuis ce menu', child: Icon(Icons.lock_outline, size: 18, color: Pal.muted))),
        ligne('Nom', i.nom),
        ligne('Prénoms', i.prenoms),
        ligne('Téléphone', i.telephone),
        ligne('Naissance', [i.naissance, if (i.age != null) '${i.age} ans'].where((x) => x.isNotEmpty).join(' · ')),
        ligne('Sexe', sexe),
        ligne('Type', i.type),
        ligne('Ordonnances', '${d.nbOrdonnances}'),
      ]),
    );
  }

  Widget _carteTerrains(DossierClient d) {
    final ref = {for (final t in _terrains ?? const <TerrainClinique>[]) t.id: t};
    final choisis = [for (final id in d.terrains) ref[id]];
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _titre('Terrains et allergies',
            action: widget.modifier
                ? TextButton.icon(key: const ValueKey('fiche-modifier-dossier'), onPressed: _modifierDossier, icon: const Icon(Icons.edit, size: 18), label: const Text('Modifier'))
                : null),
        const SizedBox(height: 6),
        if (d.terrains.isEmpty)
          const Text('Aucun terrain renseigné.', style: TextStyle(color: Pal.muted, fontSize: 13))
        else
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in choisis)
              StatusBadge(t?.libelle ?? (_terrains == null ? '…' : 'Terrain inconnu'),
                  fg: t?.allergie == true ? const Color(0xFF9B1C1C) : const Color(0xFF1F4F8F),
                  bg: t?.allergie == true ? const Color(0xFFFDECEC) : const Color(0xFFE3ECF7)),
          ]),
        const SizedBox(height: 10),
        const Text('Allergies (texte libre)', style: TextStyle(color: Pal.muted, fontSize: 12)),
        Text(d.allergies.isEmpty ? 'Aucune allergie renseignée.' : d.allergies, style: TextStyle(fontSize: 13, color: d.allergies.isEmpty ? Pal.muted : Pal.ink)),
      ]),
    );
  }

  Color _couleurEtat(String etat) => switch (etat.toLowerCase()) {
        'haut' => const Color(0xFFB91C1C),
        'bas' => const Color(0xFFB45309),
        'normal' => Pal.green,
        _ => Pal.muted,
      };

  Widget _carteParametres(DossierClient d) => SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _titre('Paramètres suivis',
              action: widget.modifier
                  ? TextButton.icon(key: const ValueKey('fiche-ajouter-mesure'), onPressed: () => _ajouterMesure(), icon: const Icon(Icons.add, size: 18), label: const Text('Mesure'))
                  : null),
          if (d.imc != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('IMC ${formaterValeur(d.imc!.valeur, 1)}${d.imc!.analyse.isEmpty ? '' : ' · ${d.imc!.analyse}'}',
                  style: TextStyle(color: _couleurEtat(d.imc!.etat), fontWeight: FontWeight.w600)),
            ),
          if (d.parametres.isEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Aucun paramètre suivi.', style: TextStyle(color: Pal.muted))),
          for (final p in d.parametres)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(p.libelle),
              subtitle: Text([
                if (p.date.isNotEmpty) p.date,
                if (p.analyse.isNotEmpty) p.analyse,
                if (p.nbMesures > 1) '${p.nbMesures} mesures',
              ].join(' · ')),
              trailing: Text(formaterParametre(p), style: TextStyle(fontWeight: FontWeight.w700, color: p.mesure ? _couleurEtat(p.etat) : Pal.muted)),
              onTap: () => _historique(p),
            ),
        ]),
      );

  Widget _carteConso() {
    final l = _conso;
    final visibles = l == null ? const <LigneConsommation>[] : l.take(50).toList();
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _titre('Consommation (12 mois)'),
        const SizedBox(height: 6),
        if (l == null && !_chargeConso && _erreurConso == null)
          OutlinedButton.icon(
              key: const ValueKey('fiche-conso'), style: outlineButton, onPressed: _chargerConso, icon: const Icon(Icons.history), label: const Text('Afficher la consommation')),
        if (_chargeConso) const LinearProgressIndicator(minHeight: 2),
        if (_erreurConso != null) BandeauErreur(erreur: _erreurConso!, onReessayer: _chargerConso),
        if (l != null && l.isEmpty) const Text('Aucun achat sur la période.', style: TextStyle(color: Pal.muted)),
        if (l != null && l.isNotEmpty) ...[
          ResumeConsommation(lignes: l),
          const SizedBox(height: 10),
          for (var i = 0; i < visibles.length; i++) ...[
            if (i > 0) const Divider(height: 14),
            LigneConsommationVue(key: ValueKey('fiche-conso-ligne-$i'), ligne: visibles[i]),
          ],
          if (l.length > 50)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('… et ${l.length - 50} autre(s) produit(s).', style: const TextStyle(color: Pal.muted, fontSize: 12)),
            ),
        ],
      ]),
    );
  }
}

// ------------------------------------------------------------------------------------------- présentation (4.4.0)

const _chiffres = [FontFeature.tabularFigures()];

/// Une ligne de résultat de la recherche : initiales, nom, téléphone, puis type, âge et sexe en pastilles.
class LigneResultatClient extends StatelessWidget {
  final ClientResume client;
  final VoidCallback onTap;
  final DateTime? maintenant; // pour les tests (âge stable)
  const LigneResultatClient({super.key, required this.client, required this.onTap, this.maintenant});

  @override
  Widget build(BuildContext context) {
    final c = client;
    final age = ageClient(c.naissance, maintenant ?? DateTime.now());
    final sexe = sexeLisible(c.sexe);
    final femme = sexe == 'Femme';
    final pastilles = [
      if (c.type.isNotEmpty) _Pastille(c.type, fg: const Color(0xFF1F4F8F), bg: const Color(0xFFE3ECF7)),
      if (age != null) _Pastille('$age ans', fg: Pal.ink, bg: const Color(0xFFF1F3F6)),
      if (sexe.isNotEmpty) _Pastille(sexe, fg: Pal.ink, bg: const Color(0xFFF1F3F6)),
    ];
    return Material(
      key: ValueKey('fiche-client-${c.id}'),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE3E8EF))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: femme ? const Color(0xFFFCE7F0) : const Color(0xFFE3ECF7),
              child: Text(initialesClient(c), style: TextStyle(fontWeight: FontWeight.w700, color: femme ? const Color(0xFF9D174D) : Pal.navy)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.nomComplet.isEmpty ? 'Client sans nom' : c.nomComplet,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Pal.ink)),
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.phone_outlined, size: 14, color: Pal.muted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(c.telephone.isEmpty ? 'Pas de téléphone' : c.telephone,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Pal.muted, fontSize: 13, fontFeatures: _chiffres)),
                  ),
                ]),
                if (pastilles.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: pastilles),
                ],
              ]),
            ),
            const Icon(Icons.chevron_right, color: Pal.muted),
          ]),
        ),
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  final String texte;
  final Color fg, bg;
  const _Pastille(this.texte, {required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(texte, style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600)),
      );
}

/// Bandeau de synthèse : produits, achats, boîtes et montant total de la période.
class ResumeConsommation extends StatelessWidget {
  final List<LigneConsommation> lignes;
  const ResumeConsommation({super.key, required this.lignes});

  @override
  Widget build(BuildContext context) {
    final r = resumeConsommation(lignes);
    Widget chiffre(String valeur, String libelle, {Key? key}) => Expanded(
          child: Column(children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(valeur, key: key, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Pal.navy, fontFeatures: _chiffres)),
            ),
            Text(libelle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Pal.muted)),
          ]),
        );
    return Container(
      key: const ValueKey('fiche-conso-resume'),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(color: const Color(0xFFF4F7FB), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        chiffre('${r.produits}', r.produits > 1 ? 'produits' : 'produit'),
        chiffre('${r.achats}', r.achats > 1 ? 'achats' : 'achat'),
        chiffre('${r.boites}', r.boites > 1 ? 'boîtes' : 'boîte'),
        chiffre('${Constants.formatNumber(r.montant)} F', 'montant total', key: const ValueKey('fiche-conso-total')),
      ]),
    );
  }
}

/// Une ligne de consommation : nom et montant alignés à droite, puis achats, rythme, dernier achat, habitude, stock.
class LigneConsommationVue extends StatelessWidget {
  final LigneConsommation ligne;
  const LigneConsommationVue({super.key, required this.ligne});

  static (Color, Color) couleursHabitude(String h) => switch (h.trim().toLowerCase()) {
        'mensuel' || 'bimensuel' => (const Color(0xFF166534), const Color(0xFFE7F6EC)),
        'dormant' => (const Color(0xFF9A3412), const Color(0xFFFDEEE3)),
        _ => (const Color(0xFF475569), const Color(0xFFF1F3F6)),
      };

  /// Icône + texte qui passe à la ligne au besoin (jamais de débordement, même texte ×1,3 sur 360 dp).
  static Widget _avecIcone(IconData icone, String texte, TextStyle style) => Text.rich(
        TextSpan(children: [
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: const EdgeInsets.only(right: 3), child: Icon(icone, size: 13, color: Pal.muted))),
          TextSpan(text: texte),
        ]),
        style: style,
      );

  @override
  Widget build(BuildContext context) {
    final x = ligne;
    final rythme = rythmeAchat(x);
    final (fg, bg) = couleursHabitude(x.habitude);
    const petit = TextStyle(fontSize: 12, color: Pal.muted, fontFeatures: _chiffres);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(x.nom, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Pal.ink))),
        const SizedBox(width: 8),
        Text('${Constants.formatNumber(x.montant)} F',
            textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Pal.ink, fontFeatures: _chiffres)),
      ]),
      const SizedBox(height: 4),
      Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('${x.nbAchats} achat${x.nbAchats > 1 ? 's' : ''} · ${x.qteTotale} boîte${x.qteTotale > 1 ? 's' : ''}', style: petit),
        if (rythme.isNotEmpty) _avecIcone(Icons.autorenew, rythme, petit),
        if (x.dernierAchat.isNotEmpty) _avecIcone(Icons.event_outlined, 'dernier le ${dateClientFr(x.dernierAchat)}', petit),
        if (x.habitude.isNotEmpty) _Pastille(x.habitude, fg: fg, bg: bg),
        if (x.stock != null)
          Text('Stock ${x.stock}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: x.stock! > 0 ? Pal.green : const Color(0xFFB91C1C))),
      ]),
    ]);
  }
}

// ------------------------------------------------------------------------------------------- édition du dossier

class _EditionDossier extends StatefulWidget {
  final FicheClientApi api;
  final String clientId;
  final DossierClient dossier;
  final List<TerrainClinique> terrains;
  const _EditionDossier({required this.api, required this.clientId, required this.dossier, required this.terrains});

  @override
  State<_EditionDossier> createState() => _EditionDossierState();
}

class _EditionDossierState extends State<_EditionDossier> {
  late final Set<String> _choisis = {...widget.dossier.terrains};
  late final _allergies = TextEditingController(text: widget.dossier.allergies);
  bool _envoi = false;
  String? _erreur;

  @override
  void dispose() {
    _allergies.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (_envoi) return;
    final e = validerAllergies(_allergies.text);
    if (e != null) {
      setState(() => _erreur = e);
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      // Terrains inconnus du référentiel (désactivés) conservés : le serveur remplace la liste entière.
      final m = await widget.api.enregistrerDossier(widget.clientId, allergies: _allergies.text, terrains: _choisis.toList());
      if (mounted) Navigator.of(context).pop(m);
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreur(e));
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget groupe(String titre, bool allergie) {
      final l = [for (final t in widget.terrains) if (t.allergie == allergie) t];
      if (l.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 10, bottom: 6), child: Text(titre, style: const TextStyle(fontWeight: FontWeight.w600))),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in l)
            FilterChip(
              label: Text(t.libelle),
              selected: _choisis.contains(t.id),
              onSelected: _envoi ? null : (v) => setState(() => v ? _choisis.add(t.id) : _choisis.remove(t.id)),
            ),
        ]),
      ]);
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(children: [
          const ListTile(title: Text('Terrains et allergies', style: TextStyle(fontWeight: FontWeight.bold))),
          const Divider(height: 1),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
              groupe('Terrains', false),
              groupe('Allergies', true),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('fiche-allergies'),
                controller: _allergies,
                enabled: !_envoi,
                minLines: 2,
                maxLines: 6,
                maxLength: maxAllergies,
                decoration: const InputDecoration(labelText: 'Autres allergies (texte libre)'),
              ),
              if (_erreur != null) Text(_erreur!, style: const TextStyle(color: Color(0xFFB91C1C))),
            ]),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(child: OutlinedButton(style: outlineButton, onPressed: _envoi ? null : () => Navigator.pop(context), child: const Text('Annuler'))),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    key: const ValueKey('fiche-enregistrer-dossier'),
                    style: navyButton,
                    onPressed: _envoi ? null : _enregistrer,
                    child: Text(_envoi ? 'Enregistrement…' : 'Enregistrer'),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------- saisie d'une mesure

class _SaisieMesureSheet extends StatefulWidget {
  final FicheClientApi api;
  final String clientId;
  final List<ParametreClinique> parametres;
  final ParametreClinique? initial;
  const _SaisieMesureSheet({required this.api, required this.clientId, required this.parametres, this.initial});

  @override
  State<_SaisieMesureSheet> createState() => _SaisieMesureSheetState();
}

class _SaisieMesureSheetState extends State<_SaisieMesureSheet> {
  late ParametreClinique _p = widget.initial ?? widget.parametres.first;
  DateTime _date = DateTime.now();
  final _valeur = TextEditingController();
  final _sysG = TextEditingController(), _diaG = TextEditingController(), _sysD = TextEditingController(), _diaD = TextEditingController();
  final _commentaire = TextEditingController();
  bool _envoi = false;
  List<String> _erreurs = const [];
  // 4.6.1 (demande 19) : clé X-Client-Ref de la saisie, gardée tant que la saisie envoyée est la même (un renvoi
  // après une réponse perdue ne crée pas de doublon sur un serveur à jour) ; saisie modifiée = nouvelle clé.
  String? _cle;
  String? _cleCorps;

  @override
  void dispose() {
    for (final c in [_valeur, _sysG, _diaG, _sysD, _diaD, _commentaire]) {
      c.dispose();
    }
    super.dispose();
  }

  SaisieMesure get _saisie => SaisieMesure(
        parametre: _p,
        date: _date,
        valeur: _valeur.text,
        systoliqueG: _sysG.text,
        diastoliqueG: _diaG.text,
        systoliqueD: _sysD.text,
        diastoliqueD: _diaD.text,
        commentaire: _commentaire.text,
      );

  Future<void> _choisirDate() async {
    final now = DateTime.now();
    final j = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(now.year - 5), lastDate: now);
    if (j == null || !mounted) return;
    final h = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    if (!mounted) return;
    setState(() => _date = DateTime(j.year, j.month, j.day, h?.hour ?? _date.hour, h?.minute ?? _date.minute));
  }

  Future<void> _enregistrer() async {
    if (_envoi) return;
    final s = _saisie;
    final e = s.erreurs();
    setState(() => _erreurs = e);
    if (e.isNotEmpty) return;
    setState(() => _envoi = true);
    try {
      final corps = jsonEncode(s.toJson());
      if (_cle == null || _cleCorps != corps) {
        _cle = FicheClientApi.nouvelleCle();
        _cleCorps = corps;
      }
      final m = await widget.api.ajouterMesure(widget.clientId, s, cle: _cle);
      if (mounted) Navigator.of(context).pop(m);
    } catch (err) {
      // Pas de nouvel envoi automatique : POST mesures n'est pas idempotent sur un serveur ancien (doublon possible).
      // Un refus du serveur ne garde pas la clé côté serveur : la garder ici est sans effet.
      if (mounted) {
        setState(() => _erreurs = [
              messageErreur(err),
              if (err is ServeurInjoignable && err.resultatIncertain)
                'La mesure a peut-être été enregistrée : vérifiez l\'historique du paramètre avant de la ressaisir.',
            ]);
      }
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Widget _champ(TextEditingController c, String label, {Key? key}) {
    final (min, max) = bornes(_p);
    return TextField(
      key: key,
      controller: c,
      enabled: !_envoi,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), LengthLimitingTextInputFormatter(7)],
      decoration: InputDecoration(
        labelText: label,
        suffixText: _p.unite.isEmpty ? null : _p.unite,
        helperText: min != null && max != null ? 'entre ${formaterValeur(min, _p.decimales)} et ${formaterValeur(max, _p.decimales)}' : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String deux(int v) => v.toString().padLeft(2, '0');
    final dateTexte = '${deux(_date.day)}/${deux(_date.month)}/${_date.year} ${deux(_date.hour)}:${deux(_date.minute)}';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(children: [
          const ListTile(title: Text('Nouvelle mesure', style: TextStyle(fontWeight: FontWeight.bold))),
          const Divider(height: 1),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('fiche-mesure-parametre'),
                value: _p.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Paramètre'),
                items: [for (final p in widget.parametres) DropdownMenuItem(value: p.id, child: Text(p.unite.isEmpty ? p.libelle : '${p.libelle} (${p.unite})'))],
                onChanged: _envoi
                    ? null
                    : (id) => setState(() {
                          _p = widget.parametres.firstWhere((p) => p.id == id, orElse: () => _p);
                          _erreurs = const [];
                        }),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text('Date de la mesure : $dateTexte'),
                trailing: TextButton(onPressed: _envoi ? null : _choisirDate, child: const Text('Changer')),
              ),
              const SizedBox(height: 8),
              if (_p.tension) ...[
                const Text('Bras gauche', style: TextStyle(fontWeight: FontWeight.w600)),
                Row(children: [
                  Expanded(child: _champ(_sysG, 'Systolique', key: const ValueKey('fiche-sys-g'))),
                  const SizedBox(width: 8),
                  Expanded(child: _champ(_diaG, 'Diastolique', key: const ValueKey('fiche-dia-g'))),
                ]),
                const SizedBox(height: 12),
                const Text('Bras droit (facultatif si le gauche est saisi)', style: TextStyle(fontWeight: FontWeight.w600)),
                Row(children: [
                  Expanded(child: _champ(_sysD, 'Systolique')),
                  const SizedBox(width: 8),
                  Expanded(child: _champ(_diaD, 'Diastolique')),
                ]),
              ] else
                _champ(_valeur, _p.libelle, key: const ValueKey('fiche-valeur')),
              const SizedBox(height: 12),
              TextField(
                controller: _commentaire,
                enabled: !_envoi,
                maxLength: maxCommentaireMesure,
                decoration: const InputDecoration(labelText: 'Commentaire (facultatif)'),
              ),
              for (final e in _erreurs)
                if (e.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(e, style: const TextStyle(color: Color(0xFFB91C1C)))),
            ]),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(child: OutlinedButton(style: outlineButton, onPressed: _envoi ? null : () => Navigator.pop(context), child: const Text('Annuler'))),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    key: const ValueKey('fiche-enregistrer-mesure'),
                    style: navyButton,
                    onPressed: _envoi ? null : _enregistrer,
                    child: Text(_envoi ? 'Enregistrement…' : 'Enregistrer'),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------- historique

class _HistoriqueMesures extends StatefulWidget {
  final FicheClientApi api;
  final String clientId;
  final ParametreSuivi parametre;
  final VoidCallback? onAjouter;
  const _HistoriqueMesures({required this.api, required this.clientId, required this.parametre, this.onAjouter});

  @override
  State<_HistoriqueMesures> createState() => _HistoriqueMesuresState();
}

class _HistoriqueMesuresState extends State<_HistoriqueMesures> {
  List<Mesure>? _mesures;
  Object? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _erreur = null);
    try {
      final l = await widget.api.mesures(widget.clientId, widget.parametre.parametreId);
      if (mounted) setState(() => _mesures = l.reversed.toList()); // la plus récente d'abord
    } catch (e) {
      if (mounted) setState(() => _erreur = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.parametre;
    final l = _mesures;
    String valeur(Mesure m) {
      final v = p.tension && m.valeur2 != null
          ? '${formaterValeur(m.valeur, p.decimales)}/${formaterValeur(m.valeur2, p.decimales)}'
          : formaterValeur(m.valeur, p.decimales);
      return p.unite.isEmpty ? v : '$v ${p.unite}';
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(children: [
        ListTile(
          title: Text(p.libelle, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: p.norme.isEmpty ? null : Text('Norme : ${p.norme}'),
          trailing: widget.onAjouter == null ? null : TextButton.icon(onPressed: widget.onAjouter, icon: const Icon(Icons.add), label: const Text('Mesure')),
        ),
        const Divider(height: 1),
        Expanded(
          child: l == null && _erreur != null
              ? ErreurVue(erreur: _erreur!, onReessayer: _charger)
              : l == null
                  ? const Center(child: CircularProgressIndicator())
                  : l.isEmpty
                      ? const Center(child: Text('Aucune mesure.', style: TextStyle(color: Pal.muted)))
                      : ListView.separated(
                          itemCount: l.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final m = l[i];
                            return ListTile(
                              dense: true,
                              title: Text(valeur(m), style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text([
                                m.date,
                                if (m.cote == 'G') 'bras gauche',
                                if (m.cote == 'D') 'bras droit',
                                if (m.analyse.isNotEmpty) m.analyse,
                                if (m.par.isNotEmpty) 'par ${m.par}',
                                if (m.commentaire.isNotEmpty) m.commentaire,
                              ].where((x) => x.isNotEmpty).join(' · ')),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
