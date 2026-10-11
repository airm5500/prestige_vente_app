// lib/parametres/parametres_screen.dart
// Nouveaux réglages : page d'entrée par rubriques (recherche, résumé, cadenas = code administrateur
// demandé une fois par visite). Aussi ouverte AVANT la connexion (démarrage, connexion, licence) :
// les rubriques qui demandent un utilisateur connecté sont alors grisées avec une explication.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/accueil/organiser_accueil_screen.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_reglages_page.dart';
import 'package:prestige_vente_app/images/images_reglages.dart';
import 'package:prestige_vente_app/images/images_reglages_page.dart';
import 'package:prestige_vente_app/parametres/connexion_page.dart';
import 'package:prestige_vente_app/parametres/hors_ligne_page.dart';
import 'package:prestige_vente_app/parametres/parametres_logic.dart';
import 'package:prestige_vente_app/parametres/parametres_services.dart';
import 'package:prestige_vente_app/parametres/parametres_widgets.dart';
import 'package:prestige_vente_app/parametres/rubriques_pages.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/screens/splash_screen.dart';
import 'package:prestige_vente_app/services/fingerprint_service.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/ventes/ventes_version.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';
import 'package:provider/provider.dart';

class ParametresScreen extends StatefulWidget {
  /// Remplaçables pour les tests.
  final ParametresServices services;
  const ParametresScreen({super.key, this.services = const ParametresServices()});

  @override
  State<ParametresScreen> createState() => _ParametresScreenState();
}

class _ParametresScreenState extends State<ParametresScreen> {
  final _search = TextEditingController();
  bool _unlocked = false; // code administrateur vérifié pendant cette visite
  ListPresentation _presentation = ListPresentation.dashboard;
  PointageSettings? _pointage;

  /// Tablette paysage : rubrique affichée à droite de la liste (null = aucune).
  Rubrique? _selected;

