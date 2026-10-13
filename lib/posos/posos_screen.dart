// lib/posos/posos_screen.dart
// Analyse posologie (Posos via Prestige) : depuis la vente en cours (le serveur relit les produits de la vente)
// ou depuis un choix de produits (menu « Analyse posologie »).
// - Alertes classées par gravité, couleurs distinctes, conduite à tenir et équivalents en rayon.
// - Mode démonstration (Posos non configuré) : bandeau permanent « Mode démonstration — résultats non réels ».
// - Jamais présenté comme un avis médical définitif (avertissement sous chaque résultat).
// - Aucune donnée du patient n'est conservée : tout reste en mémoire le temps de l'écran.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/posos/posos_api.dart';
import 'package:prestige_vente_app/posos/posos_models.dart';
import 'package:prestige_vente_app/serveur/choix_produit.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/serveur/client_contexte.dart';
import 'package:prestige_vente_app/serveur/erreur_vue.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

class PososScreen extends StatefulWidget {
  /// Vente en cours (identifiant Prestige) : analyse de la vente telle qu'enregistrée sur le serveur.
  final String? venteId;
  final String referenceVente;

  /// Produits affichés au départ (panier de la vente, ou présélection).
  final List<ProduitAnalyse> produitsInitiaux;
  final PososApi? api;
  final ChoixProduit? choixProduit;
  final ScanCode? scanner;

  const PososScreen({
    super.key,
    this.venteId,
    this.referenceVente = '',
    this.produitsInitiaux = const [],
    this.api,
    this.choixProduit,
    this.scanner,
  });

  @override
  State<PososScreen> createState() => _PososScreenState();
}

class _PososScreenState extends State<PososScreen> {
  late final PososApi _api = widget.api ?? PososApi(clientPrestige(context));
  late List<ProduitAnalyse> _produits = List.of(widget.produitsInitiaux);
  PososStatut? _statut;
  Object? _erreurStatut;
  ResultatPosos? _resultat;
  Object? _erreur;
  bool _analyse = false;

  final _age = TextEditingController();
  final _poids = TextEditingController();
  String _sexe = '';
  bool _grossesse = false, _allaitement = false, _ir = false, _ih = false;
  String? _erreurAge, _erreurPoids;

