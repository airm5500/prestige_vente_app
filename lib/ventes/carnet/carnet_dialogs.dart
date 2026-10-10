// lib/ventes/carnet/carnet_dialogs.dart
// Création d'un client carnet en page (A / B / C) : le carnet choisi est affiché pour relecture,
// validation par « CRÉER LE CLIENT » ; création d'un ayant droit (dialogue).
// Nom → strFIRSTNAME, Prénom → strLASTNAME.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_controller.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_frame.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

const Size _btn = Size(88, 44);

String? _required(String? v) => VenteInput.cleanName(v).isEmpty ? 'Requis' : null;

/// Création d'un client carnet (page) ; renvoie le client créé (déjà sélectionné dans le contrôleur) ou null.
Future<ClientAssurance?> showCreateClientCarnetPage(BuildContext context, CarnetController c,
        {String initialName = '', ListPresentation? presentation}) =>
    Navigator.of(context).push<ClientAssurance>(MaterialPageRoute(
      builder: (_) => CarnetNewClientPage(controller: c, initialName: initialName, presentation: presentation),
    ));

class CarnetNewClientPage extends StatefulWidget {
  final CarnetController controller;
  final String initialName;

  /// Présentation transmise par l'écran Vente Carnet (celle de l'appareil si non précisée).
  final ListPresentation? presentation;
  const CarnetNewClientPage({super.key, required this.controller, this.initialName = '', this.presentation});

  @override
  State<CarnetNewClientPage> createState() => _CarnetNewClientPageState();
}

class _CarnetNewClientPageState extends State<CarnetNewClientPage> with PresentationAware {
  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  final _form = GlobalKey<FormState>();
  late final _nom = TextEditingController(text: VenteInput.cleanName(widget.initialName));
  final _prenom = TextEditingController();
  final _matricule = TextEditingController();
  final _carnetQuery = TextEditingController();
  Timer? _debounce;
  TiersPayantAssurance? _carnet;
  List<TiersPayantAssurance>? _results;
  String? _searchError;
  bool _searching = false;
  bool _submitting = false;
  String? _error;
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    loadPresentation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nom.dispose();
    _prenom.dispose();
    _matricule.dispose();
    _carnetQuery.dispose();
    super.dispose();
  }

  void _onCarnetChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _searchCarnet(v));
  }

  Future<void> _searchCarnet(String v) async {
    final q = VenteInput.cleanQuery(v);
    final seq = ++_searchSeq;
    if (q.length < 3) {
      setState(() {
        _results = null;
        _searchError = null;
      });
      return;
    }
    setState(() => _searching = true);
    final r = await widget.controller.searchCarnets(q);
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _searching = false;
      if (r case VenteOk(:final value)) {
        _results = value;
        _searchError = null;
      } else {
        _results = null;
        _searchError = venteMessage(r.message);
      }
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final carnet = _carnet;
    if (carnet == null) {
      setState(() => _error = 'Choisissez le carnet dans la liste.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final r = await widget.controller.createClient(nom: _nom.text, prenom: _prenom.text, matricule: _matricule.text, carnet: carnet);
    if (!mounted) return;
    if (r case VenteOk(:final value)) {
      Navigator.of(context).pop(value);
      return;
    }
    setState(() {
      _submitting = false;
      _error = venteMessage(r.message);
    });
  }

  InputDecoration _deco(String label, {Widget? suffix}) => InputDecoration(
        labelText: label,
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFC5D0DE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Pal.navy, width: 2)),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Pal.muted, letterSpacing: 0.5)),
      );

  Widget _carnetSection() {
    final chosen = _carnet;
    if (chosen != null) {
      final guided = style == ListPresentation.guided;
      return Container(
        key: const ValueKey('carnet-choisi'),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: guided ? Pal.line : const Color(0xFFB7DCC3)),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: Pal.green),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                child: Row(children: [
                  const Icon(Icons.menu_book, color: Pal.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(chosen.strFULLNAME,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Pal.ink)),
                      if (chosen.strNAME.isNotEmpty && chosen.strNAME != chosen.strFULLNAME)
                        Text(chosen.strNAME, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
                    ]),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: Pal.navy),
                    onPressed: _submitting ? null : () => setState(() => _carnet = null),
                    child: const Text('Changer'),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      );
    }
    final results = _results;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      TextField(
        key: const ValueKey('carnet-recherche'),
        controller: _carnetQuery,
        inputFormatters: VenteInput.queryFormatters,
        decoration: _deco(
          'Rechercher le carnet * (3 car. min.)',
          suffix: _searching
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : const Icon(Icons.search),
        ),
        onChanged: _onCarnetChanged,
        onSubmitted: _searchCarnet,
      ),
      if (_searchError != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Expanded(child: Text('Recherche impossible : $_searchError', style: TextStyle(color: Colors.red.shade700, fontSize: 12.5))),
            TextButton(onPressed: () => _searchCarnet(_carnetQuery.text), child: const Text('Réessayer')),
          ]),
        ),
      if (results != null && results.isEmpty)
        const Padding(padding: EdgeInsets.only(top: 6), child: Text('Aucun carnet trouvé.', style: TextStyle(fontSize: 12.5, color: Pal.muted))),
      if (results != null && results.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.line)),
          child: Column(children: [
            for (final tp in results)
              ListTile(
                minTileHeight: 46,
                dense: true,
                leading: const Icon(Icons.menu_book_outlined, color: Pal.navy),
                title: Text(tp.strFULLNAME, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const StatusBadge('Choisir', fg: Pal.navy, bg: Color(0xFFE3ECF7)),
                onTap: () => setState(() {
                  _carnet = tp;
                  _error = null;
                }),
              ),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final guided = style == ListPresentation.guided;
    final ready = !_submitting && _carnet != null;
    return PopScope(
      canPop: !_submitting,
      child: PresentationScaffold(
        style: style,
        title: 'Nouveau client carnet',
        subtitle: 'Fiche créée sur le serveur',
        actions: (_) => const [],
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              TextFormField(
                key: const ValueKey('carnet-nc-nom'),
                controller: _nom,
                autofocus: true,
                inputFormatters: VenteInput.nameFormatters,
                decoration: _deco('Nom *'),
                validator: _required,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('carnet-nc-prenom'),
                controller: _prenom,
                inputFormatters: VenteInput.nameFormatters,
                decoration: _deco('Prénom(s) *'),
                validator: _required,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('carnet-nc-matricule'),
                controller: _matricule,
                inputFormatters: VenteInput.nameFormatters,
                decoration: _deco('Matricule *'),
                validator: _required,
                textInputAction: TextInputAction.next,
              ),
              _label('Carnet choisi'),
              _carnetSection(),
              const SizedBox(height: 12),
              const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 18, color: Pal.muted),
                SizedBox(width: 6),
                Expanded(
                  child: Text('Vérifiez avant d\'enregistrer : la fiche est créée sur le serveur.', style: TextStyle(fontSize: 12.5, color: Pal.muted)),
                ),
              ]),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                ),
            ],
          ),
        ),
        bottomNavigationBar: CarnetBottomBar(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_carnet == null && !_submitting)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('Choisissez le carnet pour créer le client.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Pal.muted)),
              ),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: outlineButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 50))),
                  onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                  child: const FittedBox(fit: BoxFit.scaleDown, child: Text('ANNULER')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  key: const ValueKey('carnet-nc-creer'),
                  style: (guided ? amberButton : navyButton).copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 50))),
                  onPressed: ready ? _submit : null,
                  child: _submitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const FittedBox(fit: BoxFit.scaleDown, child: Text('CRÉER LE CLIENT')),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Création d'un ayant droit pour le client du contrôleur (sélectionné ensuite). true = créé.
