// lib/prestigepointage/controleur_borne.dart
// Prestige Pointage : état de la borne et branchement du terminal de pointage (lib/rh) sur le client signé.
//  - identité lue dans le stockage sécurisé au lancement ; sans identité → enrôlement (pointage_app.dart) ;
//  - terminal : PointageRh avec le client signé (ClientBorne) à la place de la session, file persistante (SQLite),
//    identification (QR / 1D / NFC / empreinte), photo de contrôle ;
//  - copie des employés relue toutes les 15 min ; vérification du serveur toutes les minutes tant qu'il ne répond pas
//    normalement ; retour en ligne → file des pointages envoyée SANS confirmation (borne sans administrateur présent),
//    puis les photos ;
//  - pointages en attente depuis plus de 60 h : avertissement (le serveur refuse au-delà de 72 h).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/prestigepointage/client_borne.dart';
import 'package:prestige_vente_app/prestigepointage/identite_borne.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/rh/rh_store.dart';

class ControleurBorne extends ChangeNotifier {
  final CoffreBorne coffre;
  final RhStore store;
  final IdentificationEmploye identification;
  final PhotoControle? photos;
  final ClientBorne Function(IdentiteBorne) _client;
  final DateTime Function() maintenant;

  /// Intervalles (remplaçables pour les tests).
  Duration intervalleEmployes;
  Duration intervalleVerification;

  /// Âge au-delà duquel un pointage en attente est signalé (le serveur refuse au-delà de 72 h).
  static const ageAlerte = Duration(hours: 60);
  static const ageMaximal = Duration(hours: 72);

  ControleurBorne({
    required this.coffre,
    required this.store,
    IdentificationEmploye? identification,
    this.photos,
    ClientBorne Function(IdentiteBorne)? client,
    DateTime Function()? maintenant,
    this.intervalleEmployes = const Duration(minutes: 15),
    this.intervalleVerification = const Duration(minutes: 1),
  })  : identification = identification ?? IdentificationEmploye(),
        _client = client ?? ((i) => ClientBorne(i)),
        maintenant = maintenant ?? DateTime.now;

  IdentiteBorne? _identite;
  ClientBorne? _cl;
  PointageRh? _rh;
  bool _charge = false;

  IdentiteBorne? get identite => _identite;
  ClientBorne? get client => _cl;
  PointageRh? get rh => _rh;
  bool get charge => _charge;
  bool get enrolee => _identite != null;

  Timer? _tEmployes, _tVerif;

  Future<void> charger() async {
    final i = await coffre.lire();
    _brancher(i);
    _charge = true;
    notifyListeners();
    if (i != null) unawaited(verifier());
  }

  /// Nouvelle identité (enrôlement, réenrôlement) : gardée dans le coffre, terminal rebranché. La file des
  /// pointages est conservée (même appareil) et partira avec la nouvelle identité.
  Future<void> enroler(IdentiteBorne i) async {
    await coffre.ecrire(i);
    _brancher(i);
    notifyListeners();
    unawaited(verifier());
  }

  /// Oublie l'identité (borne retirée côté web, ou changement de serveur) ; la file des pointages reste.
  Future<void> oublier() async {
    await coffre.effacer();
    _brancher(null);
    notifyListeners();
  }

  void _brancher(IdentiteBorne? i) {
    _tEmployes?.cancel();
    _tVerif?.cancel();
    _cl?.removeListener(_onClient);
    _identite = i;
    if (i == null) {
      _cl = null;
      _rh = null;
      return;
    }
    final c = _cl = _client(i)..addListener(_onClient);
    _rh = PointageRh(
      store: store,
      serveur: c,
      identification: identification,
      photos: photos,
      clock: maintenant,
      horsLigne: () => c.horsLigne,
      nomTerminal: () => i.nom,
      journal: () => JournalTerminal.instance,
    );
    _tEmployes = Timer.periodic(intervalleEmployes, (_) => unawaited(_rafraichir()));
  }

  EtatBorne? _etatAvant;

  void _onClient() {
    final c = _cl;
    if (c == null) return;
    final e = c.etat;
    final avant = _etatAvant;
    _etatAvant = e;
    if (e == EtatBorne.ok) {
      _tVerif?.cancel();
      _tVerif = null;
      if (avant != null && avant != EtatBorne.ok) unawaited(envoyerFile());
    } else if (e != EtatBorne.inconnu && _tVerif == null) {
      _tVerif = Timer.periodic(intervalleVerification, (_) => unawaited(verifier()));
    }
    notifyListeners();
  }

  /// GET moi : remet l'état à jour (et déclenche l'envoi de la file au retour en ligne).
  Future<bool> verifier() async => (await _cl?.moi()) != null;

  Future<void> _rafraichir() async {
    final r = _rh;
    if (r == null || (_cl?.horsLigne ?? true)) return;
    await r.rafraichirEmployes();
  }

  bool _envoi = false;

  /// Envoi de la file (sans confirmation) puis des photos en attente.
  Future<void> envoyerFile() async {
    final r = _rh;
    if (r == null || _envoi) return;
    _envoi = true;
    try {
      await r.chargerFile();
      if (r.enAttente > 0) await r.envoyer();
      await r.envoyerPhotos();
    } catch (_) {
    } finally {
      _envoi = false;
      notifyListeners();
    }
  }

  /// Pointages en attente depuis plus de [ageAlerte] (seront refusés par le serveur après [ageMaximal]).
  List<PointageBadge> get bientotPerimes {
    final r = _rh;
    if (r == null) return const [];
    final limite = maintenant().subtract(ageAlerte);
    return [for (final p in r.file) if (p.statut == StatutPointageBadge.enAttente && p.lu.isBefore(limite)) p];
  }

  @override
  void dispose() {
    _tEmployes?.cancel();
    _tVerif?.cancel();
    _cl?.removeListener(_onClient);
    super.dispose();
  }
}
