// lib/ventes/assurance/assurance_dialogs.dart
// Dialogues de la vente assurance (nouvelle version) : création client / ayant droit (nom et prénom
// dans le bon ordre), ajout et modification de tiers payant (taux contrôlé, « Changer l'assurance »
// confirmé car il modifie la fiche client sur le serveur). Une panne n'est jamais « aucun résultat ».
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_controller.dart';
import 'package:prestige_vente_app/ventes/common/vente_dialogs.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

const Size _btn = Size(88, 44);

String? _required(String? v) => VenteInput.cleanName(v).isEmpty ? 'Requis' : null;

String? Function(String?) _tauxValidator(int min) => (v) {
      if ((v ?? '').trim().isEmpty) return 'Requis';
      return VenteInput.parseTaux(v, min: min) == null ? 'Invalide ($min-100)' : null;
    };

// -----------------------------------------------------------------------------
// Recherche d'assurance (tiers payant)
// -----------------------------------------------------------------------------

/// Champ de recherche d'assurance (≥ 3 caractères) avec liste de choix.
class TiersPayantPicker extends StatefulWidget {
  final Future<VenteResult<List<TiersPayantAssurance>>> Function(String query) search;
  final ValueChanged<TiersPayantAssurance?> onChanged;
  final String label;
  final bool autofocus;
  final Duration debounce;
  const TiersPayantPicker({
    super.key,
    required this.search,
    required this.onChanged,
    this.label = 'Rechercher Assurance *',
    this.autofocus = false,
    this.debounce = const Duration(milliseconds: 500),
  });

  @override
  State<TiersPayantPicker> createState() => _TiersPayantPickerState();
}

class _TiersPayantPickerState extends State<TiersPayantPicker> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<TiersPayantAssurance> _results = const [];
  TiersPayantAssurance? _selected;
  String? _error;
  bool _loading = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _changed(String text) {
    if (_selected != null && text != _selected!.strFULLNAME) {
      _selected = null;
      widget.onChanged(null);
    }
    _debounce?.cancel();
    final q = VenteInput.cleanQuery(text);
    if (q.length < 3) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(widget.debounce, () => _run(q));
  }

  Future<void> _run(String q) async {
    _lastQuery = q;
    setState(() => _loading = true);
    final r = await widget.search(q);
    if (!mounted || q != _lastQuery) return;
    setState(() {
      _loading = false;
      if (r case VenteOk(:final value)) {
        _results = value;
        _error = null;
      } else {
        _results = const [];
        _error = venteMessage(r.message);
      }
    });
  }

  void _pick(TiersPayantAssurance tp) {
    _ctrl.text = tp.strFULLNAME;
    setState(() {
      _selected = tp;
      _results = const [];
    });
    widget.onChanged(tp);
  }

  @override
  Widget build(BuildContext context) {
    final q = VenteInput.cleanQuery(_ctrl.text);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        key: const ValueKey('assurance-tp-recherche'),
        controller: _ctrl,
        autofocus: widget.autofocus,
        inputFormatters: VenteInput.queryFormatters,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: _selected == null ? '3 caractères minimum' : null,
          prefixIcon: _loading
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : Icon(_selected != null ? Icons.check_circle : Icons.search, color: _selected != null ? Colors.green : null),
        ),
        onChanged: _changed,
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Expanded(child: Text('Recherche impossible : $_error', style: TextStyle(color: Colors.red.shade700, fontSize: 12))),
            TextButton(onPressed: () => _run(q), child: const Text('Réessayer')),
          ]),
        ),
      if (_selected == null && _error == null && !_loading && q.length >= 3 && _results.isEmpty && _lastQuery == q)
        const Padding(padding: EdgeInsets.only(top: 6), child: Text('Aucune assurance trouvée.', style: TextStyle(fontSize: 12))),
      if (_results.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final tp in _results)
                ListTile(dense: true, minTileHeight: 44, title: Text(tp.strFULLNAME), onTap: () => _pick(tp)),
            ],
          ),
        ),
    ]);
  }
}

// -----------------------------------------------------------------------------
// Création du client
// -----------------------------------------------------------------------------

/// Création d'un client assurance (Nom → strFIRSTNAME, Prénom(s) → strLASTNAME). true si créé et sélectionné.
Future<bool> showCreateClientDialog(BuildContext context, AssuranceController c, {String initialName = ''}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateClientDialog(controller: c, initialName: initialName),
    ) ==
    true;

class _CreateClientDialog extends StatefulWidget {
  final AssuranceController controller;
  final String initialName;
  const _CreateClientDialog({required this.controller, required this.initialName});

  @override
  State<_CreateClientDialog> createState() => _CreateClientDialogState();
}

class _CreateClientDialogState extends State<_CreateClientDialog> {
  final _form = GlobalKey<FormState>();
  late final _nom = TextEditingController(text: widget.initialName);
  final _prenom = TextEditingController();
  final _matricule = TextEditingController();
  final _taux = TextEditingController();
  TiersPayantAssurance? _tp;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    _matricule.dispose();
    _taux.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final tp = _tp;
    if (tp == null) {
      setState(() => _error = 'Veuillez sélectionner une assurance valide dans la liste.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.controller.createClient(
      nom: _nom.text,
      prenom: _prenom.text,
      matricule: _matricule.text,
      tiersPayant: tp,
      taux: VenteInput.parseTaux(_taux.text, min: 1) ?? 0,
    );
    if (!mounted) return;
    if (r.isOk) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = venteMessage(r.message);
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Créer un client assurance'),
        content: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                key: const ValueKey('client-nom'),
                controller: _nom,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom *'),
                inputFormatters: VenteInput.nameFormatters,
                validator: _required,
                textInputAction: TextInputAction.next,
              ),
              TextFormField(
                key: const ValueKey('client-prenom'),
                controller: _prenom,
                decoration: const InputDecoration(labelText: 'Prénom(s) *'),
                inputFormatters: VenteInput.nameFormatters,
                validator: _required,
                textInputAction: TextInputAction.next,
              ),
              TextFormField(
                key: const ValueKey('client-matricule'),
                controller: _matricule,
                decoration: const InputDecoration(labelText: 'Matricule *'),
                inputFormatters: VenteInput.nameFormatters,
                validator: _required,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TiersPayantPicker(search: widget.controller.searchTiersPayants, onChanged: (tp) => setState(() => _tp = tp)),
              TextFormField(
                key: const ValueKey('client-taux'),
                controller: _taux,
                decoration: const InputDecoration(labelText: 'Pourcentage % (1 à 100) *'),
                keyboardType: TextInputType.number,
                inputFormatters: VenteInput.tauxFormatters,
                validator: _tauxValidator(1),
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: Colors.red.shade700))),
            ]),
          ),
        ),
        actions: [
          TextButton(style: TextButton.styleFrom(minimumSize: _btn), onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: _btn),
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Créer'),
          ),
        ],
      );
}

// -----------------------------------------------------------------------------
// Création d'un ayant droit
// -----------------------------------------------------------------------------

/// Nouvel ayant droit (même ordre nom / prénom que le client). true si créé et sélectionné.
Future<bool> showCreateAyantDroitDialog(BuildContext context, AssuranceController c) async =>
    await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _CreateAyantDroitDialog(controller: c)) == true;

class _CreateAyantDroitDialog extends StatefulWidget {
  final AssuranceController controller;
  const _CreateAyantDroitDialog({required this.controller});

  @override
  State<_CreateAyantDroitDialog> createState() => _CreateAyantDroitDialogState();
}

class _CreateAyantDroitDialogState extends State<_CreateAyantDroitDialog> {
  final _form = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _matricule = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nom.dispose();
    _prenom.dispose();
    _matricule.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.controller.createAyantDroit(nom: _nom.text, prenom: _prenom.text, matricule: _matricule.text);
    if (!mounted) return;
    if (r.isOk) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = venteMessage(r.message);
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nouvel ayant droit'),
        content: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                key: const ValueKey('ad-nom'),
                controller: _nom,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom *'),
                inputFormatters: VenteInput.nameFormatters,
                validator: _required,
                textInputAction: TextInputAction.next,
              ),
              TextFormField(
                key: const ValueKey('ad-prenom'),
                controller: _prenom,
                decoration: const InputDecoration(labelText: 'Prénom(s)'),
                inputFormatters: VenteInput.nameFormatters,
                textInputAction: TextInputAction.next,
              ),
              TextFormField(
                key: const ValueKey('ad-matricule'),
                controller: _matricule,
                decoration: const InputDecoration(labelText: 'Matricule *'),
                inputFormatters: VenteInput.nameFormatters,
                validator: _required,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: Colors.red.shade700))),
            ]),
          ),
        ),
        actions: [
          TextButton(style: TextButton.styleFrom(minimumSize: _btn), onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: _btn),
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Créer'),
          ),
        ],
      );
}

// -----------------------------------------------------------------------------
// Ajout d'un tiers payant à la fiche client
// -----------------------------------------------------------------------------

Future<bool> showAddTiersPayantDialog(BuildContext context, AssuranceController c) async =>
    await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _AddTpDialog(controller: c)) == true;

class _AddTpDialog extends StatefulWidget {
  final AssuranceController controller;
  const _AddTpDialog({required this.controller});

  @override
  State<_AddTpDialog> createState() => _AddTpDialogState();
}

