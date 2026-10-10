// lib/horsligne/ventes_sync.dart
// File des ventes hors ligne et envoi au serveur (étape H2).
// - Jamais d'envoi sans accord : au retour du serveur (ou « Envoyer maintenant »), une confirmation
//   liste les ventes ; celles décochées (déjà ressaisies sur le serveur) passent « ressaisie », jamais
//   envoyées. Puis UNE vente à la fois, dans l'ordre de saisie, avec les MÊMES appels que la vente en
//   ligne (VenteGateway).
// - Rapport d'anomalies persistant : chaque refus / écart (bon déjà utilisé, plafond, stock, prix,
//   caisse fermée…) y est ajouté avec le client et le(s) bon(s) concerné(s).
// - Idempotence : l'identifiant de la vente serveur est enregistré dès sa création ; avant chaque
//   ajout, le panier du serveur est relu et seuls les articles manquants sont envoyés ; une réponse
//   perdue est suivie d'une relecture (panier ou statut de la vente) : jamais de 2ᵉ vente, de 2ᵉ ligne
//   ni de 2ᵉ clôture.
// - H4 (serveur avec le patch docs/serveur/H4_client_ref.patch) : la création porte la clé client
//   `X-Client-Ref` (HL2-<id local>) ; le serveur ne crée jamais deux fois pour la même clé et une réponse
//   perdue (ou l'appli fermée pendant l'appel) est suivie d'une relecture par la clé : reprise sans anomalie.
//   Serveur sans H4 : fonctionnement ci-dessus inchangé (anomalie « vérifiez dans les préventes »).
// - Écarts (prix, stock, produit introuvable, net ≠ montant encaissé) et refus du serveur (bon,
//   plafond, caisse fermée) : la vente passe « à vérifier » avec un motif clair. Rien n'est supprimé.
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/api/models/assurance_sale_summary.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/horsligne/client_ref.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

/// Le serveur n'a pas répondu : l'envoi s'arrête, la vente reprendra à la même étape.
class _Panne implements Exception {
  final String message;
  const _Panne(this.message);
}

enum _Issue { envoyee, verifier }

class FileVentesHL extends ChangeNotifier {
  final VentesHLStore store;

  /// Accès serveur (DioVenteGateway dans l'appli, faux serveur dans les tests).
  VenteGateway? gateway;
  final DateTime Function() _clock;

  FileVentesHL({required this.store, this.gateway, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  List<VenteHorsLigne> _ventes = const [];
  bool _loaded = false;
  String? _storeError;
  bool _running = false;
  bool _again = false;
  int _index = 0;
  int _total = 0;
  String? _panne;
  DateTime? _dernierEnvoi;
  List<AnomalieHL> _anomalies = const [];
  bool _confirmation = false;
  Set<String>? _selection;

  /// Rapport d'anomalies (plus récentes en dernier).
  List<AnomalieHL> get anomalies => _anomalies;
  int get anomaliesNonTraitees => _anomalies.where((a) => !a.traitee).length;

  /// Le serveur est revenu avec des ventes en attente : confirmation à afficher (aucun envoi avant).
  bool get confirmationDemandee => _confirmation;

  /// Ventes dans l'ordre de saisie.
  List<VenteHorsLigne> get ventes => _ventes;
  bool get loaded => _loaded;
  String? get storeError => _storeError;
  bool get running => _running;

  /// « Envoi 2/5… » : rang de la vente en cours et nombre de ventes à envoyer.
  int get index => _index;
  int get total => _total;

  /// Dernière panne pendant l'envoi (serveur injoignable).
  String? get panne => _panne;
  DateTime? get dernierEnvoi => _dernierEnvoi;

  int get enAttente => _ventes.where((v) => v.aFaire).length;
  int get aVerifier => _ventes.where((v) => v.statut == StatutVenteHL.aVerifier).length;

  VenteHorsLigne? byId(String id) => _ventes.where((v) => v.id == id).firstOrNull;

  void _notify() => notifyListeners();

  Future<void> load() async {
    try {
      _ventes = await store.all();
      _anomalies = await store.anomalies();
      _storeError = null;
    } catch (e) {
      _storeError = 'File des ventes hors ligne illisible : $e';
    }
    _loaded = true;
    _notify();
  }

  Future<void> ensureLoaded() async {
    if (!_loaded) await load();
  }

  /// Numéro HL suivant (réservé dès la 1ʳᵉ ligne de la saisie).
  Future<int> reserverNumero() => store.nextNumero();

  static final _rnd = Random();

  /// Identifiant local unique.
  String nouvelId() => '${_clock().microsecondsSinceEpoch.toRadixString(36)}-${_rnd.nextInt(1 << 32).toRadixString(36)}';

  DateTime get now => _clock();

  /// Enregistre une vente saisie hors ligne (écriture immédiate sur l'appareil).
  Future<VenteHorsLigne> ajouter(VenteHorsLigne v) async {
    await ensureLoaded();
    await store.put(v);
    _replace(v);
    _notify();
    journalVenteHL(v, v.fin == FinVenteHL.especes ? 'Vente hors ligne enregistrée (encaissée en espèces)' : 'Vente hors ligne enregistrée (prévente)', encaissement: true);
    return v;
  }

  void _replace(VenteHorsLigne v) {
    final list = List.of(_ventes);
    final i = list.indexWhere((x) => x.id == v.id);
    if (i >= 0) {
      list[i] = v;
    } else {
      list.add(v);
      list.sort((a, b) => a.numero.compareTo(b.numero));
    }
    _ventes = list;
  }

  Future<VenteHorsLigne> _save(VenteHorsLigne v) async {
    final u = v.copyWith(updatedAt: _clock());
    await store.put(u);
    _replace(u);
    _notify();
    return u;
  }

  // ---------------------------------------------------------------------------
  // Actions de l'écran « Ventes hors ligne »
  // ---------------------------------------------------------------------------

  /// Ventes décochées à la confirmation : déjà ressaisies sur le serveur, jamais envoyées (gardées).
  Future<void> exclure(Iterable<String> ids) async {
    for (final id in ids) {
      final v = byId(id);
      if (v == null || !v.aFaire) continue;
      await _save(v.copyWith(statut: StatutVenteHL.ressaisie));
      journalVenteHL(v, 'Non envoyée : ressaisie sur le serveur (décochée à la confirmation)');
    }
  }

  /// L'anomalie est traitée (ou ne l'est plus).
  Future<void> marquerAnomalie(String id, bool traitee) async {
    final i = _anomalies.indexWhere((a) => a.id == id);
    if (i < 0) return;
    final a = _anomalies[i].copyWith(traitee: traitee);
    await store.putAnomalie(a);
    _anomalies = [..._anomalies]..[i] = a;
    _notify();
  }

  Future<void> _ajouterAnomalie(VenteHorsLigne v, String motif) async {
    if (_anomalies.any((a) => a.venteLocaleId == v.id && a.motif == motif && !a.traitee)) return;
    final a = AnomalieHL(
      id: nouvelId(),
      date: _clock(),
      venteLocaleId: v.id,
      numero: v.numero,
      type: v.type,
      client: v.clientNom,
      bons: v.tps.map((t) => t.numBon).where((b) => b.isNotEmpty).join(', '),
      motif: motif,
      nature: AnomalieHL.natureDe(motif),
    );
    await store.putAnomalie(a);
    _anomalies = [..._anomalies, a];
  }

  /// « Renvoyer » : l'écart affiché est accepté, la vente repart (à la même étape).
  Future<void> renvoyer(String id) async {
    final v = byId(id);
    if (v == null || v.statut == StatutVenteHL.envoyee) return;
    final m = v.motif;
    await _save(v.copyWith(
      statut: v.venteId == null ? StatutVenteHL.enAttente : StatutVenteHL.envoiEnCours,
      acceptes: [...v.acceptes, if (m != null && !v.acceptes.contains(m)) m],
    ));
    journalVenteHL(v, 'Renvoi demandé (écart accepté)', motif: m ?? '');
    await envoyer(ids: [id]);
  }

  /// « Marquer comme traitée » : la vente reste dans la liste, n'est plus envoyée.
  Future<void> marquerTraitee(String id) async {
    final v = byId(id);
    if (v == null || v.statut == StatutVenteHL.envoyee) return;
    await _save(v.copyWith(statut: StatutVenteHL.traitee));
    journalVenteHL(v, 'Marquée comme traitée (régularisée sur le serveur)');
    for (final a in _anomalies.where((a) => a.venteLocaleId == id && !a.traitee).toList()) {
      await marquerAnomalie(a.id, true);
    }
  }

  /// Suppression (confirmée par l'utilisateur) : seulement si rien n'existe sur le serveur.
  Future<bool> supprimer(String id) async {
    final v = byId(id);
    if (v == null || !v.supprimable || (_running && v.statut == StatutVenteHL.envoiEnCours)) return false;
    await store.remove(id);
    _ventes = _ventes.where((x) => x.id != id).toList();
    _notify();
    journalVenteHL(v, 'Vente hors ligne supprimée (jamais envoyée)');
    return true;
  }

  /// Purge de l'historique : ventes TERMINÉES (envoyées, traitées, ressaisies) antérieures à [avant].
  /// Les ventes en attente ou en anomalie ne sont jamais effacées.
  Future<int> purger(DateTime avant) async {
    await ensureLoaded();
    var n = 0;
    for (final v in List.of(_ventes)) {
      final fini = v.statut == StatutVenteHL.envoyee || v.statut == StatutVenteHL.traitee || v.statut == StatutVenteHL.ressaisie;
      if (!fini || !(v.envoyeeAt ?? v.updatedAt).isBefore(avant)) continue;
      try {
        await store.remove(v.id);
        _ventes = _ventes.where((x) => x.id != v.id).toList();
        n++;
      } catch (_) {}
    }
    if (n > 0) _notify();
    return n;
  }

  // ---------------------------------------------------------------------------
  // Envoi
  // ---------------------------------------------------------------------------

  /// Retour du serveur / connexion : s'il y a des ventes à envoyer, une confirmation est demandée
  /// (rien n'est envoyé sans accord).
  Future<void> demanderConfirmation() async {
    if (gateway == null) return;
    await ensureLoaded();
    if (enAttente == 0 || _running || _confirmation) return;
    _confirmation = true;
    _notify();
  }

  /// La confirmation a été affichée (envoyée, reportée ou fermée).
  void confirmationVue() {
    if (!_confirmation) return;
    _confirmation = false;
    _notify();
  }

  /// Envoie les ventes en attente choisies ([ids] ; null = toutes), une à la fois, dans l'ordre.
  /// Une panne arrête l'envoi (la vente reprendra à la même étape) ; une anomalie n'arrête pas les suivantes.
  Future<void> envoyer({Iterable<String>? ids}) async {
    _confirmation = false;
    if (_running) {
      if (ids != null && _selection != null) _selection = {..._selection!, ...ids};
      if (ids == null) _selection = null;
      _again = true;
      return;
    }
    _selection = ids?.toSet();
    final gw = gateway;
    if (gw == null) {
      _panne = 'Serveur non configuré : connectez-vous.';
      _notify();
      return;
    }
    _running = true;
    _panne = null;
    _notify();
    try {
      await ensureLoaded();
      do {
        _again = false;
        final sel = _selection;
        final todo = _ventes.where((v) => v.aFaire && (sel == null || sel.contains(v.id))).map((v) => v.id).toList();
        _total = todo.length;
        _index = 0;
        for (final id in todo) {
          final v = byId(id);
          if (v == null || !v.aFaire) continue;
          _index++;
          _notify();
          try {
            await _envoyerUne(gw, v);
          } on _Panne catch (e) {
            journalVenteHL(byId(id) ?? v, 'Envoi interrompu', resultat: ResultatJournal.echecReseau, motif: e.message, source: SourceJournal.fileHL);
            _panne = e.message;
            _again = false;
            break;
          }
        }
      } while (_again);
    } catch (e) {
      _panne = 'Envoi interrompu : $e';
    } finally {
      _running = false;
      _selection = null;
      _index = 0;
      _total = 0;
      _dernierEnvoi = _clock();
      _notify();
    }
  }

  static String _f(int v) => Constants.formatNumber(v);
  static String _clean(String m) => m.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _motifRefus(VenteRefused<dynamic> r, {String? produit}) {
    if (r.caisseFermee) return 'Caisse fermée : ouvrez la caisse puis « Renvoyer ».';
    final m = _clean(r.message);
    return produit == null ? 'Refusé par le serveur : $m' : 'Refusé par le serveur ($produit) : $m';
  }

  Never _stop(VenteResult<dynamic> r) => throw _Panne(_clean(r.message ?? 'Serveur injoignable.'));

  Future<_Issue> _envoyerUne(VenteGateway gw, VenteHorsLigne v0) async {
    var v = await _save(v0.copyWith(
      statut: StatutVenteHL.envoiEnCours,
      etape: v0.etape ?? (v0.venteId == null ? EtapeHL.creation : EtapeHL.articles),
      tentatives: v0.tentatives + 1,
      motif: null,
    ));
    Future<_Issue> verifier(String motif) async {
      v = await _save(v.copyWith(statut: StatutVenteHL.aVerifier, motif: motif));
      await _ajouterAnomalie(v, motif);
      journalVenteHL(v, 'Anomalie à l\'envoi', resultat: ResultatJournal.refus, motif: motif, source: SourceJournal.fileHL);
      _notify();
      return _Issue.verifier;
    }

    // 1. Création de la vente (1ʳᵉ ligne) — l'identifiant est enregistré dès la réponse.
    // H4 : si le serveur gère la clé client, la création porte `X-Client-Ref` (jamais créée deux fois) et une
    // réponse perdue est suivie d'une relecture par la clé ; sinon, fonctionnement d'origine (anomalie).
    final h4 = gw is ClientRefGateway ? gw as ClientRefGateway : null;
    final cle = cleClientVente(v.id);
    // Vente relue par sa clé : true = trouvée (identifiant enregistré), false = jamais créée ; panne = arrêt.
    Future<bool> relire() async {
      final lu = await h4!.lireClientRef(cle);
      if (lu is! VenteOk<ClientRefInfo?>) _stop(lu);
      final info = lu.value;
      if (info == null) return false;
      v = await _save(v.copyWith(venteId: info.id, reference: info.reference ?? v.reference, etape: EtapeHL.articles));
      return true;
    }

    if (v.venteId == null && v.etape == EtapeHL.creationEnvoyeeRef) {
      if (h4 != null && await h4.clientRefSupporte()) {
        // Réponse de la création jamais reçue (appli fermée, panne) : relire au lieu de deviner.
        if (!await relire()) v = await _save(v.copyWith(etape: EtapeHL.creation));
      } else {
        // Le serveur ne gère plus la clé : prudence d'origine.
        v = await _save(v.copyWith(etape: EtapeHL.creationEnvoyee));
      }
    }
    if (v.venteId == null) {
      final interrompu = 'Envoi interrompu pendant la création de la vente ${v.numeroLabel} (${_f(v.totalEstime)} F) : '
          'vérifiez dans les préventes du serveur qu\'elle n\'existe pas, puis « Renvoyer ».';
      if (v.etape == EtapeHL.creationEnvoyee && !v.acceptes.contains(interrompu)) return verifier(interrompu);
      final first = v.lignes.where((l) => !l.serveur).firstOrNull;
      if (first == null) return verifier('Vente sans article : rien à envoyer.');
      final conflit = await _controle(gw, v, first, first.qte);
      if (conflit != null) return verifier(conflit);
      final ref = h4 != null && await h4.clientRefSupporte() ? cle : null;
      v = await _save(v.copyWith(etape: ref != null ? EtapeHL.creationEnvoyeeRef : EtapeHL.creationEnvoyee));
      final r = await _addItem(ref != null ? h4!.avecClientRef(ref) : gw, v, first.produitId, first.qte, first.prix, null);
      switch (r) {
        case VenteOk(:final value):
          v = await _save(v.copyWith(venteId: value, etape: EtapeHL.articles));
        case VenteRefused():
          v = await _save(v.copyWith(etape: EtapeHL.creation));
          return verifier(_motifRefus(r, produit: first.nom));
        case VenteFailed(:final maybeApplied):
          if (maybeApplied && ref != null) {
            // H4 : réponse perdue → la vente est relue par sa clé (reprise sans doublon). Relecture impossible :
            // l'envoi s'arrête, l'étape reste « envoyée avec clé » et la relecture est refaite au prochain envoi.
            if (!await relire()) {
              // Clé inconnue du serveur : la vente n'a pas été créée, elle sera renvoyée (même clé).
              v = await _save(v.copyWith(etape: EtapeHL.creation, statut: StatutVenteHL.enAttente));
              _stop(r);
            }
          } else {
            if (maybeApplied) {
              return verifier('Réponse perdue pendant la création de la vente ${v.numeroLabel} (${_f(v.totalEstime)} F) : '
                  'vérifiez dans les préventes du serveur qu\'elle n\'existe pas, puis « Renvoyer ».');
            }
            v = await _save(v.copyWith(etape: EtapeHL.creation, statut: StatutVenteHL.enAttente));
            _stop(r);
          }
      }
    }
    final venteId = v.venteId!;
    if (v.etape == EtapeHL.creation || v.etape == EtapeHL.creationEnvoyee || v.etape == EtapeHL.creationEnvoyeeRef) {
      v = await _save(v.copyWith(etape: EtapeHL.articles));
    }

    // 2. Articles : relire le panier du serveur, n'envoyer que ce qui manque.
    if (v.etape == EtapeHL.articles) {
      final voulu = <String, int>{};
      final ligneDe = <String, LigneHL>{};
      for (final l in v.lignes) {
        voulu[l.produitId] = (voulu[l.produitId] ?? 0) + l.qte;
        ligneDe.putIfAbsent(l.produitId, () => l);
      }
      for (var tour = 0;; tour++) {
        if (tour > v.lignes.length * 3 + 5) {
          return verifier('Articles non confirmés par le serveur après plusieurs essais : vérifiez la vente ${v.reference ?? ''}.'.trim());
        }
        final det = await gw.saleDetails(venteId);
        if (det is VenteRefused<List<SaleItemDetail>>) return verifier(_motifRefus(det));
        if (det is! VenteOk<List<SaleItemDetail>>) _stop(det);
        final items = det.value;
        final ref = items.where((i) => i.strREF.isNotEmpty).firstOrNull?.strREF;
        if (ref != null && ref != v.reference) v = await _save(v.copyWith(reference: ref));
        final serveur = <String, int>{};
        for (final i in items) {
          serveur[i.lgFAMILLEID] = (serveur[i.lgFAMILLEID] ?? 0) + i.intQUANTITY;
        }
        for (final e in serveur.entries) {
          final local = voulu[e.key] ?? 0;
          if (e.value > local) {
            final nom = items.firstWhere((i) => i.lgFAMILLEID == e.key).strNAME;
            final m = 'Le serveur a plus d\'articles que la vente saisie : $nom (serveur ${e.value}, saisi $local).';
            if (!v.acceptes.contains(m)) return verifier(m);
          }
        }
        final manque = voulu.entries.where((e) => e.value > (serveur[e.key] ?? 0)).firstOrNull;
        if (manque == null) break;
        final ligne = ligneDe[manque.key]!;
        final qte = manque.value - (serveur[manque.key] ?? 0);
        final conflit = await _controle(gw, v, ligne, qte);
        if (conflit != null) return verifier(conflit);
        final r = await _addItem(gw, v, ligne.produitId, qte, ligne.prix, venteId);
        if (r is VenteRefused<String>) return verifier(_motifRefus(r, produit: ligne.nom));
        if (r is VenteFailed<String> && !r.maybeApplied) _stop(r);
        // Réussi ou réponse perdue : le panier est relu au tour suivant.
      }
      v = await _save(v.copyWith(etape: EtapeHL.fin));
    }

    // 3. Fin : net du serveur, puis prévente ou clôture espèces (statut relu si un envoi a pu partir).
    final especes = v.fin == FinVenteHL.especes && v.type == TypeVenteHL.comptant;
    if (v.etape == EtapeHL.finEnvoyee) {
      final s = await _statut(gw, venteId);
      if (s == 'is_Closed' || (!especes && s == 'is_Process')) return _envoyee(v, (x) => v = x);
      if (s == null) throw const _Panne('Statut de la vente non relu.');
    }
    SaleSummary? summary;
    if (v.type == TypeVenteHL.comptant) {
      final net = await gw.netVno(venteId);
      if (net is VenteRefused<SaleSummary>) return verifier(_motifRefus(net));
      if (net is! VenteOk<SaleSummary>) _stop(net);
      summary = net.value;
      if (summary.reference.isNotEmpty && summary.reference != v.reference) v = await _save(v.copyWith(reference: summary.reference));
    } else {
      final net = await gw.netAssurance(venteId: venteId, tierspayants: _tps(v));
      if (net is VenteRefused<AssuranceSaleSummary>) return verifier(_motifRefus(net));
      if (net is! VenteOk<AssuranceSaleSummary>) _stop(net);
    }
    if (especes) {
      final netServeur = summary!.montantNet;
      if (netServeur != v.netEstime) {
        final m = 'Net du serveur ${_f(netServeur)} F ≠ montant encaissé ${_f(v.netEstime)} F : vente non clôturée. '
            '« Renvoyer » pour clôturer au net du serveur.';
        if (!v.acceptes.contains(m)) return verifier(m);
      }
      // Comme en ligne : client = nom du mode, résultat non bloquant.
      await gw.updateClient(venteId, v.modeNom.toLowerCase().replaceAll(' ', '').replaceAll('é', 'e'));
      v = await _save(v.copyWith(etape: EtapeHL.finEnvoyee));
      final recu = max(v.montantRecu ?? netServeur, netServeur);
      final r = await gw.cloturerVno(
        venteId: venteId,
        summary: summary,
        typeReglementId: '1',
        clientId: v.modeNom.toLowerCase().replaceAll(' ', '').replaceAll('é', 'e'),
        userVendeurId: v.userId,
        montantRecu: recu,
        montantRemis: recu - netServeur,
      );
      if (r.isOk) return _envoyee(v, (x) => v = x);
      if (r is VenteRefused<Map<String, dynamic>>) {
        if (r.dejaCloturee) return _envoyee(v, (x) => v = x);
        v = await _save(v.copyWith(etape: EtapeHL.fin));
        return verifier(_motifRefus(r));
      }
      if (!r.uncertain) {
        v = await _save(v.copyWith(etape: EtapeHL.fin));
        _stop(r);
      }
      // Réponse perdue : relire la vente, jamais de seconde clôture à l'aveugle.
      if (await _statut(gw, venteId) == 'is_Closed') return _envoyee(v, (x) => v = x);
      _stop(r);
    }
    v = await _save(v.copyWith(etape: EtapeHL.finEnvoyee));
    final r = await gw.terminerPrevente(venteId);
    if (r.isOk) return _envoyee(v, (x) => v = x);
    if (r is VenteRefused<void>) {
      v = await _save(v.copyWith(etape: EtapeHL.fin));
      return verifier(_motifRefus(r));
    }
    if (!r.uncertain) {
      v = await _save(v.copyWith(etape: EtapeHL.fin));
      _stop(r);
    }
    final s = await _statut(gw, venteId);
    if (s == 'is_Process' || s == 'is_Closed') return _envoyee(v, (x) => v = x);
    _stop(r);
  }

  Future<_Issue> _envoyee(VenteHorsLigne v, void Function(VenteHorsLigne) set) async {
    final u = await _save(v.copyWith(statut: StatutVenteHL.envoyee, etape: null, motif: null, envoyeeAt: _clock()));
    journalVenteHL(u, 'Vente hors ligne envoyée au serveur', source: SourceJournal.fileHL);
    set(u);
    return _Issue.envoyee;
  }

  /// Statut lu sur /ventestats/{id} (null si non relu).
  Future<String?> _statut(VenteGateway gw, String venteId) async {
    final r = await gw.fullSale(venteId);
    if (r is! VenteOk<Map<String, dynamic>>) return null;
    for (final k in const ['strSTATUT', 'statut', 'str_STATUT', 'status']) {
      final s = r.value[k];
      if (s is String && s.isNotEmpty) return s;
    }
    return null;
  }

  List<VenteTp> _tps(VenteHorsLigne v) => [for (final t in v.tps) (compteTp: t.compteTp, numBon: t.numBon, taux: t.taux)];

  Future<VenteResult<String>> _addItem(VenteGateway gw, VenteHorsLigne v, String produitId, int qte, int prix, String? venteId) {
    if (v.type == TypeVenteHL.comptant) {
      return gw.addItemVno(produitId: produitId, qte: qte, itemPu: prix, venteId: venteId, prevente: true);
    }
    return gw.addItemAssurance(
      produitId: produitId,
      qte: qte,
      itemPu: prix,
      clientId: '${v.client?['lgCLIENTID'] ?? ''}',
      ayantDroitId: '${v.ayantDroit?['lgAYANTSDROITSID'] ?? v.client?['lgCLIENTID'] ?? ''}',
      natureVenteId: '1',
      typeVenteId: v.type == TypeVenteHL.carnet ? '3' : '2',
      userVendeurId: v.userId,
      tierspayants: _tps(v),
      venteId: venteId,
    );
  }

  /// Contrôle d'une ligne avant l'envoi (produit, prix, stock du serveur) ; renvoie le motif d'un
  /// écart non encore accepté (null = rien à signaler).
  Future<String?> _controle(VenteGateway gw, VenteHorsLigne v, LigneHL l, int qte) async {
    if (l.serveur) return null;
    Future<ProductSearchResultLike?> chercher(String q) async {
      if (q.trim().isEmpty) return null;
      final r = await gw.searchProductsPage(q, 0, ProductLookup.pageSize);
      if (r is VenteFailed<ProductPage>) _stop(r);
      final items = r.valueOrNull?.items ?? const [];
      final p = items.where((p) => p.lgFAMILLEID == l.produitId).firstOrNull;
      return p == null ? null : (prix: p.intPRICE, stock: p.intNUMBERAVAILABLE);
    }

    final p = await chercher(l.cip) ?? await chercher(l.nom);
    final motifs = <String>[
      if (p == null) 'Produit introuvable sur le serveur : ${l.nom}.',
      if (p != null && p.prix != l.prixCatalogue) 'Prix modifié : ${l.nom} ${_f(l.prixCatalogue)} → ${_f(p.prix)} F.',
      if (p != null && p.stock < qte) 'Stock insuffisant : ${l.nom} (stock serveur ${p.stock}, demandé $qte).',
    ];
    return motifs.where((m) => !v.acceptes.contains(m)).firstOrNull;
  }
}

typedef ProductSearchResultLike = ({int prix, int stock});
