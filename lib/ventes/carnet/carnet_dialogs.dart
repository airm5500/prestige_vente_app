// lib/ventes/carnet/carnet_dialogs.dart
// Création d'un client carnet (le carnet choisi est affiché pour relecture, validation par
// « Créer le client ») et d'un ayant droit. Nom → strFIRSTNAME, Prénom → strLASTNAME.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/client_assurance.dart';
import 'package:prestige_vente_app/api/models/tiers_payant_assurance.dart';
import 'package:prestige_vente_app/ventes/carnet/carnet_controller.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_input.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

const Size _btn = Size(88, 44);

String? _required(String? v) => VenteInput.cleanName(v).isEmpty ? 'Requis' : null;

/// Création d'un client carnet ; renvoie le client créé (déjà sélectionné dans le contrôleur) ou null.
Future<ClientAssurance?> showCreateClientCarnetDialog(BuildContext context, CarnetController c, {String initialName = ''}) => showDialog<ClientAssurance>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateClientDialog(controller: c, initialName: initialName),
    );

class _CreateClientDialog extends StatefulWidget {
  final CarnetController controller;
  final String initialName;
  const _CreateClientDialog({required this.controller, required this.initialName});

  @override
  State<_CreateClientDialog> createState() => _CreateClientDialogState();
}

class _CreateClientDialogState extends State<_CreateClientDialog> {
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

  Widget _carnetSection() {
    final chosen = _carnet;
    if (chosen != null) {
      return Card(
        key: const ValueKey('carnet-choisi'),
        color: Colors.blue.shade50,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(children: [
            const Icon(Icons.menu_book, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Carnet choisi', style: TextStyle(fontSize: 12, color: Colors.black54)),
                Text(chosen.strFULLNAME, style: const TextStyle(fontWeight: FontWeight.bold)),
              ]),
            ),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _submitting ? null : () => setState(() => _carnet = null),
              child: const Text('Changer'),
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
        decoration: InputDecoration(
          labelText: 'Rechercher le carnet * (3 car. min.)',
          suffixIcon: _searching
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : null,
        ),
        onChanged: _onCarnetChanged,
        onSubmitted: _searchCarnet,
      ),
      if (_searchError != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Expanded(child: Text('Recherche impossible : $_searchError', style: TextStyle(color: Colors.red.shade700, fontSize: 12))),
            TextButton(onPressed: () => _searchCarnet(_carnetQuery.text), child: const Text('Réessayer')),
          ]),
        ),
      if (results != null && results.isEmpty)
        const Padding(padding: EdgeInsets.only(top: 6), child: Text('Aucun carnet trouvé.', style: TextStyle(fontSize: 12))),
      if (results != null && results.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final tp in results)
                ListTile(
                  minTileHeight: 44,
                  dense: true,
                  title: Text(tp.strFULLNAME),
                  onTap: () => setState(() {
                    _carnet = tp;
                    _error = null;
                  }),
                ),
            ],
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nouveau client carnet'),
        content: SizedBox(
          width: double.maxFinite,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                  decoration: const InputDecoration(labelText: 'Prénom(s) *'),
                  validator: _required,
                  textInputAction: TextInputAction.next,
                ),
                TextFormField(
                  controller: _matricule,
                  inputFormatters: VenteInput.nameFormatters,
                  decoration: const InputDecoration(labelText: 'Matricule *'),
                  validator: _required,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                _carnetSection(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                  ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: _btn),
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: _btn),
            onPressed: _submitting || _carnet == null ? null : _submit,
            child: _submitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Créer le client'),
          ),
        ],
      );
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
        title: const Text('Nouvel ayant droit'),
        content: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
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
            style: ElevatedButton.styleFrom(minimumSize: _btn),
            onPressed: _submitting ? null : _submit,
            child: _submitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Créer'),
          ),
        ],
      );
}