Future<bool> showCreateAyantDroitDialog(BuildContext context, CarnetController c) async {
  final ok = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _CreateAyantDroitDialog(controller: c));
  return ok == true;
}

class _CreateAyantDroitDialog extends StatefulWidget {
  final CarnetController controller;
  const _CreateAyantDroitDialog({required this.controller});

  @override
  State<_CreateAyantDroitDialog> createState() => _CreateAyantDroitDialogState();
}

class _CreateAyantDroitDialogState extends State<_CreateAyantDroitDialog> {
  final _form = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  late final _matricule = TextEditingController(text: widget.controller.client?.strNUMEROSECURITESOCIAL ?? '');
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    _matricule.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final r = await widget.controller.createAyantDroit(nom: _nom.text, prenom: _prenom.text, matricule: _matricule.text);
    if (!mounted) return;
    if (r.isOk) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _error = venteMessage(r.message);
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Nouvel ayant droit'),
        content: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Patient rattaché à ${carnetName(widget.controller.client?.fullName ?? '', '', '')}',
                  style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
              TextFormField(
                controller: _nom,
                autofocus: true,
                inputFormatters: VenteInput.nameFormatters,
                decoration: const InputDecoration(labelText: 'Nom *'),
                validator: _required,
                textInputAction: TextInputAction.next,
              ),
              TextFormField(
                controller: _prenom,
                inputFormatters: VenteInput.nameFormatters,
                decoration: const InputDecoration(labelText: 'Prénom(s)'),
                textInputAction: TextInputAction.next,
              ),
              TextFormField(
                controller: _matricule,
                inputFormatters: VenteInput.nameFormatters,
                decoration: const InputDecoration(labelText: 'Matricule *'),
                validator: _required,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: _btn),
            onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: navyButton.copyWith(minimumSize: const WidgetStatePropertyAll(_btn)),
            onPressed: _submitting ? null : _submit,
            child: _submitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Créer'),
          ),
        ],
      );
}
