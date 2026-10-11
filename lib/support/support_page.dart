// lib/support/support_page.dart
// Réglages › Centre de support : envoi automatique des anomalies (activé par défaut, modifiable avec le
// code administrateur), état de la file locale, « Signaler un problème », « Renvoyer maintenant ».
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/support/signaler_probleme_screen.dart';
import 'package:prestige_vente_app/support/support_centre.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

class SupportPage extends StatelessWidget {
  final SupportCentre? centre;

  /// Code administrateur (par défaut : PinCodeDialog.show).
  final Future<bool> Function(BuildContext)? adminCheck;
  const SupportPage({super.key, this.centre, this.adminCheck});

  SupportCentre get _c => centre ?? SupportCentre.instance;

  Future<void> _basculer(BuildContext context, bool v) async {
    final ok = await (adminCheck ?? PinCodeDialog.show)(context);
    if (!ok) return;
    await _c.reglerEnvoiAuto(v);
  }

  Future<void> _renvoyer(BuildContext context) async {
    final m = ScaffoldMessenger.of(context);
    final n = await _c.renvoyer(forcer: true);
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(n > 0
            ? '$n anomalie(s) transmise(s) au centre de support.'
            : _c.routeAbsente
                ? 'Ce serveur n\'a pas le centre de support : la file est conservée.'
                : _c.enAttente > 0
                    ? 'Envoi impossible pour le moment (serveur ou session) : la file est conservée.'
                    : 'Aucune anomalie en attente.'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Centre de support')),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SwitchListTile(
              key: const Key('support_envoi_auto'),
              value: _c.envoiAuto,
              onChanged: (v) => _basculer(context, v),
              title: const Text('Envoyer automatiquement les anomalies au centre de support'),
              subtitle: const Text('Erreurs de l\'application, échecs du serveur et refus de la synchronisation hors ligne, '
                  'avec le contexte technique (sans mot de passe ni donnée patient). Modification : code administrateur.'),
            ),
            const Divider(),
            ListTile(
              key: const Key('support_etat'),
              leading: Icon(_c.routeAbsente ? Icons.cloud_off : Icons.support_agent, color: Pal.navy),
              title: Text(_c.enAttente == 0 ? 'Aucune anomalie en attente' : '${_c.enAttente} anomalie(s) en attente d\'envoi'),
              subtitle: Text(_c.routeAbsente
                  ? 'Le serveur ne propose pas encore le centre de support (version plus ancienne) : '
                      'les anomalies restent sur le terminal.'
                  : 'Les anomalies non transmises sont renvoyées au retour de la connexion.'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                ElevatedButton.icon(
                  key: const Key('support_signaler'),
                  style: navyButton,
                  onPressed: () => ouvrirSignalement(context, centre: _c),
                  icon: const Icon(Icons.report_problem_outlined),
                  label: const Text('Signaler un problème'),
                ),
                OutlinedButton.icon(
                  key: const Key('support_renvoyer'),
                  onPressed: () => _renvoyer(context),
                  icon: const Icon(Icons.send),
                  label: const Text('Renvoyer maintenant'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