class _AddTpDialogState extends State<_AddTpDialog> {
  final _form = GlobalKey<FormState>();
  final _matricule = TextEditingController();
  final _taux = TextEditingController();
  TiersPayantAssurance? _tp;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _matricule.dispose();
    _taux.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final tp = _tp;
    if (tp == null) {
      setState(() => _error = 'Veuillez sélectionner une assurance valide dans la liste.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.controller.addTiersPayantToClient(tp, matricule: _matricule.text, taux: VenteInput.parseTaux(_taux.text, min: 1) ?? 0);
    if (!mounted) return;
    if (r.isOk) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = venteMessage(r.message);
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ajouter un tiers payant'),
        content: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Client : ${widget.controller.client?.fullName ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('La fiche du client sera modifiée sur le serveur.', style: TextStyle(fontSize: 12, color: Colors.black54)),
              TiersPayantPicker(search: widget.controller.searchTiersPayants, autofocus: true, onChanged: (tp) => setState(() => _tp = tp)),
              TextFormField(
                key: const ValueKey('tp-matricule'),
                controller: _matricule,
                decoration: const InputDecoration(labelText: 'Matricule (pour ce TP) *'),
                inputFormatters: VenteInput.nameFormatters,
                validator: _required,
              ),
              TextFormField(
                key: const ValueKey('tp-taux'),
                controller: _taux,
                decoration: const InputDecoration(labelText: 'Pourcentage % (1 à 100) *'),
                keyboardType: TextInputType.number,
                inputFormatters: VenteInput.tauxFormatters,
                validator: _tauxValidator(1),
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: Colors.red.shade700))),
            ]),
          ),
        ),
        actions: [
          TextButton(style: TextButton.styleFrom(minimumSize: _btn), onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: _btn),
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Ajouter'),
          ),
        ],
      );
}

// -----------------------------------------------------------------------------
// Modification d'un tiers payant (taux de la vente / changer l'assurance)
// -----------------------------------------------------------------------------

Future<void> showEditTiersPayantDialog(BuildContext context, AssuranceController c, ActiveTiersPayant tp) =>
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => _EditTpDialog(controller: c, tp: tp));

class _EditTpDialog extends StatefulWidget {
  final AssuranceController controller;
  final ActiveTiersPayant tp;
  const _EditTpDialog({required this.controller, required this.tp});

  @override
  State<_EditTpDialog> createState() => _EditTpDialogState();
}

class _EditTpDialogState extends State<_EditTpDialog> {
  final _form = GlobalKey<FormState>();
  late final _taux = TextEditingController(text: '${widget.tp.taux}');
  bool _change = false;
  TiersPayantAssurance? _newTp;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _taux.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final taux = VenteInput.parseTaux(_taux.text);
    if (taux == null) return;
    final c = widget.controller;
    final newTp = _newTp;
    if (newTp == null) {
      final r = c.updateTaux(widget.tp.compteTp, taux);
      if (!r.isOk) {
        setState(() => _error = venteMessage(r.message));
        return;
      }
      Navigator.of(context).pop();
      return;
    }
    // « Changer l'assurance » modifie la fiche du client sur le serveur : confirmation.
    final ok = await confirmVenteAction(
      context,
      title: 'Modifier la fiche client ?',
      message: 'L\'assurance ${newTp.strFULLNAME} ($taux %) sera enregistrée sur la fiche de '
          '${c.client?.fullName ?? 'ce client'} sur le serveur, en 1ʳᵉ position.\n\n'
          'Les N° de bon devront être saisis pour la nouvelle assurance.',
      confirm: 'Modifier la fiche',
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await c.replaceTiersPayant(widget.tp, newTp, taux);
    if (!mounted) return;
    if (r.isOk) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = venteMessage(r.message);
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Modifier le tiers payant'),
        content: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.tp.tpFullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              if (!_change)
                TextButton.icon(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => setState(() => _change = true),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Changer l\'assurance'),
                )
              else ...[
                const SizedBox(height: 4),
                const Text('Modifie la fiche client sur le serveur.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                TiersPayantPicker(
                  search: widget.controller.searchTiersPayants,
                  label: 'Rechercher la nouvelle assurance',
                  autofocus: true,
                  onChanged: (tp) => setState(() => _newTp = tp),
                ),
              ],
              TextFormField(
                key: const ValueKey('tp-edit-taux'),
                controller: _taux,
                decoration: const InputDecoration(labelText: 'Taux % (0 à 100)'),
                keyboardType: TextInputType.number,
                inputFormatters: VenteInput.tauxFormatters,
                validator: _tauxValidator(0),
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: Colors.red.shade700))),
            ]),
          ),
        ),
        actions: [
          TextButton(style: TextButton.styleFrom(minimumSize: _btn), onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: _btn),
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Valider'),
          ),
        ],
      );
}
