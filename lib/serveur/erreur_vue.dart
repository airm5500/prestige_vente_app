// lib/serveur/erreur_vue.dart
// Affichage commun des erreurs serveur des modules Réserve, Analyse posologie et Fiche client :
// un message distinct par cause (serveur injoignable, session expirée, refus métier, erreur du serveur)
// et toujours une sortie (Réessayer, Se reconnecter) : jamais de chargement sans fin.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Message d'une erreur quelconque (les erreurs serveur ont déjà un texte en français).
String messageErreur(Object e) => e is ErreurPrestige ? e.message : 'Erreur inattendue : $e';

/// Titre court selon la cause.
String titreErreur(Object e) => switch (e) {
      ConnexionSecuriseeRefusee(:final nature) => nature.titre,
      ServeurIndisponible() => MessagesServeur.titreIndisponible,
      ServeurInjoignable() => MessagesServeur.titreInjoignable,
      SessionExpiree() => 'Session expirée',
      RefusMetier() => 'Refusé par Prestige',
      ErreurHttp(droitManquant: true) => 'Droit manquant',
      ErreurHttp() => 'Erreur du serveur',
      _ => 'Erreur',
    };

IconData iconeErreur(Object e) => switch (e) {
      ConnexionSecuriseeRefusee() => Icons.gpp_bad_outlined,
      ServeurIndisponible() => Icons.hourglass_top,
      ServeurInjoignable() => Icons.cloud_off,
      SessionExpiree() => Icons.lock_clock,
      RefusMetier() => Icons.block,
      ErreurHttp(droitManquant: true) => Icons.block,
      _ => Icons.error_outline,
    };

/// Même parcours que « Se déconnecter » de l'accueil : session fermée, écran de connexion.
Future<void> seReconnecter(BuildContext context) async {
  try {
    await Provider.of<AuthProvider>(context, listen: false).logout();
  } catch (_) {}
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
}

/// Bloc d'erreur centré (chargement d'un écran).
class ErreurVue extends StatelessWidget {
  final Object erreur;
  final VoidCallback? onReessayer;
  const ErreurVue({super.key, required this.erreur, this.onReessayer});

  @override
  Widget build(BuildContext context) {
    final session = erreur is SessionExpiree;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(iconeErreur(erreur), size: 48, color: session ? Pal.amber : Colors.red.shade400),
          const SizedBox(height: 12),
          Text(titreErreur(erreur), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Pal.ink)),
          const SizedBox(height: 8),
          Text(messageErreur(erreur), textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted)),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
            if (onReessayer != null)
              OutlinedButton.icon(style: outlineButton, onPressed: onReessayer, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
            if (session)
              ElevatedButton.icon(
                  style: navyButton, onPressed: () => seReconnecter(context), icon: const Icon(Icons.login), label: const Text('Se reconnecter')),
          ]),
        ]),
      ),
    );
  }
}

/// Bandeau d'erreur compact (action refusée, liste non rechargée…).
class BandeauErreur extends StatelessWidget {
  final Object erreur;
  final VoidCallback? onReessayer;
  final VoidCallback? onFermer;
  const BandeauErreur({super.key, required this.erreur, this.onReessayer, this.onFermer});

  @override
  Widget build(BuildContext context) {
    final session = erreur is SessionExpiree;
    final metier = erreur is RefusMetier;
    final fond = metier ? const Color(0xFFFFF4E5) : const Color(0xFFFDECEC);
    final encre = metier ? const Color(0xFF8A5300) : const Color(0xFF9B1C1C);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(iconeErreur(erreur), color: encre, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(messageErreur(erreur), style: TextStyle(color: encre, fontSize: 13))),
        if (session) TextButton(onPressed: () => seReconnecter(context), child: const Text('Se reconnecter')),
        if (!session && onReessayer != null) TextButton(onPressed: onReessayer, child: const Text('Réessayer')),
        if (onFermer != null) IconButton(tooltip: 'Fermer', onPressed: onFermer, icon: Icon(Icons.close, size: 18, color: encre)),
      ]),
    );
  }
}

/// Message bref (SnackBar) d'une erreur d'action.
void afficherErreur(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(messageErreur(e)),
    backgroundColor: e is RefusMetier ? const Color(0xFF8A5300) : const Color(0xFFB91C1C),
    duration: const Duration(seconds: 5),
    action: e is SessionExpiree ? SnackBarAction(label: 'Se reconnecter', textColor: Colors.white, onPressed: () => seReconnecter(context)) : null,
  ));
}
