// lib/accueil/accueil_screen.dart
// Nouvel écran d'accueil : une seule page par familles, « À faire maintenant », favoris,
// pastille d'état du serveur, recherche / scan global, barre du bas Accueil · Scanner · Tâches · Réglages.
// Présentations A (tableau de bord, défaut), B (liste compacte), C (guidé par métier).
// Conserve tout l'accueil d'origine (lib/screens/home/home_screen.dart, inchangé) : mêmes menus,
// mêmes écrans, Ajustement protégé par code, ordre / menus masqués (SettingsProvider), contrôle de
// la licence au retour au premier plan et toutes les 15 min, rappels de licence, tâches en attente.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/accueil/organiser_accueil_screen.dart';
import 'package:prestige_vente_app/accueil/recherche_globale_screen.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/interface_version.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/bl_control_provider.dart';
import 'package:prestige_vente_app/providers/caisse_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/licence_registration_screen.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/screens/bl_control/bl_list_screen.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/core/pending_sale_store.dart';
import 'package:prestige_vente_app/ventes/ventes_version.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

enum EtatServeur { verification, connecte, horsLigne }

class AccueilScreen extends StatefulWidget {
  /// Présentation imposée (tests) ; sinon celle choisie sur l'appareil (A par défaut).
  final ListPresentation? presentation;

  /// Vérification légère du serveur (tests) ; sinon GET /officine.
  final Future<bool> Function()? serverCheck;

  /// Lecture d'un code (tests) ; sinon l'appareil photo.
  final CodeScanner? scanner;

  /// Vérification du code administrateur (tests) ; sinon PinCodeDialog.show.
  final Future<bool> Function(BuildContext context)? askPin;

  const AccueilScreen({super.key, this.presentation, this.serverCheck, this.scanner, this.askPin});

  @override
  State<AccueilScreen> createState() => _AccueilScreenState();
}

/// Une carte de « À faire maintenant » / onglet Tâches.
class _Tache {
  final String titre;
  final String? detail;
  final int? nombre;
  final IconData icon;
  final Color couleur;
  final String action;
  final VoidCallback onTap;

  /// Simple information (caisse) : ne compte pas comme une tâche.
  final bool info;
  final bool erreur;
  const _Tache({
    required this.titre,
    this.detail,
    this.nombre,
    required this.icon,
    required this.couleur,
    required this.action,
    required this.onTap,
    this.info = false,
    this.erreur = false,
  });
}

class _AccueilScreenState extends State<AccueilScreen> with WidgetsBindingObserver, PresentationAware {
  static const _rouge = Color(0xFFB91C1C);

  late SaleProvider _saleProvider;
  late BlControlProvider _blProvider;
  Timer? _licenceWatchdogTimer;

  /// 0 = Accueil, 1 = Tâches.
  int _tab = 0;
  EtatServeur _serveur = EtatServeur.verification;

  bool _chargement = false;
  DateTime? _majTaches;
  int? _preventes;
  String? _preventeAncienne;
  String? _erreurPreventes;
  int? _bl;
  String? _erreurBl;
  List<(VenteMenu, PendingSale)> _interrompues = const [];
  List<String> _favoris = List.of(AccueilFavoris.parDefaut);

  /// Présentation C : liste de tous les menus dépliée.
  bool _toutVoir = false;

  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadPresentation();

