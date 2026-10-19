// lib/connexion/changement_utilisateur.dart
// 4.5.1 — Un seul compte par session (demande du serveur du 19/10/2026, points 4 et 5) :
//
// - [EtatLocalVente.effacer] : panier en cours (ancienne interface : SaleProvider, DepotSaleProvider ; nouvelle
//   interface : écrans fermés par le retour à la connexion / à l'accueil), « vente à reprendre » mémorisée de chaque
//   menu, vendeur choisi (fournisseurs assurance / carnet recréés au changement de compte), droits en mémoire.
//   Les FILES HORS LIGNE ne sont jamais touchées (ventes, stock, pointage) : chaque vente hors ligne garde son
//   compte et n'est envoyée que sous la session de CE compte (lib/horsligne/ventes_sync.dart).
//   Appelé à la déconnexion, et à toute connexion d'un AUTRE compte que le précédent (badge, connexion rapide,
//   après une expiration).
// - [brancherChangementUtilisateur] : 409 `sessionChangee` → message du serveur, compte (GET v1/user/account) et
//   droits relus, panier du compte précédent effacé, retour à l'accueil (l'action refusée n'a pas été exécutée) ;
//   retour de l'application au premier plan → droits relus.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/utilisateur_session.dart';
import 'package:prestige_vente_app/borne/borne_launcher.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/interface_version.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/ventes/core/pending_sale_store.dart';

class EtatLocalVente {
  EtatLocalVente._();

  static final Set<void Function()> _effaceurs = {};

  /// Un fournisseur d'état de vente s'inscrit (et se désinscrit dans son dispose).
  static void inscrire(void Function() effacer) => _effaceurs.add(effacer);
  static void desinscrire(void Function() effacer) => _effaceurs.remove(effacer);

  /// Diagnostic (tests).
  static int effacements = 0;

  /// Efface l'état de vente du compte précédent (jamais les files hors ligne).
  static Future<void> effacer() async {
    effacements++;
    for (final e in List.of(_effaceurs)) {
      try {
        e();
      } catch (_) {}
    }
    await PendingSaleStore.toutEffacer();
    DroitsVente.instance.oublier();
  }
}

class _Premierplan with WidgetsBindingObserver {
  _Premierplan(this.auth);
  AuthProvider auth;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && auth.status == AuthStatus.Authenticated) auth.relireDroits();
  }
}

_Premierplan? _observateur;

/// Branché une fois par l'application (lib/main.dart, à côté de brancherSessionExpiree).
/// [accueil] : écran rouvert après un 409 (Prestige Mobile : l'accueil, ou la borne si elle est active ; PrestigePOS :
/// sa borne).
void brancherChangementUtilisateur(AuthProvider auth,
    {SessionChangee? session, GlobalKey<NavigatorState>? navigateur, Widget Function()? accueil}) {
  final s = session ?? SessionChangee.instance;
  s.traiter = (message) async {
    JournalTerminal.instance.noter(
      type: TypeJournal.connexion,
      action: 'Session changée de compte sur le serveur : rien n\'a été exécuté',
      resultat: ResultatJournal.refus,
      motif: 'HTTP 409 sessionChangee',
    );
    final nav = (navigateur ?? HorsLigne.navigatorKey).currentState;
    // Retour à l'accueil d'abord : les écrans de vente se ferment (leur panier avec eux).
    nav?.popUntil((r) => r.isFirst);
    await auth.relireSessionChangee();
    final ctx = (navigateur ?? HorsLigne.navigatorKey).currentContext;
    if (ctx != null && ctx.mounted) {
      if (auth.status == AuthStatus.Authenticated) {
        // Borne active sur cet appareil : la borne (elle reconnecte SON utilisateur), sinon l'accueil.
        nav?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => (accueil ?? () => BorneLauncher.auDemarrage ? const BorneHote() : InterfaceVersion.home())()),
            (_) => false);
      }
      final c = (navigateur ?? HorsLigne.navigatorKey).currentContext;
      if (c != null && c.mounted) {
        await showDialog<void>(
          context: c,
          builder: (d) => AlertDialog(
            key: const Key('session_changee'),
            title: const Text('Compte changé'),
            content: Text(message),
            actions: [TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('OK'))],
          ),
        );
      }
    }
  };
  if (_observateur == null) {
    _observateur = _Premierplan(auth);
    WidgetsBinding.instance.addObserver(_observateur!);
  } else {
    _observateur!.auth = auth;
  }
}
