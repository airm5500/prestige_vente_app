// lib/connexion/session_expiree_app.dart
// Branchement de l'intercepteur de session (lib/api/session_expiree.dart) sur l'application :
// utilisateur connecté (AuthProvider), reconnexion silencieuse (« Rester connecté » + mot de passe dans le
// stockage sûr), retour à l'écran de connexion par le navigateur global (HorsLigne.navigatorKey) avec
// « Votre session a expiré, reconnectez-vous », journal du terminal (type connexion, jamais de secret).
// Les files hors ligne (ventes HL, stock, pointage, support) ne sont pas touchées.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/session_expiree.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/screens/auth/login_screen.dart';

void brancherSessionExpiree(AuthProvider auth, {SessionExpiree? session, GlobalKey<NavigatorState>? navigateur, Widget Function(String message)? ecranConnexion}) {
  final s = session ?? SessionExpiree.instance;
  s.connecte = () => auth.status == AuthStatus.Authenticated;
  s.reconnecter = auth.reconnexionSilencieuse;
  s.versConnexion = (message) {
    auth.sessionExpiree();
    final nav = (navigateur ?? HorsLigne.navigatorKey).currentState;
    nav?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => (ecranConnexion ?? (m) => LoginScreen(message: m))(message)),
      (_) => false,
    );
  };
  s.journal = (action, {required ok, motif = ''}) {
    JournalTerminal.instance.noter(
      type: TypeJournal.connexion,
      action: action,
      resultat: ok ? ResultatJournal.ok : ResultatJournal.refus,
      motif: motif,
    );
  };
}
