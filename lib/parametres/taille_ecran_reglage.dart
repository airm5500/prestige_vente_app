// lib/parametres/taille_ecran_reglage.dart
// Réglage « Taille de l'écran » (4.0.1), commun aux deux interfaces : Réglages › Apparence (nouvelle)
// et Configuration › Personnalisation (d'origine). Module : lib/ui/taille_ecran.dart (repris de
// Prestige Inventaire). Protégé par le code administrateur, appliqué au prochain lancement ; la fenêtre
// qui suit le choix propose « Relancer maintenant » (retour à l'accueil, interface reconstruite ; la
// session, la vente en cours côté serveur et la file d'envoi sont gardées : providers au-dessus).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';

class TailleEcranSetting extends StatefulWidget {
  /// Code administrateur (défaut : PinCodeDialog.show ; Réglages : code déjà vérifié gardé).
  final Future<bool> Function(BuildContext)? verifierPin;

  /// Couleurs du texte secondaire (charte de l'interface qui l'affiche).
  final Color? couleurAide;
  const TailleEcranSetting({super.key, this.verifierPin, this.couleurAide});

  static String detail(TailleEcran t) => switch (t) {
        TailleEcran.automatique => 'Taille définie par Android',
        TailleEcran.compact => 'Toute l\'interface 10 % plus petite',
        TailleEcran.tresCompact => 'Toute l\'interface 20 % plus petite (petits terminaux)',
      };

  @override
  State<TailleEcranSetting> createState() => _TailleEcranSettingState();
}

class _TailleEcranSettingState extends State<TailleEcranSetting> {
  Future<void> _changer(TailleEcran t) async {
    if (t == TailleEcranReglage.enregistree) return;
    final ok = await (widget.verifierPin ?? PinCodeDialog.show)(context);
    if (!ok || !mounted) return;
    await TailleEcranReglage.enregistrer(t);
    if (!mounted) return;
    setState(() {});
    final maintenant = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('taille-ecran-relancer'),
        icon: const Icon(Icons.aspect_ratio),
        title: Text('Taille de l\'écran : ${t.libelle}'),
        content: const Text('Appliquée au prochain lancement de l\'application. Vous pouvez aussi relancer l\'affichage '
            'maintenant (retour à l\'accueil ; la session et la vente en cours sont gardées).'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Plus tard')),
          FilledButton(
            key: const ValueKey('taille-ecran-relancer-maintenant'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Relancer maintenant'),
          ),
        ],
      ),
    );
    if (maintenant == true && mounted) {
      // Retour au premier écran puis interface reconstruite à la nouvelle taille (le navigateur, à clé
      // globale, est conservé).
      Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
      TailleEcranReglage.appliquerMaintenant();
    }
  }

  @override
  Widget build(BuildContext context) {
    final aide = widget.couleurAide ?? Theme.of(context).hintColor;
    final choisie = TailleEcranReglage.enregistree;
    return Column(
      key: const ValueKey('taille-ecran'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(Icons.aspect_ratio),
          title: Text('Taille de l\'écran', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('Code administrateur demandé'),
          trailing: Icon(Icons.lock_outline, size: 18),
        ),
        for (final t in TailleEcran.values)
          RadioListTile<TailleEcran>(
            key: ValueKey('taille-ecran-${t.name}'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: t,
            groupValue: choisie,
            onChanged: (v) {
              if (v != null) _changer(v);
            },
            title: Text(t.libelle),
            subtitle: Text(TailleEcranSetting.detail(t)),
          ),
        // Automatique sur un petit écran (Sunmi V2s, V3…) : Compact appliqué d'office.
        if (choisie == TailleEcran.automatique && TailleEcranReglage.compactAutomatique(context))
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 2),
            child: Text('Automatique (Compact appliqué sur cet écran)',
                key: ValueKey('taille-ecran-auto-compact'), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
          child: Text(
            TailleEcranReglage.enAttente
                ? 'Choix enregistré : appliqué au prochain lancement.'
                : 'Pour les petits écrans (Sunmi V2s 5,45″, V3) : Compact et Très compact réduisent toute l\'interface. '
                    'Le ticket imprimé n\'est pas concerné.',
            key: const ValueKey('taille-ecran-aide'),
            style: TextStyle(fontSize: 12.5, color: TailleEcranReglage.enAttente ? const Color(0xFF8A5300) : aide),
          ),
        ),
      ],
    );
  }
}
