// lib/screens/reception_bl/bilan_recu_dialog.dart
// 4.12.0 (demande 59) : résultat de la clôture « au reçu » d'un BL.
//  - écarts de la réponse de la clôture, puis relus sur le serveur (GET v1/reception/{blId}/ecarts, mode RECU) quand il
//    annonce `retourManquants` ;
//  - manquants et capacité `retourManquants` : « Créer un retour en attente des manquants » (POST
//    v1/reception/{blId}/retour-manquants, X-Client-Ref gardée pour un nouvel essai) ; retour déjà créé → sa référence,
//    plus de bouton ; droit manquant (403) → message du serveur, plus de bouton, jamais de déconnexion ;
//  - sans la capacité : exactement la fenêtre de 4.11.0 (écarts au rapport, OK).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/reception/manquants_bl.dart';
import 'package:prestige_vente_app/reception/reception_gateway.dart';
import 'package:prestige_vente_app/reception/reception_models.dart';

class BilanRecuDialog extends StatefulWidget {
  final ReceptionBl bl;
  final ReceptionResult resultat;

  /// Null : serveur sans la capacité `retourManquants` (comportement 4.11.0).
  final RetourManquantsGateway? manquants;

  const BilanRecuDialog({super.key, required this.bl, required this.resultat, this.manquants});

  @override
  State<BilanRecuDialog> createState() => _BilanRecuDialogState();
}

class _BilanRecuDialogState extends State<BilanRecuDialog> {
  late List<LigneEcart> _ecarts = lignesEcart(widget.resultat.data['ecarts']);
  late int _total = totalManquantDe(widget.resultat.data, _ecarts);
  RetourExistant? _retour;
  bool _relecture = false;
  bool _envoi = false;
  bool _interdit = false;

  /// Message du dernier essai de création (succès, déjà créé ou refus).
  String? _message;
  bool _messageOk = false;

  /// Clé `X-Client-Ref` du retour : la même pour chaque essai de cette fenêtre (un délai dépassé puis un nouvel essai ne
  /// créent jamais deux retours).
  final String _cle = nouvelleCleRetourManquants();

  @override
  void initState() {
    super.initState();
    if (widget.manquants != null) _relire();
  }

  Future<void> _relire() async {
    setState(() => _relecture = true);
    final e = await widget.manquants!.ecartsBl(widget.bl.id);
    if (!mounted) return;
    setState(() {
      _relecture = false;
      if (e.success) {
        // Bilan du serveur (quantités écrites à la clôture) ; une réponse sans ligne garde celles de la clôture.
        if (e.ecarts.isNotEmpty || e.totalManquant == 0) _ecarts = e.ecarts;
        _total = e.ecarts.isNotEmpty || e.totalManquant > 0 ? e.totalManquant : _total;
        _retour = e.retour ?? _retour;
      }
    });
  }

  Future<void> _creer() async {
    setState(() {
      _envoi = true;
      _message = null;
    });
    final r = await widget.manquants!.creerRetourManquants(widget.bl.id, clientRef: _cle);
    if (!mounted) return;
    setState(() {
      _envoi = false;
      _message = r.texte;
      _messageOk = r.success;
      if (r.success) _retour = RetourExistant(retourId: r.retourId, ref: r.ref, statut: r.statut);
      // Droit manquant, ou rien à retourner : le bouton disparaît (le serveur a tranché).
      if (r.interdit) _interdit = true;
      if (!r.success && (r.code == 'AUCUN_MANQUANT' || r.code == 'BL_NON_ENTRE_AU_RECU' || r.code == 'BL_INCONNU')) _interdit = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.resultat;
    final proposer = widget.manquants != null && _total > 0 && _retour == null && !_interdit;
    return AlertDialog(
      key: const Key('bl_cloture_recu_resultat'),
      icon: const Icon(Icons.check_circle, color: Colors.green, size: 40),
      title: const Text('Reçu entré en stock'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.message),
          if (_relecture) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
          if (_ecarts.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Écart au rapport :', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final e in _ecarts) Text(e.libelle),
            if (widget.manquants != null && _total > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Total manquant : $_total boîte(s).', key: const Key('bl_total_manquant'), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
          ],
          if (_retour != null)
            Padding(
              key: const Key('bl_retour_manquants_existant'),
              padding: const EdgeInsets.only(top: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.assignment_return_outlined, size: 20, color: Colors.green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${_retour!.libelle} : à valider dans « Retour fournisseur » sur Prestige ; rien ne sort du stock.'),
                ),
              ]),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_message!,
                  key: const Key('bl_retour_manquants_message'),
                  style: TextStyle(color: _messageOk ? Colors.green.shade800 : Colors.red.shade800, fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
      actionsOverflowDirection: VerticalDirection.up,
      actions: [
        if (proposer)
          OutlinedButton.icon(
            key: const Key('bl_retour_manquants'),
            onPressed: _envoi || _relecture ? null : _creer,
            icon: _envoi
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.assignment_return_outlined),
            label: const Text('Créer un retour en attente des manquants'),
          ),
        ElevatedButton(onPressed: _envoi ? null : () => Navigator.of(context).pop(), child: const Text('OK')),
      ],
    );
  }
}

/// Fenêtre du refus `AUCUN_RECU` : rien n'est entré, le BL reste ouvert.
Future<void> afficherAucunRecu(BuildContext context, ReceptionResult r) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('bl_aucun_recu'),
        icon: const Icon(Icons.info_outline, color: Colors.orange, size: 40),
        title: const Text('Rien n\'est entré'),
        content: const Text(messageAucunRecu),
        actions: [ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );
