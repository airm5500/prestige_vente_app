// lib/horsligne/connexion_toasts.dart
// Messages globaux de connexion (placés par MaterialApp.builder, sous le ScaffoldMessenger) :
// - perte de la connexion (en ligne → injoignable / hors ligne) : message ROUGE
//   « Connexion au serveur perdue » ;
// - retour (le serveur répond de nouveau → en ligne) : message VERT « De nouveau en ligne ».
// Rien au démarrage ; rien quand l'utilisateur passe lui-même hors ligne (interrupteur des Réglages).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';

class ConnexionToasts extends StatefulWidget {
  final Widget child;

  /// Instance utilisée (tests) ; sinon [HorsLigne.instance].
  final HorsLigne? horsLigne;

  /// Messager à utiliser ; sinon celui de MaterialApp (ScaffoldMessenger.maybeOf).
  final GlobalKey<ScaffoldMessengerState>? messengerKey;
  final Duration duree;
  const ConnexionToasts({super.key, required this.child, this.horsLigne, this.messengerKey, this.duree = const Duration(seconds: 4)});

  static const perteTexte = 'Connexion au serveur perdue';
  static const retourTexte = 'De nouveau en ligne';

  @override
  State<ConnexionToasts> createState() => _ConnexionToastsState();
}

class _ConnexionToastsState extends State<ConnexionToasts> {
  late final ServerMonitor _monitor = (widget.horsLigne ?? HorsLigne.instance).monitor;
  late EtatServeur _etat;
  DateTime? _retourVu;

  /// Une perte a été annoncée (le retour n'est annoncé qu'après une perte).
  bool _perteAnnoncee = false;

  @override
  void initState() {
    super.initState();
    // État de départ : aucun message au démarrage.
    _etat = _monitor.etat;
    _retourVu = _monitor.retourAt;
    _monitor.addListener(_onMonitor);
  }

  @override
  void dispose() {
    _monitor.removeListener(_onMonitor);
    super.dispose();
  }

  void _onMonitor() {
    if (!mounted) return;
    final avant = _etat;
    final e = _monitor.etat;
    _etat = e;
    final r = _monitor.retourAt;
    if (avant == EtatServeur.enLigne && e != EtatServeur.enLigne) {
      // Passage hors ligne choisi par l'utilisateur : ce n'est pas une perte.
      if (e == EtatServeur.horsLigne && _monitor.raison == RaisonHorsLigne.manuel) return;
      _perteAnnoncee = true;
      _montrer(ConnexionToasts.perteTexte, const Color(0xFFB91C1C), Icons.cloud_off, const Key('toast_connexion_perdue'));
    } else if (e == EtatServeur.enLigne && avant != EtatServeur.enLigne && r != null && r != _retourVu) {
      _retourVu = r;
      if (!_perteAnnoncee) return;
      _perteAnnoncee = false;
      _montrer(ConnexionToasts.retourTexte, const Color(0xFF15803D), Icons.cloud_done, const Key('toast_de_nouveau_en_ligne'));
    } else if (e == EtatServeur.enLigne) {
      // Retour en ligne demandé (interrupteur) : plus de perte en cours.
      _perteAnnoncee = false;
    }
  }

  void _montrer(String texte, Color couleur, IconData icon, Key key) {
    final m = widget.messengerKey?.currentState ?? ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      key: key,
      backgroundColor: couleur,
      behavior: SnackBarBehavior.floating,
      duration: widget.duree,
      content: Row(children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(texte, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
