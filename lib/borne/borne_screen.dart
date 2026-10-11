// lib/borne/borne_screen.dart
// B1 — Borne de vente libre-service : accueil, recherche, fiche, panier, vérification, ticket.
// Mode kiosque : bouton retour neutralisé, aucune navigation vers le reste de l'appli,
// sortie par appui long caché (coin haut gauche, 5 s) + code administrateur.
// Retour automatique à l'accueil (panier vidé) après le ticket et après l'inactivité.
// Serveur injoignable : « Borne momentanément indisponible — adressez-vous au comptoir ».
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_kiosque.dart';
import 'package:prestige_vente_app/borne/borne_panier.dart';
import 'package:prestige_vente_app/borne/borne_produit.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/borne/borne_widgets.dart';
import 'package:prestige_vente_app/horsligne/horsligne_ui.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:qr_flutter/qr_flutter.dart';

enum BorneVue { accueil, resultats, fiche, panier, ecarts, ticket }

class BorneScreen extends StatefulWidget {
  final BorneService service;
  final BorneConfig config;
  final ServerMonitor monitor;
  final BorneImprimante imprimante;
  final BorneKiosque? kiosque;

  /// Code administrateur (sortie du kiosque).
  final Future<bool> Function(BuildContext) adminCheck;

  /// Après la sortie (code correct) : retour à l'appli.
  final void Function(BuildContext) onSortie;

  /// Connexion de l'utilisateur borne (null : déjà connecté). Rappelée au retour du serveur.
  final Future<bool> Function()? connexion;

  /// Scan caméra (null : pas de bouton).
  final Future<String?> Function(BuildContext)? scanner;
  final String officine;
  final String codeType;
  final int largeurTicket;
  final BorneImageBuilder? image;

  /// B2 : le produit a-t-il une image connue (cache) ? Sert à mettre en avant les produits avec image.
  final bool? Function(String familleId)? imageConnue;

  /// Délais (réduits dans les tests si besoin).
  final Duration delaiTicket;
  final Duration delaiTicketEcran;
  final Duration avertissement;
  final Duration appuiSortie;

  const BorneScreen({
    super.key,
    required this.service,
    required this.config,
    required this.monitor,
    required this.imprimante,
    required this.adminCheck,
    required this.onSortie,
    this.kiosque,
    this.connexion,
    this.scanner,
    this.officine = '',
    this.codeType = 'QR_CODE',
    this.largeurTicket = 58,
    this.image,
    this.imageConnue,
    this.delaiTicket = const Duration(seconds: 10),
    this.delaiTicketEcran = const Duration(seconds: 30),
    this.avertissement = const Duration(seconds: 10),
    this.appuiSortie = const Duration(seconds: 5),
  });

  static const indisponibleTitre = 'Borne momentanément indisponible';
  static const indisponibleTexte = 'Adressez-vous au comptoir';
  static const toujoursLa = 'Êtes-vous toujours là ?';

  @override
  State<BorneScreen> createState() => BorneScreenState();
}

class BorneScreenState extends State<BorneScreen> {
  late final BornePanier panier =
      BornePanier(maxParProduit: widget.config.maxParProduit, maxArticles: widget.config.maxArticles)..addListener(_refresh);
  final _recherche = TextEditingController();
  final _focus = FocusNode();

  BorneVue vue = BorneVue.accueil;
  BorneVue _avantFiche = BorneVue.accueil;
  BorneProduit? _fiche;
  int _qteFiche = 1;
  String? _message;

  ProductPager? _pager;
  String? _rechercheErreur;
  Timer? _debounce;
  int _rechercheNo = 0;
  List<BorneProduit> _vedettes = const [];

  BorneVerification? _verif;
  bool _validation = false;
  String? _erreurValidation;
  BornePrevente? _prevente;
  BorneTicket? _ticket;
  bool _imprime = false;
  int _resteTicket = 0;
  Timer? _ticketTimer;

  Timer? _inactif;
  Timer? _avertTimer;
  int? _avertReste;

  Timer? _sortieTimer;
  bool _connecte = true;
  bool _connexionEnCours = false;
  Timer? _reconnexion;

  BorneConfig get cfg => widget.config;
  ServerMonitor get _m => widget.monitor;
  bool get indisponible => _m.etat != EtatServeur.enLigne || !_connecte;
  bool get avertissementVisible => _avertReste != null;

  @override
  void initState() {
    super.initState();
    HorsLigneScope.masquer.value = true;
    _m.addListener(_onMonitor);
    widget.kiosque?.demarrer();
    if (widget.connexion != null) {
      _connecte = false;
      _connecter();
    } else {
      _chargerVedettes();
    }
  }

