// lib/connexion/assistance.dart
// Numéro d'assistance (défaut 0708080068, modifiable par l'administrateur dans Paramètres › Sécurité) :
// affichage lisible, contrôle de saisie, bouton « Appeler l'assistance » (composeur du téléphone via
// url_launcher, lien tel:) ; repli si aucun composeur : le numéro est copié.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/connexion/connexion_commun.dart';
import 'package:prestige_vente_app/connexion/connexion_reglages.dart';
import 'package:url_launcher/url_launcher.dart';

class Assistance {
  Assistance._();

  /// Ouverture du composeur (remplaçable dans les tests). Renvoie `false` si impossible.
  static Future<bool> Function(Uri) lanceur = _lancer;

  static Future<bool> _lancer(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Numéro courant (réglage de l'appareil).
  static String get numero => ConnexionReglages.courant.value.assistance;

  /// Chiffres seuls (et « + » initial).
  static String nettoyer(String v) {
    final t = v.trim();
    final chiffres = t.replaceAll(RegExp(r'[^0-9]'), '');
    return t.startsWith('+') ? '+$chiffres' : chiffres;
  }

  /// Motif de refus d'un numéro saisi, ou `null`.
  static String? refus(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Saisissez un numéro';
    if (!RegExp(r'^\+?[0-9 .\-]+$').hasMatch(t)) return 'Chiffres, espaces et « + » seulement';
    final n = t.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (n < 8 || n > 15) return 'De 8 à 15 chiffres';
    return null;
  }

  /// « 0708080068 » → « 07 08 08 00 68 ».
  static String formater(String v) {
    final n = nettoyer(v);
    if (n.startsWith('+')) return n;
    if (n.length.isEven && n.length <= 12) {
      return [for (var i = 0; i < n.length; i += 2) n.substring(i, i + 2)].join(' ');
    }
    return n;
  }

  /// Ouvre le composeur ; repli : copie du numéro et message.
  static Future<void> appeler(BuildContext context, {String? numeroAppele}) async {
    final n = nettoyer(numeroAppele ?? numero);
    final ok = await lanceur(Uri(scheme: 'tel', path: n));
    if (ok || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: n));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Appel impossible sur cet appareil : numéro ${formater(n)} copié.')));
  }
}

/// Bouton « Appeler l'assistance » (contour, 48 px minimum).
class BoutonAssistance extends StatelessWidget {
  final Color couleur;
  final String libelle;
  final bool plein;
  const BoutonAssistance({super.key, required this.couleur, this.libelle = 'Appeler l\'assistance', this.plein = true});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ConnexionConfig>(
        valueListenable: ConnexionReglages.courant,
        builder: (context, c, _) => Semantics(
          button: true,
          label: '$libelle, ${Assistance.formater(c.assistance)}',
          excludeSemantics: true,
          child: SizedBox(
            height: plein ? 52 : 48,
            width: plein ? double.infinity : null,
            child: OutlinedButton.icon(
              key: const Key('appeler_assistance'),
              style: OutlinedButton.styleFrom(
                foregroundColor: couleur,
                side: BorderSide(color: couleur.withValues(alpha: 0.6)),
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: policeBouton(context, FontWeight.w700),
              ),
              onPressed: () => Assistance.appeler(context),
              icon: const Icon(Icons.call_outlined),
              label: Text(libelle, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      );
}