  bool get _depuisVente => (widget.venteId ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _lireStatut());
  }

  @override
  void dispose() {
    _age.dispose();
    _poids.dispose();
    super.dispose();
  }

  Future<void> _lireStatut() async {
    try {
      final s = await _api.statut();
      if (mounted) setState(() => _statut = s);
    } catch (e) {
      if (mounted) setState(() => _erreurStatut = e);
    }
  }

  ContextePatient _contexte() => ContextePatient(
        age: int.tryParse(_age.text.trim()),
        sexe: _sexe,
        grossesse: _sexe != 'M' && _grossesse,
        allaitement: _sexe != 'M' && _allaitement,
        insuffisanceRenale: _ir,
        insuffisanceHepatique: _ih,
        poids: int.tryParse(_poids.text.trim()),
      );

  Future<void> _analyser() async {
    if (_analyse) return;
    final ea = validerAge(_age.text), ep = validerPoids(_poids.text);
    setState(() {
      _erreurAge = ea;
      _erreurPoids = ep;
    });
    if (ea != null || ep != null) return;
    if (!_depuisVente && _produits.isEmpty) {
      afficherErreur(context, const RefusMetier('Ajoutez au moins un produit à analyser.'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _analyse = true;
      _erreur = null;
    });
    try {
      final r = _depuisVente ? await _api.analyserVente(widget.venteId!, _contexte()) : await _api.analyserProduits(_produits, _contexte());
      if (mounted) setState(() => _resultat = r);
    } catch (e) {
      if (mounted) setState(() => _erreur = e);
    } finally {
      if (mounted) setState(() => _analyse = false);
    }
  }

  Future<void> _ajouter({bool scan = false}) async {
    String? code;
    if (scan) {
      code = await (widget.scanner ?? scannerCodeParDefaut)(context);
      if (!mounted || code == null || code.trim().isEmpty) return;
    }
    final ProductSearchResult? p = await (widget.choixProduit ?? choisirProduitParDefaut)(context, code: code);
    if (!mounted || p == null) return;
    final nom = p.strNAME.trim().isNotEmpty ? p.strNAME.trim() : p.strLIBELLEE.trim();
    if (nom.isEmpty) return;
    if (_produits.any((x) => x.cip.isNotEmpty && x.cip == p.intCIP)) return;
    setState(() {
      _produits = [..._produits, ProduitAnalyse(nom: nom, cip: p.intCIP, quantite: 1)];
      _resultat = null;
    });
  }

  Future<void> _posologie(int i) async {
    final p = _produits[i];
    final c = TextEditingController(text: p.posologie);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.nom, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Posologie (facultatif)', hintText: 'ex. 1 comprimé 3 fois par jour'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(style: navyButton, onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Valider')),
        ],
      ),
    );
    c.dispose();
    if (v == null || !mounted) return;
    setState(() {
      _produits = [
        for (var k = 0; k < _produits.length; k++)
          k == i ? ProduitAnalyse(nom: p.nom, cip: p.cip, quantite: p.quantite, posologie: v.trim()) : _produits[k],
      ];
      _resultat = null;
    });
  }

  bool get _demonstration => _resultat?.demonstration == true || _statut?.demonstration == true;

  @override
  Widget build(BuildContext context) {
    final inset = Responsive.sideInset(context);
    return Scaffold(
      backgroundColor: Pal.page,
      body: Column(children: [
        NavyHeader(
          title: 'Analyse posologie',
          subtitle: _depuisVente ? 'Vente ${widget.referenceVente.isEmpty ? 'en cours' : widget.referenceVente}' : 'Interactions, contre-indications, posologies',
        ),
        if (_demonstration) const BandeauDemonstration(key: ValueKey('posos-demonstration')),
        if (_analyse) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16 + inset, 12, 16 + inset, 24),
            children: [
              if (_erreurStatut != null && _statut == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('État de Posos non vérifié : ${messageErreur(_erreurStatut!)}', style: const TextStyle(fontSize: 12, color: Pal.muted)),
                ),
              _carteProduits(),
              const SizedBox(height: 12),
              _carteContexte(),
              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  key: const ValueKey('posos-analyser'),
                  style: amberButton,
                  onPressed: _analyse || (!_depuisVente && _produits.isEmpty) ? null : _analyser,
                  icon: _analyse
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.health_and_safety),
                  label: Text(_analyse ? 'Analyse…' : 'Analyser'),
                ),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                BandeauErreur(erreur: _erreur!, onReessayer: _analyse ? null : _analyser),
              ],
              if (_resultat != null) ...[
                const SizedBox(height: 16),
                VueResultatPosos(resultat: _resultat!, demonstration: _demonstration),
              ],
              const SizedBox(height: 16),
              const Text(avertissementAnalyse, style: TextStyle(fontSize: 12, color: Pal.muted, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _carteProduits() => SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_depuisVente ? 'Produits de la vente' : 'Produits à analyser', style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.ink)),
          if (_depuisVente)
            const Text('Prestige relit les produits enregistrés sur la vente.', style: TextStyle(fontSize: 12, color: Pal.muted)),
          const SizedBox(height: 6),
          if (_produits.isEmpty && !_depuisVente)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Aucun produit : recherchez ou scannez les produits de l\'ordonnance.', style: TextStyle(color: Pal.muted)),
            ),
          for (var i = 0; i < _produits.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(_produits[i].nom, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text([
                if (_produits[i].quantite != null) 'Qté ${_produits[i].quantite}',
                _produits[i].posologie.isEmpty ? (_depuisVente ? '' : 'Posologie : toucher pour saisir') : _produits[i].posologie,
              ].where((x) => x.isNotEmpty).join(' · ')),
              onTap: _depuisVente ? null : () => _posologie(i),
              trailing: _depuisVente
                  ? null
                  : IconButton(
                      tooltip: 'Retirer',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => setState(() {
                        _produits = [..._produits]..removeAt(i);
                        _resultat = null;
                      }),
                    ),
            ),
          if (!_depuisVente) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                  key: const ValueKey('posos-rechercher'),
                  style: outlineButton,
                  onPressed: _analyse ? null : () => _ajouter(),
                  icon: const Icon(Icons.search),
                  label: const Text('Rechercher')),
              OutlinedButton.icon(
                  style: outlineButton, onPressed: _analyse ? null : () => _ajouter(scan: true), icon: const Icon(Icons.qr_code_scanner), label: const Text('Scanner')),
            ]),
          ],
        ]),
      );

  Widget _carteContexte() => SoftCard(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: const Text('Contexte du patient (facultatif)', style: TextStyle(fontWeight: FontWeight.w700, color: Pal.ink)),
            subtitle: const Text('Âge, sexe, grossesse, insuffisances : affine l\'analyse', style: TextStyle(fontSize: 12, color: Pal.muted)),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('posos-age'),
                    controller: _age,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                    decoration: InputDecoration(labelText: 'Âge', suffixText: 'ans', errorText: _erreurAge, errorMaxLines: 2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey('posos-poids'),
                    controller: _poids,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                    decoration: InputDecoration(labelText: 'Poids', suffixText: 'kg', errorText: _erreurPoids, errorMaxLines: 2),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final (v, l) in const [('', 'Sexe non précisé'), ('F', 'Femme'), ('M', 'Homme')])
                  ChoiceChip(label: Text(l), selected: _sexe == v, onSelected: (_) => setState(() => _sexe = v)),
              ]),
              if (_sexe != 'M') ...[
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Grossesse'), value: _grossesse, onChanged: (v) => setState(() => _grossesse = v)),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Allaitement'), value: _allaitement, onChanged: (v) => setState(() => _allaitement = v)),
              ],
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Insuffisance rénale'), value: _ir, onChanged: (v) => setState(() => _ir = v)),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Insuffisance hépatique'), value: _ih, onChanged: (v) => setState(() => _ih = v)),
            ],
          ),
        ),
      );
}

