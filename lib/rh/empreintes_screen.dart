// lib/rh/empreintes_screen.dart
// Enrôlement des empreintes des employés sur le terminal de pointage (SUNMI V3H avec lecteur d'empreinte).
// Accès : code administrateur de l'appli (PinCodeDialog) ET compte connecté avec le droit RH (P_SM_RH).
// Parcours : choisir l'employé → CONSENTEMENT explicite de l'employé (donnée biométrique) → 3 captures →
// test de reconnaissance → enregistrement des modèles (stockage sécurisé du terminal).
// 4.4.0 (demande 43) : partage actif sur le serveur → modèles AUSSI conservés chiffrés sur le serveur de la
// pharmacie et reconnus sur tous ses terminaux (texte du consentement adapté) ; suppression → supprimés du serveur.
// Serveur sans partage : comme avant, sur ce terminal seulement. Accès : administrateur de l'application.
// Suppression des empreintes d'un employé à tout moment (et automatiquement s'il devient inactif).
// Le journal ne garde que « empreintes enregistrées / envoyées / supprimées » (jamais de modèle).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/rh/empreintes_partagees.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

/// Texte du consentement quand le serveur NE partage PAS les empreintes (affiché et gardé avec la date).
const String texteConsentementEmpreinte =
    'J\'accepte que mon empreinte digitale soit enregistrée sur ce terminal de pointage de l\'officine, '
    'uniquement pour enregistrer mes entrées et sorties. Le modèle d\'empreinte reste sur ce terminal (jamais '
    'envoyé au serveur), chiffré, et est supprimé à ma demande ou à mon départ. Je peux utiliser mon badge à la place.';

/// 4.4.0 : texte du consentement quand le partage est actif (demande 43).
const String texteConsentementEmpreintePartagee =
    'J\'accepte que mon empreinte digitale soit enregistrée pour le pointage de l\'officine, uniquement pour '
    'enregistrer mes entrées et sorties. Le modèle d\'empreinte est conservé chiffré sur le serveur de la pharmacie '
    'et reconnu sur tous ses terminaux de pointage ; il est supprimé à ma demande ou à mon départ. Je peux utiliser '
    'mon badge à la place.';

/// Rappel réglementaire (Côte d'Ivoire) affiché à l'enrôlement.
const String rappelArtci =
    'Donnée biométrique : l\'officine doit avoir déclaré ce traitement à l\'ARTCI (loi n° 2013-450 du 19 juin 2013 '
    'relative à la protection des données à caractère personnel) avant de l\'utiliser.';

class EmpreintesScreen extends StatefulWidget {
  final PointageRh rh;
  final IdentificationEmploye identification;

  /// Contrôle du code administrateur (remplaçable pour les tests).
  final Future<bool> Function(BuildContext context)? codeAdmin;

  /// Nombre de captures par employé.
  final int captures;
  const EmpreintesScreen({super.key, required this.rh, required this.identification, this.codeAdmin, this.captures = 3});

  @override
  State<EmpreintesScreen> createState() => _EmpreintesScreenState();
}

class _EmpreintesScreenState extends State<EmpreintesScreen> {
  bool _autorise = false;
  bool _verifie = false;
  Map<String, EmpreintesEmploye> _enroles = {};
  String _filtre = '';
  String? _etat;
  bool _occupe = false;

  IdentificationEmploye get _id => widget.identification;

  /// Partage des empreintes (null : pas de serveur RH).
  EmpreintesPartagees? get _partage {
    final s = widget.rh.serveur;
    return s == null ? null : EmpreintesPartagees.pour(s, _id.coffre, horsLigne: widget.rh.horsLigne);
  }

