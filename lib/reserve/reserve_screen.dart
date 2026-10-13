// lib/reserve/reserve_screen.dart
// Menu « Réserve » : réappros manuels (Rayon → Réserve, Réserve → Rayon) et suggestions automatiques à traiter.
// Parcours décidé avec le pharmacien : suggestion PUIS traitement (comme l'écran web), jamais de mouvement direct.
// Menu réservé aux administrateurs (droit dédié quand le serveur l'exposera) : voir lib/droits/droits_modules.dart.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/reserve/reserve_api.dart';
import 'package:prestige_vente_app/reserve/reserve_models.dart';
import 'package:prestige_vente_app/reserve/reserve_panier_screen.dart';
import 'package:prestige_vente_app/reserve/reserve_regles.dart';
import 'package:prestige_vente_app/reserve/reserve_traitement_screen.dart';
import 'package:prestige_vente_app/reserve/reserve_widgets.dart';
import 'package:prestige_vente_app/serveur/choix_produit.dart';
import 'package:prestige_vente_app/serveur/client_contexte.dart';
import 'package:prestige_vente_app/serveur/erreur_vue.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

class ReserveScreen extends StatefulWidget {
  /// Tests : API sans serveur réel.
  final ReserveApi? api;
  final ChoixProduit? choixProduit;
  final ScanCode? scanner;
  const ReserveScreen({super.key, this.api, this.choixProduit, this.scanner});

  @override
  State<ReserveScreen> createState() => _ReserveScreenState();
}

