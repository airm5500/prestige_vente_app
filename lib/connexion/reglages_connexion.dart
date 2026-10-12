// lib/connexion/reglages_connexion.dart
// Paramètres › Sécurité (rubrique à cadenas, réservée au compte administrateur) : section
// « Écran de connexion » — connexion rapide (« Qui êtes-vous ? »), terminal partagé, réinitialisation des
// codes PIN personnels, numéro d'assistance.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/connexion/assistance.dart';
import 'package:prestige_vente_app/connexion/connexion_reglages.dart';
import 'package:prestige_vente_app/connexion/pin_personnel.dart';
import 'package:prestige_vente_app/parametres/parametres_widgets.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

class ReglagesEcranConnexion extends StatefulWidget {
  const ReglagesEcranConnexion({super.key});

  @override
  State<ReglagesEcranConnexion> createState() => _ReglagesEcranConnexionState();
}

class _ReglagesEcranConnexionState extends State<ReglagesEcranConnexion> {
  late final _numero = TextEditingController(text: ConnexionReglages.courant.value.assistance);
  int? _nbPin;
  bool _occupe = false;

  @override
  void initState() {
    super.initState();
    _numero.addListener(() => setState(() {}));
    _compterPin();
  }

  @override
  void dispose() {
    _numero.dispose();
    super.dispose();
  }

  Future<void> _compterPin() async {
    final n = (await PinPersonnel.instance.logins()).length;
    if (mounted) setState(() => _nbPin = n);
  }

  void _message(String texte) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texte)));

  Future<void> _rapide(bool v) => ConnexionReglages.enregistrer(ConnexionReglages.courant.value.copyWith(connexionRapide: v));

  Future<void> _partage(bool v) async {
    if (_occupe) return;
    _occupe = true;
    try {
      final c = ConnexionReglages.courant.value;
      final s = context.read<SettingsProvider>();
      // Terminal partagé : « Rester connecté » interdit (identifiants mémorisés effacés) et, de préférence,
      // connexion rapide par utilisateur activée.
      await ConnexionReglages.enregistrer(c.copyWith(terminalPartage: v, connexionRapide: v ? true : null));
      if (v) {
        if (s.stayConnected) await s.saveCredentials('', '', false);
        _message('Terminal partagé : « Rester connecté » désactivé, connexion rapide activée.');
      }
    } finally {
      _occupe = false;
    }
  }

  Future<void> _reinitialiserPin() async {
    final ok = await confirmer(context,
        title: 'Réinitialiser les codes PIN ?',
        message: 'Tous les codes PIN personnels de cet appareil et les mots de passe gardés pour eux seront effacés. '
            'Chacun pourra en recréer un à sa prochaine connexion par mot de passe.',
        action: 'Réinitialiser',
        danger: true);
    if (!ok) return;
    final n = await PinPersonnel.instance.effacerTout();
    await _compterPin();
    _message(n == 0 ? 'Aucun code PIN à effacer.' : '$n code${n > 1 ? 's' : ''} PIN effacé${n > 1 ? 's' : ''}.');
  }

  Future<void> _enregistrerNumero() async {
    if (Assistance.refus(_numero.text) != null) return;
    final n = Assistance.nettoyer(_numero.text);
    await ConnexionReglages.enregistrer(ConnexionReglages.courant.value.copyWith(assistance: n));
    _numero.text = n;
    _message('Numéro d\'assistance enregistré.');
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ConnexionConfig>(
        valueListenable: ConnexionReglages.courant,
        builder: (context, c, _) {
          final erreur = Assistance.refus(_numero.text);
          final modifie = Assistance.nettoyer(_numero.text) != c.assistance;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionLabel('Écran de connexion'),
            SwitchCard(
              key: const Key('reglage_connexion_rapide'),
              title: 'Connexion rapide par utilisateur',
              subtitle: '« Qui êtes-vous ? » : les 6 derniers utilisateurs de l\'appareil, code PIN personnel de 4 chiffres',
              value: c.connexionRapide,
              onChanged: _rapide,
            ),
            SwitchCard(
              key: const Key('reglage_terminal_partage'),
              title: 'Terminal partagé',
              subtitle: '« Rester connecté » interdit sur cet appareil ; active la connexion rapide',
              value: c.terminalPartage,
              onChanged: _partage,
            ),
            LinkCard(
              icon: Icons.pin_outlined,
              title: 'Réinitialiser les codes PIN personnels',
              subtitle: _nbPin == null ? '…' : '${_nbPin == 0 ? 'Aucun' : _nbPin} code${(_nbPin ?? 0) > 1 ? 's' : ''} sur cet appareil',
              onTap: _reinitialiserPin,
            ),
            SettingCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SettingText('Numéro d\'assistance', subtitle: 'Affiché en bas de l\'écran de connexion (bouton « Appeler l\'assistance »)'),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('reglage_assistance'),
                  controller: _numero,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +.\-]')), LengthLimitingTextInputFormatter(20)],
                  decoration: InputDecoration(
                    hintText: ConnexionConfig.assistanceParDefaut,
                    errorText: erreur,
                    prefixIcon: const Icon(Icons.call_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                      onPressed: _numero.text == ConnexionConfig.assistanceParDefaut ? null : () => _numero.text = ConnexionConfig.assistanceParDefaut,
                      child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Valeur par défaut')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        key: const Key('reglage_assistance_enregistrer'),
                        style: navyButton,
                        onPressed: erreur != null || !modifie ? null : _enregistrerNumero,
                        child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Enregistrer')),
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
            const InfoBanner('Ces réglages concernent le nouvel écran de connexion (nouvelle interface). '
                'Le code PIN personnel ne remplace pas le mot de passe du serveur ; après 3 codes faux, le mot de passe est exigé.'),
          ]);
        },
      );
}