  StatutPartageEmpreintes _statut = const StatutPartageEmpreintes();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controler());
  }

  Future<void> _controler() async {
    final pin = await (widget.codeAdmin ?? PinCodeDialog.show)(context);
    if (!mounted) return;
    if (!pin) {
      Navigator.of(context).maybePop();
      return;
    }
    final rh = widget.rh.acces == AccesRh.autorise;
    setState(() {
      _autorise = rh;
      _verifie = true;
    });
    if (rh) await _charger();
  }

  Future<void> _charger({bool synchroniser = true}) async {
    final p = _partage;
    if (p != null && synchroniser) {
      try {
        await p.synchroniser();
      } catch (_) {}
    }
    final e = await _id.enroles();
    final st = p == null ? const StatutPartageEmpreintes() : await p.statut();
    if (mounted) {
      setState(() {
        _enroles = e;
        _statut = st;
      });
    }
  }

  Future<bool> _consentement(EmployeRh e) async {
    var coche = false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          key: const Key('rh_consentement'),
          scrollable: true,
          title: Text('Consentement de ${e.nomComplet}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_statut.actif ? texteConsentementEmpreintePartagee : texteConsentementEmpreinte,
                key: const Key('rh_consentement_texte'), style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFFF1D6), borderRadius: BorderRadius.circular(10)),
              child: const Text(rappelArtci, style: TextStyle(fontSize: 12.5, color: Color(0xFF8A5300))),
            ),
            CheckboxListTile(
              key: const Key('rh_consentement_coche'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: coche,
              onChanged: (v) => set(() => coche = v ?? false),
              title: Text('${e.prenomAffiche} a lu ce texte et donne son accord'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Refus / annuler')),
            ElevatedButton(
              key: const Key('rh_consentement_ok'),
              onPressed: coche ? () => Navigator.of(ctx).pop(true) : null,
              child: const Text('Continuer'),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _enroler(EmployeRh e) async {
    if (_occupe) return;
    if (!await _consentement(e)) {
      _dire('Enrôlement annulé : pas de consentement, aucune empreinte enregistrée.');
      return;
    }
    setState(() => _occupe = true);
    final modeles = <Uint8List>[];
    try {
      for (var i = 1; i <= widget.captures; i++) {
        _dire('Capture $i / ${widget.captures} : ${e.prenomAffiche}, posez le doigt sur le lecteur…');
        modeles.add(await _id.empreinte.enroler());
      }
      _dire('Test de reconnaissance : posez de nouveau le même doigt…');
      final i = await _id.empreinte.identifier(modeles);
      if (i == null) {
        _dire('Test échoué : empreinte non reconnue. Rien n\'a été enregistré, recommencez.');
        return;
      }
      final partage = _statut.actif;
      final avant = _enroles[e.id];
      final nouveau = EmpreintesEmploye(
        employeId: e.id,
        employeNom: e.nomComplet,
        modeles: modeles,
        consentementLe: widget.rh.now,
        recueilliPar: JournalTerminal.instance.utilisateur,
        consentementPartage: partage,
      );
      await _id.enregistrer(nouveau);
      final p = _partage;
      if (p != null && partage) {
        // Refaire : les anciens modèles sont d'abord retirés du serveur (les autres terminaux les retirent aussi).
        if (avant != null && (avant.partage || avant.envoiEnAttente)) await p.supprimer(e.id);
        final etat = await p.envoyer(nouveau);
        final enAttente = (await _id.enroles())[e.id]?.envoiEnAttente == true;
        _dire(
            enAttente
                ? 'Empreintes de ${e.nomComplet} enregistrées et reconnues. Serveur injoignable : envoi au serveur à la prochaine synchronisation.'
                : etat == EtatPartageEmpreintes.actif
                    ? 'Empreintes de ${e.nomComplet} enregistrées, reconnues et partagées avec les autres terminaux.'
                    : 'Empreintes de ${e.nomComplet} enregistrées et reconnues sur ce terminal (partage indisponible).',
            ok: true);
        widget.rh.journal().noter(
            type: TypeJournal.pointageRh,
            action: 'Empreintes enregistrées — ${e.nomComplet} (${modeles.length} capture(s), consentement « partage » recueilli)',
            resultat: ResultatJournal.info);
        await _charger(synchroniser: false);
        return;
      }
      widget.rh.journal().noter(
          type: TypeJournal.pointageRh,
          action: 'Empreintes enregistrées sur le terminal — ${e.nomComplet} (${modeles.length} capture(s), consentement recueilli)',
          resultat: ResultatJournal.info);
      _dire('Empreintes de ${e.nomComplet} enregistrées et reconnues.', ok: true);
      await _charger();
    } on EmpreinteIndisponible catch (x) {
      _dire(x.message);
    } catch (x) {
      _dire('Capture impossible : $x');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _supprimer(EmployeRh e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer les empreintes ?'),
        content: Text(_statut.actif
            ? 'Les empreintes de ${e.nomComplet} seront effacées du serveur et de tous les terminaux. Il / elle pointera avec son badge.'
            : 'Les empreintes de ${e.nomComplet} seront effacées de ce terminal. Il / elle pointera avec son badge.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          ElevatedButton(key: const Key('rh_supprimer_ok'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    final avant = _enroles[e.id];
    await _id.supprimer(e.id);
    // 4.4.0 : aussi sur le serveur (refait plus tard si le réseau est coupé).
    if (avant != null && (avant.partage || avant.consentementPartage)) await _partage?.supprimer(e.id);
    widget.rh.journal().noter(type: TypeJournal.pointageRh, action: 'Empreintes supprimées du terminal — ${e.nomComplet}', resultat: ResultatJournal.info);
    _dire('Empreintes de ${e.nomComplet} supprimées.', ok: true);
    await _charger();
  }

  bool _etatOk = false;
  void _dire(String m, {bool ok = false}) {
    if (mounted) {
      setState(() {
        _etat = m;
        _etatOk = ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final employes = widget.rh.employes
        .where((e) => e.actif && (_filtre.isEmpty || '${e.nomComplet} ${e.matricule}'.toLowerCase().contains(_filtre.toLowerCase())))
        .toList()
      ..sort((a, b) => a.nomComplet.compareTo(b.nomComplet));
    return Scaffold(
      backgroundColor: Pal.page,
      appBar: AppBar(title: const Text('Empreintes des employés')),
      body: !_verifie
          ? const Center(child: CircularProgressIndicator())
          : !_autorise
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Réservé au responsable RH : le compte connecté doit avoir le droit RH (P_SM_RH).'),
                )
              : ContentWidth(
                  child: ListView(
                    key: const Key('rh_empreintes'),
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Text(rappelArtci, style: TextStyle(fontSize: 12.5, color: Color(0xFF8A5300))),
                      const SizedBox(height: 8),
                      // 4.4.0 : état du partage entre terminaux.
                      Row(children: [
                        Icon(_statut.actif ? Icons.cloud_done_outlined : Icons.phonelink_lock_outlined, size: 18, color: _statut.actif ? Pal.green : Pal.muted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(texteStatutEmpreintes(_statut, _enroles.values.where((x) => x.modeles.isNotEmpty).length),
                              key: const Key('rh_empreintes_statut'), style: const TextStyle(fontSize: 12.5, color: Pal.ink)),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      if (_etat != null)
                        Container(
                          key: const Key('rh_empreintes_etat'),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: _etatOk ? const Color(0xFFDCF5E7) : const Color(0xFFE3ECF7), borderRadius: BorderRadius.circular(12)),
                          child: Text(_etat!, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
                        ),
                      TextField(
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher un employé', border: OutlineInputBorder()),
                        onChanged: (v) => setState(() => _filtre = v.trim()),
                      ),
                      const SizedBox(height: 8),
                      for (final e in employes)
                        Card(
                          child: ListTile(
                            key: Key('rh_emp_${e.id}'),
                            leading: Icon(Icons.fingerprint, color: _enroles.containsKey(e.id) ? Pal.green : Pal.muted),
                            title: Text(e.nomComplet),
                            subtitle: Text(_enroles.containsKey(e.id)
                                ? 'Enregistrée(s) le ${DateFormat('dd/MM/yyyy').format(_enroles[e.id]!.consentementLe)} (consentement)'
                                : 'Aucune empreinte${e.matricule.isEmpty ? '' : ' · ${e.matricule}'}'),
                            trailing: Wrap(spacing: 4, children: [
                              IconButton(
                                key: Key('rh_enroler_${e.id}'),
                                tooltip: _enroles.containsKey(e.id) ? 'Refaire' : 'Enregistrer',
                                onPressed: _occupe ? null : () => _enroler(e),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                              if (_enroles.containsKey(e.id))
                                IconButton(
                                  key: Key('rh_supprimer_${e.id}'),
                                  tooltip: 'Supprimer',
                                  onPressed: _occupe ? null : () => _supprimer(e),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                            ]),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