/// Bandeau permanent du mode démonstration.
class BandeauDemonstration extends StatelessWidget {
  const BandeauDemonstration({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: const Color(0xFFF59E0B),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Row(children: [
          Icon(Icons.science_outlined, color: Pal.onAmber),
          SizedBox(width: 8),
          Expanded(
            child: Text('Mode démonstration — résultats non réels', style: TextStyle(color: Pal.onAmber, fontWeight: FontWeight.bold)),
          ),
        ]),
      );
}

/// Résultat d'une analyse : résumé par gravité puis alertes, de la plus grave à la moins grave.
class VueResultatPosos extends StatelessWidget {
  final ResultatPosos resultat;
  final bool demonstration;
  const VueResultatPosos({super.key, required this.resultat, this.demonstration = false});

  @override
  Widget build(BuildContext context) {
    final r = resultat;
    if (!r.disponible) {
      return SoftCard(
        band: Pal.amber,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Analyse indisponible', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Pal.ink)),
          const SizedBox(height: 4),
          Text(r.message.isEmpty ? 'Posos n\'a pas pu analyser ces produits.' : r.message, style: const TextStyle(color: Pal.muted)),
        ]),
      );
    }
    final par = r.parNiveau;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SoftCard(
        band: r.alertes.isEmpty ? Pal.green : r.alertes.first.niveau.encre,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            r.alertes.isEmpty ? 'Aucune alerte détectée' : '${r.alertes.length} alerte(s), dont ${r.nombreMajeures} majeure(s)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Pal.ink),
          ),
          if (demonstration && r.avertissement.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(r.avertissement, style: const TextStyle(color: Color(0xFF8A5300), fontWeight: FontWeight.w600)),
          ],
          if (r.alertes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('L\'absence d\'alerte ne garantit pas l\'absence de risque.', style: TextStyle(color: Pal.muted)),
            ),
          if (par.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final n in NiveauGravite.values)
                if (par[n] != null) StatusBadge('${par[n]} · ${n.libelle}', fg: n.encre, bg: n.fond),
            ]),
          ],
        ]),
      ),
      for (final a in r.alertes) Padding(padding: const EdgeInsets.only(top: 10), child: _CarteAlerte(alerte: a)),
      if (r.produitsNonReconnus.isNotEmpty) ...[
        const SizedBox(height: 12),
        SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Produits non reconnus par l\'analyse', style: TextStyle(fontWeight: FontWeight.w700, color: Pal.ink)),
            const Text('Ils n\'ont pas été vérifiés : contrôlez-les vous-même.', style: TextStyle(fontSize: 12, color: Pal.muted)),
            const SizedBox(height: 4),
            for (final p in r.produitsNonReconnus) Text('• $p'),
          ]),
        ),
      ],
      if (r.venteProduits.isNotEmpty) ...[
        const SizedBox(height: 12),
        SoftCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Produits analysés', style: TextStyle(fontWeight: FontWeight.w700, color: Pal.ink)),
            const SizedBox(height: 4),
            for (final p in r.venteProduits)
              Text('• ${p.nom}${p.quantite != null && p.quantite! > 0 ? ' × ${p.quantite}' : ''}${p.posologie.isEmpty ? '' : ' — ${p.posologie}'}'),
          ]),
        ),
      ],
    ]);
  }
}

class _CarteAlerte extends StatelessWidget {
  final AlertePosos alerte;
  const _CarteAlerte({required this.alerte});

  @override
  Widget build(BuildContext context) {
    final n = alerte.niveau;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: n.encre, width: 5)),
        boxShadow: const [BoxShadow(color: Color(0x1214213D), blurRadius: 6, offset: Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(n.icone, color: n.encre, size: 20),
          const SizedBox(width: 6),
          Flexible(child: StatusBadge(alerte.gravite.isEmpty ? n.libelle : alerte.gravite, fg: n.encre, bg: n.fond)),
          if (alerte.type.isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(child: Text(alerte.type, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Pal.muted))),
          ],
        ]),
        const SizedBox(height: 6),
        Text(alerte.libelle, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
        if (alerte.produits.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Produits : ${alerte.produits.join(', ')}', style: const TextStyle(fontSize: 13, color: Pal.muted)),
        ],
        if (alerte.recommandation.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Conduite à tenir : ${alerte.recommandation}', style: const TextStyle(fontSize: 13)),
        ],
        if (alerte.equivalents.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Équivalents en rayon${alerte.proposer.isEmpty ? '' : ' (${alerte.proposer.join(', ')})'} :',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          for (final e in alerte.equivalents)
            Text('• ${e.nom}${e.stock != null ? ' — stock ${e.stock}' : ''}${e.prix != null ? ' — ${e.prix} F' : ''}', style: const TextStyle(fontSize: 13)),
        ],
      ]),
    );
  }
}