class _ReserveScreenState extends State<ReserveScreen> {
  late final ReserveApi _api = widget.api ?? ReserveApi(clientPrestige(context));
  List<EnteteSuggestion> _enAttente = const [];
  bool _chargement = true;
  Object? _erreur;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  Future<void> _charger() async {
    if (!mounted) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final l = await _api.enAttente();
      if (!mounted) return;
      setState(() {
        _enAttente = l;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e;
        _chargement = false;
      });
    }
  }

  int _nombre(SensReserve s, OrigineSuggestion o) => suggestionsAReprendre(_enAttente, s, o).length;

  Future<void> _ouvrirPanier(SensReserve s) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReservePanierScreen(sens: s, api: _api, choixProduit: widget.choixProduit, scanner: widget.scanner)));
    _charger();
  }

  Future<void> _ouvrirListe(SensReserve s, OrigineSuggestion o) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReserveListeScreen(sens: s, origine: o, api: _api)));
    _charger();
  }

  Widget _carte({
    required SensReserve sens,
    required String titre,
    required String detail,
    required String bouton,
    required VoidCallback onTap,
    int? nombre,
    Key? key,
  }) =>
      SoftCard(
        key: key,
        band: couleurSens(sens),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 6, children: [
            SensBadge(sens),
            if (nombre != null && nombre > 0) StatusBadge('$nombre à traiter', fg: const Color(0xFF8A5300), bg: const Color(0xFFFFF1D6)),
          ]),
          const SizedBox(height: 10),
          Text(titre, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Pal.ink)),
          const SizedBox(height: 2),
          Text(detail, style: const TextStyle(fontSize: 13, color: Pal.muted)),
          const SizedBox(height: 12),
          // Cible tactile ≥ 48 dp (ANO-04 : 44 dp auparavant).
          SizedBox(height: 48, child: ElevatedButton(style: navyButton, onPressed: onTap, child: Text(bouton))),
        ]),
      );

  Widget _section(String titre, List<Widget> cartes) {
    final cols = Responsive.columns(context, medium: 2, expanded: 2);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(titre.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Color(0xFF4A5A70))),
      ),
      if (cols == 1)
        for (final c in cartes) Padding(padding: const EdgeInsets.only(bottom: 12), child: c)
      else
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < cartes.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: cartes[i]),
          ],
        ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    const manuelle = OrigineSuggestion.manuelle, auto = OrigineSuggestion.automatique;
    return Scaffold(
      backgroundColor: Pal.page,
      body: Column(children: [
        NavyHeader(
          title: 'Réserve',
          subtitle: 'Réappros entre le rayon et la réserve',
          actions: [IconButton(tooltip: 'Actualiser', onPressed: _chargement ? null : _charger, icon: const Icon(Icons.refresh, color: Colors.white))],
        ),
        if (_chargement) const LinearProgressIndicator(minHeight: 2),
        if (_erreur != null) BandeauErreur(erreur: _erreur!, onReessayer: _charger),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _charger,
            child: ListView(
              padding: EdgeInsets.fromLTRB(16 + Responsive.sideInset(context), 4, 16 + Responsive.sideInset(context), 24),
              children: [
                _section('Réappro manuel', [
                  _carte(
                    key: const ValueKey('reserve-manuel-versReserve'),
                    sens: SensReserve.versReserve,
                    titre: 'Ranger en réserve',
                    detail: 'Réappro RÉSERVE : le surplus du rayon part en réserve.',
                    bouton: 'Préparer',
                    nombre: _nombre(SensReserve.versReserve, manuelle),
                    onTap: () => _ouvrirPanier(SensReserve.versReserve),
                  ),
                  _carte(
                    key: const ValueKey('reserve-manuel-versRayon'),
                    sens: SensReserve.versRayon,
                    titre: 'Regarnir le rayon',
                    detail: 'Réappro RAYON : les boîtes sortent de la réserve vers le rayon.',
                    bouton: 'Préparer',
                    nombre: _nombre(SensReserve.versRayon, manuelle),
                    onTap: () => _ouvrirPanier(SensReserve.versRayon),
                  ),
                ]),
                _section('Suggestions automatiques', [
                  _carte(
                    key: const ValueKey('reserve-auto-versRayon'),
                    sens: SensReserve.versRayon,
                    titre: 'Rayon à regarnir',
                    detail: 'Proposées par Prestige après les ventes (rayon sous le seuil mini).',
                    bouton: 'Voir les suggestions',
                    nombre: _nombre(SensReserve.versRayon, auto),
                    onTap: () => _ouvrirListe(SensReserve.versRayon, auto),
                  ),
                  _carte(
                    key: const ValueKey('reserve-auto-versReserve'),
                    sens: SensReserve.versReserve,
                    titre: 'Surplus à ranger',
                    detail: 'Proposées par Prestige (rayon au-dessus du seuil réserve).',
                    bouton: 'Voir les suggestions',
                    nombre: _nombre(SensReserve.versReserve, auto),
                    onTap: () => _ouvrirListe(SensReserve.versReserve, auto),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

/// Suggestions encore à traiter d'un sens et d'une origine (emplacement de l'utilisateur).
class ReserveListeScreen extends StatefulWidget {
  final SensReserve sens;
  final OrigineSuggestion origine;
  final ReserveApi api;
  const ReserveListeScreen({super.key, required this.sens, required this.origine, required this.api});

  @override
  State<ReserveListeScreen> createState() => _ReserveListeScreenState();
}

class _ReserveListeScreenState extends State<ReserveListeScreen> {
  List<EnteteSuggestion>? _liste;
  Object? _erreur;
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final l = await widget.api.enAttente();
      if (!mounted) return;
      setState(() {
        _liste = suggestionsAReprendre(l, widget.sens, widget.origine);
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e;
        _chargement = false;
      });
    }
  }

  Future<void> _ouvrir(EnteteSuggestion s) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReserveTraitementScreen(suggestionId: s.id, api: widget.api)));
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    final liste = _liste;
    Widget corps;
    if (liste == null && _erreur != null) {
      corps = ErreurVue(erreur: _erreur!, onReessayer: _charger);
    } else if (liste == null) {
      corps = const Center(child: CircularProgressIndicator());
    } else if (liste.isEmpty) {
      corps = ListView(children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Aucune suggestion ${widget.origine.libelle.toLowerCase()} « ${widget.sens.fleche} » à traiter sur cet emplacement.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Pal.muted),
          ),
        ),
      ]);
    } else {
      corps = ListView.separated(
        padding: EdgeInsets.fromLTRB(16 + Responsive.sideInset(context), 12, 16 + Responsive.sideInset(context), 24),
        itemCount: liste.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => CarteSuggestion(entete: liste[i], onTap: () => _ouvrir(liste[i])),
      );
    }
    return Scaffold(
      backgroundColor: Pal.page,
      body: Column(children: [
        NavyHeader(
          title: 'Suggestions ${widget.origine.libelle.toLowerCase()}s',
          subtitle: '${widget.sens.fleche} · à traiter',
          actions: [IconButton(tooltip: 'Actualiser', onPressed: _chargement ? null : _charger, icon: const Icon(Icons.refresh, color: Colors.white))],
        ),
        if (_chargement && liste != null) const LinearProgressIndicator(minHeight: 2),
        if (_erreur != null && liste != null) BandeauErreur(erreur: _erreur!, onReessayer: _charger),
        Expanded(child: RefreshIndicator(onRefresh: _charger, child: corps)),
      ]),
    );
  }
}