  @override
  void dispose() {
    HorsLigneScope.masquer.value = false;
    _m.removeListener(_onMonitor);
    for (final t in [_debounce, _ticketTimer, _inactif, _avertTimer, _sortieTimer, _reconnexion]) {
      t?.cancel();
    }
    panier.dispose();
    _recherche.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Serveur / connexion
  // ---------------------------------------------------------------------------

  Future<void> _connecter() async {
    final c = widget.connexion;
    if (c == null || _connexionEnCours) return;
    _connexionEnCours = true;
    bool ok;
    try {
      ok = await c();
    } catch (_) {
      ok = false;
    } finally {
      _connexionEnCours = false;
    }
    if (!mounted) return;
    setState(() => _connecte = ok);
    _reconnexion?.cancel();
    if (ok) {
      _chargerVedettes();
    } else {
      // Nouvel essai régulier (et au retour du serveur).
      _reconnexion = Timer(const Duration(seconds: 30), _connecter);
    }
  }

  void _onMonitor() {
    if (!mounted) return;
    if (_m.etat != EtatServeur.enLigne) {
      // Borne indisponible : le client ne peut plus rien valider, son panier est effacé.
      if (vue != BorneVue.ticket) _accueil();
    } else if (!_connecte) {
      _connecter();
    }
    setState(() {});
  }

  Future<void> _chargerVedettes() async {
    final out = <BorneProduit>[];
    for (final code in cfg.vedettes) {
      final r = await widget.service.parCode(code);
      final p = r.valueOrNull;
      if (p != null) {
        _noterImages([p]);
        out.add(_produit(p));
      }
    }
    if (mounted) setState(() => _vedettes = trierPourBorne(out));
  }

  // ---------------------------------------------------------------------------
  // Inactivité
  // ---------------------------------------------------------------------------

  bool get _auRepos => vue == BorneVue.accueil && panier.vide && _recherche.text.isEmpty;

  /// Toute action du client relance le délai d'inactivité.
  void activite() {
    if (_avertReste != null) {
      _avertTimer?.cancel();
      setState(() => _avertReste = null);
    }
    _inactif?.cancel();
    if (_auRepos || vue == BorneVue.ticket) return;
    final total = Duration(seconds: cfg.inactivite);
    final avant = total > widget.avertissement ? total - widget.avertissement : Duration.zero;
    _inactif = Timer(avant, _avertir);
  }

  void _avertir() {
    if (!mounted || _auRepos || vue == BorneVue.ticket) return;
    setState(() => _avertReste = widget.avertissement.inSeconds);
    _avertTimer?.cancel();
    _avertTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      final r = (_avertReste ?? 0) - 1;
      if (r <= 0) {
        t.cancel();
        _accueil();
      } else {
        setState(() => _avertReste = r);
      }
    });
  }

  /// Retour à l'accueil : panier vidé, recherche effacée (confidentialité).
  void _accueil() {
    _inactif?.cancel();
    _avertTimer?.cancel();
    _ticketTimer?.cancel();
    _debounce?.cancel();
    _rechercheNo++;
    panier.vider();
    _recherche.clear();
    _focus.unfocus();
    if (!mounted) return;
    setState(() {
      vue = BorneVue.accueil;
      _avertReste = null;
      _pager = null;
      _rechercheErreur = null;
      _fiche = null;
      _verif = null;
      _prevente = null;
      _ticket = null;
      _erreurValidation = null;
      _message = null;
      _validation = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Recherche
  // ---------------------------------------------------------------------------

  void _onSaisie(String _) {
    activite();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => rechercher(_recherche.text));
    setState(() {});
  }

  /// Lance la recherche (rien sous 3 caractères).
  Future<void> rechercher(String brut, {SearchMode? mode}) async {
    final t = BorneService.texteRecherche(brut);
    if (t == null) {
      setState(() {
        _pager = null;
        _rechercheErreur = null;
        if (vue == BorneVue.resultats && brut.trim().isEmpty) vue = BorneVue.accueil;
      });
      return;
    }
    final no = ++_rechercheNo;
    if (ProductLookup.looksLikeCode(t)) {
      final r = await widget.service.parCode(t);
      if (!mounted || no != _rechercheNo) return;
      if (r case VenteOk(value: final p?)) {
        _ouvrirFiche(_produit(p), depuis: BorneVue.resultats);
        return;
      }
    }
    final pager = widget.service.pager(t, mode: mode);
    setState(() {
      _pager = pager;
      _rechercheErreur = null;
      vue = BorneVue.resultats;
    });
    final ok = await pager.loadMore();
    if (!mounted || no != _rechercheNo) return;
    _avecImage.clear();
    _noterImages(pager.items);
    setState(() => _rechercheErreur = ok ? null : (pager.error ?? 'Recherche impossible.'));
  }

  Future<void> _suite() async {
    final p = _pager;
    if (p == null || p.loading || !p.hasMore) return;
    final no = _rechercheNo;
    final avant = p.items.length;
    final ok = await p.loadMore();
    if (!mounted || no != _rechercheNo) return;
    _noterImages(p.items.skip(avant));
    setState(() => _rechercheErreur = ok ? null : p.error);
  }

  void _categorie(BorneCategorie c) {
    activite();
    _recherche.text = c.libelle;
    rechercher(c.motCle, mode: SearchMode.contient);
  }

  Future<void> _scanner() async {
    final s = widget.scanner;
    if (s == null) return;
    final code = await s(context);
    if (!mounted || code == null || code.trim().isEmpty) return;
    activite();
    _recherche.text = VenteInput.cleanQuery(code);
    await rechercher(code);
  }

  /// Produits avec image connus au chargement de la page (l'ordre ne bouge pas pendant que les images arrivent).
  final Set<String> _avecImage = {};

  void _noterImages(Iterable<ProductSearchResult> items) {
    final f = widget.imageConnue;
    if (f == null) return;
    for (final p in items) {
      if (f(p.lgFAMILLEID) == true) _avecImage.add(p.lgFAMILLEID);
    }
  }

  BorneProduit _produit(ProductSearchResult p) => BorneProduit(p, image: _avecImage.contains(p.lgFAMILLEID) ? 'cache' : null);

  List<BorneProduit> get _resultats => trierPourBorne([for (final p in _pager?.items ?? const <ProductSearchResult>[]) _produit(p)]);

  // ---------------------------------------------------------------------------
  // Panier
  // ---------------------------------------------------------------------------

  void _ouvrirFiche(BorneProduit p, {BorneVue? depuis}) {
    activite();
    setState(() {
      _avantFiche = depuis ?? vue;
      _fiche = p;
      _qteFiche = 1;
      _message = null;
      vue = BorneVue.fiche;
    });
  }

  void ajouter(BorneProduit p, int qte) {
    activite();
    final m = panier.ajouter(p, qte);
    setState(() => _message = m);
    if (m == null) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          width: MediaQuery.sizeOf(context).width >= 600 ? 420 : null,
          backgroundColor: Pal.green,
          content: Text('Ajouté : ${p.nom}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ));
      if (vue == BorneVue.fiche) setState(() => vue = _avantFiche);
    }
  }

  void _allerPanier() {
    activite();
    setState(() {
      vue = BorneVue.panier;
      _erreurValidation = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Validation : vérification serveur, écarts, création, ticket
  // ---------------------------------------------------------------------------

  /// « Payer en caisse » : prix et stock revérifiés ; écarts montrés avant confirmation.
  Future<void> payer() async {
    if (_validation || panier.vide || indisponible) return; // anti double appui
    activite();
    setState(() {
      _validation = true;
      _erreurValidation = null;
    });
    final r = await widget.service.verifier(panier.lignes);
    if (!mounted) return;
    if (r is! VenteOk<BorneVerification>) {
      setState(() {
        _validation = false;
        _erreurValidation = '${r.message ?? 'Vérification impossible.'} Réessayez ou adressez-vous au comptoir.';
      });
      return;
    }
    final v = r.value;
    if (v.ecarts.isNotEmpty) {
      panier.remplacer(v.lignes);
      setState(() {
        _verif = v;
        _validation = false;
        vue = BorneVue.ecarts;
      });
      return;
    }
    await _creer(v.lignes);
  }

  /// Le client accepte les écarts affichés.
  Future<void> confirmerEcarts() async {
    if (_validation) return;
    final v = _verif;
    if (v == null || v.lignes.isEmpty) return;
    activite();
    setState(() => _validation = true);
    await _creer(v.lignes);
  }

  Future<void> _creer(List<BorneLigne> lignes) async {
    final r = await widget.service.creerPrevente(lignes);
    if (!mounted) return;
    if (r is! VenteOk<BornePrevente>) {
      setState(() {
        _validation = false;
        vue = BorneVue.panier;
        _erreurValidation = '${r.message ?? 'Prévente non créée.'} Adressez-vous au comptoir si le problème persiste.';
      });
      return;
    }
    final p = r.value;
    final ticket = BorneTicket(officine: widget.officine, prevente: p, discret: cfg.ticketDiscret, codeType: widget.codeType, largeur: widget.largeurTicket);
    _inactif?.cancel();
    panier.vider();
    setState(() {
      _prevente = p;
      _ticket = ticket;
      _validation = false;
      _imprime = false;
      vue = BorneVue.ticket;
    });
    var imprime = false;
    try {
      imprime = await widget.imprimante.imprimer(ticket);
    } catch (_) {}
    if (!mounted) return;
    final d = imprime ? widget.delaiTicket : widget.delaiTicketEcran;
    setState(() {
      _imprime = imprime;
      _resteTicket = d.inSeconds;
    });
    _ticketTimer?.cancel();
    _ticketTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_resteTicket <= 1) {
        t.cancel();
        _accueil();
      } else {
        setState(() => _resteTicket--);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Sortie du kiosque (appui long caché 5 s + code administrateur)
  // ---------------------------------------------------------------------------

  void _sortieDebut() {
    _sortieTimer?.cancel();
    _sortieTimer = Timer(widget.appuiSortie, _demanderSortie);
  }

  void _sortieFin() => _sortieTimer?.cancel();

  Future<void> _demanderSortie() async {
    final ok = await widget.adminCheck(context);
    if (!ok || !mounted) return;
    await widget.kiosque?.arreter();
    if (!mounted) return;
    _accueil();
    widget.onSortie(context);
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------

  /// Colonnes : 1 (terminal), 2–3 (tablette portrait), 4 (tablette paysage / borne).
  static int colonnes(double largeur) => largeur < 600 ? 1 : (largeur < 760 ? 2 : (largeur < 900 ? 3 : 4));

  /// Panier latéral à partir de 900 px.
  static bool panierLateral(double largeur) => largeur >= 900;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final lateral = panierLateral(w) && !indisponible && vue != BorneVue.ticket;
    Widget corps = indisponible ? _indisponible() : _vue(w);
    if (lateral && vue != BorneVue.panier && vue != BorneVue.ecarts) {
      corps = Row(children: [
        Expanded(child: corps),
        SizedBox(width: 320, child: _panierLateral()),
      ]);
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {
        // Bouton retour neutralisé : dans la borne, il revient seulement à l'écran précédent de la borne.
        if (vue == BorneVue.fiche) setState(() => vue = _avantFiche);
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => activite(),
        child: Scaffold(
          backgroundColor: const Color(0xFFF7F9FC),
          body: Stack(children: [
            Positioned.fill(child: SafeArea(child: corps)),
            if (avertissementVisible) Positioned.fill(child: _avertissement()),
            // Coin caché : appui long 5 s → code administrateur.
            Positioned(
              left: 0,
              top: 0,
              width: 64,
              height: 64,
              child: GestureDetector(
                key: const ValueKey('borne-sortie'),
                behavior: HitTestBehavior.translucent,
                onLongPressStart: (_) => _sortieDebut(),
                onLongPressEnd: (_) => _sortieFin(),
                onLongPressCancel: _sortieFin,
                onTapDown: (_) => _sortieDebut(),
                onTapUp: (_) => _sortieFin(),
                onTapCancel: _sortieFin,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _vue(double w) => switch (vue) {
        BorneVue.accueil => _accueilVue(w),
        BorneVue.resultats => _resultatsVue(w),
        BorneVue.fiche => _ficheVue(),
        BorneVue.panier => _panierVue(),
        BorneVue.ecarts => _ecartsVue(),
        BorneVue.ticket => _ticketVue(),
      };

  Widget _indisponible() => Center(
        key: const ValueKey('borne-indisponible'),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 110,
              height: 110,
              decoration: const BoxDecoration(color: Color(0xFFFFF4E0), shape: BoxShape.circle),
              child: const Icon(Icons.store_mall_directory_outlined, size: 60, color: Color(0xFF8A3A00)),
            ),
            const SizedBox(height: 18),
            const Text(BorneScreen.indisponibleTitre,
                textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Pal.ink)),
            const SizedBox(height: 8),
            const Text(BorneScreen.indisponibleTexte,
                textAlign: TextAlign.center, style: TextStyle(fontSize: 20, color: Pal.navy, fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            const Text('La borne reprendra automatiquement dès que possible.', textAlign: TextAlign.center, style: TextStyle(color: Pal.muted)),
          ]),
        ),
      );

  Widget _avertissement() => ColoredBox(
        color: const Color(0x99101828),
        child: Center(
          child: Container(
            key: const ValueKey('borne-avertissement'),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 460),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.timer_outlined, size: 52, color: Pal.navy),
              const SizedBox(height: 10),
              const Text(BorneScreen.toujoursLa, textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Pal.ink)),
              const SizedBox(height: 8),
              Text('Retour à l\'accueil dans $_avertReste s (le panier sera vidé).',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Pal.muted)),
              const SizedBox(height: 18),
              BorneBouton('Je suis là', icon: Icons.touch_app, onPressed: activite),
            ]),
          ),
        ),
      );

  // --- En-tête avec recherche -------------------------------------------------

  Widget _champRecherche({bool grand = true}) => TextField(
        key: const ValueKey('borne-recherche'),
        controller: _recherche,
        focusNode: _focus,
        inputFormatters: VenteInput.queryFormatters,
        onChanged: _onSaisie,
        onSubmitted: (v) {
          _debounce?.cancel();
          rechercher(v);
        },
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: grand ? 20 : 17, color: Pal.ink),
        decoration: InputDecoration(
          hintText: 'Tapez le nom d\'un produit…',
          prefixIcon: const Icon(Icons.search, size: 28, color: Pal.navy),
          suffixIcon: _recherche.text.isEmpty
              ? (widget.scanner == null
                  ? null
                  : IconButton(
                      key: const ValueKey('borne-scanner'),
                      tooltip: 'Scanner le code-barres',
                      iconSize: 28,
                      icon: const Icon(Icons.qr_code_scanner, color: Pal.navy),
                      onPressed: _scanner))
              : IconButton(
                  tooltip: 'Effacer',
                  iconSize: 28,
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _recherche.clear();
                    rechercher('');
                    setState(() => vue = BorneVue.accueil);
                  }),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.symmetric(vertical: grand ? 20 : 14, horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      );

  Widget _entete({required bool accueil}) {
    final guidee = cfg.presentation == BornePresentation.guidee;
    final liste = cfg.presentation == BornePresentation.listeRapide;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, accueil ? 20 : 12, 16, accueil ? 22 : 14),
      decoration: BoxDecoration(
        gradient: liste ? null : const LinearGradient(colors: [Color(0xFF003366), Color(0xFF0B5394)]),
        color: liste ? Colors.white : null,
        border: liste ? const Border(bottom: BorderSide(color: Pal.line)) : null,
        borderRadius: liste ? null : const BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (guidee) ...[_etapes(vue == BorneVue.panier || vue == BorneVue.ecarts ? 1 : 0), const SizedBox(height: 10)],
        if (widget.officine.isNotEmpty)
          Text(widget.officine, style: TextStyle(fontSize: 13, color: liste ? Pal.muted : Pal.headerMuted)),
        if (accueil) ...[
          const SizedBox(height: 4),
          Text(cfg.accueil,
              key: const ValueKey('borne-accueil-texte'),
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, height: 1.15, color: liste ? Pal.navy : Colors.white)),
          const SizedBox(height: 14),
        ] else
          const SizedBox(height: 6),
        DecoratedBox(
          decoration: liste ? BoxDecoration(border: Border.all(color: const Color(0xFFC5D0DE)), borderRadius: BorderRadius.circular(16)) : const BoxDecoration(),
          child: _champRecherche(grand: accueil),
        ),
      ]),
    );
  }

  Widget _etapes(int actif) {
    Widget e(int i, String t) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: i == actif ? Pal.amber : (i < actif ? const Color(0x5916A34A) : const Color(0x1FFFFFFF)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${i + 1} $t',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: i == actif ? Pal.onAmber : Colors.white)),
          ),
        );
    return Row(children: [e(0, 'Chercher'), e(1, 'Panier'), e(2, 'Payer')]);
  }

  Widget _barrePanier() {
    if (panier.vide) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Pal.line))),
      child: SafeArea(
        top: false,
        child: Row(children: [
          const Icon(Icons.shopping_cart, color: Pal.navy, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${panier.articles} article${panier.articles > 1 ? 's' : ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Pal.ink)),
              Text(prixF(panier.total), key: const ValueKey('borne-barre-total'), style: const TextStyle(color: Pal.muted, fontSize: 15)),
            ]),
          ),
          BorneBouton('PANIER', key: const ValueKey('borne-voir-panier'), icon: Icons.arrow_forward, onPressed: _allerPanier),
        ]),
      ),
    );
  }

  // --- Accueil ---------------------------------------------------------------------

  Widget _accueilVue(double w) {
    final cats = cfg.categories;
    final colsCat = w < 600 ? 3 : 6;
    return Column(children: [
      _entete(accueil: true),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 20), children: [
          if (cats.isNotEmpty) ...[
            const Text('Catégories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Pal.ink)),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: colsCat,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: w < 600 ? 1.05 : 1.25,
              children: [for (final c in cats) _tuileCategorie(c)],
            ),
            const SizedBox(height: 16),
          ],
          if (_vedettes.isNotEmpty) ...[
            const Text('Produits mis en avant', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Pal.ink)),
            const SizedBox(height: 8),
            _grille(_vedettes, w, shrink: true),
          ],
          if (cats.isEmpty && _vedettes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Tapez au moins 3 lettres du nom d\'un produit.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Pal.muted)),
            ),
        ]),
      ),
      if (!panierLateral(w)) _barrePanier(),
    ]);
  }

  /// Pictogramme d'une catégorie d'après son libellé (sinon d'après la forme du mot-clé).
  static (IconData, Color, Color) iconeCategorie(BorneCategorie c) {
    final l = c.libelle.toLowerCase();
    bool a(List<String> m) => m.any(l.contains);
    if (a(['douleur', 'fièvre', 'fievre'])) return (Icons.healing, const Color(0xFFE3ECF7), const Color(0xFF003366));
    if (a(['rhume', 'toux', 'grippe', 'nez'])) return (Icons.sick_outlined, const Color(0xFFE0F2FE), const Color(0xFF075985));
    if (a(['hygi', 'savon', 'dent'])) return (Icons.clean_hands, const Color(0xFFFDECEC), const Color(0xFF8B1C1C));
    if (a(['bébé', 'bebe', 'enfant', 'lait'])) return (Icons.child_care, const Color(0xFFE6F4EA), const Color(0xFF166534));
    if (a(['vitamin', 'forme', 'énergie'])) return (Icons.bolt, const Color(0xFFFFF4E0), const Color(0xFF8A3A00));
    if (a(['intim', 'femme', 'homme'])) return (Icons.spa_outlined, const Color(0xFFF3E8FF), const Color(0xFF5B21B6));
    if (a(['peau', 'soleil', 'beauté', 'beaute'])) return (Icons.face_retouching_natural, const Color(0xFFFFE4E6), const Color(0xFF9F1239));
    final f = formeDuNom(c.motCle);
    final (bg, fg) = f.couleurs;
    return (f == FormeProduit.autre ? Icons.local_pharmacy : f.icon, bg, fg);
  }

  Widget _tuileCategorie(BorneCategorie c) {
    final (icon, bg, fg) = iconeCategorie(c);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Pal.line)),
      child: InkWell(
        key: ValueKey('borne-categorie-${c.libelle}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => _categorie(c),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: fg, size: 26),
            ),
            const SizedBox(height: 6),
            Text(c.libelle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Pal.ink)),
          ]),
        ),
      ),
    );
  }

  // --- Résultats ---------------------------------------------------------------------

  Widget _grille(List<BorneProduit> items, double w, {bool shrink = false, Widget? fin}) {
    final lateral = panierLateral(w);
    final cols = colonnes(lateral ? w - 320 : w).clamp(1, lateral ? 4 : 3);
    final liste = cfg.presentation == BornePresentation.listeRapide;
    final grille = !liste && cols > 1;
    Widget carte(BorneProduit p) => BorneCarteProduit(
          produit: p,
          presentation: cfg.presentation,
          grille: grille,
          image: widget.image,
          onTap: () => _ouvrirFiche(p),
          onAjouter: p.disponible ? () => ajouter(p, 1) : null,
        );
    if (!grille) {
      return ListView.separated(
        shrinkWrap: shrink,
        physics: shrink ? const NeverScrollableScrollPhysics() : null,
        padding: shrink ? EdgeInsets.zero : EdgeInsets.fromLTRB(liste ? 0 : 12, liste ? 0 : 10, liste ? 0 : 12, 16),
        itemCount: items.length + (fin == null ? 0 : 1),
        separatorBuilder: (_, __) => liste ? const Divider(height: 1, color: Color(0xFFEEF1F5)) : const SizedBox(height: 8),
        itemBuilder: (_, i) => i < items.length ? carte(items[i]) : fin!,
      );
    }
    return GridView.builder(
      shrinkWrap: shrink,
      physics: shrink ? const NeverScrollableScrollPhysics() : null,
      padding: shrink ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 10, 12, 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 236),
      itemCount: items.length + (fin == null ? 0 : 1),
      itemBuilder: (_, i) => i < items.length ? carte(items[i]) : fin!,
    );
  }

  Widget _resultatsVue(double w) {
    final p = _pager;
    final items = _resultats;
    Widget corps;
    if (p == null || (p.loading && items.isEmpty)) {
      corps = const Center(child: CircularProgressIndicator());
    } else if (items.isEmpty && _rechercheErreur != null) {
      corps = _erreur(_rechercheErreur!, () => rechercher(_recherche.text));
    } else if (items.isEmpty) {
      corps = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Aucun produit pour « ${_recherche.text.trim()} ».\nEssayez un autre nom.',
              key: const ValueKey('borne-aucun'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: Pal.muted)),
        ),
      );
    } else {
      final fin = p.hasMore || _rechercheErreur != null
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: _rechercheErreur != null
                    ? TextButton(onPressed: _suite, child: const Text('Réessayer', style: TextStyle(fontSize: 17)))
                    : (p.loading
                        ? const CircularProgressIndicator()
                        : BorneBouton('Voir plus (${items.length} sur ${p.total})', principal: false, contour: true, onPressed: _suite)),
              ),
            )
          : null;
      corps = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 300 && p.hasMore && !p.loading && _rechercheErreur == null) _suite();
          return false;
        },
        child: _grille(items, w, fin: fin),
      );
    }
    return Column(children: [
      _entete(accueil: false),
      Expanded(child: corps),
      if (!panierLateral(w)) _barrePanier(),
    ]);
  }

  Widget _erreur(String m, VoidCallback retry) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 48, color: Color(0xFFB91C1C)),
            const SizedBox(height: 8),
            Text(m, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Pal.ink)),
            const SizedBox(height: 12),
            BorneBouton('Réessayer', principal: false, onPressed: retry),
          ]),
        ),
      );

  // --- Fiche ---------------------------------------------------------------------

  Widget _retour(String t, VoidCallback f) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('borne-retour'),
            style: TextButton.styleFrom(minimumSize: const Size(borneToucheMin * 2, borneToucheMin), foregroundColor: Pal.navy),
            onPressed: () {
              activite();
              f();
            },
            icon: const Icon(Icons.arrow_back, size: 26),
            label: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
      );

  Widget _ficheVue() {
    final p = _fiche!;
    final reste = panier.restePour(p.id);
    final max = [reste, p.stock, cfg.maxParProduit].reduce((a, b) => a < b ? a : b);
    final qte = _qteFiche.clamp(1, max < 1 ? 1 : max);
    return Column(children: [
      _retour('Retour', () => setState(() => vue = _avantFiche)),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
          Center(child: BornePicto(p, taille: 170, image: widget.image)),
          const SizedBox(height: 14),
          Text(p.nom, key: const ValueKey('borne-fiche-nom'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Pal.ink)),
          const SizedBox(height: 4),
          Text('${p.forme.label} · code ${p.code}', style: const TextStyle(fontSize: 15, color: Pal.muted)),
          const SizedBox(height: 10),
          Text(prixF(p.prix), key: const ValueKey('borne-fiche-prix'), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Pal.navy)),
          const SizedBox(height: 16),
          if (!p.disponible)
            const Text('Ce produit est indisponible pour le moment. Demandez au comptoir.',
                key: ValueKey('borne-fiche-indisponible'), style: TextStyle(fontSize: 18, color: Color(0xFF991B1B), fontWeight: FontWeight.w700))
          else if (max < 1)
            Text('Quantité maximale atteinte pour ce produit (${cfg.maxParProduit} par produit, ${cfg.maxArticles} articles au total).',
                key: const ValueKey('borne-fiche-plafond'), style: const TextStyle(fontSize: 17, color: Color(0xFF8A3A00)))
          else
            Center(child: BorneQte(qte: qte, max: max, cle: 'borne-fiche-qte', onChanged: (v) => setState(() => _qteFiche = v))),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(_message!, key: const ValueKey('borne-message'), style: const TextStyle(fontSize: 16, color: Color(0xFF991B1B))),
          ],
        ]),
      ),
      if (p.disponible && max >= 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: BorneBouton('AJOUTER AU PANIER', key: const ValueKey('borne-fiche-ajouter'), icon: Icons.add_shopping_cart, onPressed: () => ajouter(p, qte)),
          ),
        ),
    ]);
  }

  // --- Panier ---------------------------------------------------------------------

  Widget _lignePanier(BorneLigne l, {bool compact = false}) {
    final p = l.produit;
    final max = (l.qte + panier.restePour(p.id)).clamp(1, p.stock < 1 ? 1 : p.stock);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Pal.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (!compact) ...[BornePicto(p, taille: 44, image: widget.image), const SizedBox(width: 10)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.nom, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: Pal.ink)),
              Text('${prixF(p.prix)} l\'unité', style: const TextStyle(fontSize: 13, color: Pal.muted)),
            ]),
          ),
          IconButton(
            key: ValueKey('borne-retirer-${p.id}'),
            tooltip: 'Retirer',
            iconSize: 28,
            constraints: const BoxConstraints(minWidth: borneToucheMin, minHeight: borneToucheMin),
            icon: const Icon(Icons.delete_outline, color: Color(0xFFB91C1C)),
            onPressed: () {
              activite();
              panier.retirer(p.id);
            },
          ),
        ]),
        Row(children: [
          BorneQte(
            qte: l.qte,
            max: max,
            cle: 'borne-panier-qte-${p.id}',
            onChanged: (v) {
              activite();
              final m = panier.changer(p.id, v);
              if (m != null) setState(() => _message = m);
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(prixF(l.total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Pal.navy)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _panierLateral() => Container(
        key: const ValueKey('borne-panier-lateral'),
        decoration: const BoxDecoration(color: Colors.white, border: Border(left: BorderSide(color: Pal.line))),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.shopping_cart, color: Pal.navy),
            SizedBox(width: 8),
            Text('Mon panier', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Pal.ink)),
          ]),
          const SizedBox(height: 10),
          Expanded(
            child: panier.vide
                ? const Center(child: Text('Votre panier est vide', style: TextStyle(color: Pal.muted, fontSize: 16)))
                : ListView.separated(
                    itemCount: panier.lignes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _lignePanier(panier.lignes[i], compact: true),
                  ),
          ),
          _total(),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: BorneBouton('PAYER', key: const ValueKey('borne-panier-lateral-payer'), icon: Icons.point_of_sale, onPressed: panier.vide ? null : _allerPanier),
          ),
        ]),
      );

  Widget _total() => Row(children: [
        const Text('Total', style: TextStyle(fontSize: 17, color: Pal.muted)),
        const SizedBox(width: 8),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(prixF(panier.total), key: const ValueKey('borne-total'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Pal.ink)),
          ),
        ),
      ]);

  Widget _panierVue() {
    final guidee = cfg.presentation == BornePresentation.guidee;
    return Column(children: [
      if (guidee)
        Container(
          color: Pal.navy,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: _etapes(1),
        ),
      _retour('Continuer mes achats', () => setState(() => vue = _pager == null ? BorneVue.accueil : BorneVue.resultats)),
      Expanded(
        child: panier.vide
            ? const Center(child: Text('Votre panier est vide', style: TextStyle(fontSize: 18, color: Pal.muted)))
            : ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 12), children: [
                const Text('Mon panier', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Pal.ink)),
                const SizedBox(height: 8),
                for (final l in panier.lignes) ...[_lignePanier(l), const SizedBox(height: 8)],
                if (_message != null) Text(_message!, key: const ValueKey('borne-message'), style: const TextStyle(color: Color(0xFF991B1B), fontSize: 15)),
                Text('Au maximum ${cfg.maxParProduit} par produit et ${cfg.maxArticles} articles.', style: const TextStyle(color: Pal.muted, fontSize: 13)),
              ]),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Pal.line))),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _total(),
            if (_erreurValidation != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_erreurValidation!, key: const ValueKey('borne-erreur-validation'), style: const TextStyle(color: Color(0xFF991B1B), fontSize: 15)),
              ),
            const SizedBox(height: 10),
            if (guidee)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Icon(Icons.payments_outlined, color: Pal.green),
                  SizedBox(width: 8),
                  Expanded(child: Text('À la caisse (espèces) : un ticket sort, présentez-le à la caisse.', style: TextStyle(fontSize: 15, color: Pal.ink))),
                ]),
              ),
            SizedBox(
              width: double.infinity,
              child: BorneBouton('PAYER EN CAISSE',
                  key: const ValueKey('borne-payer'),
                  icon: Icons.receipt_long,
                  occupe: _validation,
                  onPressed: panier.vide || _validation ? null : payer),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _ecartsVue() {
    final v = _verif!;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(18), children: [
          const Icon(Icons.info_outline, size: 48, color: Color(0xFF8A3A00)),
          const SizedBox(height: 8),
          const Text('Votre panier a été mis à jour', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Pal.ink)),
          const SizedBox(height: 6),
          const Text('Les prix et les stocks viennent d\'être vérifiés :', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Pal.muted)),
          const SizedBox(height: 12),
          for (final e in v.ecarts)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF4E0), border: Border.all(color: const Color(0xFFF5D08A)), borderRadius: BorderRadius.circular(12)),
              child: Text(e.texte, key: ValueKey('borne-ecart-${e.nom}'), style: const TextStyle(fontSize: 16, color: Color(0xFF7C2D12))),
            ),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Nouveau total', style: TextStyle(fontSize: 17, color: Pal.muted)),
            const SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(prixF(v.total), key: const ValueKey('borne-ecarts-total'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Pal.ink)),
              ),
            ),
          ]),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Column(children: [
          if (v.lignes.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: BorneBouton('CONFIRMER ET PAYER EN CAISSE',
                  key: const ValueKey('borne-confirmer-ecarts'), occupe: _validation, onPressed: _validation ? null : confirmerEcarts),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: BorneBouton('MODIFIER MON PANIER', key: const ValueKey('borne-modifier-panier'), contour: true, onPressed: _allerPanier),
          ),
        ]),
      ),
    ]);
  }

  // --- Ticket ---------------------------------------------------------------------

  Widget _ticketVue() {
    final p = _prevente!;
    final t = _ticket!;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(color: Color(0xFFE6F4EA), shape: BoxShape.circle),
              child: const Icon(Icons.check, size: 52, color: Color(0xFF166534)),
            ),
            const SizedBox(height: 8),
            const Text('Merci !', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Pal.ink)),
            const SizedBox(height: 6),
            Text(_imprime ? 'Votre ticket s\'imprime.' : 'Montrez cet écran à la caisse (ou notez le numéro).',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, color: Pal.muted)),
            const SizedBox(height: 10),
            const Text('N° de prévente', style: TextStyle(fontSize: 16, color: Pal.muted)),
            Text(p.numero, key: const ValueKey('borne-numero'), style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w900, color: Pal.navy, height: 1.05)),
            if (!_imprime) ...[
              const SizedBox(height: 8),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(10),
                child: QrImageView(key: const ValueKey('borne-qr'), data: p.reference, size: 190),
              ),
              Text(p.reference, key: const ValueKey('borne-reference'), style: const TextStyle(fontSize: 16, color: Pal.ink)),
              const SizedBox(height: 8),
              ExpansionTile(
                title: const Text('Voir le ticket', style: TextStyle(fontWeight: FontWeight.w700)),
                children: [Container(color: Colors.white, padding: const EdgeInsets.all(10), child: t.apercu())],
              ),
            ],
            const SizedBox(height: 10),
            Text('${prixF(p.total)} · ${BorneTicket.invitation}',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Pal.ink)),
            const SizedBox(height: 14),
            Text('Retour à l\'accueil dans $_resteTicket s', key: const ValueKey('borne-retour-ticket'), style: const TextStyle(color: Pal.muted, fontSize: 15)),
            const SizedBox(height: 12),
            BorneBouton('TERMINÉ', key: const ValueKey('borne-termine'), principal: false, onPressed: _accueil),
          ]),
        ),
      ),
    );
  }
}