    _saleProvider = Provider.of<SaleProvider>(context, listen: false);
    _blProvider = Provider.of<BlControlProvider>(context, listen: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<AuthProvider>(context, listen: false).loadOfficineInfo();
      Provider.of<LicenceProvider>(context, listen: false).checkReminders(context);
      _actualiser();
    });
    _chargerFavoris();

    _licenceWatchdogTimer = Timer.periodic(const Duration(minutes: 15), (timer) {
      _performSecurityCheck();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _licenceWatchdogTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Sécurité de la licence (identique à l'accueil d'origine)
  // ---------------------------------------------------------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _performSecurityCheck();
    }
  }

  bool _securityCheckRunning = false;

  void _performSecurityCheck() async {
    if (_securityCheckRunning) return;
    _securityCheckRunning = true;
    final licenceProvider = Provider.of<LicenceProvider>(context, listen: false);
    // Vérification auprès du serveur (licence supprimée ou expirée pendant l'utilisation)
    bool isExpired;
    try {
      isExpired = await licenceProvider.mustBlockAccess();
    } finally {
      _securityCheckRunning = false;
    }

    if (isExpired) {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LicenceRegistrationScreen()),
          (route) => false,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Données : serveur, tâches, favoris
  // ---------------------------------------------------------------------------
  Future<void> _chargerFavoris() async {
    final f = await AccueilFavoris.load();
    if (!mounted) return;
    setState(() => _favoris = f);
  }

  Future<bool> _verifierServeur() async {
    if (widget.serverCheck != null) {
      try {
        return await widget.serverCheck!();
      } catch (_) {
        return false;
      }
    }
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.dio.get('/officine').timeout(const Duration(seconds: 12));
      return true;
    } on DioException catch (e) {
      // Une réponse (même 401 / 500) prouve que l'application Prestige répond ; 404 : pas Prestige.
      final code = e.response?.statusCode;
      return code != null && code != 404;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _essayer(Future<void> Function() f) async {
    try {
      await f();
      return null;
    } catch (e) {
      return '$e';
    }
  }

  Future<List<(VenteMenu, PendingSale)>> _lireInterrompues() async {
    // Seule la nouvelle version des ventes mémorise (et propose de reprendre) la vente en cours.
    if (!VentesVersion.useNew.value) return const [];
    final out = <(VenteMenu, PendingSale)>[];
    for (final m in VenteMenu.values) {
      final p = await PendingSaleStore.load(m);
      if (p != null) out.add((m, p));
    }
    return out;
  }

  bool _rafraichissement = false;

  /// Vérifie le serveur et recharge les compteurs (préventes, BL à pointer, ventes interrompues).
  Future<void> _actualiser() async {
    if (_rafraichissement) return;
    _rafraichissement = true;
    _dernierRetour = DateTime.now();
    setState(() {
      _chargement = true;
      _serveur = EtatServeur.verification;
    });
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final serveurF = _verifierServeur();
    final preventesF = _essayer(() => _saleProvider.fetchPreventes());
    final blF = _essayer(() => _blProvider.fetchBonsLivraison(dtStart: today, dtEnd: today, query: ''));
    final interrompuesF = _lireInterrompues();
    final serveurOk = await serveurF;
    final errPreventes = await preventesF;
    final errBl = await blF;
    final interrompues = await interrompuesF;
    _rafraichissement = false;
    if (!mounted) return;
    setState(() {
      _chargement = false;
      _majTaches = DateTime.now();
      _serveur = serveurOk ? EtatServeur.connecte : EtatServeur.horsLigne;
      _interrompues = interrompues;
      // Une panne de la liste des préventes ressemble à « aucune » : on s'appuie sur le serveur.
      if (errPreventes != null || !serveurOk) {
        _preventes = null;
        _preventeAncienne = null;
        _erreurPreventes = errPreventes != null ? 'Préventes non chargées : $errPreventes' : 'Préventes non vérifiées : serveur injoignable';
      } else {
        final list = _saleProvider.preventes;
        _preventes = list.length;
        _erreurPreventes = null;
        _preventeAncienne = list.isEmpty
            ? null
            : 'La plus ancienne : ${list.last.heure}${list.last.userFullName.trim().isEmpty ? '' : ' (${list.last.userFullName.trim()})'}';
      }
      final blError = errBl ?? _blProvider.loadError;
      if (blError != null) {
        _bl = null;
        _erreurBl = 'BL non chargés : $blError';
      } else {
        _bl = _blProvider.bonsLivraison.where((b) => b.statutTraitement != "TERMINE").length;
        _erreurBl = null;
      }
    });
  }

  DateTime _dernierRetour = DateTime.fromMillisecondsSinceEpoch(0);

  /// Au retour sur l'accueil : favoris relus, serveur et compteurs revérifiés (au plus toutes les 30 s).
  void _apresRetour() {
    if (!mounted) return;
    _chargerFavoris();
    if (DateTime.now().difference(_dernierRetour) > const Duration(seconds: 30)) _actualiser();
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------
  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _apresRetour();
  }

  /// Ouvre un menu (code administrateur d'abord pour les menus protégés, comme à l'origine).
  Future<void> _ouvrir(AccueilMenu m) async {
    if (m.protege) {
      final ok = await (widget.askPin ?? PinCodeDialog.show)(context);
      if (!ok || !mounted) return;
    }
    await _push(m.screen());
  }

  List<AccueilMenu> _visibles(SettingsProvider s) {
    final hidden = s.hiddenMenuIds.toSet();
    return orderedMenus(s.menuOrder).where((m) => !hidden.contains(m.id)).toList();
  }

  void _rechercher(List<AccueilMenu> visibles, {String? code}) {
    _push(RechercheGlobaleScreen(
      menus: visibles,
      initialCode: code,
      scanner: widget.scanner,
      onOpenMenu: _ouvrir,
    ));
  }

  Future<void> _scanner(List<AccueilMenu> visibles) async {
    final code = await (widget.scanner ?? scannerParDefaut)(context);
    if (!mounted || code == null || code.trim().isEmpty) return;
    _rechercher(visibles, code: code);
  }

  Future<void> _organiser() async {
    await _push(OrganiserAccueilScreen(askPin: widget.askPin));
  }

  Future<void> _deconnexion() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text('Vous devrez saisir à nouveau votre identifiant et votre mot de passe.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Se déconnecter')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // Comme l'accueil d'origine.
    Provider.of<AuthProvider>(context, listen: false).logout();
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  // ---------------------------------------------------------------------------
  // Tâches
  // ---------------------------------------------------------------------------
  CaisseProvider? _caisse(BuildContext context) {
    try {
      return Provider.of<CaisseProvider>(context);
    } catch (_) {
      return null;
    }
  }

  List<_Tache> _taches(BuildContext context, Set<String> visibles) {
    final out = <_Tache>[];
    if (_erreurPreventes != null) {
      out.add(_Tache(titre: 'Préventes à encaisser', detail: _erreurPreventes, icon: Icons.cloud_off, couleur: _rouge, action: 'Réessayer', onTap: _actualiser, erreur: true));
    } else if ((_preventes ?? 0) > 0) {
      out.add(_Tache(
        titre: '$_preventes prévente(s) à encaisser',
        detail: _preventeAncienne,
        nombre: _preventes,
        icon: Icons.history_toggle_off,
        couleur: Pal.amber,
        action: 'Encaisser',
        onTap: () => _push(VentesVersion.preVente(initialTabIndex: 2)),
      ));
    }
    if (_erreurBl != null) {
      out.add(_Tache(titre: 'BL à pointer', detail: _erreurBl, icon: Icons.cloud_off, couleur: _rouge, action: 'Réessayer', onTap: _actualiser, erreur: true));
    } else if ((_bl ?? 0) > 0) {
      out.add(_Tache(
        titre: '$_bl BL à pointer',
        detail: 'Bons de livraison du jour',
        nombre: _bl,
        icon: Icons.checklist,
        couleur: Pal.blue,
        action: 'Ouvrir',
        onTap: () => _push(const BlListScreen(initialFilter: 'A_TRAITER')),
      ));
    }
    for (final (menu, sale) in _interrompues) {
      final m = accueilMenuById[switch (menu) {
        VenteMenu.prevente => 'prevente',
        VenteMenu.assurance => 'assurance',
        VenteMenu.carnet => 'carnet',
      }]!;
      final details = [
        m.short,
        if (sale.reference.trim().isNotEmpty) sale.reference.trim(),
        if (sale.total > 0) '${Constants.formatNumber(sale.total)} F',
      ].join(' · ');
      out.add(_Tache(titre: 'Vente interrompue', detail: details, icon: Icons.pause_circle_outline, couleur: _rouge, action: 'Reprendre', onTap: () => _push(m.screen())));
    }
    // Caisse : seulement si l'état est déjà connu (aucun appel supplémentaire).
    final caisse = _caisse(context);
    if (caisse != null && caisse.ouvertureData != null && visibles.contains('caisse')) {
      final ouverte = caisse.isCaisseOuverte;
      out.add(_Tache(
        titre: ouverte ? 'Caisse ouverte' : 'Caisse fermée',
        detail: 'Gestion caisse',
        icon: Icons.calculate,
        couleur: ouverte ? Pal.green : Pal.muted,
        action: ouverte ? '✓' : 'Ouvrir',
        onTap: () => _ouvrir(accueilMenuById['caisse']!),
        info: true,
      ));
    }
    return out;
  }

  int _nombreTaches(List<_Tache> t) => t.where((x) => !x.info && !x.erreur).length;

  Map<String, int> get _pastilles => {
        if ((_preventes ?? 0) > 0) 'prevente': _preventes!,
        if ((_bl ?? 0) > 0) 'bl_control': _bl!,
      };

  String? _sousTitre(String id) => switch (id) {
        'prevente' when (_preventes ?? 0) > 0 => '$_preventes prévente(s) à encaisser',
        'bl_control' when (_bl ?? 0) > 0 => '$_bl BL à pointer',
        _ => null,
      };

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final visibles = _visibles(settings);
    final idsVisibles = visibles.map((m) => m.id).toSet();
    final familles = menusByFamille(settings.menuOrder, settings.hiddenMenuIds);
    final taches = _taches(context, idsVisibles);
    final nb = _nombreTaches(taches);

    final Widget corps;
    if (_tab == 1) {
      corps = _ongletTaches(taches);
    } else {
      corps = switch (style) {
        ListPresentation.dashboard => _presentationA(visibles, familles, taches),
        ListPresentation.compact => _presentationB(visibles, familles, taches),
        ListPresentation.guided => _presentationC(visibles, familles),
      };
    }

    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _tab != 0) setState(() => _tab = 0);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: style == ListPresentation.compact && _tab == 0 ? Colors.white : Pal.page,
        body: corps,
        bottomNavigationBar: NavigationBar(
          height: 64,
          selectedIndex: _tab == 0 ? 0 : 2,
          indicatorColor: const Color(0xFFDCE6F2),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) {
            switch (i) {
              case 0:
                setState(() => _tab = 0);
              case 1:
                _scanner(visibles);
              case 2:
                setState(() => _tab = 1);
              case 3:
                _push(InterfaceVersion.settings());
            }
          },
          destinations: [
            const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Accueil'),
            const NavigationDestination(icon: Icon(Icons.qr_code_scanner), label: 'Scanner'),
            NavigationDestination(
              icon: Badge(isLabelVisible: nb > 0, label: Text('$nb'), child: const Icon(Icons.task_alt)),
              label: 'Tâches',
            ),
            const NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Réglages'),
          ],
        ),
      ),
    );
  }

  // --- Éléments communs ---

  String _date() {
    final now = DateTime.now();
    try {
      return DateFormat('EEE d MMMM', 'fr_FR').format(now);
    } catch (_) {
      return DateFormat('dd/MM/yyyy').format(now);
    }
  }

  List<Widget> _actions(Color c) => [
        PresentationMenuButton(value: style, onChanged: _setStyle, color: c),
        PopupMenuButton<String>(
          tooltip: 'Plus d\'actions',
          icon: Icon(Icons.more_vert, color: c),
          onSelected: (v) {
            switch (v) {
              case 'actualiser':
                _actualiser();
              case 'organiser':
                _organiser();
              case 'deconnexion':
                _deconnexion();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'actualiser', child: ListTile(leading: Icon(Icons.refresh), title: Text('Actualiser'), contentPadding: EdgeInsets.zero)),
            PopupMenuItem(value: 'organiser', child: ListTile(leading: Icon(Icons.dashboard_customize), title: Text('Organiser l\'accueil'), contentPadding: EdgeInsets.zero)),
            PopupMenuItem(value: 'deconnexion', child: ListTile(leading: Icon(Icons.logout), title: Text('Se déconnecter'), contentPadding: EdgeInsets.zero)),
          ],
        ),
      ];

  /// Pastille d'état du serveur (sur fond bleu si [dark]).
  Widget _pastilleServeur({bool dark = true, bool court = false}) {
    final (texte, couleur) = switch (_serveur) {
      EtatServeur.verification => ('Vérification…', const Color(0xFF94A3B8)),
      EtatServeur.connecte => (court ? 'En ligne' : 'Serveur connecté', const Color(0xFF22C55E)),
      EtatServeur.horsLigne => ('Hors ligne', const Color(0xFFEF4444)),
    };
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.14) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: couleur, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(texte,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: dark ? Colors.white : Pal.ink, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
    if (_serveur != EtatServeur.horsLigne) return pill;
    return Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      pill,
      SizedBox(
        height: 36,
        child: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: dark ? Colors.white : Pal.navy, minimumSize: const Size(44, 36)),
          onPressed: _actualiser,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Réessayer'),
        ),
      ),
    ]);
  }

  /// Licence : seulement si elle expire dans moins de 30 jours (ambre, rouge à 7 jours).
  Widget _pastilleLicence() => Consumer<LicenceProvider>(builder: (context, provider, _) {
        if (provider.status != LicenceStatus.valid || provider.licence == null) return const SizedBox.shrink();
        final days = provider.remainingDays;
        if (days > 30) return const SizedBox.shrink();
        final urgent = days <= 7;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: urgent ? const Color(0xFFDC2626) : Pal.amber, borderRadius: BorderRadius.circular(999)),
          child: Text('Licence : $days jour(s)',
              style: TextStyle(color: urgent ? Colors.white : Pal.onAmber, fontSize: 13, fontWeight: FontWeight.w600)),
        );
      });

  Widget _champRecherche(List<AccueilMenu> visibles, {required bool dark, String hint = 'Rechercher un menu ou un produit'}) => Material(
        color: dark ? Colors.white : Pal.page,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _rechercher(visibles),
          child: SizedBox(
            height: 50,
            child: Row(children: [
              const SizedBox(width: 12),
              const Icon(Icons.search, color: Pal.muted),
              const SizedBox(width: 10),
              Expanded(child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Pal.muted, fontSize: 15))),
              IconButton(tooltip: 'Scanner un code', icon: const Icon(Icons.qr_code_scanner, color: Pal.navy), onPressed: () => _scanner(visibles)),
            ]),
          ),
        ),
      );

  /// Marge latérale (tablette) : contenu centré à la largeur maximale ; 0 sur téléphone.
  double get _inset => Responsive.sideInset(context);

  Widget _titreSection(String t, {EdgeInsets padding = const EdgeInsets.fromLTRB(20, 18, 20, 8)}) => Padding(
        padding: padding + EdgeInsets.symmetric(horizontal: _inset),
        child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Pal.muted)),
      );

  Widget _pastilleNombre(int n) => Container(
        constraints: const BoxConstraints(minWidth: 22),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: const Color(0xFFDC2626), borderRadius: BorderRadius.circular(999)),
        child: Text('$n', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      );

  Widget _toutEstAJour() => const SoftCard(
        child: Row(children: [
          Icon(Icons.check_circle, color: Pal.green),
          SizedBox(width: 10),
          Expanded(child: Text('Tout est à jour ✓', style: TextStyle(fontWeight: FontWeight.w600, color: Pal.ink))),
        ]),
      );

  /// Cartes courtes de « À faire maintenant » (présentations A et B).
  List<Widget> _aFaire(List<_Tache> taches) {
    if (_chargement && _majTaches == null) {
      return const [
        SoftCard(
          child: Row(children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Expanded(child: Text('Chargement des tâches…', style: TextStyle(color: Pal.muted))),
          ]),
        ),
      ];
    }
    final out = <Widget>[];
    for (final t in taches) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: t.onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  SizedBox(
                    width: 36,
                    child: t.nombre != null
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('${t.nombre}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: t.couleur)),
                          )
                        : Icon(t.icon, color: t.couleur),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.nombre != null ? t.titre.replaceFirst('${t.nombre} ', '') : t.titre,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, color: Pal.ink, fontWeight: FontWeight.w500)),
                      if (t.erreur && t.detail != null)
                        Text(t.detail!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _rouge)),
                    ]),
                  ),
                  t.erreur ? Text(t.action, style: const TextStyle(color: Pal.navy, fontWeight: FontWeight.w600)) : const Icon(Icons.chevron_right, color: Pal.muted),
                ]),
              ),
            ),
          ),
        ),
      ));
    }
    if (_nombreTaches(taches) == 0 && !taches.any((t) => t.erreur)) out.add(_toutEstAJour());
    return out;
  }

  // --- Présentation A : tableau de bord ---

  Widget _presentationA(List<AccueilMenu> visibles, Map<MenuFamille, List<AccueilMenu>> familles, List<_Tache> taches) {
    final auth = Provider.of<AuthProvider>(context);
    final officine = auth.officine?.nomComplet.trim() ?? '';
    final nomUser = (auth.user?.fullName.trim().isNotEmpty ?? false) ? auth.user!.fullName.trim() : (auth.officine?.fullName.trim() ?? '');
    final role = auth.isAdmin ? 'Administrateur' : 'Utilisateur';
    final idsVisibles = visibles.map((m) => m.id).toSet();
    final favoris = _favoris.where(idsVisibles.contains).map((id) => accueilMenuById[id]!).toList();
    final width = MediaQuery.sizeOf(context).width;
    // Tablette : familles sur 6 (portrait) ou 8 colonnes (paysage), favoris sur 4, « À faire » sur 2.
    final taille = Responsive.of(context);
    final cols = switch (taille) {
      WindowClass.expanded => 8,
      WindowClass.medium => 6,
      WindowClass.compact => width < 330 ? 3 : 4,
    };
    final compact = taille == WindowClass.compact;
    final side = EdgeInsets.symmetric(horizontal: 16 + _inset);

    return RefreshIndicator(
      onRefresh: _actualiser,
      child: ListView(padding: EdgeInsets.zero, physics: const AlwaysScrollableScrollPhysics(), children: [
        NavyHeader(
          title: officine.isEmpty ? 'Prestige Mobile' : officine,
          subtitle: [if (nomUser.isNotEmpty) nomUser, role, _date()].join(' · '),
          actions: _actions(Colors.white),
          children: [
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [_pastilleServeur(), _pastilleLicence()]),
            _champRecherche(visibles, dark: true),
          ],
        ),
        _titreSection('À faire maintenant'),
        Padding(
            key: const ValueKey('accueil-a-faire'),
            padding: side,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: cardRows(_aFaire(taches), compact ? 1 : 2))),
        if (favoris.isNotEmpty) ...[
          _titreSection('Favoris'),
          Padding(
            padding: side,
            child: GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: compact ? 2 : 4, mainAxisExtent: 68, crossAxisSpacing: 10, mainAxisSpacing: 10),
              children: [for (final m in favoris) _tuileFavori(m)],
            ),
          ),
        ],
        for (final f in MenuFamille.values)
          if (familles[f]!.isNotEmpty) ...[
            _titreSection(f.label),
            Padding(
              padding: side,
              child: GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisExtent: 92, crossAxisSpacing: 8, mainAxisSpacing: 8),
                children: [for (final m in familles[f]!) _tuile(m)],
              ),
            ),
          ],
        if (visibles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Aucun menu affiché : utilisez « Organiser l\'accueil » (menu ⋮).', textAlign: TextAlign.center, style: TextStyle(color: Pal.muted)),
          ),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _tuileFavori(AccueilMenu m) {
    final n = _pastilles[m.id];
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _ouvrir(m),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: m.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(m.icon, color: m.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(m.short, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink)),
            ),
            if (n != null) _pastilleNombre(n),
            if (m.protege) const Icon(Icons.lock, size: 16, color: Pal.amber),
          ]),
        ),
      ),
    );
  }

  Widget _tuile(AccueilMenu m) {
    final n = _pastilles[m.id];
    return Tooltip(
      message: m.label,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _ouvrir(m),
          child: Stack(children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(m.icon, color: m.color, size: 30),
                  const SizedBox(height: 6),
                  Flexible(
                    child: Text(m.short,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Pal.ink)),
                  ),
                ]),
              ),
            ),
            if (n != null) Positioned(top: 4, right: 4, child: _pastilleNombre(n)),
            if (m.protege) const Positioned(top: 6, left: 6, child: Icon(Icons.lock, size: 14, color: Pal.amber)),
          ]),
        ),
      ),
    );
  }

  // --- Présentation B : liste compacte ---

  Widget _presentationB(List<AccueilMenu> visibles, Map<MenuFamille, List<AccueilMenu>> familles, List<_Tache> taches) {
    final auth = Provider.of<AuthProvider>(context);
    final officine = auth.officine?.nomComplet.trim() ?? '';
    final aFaire = taches.where((t) => !t.info).toList();
    return Column(children: [
      Container(
        color: Colors.white,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16 + _inset, 6, 4 + _inset, 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Prestige Mobile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Pal.navy)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    _pastilleServeur(dark: false),
                    if (officine.isNotEmpty) Text(officine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Pal.muted, fontSize: 13)),
                    _pastilleLicence(),
                  ]),
                ]),
              ),
              ..._actions(Pal.navy),
            ]),
          ),
        ),
      ),
      const Divider(height: 1, color: Pal.line),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _actualiser,
          child: ListView(padding: EdgeInsets.zero, physics: const AlwaysScrollableScrollPhysics(), children: [
            Padding(
                padding: EdgeInsets.fromLTRB(16 + _inset, 12, 16 + _inset, 4),
                child: _champRecherche(visibles, dark: false, hint: 'Rechercher un menu ou un produit')),
            if (aFaire.isNotEmpty) ...[
              _titreSection('À faire maintenant', padding: const EdgeInsets.fromLTRB(16, 14, 16, 6)),
              for (final t in aFaire)
                _ligne(
                  icon: t.icon,
                  couleur: t.couleur,
                  titre: t.titre,
                  detail: t.detail,
                  erreur: t.erreur,
                  onTap: t.onTap,
                ),
            ] else if (_majTaches != null)
              _ligne(icon: Icons.check_circle, couleur: Pal.green, titre: 'Tout est à jour ✓', onTap: null),
            for (final f in MenuFamille.values)
              if (familles[f]!.isNotEmpty) ...[
                _titreSection(f.label, padding: const EdgeInsets.fromLTRB(16, 16, 16, 6)),
                for (final m in familles[f]!)
                  _ligne(
                    icon: m.icon,
                    couleur: m.color,
                    titre: m.label,
                    detail: _sousTitre(m.id),
                    nombre: _pastilles[m.id],
                    protege: m.protege,
                    onTap: () => _ouvrir(m),
                  ),
              ],
            const SizedBox(height: 24),
          ]),
        ),
      ),
    ]);
  }

  Widget _ligne({
    required IconData icon,
    required Color couleur,
    required String titre,
    String? detail,
    int? nombre,
    bool protege = false,
    bool erreur = false,
    required VoidCallback? onTap,
  }) =>
      InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: EdgeInsets.symmetric(horizontal: 16 + _inset, vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: couleur, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(titre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Pal.ink)),
                  ),
                  if (protege) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.lock, size: 15, color: Pal.amber)),
                ]),
                if (detail != null)
                  Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: erreur ? _rouge : Pal.muted)),
              ]),
            ),
            if (nombre != null) ...[const SizedBox(width: 8), _pastilleNombre(nombre)],
            if (onTap != null) const Icon(Icons.chevron_right, color: Pal.muted),
          ]),
        ),
      );

  // --- Présentation C : guidée par métier ---

  Widget _presentationC(List<AccueilMenu> visibles, Map<MenuFamille, List<AccueilMenu>> familles) {
    final auth = Provider.of<AuthProvider>(context);
    final prenom = auth.user?.firstName.trim() ?? '';
    final ids = visibles.map((m) => m.id).toSet();
    List<AccueilMenu> parmi(List<String> l) => [for (final id in l) if (ids.contains(id)) accueilMenuById[id]!];

    final vendre = familles[MenuFamille.ventes]!;
    final encaisser = [
      if (ids.contains('prevente'))
        (titre: 'Préventes à encaisser', icon: Icons.history_toggle_off, onTap: () => _push(VentesVersion.preVente(initialTabIndex: 2))),
      for (final m in parmi(['caisse'])) (titre: m.label, icon: m.icon, onTap: () => _ouvrir(m)),
    ];
    final recevoir = familles[MenuFamille.reception]!;
    final stock = familles[MenuFamille.stock]!;

    String? compte(int? n, String libelle, String? erreur) =>
        erreur != null ? 'Compteur non vérifié' : (n == null ? null : '$n $libelle');

    final cartes = <Widget>[
      if (vendre.isNotEmpty)
        _grosseAction(Icons.receipt_long, const Color(0xFFB45309), 'Vendre', vendre.map((m) => m.short.toLowerCase()).take(3).join(', '),
            () => _feuille('Vendre', [for (final m in vendre) (titre: m.label, icon: m.icon, onTap: () => _ouvrir(m))])),
      if (encaisser.isNotEmpty)
        _grosseAction(Icons.payments, Pal.green, 'Encaisser', compte(_preventes, 'prévente(s) en attente', _erreurPreventes) ?? 'Préventes et caisse',
            () => encaisser.length == 1 ? encaisser.first.onTap() : _feuille('Encaisser', encaisser)),
      if (recevoir.isNotEmpty)
        _grosseAction(Icons.local_shipping, Pal.blue, 'Recevoir une livraison', compte(_bl, 'BL à pointer', _erreurBl) ?? 'Réception BL, contrôles, retours',
            () => _feuille('Recevoir une livraison', [for (final m in recevoir) (titre: m.label, icon: m.icon, onTap: () => _ouvrir(m))])),
      _grosseAction(Icons.search, const Color(0xFF7C3AED), 'Chercher un produit', 'Stock, prix, emplacement', () => _rechercher(visibles)),
      if (stock.isNotEmpty)
        _grosseAction(Icons.inventory_2, const Color(0xFFDC2626), 'Gérer le stock', stock.map((m) => m.short.toLowerCase()).take(3).join(', '),
            () => _feuille('Gérer le stock', [for (final m in stock) (titre: m.label, icon: m.icon, onTap: () => _ouvrir(m))])),
    ];

    return RefreshIndicator(
      onRefresh: _actualiser,
      child: ListView(padding: EdgeInsets.zero, physics: const AlwaysScrollableScrollPhysics(), children: [
        NavyHeader(
          title: prenom.isEmpty ? 'Bonjour' : 'Bonjour $prenom',
          subtitle: 'Que voulez-vous faire ?',
          rounded: false,
          actions: _actions(Colors.white),
          children: [
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [_pastilleServeur(court: true), _pastilleLicence()]),
          ],
        ),
        const SizedBox(height: 12),
        // Tablette : grandes actions sur 2 (portrait) ou 3 colonnes (paysage).
        if (Responsive.isCompact(context))
          for (final c in cartes) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: c)
        else
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16 + _inset),
            child: Column(children: cardRows([for (final c in cartes) Padding(padding: const EdgeInsets.only(bottom: 12), child: c)], Responsive.columns(context), gap: 12)),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16 + _inset, 0, 16 + _inset, 8),
          child: SizedBox(
            height: 52,
            child: OutlinedButton(
              style: outlineButton.copyWith(side: const WidgetStatePropertyAll(BorderSide(color: Pal.navy, width: 2))),
              onPressed: () => setState(() => _toutVoir = !_toutVoir),
              child: Text(_toutVoir ? 'Masquer la liste des menus' : 'Voir tous les menus'),
            ),
          ),
        ),
        if (_toutVoir)
          for (final f in MenuFamille.values)
            if (familles[f]!.isNotEmpty) ...[
              _titreSection(f.label, padding: const EdgeInsets.fromLTRB(16, 16, 16, 6)),
              Container(
                color: Colors.white,
                child: Column(children: [
                  for (final m in familles[f]!)
                    _ligne(
                      icon: m.icon,
                      couleur: m.color,
                      titre: m.label,
                      detail: _sousTitre(m.id),
                      nombre: _pastilles[m.id],
                      protege: m.protege,
                      onTap: () => _ouvrir(m),
                    ),
                ]),
              ),
            ],
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _grosseAction(IconData icon, Color couleur, String titre, String detail, VoidCallback onTap) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: couleur, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titre, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.ink)),
                  const SizedBox(height: 2),
                  Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Pal.muted)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Pal.muted),
            ]),
          ),
        ),
      );

  /// Choix d'un menu d'un métier (présentation C).
  void _feuille(String titre, List<({String titre, IconData icon, VoidCallback onTap})> choix) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(titre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.navy)),
            ),
            for (final c in choix)
              ListTile(
                minTileHeight: 56,
                leading: Icon(c.icon, color: Pal.navy),
                title: Text(c.titre),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(ctx).pop();
                  c.onTap();
                },
              ),
          ]),
        ),
      ),
    );
  }

  // --- Onglet Tâches ---

  Widget _ongletTaches(List<_Tache> taches) {
    final maj = _majTaches;
    return Column(children: [
      NavyHeader(
        title: 'Tâches',
        subtitle: _chargement ? 'Actualisation…' : (maj == null ? null : 'Actualisé à ${DateFormat('HH:mm').format(maj)}'),
        actions: [IconButton(tooltip: 'Actualiser', icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _chargement ? null : _actualiser)],
        children: [Align(alignment: Alignment.centerLeft, child: _pastilleServeur())],
      ),
      if (_chargement) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _actualiser,
          child: ListView(
            padding: EdgeInsets.fromLTRB(16 + _inset, 16, 16 + _inset, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              for (final t in taches) Padding(padding: const EdgeInsets.only(bottom: 12), child: _carteTache(t)),
              if (_nombreTaches(taches) == 0 && !taches.any((t) => t.erreur) && maj != null) _toutEstAJour(),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _carteTache(_Tache t) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: t.onTap,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 6, color: t.couleur),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.titre, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.ink)),
                        if (t.detail != null)
                          Text(t.detail!, style: TextStyle(fontSize: 13, color: t.erreur ? _rouge : Pal.muted)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: t.couleur.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                      child: Text(t.action, style: TextStyle(fontWeight: FontWeight.bold, color: t.erreur ? _rouge : Pal.navy)),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      );
}
