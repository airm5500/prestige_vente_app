// lib/accueil/organiser_accueil_screen.dart
// Organiser l'accueil : ordre par famille (glisser), favoris (étoile, 4 max), menus masqués (œil).
// Ordre et menus masqués : SettingsProvider.menuOrder / hiddenMenuIds (mêmes clés que
// « Organiser le menu d'accueil » d'origine : l'organisation actuelle est reprise).
// Protégé par le code administrateur (PinCodeDialog), comme l'original.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:prestige_vente_app/accueil/accueil_menus.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

class OrganiserAccueilScreen extends StatefulWidget {
  /// Vrai si le code administrateur vient d'être demandé par l'écran appelant
  /// (sinon l'écran le demande lui-même à l'ouverture).
  final bool alreadyAuthorized;

  /// Vérification du code (tests) ; sinon PinCodeDialog.show.
  final Future<bool> Function(BuildContext context)? askPin;
  const OrganiserAccueilScreen({super.key, this.alreadyAuthorized = false, this.askPin});

  @override
  State<OrganiserAccueilScreen> createState() => _OrganiserAccueilScreenState();
}

class _OrganiserAccueilScreenState extends State<OrganiserAccueilScreen> {
  late bool _authorized = widget.alreadyAuthorized;

  /// Ordre de chaque famille (tous les menus, masqués compris).
  final Map<MenuFamille, List<AccueilMenu>> _familles = {};
  final Set<String> _hidden = {};
  final List<String> _favoris = [];
  bool _favorisCharges = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initData();
    AccueilFavoris.load().then((f) {
      if (!mounted) return;
      setState(() {
        _favoris
          ..clear()
          ..addAll(f);
        _favorisCharges = true;
      });
    });
    if (!_authorized) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _demanderCode());
    }
  }

  Future<void> _demanderCode() async {
    if (!mounted) return;
    final ok = await (widget.askPin ?? PinCodeDialog.show)(context);
    if (!mounted) return;
    if (ok) {
      setState(() => _authorized = true);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _initData() {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    _hidden
      ..clear()
      ..addAll(settings.hiddenMenuIds.where(accueilMenuById.containsKey));
    _familles
      ..clear()
      ..addAll(menusByFamille(settings.menuOrder, const [], withHidden: true));
  }

  void _parDefaut() {
    setState(() {
      _familles
        ..clear()
        ..addAll(menusByFamille(const [], const [], withHidden: true));
      _hidden.clear();
      _favoris
        ..clear()
        ..addAll(AccueilFavoris.parDefaut);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Organisation par défaut : touchez « Enregistrer » pour l\'appliquer.')),
    );
  }

  Future<void> _enregistrer() async {
    if (_busy) return;
    setState(() => _busy = true);
    final order = [for (final f in MenuFamille.values) ..._familles[f]!.map((m) => m.id)];
    try {
      await Provider.of<SettingsProvider>(context, listen: false).saveMenuConfig(order, _hidden.toList());
      await AccueilFavoris.save(_favoris);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : $e'), backgroundColor: Colors.red));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _toggleFavori(AccueilMenu m) {
    setState(() {
      if (_favoris.contains(m.id)) {
        _favoris.remove(m.id);
      } else if (_favoris.length >= AccueilFavoris.max) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('4 favoris au maximum : retirez d\'abord une étoile.')));
      } else {
        _favoris.add(m.id);
      }
    });
  }

  void _toggleMasque(AccueilMenu m) {
    setState(() {
      if (!_hidden.remove(m.id)) _hidden.add(m.id);
    });
  }

  /// Glisser dans une famille : seuls les menus non favoris y sont affichés ; ils échangent leurs places.
  void _reorderFamille(MenuFamille f, int oldIndex, int newIndex) {
    setState(() {
      final all = _familles[f]!;
      final slots = <int>[];
      for (var i = 0; i < all.length; i++) {
        if (!_favoris.contains(all[i].id)) slots.add(i);
      }
      final visible = [for (final i in slots) all[i]];
      if (newIndex > oldIndex) newIndex -= 1;
      final item = visible.removeAt(oldIndex);
      visible.insert(newIndex, item);
      for (var k = 0; k < slots.length; k++) {
        all[slots[k]] = visible[k];
      }
    });
  }

  void _reorderFavoris(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final id = _favoris.removeAt(oldIndex);
      _favoris.insert(newIndex, id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pal.page,
      body: Column(children: [
        const NavyHeader(title: 'Organiser l\'accueil', subtitle: 'Glisser pour ordonner · ★ favori · œil : masquer'),
        Expanded(
          child: ContentWidth(
            child: !_authorized || !_favorisCharges
                ? const Center(child: Icon(Icons.lock_outline, size: 48, color: Pal.muted))
                : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                    _titre('Favoris (${_favoris.length}/${AccueilFavoris.max})'),
                    if (_favoris.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Aucun favori : touchez l\'étoile d\'un menu.', style: TextStyle(color: Pal.muted)),
                      )
                    else
                      _liste(
                        [for (final id in _favoris) accueilMenuById[id]!],
                        _reorderFavoris,
                      ),
                    for (final f in MenuFamille.values)
                      if (_familles[f]!.any((m) => !_favoris.contains(m.id))) ...[
                        _titre(f.label),
                        _liste(
                          _familles[f]!.where((m) => !_favoris.contains(m.id)).toList(),
                          (o, n) => _reorderFamille(f, o, n),
                        ),
                      ],
                  ]),
          ),
        ),
      ]),
      bottomNavigationBar: !_authorized
          ? null
          : BottomBarWidth(
              color: Colors.transparent,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(style: outlineButton, onPressed: _busy ? null : _parDefaut, child: const Text('Par défaut')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          style: navyButton,
                          onPressed: _busy || !_favorisCharges ? null : _enregistrer,
                          child: _busy
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Enregistrer'),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
    );
  }

  Widget _titre(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Pal.muted)),
      );

  Widget _liste(List<AccueilMenu> menus, void Function(int, int) onReorder) => ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorder: onReorder,
        children: [for (var i = 0; i < menus.length; i++) _ligne(menus[i], i)],
      );

  Widget _ligne(AccueilMenu m, int index) {
    final masque = _hidden.contains(m.id);
    final favori = _favoris.contains(m.id);
    return Padding(
      key: ValueKey('org_${m.id}'),
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: masque ? const Color(0xFFEDEFF3) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: Row(children: [
          ReorderableDragStartListener(
            index: index,
            child: const SizedBox(width: 44, height: 52, child: Icon(Icons.drag_indicator, color: Pal.muted)),
          ),
          Icon(m.icon, color: masque ? Colors.grey : m.color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              masque ? '${m.label} (masqué)' : m.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: masque ? Colors.grey : Pal.ink,
                decoration: masque ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (m.protege) const Icon(Icons.lock, size: 16, color: Pal.amber),
          IconButton(
            tooltip: favori ? 'Retirer des favoris' : 'Mettre en favori',
            icon: Icon(favori ? Icons.star : Icons.star_border, color: favori ? Pal.amber : Pal.muted),
            onPressed: () => _toggleFavori(m),
          ),
          IconButton(
            tooltip: masque ? 'Afficher' : 'Masquer',
            icon: Icon(masque ? Icons.visibility_off : Icons.visibility, color: masque ? Colors.grey : Pal.navy),
            onPressed: () => _toggleMasque(m),
          ),
        ]),
      ),
    );
  }
}