  ParametresServices get _sv => widget.services;
  late final PointageRepository _pointageRepo = _sv.pointageRepository ?? LocalPointageRepository();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _reloadSummaries();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reloadSummaries() async {
    final p = await PresentationPrefs.load();
    await SearchModePrefs.load();
    PointageSettings? ps;
    try {
      ps = await _pointageRepo.loadSettings();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _presentation = p;
      _pointage = ps;
    });
  }

  Future<bool> _adminOk() async {
    if (_unlocked) return true;
    final ok = await (_sv.adminCheck ?? PinCodeDialog.show)(context);
    if (!mounted) return false;
    if (ok) setState(() => _unlocked = true);
    return ok;
  }

  /// Raison pour laquelle une rubrique n'est pas accessible (null = accessible).
  String? _unavailable(Rubrique r, AuthProvider auth) => switch (r) {
        Rubrique.equipe when auth.user == null => 'Disponible après la connexion',
        Rubrique.securite when auth.user == null => 'Disponible après la connexion (compte administrateur)',
        Rubrique.securite when !auth.isAdmin => 'Réservé au compte administrateur',
        _ => null,
      };

  String _summary(Rubrique r, SettingsProvider s, LicenceProvider l) => switch (r) {
        Rubrique.connexion => ParametresSummary.connexion(s),
        Rubrique.ventes => ParametresSummary.ventes(s, newSales: VentesVersion.useNew.value),
        Rubrique.impression => ParametresSummary.impression(s),
        Rubrique.stock => ParametresSummary.stock(s),
        Rubrique.horsLigne => horsLigneSummary(),
        Rubrique.apparence => ParametresSummary.apparence(_presentation, search: SearchModePrefs.current),
        Rubrique.equipe => _pointage == null ? 'Méthode, employés, rapport' : pointageSummary(_pointage!),
        Rubrique.securite => 'Code PIN administrateur',
        Rubrique.licence => ParametresSummary.licence(l),
        Rubrique.borne => borneSummary(BorneReglages.courant.value),
        Rubrique.images => imagesSummary(ImagesReglages.courant.value),
      };

  static IconData _icon(Rubrique r) => switch (r) {
        Rubrique.connexion => Icons.language,
        Rubrique.ventes => Icons.receipt_long,
        Rubrique.impression => Icons.print,
        Rubrique.stock => Icons.inventory_2,
        Rubrique.horsLigne => Icons.cloud_off,
        Rubrique.apparence => Icons.palette,
        Rubrique.equipe => Icons.groups,
        Rubrique.securite => Icons.shield,
        Rubrique.licence => Icons.badge,
        Rubrique.borne => Icons.storefront,
        Rubrique.images => Icons.image_outlined,
      };

  Future<void> _openOrganiser(BuildContext ctx) async {
    if (!await _adminOk() || !ctx.mounted) return;
    await Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => (_sv.organiserAccueil ?? () => const OrganiserAccueilScreen(alreadyAuthorized: true))()));
  }

  void _afterServerSaved(BuildContext ctx) {
    if (_sv.afterServerSaved != null) return _sv.afterServerSaved!(ctx);
    // Comme la Configuration d'origine : l'écran de démarrage recharge l'ApiService et la licence.
    final nav = Navigator.of(ctx);
    if (!EmbeddedPane.of(ctx)) nav.pop(); // tablette paysage : la page est dans les réglages
    nav.pushReplacement(MaterialPageRoute(builder: (_) => const SplashScreen()));
  }

  Future<void> _open(Rubrique r) async {
    final auth = context.read<AuthProvider>();
    final reason = _unavailable(r, auth);
    if (reason != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${r.title} : $reason.')));
      return;
    }
    if (r.locked && !await _adminOk()) return;
    if (!mounted) return;
    if (Responsive.isExpanded(context)) {
      // Tablette paysage : la rubrique s'affiche à droite, la liste reste visible.
      setState(() => _selected = r);
      _reloadSummaries();
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _page(r)));
    if (mounted) _reloadSummaries();
  }

  Widget _page(Rubrique r) => switch (r) {
      Rubrique.connexion => ConnexionPage(adminVerified: _unlocked, afterSaved: _afterServerSaved),
      Rubrique.ventes => const VentesPage(),
      Rubrique.impression => ImpressionPage(printTest: _sv.printTestTicket ?? imprimerTicketEssai),
      Rubrique.stock => const StockPage(),
      Rubrique.horsLigne => const HorsLignePage(),
      Rubrique.apparence => ApparencePage(initial: _presentation, openOrganiser: _openOrganiser),
      Rubrique.equipe => EquipePage(repository: _pointageRepo),
      Rubrique.securite => const SecuritePage(),
      Rubrique.licence => LicencePage(hardwareInfo: _sv.hardwareInfo ?? FingerprintService.hardwareInfo),
      Rubrique.borne => const BornePage(),
      Rubrique.images => const ImagesPage(),
    };

  /// Panneau de droite (tablette paysage) : rubrique choisie, sinon une invitation.
  Widget _detail() {
    final r = _selected;
    if (r == null) {
      return const ColoredBox(
        color: Pal.page,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.tune, size: 48, color: Color(0xFF9AA8BC)),
            SizedBox(height: 10),
            Text('Choisissez une rubrique à gauche', style: TextStyle(fontSize: 15, color: Pal.muted)),
          ]),
        ),
      );
    }
    return EmbeddedPane(child: KeyedSubtree(key: ValueKey(r), child: _page(r)));
  }

  Future<void> _logout() async {
    final ok = await confirmer(context,
        title: 'Se déconnecter ?', message: 'Vous reviendrez à l\'écran de connexion.', action: 'Se déconnecter', danger: true);
    if (!ok || !mounted) return;
    // Comme l'accueil d'origine : déconnexion puis écran de connexion.
    unawaited(context.read<AuthProvider>().logout());
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  Widget _row(Rubrique r, String summary, String? reason, {bool selected = false}) {
    final enabled = reason == null;
    final unlocked = r.locked && _unlocked;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: selected ? const Color(0xFFE3ECF7) : Colors.white,
        child: InkWell(
          key: Key('rubrique_${r.name}'),
          onTap: () => _open(r),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFFE3ECF7), borderRadius: BorderRadius.circular(11)),
                child: Icon(_icon(r), color: Pal.navy, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(r.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Pal.ink)),
                    ),
                    if (r.locked)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(unlocked ? Icons.lock_open : Icons.lock,
                            key: Key('cadenas_${r.name}'), size: 15, color: unlocked ? Pal.green : const Color(0xFFB45309)),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Text(reason ?? summary,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Pal.muted),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final licence = context.watch<LicenceProvider>();
    final auth = context.watch<AuthProvider>();
    final connected = auth.user != null;
    final user = auth.user;
    final query = _search.text;
    final split = Responsive.isExpanded(context);
    final rows = <Widget>[];
    for (final r in Rubrique.values) {
      final summary = _summary(r, settings, licence);
      if (!rubriqueMatches(r, summary, query)) continue;
      rows.add(_row(r, summary, _unavailable(r, auth), selected: split && r == _selected));
    }
    final showLogout = connected && rubriqueMatchesText('se deconnecter deconnexion quitter sortir', query);
    final list = _list(rows, connected, showLogout, query);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Pal.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Réglages', style: TextStyle(fontWeight: FontWeight.bold, color: Pal.navy, fontSize: 20)),
          Text(
            connected
                ? [
                    '${user!.firstName} ${user.lastName}'.trim(),
                    if (auth.officine?.nomComplet.isNotEmpty ?? false) auth.officine!.nomComplet,
                  ].where((e) => e.isNotEmpty).join(' · ')
                : 'Non connecté',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: Pal.muted),
          ),
        ]),
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Pal.line)),
      ),
      // Tablette : liste centrée (portrait) ; rubriques à gauche et contenu à droite (paysage).
      body: split
          ? ListDetail(list: list, detail: KeyedSubtree(key: const ValueKey('reglages-detail'), child: _detail()))
          : ContentWidth(child: list),
    );
  }

  Widget _list(List<Widget> rows, bool connected, bool showLogout, String query) => SafeArea(
        top: false,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: TextField(
                key: const Key('recherche_reglage'),
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Rechercher un réglage',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(tooltip: 'Effacer', icon: const Icon(Icons.close), onPressed: _search.clear),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC5D0DE))),
                ),
              ),
            ),
            if (!connected)
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: InfoBanner('Vous n\'êtes pas connecté : la connexion au serveur, l\'impression, les ventes, le stock '
                    'et l\'apparence restent réglables. Les rubriques grisées seront disponibles après la connexion.'),
              ),
            ...rows,
            if (showLogout)
              Material(
                color: Colors.white,
                child: InkWell(
                  key: const Key('se_deconnecter'),
                  onTap: _logout,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 60),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(11)),
                        child: const Icon(Icons.power_settings_new, color: Color(0xFFDC2626), size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Se déconnecter',
                            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: Color(0xFFDC2626))),
                      ),
                    ]),
                  ),
                ),
              ),
            if (rows.isEmpty && !showLogout)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(children: [
                  const Icon(Icons.search_off, size: 40, color: Pal.muted),
                  const SizedBox(height: 8),
                  Text('Aucun réglage pour « ${query.trim()} »', textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted)),
                  TextButton(onPressed: _search.clear, child: const Text('Effacer la recherche')),
                ]),
              ),
          ],
        ),
      );
}
